/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Unit and integration tests for space settings, metadata validation, reordering, and safe deletion.
 */

import Foundation
import Testing

@testable import LadybirdEngine

@Suite("Space settings and metadata")
@MainActor
struct SpaceSettingsTests {
    private func temporaryStore() -> GraphStore {
        GraphStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json"))
    }

    @Test("Valid name, icon, and theme changes persist, round-trip, and preserve container data")
    func validMetadataPersists() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let spaceID = UUID()
        let tabID = TabID()
        let initialSpace = Workspace(
            id: spaceID,
            name: "Initial",
            icon: "house.fill",
            theme: GradientSpec.palette[0],
            containerID: "profile-seeded-1",
            activeTabID: tabID,
            tabOrder: [tabID]
        )
        let initialTab = TabDescriptor(
            id: tabID,
            workspaceID: spaceID,
            tier: .normal,
            url: "https://example.com",
            title: "Example",
            containerID: "profile-seeded-1"
        )
        let seededGraph = PersistedGraph(
            activeSpaceID: spaceID,
            essentialOrder: [],
            workspaces: [initialSpace],
            tabs: [initialTab]
        )
        try store.save(seededGraph)

        let manager = WorkspaceManager(store: store)
        #expect(manager.workspaces.first?.containerID == "profile-seeded-1")
        #expect(manager.tabs.first?.containerID == "profile-seeded-1")

        #expect(manager.renameWorkspace(spaceID, name: "  Trimmed Name  "))
        #expect(manager.updateWorkspaceIcon(spaceID, icon: "star.fill"))
        #expect(manager.updateWorkspaceTheme(spaceID, theme: GradientSpec(startHex: "112233", endHex: "#AABBCC")))

        let restored = WorkspaceManager(store: store)
        let restoredSpace = try #require(restored.workspaces.first { $0.id == spaceID })
        #expect(restoredSpace.name == "Trimmed Name")
        #expect(restoredSpace.icon == "star.fill")
        #expect(restoredSpace.isSymbol == true)
        #expect(restoredSpace.theme.startHex == "#112233")
        #expect(restoredSpace.theme.endHex == "#AABBCC")
        #expect(restoredSpace.tabOrder == [tabID])
        #expect(restoredSpace.containerID == "profile-seeded-1")
        #expect(restored.tabs.first?.containerID == "profile-seeded-1")

        // Single-scalar emoji
        #expect(manager.updateWorkspaceIcon(spaceID, icon: "🚀"))
        let restoredEmoji = WorkspaceManager(store: store)
        let emojiSpace = try #require(restoredEmoji.workspaces.first { $0.id == spaceID })
        #expect(emojiSpace.icon == "🚀")
        #expect(emojiSpace.isSymbol == false)

        // Multi-scalar emojis (e.g. keycap/variation selectors)
        #expect(manager.updateWorkspaceIcon(spaceID, icon: "☕️"))
        let restoredCoffee = WorkspaceManager(store: store)
        #expect(restoredCoffee.workspaces.first?.icon == "☕️")
        #expect(restoredCoffee.workspaces.first?.isSymbol == false)

        #expect(manager.updateWorkspaceIcon(spaceID, icon: "🛠️"))
        let restoredTools = WorkspaceManager(store: store)
        #expect(restoredTools.workspaces.first?.icon == "🛠️")
        #expect(restoredTools.workspaces.first?.isSymbol == false)
    }

    @Test("Blank names, invalid icons (arbitrary strings, digits, symbols), invalid themes, and stale IDs are rejected")
    func invalidInputsRejected() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let manager = WorkspaceManager(store: store)
        let space = manager.createWorkspace(name: "Valid", icon: "house.fill")
        let staleID = UUID()

        // Blank and whitespace-only names
        #expect(!manager.renameWorkspace(space.id, name: ""))
        #expect(!manager.renameWorkspace(space.id, name: "   \n\t  "))
        #expect(!manager.renameWorkspace(staleID, name: "Stale"))

        // Invalid icons: arbitrary non-curated strings, plain digits, ascii symbols
        #expect(!manager.updateWorkspaceIcon(space.id, icon: ""))
        #expect(!manager.updateWorkspaceIcon(space.id, icon: "   "))
        #expect(!manager.updateWorkspaceIcon(space.id, icon: "not-a-symbol"))
        #expect(!manager.updateWorkspaceIcon(space.id, icon: "foo.bar"))
        #expect(!manager.updateWorkspaceIcon(space.id, icon: "1"))
        #expect(!manager.updateWorkspaceIcon(space.id, icon: "9"))
        #expect(!manager.updateWorkspaceIcon(space.id, icon: "#"))
        #expect(!manager.updateWorkspaceIcon(space.id, icon: "*"))
        #expect(!manager.updateWorkspaceIcon(staleID, icon: "star.fill"))

        // Curated symbols and default circle.grid.2x2.fill are accepted
        #expect(manager.updateWorkspaceIcon(space.id, icon: "circle.grid.2x2.fill"))
        #expect(manager.updateWorkspaceIcon(space.id, icon: "briefcase.fill"))

        // Invalid themes (malformed hex)
        #expect(!manager.updateWorkspaceTheme(space.id, theme: GradientSpec(startHex: "invalid", endHex: "#123456")))
        #expect(!manager.updateWorkspaceTheme(space.id, theme: GradientSpec(startHex: "#12345", endHex: "#123456")))
        #expect(!manager.updateWorkspaceTheme(staleID, theme: GradientSpec(startHex: "#111111", endHex: "#222222")))

        // Verify graph is untouched by rejected inputs
        let restored = WorkspaceManager(store: store)
        let restoredSpace = try #require(restored.workspaces.first { $0.id == space.id })
        #expect(restoredSpace.name == "Valid")
        #expect(restoredSpace.icon == "briefcase.fill")
    }

    @Test("Reorder workspaces preserves all tab/space IDs, tiers, selections, essentials, and container data")
    func reorderPreservesAllData() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let space1ID = UUID()
        let space2ID = UUID()
        let space3ID = UUID()
        let tab1ID = TabID()
        let tab2ID = TabID()
        let tab3ID = TabID()
        let essentialID = TabID()

        let seededGraph = PersistedGraph(
            activeSpaceID: space2ID,
            essentialOrder: [essentialID],
            workspaces: [
                Workspace(id: space1ID, name: "Space 1", icon: "house.fill", theme: GradientSpec.palette[0], containerID: "cont-1", activeTabID: tab1ID, tabOrder: [tab1ID]),
                Workspace(id: space2ID, name: "Space 2", icon: "star.fill", theme: GradientSpec.palette[1], containerID: "cont-2", activeTabID: tab2ID, tabOrder: [tab2ID]),
                Workspace(id: space3ID, name: "Space 3", icon: "book.fill", theme: GradientSpec.palette[2], containerID: "cont-3", activeTabID: tab3ID, tabOrder: [tab3ID]),
            ],
            tabs: [
                TabDescriptor(id: essentialID, workspaceID: nil, tier: .essential, url: "https://essential.com"),
                TabDescriptor(id: tab1ID, workspaceID: space1ID, tier: .normal, url: "https://one.com"),
                TabDescriptor(id: tab2ID, workspaceID: space2ID, tier: .pinned, url: "https://two.com"),
                TabDescriptor(id: tab3ID, workspaceID: space3ID, tier: .normal, url: "https://three.com"),
            ]
        )
        try store.save(seededGraph)

        let manager = WorkspaceManager(store: store)

        // Invalid reorders rejected
        #expect(!manager.reorderWorkspaces([space1ID, space2ID])) // Missing space3
        #expect(!manager.reorderWorkspaces([space1ID, space2ID, UUID()])) // Unknown UUID
        #expect(!manager.reorderWorkspaces([space1ID, space1ID, space2ID])) // Duplicate

        // Valid reorder: 3, 1, 2
        #expect(manager.reorderWorkspaces([space3ID, space1ID, space2ID]))

        let restored = WorkspaceManager(store: store)
        #expect(restored.workspaces.map(\.id) == [space3ID, space1ID, space2ID])
        #expect(restored.workspaces.map(\.containerID) == ["cont-3", "cont-1", "cont-2"])
        #expect(restored.activeSpaceID == space2ID)
        #expect(restored.activeTabID == tab2ID)
        #expect(restored.essentialOrder == [essentialID])

        // Verify tabs in each space
        #expect(restored.tabs(in: .normal, workspaceID: space1ID).map(\.id) == [tab1ID])
        #expect(restored.tabs(in: .pinned, workspaceID: space2ID).map(\.id) == [tab2ID])
        #expect(restored.tabs(in: .normal, workspaceID: space3ID).map(\.id) == [tab3ID])
    }

    @Test("reorderWorkspaces safely rejects graphs with duplicate workspace UUIDs without crashing or losing data")
    func duplicateUUIDReorderSafety() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let duplicateID = UUID()
        let seededGraph = PersistedGraph(
            activeSpaceID: duplicateID,
            essentialOrder: [],
            workspaces: [
                Workspace(id: duplicateID, name: "Dup 1", icon: "house.fill", theme: GradientSpec.palette[0]),
                Workspace(id: duplicateID, name: "Dup 2", icon: "star.fill", theme: GradientSpec.palette[1])
            ],
            tabs: []
        )
        try store.save(seededGraph)

        let manager = WorkspaceManager(store: store)
        #expect(manager.workspaces.count == 2)

        // Attempting to reorder must safely return false rather than trapping in Dictionary(uniqueKeysWithValues:)
        let reordered = manager.reorderWorkspaces([duplicateID, duplicateID])
        #expect(!reordered)

        // Graph data and order are preserved without dropping data
        #expect(manager.workspaces.count == 2)
        #expect(manager.workspaces[0].name == "Dup 1")
        #expect(manager.workspaces[1].name == "Dup 2")
    }

    @Test("moveWorkspace validates bounds and handles boundary and multi-index moves")
    func moveWorkspaceBounds() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let manager = WorkspaceManager(store: store)
        let s0 = manager.createWorkspace(name: "0")
        let s1 = manager.createWorkspace(name: "1")
        let s2 = manager.createWorkspace(name: "2")
        let s3 = manager.createWorkspace(name: "3")

        // Out-of-bounds destination ignored
        manager.moveWorkspace(fromOffsets: IndexSet(integer: 0), toOffset: -1)
        manager.moveWorkspace(fromOffsets: IndexSet(integer: 0), toOffset: 10)
        #expect(manager.workspaces.map(\.name) == ["0", "1", "2", "3"])

        // Out-of-bounds source index ignored
        manager.moveWorkspace(fromOffsets: IndexSet(integer: 99), toOffset: 0)
        #expect(manager.workspaces.map(\.name) == ["0", "1", "2", "3"])

        // Boundary move: move last to first (destination 0)
        manager.moveWorkspace(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(manager.workspaces.map(\.name) == ["3", "0", "1", "2"])

        // Boundary move: move first to end (destination 4)
        manager.moveWorkspace(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        #expect(manager.workspaces.map(\.name) == ["0", "1", "2", "3"])

        // Multi-index move: move indices [0, 1] to end (destination 4)
        manager.moveWorkspace(fromOffsets: IndexSet([0, 1]), toOffset: 4)
        #expect(manager.workspaces.map(\.name) == ["2", "3", "0", "1"])

        let restored = WorkspaceManager(store: store)
        #expect(restored.workspaces.map(\.id) == [s2.id, s3.id, s0.id, s1.id])
    }

    @Test("Deleting the final space is rejected")
    func finalSpaceDeletionRefused() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let manager = WorkspaceManager(store: store)
        let space = manager.createWorkspace(name: "Single")
        let tab = try #require(manager.createTab(in: space.id, tier: .normal))

        let result = manager.deleteWorkspace(space.id)
        #expect(result == nil)
        #expect(manager.workspaces.count == 1)
        #expect(manager.tabs.contains { $0.id == tab.id })

        let restored = WorkspaceManager(store: store)
        #expect(restored.workspaces.count == 1)
    }

    @Test("Deleting an inactive space keeps active space and selection intact, preserves essentials")
    func deleteInactiveSpace() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let manager = WorkspaceManager(store: store)
        let space1 = manager.createWorkspace(name: "Space 1")
        let tab1 = try #require(manager.createTab(in: space1.id, tier: .normal, url: "https://one.com"))

        let space2 = manager.createWorkspace(name: "Space 2")
        let tab2 = try #require(manager.createTab(in: space2.id, tier: .pinned, url: "https://two.com"))

        let essential = try #require(manager.createTab(tier: .essential, url: "https://essential.com"))

        // Active space is space1
        manager.selectWorkspace(space1.id)
        manager.selectTab(tab1.id)

        // Delete inactive space2
        let result = try #require(manager.deleteWorkspace(space2.id))
        #expect(result.deletedTabs == [tab2.id])
        #expect(result.newActiveSpaceID == nil) // Did not change active space

        #expect(manager.workspaces.map(\.id) == [space1.id])
        #expect(manager.activeSpaceID == space1.id)
        #expect(manager.activeTabID == tab1.id)
        #expect(manager.essentialOrder == [essential.id])
        #expect(manager.descriptor(tab2.id) == nil)

        let restored = WorkspaceManager(store: store)
        #expect(restored.workspaces.map(\.id) == [space1.id])
        #expect(restored.activeSpaceID == space1.id)
        #expect(restored.activeTabID == tab1.id)
        #expect(restored.essentialOrder == [essential.id])
    }

    @Test("Deleting the active space selects neighbor and updates selection (first, middle, last)")
    func deleteActiveSpaceSelectsNeighbor() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let manager = WorkspaceManager(store: store)
        let space1 = manager.createWorkspace(name: "Space 1")
        _ = try #require(manager.createTab(in: space1.id, tier: .normal))

        let space2 = manager.createWorkspace(name: "Space 2")
        let tab2 = try #require(manager.createTab(in: space2.id, tier: .normal))

        let space3 = manager.createWorkspace(name: "Space 3")
        _ = try #require(manager.createTab(in: space3.id, tier: .normal))

        // 1. Delete first space (space1) while active -> should select next neighbor (space2)
        manager.selectWorkspace(space1.id)
        let result0 = try #require(manager.deleteWorkspace(space1.id))
        #expect(result0.newActiveSpaceID == space2.id)
        #expect(manager.activeSpaceID == space2.id)
        #expect(manager.activeTabID == tab2.id)

        // Add a 4th space to test middle deletion
        let space4 = manager.createWorkspace(name: "Space 4")
        let tab4 = try #require(manager.createTab(in: space4.id, tier: .normal))

        // Workspaces are now [space2, space3, space4].
        // 2. Delete middle space (space3) while active -> should select next neighbor (space4 at index 1)
        manager.selectWorkspace(space3.id)
        let result1 = try #require(manager.deleteWorkspace(space3.id))
        #expect(result1.newActiveSpaceID == space4.id)
        #expect(manager.activeSpaceID == space4.id)
        #expect(manager.activeTabID == tab4.id)

        // 3. Delete end space (space4) while active -> should select previous neighbor (space2)
        let result2 = try #require(manager.deleteWorkspace(space4.id))
        #expect(result2.newActiveSpaceID == space2.id)
        #expect(manager.activeSpaceID == space2.id)

        let restored = WorkspaceManager(store: store)
        #expect(restored.workspaces.map(\.id) == [space2.id])
        #expect(restored.activeSpaceID == space2.id)
    }

    @Test("Persistence failures remain visible on WorkspaceManager")
    func persistenceFailureIsVisible() throws {
        let unwritableDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: unwritableDir, withIntermediateDirectories: true)
        let storeURL = unwritableDir.appendingPathComponent("spaces.json")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unwritableDir.path)
            try? FileManager.default.removeItem(at: unwritableDir)
        }

        let store = GraphStore(url: storeURL)
        let manager = WorkspaceManager(store: store)
        _ = manager.createWorkspace(name: "Space 1")
        _ = manager.createWorkspace(name: "Space 2")

        // Make directory read-only so next save fails
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: unwritableDir.path)

        // Mutation in memory still succeeds
        let renamed = manager.renameWorkspace(manager.workspaces[0].id, name: "Renamed In Memory")
        #expect(renamed)
        #expect(manager.workspaces[0].name == "Renamed In Memory")
        // But persistence failure is recorded
        #expect(manager.persistenceFailure != nil)
    }

    @Test("BrowserModel coordinates space deletion runtime objects and clears presentation before destroying handles")
    func browserModelCoordinatesDeletion() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let model = BrowserModel(store: store)
        let space1 = model.workspaceManager.createWorkspace(name: "Space 1")
        let tab1 = try #require(model.workspaceManager.createTab(in: space1.id, tier: .normal, url: "https://one.com"))
        let space2 = model.workspaceManager.createWorkspace(name: "Space 2")
        let tab2 = try #require(model.workspaceManager.createTab(in: space2.id, tier: .normal, url: "https://two.com"))

        #expect(model.workspaces.count == 2)

        // Delete active space2: should select space1
        model.selectWorkspace(space2)
        #expect(model.activeWorkspace?.id == space2.id)

        model.deleteWorkspace(space2)

        #expect(model.workspaces.count == 1)
        #expect(model.workspaces[0].id == space1.id)
        #expect(model.workspaceManager.descriptor(tab2.id) == nil)
        #expect(model.workspaceManager.descriptor(tab1.id) != nil)

        // Verify webView.currentTabID is safely detached / cleared when no engine is attached
        #expect(model.webView.currentTabID == 0)

        // Refuse delete of only remaining space
        model.deleteWorkspace(space1)
        #expect(model.workspaces.count == 1)
    }

    @Test("BrowserModel selectNextTab and selectPreviousTab navigate visible tabs and respect collapsed pinned tier")
    func tabNavigationKeys() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let model = BrowserModel(store: store)
        let space = model.workspaceManager.createWorkspace(name: "Space")
        let essential = try #require(model.workspaceManager.createTab(tier: .essential, url: "https://essential.com"))
        let pinned = try #require(model.workspaceManager.createTab(in: space.id, tier: .pinned, url: "https://pinned.com"))
        let normal1 = try #require(model.workspaceManager.createTab(in: space.id, tier: .normal, url: "https://normal1.com"))
        let normal2 = try #require(model.workspaceManager.createTab(in: space.id, tier: .normal, url: "https://normal2.com"))

        model.selectWorkspace(space)
        model.workspaceManager.selectTab(essential.id)

        // When pinned tier is expanded (includePinned: true)
        // Order: essential -> pinned -> normal1 -> normal2
        #expect(model.selectedTabID == essential.id)

        model.selectNextTab(includePinned: true)
        #expect(model.selectedTabID == pinned.id)

        model.selectNextTab(includePinned: true)
        #expect(model.selectedTabID == normal1.id)

        model.selectNextTab(includePinned: true)
        #expect(model.selectedTabID == normal2.id)

        // Clamps at end
        model.selectNextTab(includePinned: true)
        #expect(model.selectedTabID == normal2.id)

        // Now test collapsed pinned tier (includePinned: false)
        // Order: essential -> normal1 -> normal2 (pinned is skipped!)
        model.workspaceManager.selectTab(essential.id)
        #expect(model.selectedTabID == essential.id)

        model.selectNextTab(includePinned: false)
        #expect(model.selectedTabID == normal1.id) // Skips pinned!

        model.selectNextTab(includePinned: false)
        #expect(model.selectedTabID == normal2.id)

        model.selectPreviousTab(includePinned: false)
        #expect(model.selectedTabID == normal1.id)

        model.selectPreviousTab(includePinned: false)
        #expect(model.selectedTabID == essential.id)

        // Clamps at beginning
        model.selectPreviousTab(includePinned: false)
        #expect(model.selectedTabID == essential.id)
    }

    @Test("GradientSpec hex validation and normalization")
    func hexNormalization() {
        #expect(GradientSpec.isValidHex("112233"))
        #expect(GradientSpec.isValidHex("#AABBCC"))
        #expect(GradientSpec.isValidHex("  #112233  "))
        #expect(GradientSpec.normalizedHex("112233") == "#112233")
        #expect(GradientSpec.normalizedHex("aabbcc") == "#AABBCC")
        #expect(!GradientSpec.isValidHex("12345"))
        #expect(!GradientSpec.isValidHex("1234567"))
        #expect(!GradientSpec.isValidHex("ZZZZZZ"))
    }
}
