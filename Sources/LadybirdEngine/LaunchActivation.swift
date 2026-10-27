/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Orders a new window front. AppKit lives here, not in `LadybirdUI`.
 */

import AppKit
import SwiftUI

/// A zero-size background view that orders its window front once.
///
/// Activation cannot happen in `applicationDidFinishLaunching`: SwiftUI has not created a window yet, so the app
/// launched correctly but behind whatever was already frontmost, which reads as "the app did not open".
///
/// It cannot live in `PortWebView` either. The start page mounts no web view and the web view only joins a window once
/// the user navigates, so the default launch would never activate. Hence a window-level background.
///
/// Synchronous on purpose: S3 forbids a queue hop here, and none is needed because this is already the main thread,
/// inside the run loop that owns presentation.
public final class LaunchActivationNSView: NSView {
    private var hasActivated = false

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !hasActivated else { return }
        hasActivated = true
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // It is a background: clicks belong to the content in front of it.
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

public struct LaunchActivationView: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> LaunchActivationNSView { LaunchActivationNSView() }

    public func updateNSView(_ nsView: LaunchActivationNSView, context: Context) {}
}
