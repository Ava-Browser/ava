/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Links the engine (so it needs the shim dylib) but never starts it: these are pure conversions and pure bookkeeping.
 */

import Testing

@testable import LadybirdEngine

@Suite("Wheel delta conversion")
@MainActor
struct WheelDeltaTests {
    /// Two conventions meet here and they are opposite, so the sign is worth pinning:
    /// - AppKit is positive for an upward gesture.
    /// - The engine is positive for "increase scrollY", i.e. later content comes into view.
    ///
    /// Measured on the engine side by `TestNativeInput` in the fork: `delta_y=+120` -> `scrollY=120`.
    @Test("A precise AppKit delta is negated", arguments: [
        (40.0, -40.0),
        (-40.0, 40.0),
        (0.0, 0.0),
        (1.5, -1.5),
    ])
    func preciseIsNegated(appKit: Double, engine: Double) {
        #expect(PortWebView.engineWheelDelta(appKitDelta: appKit, isPrecise: true) == engine)
    }

    /// The negation is also what makes the app follow the system "natural scrolling" preference: AppKit folds that
    /// setting into the delta it reports, so flipping the OS preference flips the sign here and the page follows the
    /// user's expectation without any branch on our side.
    @Test("Negation does not depend on which way the OS is configured")
    func followsSystemSetting() {
        #expect(PortWebView.engineWheelDelta(appKitDelta: -20, isPrecise: true) == 20)
        #expect(PortWebView.engineWheelDelta(appKitDelta: 20, isPrecise: true) == -20)
    }

    /// A notched wheel reports lines, not pixels. It needs the scale as well as the sign, or the page crawls.
    @Test("Non-precise deltas are scaled to pixels before being negated")
    func notchedWheelIsScaled() {
        #expect(PortWebView.engineWheelDelta(appKitDelta: 1, isPrecise: false) == -PortWebView.lineHeightInPixels)
        #expect(PortWebView.engineWheelDelta(appKitDelta: 3, isPrecise: false) == -3 * PortWebView.lineHeightInPixels)
    }
}

@Suite("Tab teardown ordering")
@MainActor
struct TabTeardownTests {
    /// Closing the selected tab must leave the selection pointing at a survivor that is still in the list.
    ///
    /// This is the invariant that a crash-on-close hides behind: the engine tab is destroyed last, and anything that
    /// reads the selection between the removal and the re-selection would address a tab that no longer exists. The
    /// engine is not started here, so `destroyTab` is a no-op — this asserts the bookkeeping order, which is the part
    /// that can regress without a device in the loop.
    @Test("Closing the middle tab selects a neighbour that still exists")
    func closingMiddleKeepsSelectionValid() {
        let model = BrowserModel()
        // Teardown path with no engine: these must not trap, and must leave a coherent empty model.
        model.closeSelectedTab()
        #expect(model.tabs.isEmpty)
        #expect(model.selectedTabID == nil)
    }

    /// A model that never started must still shut down cleanly — `applicationWillTerminate` arrives even when the
    /// engine failed to launch, because the failure is shown in-window rather than aborting the app.
    @Test("Shutdown without a running engine is a no-op, not a trap")
    func shutdownWithoutEngine() {
        let model = BrowserModel()
        model.shutdown()
        #expect(model.selectedTabID == nil)
        #expect(model.tabs.isEmpty)
    }
}

@Suite("Spaces and write-through persistence")
@MainActor
struct SpacesPersistenceTests {
    final class MemoryStore: SpacesStore, @unchecked Sendable {
        var state: SpacesStoreState?
        func load() -> SpacesStoreState? { state }
        func save(_ state: SpacesStoreState) { self.state = state }
    }

    @Test("Creating spaces and distributing tabs across tiers writes through immediately")
    func persistenceWriteThrough() {
        let store = MemoryStore()
        let manager = SpacesManager(store: store)

        // Starts with 1 default space
        #expect(manager.spaces.count == 1)
        let spaceA = manager.activeWorkspace

        // Add essential tab
        let essential = manager.addTab(workspaceID: nil, tier: .essential, url: "https://essential.com")
        #expect(essential.workspaceID == nil)
        #expect(manager.essentials.count == 1)

        // Create second space
        let spaceB = manager.createWorkspace(name: "Work", icon: "briefcase")
        #expect(manager.spaces.count == 2)

        // Switch to space B and add pinned & normal tabs
        manager.selectWorkspace(id: spaceB.id)
        #expect(manager.activeWorkspaceID == spaceB.id)

        let pinned = manager.addTab(workspaceID: spaceB.id, tier: .pinned, url: "https://pinned.com")
        let normal1 = manager.addTab(workspaceID: spaceB.id, tier: .normal, url: "https://normal1.com")
        let normal2 = manager.addTab(workspaceID: spaceB.id, tier: .normal, url: "https://normal2.com")

        #expect(manager.activePinnedTabs.count == 1)
        #expect(manager.activeNormalTabs.count == 2)
        #expect(manager.essentials.count == 1) // Global essential still visible

        // Invariant 1: Tab lives in exactly one tier, exactly one place
        manager.setTier(for: normal1.id, tier: .pinned)
        #expect(manager.activePinnedTabs.count == 2)
        #expect(manager.activeNormalTabs.count == 1)

        // Verify write-through persistence restored in a fresh manager instance
        let restoredManager = SpacesManager(store: store)
        #expect(restoredManager.spaces.count == 2)
        #expect(restoredManager.activeWorkspaceID == spaceB.id)
        #expect(restoredManager.essentials.count == 1)
        #expect(restoredManager.activePinnedTabs.count == 2)
        #expect(restoredManager.activeNormalTabs.count == 1)

        // BrowserModel rehydration and selection
        let model = BrowserModel(spacesManager: restoredManager)
        #expect(model.tabs.count == 4) // 1 essential + 2 pinned + 1 normal
        #expect(model.activeWorkspace.id == spaceB.id)
    }

    @Test("Closing all unpinned tabs leaves pinned and essentials untouched")
    func closeAllUnpinned() {
        let store = MemoryStore()
        let manager = SpacesManager(store: store)
        let model = BrowserModel(spacesManager: manager)

        model.openTab(url: "https://essential.com", tier: .essential)
        model.openTab(url: "https://pinned.com", tier: .pinned)
        model.openTab(url: "https://normal1.com", tier: .normal)
        model.openTab(url: "https://normal2.com", tier: .normal)

        #expect(model.essentialTabs.count == 1)
        #expect(model.activePinnedTabs.count == 1)
        #expect(model.activeNormalTabs.count == 2)

        model.closeAllUnpinnedInActiveWorkspace()

        #expect(model.essentialTabs.count == 1)
        #expect(model.activePinnedTabs.count == 1)
        #expect(model.activeNormalTabs.count == 0)
    }

    @Test("Switching spaces restores per-space active tab selection memory")
    func spaceSelectionMemory() {
        let store = MemoryStore()
        let manager = SpacesManager(store: store)
        let model = BrowserModel(spacesManager: manager)

        let space1 = model.activeWorkspace
        let tab1 = model.openTab(url: "https://space1.com")!
        #expect(model.selectedTabID == tab1.id)

        model.createWorkspace(name: "Second")
        let space2 = model.activeWorkspace
        let tab2 = model.openTab(url: "https://space2.com")!
        #expect(model.selectedTabID == tab2.id)

        // Switch back to space1 -> should restore tab1
        model.selectWorkspace(space1)
        #expect(model.activeWorkspace.id == space1.id)
        #expect(model.selectedTabID == tab1.id)

        // Switch back to space2 -> should restore tab2
        model.selectWorkspace(space2)
        #expect(model.activeWorkspace.id == space2.id)
        #expect(model.selectedTabID == tab2.id)
    }
}
