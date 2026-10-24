/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The session model: one engine, one tab, one view. Everything here runs on the main thread, which is the pump's
 * thread (R5), so no actor hops and no cross-thread handoff of the borrowed surface.
 *
 * One tab is deliberate: multi-tab teardown ordering was never exercised in the spike (Architecture.md, known gaps).
 */

import AppKit
import LadybirdBridge
import Observation

@MainActor
@Observable
public final class BrowserModel {
    /// What the address bar shows. Kept separate from `currentURL` so typing does not rewrite the page's own URL.
    public var addressText: String = ""
    /// The last URL the engine reported, or the one we navigated to.
    public private(set) var currentURL: String = ""
    public private(set) var isLoading: Bool = false
    /// Set when the engine could not be started at all; the UI shows it instead of a blank page.
    public private(set) var failure: String?

    @ObservationIgnored public let webView: PortWebView
    @ObservationIgnored private var app: PortApp?
    @ObservationIgnored private var tab: UInt64 = 0
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?

    public init() {
        // Placeholder frame only: SwiftUI lays the view out before the first paint and
        // reportViewportAfterTabCreation pushes the real size. Kept equal to the window default so the
        // one frame before layout is not a visibly wrong size.
        webView = PortWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    /// Starts the engine. Idempotent, and deliberately not in `init`: SwiftUI evaluates a `@State` initial value
    /// expression on every enclosing view init, so an engine started from `init` would leak a set of helper processes
    /// per discarded model instance.
    public func start(homeURL: String = "https://example.com") {
        guard app == nil, failure == nil else { return }

        var callbacks = PortCallbacks()
        callbacks.onURLChange = { [weak self] _, url in
            MainActor.assumeIsolated { self?.handleURLChange(url) }
        }
        callbacks.onLoadFinish = { [weak self] _, url in
            MainActor.assumeIsolated { self?.handleLoadFinish(url) }
        }
        callbacks.onReadyToPaint = { [weak self] tab in
            MainActor.assumeIsolated { self?.handlePaint(tab) }
        }

        guard let app = PortApp(callbacks: callbacks) else {
            failure = """
                The engine could not be started.

                Launch through Scripts/run.sh: it exports LADYBIRD_BINARY_PATH and DYLD_LIBRARY_PATH, which the engine \
                needs to find its helper processes and the Lagom dylibs.
                """
            return
        }
        self.app = app

        webView.onViewportChange = { [weak self] width, height, scale in
            MainActor.assumeIsolated { self?.app?.setViewport(in: self?.tab ?? 0, width: width, height: height, scale: scale) }
        }

        // Input is a straight pass-through: the view already speaks CSS pixels, and the shim scales to device pixels.
        webView.onMouse = { [weak self] type, x, y, button, buttons, clickCount, wheelDeltaY in
            MainActor.assumeIsolated {
                guard let self, let app = self.app else { return }
                app.sendMouse(
                    in: self.tab, type: type, x: x, y: y, button: button, buttons: buttons,
                    clickCount: clickCount, wheelDeltaY: wheelDeltaY
                )
            }
        }
        webView.onKey = { [weak self] key, codePoint, modifiers, isKeyDown in
            MainActor.assumeIsolated {
                guard let self, let app = self.app else { return }
                app.sendKey(in: self.tab, key: key, codePoint: codePoint, modifiers: modifiers, isKeyDown: isKeyDown)
            }
        }
        webView.onTypeText = { [weak self] text in
            MainActor.assumeIsolated {
                guard let self, let app = self.app else { return }
                app.typeText(text, in: self.tab)
            }
        }

        tab = app.createTab()
        if tab == 0 {
            failure = "The engine refused to create a tab; it could not load its system theme."
            return
        }

        // The view laid out before this tab existed, so its viewport report was dropped. Send it now, before the first
        // load, or the page renders at the engine's default size instead of the window's.
        webView.reportViewportAfterTabCreation()

        load(homeURL)
        // R8: the shim's own CFRunLoopTimer in kCFRunLoopCommonModes, so a live resize cannot starve the engine.
        app.startPump()

        // The engine owns helper processes, so it must be torn down before the process exits. This is the flow the
        // spike actually exercised (Architecture.md, known gaps).
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { self.shutdown() }
        }
    }

    /// Address bar submissions. Bare hosts get `https://`; this is where the shell decides what user text means.
    public func submitAddress() {
        load(addressText)
    }

    public func reload() {
        guard !currentURL.isEmpty else { return }
        load(currentURL)
    }

    public func load(_ input: String) {
        guard let app, tab != 0 else { return }
        let url = PortApp.normalizedURL(input)
        addressText = url
        isLoading = true
        PortBenchmark.shared.recordLoad(url: url)
        app.load(url, in: tab)
    }

    /// Main thread, after the pump stops. Called from `applicationWillTerminate`; the engine must outlive every view.
    public func shutdown() {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
        app?.destroy()
        app = nil
    }

    private func handleURLChange(_ url: String) {
        currentURL = url
        addressText = url
    }

    private func handleLoadFinish(_ url: String) {
        currentURL = url
        addressText = url
        isLoading = false
    }

    private func handlePaint(_ paintedTab: UInt64) {
        guard paintedTab == tab, let surface = app?.surface(in: tab) else { return }
        PortBenchmark.shared.recordPaint(painted: (surface.paintedWidth, surface.paintedHeight), surface: (surface.surfaceWidth, surface.surfaceHeight), cssSize: webView.bounds.size)
        webView.present(surface)
    }
}
