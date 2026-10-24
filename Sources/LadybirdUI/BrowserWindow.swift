/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The Arc-style spatial browser window:
 * - Content card: Rounded floating web view (cornerRadius 10) surrounded by space-tinted background.
 * - Sidebar: Houses traffic lights, collapse toggle, navigation (back/forward/reload),
 *   address field, essentials squircle grid, space pinned/tabs, and the space switcher dock.
 * - Toolbar in the detail view is removed: the address bar and navigation sit cleanly in the sidebar.
 */

import LadybirdEngine
import SwiftUI

public struct BrowserWindow: View {
    @State private var model = BrowserModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var addressFocused: Bool
    private static let numberShortcuts: [KeyEquivalent] = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    public init() {}

    private static var launchURL: String {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--url"), args.index(after: i) < args.endIndex {
            return args[args.index(after: i)]
        }
        for arg in args where arg.hasPrefix("--url=") {
            return String(arg.dropFirst("--url=".count))
        }
        return "https://example.com"
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            TabSidebar(model: model, addressFocused: $addressFocused)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            // Main Web View Canvas: Arc floating card
            ZStack {
                spaceThemeBackground

                content
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .padding(.leading, 2)
                    .padding(.trailing, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 400)
        .sheet(item: Binding(
            get: { model.selectedTab?.dialog },
            set: { _ in }
        )) { dialog in
            if let tab = model.selectedTab {
                DialogSheet(dialog: dialog, tab: tab, model: model)
            }
        }
        .navigationTitle(windowTitle)
        .modifier(TitleHiddenInToolbar())
        .task {
            model.start(homeURL: Self.launchURL)
            model.webView.onSwipeSpace = { deltaX in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if deltaX < 0 {
                        model.selectNextWorkspace()
                    } else {
                        model.selectPreviousWorkspace()
                    }
                }
            }
        }
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Spacer().frame(width: 0)
            }
        }
        .background {
            Group {
                Button("") { model.reload() }.keyboardShortcut("r", modifiers: .command)
                Button("") { addressFocused = true }.keyboardShortcut("l", modifiers: .command)
                Button("") { model.goBack() }.keyboardShortcut("[", modifiers: .command)
                Button("") { model.goForward() }.keyboardShortcut("]", modifiers: .command)
                Button("") { model.openTab() }.keyboardShortcut("t", modifiers: .command)
                Button("") { model.closeSelectedTab() }.keyboardShortcut("w", modifiers: .command)

                // ⌘⌥← / ⌘⌥→ to cycle through adjacent Spaces
                Button("") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        model.selectPreviousWorkspace()
                    }
                }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])

                Button("") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        model.selectNextWorkspace()
                    }
                }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])

                // ⌘⌥[1...9] to jump directly to Space N
                ForEach(0..<9, id: \.self) { index in
                    Button("") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            model.selectWorkspace(at: index)
                        }
                    }.keyboardShortcut(Self.numberShortcuts[index], modifiers: [.command, .option])
                }
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private struct TitleHiddenInToolbar: ViewModifier {
        func body(content: Content) -> some View {
            if #available(macOS 15.0, *) {
                content.toolbar(removing: .title)
            } else {
                content
            }
        }
    }

    private var windowTitle: String {
        guard let host = URL(string: model.currentURL)?.host(), !host.isEmpty else { return "Ladybird" }
        return host
    }

    @ViewBuilder
    private var content: some View {
        if let failure = model.failure {
            ContentUnavailableView {
                Label("Cannot Start the Engine", systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            WebContentView(webView: model.webView)
        }
    }

    private var spaceThemeBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            model.activeWorkspace.theme.linearGradient
        }
        .animation(.easeInOut(duration: 0.35), value: model.activeWorkspace.theme)
        .ignoresSafeArea()
    }
}

extension Color {
    init(hex: String, defaultColor: Color = .accentColor) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }
        if cleanHex.count == 3 {
            cleanHex = cleanHex.map { "\($0)\($0)" }.joined()
        }
        guard (cleanHex.count == 6 || cleanHex.count == 8), let rgb = UInt64(cleanHex.prefix(6), radix: 16) else {
            self = defaultColor
            return
        }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}

extension GradientSpec {
    var linearGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: startColorHex).opacity(0.22),
                Color(hex: endColorHex).opacity(0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
