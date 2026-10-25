/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Address bar formatting and draft state coordination.
 */

import Foundation
import Observation

/// Pure URL formatting rules for the compact address bar.
public enum AddressFormatter {
    /// Formats the resting address for compact centered display.
    ///
    /// - Ordinary HTTP(S) pages: Full parsed host. Non-standard ports (anything other than 80 for HTTP or
    ///   443 for HTTPS) are appended so unusual ports are never hidden. Subdomains are fully preserved.
    ///   IPv6 hosts are enclosed in brackets.
    /// - Empty string or "about:blank": Returns an empty string, prompting the subdued placeholder.
    /// - Other URL types (file:, about:, data:, etc.): Safe explicit display of the raw URL, never guessing a host.
    /// - Parse failures: Safe explicit display of the input without trimming into a false domain.
    public static func restingDisplay(for urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed == "about:blank" { return "" }

        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = components.host, !host.isEmpty else {
            return trimmed
        }

        let formattedHost: String
        if host.contains(":") && !host.hasPrefix("[") && !host.hasSuffix("]") {
            formattedHost = "[\(host)]"
        } else {
            formattedHost = host
        }

        if let port = components.port {
            let isStandard = (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
            if !isStandard {
                return "\(formattedHost):\(port)"
            }
        }

        return formattedHost
    }
}

/// Observable state for the browser address bar, separating resting display from active editing drafts.
@MainActor
@Observable
public final class AddressBarState {
    public private(set) var currentURL: String
    public var isEditing: Bool
    public var draft: String
    /// Increments on every request to enter or focus the address field, enabling repeated Cmd-L selection.
    public private(set) var editRequestToken: Int

    public init(initialURL: String = "") {
        self.currentURL = initialURL
        self.draft = ""
        self.isEditing = false
        self.editRequestToken = 0
    }

    /// The text displayed when resting (not editing).
    public var restingDisplay: String {
        AddressFormatter.restingDisplay(for: currentURL)
    }

    /// The complete URL suitable for copying to the system pasteboard.
    public var copyableURL: String {
        currentURL
    }

    /// Begins editing or requests re-selection, populating the draft with the full URL.
    public func beginEditing() {
        if !isEditing {
            isEditing = true
            draft = (currentURL == "about:blank") ? "" : currentURL
        }
        editRequestToken += 1
    }

    /// Discards any in-progress draft and restores resting display without navigating.
    public func discardDraft() {
        isEditing = false
        draft = ""
    }

    /// Commits the in-progress draft, returning the trimmed string for submission if non-empty, and exits editing.
    public func commitDraft() -> String? {
        guard isEditing else { return nil }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditing = false
        draft = ""
        return text.isEmpty ? nil : text
    }

    /// Responds to a tab switch: discards any active draft and synchronizes with the newly selected tab's URL.
    public func handleTabSwitch(to url: String) {
        isEditing = false
        draft = ""
        currentURL = url
    }

    /// Responds to page load / redirect notifications.
    /// In-progress drafts are preserved so background callbacks do not overwrite user input.
    public func handleURLChange(_ newURL: String) {
        currentURL = newURL
    }
}
