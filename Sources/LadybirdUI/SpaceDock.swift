/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The compact workspace switcher at the foot of the sidebar. Center-aligned scrollable dots with right-aligned New Space.
 */

import LadybirdEngine
import SwiftUI

struct SpaceDockButton: View {
    let workspace: Workspace
    let isActive: Bool
    let isRevealed: Bool
    let action: () -> Void

    @State private var isItemHovered: Bool = false
    @FocusState.Binding var focusedSpaceID: UUID?

    var body: some View {
        Button(action: action) {
            ZStack {
                if isActive {
                    if workspace.icon != "circle.fill" {
                        Capsule()
                            .fill(LinearGradient(
                                colors: [
                                    Color(hex: workspace.theme.startHex).opacity(0.20),
                                    Color(hex: workspace.theme.endHex).opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    }
                } else if isItemHovered {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                }

                if isRevealed {
                    revealedIconView
                } else {
                    restingView
                }
            }
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .overlay {
                if focusedSpaceID == workspace.id {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .focused($focusedSpaceID, equals: workspace.id)
        .onHover { isItemHovered = $0 }
        .accessibilityLabel("Space \(workspace.name)")
        .accessibilityValue(isActive ? "Selected" : "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .help(workspace.name)
    }

    @ViewBuilder
    private var restingView: some View {
        if isActive {
            if workspace.icon == "circle.fill" {
                Circle()
                    .fill(Color.primary)
                    .frame(width: 7, height: 7)
            } else {
                WorkspaceIconView(icon: workspace.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary)
            }
        } else {
            Circle()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 6, height: 6)
        }
    }

    @ViewBuilder
    private var revealedIconView: some View {
        if workspace.icon == "circle.fill" {
            Circle()
                .fill(isActive ? Color.primary : Color.secondary.opacity(0.60))
                .frame(width: isActive ? 7 : 6, height: isActive ? 7 : 6)
        } else {
            WorkspaceIconView(icon: workspace.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
        }
    }
}

struct SpaceDock: View {
    @Bindable var model: BrowserModel
    let actionState: SpaceActionState

    @State private var isGroupHovered: Bool = false
    @FocusState private var focusedSpaceID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRevealed: Bool {
        isGroupHovered || focusedSpaceID != nil
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                Spacer(minLength: 32)

                GeometryReader { geo in
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                ForEach(model.workspaces) { workspace in
                                    SpaceDockButton(
                                        workspace: workspace,
                                        isActive: model.activeWorkspace?.id == workspace.id,
                                        isRevealed: isRevealed,
                                        action: { model.selectWorkspace(workspace) },
                                        focusedSpaceID: $focusedSpaceID
                                    )
                                    .id(workspace.id)
                                    .contextMenu {
                                        SpaceContextMenu(workspace: workspace, model: model, actionState: actionState)
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                            .frame(minWidth: geo.size.width, alignment: .center)
                            .animation(reduceMotion ? .none : .easeInOut(duration: 0.18), value: isRevealed)
                        }
                        .onAppear {
                            if let activeID = model.activeWorkspace?.id {
                                proxy.scrollTo(activeID, anchor: .center)
                            }
                        }
                        .onChange(of: model.activeWorkspace?.id) { _, newID in
                            if let newID {
                                if reduceMotion {
                                    proxy.scrollTo(newID, anchor: .center)
                                } else {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        proxy.scrollTo(newID, anchor: .center)
                                    }
                                }
                            }
                        }
                        .onChange(of: focusedSpaceID) { _, newID in
                            if let newID {
                                if reduceMotion {
                                    proxy.scrollTo(newID, anchor: .center)
                                } else {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        proxy.scrollTo(newID, anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                }
                .onHover { isGroupHovered = $0 }

                Spacer(minLength: 32)
            }

            // Right-aligned New Space (+) Button
            Button(action: { model.createWorkspace() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create New Space")
            .help("New Space")
            .padding(.trailing, 10)
        }
        .frame(height: 34)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            if let active = model.activeWorkspace {
                SpaceContextMenu(workspace: active, model: model, actionState: actionState)
            }
        }
    }
}
