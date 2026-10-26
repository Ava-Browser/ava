# PRD: Ava Settings — simple controls, real capabilities

**Status:** Revised product scope. Ava-native settings remain limited to app-owned controls;
Ladybird's working `about:settings` page is the source of truth for engine-owned settings.
The former native Search/Network plan is cancelled and retained below only as research evidence.
**Updated:** 2026-10-26.
**Product owner/final reviewer:** coordinator. TDD author: supervised settings-design worker
(Gemini 3.8 Flash/high), revised after review; coordinator finalized the design.
**Platforms:** macOS 14.4+, including unsigned development builds.

## 1. Outcome

Keep Ava's native Settings focused on app-owned controls such as new-tab behavior and chrome
appearance. Engine-owned search, network, website, privacy, and browsing-data controls stay
in Ladybird's `about:settings` page. Ava must not duplicate those values, add a parallel
persistence model, or interpose a policy that blocks working engine features.

This document inventories the **checked-in engine**, commit
`66616b4deeb42fbc7ce722075f22b1b1e5f5891a`, not an assertion about every future upstream
release. Evidence below is source inspection and tests actually read, **not newly executed
engine-setting verification**. Qt UI is not evidence of engine behavior. No Qt-specific
implementation is needed for this inventory: Ladybird's own WebUI/settings definitions
provide its control catalog.

## 2. Current Ava baseline

- Native SwiftUI `Settings` scene: Cmd-comma, one app-level settings model, no second engine.
- `AppSettings`: validated custom/blank new-tab destination; System/Light/Dark APP chrome.
- `SettingsView`: General, Appearance, About; fixed small window. No search or DNS selector.
- Tab graph restoration already exists independently in `WorkspaceManager`/`GraphStore`.
- Space name/icon/theme/order belong to the sidebar space manager, not duplicate Settings.
- `LbResolveUserInput` delegates address interpretation to Ladybird. Its fallback picks
  the first built-in when the configured engine is absent; this is not a provider picker.
- Existing C ABI has no DNS/search-settings getter/setter, languages, zoom, blocking,
  browsing-data, autoplay, or geolocation settings interface. A C++ setter's existence
  is **not** evidence that Ava currently supports the feature.

References: `AppSettings`, `SettingsView`, `BrowserModel::openTab`, `LbResolveUserInput`,
`ladybird_port.h`, and existing `SettingsTests` / `InputResolutionTests`.

## 3. Complete Ladybird settings-surface inventory

Classification: **A** = app-only/native owner; **B** = engine surface exists, new Bridge
support + native-host probe needed; **D** = intentionally deferred/platform-inappropriate.
Unless explicitly already shipped, this table is not an Ava support claim. Apply timing
in B rows is a requirement to prove, not a tested guarantee.

| Ladybird control/data surface | Ava disposition | Owner / proposed timing | Evidence |
| --- | --- | --- | --- |
| New-tab URL; restore default | Already A: blank/custom; preserve behavior | AppSettings; next new tab | E1, A1 |
| Window geometry/maximized state | Keep native window behavior; not a preference row | App/native restore | E2 |
| Show system menu bar | D: Mac menu bar is native and not an optional web control | OS | E1, E3 |
| Bookmarks bar: always/never/hover | D until a real Ava bookmarks bar exists | App UI | E1, E2 |
| Vertical tabs enabled/expanded/hover expansion, left/right, stored width | A/D: Ava's sidebar is a product invariant; no horizontal-tabs switch; preserve native collapse/resize | App UI, immediate | E1, E2 |
| Default page zoom; per-host zoom map | B, Website settings | Per browser profile; existing/new tabs timing must be probed | E2, E8 |
| Force-dark website rendering | B, later experimental control; DISTINCT from app appearance | Engine content settings; probe existing/new navigation | E1, E2, E8 |
| Ordered website languages: add/remove/reorder | B | Engine content/network; next request/navigation, probe | E1, E2 |
| Middle-button autoscroll | B, advanced website/browsing option only if native input path supports it | Engine + native input | E1, E2 |
| Middle-button primary-selection paste | D on Mac unless platform explicitly supports it; not ordinary clipboard paste | Platform-gated in engine | E3, E4 |
| Open crash-reports folder/status | A/native integration candidate; only actual reports, no fabricated upload opt-in | Engine/platform path; user action | E1, E3 |
| Default search engine; disable search | B, priority; explicit None requires fallback correction | Engine address resolution; next submitted search | E2, E5, E6, E7 |
| Custom engines: add/remove, query template, optional suggestions template | B, progressive advanced editor | Engine search catalog, next submission | E2, E3, E5 |
| Search suggestions on/off and provider availability | B, later opt-in; same selected search provider | Engine/network + native address UI; live when proved | E5, E6 |
| Autoplay policy and site allowlist (add/remove/remove-all) | B, Website settings | Engine policy; existing/new page timing probe | E1, E2, E3 |
| Geolocation enablement | B, only with provider + permission response path; no fake per-origin manager | Engine/platform; explicit permission integration | E1, E2, E3 |
| Cache usage/site-data size estimates | B | Engine async operation; on request | E1, E3 |
| Maximum HTTP disk-cache size (MiB/GiB) | B, advanced Website data detail | Engine request servers; probe application | E1, E2 |
| Clear cached files | B, destructive operation with completion/error | Engine; explicit action | E1, E3 |
| Clear browsing history | B only when actual relevant history store is identified | Engine/app ownership; explicit action | E1, E3 |
| Clear download history, NOT downloaded files | B only with actual store support | Engine history; explicit action | E1, E3 |
| Clear cookies and site data | B, precise current-profile/container scope required | Engine/storage; explicit action | E1, E3 |
| Clearing time ranges: hour / four hours / today / all | B, expose only ranges/categories actually honored | Engine; explicit action | E1, E3 |
| Global Privacy Control | B, describe as a REQUEST to websites, not guaranteed blocking | Engine request/page state; wire + probe | E1, E2, E6 |
| Ad/content blocker master switch | B, staged after real native-host enforcement proof | Engine blocking pipeline | E1, E2, E9 |
| Block-count indicator visibility | D until Ava has a real indicator | App + engine | E1, E2 |
| Per-site blocking exceptions | B, Site details follow-up | Engine host canonicalization | E2, E9 |
| Built-in/language-specific filter lists: enable/disable; metadata/status | B, advanced blocking details | Engine list registry/enforcement | E1, E2, E9 |
| Filter subscriptions add/remove; update enabled lists | B, explicit network/privacy disclosure | Engine/network; async | E1, E3, E6, E9 |
| Local filter-list import/remove; custom Adblock rules | B, later advanced editor | Engine/platform picker; async import | E1, E2, E3 |
| Allow automatic service connections | B, combine into Privacy → Background connections | Engine; automatic services only | E1, E2, E9 |
| Automatic filter-list updates | B, subordinate option; retain choice when master paused | Engine; not a normal-browsing kill switch | E1, E2, E9 |
| System DNS / custom DNS | B, priority Network detail | Engine request servers; effective timing must be probed | E1, E2, E10 |
| Custom DNS transport UDP/TLS, host/IP, port, local DNSSEC | B, priority; advanced options progressively disclosed | Engine resolver; not a macOS system DNS change | E1, E2, E10 |
| DNS forced by launch arguments; proxy-resolution applicability notice | B, read-only effective-state explanation required | Engine launch/network policy | E1, E4, E10 |
| Advanced: WebContent PID in title; advanced debug menu; tab performance monitor | D for consumer Settings; Developer diagnostics only with actual Ava integration | App/engine | E2, E4 |
| Advanced: client-side window decorations | D; retain native AppKit chrome | App/OS | E2, E4 |
| Advanced: vertical-tab hover delay/animation duration | D until Ava offers that exact behavior; don't import Qt timings | App UI | E2, E4 |
| Advanced: connections per download; split without validators; restart stalled connections | D until real downloads support; unsafe splitting not a consumer recommendation | Engine download manager | E2, E4 |
| First-run completion; profile paths; serialized expanded state | Internal state, not user-facing preferences | Existing owner | E2 |

The currently defined built-in search providers are **Bing, Brave, DuckDuckGo, Ecosia,
Google, Kagi, Mojeek, Startpage, Yahoo, Yandex** (`builtin_search_engines`). Catalog order
is not an endorsement. Obtain real capabilities from the engine; do not hardcode a second
list/URL table in Swift. Some providers have no suggestions endpoint.

The DNS variant currently names **System, DNS-over-UDP, DNS-over-TLS**. No DNS-over-HTTPS
variant appears in the inspected settings contract. Do NOT advertise DoH or turn a TLS
choice into an unexplained "Secure DNS" promise. DNSSEC validation and transport
encryption are separate properties. No named resolver presets are required for first ship.

## 4. Simplified information architecture

One native app-wide Settings window, reachable with Cmd-comma. Keep it separate from a
browser tab/page/sheet. Never create a BrowserModel/engine to open it. Preserve current
preferences and focus an existing Settings window on repeated invocation.

Only show populated destinations. Introduce a native sidebar of categories when the
surface outgrows the current small TabView; do not create empty placeholders. All pages
are scrollable/resizable enough for validation messages and accessibility, not forced
into the existing 480 × 280 content size.

| Category | First-level controls | Details on demand |
| --- | --- | --- |
| General | New tabs open with; app appearance | Custom URL editor; About/version/licenses |
| Search | Default search engine | Custom providers; later opt-in suggestions |
| Websites | Default page zoom; preferred languages | Autoplay/exceptions; optional experimental page darkening; location only when ready |
| Privacy | GPC; content blocking; website data (as each is proved) | Filter sources/exceptions; background connections; precise data clearing |
| Network | DNS: System (recommended) / Custom | Resolver transport/address/port; DNSSEC; effective/override/proxy status |

About is initially a General detail, not an otherwise empty category. App appearance
moves into General without losing its existing key/value. Do not add a new homepage
concept, startup navigation override, session-reset toggle, horizontal-tabs switch, or
Space theme editor just to fill this window. Link to existing Manage Spaces if useful;
never duplicate the space graph or per-space editor state.

## 5. Priority requirements

### S1 — Search provider that actually affects the address bar

- Show the effective selected provider, not a hardcoded default in a new picker. On
  migration, preserve the user's existing provider and do not silently change current
  fresh-profile behavior. Future default-provider policy is a separate product choice.
- Selecting a provider applies to the next submitted textual search in every browser
  window sharing the engine profile. Existing pages do not navigate or reload.
- Keep Ladybird's shared input classification, public-suffix handling, and query escaping.
  Do not reimplement URL-versus-search heuristics in Swift.
- Offer "Don't search from the address bar" ONLY when it really prevents prose searches.
  Current `LbResolveUserInput` treats absent provider as first-run fallback: missing and
  explicitly disabled must be distinguishable. Required probe covers both, including
  initialized/uninitialized paths. Keep raw URLs and host:port input working.
- Custom-provider details: name required and unique under an explicitly defined policy;
  HTTPS query template containing exactly one `%s`, no credentials or unsafe schemes.
  Preserve existing imported HTTP/custom values without silently executing unsafe edits;
  TDD must specify display/migration policy rather than deleting user configuration.
  Removing a selected custom provider requires a clear fallback choice, not silent Bing.
- Suggestions default OFF for new Ava settings. Preserve a genuine existing opt-in;
  explain "Sends what you type to <provider>" BEFORE enabling. If unavailable for the
  selected provider, disable the control with a reason while retaining the user's choice.
  Actual suggestion requests/UI/cancellation are a separate capability gate; never
  launch remote suggestions from a settings toggle with no native address UI integration.

### N1 — DNS selection, simple by default and accurate when advanced

- Default: **Use system DNS**. Copy: "Use your Mac's DNS configuration."
- Custom: one compact editor, with address/IP, transport **TLS (encrypted)** or
  **UDP (unencrypted)**, and advanced port + "Validate DNSSEC locally". Defaults: UDP 53,
  TLS 853 when no explicit port is entered. Preserve a deliberate custom port across edits.
- Choose TLS as the proposed default for a NEW custom draft, but preserve the existing
  desired/configured DNS transport (excluding CLI- or proxy-forced state from draft defaults).
  TLS validation/bootstrap behavior remains a probe gate, not a claim.
- Validate full candidate on Save: host/IP supported by the engine, port 1–65535, no URL
  scheme/path/userinfo in a DNS host, correct IPv6 handling if supported. Invalid drafts
  never replace previous settings or break browsing while typing. Cancel is non-mutating.
- Show desired versus effective policy, applying/error/restart state, and launch overrides.
  Never label merely stored values as connected, verified, encrypted, or DNSSEC-protected.
- Apply to new lookups without engine recreation only if the native-host probe proves it.
  TDD must settle cache invalidation, existing connections, new helper processes, restart,
  and failure behavior. A CLI/Settings.json round-trip alone does not prove traffic routing.
- Strict TLS selection must not silently downgrade to UDP/system on failure. If Ladybird
  cannot satisfy that contract, keep the feature gated pending a separately reviewed fix.
- Proxy-resolved requests may bypass local DNS. Explain full/partial bypass and disable
  inapplicable DNSSEC controls without erasing the saved preference. No "VPN compatible"
  promise. Do not change macOS DNS, proxy settings, or other apps' network behavior.
- Omit named providers and DoH for first ship. A hostname resolver bootstrap may itself
  require system DNS: prove/document it, never claim zero DNS leakage by default.
- Any "Test connection" action is deferred until there is a bounded asynchronous real
  resolver test that distinguishes reachability from authenticated TLS/DNSSEC verification.

### W1 — Website preferences without app-theme confusion

Default zoom and ordered languages are the next candidates after Search/DNS. Values must
apply to the actual native-host page/request path, with documented live-versus-next-load
semantics. Preserve per-site zoom precedence and provide reset of an actual exception.
Website force-dark is labeled experimental and off by default for new Ava policy; it is
not App appearance. Autoplay labels must match the engine's policies and allowlist scope.
Location enablement cannot bypass the OS prompt or invent a site-permission approval.

### P1 — Privacy settings with explicit scope and honest network disclosures

GPC is a signal websites may honor, not universal tracking prevention. Blocking requires
working filter loading AND enforcement; enabling a Boolean is not sufficient. Filter-list
updates disclose third-party contacts/IP visibility, whether automatic or user-triggered.
The background master controls automatic SERVICES, not page browsing, search suggestions,
DNS, or user-requested list updates; keep those independent choices clear.

Website-data deletion requires actual async completion/error, exact data categories,
time semantics, profile/container scope, and confirmation. Default to no selected deletion
categories until the user chooses; clearly warn about sign-outs for site data. Download
history clearing must not delete files. Never delete the engine directory, workspace JSON,
saved tabs, Settings preferences, or another profile to simulate data clearing. Unavailable
categories/ranges stay omitted; stale completion may not report a different operation as
successful. No session reset or unsaved Settings draft loss merely by opening a dialog.

## 6. Ownership, persistence, and honest application state

- Existing app chrome/new-tab settings stay in `AppSettings` with stable keys and safe
  decode fallback. Do not rename `org.ladybird.*` keys or the legacy data path for branding.
- Global app appearance is app-level. Engine-backed browsing settings are scoped to the
  SINGLE active engine profile, shared across its windows/spaces unless probes prove a
  narrower session scope. No per-space DNS/provider controls or fake isolated profiles.
- One source of truth per value: the TDD must explicitly choose authority and startup
  synchronization for app versus engine-owned preferences, not let UserDefaults and
  Settings.json independently fight. Do not write JSON files behind a live engine.
- Current `Settings::persist_settings` returns void and logs errors. Getters/readback only
  prove in-memory state, not successful durable writes. TDD MUST resolve this gap before
  claiming engine-setting persistence/error handling: either a justified app-authoritative
  desired-state model with explicit effective/apply status, or a separately reviewed
  upstream-shaped error-reporting patch. A shim's unconditional success or disk preflight
  check is not a solution. Do not opportunistically change LibWebView from this app task.
- UI → Engine typed `@MainActor` facade → Bridge → additive C11 LibPort boundary. No UI
  C import, no AppKit/SwiftUI in Bridge, no raw pointer/Unmanaged outside Bridge, no queue/
  detached task/second event loop. Expensive/async operations must not block the pump.
- A typed unavailable/pending/overridden/error result is legitimate; an inert UI switch
  or a general-purpose arbitrary JSON settings bridge is not. Keep scope-specific APIs
  small, strings owned/lifetime-defined, and ABI layouts versioned when changed.
- Settings lifecycle: drafts preserve invalid input and show inline correction; Save
  commits validated structured edits, Cancel writes nothing. Toggles/pickers apply live
  only where proved. Closing Settings must not discard tabs or restart the engine.
- Reset a section only if implemented, with precise owned-key scope. Never clear an
  entire UserDefaults domain, engine profile, workspace graph, or browsing data by reset.
- Restart-required changes show a clear label and take effect on NEXT launch; never
  relaunch unexpectedly. A saved desired value and currently effective value may differ.

## 7. Delivery plan and exit criteria

### Native app settings

Preserve the existing General, Appearance, and About panes. Add only controls whose state and
behavior are owned by Ava. Cmd-comma continues to open this small native window.

### Engine settings

Search providers, suggestions, DNS/network configuration, website permissions, privacy,
and browsing-data controls remain owned by Ladybird and are configured through
`about:settings`. Do not add C ABI mirrors or Swift persistence for these controls. If a
future native integration is reconsidered, it requires a new product decision based on a
missing user capability—not visual consistency alone.

### Acceptance across phases

- Every visible control has a real effect, documented scope/timing, validation/failure
  behavior, and relaunch proof where persistence is promised. No telemetry is needed to
  prove task success; use deterministic checks and manual user flows.
- No second engine, lost tabs, reset active Space, header/sidebar redesign, new data path,
  silently changed search default, or destroyed browsing data as a settings side effect.
- Cmd-comma focuses one native Settings window; close/reopen/resize, light/dark, VoiceOver,
  keyboard, contrast/transparency/motion settings work.
- Unit tests cover app-owned defaults, unknown/corrupt stored values, cancelled drafts, and
  behavior routing. Engine settings remain covered by Ladybird's own tests and WebUI.
- CI scope remains honest: compile checks are not runtime proof. Report actual commands,
  engine revision/build provenance, screenshot evidence, and untested/blocked items.

## 8. Non-goals

Account/sync, extensions UI, DoH, proxy editor, password manager, HTTPS-only mode, cookie
partitioning controls, updater, native downloads implementation, changing sandbox/security
flags, process isolation, preferences generators/frameworks, arbitrary JSON IPC, or engine
fork changes outside the permitted seam without separate upstream-shaped approval.
Settings work does not release the Arc-sidebar/Safari-header ownership boundaries.

## 9. Evidence register (symbols, not line numbers)

All paths below are relative to `Extern/ladybird` unless prefixed `Sources`/`Tests`:

- **A1:** `Sources/LadybirdEngine/AppSettings.swift`, `Sources/LadybirdUI/SettingsView.swift`,
  `Tests/LadybirdIntegrationTests/SettingsTests.swift`; existing Ava behavior and validation.
- **E1:** `Base/res/ladybird/about-pages/settings.html` and its `settings/*.js` modules;
  eight Ladybird categories and visible controls, feature-gated in WebUI.
- **E2:** `Libraries/LibWebView/Settings.h`, `Settings.cpp`: `Settings`,
  `SearchEngineSettings`, `ContentSettings`, `ConfigVariableID`, `Settings::persist_settings`.
- **E3:** `Libraries/LibWebView/WebUI/SettingsUI.cpp`: `SettingsUI::register_interfaces`,
  `load_features`, `set_search_engine_settings`, `clear_browsing_data`, `set_dns_settings`.
  These are available WebUI handlers, NOT exported Swift APIs or native-host proof.
- **E4:** `Libraries/LibWebView/Application.cpp`: `ApplicationSettingsObserver`, launch
  DNS/proxy options; `Settings::browsing_behavior` platform primary-paste gating.
- **E5:** `Libraries/LibWebView/SearchEngine.cpp`: `builtin_search_engines`,
  `SearchEngine::format_search_query_for_navigation`; `Settings::parse_custom_search_engine`.
- **E6:** Tests READ, NOT RUN in this research: `Tests/LibWebView/test-webdriver-search-engine-settings.py`
  asserts migration, provider/suggestion coupling, unsupported-provider UI, custom suggestions
  validation, and relaunch. `test-webdriver-settings-changes.py` asserts partial update
  preservation of unrelated drafts, GPC state messages, and async list-update state; it
  does not prove GPC on actual native-host requests or DNS traffic routing.
- **E7:** `Libraries/LibPort/ladybird_port.h`, `LbResolveUserInput` implementation;
  `Tests/LibWebView/TestNativeInput.cpp` address-classification section explicitly asserts
  first-run fallback. `Tests/LadybirdBridgeTests/BridgeTests.swift` checks resolution without
  engine startup. No explicit-off native-setting test was found in the inspected native seam.
- **E8:** `ViewImplementation::content_settings_changed`; test files
  `test-webdriver-site-zoom.py` / `test-webdriver-force-dark.py` identified, not yet fully
  audited/run for this PRD. Treat their native-host application as unverified.
- **E9:** `Tests/LibWebView/TestBackgroundNetworking.cpp` cases `feature_policy`,
  `settings_are_persistent`, and list registry/persistence cases were read; not run here.
  `test-webdriver-content-blockers.py` identified for later audit/enforcement tests.
- **E10:** `Libraries/LibWebView/Options.h`: `DNSSettings`, `SystemDNS`, `DNSOverTLS`,
  `DNSOverUDP`; `Settings::parse_dns_settings`, `Settings::set_dns_settings`,
  `RequestServerManager::dns_settings_changed`, `Base/res/ladybird/about-pages/settings/network.js`.
  This proves settings/control/data shapes, not resolver security or timing. No native-host
  DNS-setting probe has been run; Phase 2 remains gated.
