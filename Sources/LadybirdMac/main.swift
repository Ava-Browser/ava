/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The app. SwiftUI owns the run loop, which is the same one the shim's CFRunLoopTimer pumps LibCore from (R5, R8).
 */

import AppKit
import LadybirdUI
import SwiftUI

@main
struct LadybirdMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            BrowserWindow()
        }
        .windowToolbarStyle(.unified)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A browser is a regular app: closing the window must be able to end it, and it needs a Dock icon.
        // Activation happens when the window actually exists — see PortWebView.viewDidMoveToWindow. Activating here
        // alone leaves the window behind whatever was frontmost, because SwiftUI has not made one yet.
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
