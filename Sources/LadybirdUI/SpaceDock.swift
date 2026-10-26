/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The compact workspace switcher at the foot of the sidebar. Center-aligned scrollable dots with right-aligned New Space.
 */

import LadybirdEngine
import SwiftUI

struct SpaceDock: View {
    @Bindable var model: BrowserModel
    let actionState: SpaceActionState

    var body: some View {
        ZStack(alignment: .trailing) {
            // Center-aligned scrollable dots/spaces
            HStack(spacing: 0) {
                Spacer(minLength: 32)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.workspaces) { workspace in
                            Button {
                                model.selectWorkspace(workspace)
                            } label: {
                                Group {
                                    if workspace.icon == "circle.fill" {
                                        if model.activeWorkspace?.id == workspace.id {
                                            Capsule()
                                                .fill(LinearGradient(
                                                    colors: [Color(hex: workspace.theme.startHex), Color(hex: workspace.theme.endHex)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ))
                                                .frame(width: 18, height: 6)
                                        } else {
                                            Circle()
                                                .fill(Color.secondary.opacity(0.45))
                                                .frame(width: 6, height: 6)
                                        }
                                    } else {
                                        WorkspaceIconView(icon: workspace.icon)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(model.activeWorkspace?.id == workspace.id ? Color.primary : Color.secondary)
                                            .frame(width: 24, height: 20)
                                            .background {
                                                if model.activeWorkspace?.id == workspace.id {
                                                    Capsule()
                                                        .fill(LinearGradient(
                                                            colors: [
                                                                Color(hex: workspace.theme.startHex).opacity(0.35),
                                                                Color(hex: workspace.theme.endHex).opacity(0.25)
                                                            ],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        ))
                                                        .background(Capsule().fill(.quaternary))
                                                }
                                            }
                                    }
                                }
                                .frame(minWidth: 24, minHeight: 24)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Space \(workspace.name)")
                            .accessibilityAddTraits(model.activeWorkspace?.id == workspace.id ? .isSelected : [])
                            .help(workspace.name)
                            .contextMenu {
                                SpaceContextMenu(workspace: workspace, model: model, actionState: actionState)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .center)
                }

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
