/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Crash state is bookkeeping on top of a model that already exists. No engine, no window: the callbacks are driven the
 * same way `adoptEngineTab` is — with an engine id the model was told about.
 */

import Foundation
import Testing

@testable import LadybirdEngine

@Suite("Crash overlay state")
@MainActor
struct CrashStateTests {
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

    /// The overlay is per-tab and must not become a window-wide flag: a background tab crashing while the user reads
    /// another page is not something to interrupt them with, and clearing it there would hide a live tab's overlay.
    @Test("A crash marks only the tab it reported")
    func crashIsPerTab() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let parent = try #require(model.selectedTab)
        let background = try #require(model.adoptEngineTab(parent: parent, engineID: 42, activate: false))
        model.select(parent, force: true)

        model.setCrashed(true, on: 42)

        #expect(background.isCrashed)
        #expect(model.selectedTab?.isCrashed == false)
        #expect(model.isCrashed == false)
    }

    @Test("The selected tab's crash reaches the chrome")
    func crashReachesChrome() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let parent = try #require(model.selectedTab)

        model.setCrashed(true, on: try #require(parent.engineID))

        #expect(model.isCrashed)
        #expect(model.selectedTab?.isCrashed == true)
    }

    /// An id the model never registered is an engine tab it does not own. Touching any tab then would mark an unrelated
    /// page as dead — the one failure mode that makes this feature worse than ignoring the callback.
    @Test("A crash for an unknown engine tab touches nothing")
    func unknownEngineTabIsIgnored() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let parent = try #require(model.selectedTab)

        model.setCrashed(true, on: 999_999)

        #expect(model.isCrashed == false)
        #expect(parent.isCrashed == false)
    }

    @Test("The engine's overlay state is authoritative in both directions")
    func overlayStateBothWays() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let engineID = try #require(model.selectedTab?.engineID)

        model.setCrashed(true, on: engineID)
        #expect(model.isCrashed)
        model.setCrashed(false, on: engineID)
        #expect(model.isCrashed == false)
    }

    /// A crashed descriptor that is torn down and rehydrated is a new renderer, so the old crash must not survive it.
    @Test("Detaching a tab clears its crashed state")
    func detachClearsCrash() throws {
        let (model, store) = makeModel()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let tab = try #require(model.selectedTab)

        model.setCrashed(true, on: try #require(tab.engineID))
        tab.detach()

        #expect(tab.isCrashed == false)
        #expect(model.isCrashed == false)
    }
}
