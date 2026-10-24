/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * One tab's UI-side state. The durable descriptor ID is the identity; the engine tab handle is an ephemeral cache.
 *
 * The surface is deliberately NOT stored here. It is borrowed for the duration of the paint callback (S5), so caching
 * one would be the only remaining use-after-free in this design. Switching tabs re-reads the tab's current frame from
 * the engine instead, which is always valid at call time.
 */

import Foundation
import Observation

/// A dialog the engine is blocked on for one tab.
public enum TabDialog: Identifiable, Equatable {
    case alert(id: UInt64, message: String)
    case confirm(id: UInt64, message: String)
    case prompt(id: UInt64, message: String, defaultText: String)
    case beforeUnload(id: UInt64, source: String)

    public var id: UInt64 {
        switch self {
        case let .alert(id, _), let .confirm(id, _), let .prompt(id, _, _), let .beforeUnload(id, _):
            return id
        }
    }

    public var message: String {
        switch self {
        case let .alert(_, message), let .confirm(_, message), let .prompt(_, message, _):
            return message
        case let .beforeUnload(_, source):
            return "Leave this page?\n\nThe page reported: \(source)"
        }
    }
}

@MainActor
@Observable
public final class BrowserTab: Identifiable {
    /// The durable descriptor UUID.
    public let id: UUID
    /// Ephemeral engine tab handle from `LbTabCreate`. Nil when unloaded.
    public internal(set) var engineID: UInt64?
    public private(set) var currentURL: String = ""
    public private(set) var customTitle: String = ""
    public private(set) var isLoading: Bool = false
    public private(set) var tier: TabTier
    public var workspaceID: UUID?
    /// The dialog this tab's page is stopped on, if any.
    public private(set) var dialog: TabDialog?

    public init(
        id: UUID = UUID(),
        engineID: UInt64? = nil,
        url: String = "",
        title: String = "",
        tier: TabTier = .normal,
        workspaceID: UUID? = nil
    ) {
        self.id = id
        self.engineID = engineID
        self.currentURL = url
        self.customTitle = title
        self.tier = tier
        self.workspaceID = workspaceID
    }

    /// Convenience for tests or legacy code expecting engine ID
    public init(engineID: UInt64, url: String = "") {
        self.id = UUID()
        self.engineID = engineID
        self.currentURL = url
        self.customTitle = ""
        self.tier = .normal
        self.workspaceID = nil
    }

    public var isLoaded: Bool { engineID != nil }

    public var title: String {
        if !customTitle.isEmpty {
            return customTitle
        }
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

    func update(title: String) {
        customTitle = title
    }

    func setTier(_ newTier: TabTier) {
        tier = newTier
        if newTier == .essential {
            workspaceID = nil
        }
    }

    func setLoading(_ loading: Bool) {
        isLoading = loading
    }

    func present(dialog: TabDialog) {
        self.dialog = dialog
    }

    func clearDialog() {
        dialog = nil
    }
}
