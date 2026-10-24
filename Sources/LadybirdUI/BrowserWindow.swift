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
    @FocusState private var addressFocused: Bool

    public init() {}

    public var body: some View {
        content
            .frame(minWidth: 480, minHeight: 320)
            .navigationTitle(windowTitle)
            // `task` runs once per view identity, which is exactly once per window. Starting the engine from `onAppear`
            // would re-run whenever SwiftUI re-appears the view.
            .task { model.start() }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: model.reload) {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .help("Reload the page (⌘R)")
                    .disabled(model.currentURL.isEmpty)
                }

                // The address field is the window's primary control, so it takes the flexible middle slot rather than
                // sitting in a custom header strip under the toolbar.
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: model.isLoading ? "circle.dotted" : "globe")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                            .accessibilityHidden(true)

                        TextField("Search or enter address", text: $model.addressText)
                            .textFieldStyle(.roundedBorder)
                            .focused($addressFocused)
                            .onSubmit(model.submitAddress)
                            .frame(minWidth: 240, idealWidth: 520)
                    }
                }
            }
            // The model is per-window state, so its shortcuts live here rather than in `Commands`. ⌘W, ⌘Q, ⌘M and
            // ⌘, stay system-owned.
            .background {
                Group {
                    Button("") { model.reload() }.keyboardShortcut("r", modifiers: .command)
                    Button("") { addressFocused = true }.keyboardShortcut("l", modifiers: .command)
                }
                .opacity(0)
                .accessibilityHidden(true)
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
