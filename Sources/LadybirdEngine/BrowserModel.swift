/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The session model: one engine, spaces & tabs, one view. Everything here runs on the main thread, which is the pump's
 * thread (R5), so no actor hops and no cross-thread handoff of the borrowed surface.
 *
 * The workspace/tab graph is durable app state; the engine's knowledge of tabs is a disposable cache of it.
 * Every mutation writes through to SpacesManager / SpacesStore. LbTab* handles are a render cache: evictable,
 * rehydratable on activation.
 */

import AppKit
import LadybirdBridge
import Observation

@MainActor
@Observable
public final class BrowserModel {
    /// Spaces manager owning the durable graph.
    public let spacesManager: SpacesManager

    /// All UI tab representations (both loaded and unloaded).
    public private(set) var tabs: [BrowserTab] = []
    /// Which tab is currently selected (descriptor UUID).
    public private(set) var selectedTabID: UUID?

    /// Whether history traversal is possible in each direction for the selected tab.
    public private(set) var canGoBack: Bool = false
    public private(set) var canGoForward: Bool = false

    /// What the address bar shows.
    public var addressText: String = ""
    /// Set when the engine could not be started at all; the UI shows it instead of a blank page.
    public private(set) var failure: String?

    /// The one engine instance for this process.
    @ObservationIgnored private static var processApp: PortApp?
    @ObservationIgnored private static var nextDialogID: UInt64 = 1

    @ObservationIgnored public let webView: PortWebView
    @ObservationIgnored private var app: PortApp?
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?

    public init(spacesManager: SpacesManager = SpacesManager()) {
        self.spacesManager = spacesManager
        webView = PortWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        loadInitialTabsFromGraph()
    }

    private func loadInitialTabsFromGraph() {
        for desc in spacesManager.tabs {
            let tab = BrowserTab(
                id: desc.id,
                engineID: nil,
                url: desc.url,
                title: desc.title,
                tier: desc.tier,
                workspaceID: desc.workspaceID
            )
            tabs.append(tab)
        }
        if let activeTabID = spacesManager.activeWorkspace.activeTabID,
           tabs.contains(where: { $0.id == activeTabID }) {
            selectedTabID = activeTabID
        } else if let first = tabs.first(where: { $0.workspaceID == spacesManager.activeWorkspaceID || $0.tier == .essential }) {
            selectedTabID = first.id
        }
    }

    public var selectedTab: BrowserTab? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    public var currentURL: String { selectedTab?.currentURL ?? "" }
    public var isLoading: Bool { selectedTab?.isLoading ?? false }

    public var activeWorkspace: Workspace { spacesManager.activeWorkspace }
    public var spaces: [Workspace] { spacesManager.spaces }

    public var essentialTabs: [BrowserTab] {
        tabs.filter { $0.tier == .essential }
    }

    public var activePinnedTabs: [BrowserTab] {
        let activeID = spacesManager.activeWorkspaceID
        return tabs.filter { $0.tier == .pinned && $0.workspaceID == activeID }
    }

    public var activeNormalTabs: [BrowserTab] {
        let activeID = spacesManager.activeWorkspaceID
        return tabs.filter { $0.tier == .normal && $0.workspaceID == activeID }
    }

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

        webView.onMouse = { [weak self] type, x, y, button, buttons, clickCount, wheelDeltaY in
            MainActor.assumeIsolated {
                guard let self, let app = self.app, let engineID = self.selectedTab?.engineID else { return }
                app.sendMouse(
                    in: engineID, type: type, x: x, y: y, button: button, buttons: buttons,
                    clickCount: clickCount, wheelDeltaY: wheelDeltaY
                )
            }
        }
        webView.onKey = { [weak self] key, codePoint, modifiers, isKeyDown in
            MainActor.assumeIsolated {
                guard let self, let app = self.app, let engineID = self.selectedTab?.engineID else { return }
                app.sendKey(in: engineID, key: key, codePoint: codePoint, modifiers: modifiers, isKeyDown: isKeyDown)
            }
        }
        webView.onTypeText = { [weak self] text in
            MainActor.assumeIsolated {
                guard let self, let app = self.app, let engineID = self.selectedTab?.engineID else { return }
                app.typeText(text, in: engineID)
            }
        }

        if tabs.isEmpty {
            openTab(url: homeURL)
        } else if let selected = selectedTab {
            rehydrate(selected)
        } else if let first = tabs.first {
            select(first)
        }

        app.startPump()

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { self.shutdown() }
        }
    }

    // MARK: - Workspaces

    public func selectWorkspace(_ workspace: Workspace) {
        guard workspace.id != spacesManager.activeWorkspaceID else { return }
        spacesManager.selectWorkspace(id: workspace.id)

        // Restore per-space active tab selection memory
        let currentWorkspace = spacesManager.activeWorkspace
        if let memoryTabID = currentWorkspace.activeTabID, let tab = tabs.first(where: { $0.id == memoryTabID }) {
            select(tab)
        } else if let first = activeNormalTabs.first ?? activePinnedTabs.first ?? essentialTabs.first {
            select(first)
        } else {
            // Space has no tabs yet: open an about:blank tab in this space
            openTab(url: "about:blank")
        }
    }

    public func createWorkspace(name: String, icon: String = "square.stack.3d.up", theme: GradientSpec = GradientSpec()) {
        let space = spacesManager.createWorkspace(name: name, icon: icon, theme: theme)
        selectWorkspace(space)
    }

    public func removeWorkspace(_ workspace: Workspace) {
        guard spacesManager.spaces.count > 1 else { return }
        let removedID = workspace.id
        // Close and unload tabs
        let toClose = tabs.filter { $0.workspaceID == removedID }
        for tab in toClose {
            closeTab(tab)
        }
        spacesManager.removeWorkspace(id: removedID)
        if let active = spacesManager.spaces.first(where: { $0.id == spacesManager.activeWorkspaceID }) {
            selectWorkspace(active)
        }
    }

    // MARK: - Tabs & Rehydration

    /// Ensures an engine tab exists for `tab`, creating and loading if currently unloaded.
    @discardableResult
    private func rehydrate(_ tab: BrowserTab) -> UInt64? {
        if let existing = tab.engineID { return existing }
        guard let app else { return nil }

        let engineID = app.createTab()
        guard engineID != 0 else {
            if tabs.isEmpty {
                failure = "The engine refused to create a tab; it could not load its system theme."
            }
            return nil
        }

        tab.engineID = engineID
        let targetURL = tab.currentURL.isEmpty ? "about:blank" : tab.currentURL
        if targetURL != "about:blank" {
            load(targetURL, in: tab)
        }
        return engineID
    }

    /// Unloads a tab's engine handle to reclaim WebContent processes (TDD §1 render cache).
    public func unloadTab(_ tab: BrowserTab) {
        guard let engineID = tab.engineID else { return }
        if selectedTabID == tab.id {
            // Cannot unload the actively presented tab unless switching first
            return
        }
        answerPendingDialog(on: tab)
        tab.engineID = nil
        app?.destroyTab(engineID)
    }

    @discardableResult
    public func openTab(url: String = "about:blank", tier: TabTier = .normal) -> BrowserTab? {
        let wsID = (tier == .essential) ? nil : spacesManager.activeWorkspaceID
        let desc = spacesManager.addTab(
            workspaceID: wsID,
            tier: tier,
            url: url == "about:blank" ? "" : url
        )

        let tab = BrowserTab(
            id: desc.id,
            engineID: nil,
            url: desc.url,
            title: desc.title,
            tier: desc.tier,
            workspaceID: desc.workspaceID
        )
        tabs.append(tab)

        select(tab)

        if url != "about:blank" {
            load(url, in: tab)
        } else {
            addressText = ""
        }
        return tab
    }

    public func select(_ tab: BrowserTab) {
        select(tab, force: false)
    }

    public func select(_ tab: BrowserTab, force: Bool) {
        let engineID = rehydrate(tab) ?? 0
        if !force, tab.id == selectedTabID, webView.currentTabID == engineID { return }

        if let leaving = selectedTab, leaving.id != tab.id {
            answerPendingDialog(on: leaving)
        }

        selectedTabID = tab.id
        webView.currentTabID = engineID
        addressText = tab.currentURL

        if let wsID = tab.workspaceID {
            spacesManager.updateActiveTab(for: wsID, tabID: tab.id)
        } else {
            // Essential tab selected: remember in active workspace
            spacesManager.updateActiveTab(for: spacesManager.activeWorkspaceID, tabID: tab.id)
        }

        if engineID != 0 {
            presentCurrentFrame(of: engineID)
            applyViewport(width: Int32(webView.bounds.width), height: Int32(webView.bounds.height), scale: viewportScale)
        }
        refreshHistoryAvailability()
    }

    public func closeTab(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }

        let wasSelected = tab.id == selectedTabID
        let neighbour: BrowserTab? = {
            guard wasSelected else { return nil }
            // Prefer next in the same workspace / active tier
            let visible = activeNormalTabs + activePinnedTabs + essentialTabs
            if let visIdx = visible.firstIndex(where: { $0.id == tab.id }) {
                if visIdx + 1 < visible.count { return visible[visIdx + 1] }
                if visIdx > 0 { return visible[visIdx - 1] }
            }
            if index + 1 < tabs.count { return tabs[index + 1] }
            if index > 0 { return tabs[index - 1] }
            return nil
        }()

        answerPendingDialog(on: tab)
        let engineID = tab.engineID

        tabs.remove(at: index)
        spacesManager.removeTab(id: tab.id)

        if let neighbour {
            select(neighbour, force: true)
        } else if tabs.isEmpty {
            selectedTabID = nil
            webView.currentTabID = 0
            addressText = ""
        }

        if let engineID {
            app?.destroyTab(engineID)
        }
    }

    public func closeSelectedTab() {
        guard let selectedTab else { return }
        closeTab(selectedTab)
    }

    public func setTier(for tab: BrowserTab, tier: TabTier) {
        tab.setTier(tier)
        spacesManager.setTier(for: tab.id, tier: tier)
    }

    public func closeAllUnpinnedInActiveWorkspace() {
        let toClose = activeNormalTabs
        for tab in toClose {
            closeTab(tab)
        }
    }

    // MARK: - Dialogs

    private static func takeDialogID() -> UInt64 {
        defer { nextDialogID += 1 }
        return nextDialogID
    }

    private func presentDialog(_ dialog: TabDialog, for engineTabID: UInt64) {
        guard let tab = tabs.first(where: { $0.engineID == engineTabID }) else {
            answerImmediately(dialog, for: engineTabID)
            return
        }
        tab.present(dialog: dialog)
    }

    private func answerImmediately(_ dialog: TabDialog, for engineTabID: UInt64) {
        guard let app else { return }
        switch dialog {
        case .alert:
            app.answerAlert(in: engineTabID)
        case .confirm:
            app.answerConfirm(in: engineTabID, accept: false)
        case .prompt:
            app.answerPrompt(in: engineTabID, response: nil)
        case .beforeUnload:
            app.answerBeforeUnload(in: engineTabID, accept: true)
        }
    }

    public func answer(_ dialog: TabDialog, on tab: BrowserTab, accepted: Bool, promptText: String? = nil) {
        guard let app, let engineID = tab.engineID else { return }
        tab.clearDialog()
        switch dialog {
        case .alert:
            app.answerAlert(in: engineID)
        case .confirm:
            app.answerConfirm(in: engineID, accept: accepted)
        case .prompt:
            app.answerPrompt(in: engineID, response: accepted ? (promptText ?? "") : nil)
        case .beforeUnload:
            app.answerBeforeUnload(in: engineID, accept: accepted)
        }
    }

    private func answerPendingDialog(on tab: BrowserTab) {
        guard let dialog = tab.dialog, let engineID = tab.engineID else { return }
        tab.clearDialog()
        answerImmediately(dialog, for: engineID)
    }

    // MARK: - History & Navigation

    public func goBack() {
        guard let app, let engineID = selectedTab?.engineID else { return }
        app.traverseHistory(.back, in: engineID)
    }

    public func goForward() {
        guard let app, let engineID = selectedTab?.engineID else { return }
        app.traverseHistory(.forward, in: engineID)
    }

    private func refreshHistoryAvailability() {
        guard let app, let engineID = selectedTab?.engineID else {
            canGoBack = false
            canGoForward = false
            return
        }
        canGoBack = app.canTraverseHistory(.back, in: engineID)
        canGoForward = app.canTraverseHistory(.forward, in: engineID)
    }

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
        guard let app else {
            tab.update(url: input)
            spacesManager.updateTab(id: tab.id, url: input)
            return
        }
        guard let engineID = rehydrate(tab) else { return }

        guard let url = app.load(input, in: engineID) else {
            failure = "Could not resolve \(input) as a URL or a search."
            return
        }
        addressText = url
        tab.setLoading(true)
        tab.update(url: url)
        spacesManager.updateTab(id: tab.id, url: url)
        PortBenchmark.shared.recordLoad(url: url)
    }

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

    private func handleURLChange(_ engineTabID: UInt64, _ url: String) {
        guard let tab = tabs.first(where: { $0.engineID == engineTabID }) else { return }
        tab.update(url: url)
        spacesManager.updateTab(id: tab.id, url: url)
        if tab.id == selectedTabID {
            addressText = url
            refreshHistoryAvailability()
        }
    }

    private func handleLoadFinish(_ engineTabID: UInt64, _ url: String) {
        guard let tab = tabs.first(where: { $0.engineID == engineTabID }) else { return }
        tab.update(url: url)
        tab.setLoading(false)
        spacesManager.updateTab(id: tab.id, url: url)
        if tab.id == selectedTabID {
            addressText = url
            refreshHistoryAvailability()
        }
    }

    private func handlePaint(_ paintedEngineTab: UInt64) {
        guard paintedEngineTab == selectedTab?.engineID else { return }
        presentCurrentFrame(of: paintedEngineTab)
    }

    // MARK: - Presentation

    private var viewportScale: Double {
        Double(webView.window?.backingScaleFactor ?? 1)
    }

    private func applyViewport(width: Int32, height: Int32, scale: Double) {
        guard let app, let engineID = selectedTab?.engineID else { return }
        app.setViewport(in: engineID, width: width, height: height, scale: scale)
    }

    private func presentCurrentFrame(of engineTabID: UInt64) {
        guard let app, let surface = app.surface(in: engineTabID) else { return }
        PortBenchmark.shared.recordPaint(
            painted: (surface.paintedWidth, surface.paintedHeight),
            surface: (surface.surfaceWidth, surface.surfaceHeight),
            cssSize: webView.bounds.size
        )
        webView.present(surface)
    }
}
