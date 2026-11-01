/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Where a link goes, before the user commits to clicking it. A browser without this cannot be used safely on a page
 * whose visible text and destination disagree.
 */

import SwiftUI

struct HoveredLinkStrip: View {
    let url: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(url)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 20)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        // The whole point is the destination, so the accessible label is the URL itself rather than the icon.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Link destination")
        .accessibilityValue(url)
    }
}
