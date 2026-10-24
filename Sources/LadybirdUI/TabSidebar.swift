/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The 3-tier spatial sidebar (Zen & Arc inspired):
 * - Essentials grid (global top tier across all spaces, rounded app tiles)
 * - Pinned tabs (space-scoped, persistent bookmarks)
 * - Separator with subtle "Close all unpinned" button
 * - Normal tabs (active tabs in space)
 * - Space switcher dock (capsule dock with spring pills, icon/emoji support, new space sheet)
 */

import LadybirdEngine
import SwiftUI

struct TabSidebar: View {
    @Bindable var model: BrowserModel
    @State private var showingNewSpaceSheet = false
    @State private var newSpaceName = ""
    @State private var newSpaceIcon = "sparkles"

    private let availableIcons = [
        "square.stack.3d.up", "sparkles", "briefcase", "book", "hammer",
        "gamecontroller", "music.note", "house", "globe", "terminal"
    ]

    var body: some View {
        VStack(spacing: 0) {
            List(selection: selection) {
                // Tier 1: Global Essentials Grid
                if !model.essentialTabs.isEmpty {
                    Section {
                        EssentialsGrid(model: model)
                            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 8, trailing: 4))
                            .listRowSeparator(.hidden)
                    } header: {
                        Text("Essentials")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                    }
                }

                // Tier 2: Space Pinned Tabs
                if !model.activePinnedTabs.isEmpty {
                    Section {
                        ForEach(model.activePinnedTabs) { tab in
                            TabRow(tab: tab, isPinned: true)
                                .tag(tab.id)
                                .contextMenu {
                                    Button("Move to Tabs") { model.setTier(for: tab, tier: .normal) }
                                    Button("Make Essential") { model.setTier(for: tab, tier: .essential) }
                                    Divider()
                                    Button("Close Tab") { model.closeTab(tab) }
                                }
                        }
                    } header: {
                        Text("Pinned")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                    }
                }

                // Tier 3: Space Normal Tabs
                Section {
                    ForEach(model.activeNormalTabs) { tab in
                        TabRow(tab: tab, isPinned: false)
                            .tag(tab.id)
                            .contextMenu {
                                Button("Pin Tab") { model.setTier(for: tab, tier: .pinned) }
                                Button("Make Essential") { model.setTier(for: tab, tier: .essential) }
                                Divider()
                                Button("Close Tab") { model.closeTab(tab) }
                            }
                    }
                } header: {
                    HStack {
                        Text("Tabs")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                        Spacer()
                        if !model.activeNormalTabs.isEmpty {
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    model.closeAllUnpinnedInActiveWorkspace()
                                }
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Close all unpinned tabs")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
                .opacity(0.6)

            // Space Switcher Dock
            SpaceSwitcherDock(model: model, showingNewSpaceSheet: $showingNewSpaceSheet)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingNewSpaceSheet) {
            VStack(alignment: .leading, spacing: 18) {
                Text("New Space")
                    .font(.system(size: 16, weight: .semibold))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Work, Personal, Research…", text: $newSpaceName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Icon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(availableIcons, id: \.self) { icon in
                            Button {
                                newSpaceIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 13))
                                    .frame(width: 24, height: 24)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(newSpaceIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(newSpaceIcon == icon ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        showingNewSpaceSheet = false
                        newSpaceName = ""
                    }
                    Button("Create Space") {
                        let name = newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                model.createWorkspace(name: name, icon: newSpaceIcon)
                            }
                        }
                        showingNewSpaceSheet = false
                        newSpaceName = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(22)
            .frame(width: 380)
        }
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: { model.selectedTabID },
            set: { newValue in
                guard let newValue, let tab = model.tabs.first(where: { $0.id == newValue }) else { return }
                model.select(tab)
            }
        )
    }
}

private struct EssentialsGrid: View {
    @Bindable var model: BrowserModel
    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 60), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(model.essentialTabs) { tab in
                EssentialTile(tab: tab, isSelected: model.selectedTabID == tab.id) {
                    model.select(tab)
                }
                .contextMenu {
                    Button("Move to Space Pinned") { model.setTier(for: tab, tier: .pinned) }
                    Button("Move to Normal Tabs") { model.setTier(for: tab, tier: .normal) }
                    Divider()
                    Button("Close Essential") { model.closeTab(tab) }
                }
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct EssentialTile: View {
    let tab: BrowserTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.accentColor : (isHovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04)))
                        .frame(width: 44, height: 44)

                    Image(systemName: tab.isLoading ? "circle.dotted" : "globe")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(tab.currentURL.isEmpty ? "New Tab" : tab.currentURL)
    }
}

private struct SpaceSwitcherDock: View {
    @Bindable var model: BrowserModel
    @Binding var showingNewSpaceSheet: Bool

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(model.spaces) { space in
                        let isActive = model.activeWorkspace.id == space.id
                        SpaceDockPill(space: space, isActive: isActive) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                model.selectWorkspace(space)
                            }
                        }
                        .contextMenu {
                            if model.spaces.count > 1 {
                                Button("Delete Space", role: .destructive) {
                                    withAnimation(.snappy(duration: 0.2)) {
                                        model.removeWorkspace(space)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            Button {
                showingNewSpaceSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .help("New Space (⌘⌥N)")
        }
    }
}

private struct SpaceDockPill: View {
    let space: Workspace
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: space.icon)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                Text(space.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.18) : (isHovering ? Color.primary.opacity(0.06) : Color.clear))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isActive ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        .onHover { isHovering = $0 }
    }
}

private struct TabRow: View {
    let tab: BrowserTab
    let isPinned: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tab.isLoading ? "circle.dotted" : (isPinned ? "pin.fill" : (tab.isLoaded ? "globe" : "cloud")))
                .font(.system(size: isPinned ? 10 : 12))
                .foregroundStyle(tab.isLoaded ? .secondary : .tertiary)
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)

            Text(tab.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(tab.isLoaded ? .primary : .secondary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .help(tab.currentURL.isEmpty ? "New Tab" : tab.currentURL)
    }
}
