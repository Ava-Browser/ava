/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The vertical tab list, and the only tab list — there is no top tab strip. One workspace, no spaces or pinning.
 *
 * Uses `List` with a selection binding rather than a hand-rolled stack of buttons: it brings keyboard navigation,
 * VoiceOver row semantics and the system selection highlight for free, and those are exactly the things a custom list
 * gets wrong.
 */

import LadybirdEngine
import SwiftUI

struct TabSidebar: View {
    @Bindable var model: BrowserModel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: selection) {
                ForEach(model.tabs) { tab in
                    TabRow(tab: tab)
                        .tag(tab.id)
                        .contextMenu {
                            Button("Close Tab") { model.closeTab(tab) }
                        }
                }
            }
            .listStyle(.sidebar)
            // The list's own background; the sidebar is chrome and should take the system material, not a colour.
            .scrollContentBackground(.hidden)

            Divider()
            HStack(spacing: 2) {
                Button {
                    model.openTab()
                } label: {
                    Label("New Tab", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("New Tab (⌘T)")

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    /// A `List` selection binding is `UInt64?` over the tags; an empty sidebar has no valid selection at all.
    private var selection: Binding<UInt64?> {
        Binding(
            get: { model.selectedTabID },
            set: { newValue in
                guard let newValue, let tab = model.tabs.first(where: { $0.id == newValue }) else { return }
                model.select(tab)
            }
        )
    }
}

private struct TabRow: View {
    let tab: BrowserTab

    var body: some View {
        HStack(spacing: 7) {
            // One glyph, two states: no spinner. A spinner is a timer-driven animation, and the engine reports loads
            // through callbacks already, so a static state change is both cheaper and honest about what we know.
            Image(systemName: tab.isLoading ? "circle.dotted" : "globe")
                .foregroundStyle(.secondary)
                .imageScale(.small)
                .accessibilityHidden(true)

            Text(tab.title)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .help(tab.currentURL.isEmpty ? "New Tab" : tab.currentURL)
    }
}
