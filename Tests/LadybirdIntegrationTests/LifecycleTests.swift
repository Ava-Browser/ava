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

    /// The point of wiring `on_load_start` at all: the spinner and the stop button have to appear on the click, not once
    /// the load state catches up. A tab that is loading before its first frame is also what makes the reload control
    /// offer "stop" during a slow navigation.
    @Test("A navigation starts loading at on_load_start")
    func loadStartMarksLoading() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let engineID = try #require(model.selectedTab?.engineID)

        #expect(model.isLoading == false)
        model.handleLoadStart(engineID)
        #expect(model.isLoading)
    }

    /// The commit says the engine's history belongs to a different document. It is also the only signal a same-URL
    /// commit produces, so it must not depend on `onURLChange` having fired.
    @Test("A committed top-level navigation survives a URL that never changed")
    func commitWithoutURLChange() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let tab = try #require(model.selectedTab)
        let engineID = try #require(tab.engineID)

        model.handleLoadStart(engineID)
        model.handleTopLevelNavigationCommit(engineID)

        #expect(model.selectedTab?.currentURL == "https://example.com")
    }

    /// A crashed renderer that commits a new document is alive again. Leaving the overlay up would tell the user a
    /// working page had failed.
    @Test("Committing a document clears a stale crash overlay")
    func commitClearsCrash() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let engineID = try #require(model.selectedTab?.engineID)

        model.setCrashed(true, on: engineID)
        #expect(model.isCrashed)

        model.handleTopLevelNavigationCommit(engineID)
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
