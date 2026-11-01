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
    @ObservationIgnored private var writeDisabledDueToBackupFailure = false

    public init(store: GraphStore = .applicationDefault()) {
        self.store = store
        let saved: PersistedGraph
        switch store.load() {
        case let .loaded(graph):
            saved = graph
        case .empty:
            saved = PersistedGraph()
        case let .unreadablePreserved(backupURL):
            saved = PersistedGraph()
            persistenceFailure = "Prior workspace graph was unreadable and was backed up to \(backupURL.lastPathComponent)."
        case let .unreadableBackupFailed(error):
            saved = PersistedGraph()
            writeDisabledDueToBackupFailure = true
            persistenceFailure = "Prior workspace graph was unreadable, and backing it up failed (\(error.localizedDescription)). Automatic saving is disabled to protect the file from being overwritten."
        }
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
            ids = workspace.tabOrder
        }
        // One index per call. Resolving each id inside `tabs` was quadratic, and the sidebar asks for all three tiers
        // on every update, so the cost showed up as input lag while a page was loading.
        let byID = Dictionary(tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { id in
            guard let tab = byID[id], tier == .essential || tab.tier == tier else { return nil }
            return tab
        }
    }

    @discardableResult
    public func createWorkspace(name: String? = nil, icon: String = "circle.fill") -> Workspace {
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

    @discardableResult
    public func renameWorkspace(_ id: UUID, name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return false }
        workspaces[index].name = trimmed
        persist()
        return true
    }

    @discardableResult
    public func updateWorkspaceIcon(_ id: UUID, icon: String) -> Bool {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Workspace.isValidIcon(trimmed) else { return false }
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return false }
        workspaces[index].icon = trimmed
        persist()
        return true
    }

    @discardableResult
    public func updateWorkspaceTheme(_ id: UUID, theme: GradientSpec) -> Bool {
        guard let start = GradientSpec.normalizedHex(theme.startHex),
              let end = GradientSpec.normalizedHex(theme.endHex) else {
            return false
        }
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return false }
        workspaces[index].theme = GradientSpec(startHex: start, endHex: end)
        persist()
        return true
    }

    @discardableResult
    public func reorderWorkspaces(_ newOrder: [UUID]) -> Bool {
        let existingIDs = workspaces.map(\.id)
        guard Set(existingIDs).count == existingIDs.count else { return false }
        guard Set(newOrder).count == newOrder.count else { return false }
        guard newOrder.count == workspaces.count else { return false }
        guard Set(newOrder) == Set(existingIDs) else { return false }
        let map = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.id, $0) })
        workspaces = newOrder.compactMap { map[$0] }
        persist()
        return true
    }

    public func moveWorkspace(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !workspaces.isEmpty,
              destination >= 0, destination <= workspaces.count,
              source.allSatisfy({ $0 >= 0 && $0 < workspaces.count }) else {
            return
        }
        var elements = workspaces
        let moving = source.map { elements[$0] }
        for index in source.reversed() {
            elements.remove(at: index)
        }
        let insertIndex = destination - source.filter { $0 < destination }.count
        guard insertIndex >= 0 && insertIndex <= elements.count else { return }
        elements.insert(contentsOf: moving, at: insertIndex)
        workspaces = elements
        persist()
    }

    @discardableResult
    public func deleteWorkspace(_ id: UUID) -> (deletedTabs: [TabID], newActiveSpaceID: UUID?)? {
        guard workspaces.count > 1 else { return nil }
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return nil }

        let targetWorkspace = workspaces[index]
        let targetTabIDs = targetWorkspace.tabOrder
        let targetSet = Set(targetTabIDs)

        // Remove only tabs belonging to this workspace. Essentials (workspaceID == nil) and other spaces survive.
        tabs.removeAll { targetSet.contains($0.id) || $0.workspaceID == id }
        workspaces.remove(at: index)

        var newActive: UUID?
        if activeSpaceID == id {
            let newIndex = min(index, workspaces.count - 1)
            newActive = workspaces[newIndex].id
            activeSpaceID = newActive
        }

        persist()
        return (deletedTabs: targetTabIDs, newActiveSpaceID: newActive)
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

    public func updateTab(_ id: TabID, url: String, title: String? = nil, faviconRef: String? = nil, clearFaviconRef: Bool = false) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let newTitle = title ?? tabs[index].title
        let newFaviconRef = clearFaviconRef ? nil : (faviconRef ?? tabs[index].faviconRef)
        // A navigation reports url, title, favicon and loading in separate callbacks, several of them repeats. Each
        // repeat used to rewrite the whole graph inside the pump (R6), so a no-op now costs nothing.
        guard tabs[index].url != url || tabs[index].title != newTitle || tabs[index].faviconRef != newFaviconRef else {
            return
        }
        tabs[index].url = url
        tabs[index].title = newTitle
        tabs[index].faviconRef = newFaviconRef
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
        moveTab(id, to: tier, in: workspaceID)
    }

    /// Puts a tab in `tier` at `index` within that tier's order; a nil index appends.
    ///
    /// Reordering and re-tiering are one mutation: an essential is ordered in `essentialOrder`, a pinned or normal tab
    /// inside its space's `tabOrder`, and a drop only says which section and where in it.
    public func moveTab(_ id: TabID, to tier: TabTier, at index: Int? = nil, in workspaceID: UUID? = nil) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[tabIndex]
        let destination = workspaceID ?? tab.workspaceID ?? activeSpaceID
        guard tier == .essential || workspaces.contains(where: { $0.id == destination }) else { return }

        // `index` counts positions in the section as it is drawn, which still contains the dragged tab. Removing it
        // first shifts every later slot down by one, so a same-tier move has to compensate or the row lands short.
        let current = (tier == .essential ? essentialOrder : (workspaces.first { $0.id == destination }?.tabOrder ?? []))
            .filter { descriptor($0)?.tier == tier }
        var slot = min(max(index ?? current.count, 0), current.count)
        if let from = current.firstIndex(of: id), from < slot { slot -= 1 }

        essentialOrder.removeAll { $0 == id }
        if let oldWorkspaceID = tab.workspaceID, let oldIndex = workspaces.firstIndex(where: { $0.id == oldWorkspaceID }) {
            workspaces[oldIndex].tabOrder.removeAll { $0 == id }
        }
        tabs[tabIndex].tier = tier

        if tier == .essential {
            tabs[tabIndex].workspaceID = nil
            essentialOrder.insert(id, at: slot)
        } else if let destination, let index = workspaces.firstIndex(where: { $0.id == destination }) {
            tabs[tabIndex].workspaceID = destination
            let insertion = insertionPoint(for: slot, in: workspaces[index].tabOrder, tier: tier)
            workspaces[index].tabOrder.insert(id, at: insertion)
            // Leaving Essentials: every space could select it, so the ones that are not the destination are now
            // pointing at a tab their own list does not contain. `BrowserModel.selectWorkspace` would then present a
            // tab the sidebar does not list. Same repair `closeTab` does for an essential, down to preferring another
            // essential because that is the kind of tab the space was showing.
            for other in workspaces.indices where workspaces[other].id != destination && workspaces[other].activeTabID == id {
                workspaces[other].activeTabID = essentialOrder.first ?? workspaces[other].tabOrder.first
            }
        }
        persist()
    }

    /// Where the `slot`-th tab of `tier` starts inside a space's mixed `tabOrder`.
    private func insertionPoint(for slot: Int, in order: [TabID], tier: TabTier) -> Int {
        let lane = order.filter { descriptor($0)?.tier == tier }
        if slot < lane.count, let anchor = order.firstIndex(of: lane[slot]) {
            return anchor
        }
        if let last = lane.last, let anchor = order.firstIndex(of: last) {
            return anchor + 1
        }
        // An empty tier keeps the layout order: pinned above, normal below.
        guard tier == .pinned else { return order.count }
        return order.firstIndex { descriptor($0)?.tier == .normal } ?? order.count
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
        guard !writeDisabledDueToBackupFailure else {
            return
        }
        do {
            try store.save(snapshot())
            // Assigning an already-nil value still counts as a change to every observer of this model, which is a
            // full sidebar invalidation per write.
            if persistenceFailure != nil { persistenceFailure = nil }
        } catch {
            persistenceFailure = "Could not save spaces: \(error.localizedDescription)"
        }
    }
}
