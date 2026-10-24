/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The 3-tier sidebar:
 * - Essentials grid (global across all spaces)
 * - Pinned tabs (per-space)
 * - Normal tabs (per-space)
 * - Separator with "Close all unpinned"
 * - Space switcher dock at the bottom
 */

import LadybirdEngine
import SwiftUI

struct TabSidebar: View {
    @Bindable var model: BrowserModel
    @State private var showingNewSpaceSheet = false
    @State private var newSpaceName = ""

    var body: some View {
        VStack(spacing: 0) {
            List(selection: selection) {
                // Tier 1: Global Essentials
                if !model.essentialTabs.isEmpty {
                    Section {
                        EssentialsGrid(model: model, selection: selection)
                    } header: {
                        Text("Essentials")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Tier 2: Pinned tabs in active space
                if !model.activePinnedTabs.isEmpty {
                    Section {
                        ForEach(model.activePinnedTabs) { tab in
                            TabRow(tab: tab)
                                .tag(tab.id)
                                .contextMenu {
                                    Button("Unpin Tab") { model.setTier(for: tab, tier: .normal) }
                                    Button("Make Essential") { model.setTier(for: tab, tier: .essential) }
                                    Divider()
                                    Button("Close Tab") { model.closeTab(tab) }
                                }
                        }
                    } header: {
                        Text("Pinned")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Tier 3: Normal tabs in active space
                Section {
                    ForEach(model.activeNormalTabs) { tab in
                        TabRow(tab: tab)
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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !model.activeNormalTabs.isEmpty {
                            Button("Close All") {
                                model.closeAllUnpinnedInActiveWorkspace()
                            }
                            .buttonStyle(.plain)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()

            // Space Switcher Dock
            SpaceSwitcherDock(model: model, showingNewSpaceSheet: $showingNewSpaceSheet)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.bar)
        }
        .sheet(isPresented: $showingNewSpaceSheet) {
            VStack(spacing: 16) {
                Text("New Space")
                    .font(.headline)
                TextField("Space name", text: $newSpaceName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                HStack {
                    Button("Cancel") {
                        showingNewSpaceSheet = false
                        newSpaceName = ""
                    }
                    Button("Create") {
                        let name = newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty {
                            model.createWorkspace(name: name)
                        }
                        showingNewSpaceSheet = false
                        newSpaceName = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
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
    let selection: Binding<UUID?>

    private let columns = [GridItem(.adaptive(minimum: 40, maximum: 56), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(model.essentialTabs) { tab in
                EssentialItem(tab: tab, isSelected: model.selectedTabID == tab.id) {
                    model.select(tab)
                }
                .contextMenu {
                    Button("Unpin from Essentials") { model.setTier(for: tab, tier: .pinned) }
                    Divider()
                    Button("Close Essential") { model.closeTab(tab) }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct EssentialItem: View {
    let tab: BrowserTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tab.isLoading ? "circle.dotted" : "globe")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                    )
                Text(tab.title)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(tab.currentURL.isEmpty ? "New Tab" : tab.currentURL)
    }
}

private struct SpaceSwitcherDock: View {
    @Bindable var model: BrowserModel
    @Binding var showingNewSpaceSheet: Bool

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.spaces) { space in
                        SpacePill(
                            space: space,
                            isActive: model.activeWorkspace.id == space.id
                        ) {
                            model.selectWorkspace(space)
                        }
                        .contextMenu {
                            if model.spaces.count > 1 {
                                Button("Delete Space", role: .destructive) {
                                    model.removeWorkspace(space)
                                }
                            }
                        }
                    }
                }
            }

            Button {
                showingNewSpaceSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("New Space")
        }
    }
}

private struct SpacePill: View {
    let space: Workspace
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: space.icon)
                    .font(.system(size: 11))
                Text(space.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TabRow: View {
    let tab: BrowserTab

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: tab.isLoading ? "circle.dotted" : (tab.isLoaded ? "globe" : "cloud"))
                .foregroundStyle(tab.isLoaded ? .secondary : .tertiary)
                .imageScale(.small)
                .accessibilityHidden(true)

            Text(tab.title)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(tab.isLoaded ? .primary : .secondary)

            Spacer(minLength: 0)
        }
        .help(tab.currentURL.isEmpty ? "New Tab" : tab.currentURL)
    }
}
