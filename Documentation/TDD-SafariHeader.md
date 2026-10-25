# Specification: Safari-reference header

**Status:** Design specification only; not assigned for implementation.
**Reference:** User-supplied Safari header capture, 2026-10-25.
**Relationship:** Sidebar work in `TDD-SpaceSettings.md` still freezes the existing header.
This document defines a later, separately approved header pass; it does not lift that freeze.

## 1. Goal and boundaries

Ava's browser header should match the supplied Safari composition: native traffic lights,
compact grouped navigation, a large quiet address capsule with centered resting address,
and separate trailing action groups. Keep the Arc-like sidebar BELOW this header. Do not
move URL entry into the sidebar or adopt Arc's header layout.

Use real native window/toolbar behavior and real browser actions, not a screenshot-shaped
row of decorative controls. No changes to web rendering, engine threading, sessions, or
persistent workspace/tab structure belong to this work.

Read `Architecture.md`, `Rules.md`, and `Traps.md` before implementation.

## 2. Reference and scale

Local input (2198 × 238 pixels):
`/var/folders/02/l1xpyx6x5b9g5zq8y9l9n27m0000gn/T/orca-paste-1792930943599-06a19ab4-a8d7-4d24-8145-20e3e56bbae5.png`

The image includes wallpaper around the window; compare the window chrome, not the
entire image bounds. Do not commit this raw capture as a public asset without sanitizing
its browsing information. If it becomes unavailable, request it again.

The capture appears consistent with a 2× display, but scale/OS version are unconfirmed.
Approximate original-image measurements and conditional point equivalents:

| Element | Screenshot estimate | If 2× |
| --- | --- | --- |
| Visible window width | 1920 px | 960 pt |
| Header height to content boundary | 106 px | 53 pt |
| Group/address capsule height | 70 px | 35 pt |
| Sidebar-toggle group width | 134 px | 67 pt |
| Back/forward group width | 148 px | 74 pt |
| Address capsule width in this composition | 720 px | 360 pt |
| Traffic-light diameter | 28 px | 14 pt |
| Address text | about 26 px | about 13 pt |

These are visual starting estimates, not fixed native control dimensions. Confirm scale
and measure a rendered build before treating them as acceptance values. Native traffic
lights, toolbar height, materials, and control shapes remain system-owned. The point is
matching this screenshot's hierarchy, density, and spacing—not hardcoding a 960 pt window.

## 3. Composition, left to right

1. **Native traffic lights.** Keep AppKit's close/minimize/zoom controls, their active/
   inactive states, accessibility, full-screen behavior, and system placement. Never draw
   replacement circles, move them manually, or fake a window radius.
2. **Sidebar group.** A sidebar symbol with an adjacent disclosure/menu affordance inside
   one compact group, distinct from navigation. The sidebar toggle continues to control
   the existing split view. Any disclosure must open real, relevant sidebar options;
   omit it in the first implementation if no such options exist. Do not duplicate the
   automatic split-view toggle or place sidebar options in the address capsule.
3. **History group.** Back and forward chevrons share one compact native group; the
   reference has a subtle internal separator. Enabled/disabled state comes from actual
   history. Preserve existing navigation shortcuts and tooltips. No reload button here.
4. **Address group.** The main flexible capsule, wider than any action group. Page-related
   affordance at its leading edge; resting host centered INSIDE the capsule; reload at
   its trailing edge. The text must not visually follow the leading icon like the
   current left-aligned text field. Reserve balanced internal space so reload does not
   shift the resting host off center.
5. **Optional utility group.** The reference includes download/bookmark controls and
   several colorful icons, some of which are installation-specific extensions. They
   are not Ava branding and must not be copied as fake installed extensions. Real
   download/bookmark features may join this group when implemented; do not reserve a
   large empty capsule or show enabled dead controls in their absence.
6. **Trailing browser actions.** Reference order: Share, New Tab (`+`), tab overview
   (overlapping rectangles), in a separate compact group. New Tab already exists.
   Share/overview require real behavior before becoming enabled controls; see §7.

Groups share one vertical centerline, with small consistent gaps and generous whitespace
around the URL. Address text is centered within its capsule; the capsule occupies the
available middle region. Do not force its center to the exact WINDOW midpoint when
asymmetric native leading/trailing groups make that impossible—the reference itself
has asymmetric controls.

## 4. Address behavior and states

### Resting

- Display the full parsed host for an ordinary HTTP(S) page, centered and single-line.
  Do not misrepresent a subdomain, hide an unusual port, or show a different site's name.
  An empty/new tab displays a subdued prompt, never the previous page's host.
- Preserve the actual complete URL separately from the compact display. Copying the
  address must use the complete URL, including scheme/path/query, not just visible host.
- Other URL types and parse failures use an explicit safe display, not a guessed host.
  Never trim arbitrary user input into a falsely reassuring domain.
- Use system body-sized text (approximately 13 pt), semantic foreground, quiet surface,
  and no redundant page title in the same header.

### Editing

- Clicking the text/capsule or Cmd-L enters an editable field containing the FULL URL
  and selects it. Leading/trailing action buttons retain their own independent targets.
- Editing is conventionally leading-aligned, with a visible system focus treatment;
  it need not remain centered like resting display.
- Return uses the existing address/search resolution and submission path. Preserve
  paste, selection, arrow keys, standard Edit commands, and current search provider.
- Escape discards the draft and restores current-page display without navigating.
  Focus loss exits editing without implicitly submitting a draft. Page callbacks must
  not overwrite an in-progress draft. Tab switches must not carry one tab's draft into
  another; explicitly restore the newly selected tab's address.
- Do not introduce an autocomplete/search-suggestions service in this visual pass.

### Loading, history, and security

- Put reload INSIDE the address capsule at the trailing edge, still wired to existing
  reload behavior and Cmd-R. Remove the redundant standalone leading reload button.
- Loading feedback stays restrained and does not shift URL geometry. A Stop button is
  permitted only if a working cancellation API is available and separately wired;
  never replace reload with a no-op Stop icon merely to resemble Safari.
- Back/forward disabled states reflect actual availability. Loading must not disable
  unrelated sidebar/header controls or reset field focus.
- The leading page/reader icon in the screenshot is not proof that Ava supports Reader,
  AI, or site permissions. Until a real page-actions surface exists, use the existing
  honest decorative fallback, not a fake actionable Safari feature.
- Do not display a lock, privacy shield, or "secure" assertion unless backed by actual
  verified engine security state. A copied Safari icon is not security evidence.

## 5. Surfaces, typography, and system compatibility

The reference is a light, nearly neutral header with light rounded control groups and
very restrained separation. Match its grouping and negative space. Do not add heavy
outlines, colored branding, gradients from the active space, stacked glass, or custom
shadows. The screenshot's dark line at the content edge should be investigated as a
boundary in the capture; use a single native separator where needed, not a permanent
thick black rule copied without context.

Use semantic colors and native grouping/materials. Light and dark appearances are
separate treatments; custom selection/focus must remain legible in inactive windows,
Increase Contrast, and Reduce Transparency. Native controls own motion; no bounce.

Current deployment target is macOS 14.4. Keep it. Newer toolbar/Liquid Glass APIs need
availability checks and native older-OS fallbacks. Do not pretend a macOS 14 control can
be pixel-identical to a newer Safari chrome by painting imitation system glass. Report
OS-version differences; evaluate tight pixel matching on the same OS/backing scale.

## 6. Resizing and interaction contract

- Retain native toolbar drag area, split-view collapse, window resize, full screen,
  toolbar overflow, traffic lights, and menu-bar commands.
- Existing narrow-window minimum is 620 pt; validate there as well as a reference-sized
  window (~960 pt if scale is confirmed). The address remains usable instead of forcing
  utility groups to push it offscreen or clipping navigation.
- Flexible address width uses the space left after native action groups; do not keep
  the current 520 pt ideal width if it crowds the reference-sized composition. Start
  near the measured 360 pt for this reference layout, then verify with the actual
  implemented actions. This is not a global fixed maximum.
- Optional utilities yield to address/navigation space first, using native overflow.
  No placeholder gaps for unimplemented utilities. At narrow widths, prioritize actual
  navigation, editable address, sidebar toggle, and New Tab over visual symmetry.
- Every icon button has an accessible name and help text. Decorative icons are hidden
  from VoiceOver. Keyboard users can reach the address and every available action;
  visible focus must not be removed to achieve screenshot parity.

## 7. Smallest complete implementation and explicit deferrals

First header pass (after the current sidebar task is reviewed): native sidebar toggle,
grouped back/forward, true resting/editing address states, trailing in-field reload,
and existing New Tab action; match the reference's structure with those real controls.

Full reference parity additionally includes working Share and tab overview, and any
future bookmark/download controls. Treat those as bounded functional follow-ups, not
fake buttons in the visual pass. A real macOS Share action would go through an Engine-
owned platform integration seam, never by importing AppKit in `LadybirdUI`. A real tab
overview must select/close actual tabs, not present dummy thumbnails. Downloads/bookmarks,
extensions, Reader, AI, privacy reporting, and remote suggestions are not authorized here.

The implementation report must call the first pass **partial reference parity** if any
reference browser actions remain absent. Do not declare complete Safari parity by only
matching the address capsule.

## 8. Implementation seams and verification

Expected future code: `BrowserWindow` toolbar composition, a small address-field view if
needed, and minimal existing `BrowserModel` input/state coordination. Reuse current
navigation/new-tab methods; no engine fork, C ABI, persistence migration, or new dependency.
A view-local draft is preferable to overloading the current navigation URL as edit state.
Read all address/history/tab-selection callers before changing their contracts.

Acceptance:

1. Capture pre-change header and sidebar at known scale/OS. Render reference-sized and
   minimum-width windows, light/dark, sidebar open/collapsed, inactive, and full-screen.
2. Compare cropped header regions at equal scale: group bounds/gaps, shared centerline,
   capsule height/width, text centering, and separation from content. Aim within about
   2 normalized pixels for custom geometry; list native-system differences separately.
3. Test Cmd-L/full URL selection, click-to-edit, Return navigation/search, Escape, blur,
   copy/paste, long URLs, unusual ports, empty/new tab, loading callbacks during edits,
   tab switches, disabled history, and in-field reload/Cmd-R. Add focused tests for any
   new URL-display/draft logic; do not change the shared resolution rules silently.
4. Verify sidebar space menus/editors/themes still work and look unchanged. Sidebar
   themes must not leak into the header. Recheck native window dragging and shortcuts.
5. Run build, tests, and layer guard. Provide actual screenshots and remaining visual/
   functional differences. A passing build alone is not evidence of Safari matching.

No source changes or worker assignment are authorized by this document alone. The
coordinator must explicitly release the current header freeze for a later task.
