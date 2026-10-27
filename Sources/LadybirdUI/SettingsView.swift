/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Arc-inspired native macOS Settings window.
 */

import AppKit
import LadybirdEngine
import SwiftUI

public enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general
    case appearance
    case about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .about: "About"
        }
    }

    public var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .about: "info.circle"
        }
    }
}

public struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @AppStorage("org.ladybird.settings.selectedPane") private var selectedPane: String = SettingsPane.general.rawValue

    public init() {}

    public var body: some View {
        TabView(selection: $selectedPane) {
            GeneralSettingsPane(settings: settings)
                .tabItem {
                    Label(SettingsPane.general.title, systemImage: SettingsPane.general.systemImage)
                }
                .tag(SettingsPane.general.rawValue)

            AppearanceSettingsPane(settings: settings)
                .tabItem {
                    Label(SettingsPane.appearance.title, systemImage: SettingsPane.appearance.systemImage)
                }
                .tag(SettingsPane.appearance.rawValue)

            AboutSettingsPane()
                .tabItem {
                    Label(SettingsPane.about.title, systemImage: SettingsPane.about.systemImage)
                }
                .tag(SettingsPane.about.rawValue)
        }
        .frame(width: 480, height: 280)
        .padding(20)
    }
}

// MARK: - General Pane

struct GeneralSettingsPane: View {
    let settings: AppSettings
    @State private var customURLInput: String = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("New tabs open with:", selection: Binding(
                    get: { settings.newTabDestinationType },
                    set: { newType in
                        settings.setNewTabDestinationType(newType)
                        if newType == .custom && customURLInput.isEmpty {
                            customURLInput = settings.customNewTabURL
                        }
                    }
                )) {
                    ForEach(NewTabDestinationType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.radioGroup)

                if settings.newTabDestinationType == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            TextField("URL", text: $customURLInput)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { commitCustomURL() }
                                .accessibilityLabel("Custom New Tab URL")

                            Button("Save") {
                                commitCustomURL()
                            }
                            .disabled(customURLInput.trimmingCharacters(in: .whitespacesAndNewlines) == settings.customNewTabURL)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .accessibilityLabel("Validation Error: \(errorMessage)")
                        }

                        Text("Supports http://, https://, or about:blank.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 20)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            customURLInput = settings.customNewTabURL
            errorMessage = nil
        }
    }

    private func commitCustomURL() {
        switch settings.commitCustomNewTabURL(customURLInput) {
        case .success(let saved):
            customURLInput = saved
            errorMessage = nil
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Appearance Pane

struct AppearanceSettingsPane: View {
    let settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("App appearance:", selection: Binding(
                    get: { settings.appearance },
                    set: { settings.setAppearance($0) }
                )) {
                    ForEach(AppAppearance.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("Applies to the browser window, sidebar, and settings chrome. Website content theme is controlled by the engine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About Pane

struct AboutSettingsPane: View {
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "dev"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            Text("Ava")
                .font(.title2.bold())

            Text(versionString)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Powered by the Ladybird web engine.")
                .font(.subheadline)

            Link("ladybird.org", destination: URL(string: "https://ladybird.org")!)
                .font(.footnote)

            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("• Mac frontend: BSD 2-Clause License")
                Text("• Ladybird engine: BSD 2-Clause License")
                Text("• Third-party dependencies: Licensed under their respective open-source licenses (BSD, Apache 2.0, MIT, zlib, and others). See repository for complete notices.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }
}
