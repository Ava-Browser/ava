/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * SpacesManager: App-level manager coordinating Workspaces and TabDescriptors.
 * Mutations write through immediately to the SpacesStore.
 */

import Foundation
import Observation

@MainActor
@Observable
public final class SpacesManager {
    public private(set) var spaces: [Workspace] = []
    public private(set) var tabs: [TabDescriptor] = []
    public private(set) var folders: [TabFolder] = []
    public private(set) var activeWorkspaceID: UUID

    @ObservationIgnored private let store: SpacesStore

    public init(store: SpacesStore = JSONSpacesStore()) {
        self.store = store
        if let state = store.load(), !state.spaces.isEmpty {
            self.spaces = state.spaces
            self.tabs = state.tabs
            self.folders = state.folders
            if state.spaces.contains(where: { $0.id == state.activeWorkspaceID }) {
                self.activeWorkspaceID = state.activeWorkspaceID
            } else {
                self.activeWorkspaceID = state.spaces[0].id
            }
        } else {
            let defaultSpace = Workspace(name: "Default", icon: "square.stack.3d.up")
            self.spaces = [defaultSpace]
            self.tabs = []
            self.folders = []
            self.activeWorkspaceID = defaultSpace.id
            persist()
        }
    }

    public var activeWorkspace: Workspace {
        spaces.first(where: { $0.id == activeWorkspaceID }) ?? spaces[0]
    }

    public var essentials: [TabDescriptor] {
        tabs.filter { $0.tier == .essential }
    }

    public var activePinnedTabs: [TabDescriptor] {
        let activeID = activeWorkspaceID
        return tabs.filter { $0.tier == .pinned && $0.workspaceID == activeID }
    }

    public var activeNormalTabs: [TabDescriptor] {
        let activeID = activeWorkspaceID
        return tabs.filter { $0.tier == .normal && $0.workspaceID == activeID }
    }

    public func selectWorkspace(id: UUID) {
        guard spaces.contains(where: { $0.id == id }) else { return }
        activeWorkspaceID = id
        persist()
    }

    @discardableResult
    public func createWorkspace(name: String, icon: String = "square.stack.3d.up", theme: GradientSpec = GradientSpec()) -> Workspace {
        let space = Workspace(name: name, icon: icon, theme: theme)
        spaces.append(space)
        persist()
        return space
    }

    public func removeWorkspace(id: UUID) {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces.remove(at: index)
        // Remove tabs belonging to this space
        tabs.removeAll(where: { $0.workspaceID == id })
        folders.removeAll(where: { $0.workspaceID == id })
        if activeWorkspaceID == id {
            let newIndex = min(index, spaces.count - 1)
            activeWorkspaceID = spaces[newIndex].id
        }
        persist()
    }

    public func updateActiveTab(for workspaceID: UUID, tabID: UUID?) {
        guard let index = spaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        spaces[index].activeTabID = tabID
        persist()
    }

    public func addTab(
        id: UUID = UUID(),
        workspaceID: UUID?,
        tier: TabTier = .normal,
        url: String,
        title: String = "",
        faviconRef: String? = nil
    ) -> TabDescriptor {
        let descriptor = TabDescriptor(
            id: id,
            workspaceID: tier == .essential ? nil : (workspaceID ?? activeWorkspaceID),
            tier: tier,
            url: url,
            title: title,
            faviconRef: faviconRef
        )
        tabs.append(descriptor)
        if let wsID = descriptor.workspaceID, let index = spaces.firstIndex(where: { $0.id == wsID }) {
            spaces[index].tabOrder.append(descriptor.id)
            spaces[index].activeTabID = descriptor.id
        }
        persist()
        return descriptor
    }

    public func removeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let descriptor = tabs[index]
        tabs.remove(at: index)
        if let wsID = descriptor.workspaceID, let wsIndex = spaces.firstIndex(where: { $0.id == wsID }) {
            spaces[wsIndex].tabOrder.removeAll(where: { $0 == id })
            if spaces[wsIndex].activeTabID == id {
                spaces[wsIndex].activeTabID = spaces[wsIndex].tabOrder.last
            }
        }
        persist()
    }

    public func setTier(for tabID: UUID, tier: TabTier) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let oldTier = tabs[index].tier
        guard oldTier != tier else { return }

        tabs[index].tier = tier
        if tier == .essential {
            // Invariant 1: Essentials have workspaceID = nil
            if let oldWsID = tabs[index].workspaceID, let wsIdx = spaces.firstIndex(where: { $0.id == oldWsID }) {
                spaces[wsIdx].tabOrder.removeAll(where: { $0 == tabID })
            }
            tabs[index].workspaceID = nil
        } else if tabs[index].workspaceID == nil {
            tabs[index].workspaceID = activeWorkspaceID
            if let wsIdx = spaces.firstIndex(where: { $0.id == activeWorkspaceID }) {
                if !spaces[wsIdx].tabOrder.contains(tabID) {
                    spaces[wsIdx].tabOrder.append(tabID)
                }
            }
        }
        persist()
    }

    public func updateTab(id: UUID, url: String? = nil, title: String? = nil, scrollY: Double? = nil) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if let url { tabs[index].url = url }
        if let title { tabs[index].title = title }
        if let scrollY { tabs[index].scrollY = scrollY }
        persist()
    }

    public func closeAllUnpinnedInActiveWorkspace() {
        let activeID = activeWorkspaceID
        tabs.removeAll(where: { $0.tier == .normal && $0.workspaceID == activeID })
        if let wsIndex = spaces.firstIndex(where: { $0.id == activeID }) {
            spaces[wsIndex].tabOrder.removeAll(where: { tabID in
                !tabs.contains(where: { $0.id == tabID })
            })
            if let activeTabID = spaces[wsIndex].activeTabID, !tabs.contains(where: { $0.id == activeTabID }) {
                spaces[wsIndex].activeTabID = spaces[wsIndex].tabOrder.last
            }
        }
        persist()
    }

    private func persist() {
        let state = SpacesStoreState(
            schemaVersion: 1,
            activeWorkspaceID: activeWorkspaceID,
            spaces: spaces,
            tabs: tabs,
            folders: folders
        )
        store.save(state)
    }
}
