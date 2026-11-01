/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The window: one real toolbar holding the page controls, the page below it. One job, so no sidebar.
 */

import LadybirdEngine
import SwiftUI

public struct BrowserWindow: View {
    @State private var model = BrowserModel()
    @State private var spaceActionState = SpaceActionState()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var addressState = AddressBarState()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    /// The page to open at launch.
    ///
    /// `--url <value>` only, and note the prefix: a *bare* positional argument makes AppKit treat the launch as a
    /// document-open request, and SwiftUI then never creates a window at all (measured — the process runs, the window
    /// does not exist). Requiring the flag keeps that path untouched.
    ///
    /// This exists because there is otherwise no way to point the app at a page without driving the UI, which a
    /// benchmark or a regression script cannot do reliably.
    private static var launchURLArgument: String? {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--url"), args.index(after: i) < args.endIndex {
            return args[args.index(after: i)]
        }
        // Tolerate `--url=<value>` too, which is what most callers reach for first.
        for arg in args where arg.hasPrefix("--url=") {
            return String(arg.dropFirst("--url=".count))
        }
        return nil
    }

    private static var launchURL: String { launchURLArgument ?? AppSettings.shared.newTabURL }

    public var body: some View {
        // One workspace: the sidebar is the only tab list, and the page sits beside it.
        //
        // This was an HSplitView, on the grounds that the window had no collapse behaviour and a split view would only
        // add chrome nobody asked for. The sidebar now collapses, and that reverses the trade: the header toggle, the
        // ⌃⌘S shortcut, the animated width change, the material behind the list and the collapsed state that stops
        // taking keystrokes are all behaviours an HSplitView does not have and would each have to be rebuilt by hand —
        // probably subtly wrong, since the collapsed case is the one nobody remembers to test.
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                TabSidebar(model: model, actionState: spaceActionState)
                SpaceDock(model: model, actionState: spaceActionState)
            }
            .background(
                SidebarSwipeRepresentable(
                    onSwipeLeft: { model.selectNextWorkspace() },
                    onSwipeRight: { model.selectPreviousWorkspace() }
                )
            )
            .background {
                if let activeWorkspace = model.activeWorkspace {
                    if reduceTransparency {
                        Color.clear
                    } else {
                        LinearGradient(
                            colors: [
                                Color(hex: activeWorkspace.theme.startHex).opacity(0.08),
                                Color(hex: activeWorkspace.theme.endHex).opacity(0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            }
            .modifier(SpaceActionModifier(model: model, actionState: spaceActionState))
            // The width is not persisted here on purpose: SwiftUI's NavigationSplitView already writes the column's
            // frame to `NSSplitView Subview Frames` in the app's preferences and restores it on launch. Tracking it
            // ourselves duplicated that and could disagree with it. `ideal` only seeds a first launch.
            .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 320)
        } detail: {
            content
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 320)
            // Orders the window front once per launch, whichever content is showing. It lives at window level because
            // the start page mounts no web view, so a per-view trigger would miss the default launch entirely.
            .background(LaunchActivationView())
            // A dialog lives on the tab that asked, so the sheet is attached to whichever tab is selected. The model
            // answers it before switching away or closing, so it can never be presented for an invisible tab.
            .sheet(item: Binding(
                get: { model.selectedTab?.dialog },
                set: { _ in }
            )) { dialog in
                if let tab = model.selectedTab {
                    DialogSheet(dialog: dialog, tab: tab, model: model)
                }
            }
            // NB: the title still reaches the Dock and the Window menu; it is only kept out of the toolbar, where it
            // repeated what the address field already shows. `toolbar(removing:)` is macOS 15+, and the package
            // targets 14.4, so older systems keep the title — cosmetic only, nothing depends on its absence.
            .navigationTitle(windowTitle)
            .modifier(TitleHiddenInToolbar())
            // `task` runs once per view identity, which is exactly once per window. Starting the engine from `onAppear`
            // would re-run whenever SwiftUI re-appears the view.
            .task {
                model.start(
                    homeURL: Self.launchURL,
                    overrideRestoredTab: Self.launchURLArgument != nil
                )
                // Settings needs a live window to open the engine's settings page; it must not make its own model.
                BrowserCommandRouter.shared.register(model)
                addressState.handleTabSwitch(to: model.currentURL)
            }
            .onChange(of: model.selectedTabID) { _, _ in
                addressState.handleTabSwitch(to: model.currentURL)
            }
            .onChange(of: model.currentURL) { _, newURL in
                addressState.handleURLChange(newURL)
            }
            .onChange(of: model.focusAddressRequested) { _, requested in
                if requested {
                    if !isShowingStartPage {
                        addressState.beginEditing()
                    }
                    model.focusAddressRequested = false
                }
            }
            .toolbar {
                // Navigation history sits in a compact native group at the window's leading edge.
                ToolbarItem(placement: .navigation) {
                    ControlGroup {
                        Button(action: model.goBack) {
                            Label("Back", systemImage: "chevron.backward")
                        }
                        .help("Go back (⌘[)")
                        .disabled(!model.canGoBack)

                        Button(action: model.goForward) {
                            Label("Forward", systemImage: "chevron.forward")
                        }
                        .help("Go forward (⌘])")
                        .disabled(!model.canGoForward)
                    }
                    .controlGroupStyle(.navigation)
                }

                // Centered address capsule in the principal slot, holding resting host and trailing reload.
                ToolbarItem(placement: .principal) {
                    AddressBarView(model: model, state: addressState)
                        .frame(minWidth: 220, idealWidth: 360, maxWidth: 640)
                }

                // Trailing the field, where Safari puts it: `+` reads as "another page of this kind".
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.openTab()
                    } label: {
                        Label("New Tab", systemImage: "plus")
                    }
                    .help("New Tab (⌘T)")
                }
            }
            // The model is per-window state, so its shortcuts live here rather than in `Commands`. ⌘W, ⌘Q, ⌘M and
            // ⌘, stay system-owned.
            .background {
                Group {
                    Button("") { model.reload() }.keyboardShortcut("r", modifiers: .command)
                    Button("") { addressState.beginEditing() }.keyboardShortcut("l", modifiers: .command)
                    // ⌘[ / ⌘] is the macOS convention for history, and it is what the buttons' tooltips promise.
                    Button("") { model.goBack() }.keyboardShortcut("[", modifiers: .command)
                    Button("") { model.goForward() }.keyboardShortcut("]", modifiers: .command)
                    Button("") { model.openTab() }.keyboardShortcut("t", modifiers: .command)
                    // ⌘W closes a tab, not the window: the system Close command would otherwise take the whole window
                    // down, which in a tabbed browser is the wrong granularity. Closing the last tab closes the
                    // window, which is what applicationShouldTerminateAfterLastWindowClosed already does.
                    Button("") { model.closeSelectedTab() }.keyboardShortcut("w", modifiers: .command)
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
        guard let host = URL(string: model.currentURL)?.host(), !host.isEmpty else { return "Ava" }
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
        } else if isShowingStartPage {
            StartPageView(model: model)
        } else {
            WebContentView(webView: model.webView)
        }
    }

    private var isShowingStartPage: Bool {
        model.currentURL.isEmpty || model.currentURL == AppSettings.blankPageURL
    }
}
