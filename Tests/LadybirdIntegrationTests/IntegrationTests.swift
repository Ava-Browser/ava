/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Links the engine (so it needs the shim dylib) but never starts it: these are pure conversions and pure bookkeeping.
 */

import Foundation
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

@Suite("Workspace persistence")
@MainActor
struct WorkspacePersistenceTests {
    private func temporaryStore() -> GraphStore {
        GraphStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json"))
    }

    @Test("Two spaces and five tabs restore with their tiers, order and active selection")
    func graphRoundTrip() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let manager = WorkspaceManager(store: store)
        let first = manager.createWorkspace(name: "Personal", icon: "house.fill")
        let essential = try #require(manager.createTab(tier: .essential, url: "https://mail.example"))
        let pinned = try #require(manager.createTab(tier: .pinned, url: "https://docs.example"))
        let personalSelected = try #require(manager.createTab(tier: .normal, url: "https://one.example"))

        let second = manager.createWorkspace(name: "Work", icon: "briefcase.fill")
        let workPinned = try #require(manager.createTab(tier: .pinned, url: "https://issues.example"))
        let selected = try #require(manager.createTab(tier: .normal, url: "https://build.example"))
        manager.selectTab(selected.id)

        let restored = WorkspaceManager(store: store)
        #expect(restored.workspaces.map(\.name) == ["Personal", "Work"])
        #expect(restored.activeSpaceID == second.id)
        #expect(restored.activeTabID == selected.id)
        #expect(restored.tabs(in: .essential).map(\.id) == [essential.id])
        restored.selectWorkspace(first.id)
        #expect(restored.activeTabID == personalSelected.id)
        #expect(restored.tabs(in: .pinned).map(\.id) == [pinned.id])
        #expect(restored.tabs(in: .normal).count == 1)
        restored.selectWorkspace(second.id)
        #expect(restored.tabs(in: .pinned).map(\.id) == [workPinned.id])
        #expect(restored.tabs(in: .normal).map(\.id) == [selected.id])
    }

    @Test("Restored descriptors start unloaded until selected with an engine")
    func restoredTabsAreLazy() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let manager = WorkspaceManager(store: store)
        _ = manager.createWorkspace(name: "Only")
        _ = try #require(manager.createTab(tier: .pinned, url: "https://one.example"))
        _ = try #require(manager.createTab(tier: .normal, url: "https://two.example"))

        let model = BrowserModel(store: store)
        #expect(model.tabs.count == 2)
        #expect(model.tabs.allSatisfy { !$0.isLoaded })
        #expect(model.selectedTab?.currentURL == "https://two.example")
    }

    @Test("An unreadable graph is preserved before fresh state can replace it")
    func unreadableGraphIsBackedUp() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let broken = Data("not json".utf8)
        try broken.write(to: store.url)

        _ = WorkspaceManager(store: store)

        #expect(try Data(contentsOf: store.url.appendingPathExtension("unreadable")) == broken)
    }

    @Test("Retiering writes through immediately")
    func retierWritesThrough() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let manager = WorkspaceManager(store: store)
        _ = manager.createWorkspace(name: "Only")
        let tab = try #require(manager.createTab(tier: .normal))
        manager.retier(tab.id, to: .pinned)

        let restored = WorkspaceManager(store: store)
        #expect(restored.tabs(in: .normal).isEmpty)
        #expect(restored.tabs(in: .pinned).map(\.id) == [tab.id])
    }
}

@Suite("Runtime teardown")
@MainActor
struct RuntimeTeardownTests {
    private func temporaryStore() -> GraphStore {
        GraphStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json"))
    }

    @Test("Closing with no engine and no tab is a no-op")
    func closeWithoutEngine() {
        let model = BrowserModel(store: temporaryStore())
        model.closeSelectedTab()
        #expect(model.tabs.isEmpty)
        #expect(model.selectedTabID == nil)
    }

    /// Shutdown clears only the disposable engine cache. The descriptor graph is the durable source of truth and must
    /// survive applicationWillTerminate — clearing it here would make quit itself erase the next launch.
    @Test("Shutdown without a running engine preserves the durable graph")
    func shutdownWithoutEnginePreservesGraph() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let manager = WorkspaceManager(store: store)
        _ = manager.createWorkspace(name: "Only")
        let tab = try #require(manager.createTab(url: "https://example.com"))

        let model = BrowserModel(store: store)
        model.shutdown()

        #expect(model.selectedTabID == tab.id)
        #expect(model.tabs.map(\.id) == [tab.id])
        #expect(model.tabs.allSatisfy { !$0.isLoaded })
    }
}
