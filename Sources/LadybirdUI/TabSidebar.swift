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
    @FocusState private var isRenameFocused: Bool

    @State private var isEssentialsTargeted: Bool = false
    @State private var isPinnedTargeted: Bool = false
    @State private var isLineTargeted: Bool = false
    @State private var isNormalTargeted: Bool = false

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

                // 1. Essentials Tier (adaptive 48x48 rounded tiles, captionless)
                essentialsSection
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 12)

                // 2. Active Space Header Row
                if let activeWorkspace = model.activeWorkspace {
                    activeSpaceHeader(activeWorkspace)
                        .padding(.horizontal, 10)
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

                // 6. Normal Tabs Tier
                normalTabsSection
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 12)

                // Fill remaining empty space for generous right-click hit target
                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity, minHeight: 400, alignment: .topLeading)
            .contentShape(Rectangle())
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

    private var essentialsSection: some View {
        VStack(spacing: 0) {
            if model.essentialTabs.isEmpty {
                // Real-sized drop target without resting filler text; highlights on drag
                ZStack {
                    if isEssentialsTargeted {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        Text("Drop to make Essential")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { ids, _ in
                    retier(ids, to: .essential)
                } isTargeted: { targeted in
                    isEssentialsTargeted = targeted
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48, maximum: 48), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(model.essentialTabs) { tab in
                        EssentialTile(tab: tab, model: model)
                            .draggable(tab.id.raw.uuidString)
                    }
                }
                .dropDestination(for: String.self) { ids, _ in
                    retier(ids, to: .essential)
                } isTargeted: { targeted in
                    isEssentialsTargeted = targeted
                }
            }
        }
    }

    // MARK: - Active Space Header

    private func activeSpaceHeader(_ workspace: Workspace) -> some View {
        HStack(spacing: 6) {
            Button {
                if reduceMotion {
                    isPinnedExpanded.toggle()
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isPinnedExpanded.toggle()
                    }
                }
            } label: {
                Image(systemName: isPinnedExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPinnedExpanded ? "Collapse Pinned Tabs" : "Expand Pinned Tabs")
            .help(isPinnedExpanded ? "Collapse Pinned Tabs" : "Expand Pinned Tabs")

            if renameState.editingWorkspaceID == workspace.id {
                TextField("Space Name", text: $renameState.draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .focused($isRenameFocused)
                    .onAppear {
                        isRenameFocused = true
                    }
                    .onSubmit {
                        renameState.commit(model: model)
                        isRenameFocused = false
                    }
                    .onExitCommand {
                        renameState.cancel()
                        isRenameFocused = false
                    }
                    .onChange(of: isRenameFocused) { _, focused in
                        if !focused && renameState.isEditing {
                            renameState.commit(model: model)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            } else {
                Button {
                    renameState.begin(for: workspace)
                    isRenameFocused = true
                } label: {
                    Text(workspace.name)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Space name \(workspace.name). Click to rename.")
                .help("Click to rename space")
            }

            Spacer(minLength: 0)

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
        .frame(height: 34)
        .contentShape(Rectangle())
        .onHover { isHeaderHovered = $0 }
        .dropDestination(for: String.self) { ids, _ in
            retier(ids, to: .pinned)
        } isTargeted: { targeted in
            isPinnedTargeted = targeted
        }
        .contextMenu {
            SpaceContextMenu(workspace: workspace, model: model, actionState: actionState)
        }
    }

    // MARK: - Pinned Section

    private var pinnedSection: some View {
        VStack(spacing: 2) {
            if model.pinnedTabs.isEmpty {
                if isPinnedTargeted {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        Text("Drop to Pin Tab")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
            } else {
                ForEach(model.pinnedTabs) { tab in
                    TabRowView(tab: tab, model: model)
                        .draggable(tab.id.raw.uuidString)
                        .dropDestination(for: String.self) { ids, _ in retier(ids, to: .pinned) }
                        .contextMenu { tabMenu(tab) }
                }
            }
        }
        .dropDestination(for: String.self) { ids, _ in
            retier(ids, to: .pinned)
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
        .dropDestination(for: String.self) { ids, _ in
            retier(ids, to: .pinned)
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
        VStack(spacing: 3) {
            ForEach(model.normalTabs) { tab in
                TabRowView(tab: tab, model: model)
                    .draggable(tab.id.raw.uuidString)
                    .dropDestination(for: String.self) { ids, _ in retier(ids, to: .normal) }
                    .contextMenu { tabMenu(tab) }
            }
            if model.normalTabs.isEmpty {
                ZStack {
                    if isNormalTargeted {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        Text("Drop tab here")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { ids, _ in
                    retier(ids, to: .normal)
                } isTargeted: { targeted in
                    isNormalTargeted = targeted
                }
            }
        }
        .dropDestination(for: String.self) { ids, _ in
            retier(ids, to: .normal)
        } isTargeted: { targeted in
            isNormalTargeted = targeted
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func tabMenu(_ tab: BrowserTab) -> some View {
        if model.workspaceManager.descriptor(tab.id)?.tier != .pinned {
            Button("Pin Tab") { model.retier(tab, to: .pinned) }
        }
        if model.workspaceManager.descriptor(tab.id)?.tier != .essential {
            Button("Make Essential") { model.retier(tab, to: .essential) }
        }
        if model.workspaceManager.descriptor(tab.id)?.tier != .normal {
            Button("Move to Tabs") { model.retier(tab, to: .normal) }
        }
        Divider()
        Button("Close Tab", role: .destructive) { model.closeTab(tab) }
    }

    private func retier(_ values: [String], to tier: TabTier) -> Bool {
        guard let value = values.first, let uuid = UUID(uuidString: value),
              let tab = model.tabs.first(where: { $0.id == TabID(raw: uuid) }) else { return false }
        model.retier(tab, to: tier)
        return true
    }
}

// MARK: - EssentialTile (48x48 Captionless)

private struct EssentialTile: View {
    let tab: BrowserTab
    let model: BrowserModel
    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var isSelected: Bool {
        model.selectedTabID == tab.id
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

                Image(systemName: tab.isLoading ? "circle.dotted" : "globe")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .accessibilityHidden(true)
            }
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
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
    let tab: BrowserTab
    let model: BrowserModel
    @State private var isHovered = false
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isSelected: Bool {
        model.selectedTabID == tab.id
    }

    var body: some View {
        HStack(spacing: 4) {
            // Main Selection Area
            Button {
                model.select(tab)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: tab.isLoading ? "circle.dotted" : (tab.isLoaded ? "globe" : "moon.zzz"))
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .frame(width: 16)
                        .accessibilityHidden(true)

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
        .frame(height: 34)
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
