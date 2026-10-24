# Technical Design Document: Spaces (Workspaces)

**Status:** Proposed · **Owns:** PRD-Spatial-Browser-Ladybird.md, Features 1 & 2 and the
groundwork for 3–5 · **Board review:** 2026-10-24 (advisor session)

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

**Profiles (yes over time; NO simultaneously in one process — engine edge, measured).**
Profiles are Application-level state (storage root, cookie jars, caches). Two hard facts,
both verified in this codebase rather than assumed:

1. `WebView::Application` asserts `VERIFY(!s_the)` — exactly one engine per process (this was
   the second-BrowserModel crash of the sidebar milestone).
2. A profile's storage root is fixed at Application construction (see `Profiles/default` in
   helper process argv).

Therefore: multiple profiles OVER TIME (switch the active profile, others' graphs persist in
their own stores) is app-side and supported by the model. Multiple profiles SIMULTANEOUSLY in
one process is impossible without an engine change; per-window profiles implies per-process
profiles, a heavyweight architecture decision, not a milestone. Containers (§5) were designed
to absorb the dominant profile use-case (work-vs-personal logins) inside one profile; profiles
are deferred to PRD Phase 5 class, with the schema profile-scoped from day one so their
arrival needs no data-model rework.

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

Store: SwiftData or SQLite (decision left to implementer; the schema below is the contract,
not the library). One write per mutation; app termination needs no flush.

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
| Simultaneous multi-profile assumed by a phase plan | engine boundary (§2.1) | one active profile per process, standing rule; simultaneous profiles gated on an engine probe + architecture decision, not a milestone |

---

## 8. Decision log

- 2026-10-24 — Durable-graph/ephemeral-engine split adopted as the governing principle
  (advisor session); deadlines: model split precedes any space UI.
- (pending, M5.5) — containers probe verdict.
