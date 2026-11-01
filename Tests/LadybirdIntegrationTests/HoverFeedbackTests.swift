/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Hover feedback is the one piece of chrome whose failure is silent: a stale label or tooltip points at a link the user
 * is no longer over, and nothing about the page looks wrong. Every case here is a way that could happen.
 */

import AppKit
import Foundation
import Testing

@testable import LadybirdEngine

@Suite("Hovered link and tooltips")
@MainActor
struct HoverFeedbackTests {
    private func temporaryStore() -> GraphStore {
        GraphStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json"))
    }

    private func makeModel() -> (BrowserModel, GraphStore) {
        let store = temporaryStore()
        let manager = WorkspaceManager(store: store)
        _ = manager.createWorkspace(name: "Only")
        _ = manager.createTab(url: "https://example.com")
        return (BrowserModel(store: store), store)
    }

    /// A restored descriptor has no engine tab until one is adopted, and every handler keys on the engine's id.
    private func adopt(_ model: BrowserModel, engineID: UInt64) throws -> BrowserTab {
        let parent = try #require(model.selectedTab)
        return try #require(model.adoptEngineTab(parent: parent, engineID: engineID, activate: true))
    }

    @Test("Hovering a link reports its destination, unhovering clears it")
    func hoverAndUnhover() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let tab = try adopt(model, engineID: 42)
        model.handleLinkHover(42, "https://elsewhere.example/page")
        #expect(model.hoveredLink == "https://elsewhere.example/page")

        model.handleLinkUnhover(42)
        #expect(model.hoveredLink == nil)
        #expect(tab.isLoaded)
    }

    /// A background tab can emit hover as its page scrolls under a pointer the user is not moving; showing it would
    /// label a link on a page that is not even visible.
    @Test("A background tab's hover does not reach the label")
    func backgroundTabHoverIsIgnored() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let parent = try #require(model.selectedTab)
        let background = try #require(model.adoptEngineTab(parent: parent, engineID: 42, activate: false))
        model.select(parent, force: true)

        model.handleLinkHover(42, "https://hidden.example")
        #expect(model.hoveredLink == nil)
        #expect(background.currentURL == "about:blank")

        // ... and the same for a tab the model does not own.
        model.handleLinkHover(999_999, "https://unknown.example")
        #expect(model.hoveredLink == nil)
    }

    /// The pointer never reports leaving the link when the page it was over goes away, so the navigation has to.
    @Test("A URL change clears a hover from the document being replaced")
    func urlChangeClearsHover() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let tab = try adopt(model, engineID: 42)

        model.handleLinkHover(42, "https://elsewhere.example")
        model.handleURLChange(42, "https://current.example/next")

        #expect(model.hoveredLink == nil)
        #expect(tab.currentURL == "https://current.example/next")
    }

    @Test("Starting a navigation clears a hover")
    func loadStartClearsHover() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try adopt(model, engineID: 42)

        model.handleLinkHover(42, "https://elsewhere.example")
        model.handleLoadStart(42)

        #expect(model.hoveredLink == nil)
    }

    /// Clicking a link to another tab is a tab switch, and the label followed the page. It must not carry over to the
    /// tab that becomes visible — the pointer is over a link on a page the user has just left.
    @Test("Switching tabs clears the hover")
    func tabSwitchClearsHover() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let first = try adopt(model, engineID: 42)
        let second = try #require(model.adoptEngineTab(parent: first, engineID: 43, activate: true))
        model.select(first, force: true)

        model.handleLinkHover(42, "https://elsewhere.example")
        #expect(model.hoveredLink != nil)

        model.select(second, force: true)
        #expect(model.hoveredLink == nil)
    }

    /// The view has one tooltip slot, so the label and the tooltip have to be cleared by the same gesture. A tooltip
    /// left behind appears over the next page, which is worse than no tooltip at all.
    @Test("The page's tooltip is cleared with the hover")
    func tooltipClearsWithHover() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try adopt(model, engineID: 42)

        model.webView.applyTooltip("Save changes")
        #expect(model.webView.toolTip == "Save changes")

        model.handleURLChange(42, "https://current.example/next")
        #expect(model.webView.toolTip == nil)
    }

    /// A renderer that dies mid-hover can never send the leave event, so the crash itself has to retract both halves of
    /// the feedback. Otherwise the strip and the tooltip keep naming a link on a page that is no longer running.
    @Test("A crash on the selected tab clears the hovered link and the tooltip")
    func selectedTabCrashClearsHover() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try adopt(model, engineID: 42)

        model.handleLinkHover(42, "https://elsewhere.example/page")
        model.webView.applyTooltip("Save changes")
        #expect(model.hoveredLink != nil)
        #expect(model.webView.toolTip == "Save changes")

        model.setCrashed(true, on: 42)
        #expect(model.hoveredLink == nil)
        #expect(model.webView.toolTip == nil)
    }

    /// The mirror of `backgroundTabHoverIsIgnored`: a background tab crashing must not blank the label that belongs to
    /// the page actually on screen, and a crash being *cleared* must not clear feedback either.
    @Test("A background tab's crash leaves the selected tab's hover alone")
    func backgroundCrashLeavesHover() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        // 42 is the visible tab; 99 is a second tab in another space, so it is never the selected one.
        let selected = try adopt(model, engineID: 42)
        _ = try #require(model.adoptEngineTab(parent: selected, engineID: 99, activate: false))
        model.select(selected, force: true)

        model.handleLinkHover(42, "https://elsewhere.example/page")
        model.webView.applyTooltip("Save changes")

        model.setCrashed(true, on: 99)
        #expect(model.hoveredLink == "https://elsewhere.example/page")
        #expect(model.webView.toolTip == "Save changes")

        // Clearing a crash is not a crash: it must never retract feedback on its own.
        model.setCrashed(false, on: 42)
        #expect(model.hoveredLink == "https://elsewhere.example/page")
    }

    @Test("An empty tooltip clears the slot rather than showing nothing")
    func emptyTooltipClears() {
        let view = PortWebView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))

        view.applyTooltip("Save changes")
        view.applyTooltip("")
        #expect(view.toolTip == nil)

        view.applyTooltip(nil)
        #expect(view.toolTip == nil)
    }
}
