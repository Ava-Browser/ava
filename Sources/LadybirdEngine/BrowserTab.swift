/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * One tab's runtime state. Its durable identity and metadata live in TabDescriptor; its engine handle is disposable.
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
    /// Stable across launches and independent of the engine's opaque u64 handle.
    public let id: TabID
    /// nil means unloaded. The descriptor remains and selecting it rehydrates this cache entry.
    public private(set) var engineID: UInt64?
    public private(set) var currentURL: String
    public private(set) var title: String
    public private(set) var isLoading: Bool = false
    public private(set) var dialog: TabDialog?

    init(descriptor: TabDescriptor, engineID: UInt64? = nil) {
        id = descriptor.id
        self.engineID = engineID
        currentURL = descriptor.url
        title = descriptor.title
    }

    public var isLoaded: Bool { engineID != nil }

    func attach(engineID: UInt64) {
        self.engineID = engineID
    }

    func detach() {
        engineID = nil
        isLoading = false
        dialog = nil
    }

    func update(url: String) {
        currentURL = url
        if let host = URL(string: url)?.host(), !host.isEmpty {
            title = host
        } else if url.isEmpty || url == "about:blank" {
            title = "New Tab"
        } else {
            title = url
        }
    }

    func setLoading(_ loading: Bool) { isLoading = loading }
    func present(dialog: TabDialog) { self.dialog = dialog }
    func clearDialog() { dialog = nil }
}
