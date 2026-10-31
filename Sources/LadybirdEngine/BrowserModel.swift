/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The runtime half of the browser. WorkspaceManager owns durable truth; engine tabs here are an evictable render cache.
 */

import AppKit
import LadybirdBridge
import Observation

@MainActor
@Observable
public final class BrowserModel {
    public let workspaceManager: WorkspaceManager

    /// Runtime objects exist for every descriptor so unloaded rows still have a stable observable identity.
    private var runtimeTabs: [TabID: BrowserTab]
    @ObservationIgnored private var engineToTab: [UInt64: TabID] = [:]

    public private(set) var canGoBack = false
    public private(set) var canGoForward = false
    public var addressText = ""
    public var focusAddressRequested = false
    public private(set) var failure: String?

    @ObservationIgnored private static var processApp: PortApp?
    @ObservationIgnored private static var nextDialogID: UInt64 = 1
    @ObservationIgnored public let webView: PortWebView
    @ObservationIgnored private var app: PortApp?
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private let newTabURLProvider: (() -> String)?
    @ObservationIgnored private let faviconStore: FaviconStore

    public init(
        store: GraphStore = .applicationDefault(),
        faviconStore: FaviconStore = .applicationDefault(),
        newTabURLProvider: (() -> String)? = nil
    ) {
        let manager = WorkspaceManager(store: store)
        workspaceManager = manager
        self.faviconStore = faviconStore
        // Restored rows paint their cached icon before the engine exists, so the sidebar is not a wall of globes.
        runtimeTabs = Dictionary(uniqueKeysWithValues: manager.tabs.map { descriptor in
            let ref = descriptor.faviconRef
            return (descriptor.id, BrowserTab(descriptor: descriptor, favicon: ref.flatMap(faviconStore.image(for:))))
        })
        webView = PortWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.newTabURLProvider = newTabURLProvider
    }

    public var workspaces: [Workspace] { workspaceManager.workspaces }
    public var activeWorkspace: Workspace? { workspaceManager.activeWorkspace }
    public var selectedTabID: TabID? { workspaceManager.activeTabID }
    public var selectedTab: BrowserTab? { selectedTabID.flatMap { runtimeTabs[$0] } }
    public var currentURL: String { selectedTab?.currentURL ?? "" }
    public var isLoading: Bool { selectedTab?.isLoading ?? false }

    public var essentialTabs: [BrowserTab] { runtime(for: workspaceManager.tabs(in: .essential)) }
    public var pinnedTabs: [BrowserTab] { runtime(for: workspaceManager.tabs(in: .pinned)) }
    public var normalTabs: [BrowserTab] { runtime(for: workspaceManager.tabs(in: .normal)) }
    public var tabs: [BrowserTab] { essentialTabs + pinnedTabs + normalTabs }

    public func start(homeURL: String = "https://example.com", overrideRestoredTab: Bool = false) {
        guard app == nil, failure == nil else { return }
        let isRestoring = workspaceManager.activeTabID != nil

        var callbacks = PortCallbacks()
        callbacks.onURLChange = { [weak self] engineID, url in
            MainActor.assumeIsolated { self?.handleURLChange(engineID, url) }
        }
        callbacks.onLoadFinish = { [weak self] engineID, url in
            MainActor.assumeIsolated { self?.handleLoadFinish(engineID, url) }
        }
        callbacks.onTitleChange = { [weak self] engineID, title in
            MainActor.assumeIsolated { self?.handleTitleChange(engineID, title) }
        }
        callbacks.onLoadingStateChange = { [weak self] engineID, isLoading in
            MainActor.assumeIsolated { self?.handleLoadingStateChange(engineID, isLoading) }
        }
        callbacks.onFaviconChange = { [weak self] engineID, data, hash in
            MainActor.assumeIsolated { self?.handleFaviconChange(engineID, data, hash) }
        }
        callbacks.onReadyToPaint = { [weak self] engineID in
            MainActor.assumeIsolated { self?.handlePaint(engineID) }
        }
        callbacks.onRequestAlert = { [weak self] engineID, message in
            MainActor.assumeIsolated { self?.presentDialog(.alert(id: Self.takeDialogID(), message: message), for: engineID) }
        }
        callbacks.onRequestConfirm = { [weak self] engineID, message in
            MainActor.assumeIsolated { self?.presentDialog(.confirm(id: Self.takeDialogID(), message: message), for: engineID) }
        }
        callbacks.onRequestPrompt = { [weak self] engineID, message, defaultText in
            MainActor.assumeIsolated {
                self?.presentDialog(.prompt(id: Self.takeDialogID(), message: message, defaultText: defaultText), for: engineID)
            }
        }
        callbacks.onRequestBeforeUnload = { [weak self] engineID, source in
            MainActor.assumeIsolated {
                self?.presentDialog(.beforeUnload(id: Self.takeDialogID(), source: source), for: engineID)
            }
        }

        guard Self.processApp == nil else {
            failure = "Internal error: a second browser model tried to start the engine."
            return
        }
        // Hover feedback: the page's cursor and its hovered link. Without the cursor half, every element looks inert
        // however correctly it is styled, because the pointer never changes shape.
        var ui = PortUICallbacks()
        ui.onCursorChange = { [weak self] engineID, cursor in
            MainActor.assumeIsolated {
                guard let self, engineID == self.selectedTab?.engineID else { return }
                self.webView.applyCursor(cursor)
            }
        }

        guard let app = PortApp(callbacks: callbacks, ui: ui) else {
            failure = """
                The engine could not be started.

                Launch through Scripts/run.sh: it exports LADYBIRD_BINARY_PATH and DYLD_LIBRARY_PATH, which the engine \
                needs to find its helper processes and the Lagom dylibs.
                """
            return
        }
        Self.processApp = app
        self.app = app
        installWebViewCallbacks()

        if workspaceManager.workspaces.isEmpty {
            _ = workspaceManager.createWorkspace(name: "Personal", icon: "circle.fill")
        }
        if workspaceManager.activeTabID == nil {
            _ = openTab(url: homeURL)
        } else if let selectedTab {
            // `--url` is an explicit caller request (benchmarks and regression fixtures depend on it), so replace the
            // selected descriptor before rehydration. Starting its restored request and immediately superseding it
            // would create two loads and make the fixture race the page it explicitly asked for.
            if isRestoring, overrideRestoredTab {
                selectedTab.update(url: homeURL)
                workspaceManager.updateTab(selectedTab.id, url: homeURL, title: selectedTab.title)
            }
            select(selectedTab, force: true)
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

    private func installWebViewCallbacks() {
        webView.onViewportChange = { [weak self] width, height, scale in
            MainActor.assumeIsolated { self?.applyViewport(width: width, height: height, scale: scale) }
        }
        webView.onMouse = { [weak self] type, x, y, button, buttons, clickCount, wheelDeltaY in
            MainActor.assumeIsolated {
                guard let self, let app = self.app, let id = self.selectedTab?.engineID else { return }
                app.sendMouse(
                    in: id, type: type, x: x, y: y, button: button, buttons: buttons,
                    clickCount: clickCount, wheelDeltaY: wheelDeltaY
                )
            }
        }
        webView.onKey = { [weak self] key, codePoint, modifiers, isKeyDown in
            MainActor.assumeIsolated {
                guard let self, let app = self.app, let id = self.selectedTab?.engineID else { return }
                app.sendKey(in: id, key: key, codePoint: codePoint, modifiers: modifiers, isKeyDown: isKeyDown)
            }
        }
        webView.onTypeText = { [weak self] text in
            MainActor.assumeIsolated {
                guard let self, let app = self.app, let id = self.selectedTab?.engineID else { return }
                app.typeText(text, in: id)
            }
        }
    }

    // MARK: - Spaces

    @discardableResult
    public func createWorkspace() -> Workspace {
        let workspace = workspaceManager.createWorkspace()
        _ = openTab()
        return workspace
    }

    public func selectWorkspace(_ workspace: Workspace) {
        guard workspace.id != workspaceManager.activeSpaceID else { return }
        if let selectedTab { answerPendingDialog(on: selectedTab) }
        workspaceManager.selectWorkspace(workspace.id)
        if let id = workspaceManager.activeTabID, let tab = runtimeTabs[id] {
            select(tab, force: true)
        } else if let first = (essentialTabs + pinnedTabs + normalTabs).first {
            select(first, force: true)
        } else {
            _ = openTab()
        }
    }

    public func selectNextWorkspace() {
        guard let active = activeWorkspace,
              let index = workspaces.firstIndex(where: { $0.id == active.id }),
              index + 1 < workspaces.count else { return }
        selectWorkspace(workspaces[index + 1])
    }

    public func selectPreviousWorkspace() {
        guard let active = activeWorkspace,
              let index = workspaces.firstIndex(where: { $0.id == active.id }),
              index > 0 else { return }
        selectWorkspace(workspaces[index - 1])
    }

    public func deleteWorkspace(_ workspace: Workspace) {
        guard workspaces.count > 1 else { return }
        let targetID = workspace.id
        guard workspaces.contains(where: { $0.id == targetID }) else { return }
        let isDeletingActive = workspaceManager.activeSpaceID == targetID

        // Collect all tabs belonging to this space
        let spaceDescriptors = workspaceManager.tabs.filter { $0.workspaceID == targetID }
        let spaceTabs = spaceDescriptors.compactMap { runtimeTabs[$0.id] }

        // 1. Resolve pending dialogs on tabs in the space to be deleted
        for tab in spaceTabs {
            answerPendingDialog(on: tab)
        }

        // 2. If deleting the active space, detach and clear the presented tab before destroying old handles
        if isDeletingActive {
            if let leaving = selectedTab {
                answerPendingDialog(on: leaving)
            }
            // Explicitly clear old presentation before attempting survivor selection, so that
            // any rehydration failure leaves the view safely cleared rather than bound to a destroyed handle.
            webView.currentTabID = 0
            webView.clearSurface()
            addressText = ""

            _ = workspaceManager.deleteWorkspace(targetID)

            if let survivor = selectedTab {
                select(survivor, force: true)
            } else if let first = (essentialTabs + pinnedTabs + normalTabs).first {
                select(first, force: true)
            }
        } else {
            // Inactive space deletion: active space and current page remain untouched
            _ = workspaceManager.deleteWorkspace(targetID)
        }

        // 3. Destroy handles and remove runtime tabs for the deleted space
        for tab in spaceTabs {
            if let engineID = tab.engineID {
                engineToTab.removeValue(forKey: engineID)
                app?.destroyTab(engineID)
            }
            runtimeTabs.removeValue(forKey: tab.id)
        }
        pruneFaviconCache()
    }

    @discardableResult
    public func renameWorkspace(_ workspace: Workspace, name: String) -> Bool {
        workspaceManager.renameWorkspace(workspace.id, name: name)
    }

    @discardableResult
    public func updateWorkspaceIcon(_ workspace: Workspace, icon: String) -> Bool {
        workspaceManager.updateWorkspaceIcon(workspace.id, icon: icon)
    }

    @discardableResult
    public func updateWorkspaceTheme(_ workspace: Workspace, theme: GradientSpec) -> Bool {
        workspaceManager.updateWorkspaceTheme(workspace.id, theme: theme)
    }

    @discardableResult
    public func reorderWorkspaces(_ newOrder: [UUID]) -> Bool {
        workspaceManager.reorderWorkspaces(newOrder)
    }

    public func moveWorkspace(fromOffsets: IndexSet, toOffset: Int) {
        workspaceManager.moveWorkspace(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    public func visibleTabs(includePinned: Bool = true) -> [BrowserTab] {
        if includePinned {
            return essentialTabs + pinnedTabs + normalTabs
        } else {
            return essentialTabs + normalTabs
        }
    }

    public func selectNextTab(includePinned: Bool = true) {
        let visible = visibleTabs(includePinned: includePinned)
        guard !visible.isEmpty else { return }
        guard let current = selectedTabID, let idx = visible.firstIndex(where: { $0.id == current }) else {
            if let first = visible.first { select(first) }
            return
        }
        let nextIdx = min(idx + 1, visible.count - 1)
        select(visible[nextIdx])
    }

    public func selectPreviousTab(includePinned: Bool = true) {
        let visible = visibleTabs(includePinned: includePinned)
        guard !visible.isEmpty else { return }
        guard let current = selectedTabID, let idx = visible.firstIndex(where: { $0.id == current }) else {
            if let last = visible.last { select(last) }
            return
        }
        let prevIdx = max(idx - 1, 0)
        select(visible[prevIdx])
    }

    // MARK: - Tabs

    @discardableResult
    public func openTab(url: String? = nil, tier: TabTier = .normal) -> BrowserTab? {
        let destination = url ?? (newTabURLProvider?() ?? AppSettings.shared.newTabURL)

        // If opening an unaddressed new tab, reuse an existing blank tab in the active space rather than creating duplicate empty tabs
        if url == nil, tier == .normal {
            if let existingBlank = normalTabs.first(where: { $0.currentURL == "about:blank" || $0.currentURL.isEmpty }) {
                select(existingBlank)
                focusAddressRequested = true
                return existingBlank
            }
        }

        guard app != nil, let descriptor = workspaceManager.createTab(tier: tier, url: destination) else { return nil }
        let tab = BrowserTab(descriptor: descriptor)
        runtimeTabs[tab.id] = tab
        select(tab, force: true)
        if url == nil {
            focusAddressRequested = true
        }
        return tab
    }

    public func select(_ tab: BrowserTab) { select(tab, force: false) }

    public func select(_ tab: BrowserTab, force: Bool) {
        if !force, tab.id == selectedTabID, webView.currentTabID == tab.engineID { return }
        if let leaving = selectedTab, leaving.id != tab.id { answerPendingDialog(on: leaving) }

        workspaceManager.selectTab(tab.id)
        let wasUnloaded = tab.engineID == nil
        guard rehydrate(tab) else { return }
        webView.currentTabID = tab.engineID ?? 0
        addressText = tab.currentURL == "about:blank" ? "" : tab.currentURL
        // Reset the view's de-duplication cache: SwiftUI may have reported this exact size before the engine tab existed.
        // The viewport must reach the new tab before its first navigation, not after its first wrong-sized paint.
        webView.reportViewportAfterTabCreation()
        if let engineID = tab.engineID, !presentCurrentFrame(of: engineID) {
            webView.clearSurface()
        }
        if wasUnloaded, tab.currentURL != "about:blank", !tab.currentURL.isEmpty {
            load(tab.currentURL, in: tab)
        }
        refreshHistoryAvailability()
    }

    /// Creates an engine cache entry only when a descriptor is activated. Relaunch therefore restores the complete
    /// graph without spawning one WebContent process per background tab.
    private func rehydrate(_ tab: BrowserTab) -> Bool {
        if tab.engineID != nil { return true }
        guard let app else { return false }
        let engineID = app.createTab()
        guard engineID != 0 else {
            failure = "The engine refused to create a tab; it could not load its system theme."
            return false
        }
        tab.attach(engineID: engineID)
        engineToTab[engineID] = tab.id
        return true
    }

    public func closeTab(_ tab: BrowserTab) {
        guard workspaceManager.descriptor(tab.id) != nil else { return }
        answerPendingDialog(on: tab)
        let engineID = tab.engineID
        workspaceManager.closeTab(tab.id)

        if let survivor = selectedTab {
            select(survivor, force: true)
        } else if let first = (essentialTabs + pinnedTabs + normalTabs).first {
            select(first, force: true)
        } else {
            webView.currentTabID = 0
            webView.clearSurface()
            addressText = ""
        }

        if let engineID {
            engineToTab.removeValue(forKey: engineID)
            app?.destroyTab(engineID)
        }
        runtimeTabs.removeValue(forKey: tab.id)
        pruneFaviconCache()
    }

    public func closeSelectedTab() {
        guard let selectedTab else { return }
        closeTab(selectedTab)
    }

    public func closeAllUnpinned() {
        let closing = normalTabs
        for tab in closing { answerPendingDialog(on: tab) }
        let closedIDs = workspaceManager.closeAllUnpinned()

        for id in closedIDs {
            guard let tab = runtimeTabs.removeValue(forKey: id), let engineID = tab.engineID else { continue }
            engineToTab.removeValue(forKey: engineID)
            app?.destroyTab(engineID)
        }

        if let selectedTab {
            select(selectedTab, force: true)
        } else {
            webView.currentTabID = 0
            webView.clearSurface()
            addressText = ""
        }
        pruneFaviconCache()
    }

    public func retier(_ tab: BrowserTab, to tier: TabTier) {
        workspaceManager.retier(tab.id, to: tier)
    }

    // MARK: - Dialogs

    private static func takeDialogID() -> UInt64 {
        defer { nextDialogID += 1 }
        return nextDialogID
    }

    private func presentDialog(_ dialog: TabDialog, for engineID: UInt64) {
        guard let id = engineToTab[engineID], let tab = runtimeTabs[id] else {
            answerImmediately(dialog, for: engineID)
            return
        }
        tab.present(dialog: dialog)
    }

    private func answerImmediately(_ dialog: TabDialog, for engineID: UInt64) {
        guard let app else { return }
        switch dialog {
        case .alert: app.answerAlert(in: engineID)
        case .confirm: app.answerConfirm(in: engineID, accept: false)
        case .prompt: app.answerPrompt(in: engineID, response: nil)
        case .beforeUnload: app.answerBeforeUnload(in: engineID, accept: true)
        }
    }

    public func answer(_ dialog: TabDialog, on tab: BrowserTab, accepted: Bool, promptText: String? = nil) {
        guard let app, let engineID = tab.engineID else { return }
        tab.clearDialog()
        switch dialog {
        case .alert: app.answerAlert(in: engineID)
        case .confirm: app.answerConfirm(in: engineID, accept: accepted)
        case .prompt: app.answerPrompt(in: engineID, response: accepted ? (promptText ?? "") : nil)
        case .beforeUnload: app.answerBeforeUnload(in: engineID, accept: accepted)
        }
    }

    private func answerPendingDialog(on tab: BrowserTab) {
        guard let dialog = tab.dialog, let engineID = tab.engineID else { return }
        tab.clearDialog()
        answerImmediately(dialog, for: engineID)
    }

    // MARK: - Navigation

    public func goBack() {
        guard let app, let id = selectedTab?.engineID else { return }
        app.traverseHistory(.back, in: id)
    }

    public func goForward() {
        guard let app, let id = selectedTab?.engineID else { return }
        app.traverseHistory(.forward, in: id)
    }

    private func refreshHistoryAvailability() {
        guard let app, let id = selectedTab?.engineID else {
            canGoBack = false
            canGoForward = false
            return
        }
        canGoBack = app.canTraverseHistory(.back, in: id)
        canGoForward = app.canTraverseHistory(.forward, in: id)
    }

    public func submitAddress() { load(addressText) }

    public func copyCurrentURL(to pasteboard: NSPasteboard = .general) {
        guard !currentURL.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(currentURL, forType: .string)
    }

    public func reload() {
        guard let selectedTab, !selectedTab.currentURL.isEmpty else { return }
        load(selectedTab.currentURL, in: selectedTab)
    }

    public func load(_ input: String) {
        guard let selectedTab else { return }
        load(input, in: selectedTab)
    }

    private func load(_ input: String, in tab: BrowserTab) {
        let wasUnloaded = tab.engineID == nil
        guard let app, rehydrate(tab), let engineID = tab.engineID else { return }
        if wasUnloaded, tab.id == selectedTabID {
            webView.reportViewportAfterTabCreation()
        }
        guard let url = app.load(input, in: engineID) else {
            failure = "Could not resolve \(input) as a URL or a search."
            return
        }
        tab.update(url: url)
        workspaceManager.updateTab(tab.id, url: url, title: tab.title, faviconRef: tab.faviconRef)
        if tab.id == selectedTabID { addressText = url }
        tab.setLoading(true)
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
        engineToTab.removeAll()
        for tab in runtimeTabs.values { tab.detach() }
    }

    // MARK: - Engine events

    /// Keyed by the engine's SHA-256 hash, so two tabs on one site share a single decoded image.
    ///
    /// Evicted to the hashes the live tabs still reference after each update: a browser left open for days would
    /// otherwise retain every icon it ever saw. Cheap because the bound is the tab count, not history length.
    private var faviconCache: [String: NSImage] = [:]

    private func handleURLChange(_ engineID: UInt64, _ url: String) {
        guard let id = engineToTab[engineID], let tab = runtimeTabs[id] else { return }
        tab.update(url: url)
        workspaceManager.updateTab(id, url: url, title: tab.title, faviconRef: tab.faviconRef)
        if id == selectedTabID {
            addressText = url
            refreshHistoryAvailability()
        }
    }

    private func handleLoadFinish(_ engineID: UInt64, _ url: String) {
        guard let id = engineToTab[engineID], let tab = runtimeTabs[id] else { return }
        tab.update(url: url)
        tab.setLoading(false)
        workspaceManager.updateTab(id, url: url, title: tab.title, faviconRef: tab.faviconRef)
        if id == selectedTabID {
            addressText = url
            refreshHistoryAvailability()
        }
    }

    private func handleTitleChange(_ engineID: UInt64, _ title: String) {
        guard let id = engineToTab[engineID], let tab = runtimeTabs[id] else { return }
        tab.updateTitle(title)
        workspaceManager.updateTab(id, url: tab.currentURL, title: tab.title, faviconRef: tab.faviconRef)
    }

    private func handleLoadingStateChange(_ engineID: UInt64, _ isLoading: Bool) {
        guard let id = engineToTab[engineID], let tab = runtimeTabs[id] else { return }
        tab.setLoading(isLoading)
    }

    private func handleFaviconChange(_ engineID: UInt64, _ data: Data?, _ hash: String?) {
        guard let id = engineToTab[engineID], let tab = runtimeTabs[id] else { return }
        guard let data, let hash, !hash.isEmpty else {
            tab.clearFavicon()
            workspaceManager.updateTab(id, url: tab.currentURL, title: tab.title, clearFaviconRef: true)
            pruneFaviconCache()
            return
        }

        let image: NSImage?
        if let cached = faviconCache[hash] {
            image = cached
        } else if let decoded = NSImage(data: data) {
            faviconCache[hash] = decoded
            image = decoded
        } else {
            image = nil
        }

        tab.updateFavicon(image: image, ref: hash)
        workspaceManager.updateTab(id, url: tab.currentURL, title: tab.title, faviconRef: hash)
        // Written even on a memory-cache hit: pruning may have deleted the file for a hash still held in memory, and
        // the reference is now persisted again. Synchronous by precedent: the `updateTab` above already rewrites the
        // whole graph inside this callback, and a few hundred bytes is the smaller of the two writes.
        // shortcut: main-thread file I/O inside an engine callback (R6); revisit if the icon set grows a byte quota.
        if image != nil { faviconStore.store(data, for: hash) }
        pruneFaviconCache()
    }

    /// Drops decoded icons no live tab references any more, in memory and on disk.
    private func pruneFaviconCache() {
        let live = Set(runtimeTabs.values.compactMap(\.faviconRef))
        faviconStore.prune(keeping: live)
        faviconCache = faviconCache.filter { live.contains($0.key) }
    }

    private func handlePaint(_ engineID: UInt64) {
        guard engineToTab[engineID] == selectedTabID else { return }
        presentCurrentFrame(of: engineID)
    }

    // MARK: - Presentation

    private var viewportScale: Double { Double(webView.window?.backingScaleFactor ?? 1) }

    private func applyViewport(width: Int32, height: Int32, scale: Double) {
        guard let app, let id = selectedTab?.engineID else { return }
        app.setViewport(in: id, width: width, height: height, scale: scale)
    }

    @discardableResult
    private func presentCurrentFrame(of engineID: UInt64) -> Bool {
        guard let app, let surface = app.surface(in: engineID) else { return false }
        PortBenchmark.shared.recordPaint(
            painted: (surface.paintedWidth, surface.paintedHeight),
            surface: (surface.surfaceWidth, surface.surfaceHeight),
            cssSize: webView.bounds.size
        )
        webView.present(surface)
        return true
    }

    private func runtime(for descriptors: [TabDescriptor]) -> [BrowserTab] {
        descriptors.map { descriptor in
            if let existing = runtimeTabs[descriptor.id] {
                return existing
            }
            let ref = descriptor.faviconRef
            let newTab = BrowserTab(descriptor: descriptor, favicon: ref.flatMap(faviconStore.image(for:)))
            runtimeTabs[descriptor.id] = newTab
            return newTab
        }
    }
}
