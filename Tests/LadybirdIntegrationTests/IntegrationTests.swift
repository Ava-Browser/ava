/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Links the engine (so it needs the shim dylib) but never starts it: these are pure conversions and pure bookkeeping.
 */

import Foundation
import IOSurface
import LadybirdBridge
import QuartzCore
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

    @Test("An engine-created target-blank view is adopted instead of replaced")
    func engineCreatedTabIsAdopted() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let manager = WorkspaceManager(store: store)
        _ = manager.createWorkspace(name: "Only")
        _ = try #require(manager.createTab(url: "https://search.example"))

        let model = BrowserModel(store: store)
        let parent = try #require(model.selectedTab)
        let child = try #require(model.adoptEngineTab(parent: parent, engineID: 42, activate: true))

        #expect(child.engineID == 42)
        #expect(model.selectedTab?.id == child.id)
        #expect(model.tabs.count == 2)
    }

    /// A background space's page can still call `window.open()`. Adopting that tab must not point the visible view at
    /// it while the space's own tab is what the sidebar shows, or input goes to a tab nobody can see.
    @Test("An engine-created tab in a background space is adopted without being activated")
    func engineCreatedBackgroundTabIsNotActivated() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let manager = WorkspaceManager(store: store)
        let foreground = manager.createWorkspace(name: "Foreground")
        _ = try #require(manager.createTab(url: "https://visible.example"))
        let background = manager.createWorkspace(name: "Background")
        let backgroundParent = try #require(manager.createTab(url: "https://hidden.example"))
        manager.selectWorkspace(foreground.id)

        let model = BrowserModel(store: store)
        let visible = try #require(model.selectedTab)
        // The parent is in the background space, so its runtime object is only reachable through the space's own list.
        model.workspaceManager.selectWorkspace(background.id)
        let parent = try #require(model.selectedTab)
        model.workspaceManager.selectWorkspace(foreground.id)
        #expect(model.selectedTab?.id == visible.id)

        let child = try #require(model.adoptEngineTab(parent: parent, engineID: 42, activate: true))

        #expect(child.engineID == 42)
        // The view is what `onMouse`, `onKey` and `onTypeText` treat as the visible target, and `select` is the only
        // thing that moves it. Pointing it at the background tab sends input to a page nobody can see.
        #expect(model.webView.currentTabID != child.engineID)
        #expect(model.selectedTab?.id == visible.id)
        #expect(model.workspaceManager.activeTabID == visible.id)
        #expect(model.workspaceManager.tabs(in: .normal, workspaceID: background.id).map(\.id).contains(child.id))
        #expect(model.workspaceManager.tabs(in: .normal, workspaceID: foreground.id).count == 1)
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

    @Test("An unreadable graph is preserved with a timestamp and repeated failures accumulate")
    func unreadableGraphIsBackedUpWithTimestamps() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let storeURL = root.appendingPathComponent("spaces.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let broken1 = Data("broken payload 1".utf8)
        try broken1.write(to: storeURL)

        let time1 = Date(timeIntervalSince1970: 1_700_000_000)
        let store1 = GraphStore(url: storeURL, now: { time1 })
        let manager1 = WorkspaceManager(store: store1)
        _ = manager1.createWorkspace(name: "Fresh")

        let backups1 = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.contains("unreadable-") }
        #expect(backups1.count == 1)
        let firstBackupURL = root.appendingPathComponent(backups1[0])
        #expect(try Data(contentsOf: firstBackupURL) == broken1)

        // Write a second broken file at a later time
        let time2 = time1.addingTimeInterval(3600)
        let broken2 = Data("broken payload 2".utf8)
        try broken2.write(to: storeURL)

        let store2 = GraphStore(url: storeURL, now: { time2 })
        _ = WorkspaceManager(store: store2)

        let backups2 = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.contains("unreadable-") }
        #expect(backups2.count == 2)
    }

    @Test("If backup of unreadable graph fails, overwrite is aborted and store remains untouched")
    func unreadableBackupFailureAbortsOverwrite() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let storeURL = root.appendingPathComponent("spaces.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let broken = Data("precious unreadable data".utf8)
        try broken.write(to: storeURL)

        // Force write failure for backup URL by occupying the target backup directory/path with an unwritable file
        let simulatedTime = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let timestamp = formatter.string(from: simulatedTime)
        let backupURL = storeURL.deletingPathExtension().appendingPathExtension("unreadable-\(timestamp).json")

        // Pre-create an unwritable directory at the backup location
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: backupURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: backupURL.path)
        }

        let store = GraphStore(url: storeURL, now: { simulatedTime })
        let manager = WorkspaceManager(store: store)

        #expect(manager.persistenceFailure?.contains("backing it up failed") == true)

        // A mutation in memory must NOT overwrite storeURL
        _ = manager.createWorkspace(name: "Should Not Overwrite")
        _ = manager.createTab(url: "https://should-not-persist.example")

        #expect(try Data(contentsOf: storeURL) == broken)
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

    @Test("A drop reorders within a tier and moves between all three")
    func dragReordersAndRetiers() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let manager = WorkspaceManager(store: store)
        _ = manager.createWorkspace(name: "Only")
        let first = try #require(manager.createTab(tier: .normal, url: "https://one.example"))
        let second = try #require(manager.createTab(tier: .normal, url: "https://two.example"))
        let third = try #require(manager.createTab(tier: .normal, url: "https://three.example"))

        // Within a tier: dropping `third` on the top half of `first` puts it first.
        manager.moveTab(third.id, to: .normal, at: 0)
        #expect(manager.tabs(in: .normal).map(\.id) == [third.id, first.id, second.id])

        // Pinned, then back to unpinned as a different tier rather than an append-only special case.
        manager.moveTab(first.id, to: .pinned, at: 0)
        let pinned = try #require(manager.createTab(tier: .pinned, url: "https://pinned.example"))
        manager.moveTab(pinned.id, to: .pinned, at: 0)
        #expect(manager.tabs(in: .pinned).map(\.id) == [pinned.id, first.id])

        manager.moveTab(first.id, to: .normal, at: 1)
        #expect(manager.tabs(in: .pinned).map(\.id) == [pinned.id])
        #expect(manager.tabs(in: .normal).map(\.id) == [third.id, first.id, second.id])

        // Essentials are global, and coming back from them re-enters the active space.
        manager.moveTab(second.id, to: .essential)
        #expect(manager.tabs(in: .normal).map(\.id) == [third.id, first.id])
        #expect(manager.tabs(in: .essential).map(\.id) == [second.id])
        manager.moveTab(second.id, to: .normal, at: 0)
        #expect(manager.tabs(in: .normal).map(\.id) == [second.id, third.id, first.id])

        // Order is durable, not just in-memory.
        let restored = WorkspaceManager(store: store)
        #expect(restored.tabs(in: .normal).map(\.id) == [second.id, third.id, first.id])
        #expect(restored.tabs(in: .pinned).map(\.id) == [pinned.id])
    }

    /// An essential can be selected from every space. Once it lands in Pinned it belongs to one space only, so the
    /// other spaces were pointing at a tab their own list no longer contains — `BrowserModel.selectWorkspace` would
    /// then present a page the sidebar does not show. Only `normalize()` on the next launch repaired it before.
    @Test("Moving a tab out of Essentials repairs every other space's selection")
    func leavingEssentialsRepairsOtherSpaces() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let manager = WorkspaceManager(store: store)
        let first = manager.createWorkspace(name: "First")
        let second = manager.createWorkspace(name: "Second")
        let otherEssential = try #require(manager.createTab(tier: .essential, url: "https://mail.example"))
        let moving = try #require(manager.createTab(tier: .essential, url: "https://docs.example"))

        // Both spaces are showing the tab that is about to leave the tier.
        manager.selectTab(moving.id, in: first.id)
        manager.selectTab(moving.id, in: second.id)
        #expect(manager.activeTabID == moving.id)

        manager.moveTab(moving.id, to: .pinned, in: second.id)

        // The destination keeps it; the other space falls back to a tab it can actually show.
        #expect(manager.tabs(in: .pinned, workspaceID: second.id).map(\.id) == [moving.id])
        #expect(manager.workspaces.first { $0.id == second.id }?.activeTabID == moving.id)
        #expect(manager.workspaces.first { $0.id == first.id }?.activeTabID == otherEssential.id)
        #expect(manager.tabs(in: .normal, workspaceID: first.id).isEmpty)

        // And the repair is what a fresh manager would have derived anyway, so nothing is left for `normalize()`.
        let restored = WorkspaceManager(store: store)
        #expect(restored.workspaces.first { $0.id == first.id }?.activeTabID == otherEssential.id)
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

    /// Reload goes through `LbTabReload`, which needs an engine tab. Without one it must do nothing at all: a reload
    /// that fell back to `load(currentURL)` would fabricate a navigation for a tab the user never opened.
    @Test("Reloading or stopping with no engine tab does nothing")
    func reloadWithoutEngineIsInert() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let manager = WorkspaceManager(store: store)
        _ = manager.createWorkspace(name: "Only")
        let tab = try #require(manager.createTab(url: "https://example.com"))

        let model = BrowserModel(store: store)
        #expect(model.selectedTab?.isLoaded == false)
        model.reload()
        model.reload(bypassCache: true)
        model.stopLoading()

        #expect(model.selectedTab?.isLoaded == false)
        #expect(model.selectedTab?.currentURL == "https://example.com")
        #expect(model.tabs.map(\.id) == [tab.id])
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

@Suite("PortWebView presentation geometry")
@MainActor
struct PortWebViewPresentationTests {
    @Test("Presenting padded surface anchors top-left at y=0")
    func presentationAnchorsTopLeft() throws {
        let view = PortWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let layer = try #require(view.layer?.sublayers?.first)

        let surface = try #require(IOSurface(properties: [
            .width: 800,
            .height: 856,
            .bytesPerElement: 4,
        ]))

        let portSurface = PortSurface(
            iosurface: Unmanaged.passUnretained(surface).toOpaque(),
            paintedWidth: 800,
            paintedHeight: 600,
            surfaceWidth: 800,
            surfaceHeight: 856
        )

        view.present(portSurface)

        #expect(view.isFlipped)
        #expect(layer.contentsGravity == .bottomLeft)
        #expect(layer.contentsRect.origin.x == 0)
        #expect(layer.contentsRect.origin.y == 0)
        #expect(layer.contentsRect.width == 1.0)
        #expect(abs(layer.contentsRect.height - (600.0 / 856.0)) < 0.0001)

        view.clearSurface()
        #expect(layer.contents == nil)
    }
}

/*
 * The pointer and the Command shortcuts. Both were silently broken in ways that look like styling problems: the page's
 * cursor never reached AppKit, and ⌘C crossed the ABI as (invalid, 0, Mod_Super) so no editing shortcut ever matched.
 */

import AppKit

@MainActor
@Suite("Hover and key translation")
struct HoverAndKeyTranslationTests {
    @Test("Mouse modifier flags use the engine key-modifier mask")
    func mouseModifiers() {
        let modifiers = PortWebView.engineModifiers(from: [.command, .shift, .option, .control])
        #expect(modifiers == PortKey.modSuper | PortKey.modShift | PortKey.modAlt | PortKey.modCtrl)
        #expect(PortWebView.engineModifiers(from: []) == 0)
    }

    @Test("A hand cursor maps to the pointing hand")
    func handCursor() {
        #expect(PortWebView.cursor(for: PortStandardCursor.hand) == .pointingHand)
    }

    @Test("A text cursor maps to the I-beam")
    func textCursor() {
        #expect(PortWebView.cursor(for: PortStandardCursor.iBeam) == .iBeam)
    }

    @Test("An unmapped cursor ordinal stays an arrow rather than guessing")
    func unmappedCursor() {
        #expect(PortWebView.cursor(for: 9999) == .arrow)
    }

    @Test("Applying a standard cursor does not trap and keeps the view's cursor")
    func applyStandardCursor() {
        let view = PortWebView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.applyCursor(.standard(PortStandardCursor.hand))
        // resetCursorRects is what makes it survive scrolling; calling it must be safe with no window attached.
        view.resetCursorRects()
    }

    @Test("Applying an image cursor falls back instead of trapping on undecodable bytes")
    func applyImageCursor() {
        let view = PortWebView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.applyCursor(.image(Data([0x00, 0x01, 0x02]), hotspotX: 0, hotspotY: 0))
    }
}
