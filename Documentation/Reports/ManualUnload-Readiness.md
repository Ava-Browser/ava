# Manual Inactive Workspace Unload — Readiness and Handoff Report

**Status:** Handoff checkpoint reached prior to implementation by coordinator directive (budget cap); worktree is clean of source modifications.
**Task:** `task_50f0a3eead6e` (Dispatch `ctx_cbd12551e788`)
**Reference:** [TDD-Spaces.md](../TDD-Spaces.md) (Milestone 6: Manual Inactive Workspace Unload slice)

---

## Executive Summary

Investigation completed into the runtime tab lifecycle, durable graph storage, and space context menu integration. The app-side architecture is already well-aligned for manual unload: `BrowserTab` already provides `detach()`, `BrowserModel` already supports lazy rehydration on activation, and `WorkspaceManager` maintains durable tab descriptors independently of disposable engine handles. No new source code, builds, or process launches were executed per the coordinator handoff directive.

---

## Architectural Findings

1. **Tab Runtime State (`Sources/LadybirdEngine/BrowserTab.swift`):**
   - `BrowserTab` exposes `public private(set) var engineID: UInt64?`.
   - `detach()` already exists on `BrowserTab`: it resets `engineID = nil`, `isLoading = false`, and `dialog = nil`.
   - Selecting an unloaded tab (`engineID == nil`) in `BrowserModel.select(_:force:)` already routes through `rehydrate(_:)`, which calls `app.createTab()`, `tab.attach(engineID:)`, and re-navigates `tab.currentURL`.

2. **Required Engine Primitives (`Sources/LadybirdEngine/BrowserModel.swift`):**
   - `unloadTab(_ tab: BrowserTab) -> Bool`:
     - Reject if `tab.id == selectedTabID` (currently displayed tab) or if `tab.engineID == nil` (already unloaded).
     - Answer pending dialogs (`answerPendingDialog(on: tab)`) to prevent engine hangs.
     - Remove handle from `engineToTab` lookup before destroying.
     - Call `app?.destroyTab(engineID)`.
     - Call `tab.detach()`.
     - Retain `runtimeTabs[tab.id]` and do not modify the `workspaceManager` descriptor (URL, title, tier, and order survive untouched).
   - `unloadWorkspace(_ workspace: Workspace) -> Bool`:
     - Reject if `workspace.id == selectedWorkspaceID` (active workspace cannot be unloaded).
     - Query workspace tabs via `workspaceManager.tabs(in: workspace.id)`.
     - Filter strictly to tabs belonging to this space (`descriptor.workspaceID == workspace.id`); never touch global Essentials (`workspaceID == nil`) or other spaces.
     - Invoke `unloadTab` on each loaded tab in the space.

3. **UI & Confirmation (`Sources/LadybirdUI/SpaceSettingsViews.swift`):**
   - Extend `SpaceContextMenu` (shared by `TabSidebar` header and `SpaceDock` capsule):
     - Add an "Unload Inactive Tabs" action.
     - Disable when `workspace.id == model.selectedWorkspaceID` or when the workspace has no currently loaded tabs.
     - Wire an explicit confirmation alert warning that unloading discards live page/form state while preserving tab links.
     - Dismissing / Canceling the alert performs a no-op.

4. **Engine / Process Constraints & Disclosures:**
   - History and exact scroll position restore are unavailable in Ladybird's C ABI / WebContent session APIs; rehydrating a tab performs a fresh navigation to `currentURL`. This limitation is documented in `TDD-Spaces.md` M6.
   - Process reclamation verification requires scoping `ps` descendant queries to Ava's own bundle PID and accounting for shared helper pools.

---

## Next Steps for Implementer

1. Add `unloadTab(_:)` and `unloadWorkspace(_:)` with guard checks on `@MainActor BrowserModel`.
2. Update `SpaceContextMenu` and add a confirmation presentation state in `SpaceActionState` / `SpaceSettingsViews.swift`.
3. Add unit tests in `Tests/LadybirdIntegrationTests/` using an isolated `tempGraphStore`:
   - Verify active workspace unload rejection.
   - Verify inactive workspace tab detachment without descriptor loss (IDs, titles, URLs, and ordering preserved in JSON graph).
   - Verify global Essentials and unrelated spaces remain untouched.
   - Verify rehydration on subsequent selection.
4. Execute layer checks (`Scripts/check-layers.sh`) and Swift test suite using the shared read-only engine build tree (`Extern/ladybird/Build/release/lib`).
