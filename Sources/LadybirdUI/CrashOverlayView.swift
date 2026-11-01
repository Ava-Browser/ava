/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * What a dead renderer looks like. Not a crash reporter: the tab's last frame is still attached to the web view, so a
 * page that stopped working would otherwise be indistinguishable from one that finished painting and is waiting.
 */

import LadybirdEngine
import SwiftUI

struct CrashOverlayView: View {
    let model: BrowserModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
            Text("This page stopped working")
                .font(.headline)
            Text("The page's process ended. Reloading usually brings it back.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Reload") { model.reload() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 12, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page stopped working")
    }
}
