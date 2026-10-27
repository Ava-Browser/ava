/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import LadybirdEngine
import SwiftUI

struct StartPageView: View {
    let model: BrowserModel

    @State private var query = ""
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    themedLiftMark
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)

                    Text("ava")
                        .font(.system(size: 24, weight: .medium))
                        .tracking(-0.7)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Ava")

                searchField
            }
            .frame(maxWidth: 520)
            .position(x: geometry.size.width / 2, y: geometry.size.height * 0.38)
        }
        .padding(.horizontal, 40)
        .background(colorScheme == .light ? Color(red: 0.953, green: 0.945, blue: 0.922) : Color(nsColor: .windowBackgroundColor))
        .onAppear { isSearchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search or enter a URL", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .tint(colorScheme == .dark ? .white : Color(red: 0.14, green: 0.15, blue: 0.16))
                .focused($isSearchFocused)
                .onSubmit(submit)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: 520, minHeight: 56)
        .background(searchFieldBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.primary.opacity(colorScheme == .dark ? 0.14 : 0.1), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var searchFieldBackground: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(colorScheme == .light ? Color.white.opacity(0.62) : Color.white.opacity(0.07))
    }

    @ViewBuilder
    private var themedLiftMark: some View {
        if let theme = model.activeWorkspace?.theme {
            LiftMark()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: theme.startHex), Color(hex: theme.endHex)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(colorScheme == .light ? 0.82 : 0.9)
        } else {
            LiftMark().fill(.primary)
        }
    }

    private func submit() {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        model.load(input)
    }
}

struct LiftMark: Shape {
    func path(in rect: CGRect) -> Path {
        let source = CGSize(width: 300, height: 300)
        let scale = min(rect.width / source.width, rect.height / source.height)
        let x = rect.minX + (rect.width - source.width * scale) / 2
        let y = rect.minY + (rect.height - source.height * scale) / 2

        func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
            CGPoint(x: x + px * scale, y: y + py * scale)
        }

        var path = Path()
        path.move(to: point(61, 230))
        path.addCurve(to: point(47, 108), control1: point(25, 203), control2: point(24, 150))
        path.addCurve(to: point(174, 42), control1: point(74, 58), control2: point(122, 33))
        path.addCurve(to: point(258, 142), control1: point(225, 51), control2: point(258, 91))
        path.addCurve(to: point(212, 238), control1: point(258, 180), control2: point(242, 213))
        path.addCurve(to: point(208, 137), control1: point(228, 197), control2: point(226, 164))
        path.addCurve(to: point(135, 109), control1: point(190, 110), control2: point(163, 99))
        path.addCurve(to: point(102, 174), control1: point(108, 118), control2: point(98, 145))
        path.addCurve(to: point(79, 232), control1: point(106, 202), control2: point(96, 225))
        path.addQuadCurve(to: point(61, 230), control: point(69, 237))
        path.closeSubpath()
        return path
    }
}
