/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Tests for sidebar two-finger trackpad swipe classification, hit-testing scoping,
 * space navigation, and inline space rename behavior.
 */

import AppKit
import Foundation
import Testing

@testable import LadybirdEngine
@testable import LadybirdUI

final class TestScrollEvent: NSEvent, @unchecked Sendable {
    var testWindow: NSWindow?
    var testLocationInWindow: NSPoint = .zero
    var testPhase: NSEvent.Phase = []
    var testMomentumPhase: NSEvent.Phase = []
    var testScrollingDeltaX: CGFloat = 0
    var testScrollingDeltaY: CGFloat = 0
    var testIsPrecise: Bool = true

    override var window: NSWindow? { testWindow }
    override var locationInWindow: NSPoint { testLocationInWindow }
    override var phase: NSEvent.Phase { testPhase }
    override var momentumPhase: NSEvent.Phase { testMomentumPhase }
    override var scrollingDeltaX: CGFloat { testScrollingDeltaX }
    override var scrollingDeltaY: CGFloat { testScrollingDeltaY }
    override var hasPreciseScrollingDeltas: Bool { testIsPrecise }
    override var type: NSEvent.EventType { .scrollWheel }
}

@Suite("Sidebar trackpad swipe classifier")
struct SidebarSwipeClassifierTests {
    @Test("Leftward swipe exceeding threshold commits switch to next space on ended")
    func leftwardSwipeSwitchesNext() {
        var classifier = SidebarSwipeClassifier()

        let act1 = classifier.process(
            isPrecise: true, phase: .began, momentumPhase: [], deltaX: -15.0, deltaY: 0.0
        )
        #expect(act1 == .consume)
        #expect(classifier.state == .horizontalLocked(deltaX: -15.0))

        let act2 = classifier.process(
            isPrecise: true, phase: .changed, momentumPhase: [], deltaX: -30.0, deltaY: 1.0
        )
        #expect(act2 == .consume)
        #expect(classifier.state == .horizontalLocked(deltaX: -45.0))

        let act3 = classifier.process(
            isPrecise: true, phase: .ended, momentumPhase: [], deltaX: 0.0, deltaY: 0.0
        )
        #expect(act3 == .switchToNext)
        #expect(classifier.state == .idle)
    }

    @Test("Rightward swipe exceeding threshold commits switch to previous space on ended")
    func rightwardSwipeSwitchesPrevious() {
        var classifier = SidebarSwipeClassifier()

        let act1 = classifier.process(
            isPrecise: true, phase: .began, momentumPhase: [], deltaX: 20.0, deltaY: 0.0
        )
        #expect(act1 == .consume)

        let act2 = classifier.process(
            isPrecise: true, phase: .changed, momentumPhase: [], deltaX: 25.0, deltaY: 0.0
        )
        #expect(act2 == .consume)

        let act3 = classifier.process(
            isPrecise: true, phase: .ended, momentumPhase: [], deltaX: 0.0, deltaY: 0.0
        )
        #expect(act3 == .switchToPrevious)
        #expect(classifier.state == .idle)
    }

    @Test("Dominant vertical scroll locks to vertical pass-through and vertical cancellation passes through")
    func verticalScrollPassesThrough() {
        var classifier = SidebarSwipeClassifier()

        let act1 = classifier.process(
            isPrecise: true, phase: .began, momentumPhase: [], deltaX: 2.0, deltaY: -20.0
        )
        #expect(act1 == .passThrough)
        #expect(classifier.state == .verticalLocked)

        let act2 = classifier.process(
            isPrecise: true, phase: .changed, momentumPhase: [], deltaX: -50.0, deltaY: -15.0
        )
        #expect(act2 == .passThrough)

        // Vertical gesture cancellation must pass through rather than be consumed
        let actCancel = classifier.process(
            isPrecise: true, phase: .cancelled, momentumPhase: [], deltaX: 0.0, deltaY: 0.0
        )
        #expect(actCancel == .passThrough)
        #expect(classifier.state == .idle)
    }

    @Test("Traditional notched mouse wheel always passes through")
    func nonPreciseWheelPassesThrough() {
        var classifier = SidebarSwipeClassifier()

        let act = classifier.process(
            isPrecise: false, phase: [], momentumPhase: [], deltaX: -100.0, deltaY: 0.0
        )
        #expect(act == .passThrough)
        #expect(classifier.state == .idle)
    }

    @Test("Momentum scrolling events always pass through")
    func momentumPassesThrough() {
        var classifier = SidebarSwipeClassifier()

        let act = classifier.process(
            isPrecise: true, phase: [], momentumPhase: .changed, deltaX: -80.0, deltaY: 0.0
        )
        #expect(act == .passThrough)
        #expect(classifier.state == .idle)
    }

    @Test("Undecided gestures pass through until the horizontal axis locks")
    func undecidedGesturePassesThrough() {
        var classifier = SidebarSwipeClassifier()

        let began = classifier.process(
            isPrecise: true, phase: .began, momentumPhase: [], deltaX: 4.0, deltaY: 4.0
        )
        #expect(began == .passThrough)
        #expect(classifier.state == .tracking(deltaX: 4.0, deltaY: 4.0))

        let undecided = classifier.process(
            isPrecise: true, phase: .changed, momentumPhase: [], deltaX: 2.0, deltaY: 2.0
        )
        #expect(undecided == .passThrough)
        #expect(classifier.state == .tracking(deltaX: 6.0, deltaY: 6.0))

        let locked = classifier.process(
            isPrecise: true, phase: .changed, momentumPhase: [], deltaX: 4.0, deltaY: 0.0
        )
        #expect(locked == .consume)
        #expect(classifier.state == .horizontalLocked(deltaX: 10.0))
    }

    @Test("Small gestures below threshold do not switch spaces")
    func smallGestureDoesNotSwitch() {
        var classifier = SidebarSwipeClassifier()

        _ = classifier.process(isPrecise: true, phase: .began, momentumPhase: [], deltaX: -10.0, deltaY: 0.0)
        _ = classifier.process(isPrecise: true, phase: .changed, momentumPhase: [], deltaX: -10.0, deltaY: 0.0)
        let actEnd = classifier.process(isPrecise: true, phase: .ended, momentumPhase: [], deltaX: 0.0, deltaY: 0.0)

        #expect(actEnd == .consume)
        #expect(classifier.state == .idle)
    }

    @Test("Gesture reversal before ending does not switch spaces")
    func gestureReversalDoesNotSwitch() {
        var classifier = SidebarSwipeClassifier()

        _ = classifier.process(isPrecise: true, phase: .began, momentumPhase: [], deltaX: -20.0, deltaY: 0.0)
        _ = classifier.process(isPrecise: true, phase: .changed, momentumPhase: [], deltaX: -25.0, deltaY: 0.0)
        _ = classifier.process(isPrecise: true, phase: .changed, momentumPhase: [], deltaX: 35.0, deltaY: 0.0)

        let actEnd = classifier.process(isPrecise: true, phase: .ended, momentumPhase: [], deltaX: 0.0, deltaY: 0.0)
        #expect(actEnd == .consume)
        #expect(classifier.state == .idle)
    }

    @Test("Gesture does not begin tracking on changed event from idle")
    func noStartOnChangedFromIdle() {
        var classifier = SidebarSwipeClassifier()

        let act = classifier.process(
            isPrecise: true, phase: .changed, momentumPhase: [], deltaX: -50.0, deltaY: 0.0
        )
        #expect(act == .passThrough)
        #expect(classifier.state == .idle)
    }
}

@Suite("Sidebar space navigation and hit testing")
@MainActor
struct SidebarSpaceNavigationTests {
    private func temporaryStore() -> GraphStore {
        GraphStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json"))
    }

    @Test("selectNextWorkspace advances sequentially and stops at end without wrapping")
    func selectNextWorkspaceStopsAtEnd() {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let model = BrowserModel(store: store)
        let space1 = model.createWorkspace()
        let space2 = model.createWorkspace()
        let space3 = model.createWorkspace()

        model.selectWorkspace(space1)
        #expect(model.activeWorkspace?.id == space1.id)

        model.selectNextWorkspace()
        #expect(model.activeWorkspace?.id == space2.id)

        model.selectNextWorkspace()
        #expect(model.activeWorkspace?.id == space3.id)

        model.selectNextWorkspace()
        #expect(model.activeWorkspace?.id == space3.id)
    }

    @Test("selectPreviousWorkspace retreats sequentially and stops at beginning without wrapping")
    func selectPreviousWorkspaceStopsAtBeginning() {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let model = BrowserModel(store: store)
        let space1 = model.createWorkspace()
        let space2 = model.createWorkspace()

        model.selectWorkspace(space2)
        #expect(model.activeWorkspace?.id == space2.id)

        model.selectPreviousWorkspace()
        #expect(model.activeWorkspace?.id == space1.id)

        model.selectPreviousWorkspace()
        #expect(model.activeWorkspace?.id == space1.id)
    }

    @Test("SidebarSwipeTrackingView hit testing respects matching window and sidebar bounds")
    func hitTestRespectsMatchingWindowAndBounds() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let trackingView = SidebarSwipeTrackingView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        window.contentView?.addSubview(trackingView)

        var switchedNext = false
        var switchedPrev = false
        trackingView.onSwipeLeft = { switchedNext = true }
        trackingView.onSwipeRight = { switchedPrev = true }

        let event = TestScrollEvent()
        event.testWindow = window
        event.testLocationInWindow = NSPoint(x: 500, y: 300)
        event.testPhase = .began
        event.testScrollingDeltaX = -50

        let result = trackingView.handleScrollWheel(event)
        #expect(result === event)
        #expect(!switchedNext)
        #expect(!switchedPrev)
        #expect(trackingView.classifier.state == .idle)

        trackingView.cleanup()
    }

    @Test("Gesture begun outside sidebar then moved inside does NOT trigger space switch")
    func gestureBegunOutsideThenMovedInsideDoesNotSwitch() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let trackingView = SidebarSwipeTrackingView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        window.contentView?.addSubview(trackingView)

        var switchedNext = false
        trackingView.onSwipeLeft = { switchedNext = true }

        // 1. Gesture began outside (x: 500 over web view)
        let beganEvent = TestScrollEvent()
        beganEvent.testWindow = window
        beganEvent.testLocationInWindow = NSPoint(x: 500, y: 300)
        beganEvent.testPhase = .began
        beganEvent.testScrollingDeltaX = -20
        let res1 = trackingView.handleScrollWheel(beganEvent)
        #expect(res1 === beganEvent)
        #expect(trackingView.classifier.state == .idle)

        // 2. Gesture moved inside sidebar (x: 100) with .changed phase
        let changedEvent = TestScrollEvent()
        changedEvent.testWindow = window
        changedEvent.testLocationInWindow = NSPoint(x: 100, y: 300)
        changedEvent.testPhase = .changed
        changedEvent.testScrollingDeltaX = -40
        let res2 = trackingView.handleScrollWheel(changedEvent)
        #expect(res2 === changedEvent)
        #expect(trackingView.classifier.state == .idle)

        // 3. Gesture ended inside sidebar
        let endedEvent = TestScrollEvent()
        endedEvent.testWindow = window
        endedEvent.testLocationInWindow = NSPoint(x: 100, y: 300)
        endedEvent.testPhase = .ended
        endedEvent.testScrollingDeltaX = 0
        let res3 = trackingView.handleScrollWheel(endedEvent)
        #expect(res3 === endedEvent)
        #expect(!switchedNext)
        #expect(trackingView.classifier.state == .idle)

        trackingView.cleanup()
    }

    @Test("Scope exit during gesture resets classifier and prevents stale commit")
    func scopeExitResetsClassifier() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let trackingView = SidebarSwipeTrackingView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        window.contentView?.addSubview(trackingView)

        var switchedNext = false
        trackingView.onSwipeLeft = { switchedNext = true }

        // 1. Began inside sidebar (x: 100)
        let beganEvent = TestScrollEvent()
        beganEvent.testWindow = window
        beganEvent.testLocationInWindow = NSPoint(x: 100, y: 300)
        beganEvent.testPhase = .began
        beganEvent.testScrollingDeltaX = -30
        _ = trackingView.handleScrollWheel(beganEvent)
        #expect(trackingView.classifier.state == .horizontalLocked(deltaX: -30))

        // 2. Moved outside sidebar (x: 500) -> must reset
        let outsideEvent = TestScrollEvent()
        outsideEvent.testWindow = window
        outsideEvent.testLocationInWindow = NSPoint(x: 500, y: 300)
        outsideEvent.testPhase = .changed
        outsideEvent.testScrollingDeltaX = -20
        _ = trackingView.handleScrollWheel(outsideEvent)
        #expect(trackingView.classifier.state == .idle)

        // 3. Ended event cannot commit stale gesture
        let endedEvent = TestScrollEvent()
        endedEvent.testWindow = window
        endedEvent.testLocationInWindow = NSPoint(x: 100, y: 300)
        endedEvent.testPhase = .ended
        _ = trackingView.handleScrollWheel(endedEvent)
        #expect(!switchedNext)
        #expect(trackingView.classifier.state == .idle)

        trackingView.cleanup()
    }

    @Test("Attached modal sheet blocks gesture and resets classifier")
    func attachedSheetBlocksGesture() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let trackingView = SidebarSwipeTrackingView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        window.contentView?.addSubview(trackingView)
        window.beginSheet(sheet, completionHandler: nil)

        let event = TestScrollEvent()
        event.testWindow = window
        event.testLocationInWindow = NSPoint(x: 100, y: 300)
        event.testPhase = .began
        event.testScrollingDeltaX = -40

        let result = trackingView.handleScrollWheel(event)
        #expect(result === event)
        #expect(trackingView.classifier.state == .idle)

        window.endSheet(sheet)
        trackingView.cleanup()
    }

    @Test("Hidden sidebar view rejects swipe events")
    func hiddenSidebarRejectsEvents() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let trackingView = SidebarSwipeTrackingView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        window.contentView?.addSubview(trackingView)
        trackingView.isHidden = true

        let event = TestScrollEvent()
        event.testWindow = window
        event.testLocationInWindow = NSPoint(x: 100, y: 300)
        event.testPhase = .began
        event.testScrollingDeltaX = -40

        let result = trackingView.handleScrollWheel(event)
        #expect(result === event)
        #expect(trackingView.classifier.state == .idle)

        trackingView.cleanup()
    }
}

@Suite("Space inline rename lifecycle and isolation")
@MainActor
struct SpaceInlineRenameLifecycleTests {
    private func temporaryStore() -> GraphStore {
        GraphStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json"))
    }

    @Test("Return commits trimmed name and exits editing")
    func returnCommitsTrimmedName() {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let model = BrowserModel(store: store)
        let space = model.createWorkspace()
        model.selectWorkspace(space)

        var state = SpaceRenameState()
        state.begin(for: space)
        #expect(state.editingWorkspaceID == space.id)
        #expect(state.isEditing)

        state.draft = "   Design System   "
        state.commit(model: model)

        #expect(state.editingWorkspaceID == nil)
        #expect(!state.isEditing)
        #expect(state.draft.isEmpty)
        #expect(model.activeWorkspace?.name == "Design System")
    }

    @Test("Commit resets state before model mutation")
    func commitResetsStateBeforeModelMutation() {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let model = BrowserModel(store: store)
        let space = model.createWorkspace()
        model.selectWorkspace(space)

        var state = SpaceRenameState()
        state.begin(for: space)
        state.draft = "Clean Name"

        state.commit(model: model)
        #expect(!state.isEditing)
        #expect(state.editingWorkspaceID == nil)
        #expect(state.draft.isEmpty)
        #expect(model.activeWorkspace?.name == "Clean Name")
    }

    @Test("Escape cancels draft and restores original name")
    func escapeCancelsDraft() {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let model = BrowserModel(store: store)
        let space = model.createWorkspace()
        model.selectWorkspace(space)
        let originalName = space.name

        var state = SpaceRenameState()
        state.begin(for: space)
        state.draft = "Discarded Changes"
        state.cancel()

        #expect(state.editingWorkspaceID == nil)
        #expect(!state.isEditing)
        #expect(state.draft.isEmpty)
        #expect(model.activeWorkspace?.name == originalName)
    }

    @Test("Blur with invalid empty/whitespace name restores original name")
    func blurWithInvalidNameRestoresOriginal() {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let model = BrowserModel(store: store)
        let space = model.createWorkspace()
        model.selectWorkspace(space)
        let originalName = space.name

        var state = SpaceRenameState()
        state.begin(for: space)
        state.draft = "    \n   "
        state.commit(model: model)

        #expect(state.editingWorkspaceID == nil)
        #expect(!state.isEditing)
        #expect(model.activeWorkspace?.name == originalName)
    }

    @Test("Space switch cancels in-progress draft and isolates newly selected space")
    func spaceSwitchCancelsDraft() {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let model = BrowserModel(store: store)
        let space1 = model.createWorkspace()
        let space2 = model.createWorkspace()
        model.selectWorkspace(space1)
        let space2OriginalName = space2.name

        var state = SpaceRenameState()
        state.begin(for: space1)
        state.draft = "Leaked Draft"

        model.selectWorkspace(space2)
        state.handleSpaceSwitch(newActiveID: space2.id)

        #expect(state.editingWorkspaceID == nil)
        #expect(!state.isEditing)
        #expect(state.draft.isEmpty)
        #expect(model.activeWorkspace?.name == space2OriginalName)
    }

    @Test("Commit cancels rather than persisting stale draft if space switched before commit")
    func commitGuardsActiveWorkspace() {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let model = BrowserModel(store: store)
        let space1 = model.createWorkspace()
        let space2 = model.createWorkspace()
        model.selectWorkspace(space1)
        let space1OriginalName = space1.name
        let space2OriginalName = space2.name

        var state = SpaceRenameState()
        state.begin(for: space1)
        state.draft = "Stale Draft For Space 1"

        // Space 2 became active before commit fired (e.g. observer ordering race)
        model.selectWorkspace(space2)

        // Commit must guard target is active workspace and cancel rather than corrupting data
        state.commit(model: model)
        #expect(!state.isEditing)
        #expect(state.editingWorkspaceID == nil)
        #expect(model.activeWorkspace?.name == space2OriginalName)
        #expect(model.workspaces.first(where: { $0.id == space1.id })?.name == space1OriginalName)
    }
}
