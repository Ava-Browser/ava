/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Observable application settings backed by UserDefaults, with strict validation and safe fallbacks.
 */

import AppKit
import Foundation
import Observation

/// The appearance of the app chrome (window, sidebar, sheets, settings).
///
/// Note: Page content theming in WebContent is separate and not modified by this setting.
public enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Applies this appearance policy via NSApp.appearance.
    ///
    /// Setting NSApp.appearance cleanly cascades to all windows and views without conflicting
    /// per-view preferredColorScheme overrides. If NSApp is not initialized (such as in headless
    /// unit tests), this safely no-ops.
    @MainActor
    public func apply() {
        guard let app = NSApp else { return }
        switch self {
        case .system:
            app.appearance = nil
        case .light:
            app.appearance = NSAppearance(named: .aqua)
        case .dark:
            app.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// Destination for newly opened tabs when the caller does not provide an explicit URL.
public enum NewTabDestinationType: String, CaseIterable, Identifiable, Sendable {
    case blank
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .blank: "Blank Page"
        case .custom: "Custom URL"
        }
    }
}

/// Errors raised when validating a custom destination URL.
public enum DestinationValidationError: LocalizedError, Equatable, Sendable {
    case empty
    case invalidURL
    case unsupportedScheme(String)
    case missingHost

    public var errorDescription: String? {
        switch self {
        case .empty:
            "URL cannot be empty."
        case .invalidURL:
            "Please enter a valid URL."
        case .unsupportedScheme(let scheme):
            "Scheme '\(scheme)' is not supported. Use http://, https://, or about:blank."
        case .missingHost:
            "URL must include a valid host name."
        }
    }
}

@MainActor
@Observable
public final class AppSettings {
    public static let appearanceKey = "org.ladybird.settings.appearance"
    public static let newTabTypeKey = "org.ladybird.settings.newTabType"
    public static let newTabCustomURLKey = "org.ladybird.settings.newTabCustomURL"

    public static let defaultCustomURL = "https://example.com"
    public static let blankPageURL = "about:blank"

    @ObservationIgnored private let userDefaults: UserDefaults

    public private(set) var appearance: AppAppearance
    public private(set) var newTabDestinationType: NewTabDestinationType
    public private(set) var customNewTabURL: String

    public static let shared = AppSettings()

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // 1. Appearance with safe fallback
        if let raw = userDefaults.string(forKey: Self.appearanceKey),
           let parsed = AppAppearance(rawValue: raw) {
            appearance = parsed
        } else {
            appearance = .system
        }

        // 2. New tab type with safe fallback
        if let raw = userDefaults.string(forKey: Self.newTabTypeKey),
           let parsed = NewTabDestinationType(rawValue: raw) {
            newTabDestinationType = parsed
        } else {
            newTabDestinationType = .blank
        }

        // 3. Custom new tab URL with validation and safe fallback
        if let savedURL = userDefaults.string(forKey: Self.newTabCustomURLKey),
           case .success(let validated) = Self.validate(url: savedURL) {
            customNewTabURL = validated
        } else {
            customNewTabURL = Self.defaultCustomURL
        }
    }

    /// The concrete URL string to use when opening a new tab without an explicit URL.
    ///
    /// BrowserModel reads this directly so it does not need to know the destination enum.
    public var newTabURL: String {
        switch newTabDestinationType {
        case .blank:
            Self.blankPageURL
        case .custom:
            customNewTabURL
        }
    }

    // MARK: - Mutators

    public func setAppearance(_ newAppearance: AppAppearance) {
        appearance = newAppearance
        userDefaults.set(newAppearance.rawValue, forKey: Self.appearanceKey)
        newAppearance.apply()
    }

    public func setNewTabDestinationType(_ type: NewTabDestinationType) {
        newTabDestinationType = type
        userDefaults.set(type.rawValue, forKey: Self.newTabTypeKey)
    }

    /// Commits a validated custom destination URL.
    ///
    /// If the input is invalid, the previous valid value is preserved, nothing is written to
    /// UserDefaults, and a validation failure is returned.
    @discardableResult
    public func commitCustomNewTabURL(_ candidate: String) -> Result<String, DestinationValidationError> {
        switch Self.validate(url: candidate) {
        case .success(let validURL):
            customNewTabURL = validURL
            userDefaults.set(validURL, forKey: Self.newTabCustomURLKey)
            return .success(validURL)
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Applies the currently configured appearance to the application.
    public func applyAppearance() {
        appearance.apply()
    }

    // MARK: - Validation

    /// Validates a custom destination URL candidate against allowed schemes (http, https, about:blank).
    ///
    /// Does not convert invalid text or bare words into searches.
    public static func validate(url candidate: String) -> Result<String, DestinationValidationError> {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.empty)
        }

        if trimmed.lowercased() == blankPageURL {
            return .success(blankPageURL)
        }

        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased() else {
            return .failure(.invalidURL)
        }

        guard scheme == "http" || scheme == "https" else {
            return .failure(.unsupportedScheme(scheme))
        }

        guard let host = components.host, !host.isEmpty else {
            return .failure(.missingHost)
        }

        // Must be constructible as a valid Foundation URL
        guard components.url != nil else {
            return .failure(.invalidURL)
        }

        return .success(trimmed)
    }
}
