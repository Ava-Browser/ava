/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The Arc-style spatial vertical sidebar:
 * - Top: Navigation buttons (Back, Forward, Reload) + Unified Address/Search Capsule
 * - Essentials grid: 4-column squircle app icon tiles (46x46pt, 8pt spacing)
 * - Space header: Space icon + Title (13pt bold)
 * - Space Pinned tabs
 * - Hairline 1px separator
 * - "+ New Tab" button
 * - Space Normal tabs with single crisp selection pill
 * - Bottom dock: Close unpinned button + pagination dots (on gradient, no separate material band) + '+' New Space
 */

import LadybirdEngine
import SwiftUI

struct TabSidebar: View {
    @Bindable var model: BrowserModel
    var addressFocused: FocusState<Bool>.Binding

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var fallbackAddressFocus: Bool
    @State private var showingNewSpaceSheet = false
    @State private var newSpaceName = ""
    @State private var newSpaceIcon = "sparkles"
    @State private var selectedThemeIndex = 0
    @State private var isNewTabHovering = false

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

    private var effectiveAddressFocus: FocusState<Bool>.Binding {
        addressFocused
    }

    private var quietHostText: String {
        if let host = URL(string: model.currentURL)?.host(), !host.isEmpty {
            return host
        }
        return model.currentURL.isEmpty ? "Search or enter URL" : model.currentURL
    }

    private var springAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.8)
    }

    var body: some View {
        VStack(spacing: 8) {
            // 1. Navigation & Unified Address Field
            VStack(spacing: 8) {
                // Top control bar
                HStack(spacing: 8) {
                    Button {
                        // Sidebar collapse toggle
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Toggle Sidebar")
                    .help("Toggle Sidebar (⌃⌘S)")

                    Spacer()

                    HStack(spacing: 8) {
                        Button(action: model.goBack) {
                            Image(systemName: "chevron.backward")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.canGoBack)
                        .foregroundStyle(model.canGoBack ? Color.primary : Color.secondary.opacity(0.3))
                        .accessibilityLabel("Back")
                        .help("Back (⌘[)")

                        Button(action: model.goForward) {
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.canGoForward)
                        .foregroundStyle(model.canGoForward ? Color.primary : Color.secondary.opacity(0.3))
                        .accessibilityLabel("Forward")
                        .help("Forward (⌘])")

                        Button(action: model.reload) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(model.currentURL.isEmpty ? Color.secondary.opacity(0.3) : Color.primary.opacity(0.8))
                        .accessibilityLabel("Reload")
                        .help("Reload (⌘R)")
                    }
                }
                .padding(.leading, 78) // Reserved space for macOS traffic lights (red, yellow, green)
                .padding(.trailing, 10)
                .padding(.top, 14)

                // Unified Address Capsule (~36pt height, calm host display when unfocused)
                addressCapsule
                    .padding(.horizontal, 10)

                // 2. Essentials Grid (4 columns, 46x46 squircles, 8pt spacing)
                if !model.essentialTabs.isEmpty {
                    EssentialsGrid(model: model)
                        .padding(.horizontal, 10)
                        .padding(.top, 2)
                }
            }

            // 3. Tab Hierarchy ScrollView (single crisp selection pills, no double borders)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Space Header
                    spaceHeader
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)

                    // Pinned Tabs
                    if !model.activePinnedTabs.isEmpty {
                        VStack(spacing: 2) {
                            ForEach(model.activePinnedTabs) { tab in
                                ArcTabRow(
                                    tab: tab,
                                    isSelected: model.selectedTabID == tab.id,
                                    isPinned: true,
                                    onSelect: { model.select(tab) },
                                    onClose: { model.closeTab(tab) }
                                )
                                .contextMenu {
                                    Button("Move to Tabs") { model.setTier(for: tab, tier: .normal) }
                                    Button("Make Essential") { model.setTier(for: tab, tier: .essential) }
                                    Divider()
                                    Button("Close Tab") { model.closeTab(tab) }
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 4)
                    }

                    // 1px Hairline Divider
                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)

                    // "+ New Tab" row
                    Button {
                        withAnimation(.snappy(duration: 0.15)) {
                            _ = model.openTab()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 14, height: 14)
                            Text("New Tab")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isNewTabHovering ? Color.primary.opacity(0.06) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New Tab")
                    .help("New Tab (⌘T)")
                    .onHover { isNewTabHovering = $0 }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)

                    // Normal Tabs
                    VStack(spacing: 2) {
                        ForEach(model.activeNormalTabs) { tab in
                            ArcTabRow(
                                tab: tab,
                                isSelected: model.selectedTabID == tab.id,
                                isPinned: false,
                                onSelect: { model.select(tab) },
                                onClose: { model.closeTab(tab) }
                            )
                            .contextMenu {
                                Button("Pin Tab") { model.setTier(for: tab, tier: .pinned) }
                                Button("Make Essential") { model.setTier(for: tab, tier: .essential) }
                                Divider()
                                Button("Close Tab") { model.closeTab(tab) }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 0)

            // 4. Arc Bottom Dock (directly on space gradient, no separate material band)
            ArcSpaceSwitcherDock(model: model, showingNewSpaceSheet: $showingNewSpaceSheet, springAnimation: springAnimation)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                model.activeWorkspace.theme.linearGradient
            }
            .animation(springAnimation, value: model.activeWorkspace.theme)
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingNewSpaceSheet) {
            newSpaceSheetView
        }
    }

    // MARK: - Subviews

    private var addressCapsule: some View {
        HStack(spacing: 6) {
            Image(systemName: model.isLoading ? "arrow.trianglehead.2.clockwise.rotate.90" : "lock.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if effectiveAddressFocus.wrappedValue {
                TextField("Search or enter URL", text: $model.addressText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused(effectiveAddressFocus)
                    .onSubmit(model.submitAddress)
            } else {
                Text(quietHostText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !model.currentURL.isEmpty {
                Button {
                    model.copyCurrentURL()
                } label: {
                    Image(systemName: "link")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy URL")
                .help("Copy URL")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(effectiveAddressFocus.wrappedValue ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            effectiveAddressFocus.wrappedValue = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(effectiveAddressFocus.wrappedValue ? "Address text field" : "Address: \(quietHostText)")
    }

    private var spaceHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: model.activeWorkspace.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 16, height: 16)
            Text(model.activeWorkspace.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Active Space: \(model.activeWorkspace.name)")
    }

    private var newSpaceSheetView: some View {
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
                        .accessibilityLabel("Select icon \(icon)")
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
                        .accessibilityLabel("Select theme \(preset.name)")
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
                        withAnimation(springAnimation) {
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

// MARK: - Essentials Grid

private struct EssentialsGrid: View {
    @Bindable var model: BrowserModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

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
                    .fill(isSelected ? Color.primary.opacity(0.24) : (isHovering ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06)))
                    .frame(height: 46)

                Image(systemName: tab.isLoading ? "circle.dotted" : "globe")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.7) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(tab.title.isEmpty ? "Essential tab" : tab.title)
        .help(tab.title.isEmpty ? (tab.currentURL.isEmpty ? "New Tab" : tab.currentURL) : tab.title)
    }
}

// MARK: - Arc Tab Row

private struct ArcTabRow: View {
    let tab: BrowserTab
    let isSelected: Bool
    let isPinned: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: tab.isLoading ? "circle.dotted" : (tab.isLoaded ? "globe" : "cloud"))
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)

                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
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
                    .accessibilityLabel("Close Tab \(tab.title)")
                    .help("Close Tab")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.12) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(tab.title.isEmpty ? "Tab" : tab.title)
        .help(tab.currentURL.isEmpty ? "New Tab" : tab.currentURL)
    }
}

// MARK: - Arc Bottom Dock

private struct ArcSpaceSwitcherDock: View {
    @Bindable var model: BrowserModel
    @Binding var showingNewSpaceSheet: Bool
    let springAnimation: Animation

    var body: some View {
        HStack(spacing: 0) {
            // Close Unpinned Tabs (formerly labeled Archive)
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
            .accessibilityLabel("Close Unpinned Tabs")
            .help("Close Unpinned Tabs")

            Spacer()

            // Space pagination dots & active icon (directly on gradient, no separate material band)
            HStack(spacing: 8) {
                ForEach(model.spaces) { space in
                    let isActive = model.activeWorkspace.id == space.id
                    Button {
                        withAnimation(springAnimation) {
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
                    .accessibilityLabel(isActive ? "Active Space \(space.name)" : "Switch to Space \(space.name)")
                    .help(space.name)
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
            .accessibilityLabel("New Space")
            .help("New Space (⌘⌥N)")
        }
    }
}
