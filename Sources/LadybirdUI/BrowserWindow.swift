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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var addressFocused: Bool

    public init() {}

    /// The page to open at launch.
    ///
    /// `--url <value>` only, and note the prefix: a *bare* positional argument makes AppKit treat the launch as a
    /// document-open request, and SwiftUI then never creates a window at all (measured — the process runs, the window
    /// does not exist). Requiring the flag keeps that path untouched.
    ///
    /// This exists because there is otherwise no way to point the app at a page without driving the UI, which a
    /// benchmark or a regression script cannot do reliably.
    private static var launchURL: String {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--url"), args.index(after: i) < args.endIndex {
            return args[args.index(after: i)]
        }
        // Tolerate `--url=<value>` too, which is what most callers reach for first.
        for arg in args where arg.hasPrefix("--url=") {
            return String(arg.dropFirst("--url=".count))
        }
        return "https://example.com"
    }

    public var body: some View {
        // One workspace: the sidebar is the only tab list, and the page sits beside it.
        //
        // This was an HSplitView, on the grounds that the window had no collapse behaviour and a split view would only
        // add chrome nobody asked for. The sidebar now collapses, and that reverses the trade: the header toggle, the
        // ⌃⌘S shortcut, the animated width change, the material behind the list and the collapsed state that stops
        // taking keystrokes are all behaviours an HSplitView does not have and would each have to be rebuilt by hand —
        // probably subtly wrong, since the collapsed case is the one nobody remembers to test.
        NavigationSplitView(columnVisibility: $columnVisibility) {
            TabSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 320)
        } detail: {
            content
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 320)
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
            .task { model.start(homeURL: Self.launchURL) }
            .toolbar {
                // One principal item holding the navigation cluster, the address field and New Tab.
                //
                // These were separate toolbar items, with the buttons in `.navigation` and the field in `.principal`.
                // That pins the buttons to the window's left edge and centres the field independently, which opens a
                // dead gap between them that grows with the window -- the header looked assembled rather than drawn.
                // Safari centres the cluster as a unit and lets the buttons hug the field; one item reproduces that,
                // and the field's own ceiling is what stops the group stretching.
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 10) {
                        // Back/forward/reload read left to right in the order every macOS browser uses. Each is gated
                        // on the engine's own answer (`canGoBack`/`canGoForward`, refreshed when navigation happens)
                        // rather than a guessed history depth, so a button cannot disagree with what traversing would
                        // actually do.
                        HStack(spacing: 14) {
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

                            Button(action: model.reload) {
                                Label("Reload", systemImage: "arrow.clockwise")
                            }
                            .help("Reload the page (⌘R)")
                            .disabled(model.currentURL.isEmpty)
                        }
                        .buttonStyle(.borderless)
                        .labelStyle(.iconOnly)

                        // The icon sits *inside* the field, on the text's own leading edge, which is the macOS
                        // convention (Safari, Mail, System Settings). A sibling HStack put the icon outside the border,
                        // where it read as a separate control and the rounded border's own insets misaligned it against
                        // the text.
                        HStack(spacing: 6) {
                            Image(systemName: model.isLoading ? "arrow.trianglehead.2.clockwise.rotate.90" : "globe")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.secondary)
                                .frame(width: 14, height: 14)
                                .accessibilityHidden(true)

                            TextField("Search or enter address", text: $model.addressText)
                                .textFieldStyle(.plain)
                                .focused($addressFocused)
                                .onSubmit(model.submitAddress)
                        }
                        // The field draws its own capsule, always.
                        //
                        // It used to rely on the toolbar item's chrome, because a background of its own stacked a
                        // second border inside the one macOS drew for a single-item `.principal`. Now the item holds
                        // the whole cluster, no per-item chrome is drawn, and the field would otherwise have no
                        // background at all -- which is what the screenshot showed. The condition is gone rather than
                        // inverted: it was only ever there to avoid a second border, and there is no first one now.
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background { FieldChrome() }
                        // Ceiling on the field, not on the group: without it the pill grows to fill the toolbar, and
                        // the cluster stops reading as centred.
                        .frame(minWidth: 240, idealWidth: 520, maxWidth: 620)
                        .contentShape(Rectangle())
                        .onTapGesture { addressFocused = true }

                        // Trailing the field, where Safari puts it: `+` reads as "another page of this kind", so it
                        // belongs next to the address it would open rather than in the sidebar's navigation group.
                        Button {
                            model.openTab()
                        } label: {
                            Label("New Tab", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                        .labelStyle(.iconOnly)
                        .help("New Tab (⌘T)")
                    }
                }
            }
            // The model is per-window state, so its shortcuts live here rather than in `Commands`. ⌘W, ⌘Q, ⌘M and
            // ⌘, stay system-owned.
            .background {
                Group {
                    Button("") { model.reload() }.keyboardShortcut("r", modifiers: .command)
                    Button("") { addressFocused = true }.keyboardShortcut("l", modifiers: .command)
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

    /// The address field's capsule, drawn by the host.
    ///
    /// `textBackgroundColor` and `separatorColor` rather than literals, so it follows the system's appearance instead
    /// of staying light on a dark window.
    private struct FieldChrome: View {
        var body: some View {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                // A material, not `textBackgroundColor`: that colour is near-white in light mode but *darker* than the
                // toolbar in dark mode, so the field read as a black bar. A material is defined relative to what is
                // behind it, which is the one property that has to hold on both appearances.
                .fill(.thinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                }
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
}
