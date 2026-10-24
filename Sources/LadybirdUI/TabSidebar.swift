/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The Arc-style spatial vertical sidebar:
 * - Top: Navigation buttons (Back, Forward, Reload) + Unified Address/Search Capsule
 * - Essentials grid: 2x4 square app icon tiles
 * - Space header: Space icon + Title (e.g. "General", "Work")
 * - Space Pinned tabs
 * - Hairline separator with "Clear" unpinned tabs button
 * - "+ New Tab" button
 * - Space Normal tabs
 * - Bottom dock: Library icon + space pagination pills/dots + '+' New Space button
 */

import LadybirdEngine
import SwiftUI

struct TabSidebar: View {
    @Bindable var model: BrowserModel
    var addressFocused: FocusState<Bool>.Binding

    @State private var showingNewSpaceSheet = false
    @State private var newSpaceName = ""
    @State private var newSpaceIcon = "sparkles"
    @State private var selectedThemeIndex = 0

    struct ThemePreset: Identifiable {
        let id: String
        let name: String
        let spec: GradientSpec
    }

    private let themePresets: [ThemePreset] = [
        ThemePreset(id: "blue-purple", name: "Ocean", spec: GradientSpec(startColorHex: "#3B82F6", endColorHex: "#8B5CF6")),
        ThemePreset(id: "rose-orange", name: "Sunset", spec: GradientSpec(startColorHex: "#F43F5E", endColorHex: "#FB923C")),
        ThemePreset(id: "emerald-teal", name: "Forest", spec: GradientSpec(startColorHex: "#10B981", endColorHex: "#06B6D4")),
        ThemePreset(id: "burgundy-wine", name: "Wine", spec: GradientSpec(startColorHex: "#881337", endColorHex: "#4C0519")),
        ThemePreset(id: "amber-yellow", name: "Amber", spec: GradientSpec(startColorHex: "#D97706", endColorHex: "#F59E0B")),
    ]

    private let availableIcons = [
        "globe", "sparkles", "briefcase", "book", "hammer",
        "gamecontroller", "music.note", "house", "terminal", "cup.and.saucer"
    ]

    var body: some View {
        VStack(spacing: 8) {
            // 1. Navigation & Unified Address Field
            VStack(spacing: 8) {
                // Top control bar
                HStack(spacing: 10) {
                    Button(action: model.goBack) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canGoBack)
                    .foregroundStyle(model.canGoBack ? Color.primary : Color.secondary.opacity(0.3))
                    .help("Back (⌘[)")

                    Button(action: model.goForward) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canGoForward)
                    .foregroundStyle(model.canGoForward ? Color.primary : Color.secondary.opacity(0.3))
                    .help("Forward (⌘])")

                    Button(action: model.reload) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.currentURL.isEmpty ? Color.secondary.opacity(0.3) : Color.primary.opacity(0.8))
                    .help("Reload (⌘R)")

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)

                // Address field
                HStack(spacing: 6) {
                    Image(systemName: model.isLoading ? "arrow.trianglehead.2.clockwise.rotate.90" : "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)

                    TextField("Search or enter URL", text: $model.addressText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .focused(addressFocused)
                        .onSubmit(model.submitAddress)

                    if !model.currentURL.isEmpty {
                        Button {
                            if let url = URL(string: model.currentURL) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                            }
                        } label: {
                            Image(systemName: "link")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy URL")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(addressFocused.wrappedValue ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture { addressFocused.wrappedValue = true }
                .padding(.horizontal, 10)

                // 2. Essentials Grid (Arc 2x4 square tiles)
                if !model.essentialTabs.isEmpty {
                    EssentialsGrid(model: model)
                        .padding(.horizontal, 10)
                }
            }

            // 3. Tab Hierarchy List
            List(selection: selection) {
                // Space Header
                Section {
                    // Pinned Tabs
                    ForEach(model.activePinnedTabs) { tab in
                        ArcTabRow(tab: tab, isSelected: model.selectedTabID == tab.id, isPinned: true) {
                            model.closeTab(tab)
                        }
                        .tag(tab.id)
                        .contextMenu {
                            Button("Move to Tabs") { model.setTier(for: tab, tier: .normal) }
                            Button("Make Essential") { model.setTier(for: tab, tier: .essential) }
                            Divider()
                            Button("Close Tab") { model.closeTab(tab) }
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: model.activeWorkspace.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(model.activeWorkspace.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }

                // Divider and "+ New Tab"
                Section {
                    Button {
                        withAnimation(.snappy(duration: 0.15)) {
                            _ = model.openTab()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("New Tab")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .help("New Tab (⌘T)")

                    // Normal Tabs
                    ForEach(model.activeNormalTabs) { tab in
                        ArcTabRow(tab: tab, isSelected: model.selectedTabID == tab.id, isPinned: false) {
                            model.closeTab(tab)
                        }
                        .tag(tab.id)
                        .contextMenu {
                            Button("Pin Tab") { model.setTier(for: tab, tier: .pinned) }
                            Button("Make Essential") { model.setTier(for: tab, tier: .essential) }
                            Divider()
                            Button("Close Tab") { model.closeTab(tab) }
                        }
                    }
                } header: {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 1)
                        .padding(.vertical, 2)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            // 4. Arc Bottom Dock
            ArcSpaceSwitcherDock(model: model, showingNewSpaceSheet: $showingNewSpaceSheet)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
        }
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                model.activeWorkspace.theme.linearGradient
            }
            .animation(.easeInOut(duration: 0.35), value: model.activeWorkspace.theme)
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingNewSpaceSheet) {
            VStack(alignment: .leading, spacing: 18) {
                Text("New Space")
                    .font(.system(size: 16, weight: .semibold))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Space Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Work, Personal, Studies…", text: $newSpaceName)
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
                                    .frame(width: 26, height: 26)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(newSpaceIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(newSpaceIcon == icon ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Theme")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ForEach(Array(themePresets.enumerated()), id: \.element.id) { index, preset in
                            Button {
                                selectedThemeIndex = index
                            } label: {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: preset.spec.startColorHex), Color(hex: preset.spec.endColorHex)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedThemeIndex == index ? Color.primary : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(preset.name)
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
                            let theme = themePresets[selectedThemeIndex].spec
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                model.createWorkspace(name: name, icon: newSpaceIcon, theme: theme)
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

// MARK: - Essentials Grid

private struct EssentialsGrid: View {
    @Bindable var model: BrowserModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
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
    }
}

private struct EssentialTile: View {
    let tab: BrowserTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.22) : (isHovering ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06)))
                    .frame(height: 40)

                Image(systemName: tab.isLoading ? "circle.dotted" : "globe")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.7) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(tab.title.isEmpty ? (tab.currentURL.isEmpty ? "New Tab" : tab.currentURL) : tab.title)
    }
}

// MARK: - Arc Tab Row

private struct ArcTabRow: View {
    let tab: BrowserTab
    let isSelected: Bool
    let isPinned: Bool
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tab.isLoading ? "circle.dotted" : (tab.isLoaded ? "globe" : "cloud"))
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(width: 14, height: 14)

            Text(tab.title)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? Color.primary : (tab.isLoaded ? Color.primary.opacity(0.9) : Color.secondary))

            Spacer(minLength: 0)

            if isHovering || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(3)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Close Tab")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.12) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
        )
        .onHover { isHovering = $0 }
        .help(tab.currentURL.isEmpty ? "New Tab" : tab.currentURL)
    }
}

// MARK: - Arc Bottom Dock

private struct ArcSpaceSwitcherDock: View {
    @Bindable var model: BrowserModel
    @Binding var showingNewSpaceSheet: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Archive / Library Box
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    model.closeAllUnpinnedInActiveWorkspace()
                }
            } label: {
                Image(systemName: "archivebox")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Archive Unpinned Tabs")

            Spacer()

            // Space icons (active) and pagination dots (inactive)
            HStack(spacing: 8) {
                ForEach(model.spaces) { space in
                    let isActive = model.activeWorkspace.id == space.id
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            model.selectWorkspace(space)
                        }
                    } label: {
                        if isActive {
                            Image(systemName: space.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.primary)
                                .frame(width: 20, height: 20)
                        } else {
                            Circle()
                                .fill(Color.primary.opacity(0.35))
                                .frame(width: 5, height: 5)
                                .frame(width: 14, height: 20)
                                .contentShape(Rectangle())
                        }
                    }
                    .buttonStyle(.plain)
                    .help(space.name)
                    .contextMenu {
                        if space.id != model.activeWorkspace.id {
                            Button("Unload Space Tabs") {
                                withAnimation(.snappy(duration: 0.2)) {
                                    model.unloadWorkspace(space)
                                }
                            }
                        }
                        if model.spaces.count > 1 {
                            Divider()
                            Button("Delete Space", role: .destructive) {
                                withAnimation(.snappy(duration: 0.2)) {
                                    model.removeWorkspace(space)
                                }
                            }
                        }
                    }
                }
            }

            Spacer()

            // '+' New Space Button
            Button {
                showingNewSpaceSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("New Space (⌘⌥N)")
        }
    }
}
