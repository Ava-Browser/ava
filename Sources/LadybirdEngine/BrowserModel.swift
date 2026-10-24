/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The session model: one engine, many tabs, one view. Everything here runs on the main thread, which is the pump's
 * thread (R5), so no actor hops and no cross-thread handoff of the borrowed surface.
 *
 * Tabs are never destroyed by switching. Each tab owns an engine tab for its whole life; selecting a different one only
 * changes which tab this model addresses and which surface is presented. That keeps page state, history and scroll
 * position intact, and it means the only teardown path is an explicit close — which is the smallest surface to get
 * right, given multi-tab teardown was never exercised in the spike.
 */

import AppKit
import LadybirdBridge
import Observation

@MainActor
@Observable
public final class BrowserModel {
    /// Tabs in sidebar order. The engine handles inside are the identity; position is presentation.
    public private(set) var tabs: [BrowserTab] = []
    /// Which tab the address bar and the web view address. Always one of `tabs` while `tabs` is non-empty.
    public private(set) var selectedTabID: UInt64?

    /// Whether history traversal is possible in each direction for the selected tab.
    ///
    /// Stored, not computed. The engine owns this fact and every navigation invalidates it, so a computed property
    /// reading `selectedTab?.id` would only republish when the *tab* changed — a back-then-forward would leave a dead
    /// Back button, because no observable state it depends on had changed. Refreshed in the URL and load-finish
    /// handlers, which is where the engine's history can actually change.
    public private(set) var canGoBack: Bool = false
    public private(set) var canGoForward: Bool = false

    /// What the address bar shows. Kept separate from the selected tab's URL so typing does not rewrite the page's URL.
    public var addressText: String = ""
    /// Set when the engine could not be started at all; the UI shows it instead of a blank page.
    public private(set) var failure: String?

    /// The one engine instance for this process.
    ///
    /// `WebView::Application`'s constructor asserts `VERIFY(!s_the)` — the engine permits exactly one application per
    /// process, and a second construction is an immediate crash, not an error. A per-instance `app == nil` guard is not
    /// enough: if SwiftUI discards a `BrowserModel` (a new view identity) while the old one is still alive, a fresh
    /// model would build a second `PortApp` and abort. Holding it here makes the constraint explicit and shared, which
    /// is what the engine actually requires.
    @ObservationIgnored private static var processApp: PortApp?
    /// Monotonic id for presented dialogs. Two alerts on the same tab must not share a sheet identity, or the second
    /// would reuse the first's presented content instead of updating it.
    @ObservationIgnored private static var nextDialogID: UInt64 = 1

    @ObservationIgnored public let webView: PortWebView
    @ObservationIgnored private var app: PortApp?
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?

    public init() {
        // Placeholder frame only: SwiftUI lays the view out before the first paint and
        // reportViewportAfterTabCreation pushes the real size. Kept equal to the window default so the
        // one frame before layout is not a visibly wrong size.
        webView = PortWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    public var selectedTab: BrowserTab? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    public var currentURL: String { selectedTab?.currentURL ?? "" }
    public var isLoading: Bool { selectedTab?.isLoading ?? false }

    /// Starts the engine. Idempotent, and deliberately not in `init`: SwiftUI evaluates a `@State` initial value
    /// expression on every enclosing view init, so an engine started from `init` would leak a set of helper processes
    /// per discarded model instance.
    public func start(homeURL: String = "https://example.com") {
        guard app == nil, failure == nil else { return }

        var callbacks = PortCallbacks()
        callbacks.onURLChange = { [weak self] tab, url in
            MainActor.assumeIsolated { self?.handleURLChange(tab, url) }
        }
        callbacks.onLoadFinish = { [weak self] tab, url in
            MainActor.assumeIsolated { self?.handleLoadFinish(tab, url) }
        }
        callbacks.onReadyToPaint = { [weak self] tab in
            MainActor.assumeIsolated { self?.handlePaint(tab) }
        }

        // All four or none: the ABI auto-answers a dialog whose callback is absent, so a partial set would silently
        // auto-answer some and hang the page on the rest. The engine is blocked inside each of these, so the sheet is
        // the only thing that unblocks that tab.
        callbacks.onRequestAlert = { [weak self] tab, message in
            MainActor.assumeIsolated { self?.presentDialog(.alert(id: BrowserModel.takeDialogID(), message: message), for: tab) }
        }
        callbacks.onRequestConfirm = { [weak self] tab, message in
            MainActor.assumeIsolated { self?.presentDialog(.confirm(id: BrowserModel.takeDialogID(), message: message), for: tab) }
        }
        callbacks.onRequestPrompt = { [weak self] tab, message, defaultText in
            MainActor.assumeIsolated { self?.presentDialog(.prompt(id: BrowserModel.takeDialogID(), message: message, defaultText: defaultText), for: tab) }
        }
        callbacks.onRequestBeforeUnload = { [weak self] tab, source in
            MainActor.assumeIsolated { self?.presentDialog(.beforeUnload(id: BrowserModel.takeDialogID(), source: source), for: tab) }
        }

        // One engine per process: constructing a second asserts inside WebView::Application. But adopting an existing
        // one is not an option either — LbAppCreate takes its callbacks once, and the closures bound to a discarded
        // model would keep firing into it. So a second start() is a wiring bug, and it fails loudly here rather than
        // silently presenting a dead tab.
        guard Self.processApp == nil else {
            failure = "Internal error: a second browser model tried to start the engine."
            return
        }

        guard let app = PortApp(callbacks: callbacks) else {
            failure = """
                The engine could not be started.

                Launch through Scripts/run.sh: it exports LADYBIRD_BINARY_PATH and DYLD_LIBRARY_PATH, which the engine \
                needs to find its helper processes and the Lagom dylibs.
                """
            return
        }
        Self.processApp = app
        self.app = app

        webView.onViewportChange = { [weak self] width, height, scale in
            MainActor.assumeIsolated { self?.applyViewport(width: width, height: height, scale: scale) }
        }

        // Input goes to the selected tab. Resolved per event rather than captured, so switching tabs does not need to
        // reinstall these closures.
        webView.onMouse = { [weak self] type, x, y, button, buttons, clickCount, wheelDeltaY in
            MainActor.assumeIsolated {
                guard let self, let app = self.app, let id = self.selectedTabID else { return }
                app.sendMouse(
                    in: id, type: type, x: x, y: y, button: button, buttons: buttons,
                    clickCount: clickCount, wheelDeltaY: wheelDeltaY
                )
            }
        }
        webView.onKey = { [weak self] key, codePoint, modifiers, isKeyDown in
            MainActor.assumeIsolated {
                guard let self, let app = self.app, let id = self.selectedTabID else { return }
                app.sendKey(in: id, key: key, codePoint: codePoint, modifiers: modifiers, isKeyDown: isKeyDown)
            }
        }
        webView.onTypeText = { [weak self] text in
            MainActor.assumeIsolated {
                guard let self, let app = self.app, let id = self.selectedTabID else { return }
                app.typeText(text, in: id)
            }
        }

        openTab(url: homeURL)
        guard !tabs.isEmpty else { return }

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

    // MARK: - Tabs

    /// Creates an engine tab and selects it. Returns the new tab, or nil if the engine refused.
    @discardableResult
    public func openTab(url: String = "about:blank") -> BrowserTab? {
        guard let app else { return nil }
        let id = app.createTab()
        guard id != 0 else {
            if tabs.isEmpty {
                failure = "The engine refused to create a tab; it could not load its system theme."
            }
            return nil
        }

        let tab = BrowserTab(id: id)
        tabs.append(tab)
        select(tab)

        // A brand-new tab has never been given a viewport, so it renders at the engine default until told otherwise.
        // select() only presents existing frames; this is the one place the new tab needs its size pushed.
        applyViewport(width: Int32(webView.bounds.width), height: Int32(webView.bounds.height), scale: viewportScale)

        if url != "about:blank" {
            load(url, in: tab)
        } else if let selected = tabs.last, selected.id == id {
            addressText = ""
        }
        return tab
    }

    /// Selects an existing tab. Does not touch the engine's tab beyond asking for its current frame, so the page is
    /// never reloaded and its state survives exactly as it was left.
    public func select(_ tab: BrowserTab) {
        select(tab, force: false)
    }

    /// `force` is for the close path, where the model has just removed a row and must re-point the view at the
    /// survivor even though the ids may look unchanged to the fast-path check.
    public func select(_ tab: BrowserTab, force: Bool) {
        if !force, tab.id == selectedTabID, webView.currentTabID == tab.id { return }

        // Leaving the current tab: answer its dialog first. The sheet lives on the tab that asked, so once that tab is
        // not visible the user has no way to reach it, and the page would stay stopped.
        if let leaving = selectedTab, leaving.id != tab.id {
            answerPendingDialog(on: leaving)
        }

        selectedTabID = tab.id
        webView.currentTabID = tab.id
        addressText = tab.currentURL

        // Present the newly visible tab's last frame immediately, so switching does not flash blank while waiting for
        // the next paint. A tab that has never painted simply has no frame, which is correct.
        presentCurrentFrame(of: tab.id)

        // Its viewport may have changed (or been set for the first time) while it was in the background.
        applyViewport(width: Int32(webView.bounds.width), height: Int32(webView.bounds.height), scale: viewportScale)
        refreshHistoryAvailability()
    }

    /// Closes a tab and destroys its engine tab. Selecting a neighbour first keeps the view pointing at something real
    /// for the whole of the teardown.
    public func closeTab(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }

        // Pick the survivor before mutating, so `select` never sees a table mid-removal.
        let wasSelected = tab.id == selectedTabID
        let neighbour: BrowserTab? = {
            guard wasSelected else { return nil }
            if index + 1 < tabs.count { return tabs[index + 1] }
            if index > 0 { return tabs[index - 1] }
            return nil
        }()

        // Answer before anything else: the page is stopped until it gets a reply, and the engine tab is about to be
        // destroyed. With dialogs installed this is the ordering the brief requires, not an optimisation.
        answerPendingDialog(on: tab)

        tabs.remove(at: index)

        if let neighbour {
            select(neighbour, force: true)
        } else if tabs.isEmpty {
            selectedTabID = nil
            webView.currentTabID = 0
            addressText = ""
        }

        // The engine tab goes away last, after the view has stopped asking for its frame. This app installs no dialog
        // callbacks, so the engine auto-answers before_unload and there is nothing pending to answer here — when those
        // are wired, any pending dialog for this tab must be answered before this call.
        app?.destroyTab(tab.id)
    }

    /// Closes the selected tab, if any.
    public func closeSelectedTab() {
        guard let selectedTab else { return }
        closeTab(selectedTab)
    }

    // MARK: - Navigation

    // MARK: - Dialogs

    private static func takeDialogID() -> UInt64 {
        defer { nextDialogID += 1 }
        return nextDialogID
    }

    private func presentDialog(_ dialog: TabDialog, for tabID: UInt64) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else {
            // The tab went away between the engine asking and us handling it. Answer immediately rather than leaving a
            // page stopped forever — a tab that cannot answer must not hold the engine.
            answerImmediately(dialog, for: tabID)
            return
        }
        tab.present(dialog: dialog)
    }

    /// Answers a dialog with its safe default. Used when the tab is gone, or when a dialog must be cleared before the
    /// tab switches away or closes.
    private func answerImmediately(_ dialog: TabDialog, for tabID: UInt64) {
        guard let app else { return }
        switch dialog {
        case .alert:
            app.answerAlert(in: tabID)
        case .confirm:
            app.answerConfirm(in: tabID, accept: false)
        case .prompt:
            app.answerPrompt(in: tabID, response: nil)
        case .beforeUnload:
            // Inverted sense: true allows the navigation, which is the safe default for a dialog nobody is present for.
            app.answerBeforeUnload(in: tabID, accept: true)
        }
    }

    /// The host's answer from a presented sheet.
    public func answer(_ dialog: TabDialog, on tab: BrowserTab, accepted: Bool, promptText: String? = nil) {
        guard let app else { return }
        tab.clearDialog()
        switch dialog {
        case .alert:
            app.answerAlert(in: tab.id)
        case .confirm:
            app.answerConfirm(in: tab.id, accept: accepted)
        case .prompt:
            app.answerPrompt(in: tab.id, response: accepted ? (promptText ?? "") : nil)
        case .beforeUnload:
            app.answerBeforeUnload(in: tab.id, accept: accepted)
        }
    }

    /// Answers any pending dialog on `tab` with its safe default.
    ///
    /// Called before switching away from or closing a tab. The page is stopped until it gets a reply, so a tab that
    /// keeps a dialog while becoming invisible would be wedged with no way for the user to reach the sheet.
    private func answerPendingDialog(on tab: BrowserTab) {
        guard let dialog = tab.dialog else { return }
        tab.clearDialog()
        answerImmediately(dialog, for: tab.id)
    }

    // MARK: - History

    public func goBack() {
        guard let app, let id = selectedTab?.id else { return }
        app.traverseHistory(.back, in: id)
    }

    public func goForward() {
        guard let app, let id = selectedTab?.id else { return }
        app.traverseHistory(.forward, in: id)
    }

    /// Re-reads the engine's own answer. Called from every place history can change, so the buttons never go stale.
    private func refreshHistoryAvailability() {
        guard let app, let id = selectedTab?.id else {
            canGoBack = false
            canGoForward = false
            return
        }
        canGoBack = app.canTraverseHistory(.back, in: id)
        canGoForward = app.canTraverseHistory(.forward, in: id)
    }

    /// Address bar submissions. Bare hosts get `https://`; this is where the shell decides what user text means.
    public func submitAddress() {
        load(addressText)
    }

    public func reload() {
        guard let selectedTab, !selectedTab.currentURL.isEmpty else { return }
        load(selectedTab.currentURL)
    }

    public func load(_ input: String) {
        guard let selectedTab else { return }
        load(input, in: selectedTab)
    }

    private func load(_ input: String, in tab: BrowserTab) {
        guard let app else { return }
        // The engine decides whether this is a URL or a search. Showing the resolved form means a search visibly turns
        // into its query URL rather than sitting there looking like it did nothing.
        guard let url = app.load(input, in: tab.id) else {
            failure = "Could not resolve \(input) as a URL or a search."
            return
        }
        addressText = url
        tab.setLoading(true)
        PortBenchmark.shared.recordLoad(url: url)
    }

    /// Main thread, after the pump stops. Called from `applicationWillTerminate`; the engine must outlive every view.
    public func shutdown() {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
        app?.destroy()
        app = nil
        Self.processApp = nil
        selectedTabID = nil
    }

    // MARK: - Engine events

    private func handleURLChange(_ tabID: UInt64, _ url: String) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        tab.update(url: url)
        if tabID == selectedTabID {
            addressText = url
            refreshHistoryAvailability()
        }
    }

    private func handleLoadFinish(_ tabID: UInt64, _ url: String) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        tab.update(url: url)
        tab.setLoading(false)
        if tabID == selectedTabID {
            addressText = url
            refreshHistoryAvailability()
        }
    }

    private func handlePaint(_ paintedTab: UInt64) {
        // A background tab painting is normal and must not be presented — it would replace the visible page. R3 still
        // holds: the frame is simply dropped, and the tab's own next paint (or the switch-time re-read) shows it.
        guard paintedTab == selectedTabID else { return }
        presentCurrentFrame(of: paintedTab)
    }

    // MARK: - Presentation

    private var viewportScale: Double {
        Double(webView.window?.backingScaleFactor ?? 1)
    }

    /// Pushes the viewport to the selected tab. Only the selected tab needs it: a background tab's viewport is applied
    /// when it is next selected, which is the moment its size starts mattering.
    private func applyViewport(width: Int32, height: Int32, scale: Double) {
        guard let app, let id = selectedTabID else { return }
        app.setViewport(in: id, width: width, height: height, scale: scale)
    }

    private func presentCurrentFrame(of tabID: UInt64) {
        guard let app, let surface = app.surface(in: tabID) else { return }
        PortBenchmark.shared.recordPaint(
            painted: (surface.paintedWidth, surface.paintedHeight),
            surface: (surface.surfaceWidth, surface.surfaceHeight),
            cssSize: webView.bounds.size
        )
        webView.present(surface)
    }
}
