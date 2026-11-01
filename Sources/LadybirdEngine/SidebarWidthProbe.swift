/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Reads the sidebar width the user dragged, so it can be remembered without a settings control.
 */

import AppKit
import SwiftUI

/// Observes the `NSSplitView` that backs `NavigationSplitView` and reports its sidebar width once a drag settles.
///
/// SwiftUI can *set* the sidebar width (`navigationSplitViewColumnWidth`) but has no getter for it, and no callback
/// that fires when the divider moves. The width the user chose therefore has to come from AppKit, which is why this
/// probe lives in `LadybirdEngine` rather than `LadybirdUI`.
///
/// It reports on `didEndLiveResize`, not on every frame: a drag emits a continuous stream of intermediate widths, and
/// only the settled one is worth persisting.
public final class SidebarWidthProbeView: NSView {
    /// Called with the settled sidebar width.
    public var onWidthSettled: ((CGFloat) -> Void)?

    private weak var observedSplitView: NSSplitView?

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopObserving() }
    }

    /// SwiftUI installs the split view after this view joins the hierarchy, so the lookup happens on the first layout
    /// pass rather than at `viewDidMoveToWindow`. No queue hop: S3 forbids one, and the layout pass is already on the
    /// main thread inside the run loop that owns presentation (R5).
    public override func layout() {
        super.layout()
        guard observedSplitView == nil, window != nil else { return }
        if let splitView = Self.findSplitView(in: window?.contentView) {
            observe(splitView)
        }
    }

    private func observe(_ splitView: NSSplitView) {
        stopObserving()
        observedSplitView = splitView
        // The notification, not the delegate: SwiftUI's split view asserts ownership of its delegate, and reassigning it
        // traps. This only listens, so nothing SwiftUI relies on is replaced.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(splitViewDidResize),
            name: NSSplitView.didResizeSubviewsNotification,
            object: splitView
        )
        // Leaving full screen resizes the column too, and that width is worth keeping.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(splitViewDidResize),
            name: NSWindow.didExitFullScreenNotification,
            object: splitView.window
        )
    }

    private func stopObserving() {
        NotificationCenter.default.removeObserver(self)
        observedSplitView = nil
    }

    @objc private func splitViewDidResize(_ notification: Notification) {
        // Mid-drag the divider is still live; only the settled width is worth persisting. AppKit still reports the drag
        // in `currentEvent` at this point, which is what distinguishes the two.
        if let splitView = observedSplitView,
           splitView.window?.currentEvent?.type == .leftMouseDragged {
            return
        }
        reportWidth()
    }

    private func reportWidth() {
        guard let splitView = observedSplitView,
              let sidebar = splitView.arrangedSubviews.first,
              !splitView.isSubviewCollapsed(sidebar)
        else { return }
        onWidthSettled?(sidebar.frame.width)
    }

    /// A sidebar is the first arranged subview of a two-column split view. Anything else would persist the detail
    /// column's width as if it were the sidebar's.
    private static func findSplitView(in view: NSView?) -> NSSplitView? {
        guard let view else { return nil }
        if let splitView = view as? NSSplitView, splitView.arrangedSubviews.count >= 2 {
            return splitView
        }
        for subview in view.subviews {
            if let found = findSplitView(in: subview) { return found }
        }
        return nil
    }

    // NotificationCenter holds its observer unowned, so an entry left behind by a deallocated view is a dangling
    // pointer that traps the next time a matching notification is posted. This touches no stored property, so it is
    // safe from a nonisolated deinit.
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // A probe: it must never take a click meant for the sidebar.
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

public struct SidebarWidthProbe: NSViewRepresentable {
    public var onWidthSettled: (CGFloat) -> Void

    public init(onWidthSettled: @escaping (CGFloat) -> Void) {
        self.onWidthSettled = onWidthSettled
    }

    public func makeNSView(context: Context) -> SidebarWidthProbeView {
        let view = SidebarWidthProbeView()
        view.onWidthSettled = onWidthSettled
        return view
    }

    public func updateNSView(_ nsView: SidebarWidthProbeView, context: Context) {
        nsView.onWidthSettled = onWidthSettled
    }
}
