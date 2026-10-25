# TDD: Capability-backed Ava Settings

**Status:** Design reviewed and finalized; Phase 0 implementation authorized, engine features
remain blocked until their probes pass. **Review date:** 2026-10-25.
**Author:** settings-design worker, Gemini 3.8 Flash/high. **Final reviewer:** coordinator.
**Product contract:** [PRD-Settings.md](PRD-Settings.md).
Read Architecture → Rules → Traps → PRD-Settings before implementation.

## 1. Decisions and implementation boundaries

1. Preserve existing app preferences and data paths. Extend the native Settings scene;
   do not add another engine, web settings page, database, or generic preferences framework.
2. Separate **desired configuration**, **configuration handed to the engine**, and
   **observed request behavior**. None implies the others succeeded.
3. New engine preferences have a small throwing, atomic Codable store. Existing chrome/
   new-tab keys remain in UserDefaults. Neither engine getters nor UserDefaults.set can
   acknowledge a durable disk write, so neither is used to claim durable engine saves.
4. Search ships independently before DNS. First UI slice: built-in provider chooser and
   explicit search-off, plus existing General/About. Custom editing and remote suggestions
   are separate slices. Do not display empty Websites/Privacy/Network destinations.
5. No new engine behavior is declared proven by this document. Source inspection finds
   candidate paths; native probes must measure those paths before controls ship.

Ownership stays UI → `@MainActor LadybirdEngine` → `LadybirdBridge` → C11 LibPort.
Only Engine may use AppKit/CoreFoundation. UI never imports CLadybirdPort; Bridge never
imports AppKit/SwiftUI; Unmanaged stays in Bridge. No DispatchQueue, Task.detached, second
loop, display link, or blocking callback. Retain the current main-thread CommonModes pump.

Fork edits: LibPort, TestNative* probes, their permitted CMake registrations ONLY. A genuine
LibWebView/helper change needs a separate upstream-shaped proposal and approval. App/fork
changes land separately. This TDD does not authorize security/sandbox bypasses or edits to
another checkout's build source. See §9 for build-provenance rules.

**Current lifecycle limitation:** each BrowserWindow constructs a BrowserModel; do not
assume arbitrary multiwindow engine ownership has been solved. Settings must bind to the
existing live engine owner and NEVER create another BrowserModel/PortApp. Any multiwindow
lifecycle gap is a separate prerequisite, not fixed by pretending the singleton is shared.

## 2. Files, scope, and state ownership

| Location | Responsibility |
| --- | --- |
| Existing `AppSettings.swift` | Existing appearance/new-tab prefs; typed observable settings facade |
| New `EnginePreferences.swift` | New Codable desired record and small atomic file reader/writer |
| Existing Engine-owned startup path | Import/load and apply before first user navigation; no dependency inversion into Bridge |
| `SettingsView.swift` and small pane/editor views | Native forms, local drafts, inline errors, only populated categories |
| `LadybirdBridge/Port.swift` | Typed wrappers, synchronous UTF-8 copies, C result → throws |
| `Libraries/LibPort/` | Existing Settings adaptation, search policy, typed import/status snapshots |
| `TestNativeSettingsSearch*`, `TestNativeSettingsDNS*` | Deterministic native-host evidence; proposed, not yet present/run |
| Existing Swift test targets | Temporary-store/defaults tests, injected engine adapter/store effects |

Chrome/new-tab scope remains app-wide. Engine preferences apply to the one active engine
profile in this release, across its spaces—not separate DNS/search per visual Space.
There is no profile picker. The store path is a sibling of the existing graph under
`~/Library/Application Support/LadybirdMac/EnginePreferences.json`; do not rename the graph
or legacy UserDefaults keys. Future independent profiles require a separate scoped-store
migration before that feature ships; do not advertise profile switching with this store.

## 3. Desired-state record and persistence

New schema version 1 contains:

- Tagged search choice: `fallback`, `disabled`, `builtin(id)`, or `custom(name)`.
  A custom engine named `none` is not the disabled sentinel.
- Imported custom provider descriptors and the genuine suggestions preference. These are
  preserved even before editors/suggestion UI ship. Do not copy built-in URL definitions
  into Swift as a second catalog.
- Optional desired DNS record: system OR custom transport/address/port/DNSSEC. No split
  independent keys that can persist half of an update. CLI overrides are NEVER saved as
  the user's choice.

Write flow: validate full candidate → atomically write complete new record → publish desired
state → apply to live engine if available. Save failure preserves prior file and observable
choice and shows a concrete error; Cancel writes nothing. If applying a durably saved
valid choice fails, retain desired state, show the apply error/pending state, and do not
pretend it is effective. A retry explicitly reapplies the same desired record.

Use Foundation atomic writes with thrown errors; no guarantee against total filesystem/
hardware failure is implied. Corrupt/newer files must be preserved before replacement;
if backup fails, disable automatic writes, retaining the original bytes and exposing an
error. Reuse the existing graph's preservation POLICY, not its tab-graph storage/types.
Do not clear UserDefaults domains, browsing data, or workspace state during recovery.

### First launch / migration sequence

1. Load existing app-only keys unchanged. If the new file exists, it is authority; do
   not reimport or overwrite it from engine Settings.json on every startup.
2. If absent, capture a typed migration snapshot BEFORE setters overwrite engine state.
   LibPort reads from the actual engine profile's existing configuration using existing
   parser/catalog logic. No Swift code rewrites live Settings.json.
3. Distinguish original key absence from an explicit null/disabled choice. Inspect the
   actual `searchEngine.engine`, legacy `searchEngine.name`, and `autocompleteEngine`
   shapes; preserve selected custom descriptors, suggestions opt-in, and DNS choice.
   Getter/serialize_json normalization loses provenance: `Settings::serialize_json` also
   writes `searchEngine.engine = null` during unrelated saves with no selected provider.
   Therefore raw null is **ambiguous**, not proof of explicit user disablement. Capture
   original presence before mutation; return a typed ambiguous/needs-choice state when
   intent cannot be reconstructed. Preserve bytes/preferences and request an explicit
   provider/off choice before transmitting a prose query; do not silently choose fallback
   or claim the user disabled search. Missing-file first-run fallback remains unchanged.
4. Validate/import without silently deleting existing HTTP/custom provider values. Such
   imported entries may be shown read-only pending secure editing policy. Do not send a
   query to a different provider because an imported entry is unavailable.
5. Atomically save the snapshot, then apply managed values through typed APIs. On import
   save failure, do not replace the engine's previous settings with defaults. Show a
   recoverable migration error and keep Settings read-only for those values.
6. Projection runs from the existing Engine-owned startup method AFTER PortApp creation,
   BEFORE first user navigation. Bridge must not import/call Engine/AppSettings.
   Prove startup ordering, helper initialization, and handling of engine-cache errors;
   do not claim a locked/corrupt Settings.json has no effect on startup.

Settings.json remains Ladybird-owned derived configuration for managed values; never edit
it behind the engine. Unmanaged keys are preserved and remain outside Ava's authority.
There is no startup guarantee of zero background traffic: that needs separate measurement.

## 4. Search design

Source basis: `LbResolveUserInput`, `builtin_search_engines`, `Settings::set_search_engine_settings`,
`WebView::sanitize_url`, and the tests in the PRD evidence register. Existing fallback is
first built-in **Bing** at this pin; preserve it. No new default-provider policy is adopted.

Four relevant states:

- No original choice: fallback to actual first built-in, as existing native input tests require.
- Valid chosen provider: resolve using that engine and Ladybird's percent-encoding/classifier.
- Explicitly disabled: prose returns no search URL; real URLs/hosts/host:port remain usable.
- Missing/removed chosen custom provider: block prose searches with an unavailable message;
  never send queries to fallback or another previously configured provider without consent.

Keep policy in the current LbApp lifetime, initialized/reset at create/destroy. The existing
handle-less `LbResolveUserInput` must honor the live app's policy through a non-owning
association to the single live LbApp; before engine creation it preserves existing offline
fallback. The association is cleared before destruction; no static disabled policy may
leak across sequential tests/engine lifetimes. Confirm this design with the native probe;
if lifecycle access cannot be made safe, propose an additive app-bound resolver and update
ALL active browser callers rather than leaving a bypass of explicit search-off.

The engine catalog, not a Swift URL table, supplies built-ins plus imported custom entries.
Catalog references are copied synchronously in Bridge. Built-in IDs may initially be the
engine's stable names at this pin; custom names remain separately tagged. Unknown/stale
IDs produce a typed error and visible unavailable state.

First UI uses one provider picker with an explicit off entry, not conflicting picker/toggle
states. Preserve custom selections as read-only selectable imported entries where supported.
No suggestions UI in first slice. When it eventually ships, preserve opt-in while the
current provider lacks an endpoint; the network path remains disabled while unavailable.
Expose provider disclosure before opt-in. Do not fetch suggestions merely to populate Settings.

Custom editor follow-up: trimmed unique name, HTTPS URL, valid host, no credentials/control
characters, exactly one `%s`. Validate the placeholder's location/URL parsing, not just string
presence. Duplicate policy matches engine catalog identity; never override a built-in by name.
Reject invalid drafts without replacing prior values; removal of the selected provider requires
explicit replacement/off, never fallback. Test imported legacy HTTP values separately.

## 5. DNS design and health limits

The inspected `DNSSettings` variant contains System, UDP, TLS; **not DoH**. Provisional
routing/security paths in `Resolver::create`, `Request::handle_dns_lookup_state`,
`apply_dns_settings`, and `RequestServerManager::dns_settings_changed` are SOURCE EVIDENCE,
not executed proof. System/custom switches stay gated until §9.

Persist the desired whole record; keep separate configured and applicability snapshots.
`LbDNSSetSettings` can acknowledge validation/configuration handoff only. Current IPC has
no settings-wide resolver-handshake ACK. UI must say **Configured**, **Pending**,
**Overridden**, **Unavailable**, or **Error**, never Connected/Verified/Encrypted merely
because a setter/getter succeeded. Per-request DNS failure is not automatically observable
through today's ABI; no phantom callback or `lastDNSError` fed by nonexistent events.
A connection-test button remains deferred.

System is default. New custom DRAFT defaults to TLS/853; preserve existing UDP/custom port.
Ports must be 1–65535 at the UI/model boundary; an omitted draft port chooses transport
default once, not overwrites an intentional custom port whenever transport changes.

Validate IPv4/IPv6 with platform parsing in Engine (and equivalent engine validation at C
boundary); normalize accepted IPv6 bracket policy explicitly. Hostnames follow actual
engine-supported ASCII/IDNA rules, checked by probe; reject malformed literals, URL schemes,
paths, userinfo, controls, embedded whitespace, invalid labels, ports embedded in host, and
out-of-range numbers. No live resolver changes while typing. Cancel is non-mutating.

CLI override: honor the original desired choice separately from launch-forced effective
settings. Read existing forced/proxy metadata internally from Settings serialization or
existing request options and translate to typed fields. Do not add an unapproved upstream
getter solely for convenience. Save/apply cannot clear the forced flag through a normal
setter. Explain the override and disable editing while in effect.

Proxy applicability must distinguish none/partial/all, including HTTP versus HTTPS route
coverage; a global flag alone must not imply every PAC-selected request uses the same route.
Show host/port only, never credentials. Full remote resolution makes local DNSSEC control
inapplicable without erasing its saved preference; partial bypass explains which requests
may differ. DNSSEC authenticity and TLS transport encryption are distinct.

Probes must determine bootstrap lookup behavior for hostname resolvers, authentication and
certificate-name handling for both IP/hostname TLS endpoints, existing connection/cache
semantics, running/new helper propagation, and failure/no-downgrade behavior. If strict
TLS cannot be guaranteed, do not ship a promise of strict encryption; keep that mode blocked
pending a separate reviewed fix. No changes to system DNS or other apps; no zero-leakage claim.

## 6. Proposed boundary contracts (not existing exported APIs)

Only implement functions required by the accepted slice. Do not ship speculative Phase 3
headers or change LbCallbacks layout. Add new named/versioned types without widening old
structs/enums; new structs carry a size/version prefix, checked before reading/writing.

| Proposed operation | Contract |
| --- | --- |
| Read settings migration snapshot | Typed search provenance, selected identity, custom catalog, suggestions preference, desired DNS and override applicability; captured before mutation; scoped to actual engine profile |
| Visit search catalog | Synchronous C callback per typed descriptor: version/size, kind/identity/name/query URL/optional suggestions metadata; callback strings borrowed ONLY until callback returns; Bridge copies |
| Get/apply search choice | Typed fallback/provider/disabled policy; validates identity; result separates invalid ID/unavailable engine; lifetime in LbApp |
| Get DNS configuration/status | Typed versioned snapshot: desired/configured transport/address/port/DNSSEC, CLI forced state, proxy none/partial/all + safe server display; no network-health assertion |
| Apply DNS configuration | Complete validated candidate; refuses override/invalid args; success means configuration handed off, not lookup or durability proof |

Common C11 shape: opaque `LbApp*`, explicit UTF-8 pointer+length pairs, typed result enum
(OK, invalid/null argument, unknown identity, engine unavailable, overridden, unsupported
version), no arbitrary JSON payload or C++/ObjC objects. Required pointers are nonnull;
zero-length optional fields are explicitly allowed; invalid UTF-8/embedded NUL/length
mismatch is rejected rather than passed into a C-string API. Outputs reset before work;
caller must release prior owned buffers before reusing a result. Any returned owned
strings use matching `LbStringFree`, including partial-allocation cleanup on failure.

Main-thread asserts per entry point. Bridge maps results to typed throws; upper layers see
no numeric codes/raw pointers. No undefined void-setter success or invented localized
error buffers. Swift owns user-facing error messages; invalid C enums fail closed, never
silently coerce DNS transport to system. Teardown invalidates non-owning app associations.
No async operation callbacks are added in these synchronous configuration slices.

Phase 3 asynchronous operations need their OWN reviewed request-ID/completion contract:
exactly-once success/failure/cancellation, Bridge-owned context lifetime, stale completion
rejection, teardown cleanup, and nonblocking main-thread callbacks. Reopening Settings
must not attach an old data-delete completion to a new operation.

## 7. Full inventory disposition and UI timing

PRD §3 is the exhaustive control catalog; this table assigns remaining implementation gates
without reproducing its source table or claiming all Phase 3 controls are already designed.

| Capability group | Scope/default/timing | Delivery requirement |
| --- | --- | --- |
| Existing new-tab + chrome appearance | App; blank/System; next tab/live | Preserve keys/validation; About becomes General detail |
| Search provider/off | One engine profile; existing fallback; next query | §4 + native search/migration probes |
| Custom providers/suggestions | Profile; preserve imported values, new suggestions off | Separate secure-editor/native-suggestion TDD slices |
| DNS/override/proxy/DNSSEC | Profile; System, DNSSEC off; lookup timing UNVERIFIED | §5 + native DNS gate |
| Zoom + host overrides/languages | Profile; engine 100%/system-language defaults | Measure host precedence, existing/new tabs, requests and relaunch; no invented zoom bounds |
| Force dark / autoplay + allowlist | Profile; new force-dark off; existing BlockAudio policy | Page effects/reload timing probe; distinct from app theme |
| Geolocation | Provider/OS/site response path; engine default off | Native permission integration gate; not a simple granted-location Boolean |
| Cache size/estimates and data clearing | Profile; engine cache default; explicit async action | Categories/ranges actually honored, exact scope/errors, sign-out warning, no selected categories by default |
| GPC | Profile; existing/new policy explicit, new default off; next-request proof | Prove actual signal; no guaranteed tracking protection claim |
| Blocking/exception lists/count | Profile; engine master/lists initially off at this pin | Prove list loading + request enforcement; count UI only if real indicator exists |
| List subscriptions/local import/custom rules | Profile; no unsolicited new subscriptions | Explicit IP/contact disclosure, validation, bounded file size, async error/cancel; separate editor slice |
| Background service master/list auto-updates | Profile; preserve existing master on/updates off | Pausing preserves choices; excludes browsing/DNS/suggestions/explicit updates |
| Crash-folder reveal | Actual OS-supported report path; user action | No upload controls or fabricated path; Engine platform seam |
| Middle-button autoscroll | Engine/input path, existing policy | Probe native input support before advanced control |
| Menu/bookmarks/tab-position/window decorations | Native/app ownership | No hide-Mac-menu, horizontal-tabs, nonexistent bookmarks-bar, or fake Qt tuning controls |
| Debug/performance/download-tuning | Developer/download ownership | Deferred until actual Ava consumer; no unsafe consumer defaults |
| Geometry/first-run metadata | Existing internal owners | Not editable preference rows or second stores |

Only populated native destinations ship. Current small TabView can remain until a third
substantial category warrants a sidebar. Use a resizable/scrollable native Settings window,
Cmd-comma reuse, clear labels, keyboard/VoiceOver, light/dark/contrast/transparency/motion.
Structured editors use local drafts + Save/Cancel and inline errors; supported toggles/
pickers apply immediately only where proven. Reset touches only its owned preference group.
Settings never redesigns the Safari header or Arc sidebar.

## 8. Tests and acceptance of app-side slices

Isolate stores in temporary directories and UserDefaults suites; no real clipboard/profile
writes or second engine startup from unit tests. Inject a narrow apply closure/protocol only
if needed to test unavailable/rejected/overridden effects; no generic plugin architecture.

Required tests: legacy keys unchanged; tagged-choice name collisions; complete metadata/DNS
atomic round-trip; malformed/newer-file preservation and backup/write failure; cancelled
and invalid drafts; missing selected custom provider blocks search; import exactly once;
actual key shapes/current+legacy custom/suggestion/DNS cases; no forced CLI setting imported
as desire; startup/retry ordering; denied apply keeps desired/effective states distinct.

Search tests include Unicode/percent-encoding, URL/prose/host:port, enabled/off/fallback,
uninitialized resolution, engine teardown/state reset, and no fallback after explicit-off.
DNS validation tables include IPv4/IPv6, IDNA policy, invalid schemes/credentials/whitespace,
transport changes with custom port, unknown enum and bad size/version/null/string inputs.

Manual native Settings checks: open/reuse/close, keyboard and VoiceOver, visible errors,
relaunch, engine unavailable, active-page/tab/space preservation, and no effect from Cancel.
Visual evidence is separate from compilation. No second engine for multiwindow testing;
record any existing multiwindow prerequisite rather than claiming unsupported coverage.

## 9. Native probes, sequencing, and rollback

**All probes below are proposed/unrun.** Phase 0a search/migration can pass and unblock
Phase 1 independently; DNS failure must not block the safe search slice.

- `TestNativeSettingsSearch*`: isolated config; built-in catalog and configured/off/fallback
  route assertions; query encoding; invalid IDs; raw URL/host:port; typed migration snapshot
  preserves original key presence/custom/opt-in. Use bounded deadlines and subprocesses for
  lifecycle cases if sequential engine creation itself is not supported. Reuse assertions
  from the existing TestNativeInput without changing unrelated input tests.
- `TestNativeSettingsDNS*`: deterministic loopback fixtures on dynamically allocated ports,
  unique test names, captured resolver queries, local HTTP target, valid test trust chain
  for a POSITIVE authenticated TLS case, negative handshake/certificate cases, and observable
  fallback traps for both UDP AND system resolution. Packet absence on one port is NOT
  proof of no downgrade. Never disable certificate validation to make a fixture pass.
- DNS matrix: System→UDP→TLS→System; running/new helpers; cached/uncached names and existing
  connections; hostname-bootstrap disclosure; DNSSEC valid/invalid behavior; proxy partial/
  full/PAC applicability; CLI `--dns-server <host> --dns-port <port>` (plus TLS flag as needed).
  Bound each wait; no public DNS dependency or privileged port assumptions. If test trust or
  routing observability needs forbidden engine changes, report BLOCKED before editing.

Build in the audited fork checkout. In isolated Orca worktrees, initialize independent
submodule git metadata; never copy/repoint another worktree's `.git` pointer. A shared build
symlink may be used read-only for Swift linking after source comparison, NOT to compile a
new probe against the wrong CMAKE_HOME_DIRECTORY or overwrite shared libraries.

Register permitted targets, then use `cmake --build <audited-build> --target <probe-target>`
and execute that produced target with bounded timeout. Record source SHA, CMake source root,
actual command/result, fixture setup, and untested cases. Run Swift tests and Bash4+ layer
check. An app compile or setting/getter round-trip is not resolver/persistence proof.

Commit order: permitted fork adaptation + probes first; deliberate remote pin advance;
Bridge/Engine facade + tests; native populated pane; follow-up capabilities independently.
No app/fork changes in one feature commit. API descriptions above are proposed contracts,
not permission to change upstream-shaped code without review.

Rollback preserves original desired record and privacy choices. Feature UI may be hidden
while a regression is fixed, but disabled/unavailable search may NEVER silently become Bing.
Do not downgrade desired strict TLS, erase profile data, or reset unrelated settings to
restore a green build. Report blocked runtime gates instead of weakening tests.

## 10. Review record and current release gate

First draft rejected for unmeasured security guarantees, impossible callbacks, invalid
Swift examples, migration ambiguity, incomplete inventory, and unsafe fallback/persistence
claims. Revised by the worker; finalized by coordinator with lifecycle/import/protocol
clarifications and separately executable phase gates.

**Approved now:** Phase 0 search/migration implementation and evidence collection; separate
DNS probe planning. **Not claimed complete:** any new settings runtime support, DNS security
behavior, engine preference migration, multiwindow lifecycle, or a shipped Settings pane.
Phase 1 authoring begins only after its native evidence is reviewed and the exact implemented
ABI is recorded alongside this design. Phase 3 requires focused capability-specific designs.
