/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The active space's three tab tiers. Tier drops are durable model mutations, not view-local rearrangement.
 */

import LadybirdEngine
import SwiftUI

struct TabSidebar: View {
    @Bindable var model: BrowserModel

    var body: some View {
        List(selection: selection) {
            Section("Essentials") {
                if model.essentialTabs.isEmpty {
                    DropHint()
                        .dropDestination(for: String.self) { ids, _ in retier(ids, to: .essential) }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 6)], spacing: 6) {
                        ForEach(model.essentialTabs) { tab in
                            EssentialTabButton(tab: tab, model: model)
                                .draggable(tab.id.raw.uuidString)
                        }
                    }
                    .padding(.vertical, 3)
                    .dropDestination(for: String.self) { ids, _ in retier(ids, to: .essential) }
                }
            }

            Section("Pinned") {
                if model.pinnedTabs.isEmpty {
                    DropHint()
                        .dropDestination(for: String.self) { ids, _ in retier(ids, to: .pinned) }
                } else {
                    ForEach(model.pinnedTabs) { tab in
                        TabRow(tab: tab)
                            .tag(tab.id)
                            .draggable(tab.id.raw.uuidString)
                            .dropDestination(for: String.self) { ids, _ in retier(ids, to: .pinned) }
                            .contextMenu { tabMenu(tab) }
                    }
                }
            }

            Section("Tabs") {
                ForEach(model.normalTabs) { tab in
                    TabRow(tab: tab)
                        .tag(tab.id)
                        .draggable(tab.id.raw.uuidString)
                        .dropDestination(for: String.self) { ids, _ in retier(ids, to: .normal) }
                        .contextMenu { tabMenu(tab) }
                }
                if model.normalTabs.isEmpty {
                    DropHint()
                        .dropDestination(for: String.self) { ids, _ in retier(ids, to: .normal) }
                }
            }

            if !model.normalTabs.isEmpty {
                Section {
                    Button("Close All Unpinned", role: .destructive, action: model.closeAllUnpinned)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private var selection: Binding<TabID?> {
        Binding(
            get: { model.selectedTabID },
            set: { id in
                guard let id, let tab = model.tabs.first(where: { $0.id == id }) else { return }
                model.select(tab)
            }
        )
    }

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

private struct DropHint: View {
    var body: some View {
        Text("Drop a tab here")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .contentShape(Rectangle())
    }
}

private struct EssentialTabButton: View {
    let tab: BrowserTab
    let model: BrowserModel

    var body: some View {
        Button { model.select(tab) } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.isLoading ? "circle.dotted" : "globe")
                    .frame(width: 28, height: 28)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                Text(tab.title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .help(tab.currentURL)
        .contextMenu {
            Button("Move to Pinned") { model.retier(tab, to: .pinned) }
            Button("Move to Tabs") { model.retier(tab, to: .normal) }
            Divider()
            Button("Close Tab", role: .destructive) { model.closeTab(tab) }
        }
    }
}

private struct TabRow: View {
    let tab: BrowserTab

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: tab.isLoading ? "circle.dotted" : (tab.isLoaded ? "globe" : "moon.zzz"))
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
