/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Safari-style quiet address capsule with centered resting host and inline controls.
 */

import LadybirdEngine
import SwiftUI

public struct AddressBarView: View {
    let model: BrowserModel
    @Bindable var state: AddressBarState

    public init(model: BrowserModel, state: AddressBarState) {
        self.model = model
        self.state = state
    }

    public var body: some View {
        ZStack {
            // Safari's field is a capsule in both states: the radius is half the height, and only the ring changes.
            // Editing swaps the hairline for a 2 pt accent ring instead of resizing or re-rounding the shape.
            Capsule()
                .fill(Color.secondary.opacity(0.1))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            state.isEditing ? Color.accentColor : Color.secondary.opacity(0.25),
                            lineWidth: state.isEditing ? 2 : 0.75
                        )
                )

            // Center slot: Centered resting host button spanning the middle area, or editable AddressNativeField.
            if state.isEditing {
                AddressNativeField(
                    text: $state.draft,
                    editRequestToken: state.editRequestToken,
                    onSubmit: {
                        if let text = state.commitDraft(), !text.isEmpty {
                            model.load(text)
                        }
                    },
                    onCancel: {
                        state.discardDraft()
                    }
                )
                .padding(.horizontal, 32)
            } else {
                Button {
                    state.beginEditing()
                } label: {
                    Text(state.restingDisplay.isEmpty ? "Search or enter address" : state.restingDisplay)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(state.restingDisplay.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .accessibilityLabel("Address and Search")
                .accessibilityValue(state.restingDisplay.isEmpty ? "Empty" : state.restingDisplay)
                .accessibilityHint("Activate to enter address or search term")
            }

            // Inline leading and trailing controls with identical fixed width to preserve center symmetry.
            HStack(spacing: 0) {
                leadingAffordance
                    .frame(width: 28, height: 28)

                Spacer()

                trailingReload
                    .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 32)
        .contextMenu {
            if !state.copyableURL.isEmpty {
                Button("Copy Address") {
                    model.copyCurrentURL()
                }
            }
        }
    }

    @ViewBuilder
    private var leadingAffordance: some View {
        if model.isLoading {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "globe")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
        }
    }

    private var trailingReload: some View {
        Button(action: model.reload) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
        .help("Reload the page (⌘R)")
        .disabled(model.currentURL.isEmpty)
        .accessibilityLabel("Reload")
    }
}
