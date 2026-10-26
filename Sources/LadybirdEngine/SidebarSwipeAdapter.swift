/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Scoped trackpad swipe handling over the sidebar for space switching.
 */

import AppKit
import SwiftUI

struct SidebarSwipeClassifier: Sendable {
    enum Action: Equatable, Sendable {
        case passThrough
        case consume
        case switchToNext
        case switchToPrevious
    }

    enum State: Equatable, Sendable {
        case idle
        case tracking(deltaX: Double, deltaY: Double)
        case horizontalLocked(deltaX: Double)
        case verticalLocked
    }

    var state: State = .idle
    let switchThreshold: Double = 40.0
    let dominantAxisRatio: Double = 1.2
    let minIntentDistance: Double = 8.0

    mutating func reset() {
        state = .idle
    }

    mutating func process(
        isPrecise: Bool,
        phase: NSEvent.Phase,
        momentumPhase: NSEvent.Phase,
        deltaX: Double,
        deltaY: Double
    ) -> Action {
        guard isPrecise, momentumPhase.isEmpty, !phase.isEmpty else {
            state = .idle
            return .passThrough
        }

        if phase.contains(.cancelled) {
            let wasHorizontal = if case .horizontalLocked = state { true } else { false }
            state = .idle
            return wasHorizontal ? .consume : .passThrough
        }

        if phase.contains(.began) {
            state = .tracking(deltaX: deltaX, deltaY: deltaY)
            return evaluateTracking(deltaX: deltaX, deltaY: deltaY)
        }

        if phase.contains(.ended) {
            let previousState = state
            state = .idle
            switch previousState {
            case let .horizontalLocked(totalX):
                let finalX = totalX + deltaX
                if finalX <= -switchThreshold {
                    return .switchToNext
                } else if finalX >= switchThreshold {
                    return .switchToPrevious
                }
                return .consume
            case let .tracking(totalX, totalY):
                let finalX = totalX + deltaX
                let finalY = totalY + deltaY
                if abs(finalX) >= switchThreshold && abs(finalX) >= abs(finalY) * dominantAxisRatio {
                    return finalX <= -switchThreshold ? .switchToNext : .switchToPrevious
                }
                return abs(finalY) > abs(finalX) ? .passThrough : .consume
            case .verticalLocked, .idle:
                return .passThrough
            }
        }

        if phase.contains(.changed) {
            switch state {
            case .verticalLocked:
                return .passThrough
            case let .horizontalLocked(totalX):
                state = .horizontalLocked(deltaX: totalX + deltaX)
                return .consume
            case let .tracking(totalX, totalY):
                let newX = totalX + deltaX
                let newY = totalY + deltaY
                state = .tracking(deltaX: newX, deltaY: newY)
                return evaluateTracking(deltaX: newX, deltaY: newY)
            case .idle:
                return .passThrough
            }
        }

        if case .horizontalLocked = state {
            return .consume
        }
        return .passThrough
    }

    private mutating func evaluateTracking(deltaX: Double, deltaY: Double) -> Action {
        let absX = abs(deltaX)
        let absY = abs(deltaY)

        if absY >= minIntentDistance && absY > absX {
            state = .verticalLocked
            return .passThrough
        }

        if absX >= minIntentDistance && absX >= absY * dominantAxisRatio {
            state = .horizontalLocked(deltaX: deltaX)
            return .consume
        }

        return absY > absX ? .passThrough : .consume
    }
}

@MainActor
public final class SidebarSwipeTrackingView: NSView {
    public var onSwipeLeft: (() -> Void)?
    public var onSwipeRight: (() -> Void)?

    var classifier = SidebarSwipeClassifier()
    nonisolated(unsafe) private var localMonitor: Any?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override var isFlipped: Bool { true }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installMonitorIfNeeded()
        } else {
            removeMonitor()
            classifier.reset()
        }
    }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    public func cleanup() {
        removeMonitor()
        classifier.reset()
    }

    private func installMonitorIfNeeded() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleScrollWheel(event)
        }
    }

    private func removeMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    public func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
        guard let window = self.window, event.window === window else {
            classifier.reset()
            return event
        }
        guard window.attachedSheet == nil, !isHiddenOrHasHiddenAncestor else {
            classifier.reset()
            return event
        }
        guard visibleRect.width > 0, visibleRect.height > 0 else {
            classifier.reset()
            return event
        }

        let locationInWindow = event.locationInWindow
        let localPoint = convert(locationInWindow, from: nil)
        guard bounds.contains(localPoint), visibleRect.contains(localPoint) else {
            classifier.reset()
            return event
        }

        let action = classifier.process(
            isPrecise: event.hasPreciseScrollingDeltas,
            phase: event.phase,
            momentumPhase: event.momentumPhase,
            deltaX: Double(event.scrollingDeltaX),
            deltaY: Double(event.scrollingDeltaY)
        )

        switch action {
        case .passThrough:
            return event
        case .consume:
            return nil
        case .switchToNext:
            onSwipeLeft?()
            return nil
        case .switchToPrevious:
            onSwipeRight?()
            return nil
        }
    }
}

public struct SidebarSwipeRepresentable: NSViewRepresentable {
    public var onSwipeLeft: () -> Void
    public var onSwipeRight: () -> Void

    public init(onSwipeLeft: @escaping () -> Void, onSwipeRight: @escaping () -> Void) {
        self.onSwipeLeft = onSwipeLeft
        self.onSwipeRight = onSwipeRight
    }

    public func makeNSView(context: Context) -> SidebarSwipeTrackingView {
        let view = SidebarSwipeTrackingView()
        view.onSwipeLeft = onSwipeLeft
        view.onSwipeRight = onSwipeRight
        return view
    }

    public func updateNSView(_ nsView: SidebarSwipeTrackingView, context: Context) {
        nsView.onSwipeLeft = onSwipeLeft
        nsView.onSwipeRight = onSwipeRight
    }

    public static func dismantleNSView(_ nsView: SidebarSwipeTrackingView, coordinator: ()) {
        nsView.cleanup()
    }
}
