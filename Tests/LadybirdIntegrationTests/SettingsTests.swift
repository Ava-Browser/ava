/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Isolated unit tests for application settings persistence, validation, and safe fallbacks.
 */

import Foundation
import Testing

@testable import LadybirdEngine

@Suite("App Settings persistence and validation", .serialized)
@MainActor
struct SettingsTests {
    private func createIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "org.ladybird.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }

    private func cleanUpDefaults(_ suiteName: String) {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @Test("Fresh settings start with default values")
    func defaultsOnCleanState() {
        let (defaults, suiteName) = createIsolatedDefaults()
        defer { cleanUpDefaults(suiteName) }

        let settings = AppSettings(userDefaults: defaults)
        #expect(settings.appearance == .system)
        #expect(settings.newTabDestinationType == .blank)
        #expect(settings.customNewTabURL == AppSettings.defaultCustomURL)
        #expect(settings.newTabURL == "about:blank")
    }

    @Test("Appearance changes persist and update observable state")
    func appearancePersistence() {
        let (defaults, suiteName) = createIsolatedDefaults()
        defer { cleanUpDefaults(suiteName) }

        let settings = AppSettings(userDefaults: defaults)
        settings.setAppearance(.dark)
        #expect(settings.appearance == .dark)
        #expect(defaults.string(forKey: AppSettings.appearanceKey) == "dark")

        settings.setAppearance(.light)
        #expect(settings.appearance == .light)
        #expect(defaults.string(forKey: AppSettings.appearanceKey) == "light")

        settings.setAppearance(.system)
        #expect(settings.appearance == .system)
        #expect(defaults.string(forKey: AppSettings.appearanceKey) == "system")

        // Fresh instance reading from the same store reflects the last value
        let restored = AppSettings(userDefaults: defaults)
        #expect(restored.appearance == .system)
    }

    @Test("New tab destination type changes effective URL")
    func destinationTypeSwitching() {
        let (defaults, suiteName) = createIsolatedDefaults()
        defer { cleanUpDefaults(suiteName) }

        let settings = AppSettings(userDefaults: defaults)
        #expect(settings.newTabURL == "about:blank")

        settings.setNewTabDestinationType(.custom)
        #expect(settings.newTabURL == AppSettings.defaultCustomURL)
        #expect(defaults.string(forKey: AppSettings.newTabTypeKey) == "custom")

        settings.setNewTabDestinationType(.blank)
        #expect(settings.newTabURL == "about:blank")
        #expect(defaults.string(forKey: AppSettings.newTabTypeKey) == "blank")
    }

    @Test("URL validation accepts valid http, https, and about:blank")
    func urlValidationAcceptsValidSchemes() {
        #expect(AppSettings.validate(url: "https://ladybird.org") == .success("https://ladybird.org"))
        #expect(AppSettings.validate(url: "http://localhost:8080") == .success("http://localhost:8080"))
        #expect(AppSettings.validate(url: "about:blank") == .success("about:blank"))
        #expect(AppSettings.validate(url: "  https://example.com/path?arg=1  ") == .success("https://example.com/path?arg=1"))
    }

    @Test("URL validation rejects empty, unsupported, or dangerous schemes")
    func urlValidationRejectsInvalidSchemes() {
        #expect(AppSettings.validate(url: "") == .failure(.empty))
        #expect(AppSettings.validate(url: "   ") == .failure(.empty))
        #expect(AppSettings.validate(url: "javascript:alert(1)") == .failure(.unsupportedScheme("javascript")))
        #expect(AppSettings.validate(url: "file:///etc/passwd") == .failure(.unsupportedScheme("file")))
        #expect(AppSettings.validate(url: "data:text/html,test") == .failure(.unsupportedScheme("data")))
        #expect(AppSettings.validate(url: "ftp://files.example.com") == .failure(.unsupportedScheme("ftp")))
        #expect(AppSettings.validate(url: "not a url") == .failure(.invalidURL))
        #expect(AppSettings.validate(url: "https://") == .failure(.missingHost))
    }

    @Test("Invalid custom URL commit preserves prior valid value and does not persist")
    func invalidCommitPreservesPriorValue() {
        let (defaults, suiteName) = createIsolatedDefaults()
        defer { cleanUpDefaults(suiteName) }

        let settings = AppSettings(userDefaults: defaults)

        let commitResult = settings.commitCustomNewTabURL("https://valid-target.org")
        #expect(commitResult == .success("https://valid-target.org"))
        #expect(settings.customNewTabURL == "https://valid-target.org")
        #expect(defaults.string(forKey: AppSettings.newTabCustomURLKey) == "https://valid-target.org")

        // Attempting to commit an invalid URL should fail and leave the prior valid URL unchanged
        let failedResult = settings.commitCustomNewTabURL("javascript:exploit()")
        #expect(failedResult == .failure(.unsupportedScheme("javascript")))
        #expect(settings.customNewTabURL == "https://valid-target.org")
        #expect(defaults.string(forKey: AppSettings.newTabCustomURLKey) == "https://valid-target.org")

        let emptyResult = settings.commitCustomNewTabURL("   ")
        #expect(emptyResult == .failure(.empty))
        #expect(settings.customNewTabURL == "https://valid-target.org")
        #expect(defaults.string(forKey: AppSettings.newTabCustomURLKey) == "https://valid-target.org")
    }

    @Test("Corrupted or unknown stored values safely fall back to defaults")
    func corruptedValuesFallback() {
        let (defaults, suiteName) = createIsolatedDefaults()
        defer { cleanUpDefaults(suiteName) }

        // Populate corrupt/malicious keys directly into storage
        defaults.set("neon-glitch-appearance", forKey: AppSettings.appearanceKey)
        defaults.set("floating-tabs-type", forKey: AppSettings.newTabTypeKey)
        defaults.set("javascript:corrupted()", forKey: AppSettings.newTabCustomURLKey)

        let settings = AppSettings(userDefaults: defaults)
        #expect(settings.appearance == .system)
        #expect(settings.newTabDestinationType == .blank)
        #expect(settings.customNewTabURL == AppSettings.defaultCustomURL)
        #expect(settings.newTabURL == "about:blank")
    }
}
