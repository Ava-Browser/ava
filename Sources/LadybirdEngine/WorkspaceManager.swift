/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Mutations of the durable workspace/tab graph. Every successful mutation writes through before returning.
 */

import Foundation
import Observation

@MainActor
@Observable
public final class WorkspaceManager {
    public private(set) var workspaces: [Workspace]
    public private(set) var tabs: [TabDescriptor]
    public private(set) var essentialOrder: [TabID]
    public private(set) var activeSpaceID: UUID?
    /// Persistence failures are visible to the chrome. The in-memory mutation still stands so an unwritable disk does
    /// not make controls appear broken; a later successful mutation writes the complete current graph.
    public private(set) var persistenceFailure: String?

    @ObservationIgnored private let store: GraphStore

    public init(store: GraphStore = .applicationDefault()) {
        self.store = store
        let saved = store.load() ?? PersistedGraph()
        workspaces = saved.workspaces
        tabs = saved.tabs
        essentialOrder = saved.essentialOrder
        activeSpaceID = saved.activeSpaceID
        normalize()
    }

    public var activeWorkspace: Workspace? {
        guard let activeSpaceID else { return nil }
        return workspaces.first { $0.id == activeSpaceID }
    }

    public var activeTabID: TabID? { activeWorkspace?.activeTabID }

    public func descriptor(_ id: TabID) -> TabDescriptor? {
        tabs.first { $0.id == id }
    }

    public func tabs(in tier: TabTier, workspaceID: UUID? = nil) -> [TabDescriptor] {
        let ids: [TabID]
        if tier == .essential {
            ids = essentialOrder
        } else {
            guard let workspace = workspaces.first(where: { $0.id == (workspaceID ?? activeSpaceID) }) else { return [] }
            ids = workspace.tabOrder.filter { descriptor($0)?.tier == tier }
        }
        return ids.compactMap(descriptor)
    }

    @discardableResult
    public func createWorkspace(name: String? = nil, icon: String = "circle.grid.2x2.fill") -> Workspace {
        let number = workspaces.count + 1
        let workspace = Workspace(
            name: name ?? "Space \(number)",
            icon: icon,
            theme: GradientSpec.palette[(number - 1) % GradientSpec.palette.count]
        )
        workspaces.append(workspace)
        activeSpaceID = workspace.id
        persist()
        return workspace
    }

    public func selectWorkspace(_ id: UUID) {
        guard workspaces.contains(where: { $0.id == id }), activeSpaceID != id else { return }
        activeSpaceID = id
        persist()
    }

    public func renameWorkspace(_ id: UUID, name: String) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].name = name
        persist()
    }

    @discardableResult
    public func createTab(
        in workspaceID: UUID? = nil,
        tier: TabTier = .normal,
        url: String = "about:blank",
        select: Bool = true
    ) -> TabDescriptor? {
        let destination = tier == .essential ? nil : (workspaceID ?? activeSpaceID)
        guard tier == .essential || workspaces.contains(where: { $0.id == destination }) else { return nil }

        let tab = TabDescriptor(workspaceID: destination, tier: tier, url: url)
        tabs.append(tab)
        if tier == .essential {
            essentialOrder.append(tab.id)
        } else if let destination, let index = workspaces.firstIndex(where: { $0.id == destination }) {
            workspaces[index].tabOrder.append(tab.id)
        }
        if select, let selectedSpace = destination ?? activeSpaceID,
           let index = workspaces.firstIndex(where: { $0.id == selectedSpace }) {
            workspaces[index].activeTabID = tab.id
        }
        persist()
        return tab
    }

    public func selectTab(_ id: TabID, in workspaceID: UUID? = nil) {
        guard let tab = descriptor(id) else { return }
        let spaceID = tab.workspaceID ?? workspaceID ?? activeSpaceID
        guard let spaceID, let index = workspaces.firstIndex(where: { $0.id == spaceID }) else { return }
        // Essentials may be selected from every space; other tabs only from their owner.
        guard tab.tier == .essential || tab.workspaceID == spaceID else { return }
        workspaces[index].activeTabID = id
        persist()
    }

    public func updateTab(_ id: TabID, url: String, title: String? = nil) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].url = url
        if let title { tabs[index].title = title }
        persist()
    }

    public func closeTab(_ id: TabID) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[tabIndex]
        tabs.remove(at: tabIndex)
        essentialOrder.removeAll { $0 == id }

        if let workspaceID = tab.workspaceID, let index = workspaces.firstIndex(where: { $0.id == workspaceID }) {
            let oldPosition = workspaces[index].tabOrder.firstIndex(of: id)
            workspaces[index].tabOrder.removeAll { $0 == id }
            if workspaces[index].activeTabID == id {
                workspaces[index].activeTabID = neighbour(in: workspaces[index].tabOrder, around: oldPosition)
                    ?? essentialOrder.first
            }
        } else {
            // An essential can be selected in every space, so clear or replace it everywhere.
            for index in workspaces.indices where workspaces[index].activeTabID == id {
                workspaces[index].activeTabID = essentialOrder.first ?? workspaces[index].tabOrder.first
            }
        }
        persist()
    }

    /// Moves a tab between sidebar tiers. Dropping on Essentials makes it global; moving it back places it in the
    /// active workspace because an essential deliberately has no owner to remember.
    public func retier(_ id: TabID, to tier: TabTier, in workspaceID: UUID? = nil) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == id }), tabs[tabIndex].tier != tier else { return }
        let oldWorkspaceID = tabs[tabIndex].workspaceID
        let destination = workspaceID ?? oldWorkspaceID ?? activeSpaceID
        guard tier == .essential || workspaces.contains(where: { $0.id == destination }) else { return }

        essentialOrder.removeAll { $0 == id }
        if let oldWorkspaceID, let index = workspaces.firstIndex(where: { $0.id == oldWorkspaceID }) {
            workspaces[index].tabOrder.removeAll { $0 == id }
        }

        if tier == .essential {
            tabs[tabIndex].workspaceID = nil
            essentialOrder.append(id)
        } else if let destination, let index = workspaces.firstIndex(where: { $0.id == destination }) {
            tabs[tabIndex].workspaceID = destination
            workspaces[index].tabOrder.append(id)
        }
        tabs[tabIndex].tier = tier
        persist()
    }

    /// Close only normal tabs in the active space. Pinned and essentials are intentionally untouched.
    public func closeAllUnpinned() -> [TabID] {
        guard let workspace = activeWorkspace else { return [] }
        let ids = workspace.tabOrder.filter { descriptor($0)?.tier == .normal }
        for id in ids { closeTab(id) }
        return ids
    }

    public func snapshot() -> PersistedGraph {
        PersistedGraph(
            activeSpaceID: activeSpaceID,
            essentialOrder: essentialOrder,
            workspaces: workspaces,
            tabs: tabs
        )
    }

    private func neighbour(in order: [TabID], around oldPosition: Int?) -> TabID? {
        guard !order.isEmpty else { return nil }
        guard let oldPosition else { return order.first }
        return order[min(oldPosition, order.count - 1)]
    }

    /// Repairs references that can be stale after a killed write or a file edited by an older build. Normalization is
    /// intentionally conservative: it discards dangling references, never descriptors that might still be recoverable.
    private func normalize() {
        let ids = Set(tabs.map(\.id))
        essentialOrder = essentialOrder.filter { ids.contains($0) && descriptor($0)?.tier == .essential }
        for index in workspaces.indices {
            let workspaceID = workspaces[index].id
            workspaces[index].tabOrder = workspaces[index].tabOrder.filter {
                ids.contains($0) && descriptor($0)?.workspaceID == workspaceID && descriptor($0)?.tier != .essential
            }
            if let active = workspaces[index].activeTabID,
               descriptor(active)?.workspaceID != workspaceID && descriptor(active)?.tier != .essential {
                workspaces[index].activeTabID = workspaces[index].tabOrder.first ?? essentialOrder.first
            } else if workspaces[index].activeTabID == nil {
                workspaces[index].activeTabID = workspaces[index].tabOrder.first ?? essentialOrder.first
            }
        }
        if !workspaces.contains(where: { $0.id == activeSpaceID }) {
            activeSpaceID = workspaces.first?.id
        }
    }

    private func persist() {
        do {
            try store.save(snapshot())
            persistenceFailure = nil
        } catch {
            persistenceFailure = "Could not save spaces: \(error.localizedDescription)"
        }
    }
}
