/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Opt-in instrumentation for measuring presentation, not a feature. Inert unless LB_BENCH names an output path.
 *
 * It answers questions a profiler cannot: how many paints a scroll burst actually produces (R3 says a settled page
 * emits one, so a burst producing hundreds would mean something is re-rendering), and whether we paint at the scale the
 * display asked for or at twice it.
 *
 * No timers and no redraw loop of its own (R3): it only timestamps events the engine already sends us.
 */

import Foundation
import QuartzCore

@MainActor
public final class PortBenchmark {
    public static let shared = PortBenchmark()

    private let handle: FileHandle?

    private init() {
        let path = ProcessInfo.processInfo.environment["LB_BENCH"]
        if let path, !path.isEmpty {
            FileManager.default.createFile(atPath: path, contents: nil)
            handle = FileHandle(forWritingAtPath: path)
        } else {
            handle = nil
        }
    }

    public var isEnabled: Bool { handle != nil }

    /// One row per frame, so paint counts and gaps can be computed offline.
    func recordPaint(painted: (Int, Int), surface: (Int, Int), cssSize: CGSize) {
        guard isEnabled else { return }
        let now = CACurrentMediaTime()
        // device pixel ratio implied by what was actually painted, which is the number a double-applied scale would move.
        let impliedScale = cssSize.width > 0 ? Double(painted.0) / Double(cssSize.width) : 0
        write(String(
            format: "paint t=%.6f painted=%dx%d surface=%dx%d css=%dx%d implied_scale=%.3f",
            now, painted.0, painted.1, surface.0, surface.1,
            Int(cssSize.width), Int(cssSize.height), impliedScale
        ))
    }

    func recordLoad(url: String) {
        guard isEnabled else { return }
        write(String(format: "load t=%.6f url=%@", CACurrentMediaTime(), url))
    }

    /// Flushes on every write so a run that is killed still leaves usable data.
    private func write(_ line: String) {
        guard let handle else { return }
        handle.write(Data((line + "\n").utf8))
    }
}
