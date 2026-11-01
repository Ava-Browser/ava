/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Navigation lifecycle, driven through the same callback seams the integration tests use: a model with no engine and
 * an engine id it was told about.
 */

import Foundation
import Testing

@testable import LadybirdEngine

@Suite("Navigation lifecycle")
@MainActor
struct NavigationLifecycleTests {
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

    /// A restored descriptor has no engine tab, and every handler keys on the engine's id.
    private func adopt(_ model: BrowserModel, engineID: UInt64) throws -> BrowserTab {
        let parent = try #require(model.selectedTab)
        return try #require(model.adoptEngineTab(parent: parent, engineID: engineID, activate: true))
    }

    /// The point of wiring `on_load_start` at all: the spinner and the stop button have to appear on the click, not once
    /// the load state catches up. A tab that is loading before its first frame is also what makes the reload control
    /// offer "stop" during a slow navigation.
    @Test("A navigation starts loading at on_load_start")
    func loadStartMarksLoading() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try adopt(model, engineID: 42)

        #expect(model.isLoading == false)
        model.handleLoadStart(42)
        #expect(model.isLoading)
    }

    /// The commit says the engine's history belongs to a different document. It is also the only signal a same-URL
    /// commit produces, so it must not depend on `onURLChange` having fired.
    @Test("A committed top-level navigation survives a URL that never changed")
    func commitWithoutURLChange() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let tab = try adopt(model, engineID: 42)

        model.handleLoadStart(42)
        model.handleURLChange(42, "https://redirected.example/final")
        model.handleTopLevelNavigationCommit(42)

        #expect(model.selectedTab?.currentURL == "https://redirected.example/final")
        #expect(tab.currentURL == "https://redirected.example/final")
    }

    /// A crashed renderer that commits a new document is alive again. Leaving the overlay up would tell the user a
    /// working page had failed.
    @Test("Committing a document clears a stale crash overlay")
    func commitClearsCrash() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try adopt(model, engineID: 42)

        model.setCrashed(true, on: 42)
        #expect(model.isCrashed)

        model.handleTopLevelNavigationCommit(42)
        #expect(model.isCrashed == false)
    }

    @Test("Lifecycle events for an unknown engine tab are ignored")
    func unknownEngineTab() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        model.handleLoadStart(999_999)
        model.handleTopLevelNavigationCommit(999_999)

        #expect(model.isLoading == false)
        #expect(model.selectedTab?.isCrashed == false)
    }
}
