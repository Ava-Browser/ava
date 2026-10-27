/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Tests for launch window activation, which the start page path depends on because it mounts no web view.
 */

import AppKit
import Foundation
import Testing

@testable import LadybirdEngine

@Suite("Launch activation")
@MainActor
struct LaunchActivationTests {
    private func window() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
    }

    @Test("Joining a window orders it front without a web view")
    func ordersWindowFront() {
        let window = window()
        let view = LaunchActivationNSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        #expect(!window.isVisible)
        window.contentView?.addSubview(view)
        #expect(window.isVisible)
    }

    // The view sits behind the content, so it must never take a click from the start page's search field.
    @Test("Activation view never intercepts hit testing")
    func doesNotInterceptClicks() {
        let window = window()
        let view = LaunchActivationNSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView?.addSubview(view)
        #expect(view.hitTest(NSPoint(x: 200, y: 150)) == nil)
    }
}
