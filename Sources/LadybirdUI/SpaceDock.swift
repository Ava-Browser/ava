/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The compact workspace switcher at the foot of the sidebar. Accessible horizontal scrolling with New Space retained.
 */

import LadybirdEngine
import SwiftUI

struct SpaceDock: View {
    @Bindable var model: BrowserModel
    let actionState: SpaceActionState

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.workspaces) { workspace in
                        Button {
                            model.selectWorkspace(workspace)
                        } label: {
                            WorkspaceIconView(icon: workspace.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(model.activeWorkspace?.id == workspace.id ? Color.primary : Color.secondary)
                                .frame(width: 28, height: 24)
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
                        .buttonStyle(.plain)
                        .accessibilityLabel("Space \(workspace.name)")
                        .help(workspace.name)
                        .contextMenu {
                            SpaceContextMenu(workspace: workspace, model: model, actionState: actionState)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 4)

            Button(action: { model.createWorkspace() }) {
                Label("New Space", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create New Space")
            .help("New Space")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
    }
}
