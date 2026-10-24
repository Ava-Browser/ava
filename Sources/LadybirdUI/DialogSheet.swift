/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The sheet for the four blocking JS dialogs. Presented on the tab that asked, because that is where the page is
 * stopped: the engine blocks the tab's script until it gets a reply, so a dialog the user cannot see is a wedged page.
 */

import LadybirdEngine
import SwiftUI

struct DialogSheet: View {
    let dialog: TabDialog
    let tab: BrowserTab
    let model: BrowserModel

    @State private var promptText: String = ""
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            Text(dialog.message)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if case let .prompt(_, _, defaultText) = dialog {
                TextField(defaultText, text: $promptText)
                    .textFieldStyle(.roundedBorder)
                    .focused($promptFocused)
                    .onSubmit { accept() }
            }

            HStack {
                Spacer()
                if case .alert = dialog {
                    // An alert is an acknowledgement, not a decision: one button, and Return/Escape both dismiss it.
                    Button("OK", action: accept)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(cancelTitle) { model.answer(dialog, on: tab, accepted: false) }
                        .keyboardShortcut(.cancelAction)
                    Button(acceptTitle, action: accept)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 380, idealWidth: 440)
        .onAppear {
            if case let .prompt(_, _, defaultText) = dialog {
                promptText = defaultText
                promptFocused = true
            }
        }
    }

    private var title: String {
        switch dialog {
        case .alert: "This page says"
        case .confirm: "This page asks"
        case .prompt: "This page asks"
        case .beforeUnload: "Leave this page?"
        }
    }

    private var acceptTitle: String {
        switch dialog {
        case .alert: "OK"
        case .confirm: "OK"
        case .prompt: "OK"
        case .beforeUnload: "Leave"
        }
    }

    /// Declining is the safe default, and for `beforeUnload` the safe answer is the *cancel* one — staying.
    private var cancelTitle: String {
        switch dialog {
        case .alert: "OK"
        case .confirm: "Cancel"
        case .prompt: "Cancel"
        case .beforeUnload: "Stay"
        }
    }

    private func accept() {
        model.answer(dialog, on: tab, accepted: true, promptText: promptText)
    }
}
