/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The compact workspace switcher at the foot of the sidebar. The system split view still owns collapse behaviour.
 */

import LadybirdEngine
import SwiftUI

struct SpaceDock: View {
    @Bindable var model: BrowserModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(model.workspaces) { workspace in
                Button { model.selectWorkspace(workspace) } label: {
                    Group {
                        if workspace.icon.contains(".") {
                            Image(systemName: workspace.icon)
                        } else {
                            Text(workspace.icon)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 24)
                    .background {
                            if model.activeWorkspace?.id == workspace.id {
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [Color(hex: workspace.theme.startHex), Color(hex: workspace.theme.endHex)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(workspace.name)
            }

            Spacer(minLength: 0)

            Button(action: { model.createWorkspace() }) {
                Label("New Space", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("New Space")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x808080
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255,
            opacity: 1
        )
    }
}
