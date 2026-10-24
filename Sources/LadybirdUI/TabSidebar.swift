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
        // The list owns the whole column. The "new tab" button used to sit in a hand-drawn bar under a manual
        // Divider, but a sidebar action belongs in the toolbar where macOS puts it, and the divider was a second
        // separator immediately above the split view's own — visibly two lines where the system draws one.
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
        // One action: a new tab. In the toolbar's sidebar group it collapses with the sidebar and takes the same
        // control size as every other toolbar button, instead of being the one control at a different scale.
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.openTab()
                } label: {
                    Label("New Tab", systemImage: "plus")
                }
                .help("New Tab (⌘T)")
            }
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
