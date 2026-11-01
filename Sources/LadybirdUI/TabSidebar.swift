/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The active space's sidebar: adaptive captionless Essentials, active space header with collapse/options,
 * collapsible pinned tabs, divider with Clear, New Tab, and normal tabs with pill selection.
 */

import LadybirdEngine
import SwiftUI

struct TabSidebar: View {
    @Bindable var model: BrowserModel
    let actionState: SpaceActionState

    @State private var isPinnedExpanded: Bool = true
    @State private var isHeaderHovered: Bool = false
    @State private var isEllipsisHovered: Bool = false
    @FocusState private var isEllipsisFocused: Bool

    @State private var renameState = SpaceRenameState()

    @State private var isPinnedTargeted: Bool = false
    @State private var isLineTargeted: Bool = false
    @State private var essentialsWidth: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Persistence failure warning banner
                if let failure = model.workspaceManager.persistenceFailure {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                            .accessibilityHidden(true)
                        Text(failure)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(8)
                    .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Persistence failure: \(failure)")
                }

                // 1. Essentials Tier (adaptive 48x48 rounded tiles, captionless). Nothing is drawn when there are
                // none: an empty tier that reserves height is just a gap at the top of the sidebar. Reordering and
                // removing still work whenever at least one essential exists; making one from scratch is the row's
                // "Make Essential" action.
                if hasEssentials {
                    essentialsSection
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                        .padding(.bottom, 12)
                }

                // 2. Active Space Header Row
                if let activeWorkspace = model.activeWorkspace {
                    activeSpaceHeader(activeWorkspace)
                        .padding(.horizontal, 10)
                        .padding(.top, hasEssentials ? 0 : 10)
                        .padding(.bottom, (!model.pinnedTabs.isEmpty || isPinnedTargeted) ? 4 : 2)
                }

                // 3. Pinned Tabs (collapsible under the active space row)
                if isPinnedExpanded && (!model.pinnedTabs.isEmpty || isPinnedTargeted) {
                    pinnedSection
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)
                }

                // 4. Divider with trailing "Clear" button
                dividerWithClear
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)

                // 5. "+ New Tab" row
                newTabRow
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)

                // 6. Normal Tabs Tier. An empty tier draws nothing but keeps a small strip so the section below the
                // divider still reads as a place to drop, rather than collapsing into the divider.
                normalTabsSection
                    .frame(maxWidth: .infinity, minHeight: model.normalTabs.isEmpty ? 40 : 0, alignment: .topLeading)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 12)

                // Fill remaining empty space for generous right-click hit target
                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity, minHeight: 400, alignment: .topLeading)
            .contentShape(Rectangle())
            // Catch-all for the empty space, which is most of the sidebar: a drop anywhere that is not a section of its
            // own means unpinned, so dragging a tab out of Essentials or Pinned never needs a precise aim. SwiftUI
            // resolves to the innermost target under the pointer, so the sections above keep their own meaning.
            .dropDestination(for: String.self) { ids, _ in
                moved(ids, to: .normal, at: nil)
            }
            .contextMenu {
                if let activeWorkspace = model.activeWorkspace {
                    SpaceContextMenu(workspace: activeWorkspace, model: model, actionState: actionState)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) {
            guard !renameState.isEditing else { return .ignored }
            model.selectNextTab(includePinned: isPinnedExpanded)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !renameState.isEditing else { return .ignored }
            model.selectPreviousTab(includePinned: isPinnedExpanded)
            return .handled
        }
        .onChange(of: actionState.inlineRenameWorkspaceID) { _, requestedID in
            guard let requestedID,
                  let workspace = model.workspaces.first(where: { $0.id == requestedID }) else { return }
            actionState.inlineRenameWorkspaceID = nil
            // The field lives in the active Space's header, so a request from the dock's menu for another Space has to
            // switch there first; otherwise editing starts with no visible editor.
            if model.activeWorkspace?.id != workspace.id {
                model.selectWorkspace(workspace)
            }
            renameState.begin(for: workspace)
        }
        .onChange(of: model.activeWorkspace?.id) { _, newID in
            renameState.handleSpaceSwitch(newActiveID: newID)
        }
        .onChange(of: model.selectedTabID) { _, _ in
            if renameState.isEditing {
                renameState.commit(model: model)
            }
        }
        .onDisappear {
            renameState.cancel()
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Essentials Section

    private var hasEssentials: Bool { !model.essentialTabs.isEmpty }

    private var essentialsSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: EssentialTile.size, maximum: EssentialTile.size), spacing: EssentialTile.spacing)], alignment: .leading, spacing: EssentialTile.spacing) {
            ForEach(model.essentialTabs) { tab in
                EssentialTile(tab: tab, model: model)
                    .draggable(tab.id.raw.uuidString)
            }
        }
        .background {
            // The grid's own width is what decides how many tiles fit per row, which is what turns a drop point into
            // a slot. Measured in the background so the grid keeps its own layout.
            GeometryReader { proxy in
                Color.clear.onAppear { essentialsWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in essentialsWidth = width }
            }
        }
        .dropDestination(for: String.self) { ids, location in
            moved(ids, to: .essential, at: gridSlot(at: location, count: model.essentialTabs.count))
        }
    }

    /// The slot a drop point means in a uniform row-major grid.
    private func gridSlot(at location: CGPoint, count: Int) -> Int {
        let stride = EssentialTile.size + EssentialTile.spacing
        let columns = max(1, Int((essentialsWidth + EssentialTile.spacing) / stride))
        let row = max(0, Int(location.y / stride))
        let column = max(0, min(columns - 1, Int(location.x / stride)))
        return min(row * columns + column, count)
    }

    // MARK: - Active Space Header

    private func activeSpaceHeader(_ workspace: Workspace) -> some View {
        HStack(spacing: 10) {
            // Arc parity: the resting slot shows the space icon; hover reveals the disclosure chevron in the same
            // 12 pt slot, so nothing shifts between states.
            Button {
                if reduceMotion {
                    isPinnedExpanded.toggle()
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isPinnedExpanded.toggle()
                    }
                }
            } label: {
                Group {
                    if isHeaderHovered {
                        Image(systemName: isPinnedExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    } else {
                        WorkspaceIconView(icon: workspace.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPinnedExpanded ? "Collapse Pinned Tabs" : "Expand Pinned Tabs")
            .help(isPinnedExpanded ? "Collapse Pinned Tabs" : "Expand Pinned Tabs")

            if renameState.editingWorkspaceID == workspace.id {
                // Same visual language as the address field: a capsule with the accent ring while editing.
                RenameTextField(
                    text: $renameState.draft,
                    onSubmit: { renameState.commit(model: model) },
                    onCancel: { renameState.cancel() }
                )
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(Color.secondary.opacity(0.1)))
                .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 2))
            } else {
                // Arc parity: the title is a label, not an edit affordance. Renaming starts from Rename Space….
                Text(workspace.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityAddTraits(.isHeader)
            }

            Spacer(minLength: 0)

            if renameState.editingWorkspaceID == workspace.id {
                Button("Done") { renameState.commit(model: model) }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Save space name")
                .help("Save space name")
            } else {
                Menu {
                    SpaceContextMenu(workspace: workspace, model: model, actionState: actionState)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(isEllipsisHovered || isEllipsisFocused ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .focused($isEllipsisFocused)
                .opacity(isHeaderHovered || isEllipsisHovered || isEllipsisFocused ? 1.0 : 0.0)
                .onHover { isEllipsisHovered = $0 }
                .accessibilityLabel("Space options for \(workspace.name)")
                .help("Space Options")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background {
            // The pill marks the active row, so it stays while renaming rather than vanishing with the pointer.
            if isHeaderHovered || renameState.isEditing {
                let activeColor = controlActiveState == .inactive ? Color.primary.opacity(0.04) : (reduceTransparency ? Color.primary.opacity(0.12) : Color.primary.opacity(0.07))
                RoundedRectangle(cornerRadius: 12)
                    .fill(activeColor)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { isHeaderHovered = $0 }
        // The space row doubles as "the top of Pinned", so a drop here pins a tab as the first one.
        .dropDestination(for: String.self) { ids, _ in
            moved(ids, to: .pinned, at: 0)
        } isTargeted: { targeted in
            isPinnedTargeted = targeted
        }
        .contextMenu {
            SpaceContextMenu(workspace: workspace, model: model, actionState: actionState)
        }
    }

    // MARK: - Pinned Section

    private var pinnedSection: some View {
        VStack(spacing: TabRowView.spacing) {
            ForEach(model.pinnedTabs) { tab in
                TabRowView(tab: tab, model: model)
                    .draggable(tab.id.raw.uuidString)
                    .contextMenu { tabMenu(tab, tier: .pinned) }
            }
        }
        .dropDestination(for: String.self) { ids, location in
            moved(ids, to: .pinned, at: rowSlot(at: location, count: model.pinnedTabs.count))
        } isTargeted: { targeted in
            isPinnedTargeted = targeted
        }
    }

    // MARK: - Divider with Clear

    private var dividerWithClear: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(isLineTargeted || isPinnedTargeted ? Color.accentColor : Color.primary.opacity(colorSchemeContrast == .increased ? 0.3 : 0.12))
                .frame(height: isLineTargeted || isPinnedTargeted ? 2 : 1)

            if !model.normalTabs.isEmpty {
                Button("Clear") {
                    model.closeAllUnpinned()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear unpinned tabs")
                .help("Close all normal tabs in this space")
            }
        }
        .frame(height: 20)
        .contentShape(Rectangle())
        // The line sits on the boundary, so it is the unpinned drop target: it is always present, which is what makes
        // "drag a tab back out of pinned" work even when there are no normal tabs to aim at.
        .dropDestination(for: String.self) { ids, _ in
            moved(ids, to: .normal, at: nil)
        } isTargeted: { targeted in
            isLineTargeted = targeted
        }
    }

    // MARK: - New Tab Row

    private var newTabRow: some View {
        Button {
            model.openTab()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text("New Tab")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New Tab")
        .help("New Tab (⌘T)")
    }

    // MARK: - Normal Tabs Section

    private var normalTabsSection: some View {
        VStack(spacing: TabRowView.spacing) {
            ForEach(model.normalTabs) { tab in
                TabRowView(tab: tab, model: model)
                    .draggable(tab.id.raw.uuidString)
                    .contextMenu { tabMenu(tab, tier: .normal) }
            }
        }
        .dropDestination(for: String.self) { ids, location in
            moved(ids, to: .normal, at: rowSlot(at: location, count: model.normalTabs.count))
        }
    }

    // MARK: - Helpers

    /// The section a row is rendered in already knows its tier, so this takes it instead of looking the descriptor up
    /// three times per row — which was three linear scans of the whole graph, on every row, on every sidebar update.
    @ViewBuilder
    private func tabMenu(_ tab: BrowserTab, tier: TabTier) -> some View {
        if tier != .pinned {
            Button("Pin Tab") { model.retier(tab, to: .pinned) }
        }
        if tier != .essential {
            Button("Make Essential") { model.retier(tab, to: .essential) }
        }
        if tier != .normal {
            Button("Move to Tabs") { model.retier(tab, to: .normal) }
        }
        Divider()
        Button("Close Tab", role: .destructive) { model.closeTab(tab) }
    }

    /// The slot a drop point means in a uniform column of rows. The nearest gap wins, so the top half of a row lands
    /// above it and the bottom half below it.
    private func rowSlot(at location: CGPoint, count: Int) -> Int {
        let stride = TabRowView.height + TabRowView.spacing
        return min(max(Int((location.y / stride).rounded()), 0), count)
    }

    private func moved(_ values: [String], to tier: TabTier, at index: Int?) -> Bool {
        guard let value = values.first, let uuid = UUID(uuidString: value),
              let tab = model.tabs.first(where: { $0.id == TabID(raw: uuid) }) else { return false }
        model.move(tab, to: tier, at: index)
        return true
    }
}

// MARK: - EssentialTile (48x48 Captionless)

private struct EssentialTile: View {
    static let size: CGFloat = 48
    static let spacing: CGFloat = 8

    let tab: BrowserTab
    let model: BrowserModel
    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var isSelected: Bool {
        model.selectedTabID == tab.id
    }

    private var isAvaStartPage: Bool {
        tab.currentURL.isEmpty || tab.currentURL == AppSettings.blankPageURL
    }

    var body: some View {
        Button {
            model.select(tab)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.primary.opacity(0.15) : (isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04)))

                if isSelected || colorSchemeContrast == .increased {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? Color.primary.opacity(0.3) : Color.primary.opacity(0.15), lineWidth: 1)
                }

                if tab.isLoading {
                    Image(systemName: "circle.dotted")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .accessibilityHidden(true)
                } else if let favicon = tab.favicon {
                    Image(nsImage: favicon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .accessibilityHidden(true)
                } else if isAvaStartPage {
                    LiftMark()
                        .fill(isSelected ? Color.primary : Color.secondary)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: Self.size, height: Self.size)
        }
        .buttonStyle(.plain)
        // `.plain` only takes the glyph's own bounds, so a click beside the icon did nothing.
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { isHovered = $0 }
        .help(tab.title.isEmpty ? tab.currentURL : "\(tab.title)\(tab.currentURL.isEmpty ? "" : " — " + tab.currentURL)")
        .accessibilityLabel(tab.title.isEmpty ? "Essential tab" : tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .contextMenu {
            Button("Move to Pinned") { model.retier(tab, to: .pinned) }
            Button("Move to Tabs") { model.retier(tab, to: .normal) }
            Divider()
            Button("Close Tab", role: .destructive) { model.closeTab(tab) }
        }
    }
}

// MARK: - TabRowView (Sibling Close Button & Independent Selection)

private struct TabRowView: View {
    static let height: CGFloat = 34
    static let spacing: CGFloat = 3

    let tab: BrowserTab
    let model: BrowserModel
    @State private var isHovered = false
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isSelected: Bool {
        model.selectedTabID == tab.id
    }

    private var isAvaStartPage: Bool {
        tab.currentURL.isEmpty || tab.currentURL == AppSettings.blankPageURL
    }

    var body: some View {
        HStack(spacing: 4) {
            // Main Selection Area. The row's own `contentShape` below is the click target; the button's label carries
            // a matching one so a click on the padding beside the title still selects instead of doing nothing.
            Button {
                model.select(tab)
            } label: {
                HStack(spacing: 8) {
                    if tab.isLoading {
                        Image(systemName: "circle.dotted")
                            .font(.system(size: 13))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                    } else if let favicon = tab.favicon {
                        Image(nsImage: favicon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .accessibilityHidden(true)
                    } else if isAvaStartPage {
                        LiftMark()
                            .fill(isSelected ? Color.primary : Color.secondary)
                            .frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: tab.isLoaded ? "globe" : "moon.zzz")
                            .font(.system(size: 13))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                    }

                    Text(tab.title.isEmpty ? (tab.currentURL.isEmpty ? "New Tab" : tab.currentURL) : tab.title)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Fills the row up to the close button, so the whole width selects — not just the text and favicon.
            .frame(maxWidth: .infinity)
            .accessibilityLabel("\(tab.title.isEmpty ? "New Tab" : tab.title)")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            // Sibling Close Button on Hover / Selection
            if isHovered || isSelected {
                Button {
                    model.closeTab(tab)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close tab \(tab.title)")
                .help("Close Tab")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .background {
            if isSelected {
                let activeColor = controlActiveState == .inactive ? Color.primary.opacity(0.06) : (reduceTransparency ? Color.primary.opacity(0.15) : Color.primary.opacity(0.10))
                RoundedRectangle(cornerRadius: 12)
                    .fill(activeColor)
                    .shadow(color: Color.black.opacity(controlActiveState == .inactive ? 0.0 : 0.05), radius: 2, x: 0, y: 1)

                if colorSchemeContrast == .increased {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
                }
            } else if isHovered {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.04))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { isHovered = $0 }
        .help(tab.currentURL.isEmpty ? "New Tab" : tab.currentURL)
    }
}
