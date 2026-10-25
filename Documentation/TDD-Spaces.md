# Technical Design Document: Spaces (Workspaces)

**Status:** M5 implemented; M5.5 probe recorded. Current sidebar/space-settings work:
[TDD-SpaceSettings.md](TDD-SpaceSettings.md).
Original scope: spatial-browser Features 1 & 2 and groundwork for 3–5.
**Board review:** 2026-10-24 (advisor session).

Related reading order: `Documentation/Architecture.md` → `Rules.md` → `Traps.md` → this file.
The probes in `Extern/ladybird/Tests/LibWebView/TestNative*` remain the executable spec for
engine behaviour; nothing in this TDD may contradict a rule R1–R8 or S1–S6.

---

## 1. The governing principle

> **The workspace/tab graph is durable app state; the engine's knowledge of tabs is a
> disposable cache of it.**

Every mutation (create, close, retier, reorder, navigate) writes straight through to the store.
`LbTab*` handles are a render cache: evictable (unload), rehydratable (activate). This single
invariant is what turns "persistent tabs, unload workspace, crash recovery, and containers"
from four features into one policy.

---

## 2. Entities

All pure data. The model lives in `LadybirdEngine` on `@MainActor` (S2, S3: no thread hops,
ever — the rule survives this design).

```
Profile
 └── spaces: [Workspace]            (ordered; dock order)

Workspace {
    id: UUID
    name, icon: String               (emoji or SF Symbol name)
    theme: GradientSpec
    containerID: String?             (nil = default session; dormant until Milestone 5.5)
    activeTabID: TabID?              (per-space selection memory — switching restores it)
    tabOrder: [TabID]
}

TabDescriptor {                      (durable; written through on every mutation)
    id: TabID
    workspaceID: Workspace.ID?       (nil ⇒ Global Essential — lives in every space's top tier)
    tier: .essential | .pinned | .normal
    url, title, faviconRef
    scrollY: Double?                 (best-effort, captured at unload; no API for exact restore)
}

Runtime caches (never persisted, may be nil):
    tabHandles:   TabID → engine tab id (LbTabCreate result)
    sessionPool:  containerID → engine session  (lazy; Milestone 5.5+)
    thumbnails:   TabID → CGImage    (snapshot AT CAPTURE TIME — never the IOSurface; S5)
```

## 2.1 The tree scales — and where it stops

The graph nests to **Profile → Spaces → Folders → Tabs**, and everything below Profile is
purely app-side structure — the engine is never told.

**Folders (cheap; rides in the schema from day one).**
A folder is a grouping node inside a space, engine-ignorant like spaces themselves:

```
TabFolder { id, workspaceID, name, collapsed, order }
TabDescriptor { ..., folderID: TabFolder.ID? }
```

Invariant 1 survives by widening "one place" to mean `workspace + optional folder`. `folderID`
and `containerID` ship in the persistence schema from day one even while unused — adding
columns to a live store later is a migration; dormant nulls cost nothing. The schema allows
nesting depth; the UI ships single-level folders (Zen/Arc behaviour).

**Profiles (yes over time; simultaneous = gated on the SAME probe as containers).**
The first version of this section declared simultaneous profiles impossible; that was wrong,
and the correction matters. Decompose a profile into its ingredients:

| Ingredient | Needs | Verdict |
|---|---|---|
| Identity (name, avatar, spaces/tabs) | app-side store per profile | buildable |
| Own history/bookmarks/settings | app-side persistence | buildable |
| Isolated cookies/logins | named sessions with persistent jars | **the §5 containers probe** |
| Own storage directory | separate per-profile root | NOT needed as such: Chrome keeps all profiles under ONE root as subdirs; a fixed Application-level root is compatible with that layout |
| Per-profile process isolation | per-profile engine | genuinely blocked |

Two engine facts remain hard boundaries, both measured:

1. `WebView::Application` asserts `VERIFY(!s_the)` — exactly one engine per process (this was
   the second-BrowserModel crash of the sidebar milestone).
2. A profile's storage root is fixed at Application construction (see `Profiles/default` in
   helper process argv).

But profiles-as-named-sessions never need a second engine, and fact 2 permits one root with
per-session storage beneath it — which is exactly the Chrome layout. The engine already runs
multiple sessions simultaneously (normal + private coexist). So: multiple profiles OVER TIME
is fully app-side; multiple profiles SIMULTANEOUSLY reduces to the §5 probe. On a green
verdict, simultaneous profiles are buildable as containers + identity + per-profile app-side
stores, and ride Milestone 6 rather than Phase 5. On red, the same upstream-shaped patch
discussion applies as for containers. The genuinely deferred pieces are only per-profile
process/crash isolation and Chromium-style deep separation.

### Invariants

1. **A tab lives in exactly one tier, exactly one place.** Essentials are a tier, not
   "pinned everywhere": an Essential closes only from its essentials section; it does not
   appear in any space's pinned list.
2. **Any tab may be `unloaded`:** descriptor present, engine handle nil. Unload is the ONLY
   destroy besides close. Switching spaces NEVER destroys a tab (rule already shipped; stays).
3. **Containers follow workspaces; tabs follow their workspace.** A tab's session is derived,
   never set per-tab. Changing a workspace's container closes and re-creates its tabs; there is
   no live migration.
4. **Persistence is a side effect of mutation, not a save action.** There is no autosave,
   no expiry, and therefore no auto-archive — that behaviour is impossible by construction
   (Zen requirement, enforced structurally).
5. **The shim stays ignorant of spaces.** Engine tab ids are opaque u64s; grouping is
   app-side only. Fork changes are confined to container sessions (§5), additive, C11 (R2, R4).

---

## 3. Layer placement

| Concern | Layer | Notes |
|---|---|---|
| Graph, tiers, write-through persistence, session pool, unload policy | `LadybirdEngine` | model only; no AppKit needed except the existing PortWebView glue |
| 3-tier sidebar (essentials grid / pinned / normal), separator with "Close all unpinned" | `LadybirdUI` | renders the active workspace from the model |
| Space switcher dock (icon capsule, spring pill, drag reorder) | `LadybirdUI` | matched-geometry spring in a later polish pass is acceptable |
| Trackpad 2-finger space slide (`NSEvent.phase`) | `LadybirdEngine` | AppKit event seam; boundary overshoot → drawer/plus-sheet per PRD |
| Tab thumbnails | `LadybirdEngine` | CGImage at capture time; storage on disk with the descriptor |
| Space routing (Milestone 6+) | `LadybirdEngine` | resolve rule BEFORE placing a new tab; see PRD Feature 3 |

---

## 4. Persistence design

Implemented store: `GraphStore`, an atomically replaced Codable JSON graph (see §8).
The original SwiftData/SQLite proposal was not adopted. Reuse the existing store; do not
introduce a second persistence system. One write per mutation; app termination needs no flush.

Minimum tables: `Workspace`, `TabDescriptor`, plus `ProfileMeta(schemaVersion, activeSpaceID,
lastOpenTabPerSpace)`.

Restore on launch: rebuild the graph, create engine tabs LAZILY — one per restored tab is
acceptable for ≤ ~20 tabs; beyond that restore descriptors only and rehydrate on activation
(tabs open *unloaded*). This is the same code path as unload, which is the point of §1.

---

## 5. Containers (Milestone 5.5 — gated on the probe)

Per-space cookie/storage isolation. Known from the tree: storage binds to
`BrowsingSession`; `SiteBinding` is only `Unrestricted | Bound`; private windows already run
a second simultaneous session. Hypothesis: one session per containerID via additive shim
calls (`LbSessionCreate(label)` → `LbTabCreateInSession`).

**Probe protocol (run BEFORE any container UI):**

1. Create two sessions simultaneously in one process. Pages in each load and paint normally.
2. Set a cookie in session A (e.g. log in); confirm session B does not see it.
3. Quit, relaunch, confirm session A's jar persists on disk under a distinct identity.
   If private-style sessions turn out to be in-memory only, this probe FAILS containers.

Green ⇒ Milestone 6 (session pool + per-space containers UI).
Red ⇒ fork patch "persist named BrowsingSessions" evaluated as an upstream-shaped
contribution per R7; containers are announced as deferred, not faked.

---

## 6. Milestones and acceptance criteria

### M5 — Spaces, dumb-but-real (no engine changes)
- Model: `Workspace`, `TabDescriptor`, `WorkspaceManager` with write-through persistence.
- UI: 3-tier sidebar from the active workspace; space switcher dock; ⌘T/B ⌘W/B operate on the
  active space; drag between pinned/normal (retier is a mutation, persists immediately).
- **Accept:** create 2 spaces, distribute 5 tabs across tiers, quit mid-load, relaunch →
  graph restored exactly; active space restored; isolated tabs rehydrate on click without
  killing neighbours. `check-layers.sh` green; existing 11 tests still pass.

### M5.5 — Containers probe (fork, half a day)
- The §5 protocol, all three steps, answered in writing in this document's decision log.
- **Accept:** green/red verdict recorded; on green, `LbSession*` ABI additions land in the
  fork as their own commit.

### M6 — Containers + Unload + Gestures
- Session pool per containerID; per-space container picker; unload policy (manual first,
  auto-unload idle-space optional behind a setting).
- **Accept:** two spaces on different containers hold separate logins to the same site
  simultaneously, verified across a relaunch; unload of a 3-tab space reclaims its
  WebContent processes (ps-scoped to OUR bundle, per the lifecycle-milestone grep lesson);
  swipe slides between spaces 1:1 with finger.
- Scroll restore is best-effort `scrollY`; session history on rehydrate explicitly NOT
  guaranteed — no upstream API (documented, not faked).

### Deferred (PRD later phases)
Space routing rules, split view, Glance, compact mode, mesh gradients, omnibar — per the PRD
phases; none implied by this TDD.

---

## 7. Risks and the rule each one implicates

| Risk | Bearing rule | Mitigation |
|---|---|---|
| N spaces × M tabs eats RAM (WebContent per tab) | demand-driven (R3) | unload policy ships IN M6, not later; memory budget verified via ps-scope check |
| Persisted containers fail the probe (in-memory jars) | R7 fork purity | red ⇒ upstream-shaped patch discussion, never a silent fake-jar |
| Restoring >50 tabs at launch spawns 50 processes at once | none yet | lazy rehydrate-by-default at scale (§4) |
| Engine tab ids recycled after kill/reload confuse the cache | R2 opaque handles | handle map is rebuilt on rehydrate; never persisted |
| Dialog-milestone invariant (absence-or-all-four) on new sessions | audit / Traps.md | dialogs bind per TAB, not per session; switch-away answers pending first (already shipped) |
| Simultaneous multi-profile via per-profile ENGINES assumed by a phase plan | engine boundary (§2.1) | multi-engine per process is impossible (`VERIFY(!s_the)`); profiles-as-named-sessions avoids it and is gated on the containers probe |

---

## 8. Decision log

- 2026-10-24 — Durable-graph/ephemeral-engine split adopted as the governing principle
  (advisor session); deadlines: model split precedes any space UI.
- 2026-10-24 — CORRECTION: simultaneous profiles are NOT engine-blocked; they decompose into
  named sessions (§5 probe) plus app-side identity/stores, per the profile-ingredient table
  in §2.1. Only per-profile process isolation stays deferred.
- 2026-10-25 — M5 persistence uses one atomically replaced JSON graph at
  `~/Library/Application Support/LadybirdMac/spaces.json`. The graph is small, synchronous writes preserve S3, and a
  malformed/newer document is copied to `.unreadable` before fresh state can replace it.
- 2026-10-25 — M5 accepted: two spaces and five tabs across Essential/Pinned/Normal survived a graceful quit while the
  selected tab was mid-load; relaunch restored IDs, order, tiers, per-space selections, and active space exactly.
  Activating an unloaded tab added a WebContent process while both existing helper PIDs survived, proving lazy
  rehydration did not kill neighbours. Drag-retier and the native sidebar collapse toggle were also run-verified.
- 2026-10-25 — M5.5 Containers Probe: GREEN on all three questions (measured in fork probe `TestNativeContainers.cpp`,
  commit `8acb7af5e2`).
  (a) Simultaneous named sessions load and paint normally in one process (PASS: Session A painted=true, Session B painted=true).
  (b) Cookie isolation holds between simultaneous sessions (PASS: Session A contains 'token=secret_a', Session B does not).
  (c) Multiple persistent cookie databases under distinct identities survive quit/relaunch (PASS: 'Container_Work' database
      reopened into a fresh CookieJar retrieved 'work_token=work_secret').
  Architectural finding: LibWebView's low-level stores (`Database::Database`, `CookieJar`, `StorageJar`) fully support arbitrary
  distinct persisted databases in parallel. However, `BrowsingSession::create` and `Application::session_for_new_view` currently
  only branch on `IsPrivate::No` (default session) vs `IsPrivate::Yes` (in-memory transient stores). To ship per-space
  containers in M6, an upstream-shaped patch extending `Application` and `ViewImplementation` to accept a named session identifier
  (or persistent `BrowsingSession`) will be required.
