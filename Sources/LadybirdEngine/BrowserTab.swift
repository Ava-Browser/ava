/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * One tab's UI-side state. The engine tab id is the identity: the engine keeps the page alive, and this only records
 * what the chrome needs to draw a row and what the address bar should show when the tab is selected.
 *
 * The surface is deliberately NOT stored here. It is borrowed for the duration of the paint callback (S5), so caching
 * one would be the only remaining use-after-free in this design. Switching tabs re-reads the tab's current frame from
 * the engine instead, which is always valid at call time.
 */

import Foundation
import Observation

@MainActor
@Observable
public final class BrowserTab: Identifiable {
    /// The engine's tab handle from `LbTabCreate`, and the identity SwiftUI uses. Stable for the tab's life.
    public let id: UInt64
    public private(set) var currentURL: String = ""
    public private(set) var isLoading: Bool = false

    init(id: UInt64) {
        self.id = id
    }

    /// What the sidebar row shows. The ABI has no page-title callback yet, so the host is the best available label;
    /// falling back to the URL keeps about:blank and data: pages identifiable rather than blank.
    public var title: String {
        if let host = URL(string: currentURL)?.host(), !host.isEmpty {
            return host
        }
        if currentURL.isEmpty || currentURL == "about:blank" {
            return "New Tab"
        }
        return currentURL
    }

    func update(url: String) {
        currentURL = url
    }

    func setLoading(_ loading: Bool) {
        isLoading = loading
    }
}
