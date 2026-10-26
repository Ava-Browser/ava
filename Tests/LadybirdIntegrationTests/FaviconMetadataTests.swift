/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Tests for favicon, title, and metadata state and persistence in LadybirdEngine.
 */

import AppKit
import Foundation
import Testing

@testable import LadybirdEngine

@Suite("Favicon and tab metadata state")
@MainActor
struct FaviconMetadataTests {
    private func temporaryStore() -> GraphStore {
        GraphStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json"))
    }

    @Test("BrowserTab initializes with default title and nil favicon")
    func tabDefaults() {
        let descriptor = TabDescriptor(workspaceID: nil, tier: .normal, url: "https://example.com")
        let tab = BrowserTab(descriptor: descriptor)

        #expect(tab.title == "New Tab")
        #expect(tab.favicon == nil)
        #expect(tab.faviconRef == nil)
        #expect(tab.isLoading == false)
    }

    @Test("Updating title sets real document title and preserves it across URL updates")
    func titleUpdateAndPreservation() {
        let descriptor = TabDescriptor(workspaceID: nil, tier: .normal, url: "https://example.com")
        let tab = BrowserTab(descriptor: descriptor)

        tab.updateTitle("Example Domain - Welcome")
        #expect(tab.title == "Example Domain - Welcome")

        // Subsequent URL update with non-empty title does not overwrite the real title
        tab.update(url: "https://example.com/subpage")
        #expect(tab.title == "Example Domain - Welcome")
        #expect(tab.currentURL == "https://example.com/subpage")

        // about:blank resets to "New Tab"
        tab.update(url: "about:blank")
        #expect(tab.title == "New Tab")
    }

    @Test("Favicon updates and clears correctly, and survives tab detach")
    func faviconLifecycle() {
        let descriptor = TabDescriptor(workspaceID: nil, tier: .normal, url: "https://example.com")
        let tab = BrowserTab(descriptor: descriptor)

        // Mock 1x1 NSImage
        let image = NSImage(size: NSSize(width: 16, height: 16))
        let hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        tab.updateFavicon(image: image, ref: hash)
        #expect(tab.favicon != nil)
        #expect(tab.faviconRef == hash)

        // Detaching (unloading) preserves the favicon and faviconRef for resting display
        tab.detach()
        #expect(tab.isLoaded == false)
        #expect(tab.favicon != nil)
        #expect(tab.faviconRef == hash)

        // Explicit clear resets both
        tab.clearFavicon()
        #expect(tab.favicon == nil)
        #expect(tab.faviconRef == nil)
    }

    @Test("Favicon hash reference persists through WorkspaceManager graph store")
    func persistenceRoundTrip() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let manager = WorkspaceManager(store: store)
        _ = manager.createWorkspace(name: "Test Space", icon: "globe")
        let tab = try #require(manager.createTab(tier: .normal, url: "https://example.com"))
        let tabID = tab.id

        let hash = "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
        manager.updateTab(tabID, url: "https://example.com", title: "Example Domain", faviconRef: hash)

        // Verify stored in active manager
        let descriptor = try #require(manager.descriptor(tabID))
        #expect(descriptor.title == "Example Domain")
        #expect(descriptor.faviconRef == hash)

        // Re-read from disk in fresh manager
        let restored = WorkspaceManager(store: store)
        let restoredDesc = try #require(restored.descriptor(tabID))
        #expect(restoredDesc.title == "Example Domain")
        #expect(restoredDesc.faviconRef == hash)

        // Clear faviconRef
        manager.updateTab(tabID, url: "https://example.com", title: "Example Domain", clearFaviconRef: true)
        let clearedDesc = try #require(manager.descriptor(tabID))
        #expect(clearedDesc.faviconRef == nil)
    }
}
