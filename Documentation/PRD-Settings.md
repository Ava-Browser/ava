# PRD: Arc-inspired native Settings

Status: Proposed implementation brief
Owner: settings-porter
Scope: local macOS app, macOS 14.4+, unsigned development builds

## Goal

Give the browser a cohesive, native Settings window inspired by Arc's clarity and personality.
This is not an Arc clone or a feature-parity project. Every visible preference must control
real behavior supported by our app, macOS, or a verified Ladybird API.

Read AGENTS.md, Architecture.md, Rules.md, Traps.md and TDD-Spaces.md before implementation.
Existing layer and main-thread rules remain binding.

## Product principles

- Native Mac Settings window, not a web page, browser tab, or sheet over page content.
- Familiar controls, concise labels, calm spacing, restrained materials and semantic colors.
- Arc inspiration means coherent grouping and approachable presentation, not copied branding.
- No fake switches, placeholder panes, silently ignored values, or aspirational privacy claims.
- A small working settings surface is preferable to a large catalog of unavailable features.
- Settings must not recreate the engine or reset tabs merely to apply an appearance change.

## Entry and window behavior

- App menu: Settings… with Command-comma; repeatedly invoking it focuses the existing window.
- Closing Settings does not close browser windows or terminate the engine.
- One settings window shared across browser windows; no second BrowserModel/PortApp instance.
- Sidebar and content layout when at least three populated categories exist; otherwise use
  a simpler native structure. No empty destinations just to match Arc.
- Initial pane selection remembered separately from browsing state.
- Support keyboard navigation, VoiceOver, light/dark appearance, Increase Contrast,
  Reduce Transparency, and Reduce Motion. Use system traffic lights and controls.
- macOS 15+ effects are optional and availability-gated; no deployment-target increase.

## Capability inventory: mandatory first deliverable

Before implementation, report a table to advisor:

    preference | owner/scope | existing API or symbol | supported now? | application timing | test

Inspect the actual app and fork; do not infer support from Qt's controls or a method name.
For engine semantics, cite an existing test/probe actually read. If behavior is unproven,
mark it unverified and propose a probe rather than claiming support.

Classify each item: app-only, macOS integration, existing Bridge/engine API, or unsupported.
The first implementation should be app-only where possible. Unsupported or unverified items
are omitted, not displayed as convincing but inert controls.

## Candidate categories and release scope

These are candidates, not promises. Only populated, capability-verified categories ship.

### General

- Home/new-tab destination, if both behaviors are routed through a shared existing model API.
  Keep them separate if their meanings differ. Validate a supported URL; show inline errors
  and preserve the previous good value on invalid input. No navigation merely by typing.
- Search provider using a small explicitly supported set, only if omnibar search routing
  exists. Changing it must affect actual subsequent searches through the same routing path.
- Restore previous session only if session persistence/restore has landed. Do not implement
  a competing persistence store or restore pipeline as part of Settings.
- Default-browser integration is optional: use a supported system flow with consent and show
  failures. Do not claim the app is default based on a locally saved Boolean. Defer if the
  development bundle cannot register reliably.

### Appearance

- App chrome appearance: System / Light / Dark, if it can be applied consistently.
  This does not promise changes to page rendering or website color-scheme preferences.
- Sidebar visibility or placement only through existing supported window/sidebar state.
  Do not introduce a second source of truth for the system collapse toggle.
- Accent/theme customization is optional and depends on an existing theme model. No new
  theme engine, mesh-gradient editor, or hardcoded imitation of Arc in this milestone.

### Tabs and Spaces

- Only expose preferences already implemented by the tab/space model.
- No automatic tab expiration or archival. Persistent tabs remain the product default.
- Profile, Space, and container are distinct concepts; never label a visual Space as an
  isolated account container without verified storage isolation.
- Do not implement or modify Spaces, folders, containers, unloading, or session restoration
  here. Coordinate with the current model owner and consume its API after it lands.

### Privacy and website controls — capability-gated, not required for v1

- Include only controls backed by verified engine behavior and a working response path.
- Do not fabricate tracking protection, HTTPS-only, cookie partitioning, permission defaults,
  cache clearing, or per-site controls because Arc has similar settings.
- Destructive clearing requires a precise description of scope and a working engine API;
  never simulate it by deleting development folders or only clearing Swift preferences.
- No security/isolation claims based solely on storing a setting.

### About

- App name/version/build where available; useful development-build fallback otherwise.
- Acknowledge Ladybird as the web engine; links to the actual project and relevant licenses.
- No updater controls, release-channel picker, account sign-in, or invented version numbers.

## Scope and persistence

- Window layout/appearance preferences are app-level unless a profile-aware store already
  defines a narrower scope. State the scope of every preference in the inventory.
- Browsing preferences belong to the active profile when the profile model supports that;
  do not silently share a supposedly profile-specific preference globally.
- Use the existing settings mechanism if present. Otherwise standard UserDefaults is enough
  for small app preferences; no database or package dependency for this feature.
- Stable keys, centralized defaults, validation on read, and safe fallback for unknown values.
- Do not persist engine handles, CF pointers, surfaces, or copies of the workspace graph.
- Apply changes immediately where safe. If a genuine setting requires restart, say so clearly
  and preserve it for the next launch; never force an unexpected restart.
- Reset, if provided, resets only preferences owned by this feature, not tabs, profiles,
  browsing data, or unrelated UserDefaults keys.

## Architecture and collaboration

- LadybirdUI owns settings views. LadybirdEngine exposes typed observable preferences and
  applies effects through existing model APIs. Bridge remains the sole C-ABI adapter.
- No direct C imports from UI, no AppKit in Bridge, no thread hops or additional event loops.
- Create new settings files rather than rewriting BrowserModel/BrowserWindow for convenience.
- Coordinate the minimal app-menu/scene wiring with browser-mac, who owns the live shell.
- Do not touch fork sources, submodule metadata/pins, build scripts, surface presentation,
  resizing, or tab selection without an explicit ownership agreement. Request a Bridge API
  from its owner if genuinely needed; engine work is not automatically authorized by this PRD.
- Coordinate launches with browser-mac and junior-worker. No broad pkill or shared relinks
  during the glitch investigator's stable reproduction window.

## Delivery phases

1. Capability inventory and proposed v1 controls; advisor reviews before implementation.
2. Native Settings entry/window plus the smallest verified General/Appearance/About subset.
3. Follow-up categories only when their underlying features exist; no empty scaffolding.

## Acceptance criteria

- Command-comma opens/focuses one Settings window; browser remains usable behind it.
- Every visible control demonstrably changes the behavior described by its label.
- Preferences survive quit/relaunch; corrupt/unknown stored values fall back safely.
- Changes do not create a second engine, lose tabs, reset the active Space, or alter page
  surface geometry as a side effect of merely opening Settings.
- Invalid destinations show an actionable error without replacing the last valid value.
- App appearance works in System/Light/Dark without claiming to theme website content.
- Keyboard and VoiceOver work; labels and focus order are coherent in both appearances.
- Unit tests cover defaults, stored-value validation, and preference-to-behavior routing.
  Manual verification covers menu shortcut, window reuse, live effect, and relaunch.
- Layer checks and existing tests pass; report precisely which controls were exercised.

## Non-goals

Exact Arc parity, Arc account/sync, extensions, imported Arc preferences, custom shortcuts
editor, new engine security features, auto-updater, signing/notarization, a persistence
redesign, and unrelated fixes for tab/resize/first-window rendering glitches.
