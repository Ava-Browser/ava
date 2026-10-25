# TDD: Arc-reference sidebar and space settings

**Status:** Approved for implementation · **Implementation owner:** ava-dev
**Scope:** Working space settings first, pixel-close surrounding sidebar second.
Read `Architecture.md` → `Rules.md` → `Traps.md` → `TDD-Spaces.md` before this document.
This supplements, rather than replaces, the durable-graph design in `TDD-Spaces.md`.

## 1. Product constraint: preserve Ava's header

Ava keeps its Safari-like URL/header experience. Arc is the reference for the sidebar
**below** that header, not for the toolbar, address field, navigation controls, or traffic
lights. Do not add Arc's address field to the sidebar.

Protected: `BrowserWindow`'s `.toolbar` block, address focus/submission, URL shortcuts,
back/forward/reload, toolbar new-tab action, native window controls, window drag behavior,
and page presentation. Changes in `BrowserWindow` are limited to sidebar composition,
sidebar-local editor presentation state, and sidebar width. Theme changes must not tint
the header or web content. No engine-fork, bridge, event-loop, or container-session work.

## 2. Reference captures and measurement limits

User-provided local inputs:

- A (999 × 674): active-space row context menu.
  `/var/folders/02/l1xpyx6x5b9g5zq8y9l9n27m0000gn/T/orca-paste-1792930194834-e901c873-fe48-4a53-a6f7-b5556c80b186.png`
- B (1011 × 1322): menu opened from bottom space dock.
  `/var/folders/02/l1xpyx6x5b9g5zq8y9l9n27m0000gn/T/orca-paste-1792930213789-b666d56f-5709-4e52-b932-1367be95220a.png`
  Arc ends around y=1080; the Orca window below it is NOT a design reference.

These paths are local implementation inputs, not public assets. Do not commit the raw
captures: they contain unrelated browsing/application information. If they disappear,
request them again rather than reconstructing Arc from memory.

Estimates in screenshot pixels, provisionally treated as 1 pixel per layout point:

| Element | Observed estimate |
| --- | --- |
| Sidebar width | A: 227 px; B: 241 px |
| Sidebar leading content inset | 8 px |
| Essentials tile | 48 px square; 8 px gaps |
| Active-space row | about 36 px tall |
| Selected normal-tab row | about 36 px tall; 12 px corner radius |
| Context menu | about 234 px wide; roughly 24 px item spacing |

Capture scale is not established. Normalize before comparing, record backing scale/OS/
appearance, and adjust custom spacing against the images. These are starting estimates,
not Arc API constants. Native menus own their metrics; do not draw fake macOS menus.

## 3. Existing implementation and change surface

- `Workspace`: UUID, name, icon string, `GradientSpec`, dormant `containerID`, selected tab,
  ordered tab IDs. All needed metadata already exists; no schema change is required.
- `WorkspaceManager`: write-through `GraphStore`, create/select/rename, tabs/retier/close.
  Missing: validated metadata updates, workspace reorder/delete.
- `BrowserModel`: runtime tab cache, pending-dialog handling, selection/surface routing,
  engine-handle destruction. Space deletion MUST go through this runtime coordinator.
- `TabSidebar`: generic List section headings and titled Essential tiles; needs the
  reference's compact hierarchy and active-space settings entry point.
- `SpaceDock`: existing switch/create controls; lacks space context menus.
- Tests: `Tests/LadybirdIntegrationTests`; temporary `GraphStore` pattern already exists.

Inspect every caller of mutations being changed. Expected edits: those files, small
shared menu/editor/icon views in `LadybirdUI`, and focused model tests. UI stays SwiftUI;
no AppKit imports in UI/Bridge, no C ABI imports in UI, no new dependency/framework.

## 4. One space-settings menu, three entry points

One small shared SwiftUI menu-content view, keyed by **workspace UUID**, opens from:

1. Active-space row's trailing ellipsis, by normal click/keyboard.
2. Right-click on the active-space row.
3. Right-click on ANY dock space icon, targeting THAT space without selecting it or
   changing the current page first.

Match reference wording, ordering, and separator groups:

| Group | Item | Current slice |
| --- | --- | --- |
| Identity | Change Space Icon… | Working icon editor |
| | Rename Space… | Working name editor |
| | Edit Theme Color… | Working theme editor |
| | Set Profile | Disabled |
| Structure | New Folder | Disabled |
| | Live Folders | Disabled |
| Sharing | Share Space… | Disabled |
| | Export “<space name>” into Folder | Disabled |
| Management | Manage Spaces… | Working manager |
| Destructive | Delete Space | Working confirmation; disabled for final space |

Separate each group with native separators. Arc shows submenu arrows for profile/live
folders/export; do not invent fake submenus or enabled no-op actions to copy arrows.
Disabled actions are an explicit interim difference. Profiles, folders, sharing, export,
and storage isolation are NOT implemented by this work. Do not imply dormant
`containerID` is a working profile boundary.

Use native `Menu`/`contextMenu` behavior for keyboard navigation, focus, dismissal,
hover, screen-edge repositioning, materials, and shadow. No custom menu overlay.

## 5. Space settings behavior

### Rename

Prefill/select current text. Trim surrounding whitespace/newlines; reject blank names
without a write. Duplicate names are allowed; identity is UUID. Return/Save commits once;
Escape/Cancel preserves both model and stored bytes. Re-resolve target UUID on commit.

### Icon

Offer a small curated SF Symbols grid plus a single-emoji input, using the existing
`Workspace.icon` string. Preserve existing icons. Validate input before Save; Cancel is
non-mutating. Dock and active-space row use one icon renderer. Fix the current
`contains(".")` heuristic: valid symbol names need not contain a dot. A small known-symbol
set for offered icons plus explicit emoji validation is enough; no icon package/catalog.

### Theme

Reuse `GradientSpec.startHex/endHex` and the existing palette. Show a preview with
explicit Save/Cancel; native color pickers may edit the two endpoints. Any color
serialization/validation belongs in one place, with a small test if nontrivial.
Apply a soft theme tint to the sidebar/dock only. Labels must remain readable in light/
dark, increased contrast, and reduced transparency. Do not override the system control
accent globally, recolor the header, or add elaborate mesh gradients.

### Manage Spaces

Use a short window-attached management sheet, not a new global Settings architecture.
List actual spaces in dock order; support select/edit, create, reorder, and delete using
the same actions/editors. Reorder preserves UUIDs, tabs, selected workspace, per-space
selected tabs, and container fields. Include keyboard move-up/down alongside drag reorder
if drag is provided. No search, profile manager, or folder management.

### Delete safely

Confirm with the target space name and consequence: its pinned/normal tabs close;
**global Essentials survive**. Cancel is the safe/default action. Reject deletion of the
final workspace in the model too, not only the menu. A stale target is a harmless no-op.

Inactive-space deletion does not change the active space/page. Active-space deletion
selects the next neighbor at the deleted index, or previous neighbor if deleting the
end, restoring the survivor's selection. Resolve pending dialogs and clear/rebind the
presented tab before destroying its handles. Remove only the deleted space's runtime
entries via `BrowserModel`; do not orphan engine tabs by only removing graph metadata.
Use existing close/selection primitives and handle-lifetime rules, not a second engine.

### Persistence and failures

Use validated `WorkspaceManager` mutations, not writes to copied Workspaces in views.
Keep editor drafts local until Save. Reuse `GraphStore` and its atomic JSON writes; keep
IDs, existing storage paths/schema, tab ordering, and unreadable-backup protection.
Surface `persistenceFailure` visibly in the space UI: existing manager policy keeps the
in-memory mutation on a save failure. Do not silently claim it was durably saved or add
a separate rollback/store layer. No unrequested migration or new persisted settings.

## 6. Surrounding sidebar fidelity

- Essentials: rounded icon-only tiles, no title captions; keep accessible names/help.
  Use real available imagery or existing fallbacks; never ship reference site icons as
  fake favicons. Report fallback differences rather than expanding into favicon plumbing.
- Remove the generic resting `Essentials` / `Pinned` / `Tabs` section-label treatment.
  Put a compact active-space row below Essentials: leading disclosure for a REAL
  collapsible pinned region, secondary-weight space name, trailing ellipsis available
  on hover/focus and reachable with keyboard/VoiceOver. Collapsing pinned tabs does not
  hide normal tabs or destroy handles. Disclosure state may be view-local in this slice.
- Divider and trailing `Clear`: use existing close-normal-tabs behavior only. Preserve
  pinned tabs, Essentials, and other spaces. `New Tab` uses the existing configured
  new-tab flow; keep the toolbar's plus button unchanged.
- Normal tabs: leading favicon/fallback, single-line title with trailing ellipsis,
  quiet hover and pale rounded selection (legible counterpart in dark/inactive mode).
  Preserve keyboard selection, contextual tier operations, and valid drag-retier drops.
- Empty tiers: no permanent "Drop a tab here" filler in the resting reference layout;
  retain accessible, real drop targets during dragging and useful empty-state actions.
- Dock stays bottom anchored with a few tabs. Keep real icons, selected treatment, and
  existing create affordance. Many spaces must overflow accessibly rather than clip.
- Keep native sidebar resize/collapse. Prefer ideal width near 240 pt; compare at roughly
  230–240 pt and existing narrow/wide bounds. Aim for custom spacing within approximately
  2 normalized pixels of the references. Record OS-controlled menu/material differences;
  never modify toolbar geometry to make the captures align.
- Honor reduced motion/transparency, increased contrast, inactive windows, light/dark,
  long names, keyboard focus, and accessible labels. No unrequested motion system.

## 7. Validation and handoff gates

### Model tests (isolated store; no second engine startup)

- Valid name/icon/theme changes round-trip in a fresh manager. Blank names and stale
  IDs do not corrupt the graph. Invalid editor inputs cannot reach persistence.
- Reorder round-trips with space/tab UUIDs, selected space, per-space selection,
  Essentials, pinned/normal order, and dormant container fields intact.
- Delete active/inactive, first/middle/last, final-space refusal, and Essentials survival.
  No deleted-space descriptors or dangling active selection remain.
- At least one failed-save path and existing unreadable-backup write protection cover
  new mutations. Cancelled edits/deletion preserve bytes (manual UI check if necessary).
- Runtime coordination without an engine where possible; manual active-page deletion
  checks handle cleanup/survivor presentation where model-only tests cannot.

### Visual and interactive checks

1. Before edits, capture Ava's unchanged-header baseline. Keep a hash/diff of the toolbar
   block; afterwards verify URL entry, Cmd-L, back/forward/reload, toolbar plus, and
   native sidebar collapse remain unchanged.
2. Capture resting sidebar, row menu, and dock menu at matched widths. Compare cropped
   sidebar/menu regions to A/B, not unrelated website pixels. Report numeric mismatches,
   backing scale, and remaining differences. Native OS differences must be explicit.
3. Inactive dock menu targets that space without switching page. Rename/icon/theme and
   reorder survive quit/relaunch. Confirm/cancel active and inactive space deletion;
   Essentials and unrelated loaded pages survive.
4. Check light/dark, narrow/wide sidebar, long names, empty tiers, many spaces, keyboard,
   VoiceOver labels, Escape/Cancel, reduced transparency, and increased contrast.
5. Run `swift build`, `swift test`, and Bash 4+ `Scripts/check-layers.sh`. If moving the
   checkout caused stale module-cache paths, use a fresh `--scratch-path` instead of
   deleting developer state. Report shared-engine-build provenance warnings honestly.

**Completion gate:** working settings, persistent model tests, before/after sidebar
screenshots, unchanged Safari-style header, and a list of measured remaining deviations.
If screenshot/UI tooling is unavailable, report visual verification as blocked; compilation
alone is not evidence of pixel parity.

## 8. Execution ownership

ava-dev is the sole implementation writer in the shared checkout. Preserve the pending
`.gitignore` edit. ava-ux is standing by, with no overlapping edits. Stop and ask the
coordinator if a design conflict needs broader scope, engine changes, a schema change,
or alterations to the header. Send a diff/test/screenshot report for review; do not commit,
push, change repository settings, or kill unrelated app/helper processes without approval.
