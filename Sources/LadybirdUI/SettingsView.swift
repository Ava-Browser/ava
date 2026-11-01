/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The native Settings window: app-owned preferences only. Engine-owned settings (search, privacy, network, blocking,
 * page content) live on the engine's own about:settings page, reachable from General.
 */

import LadybirdEngine
import SwiftUI

public enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general
    case appearance
    case browsing
    case about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .browsing: "Browsing"
        case .about: "About"
        }
    }

    public var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .browsing: "sidebar.left"
        case .about: "info.circle"
        }
    }
}

public struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @AppStorage("org.ladybird.settings.selectedPane") private var selectedPane: String = SettingsPane.general.rawValue

    public init() {}

    public var body: some View {
        // A plain HStack, deliberately NOT a NavigationSplitView. A split view injects a sidebar-collapse toggle into
        // the titlebar and makes the pane list collapsible; in Settings that toggle is a stray control that can hide
        // the only navigation there is, and `toolbar(removing: .sidebarToggle)` did not reliably remove it. Building
        // the two columns by hand gives the same System Settings look with nothing to collapse and no toolbar at all.
        HStack(spacing: 0) {
            List(SettingsPane.allCases, selection: Binding(
                get: { SettingsPane(rawValue: selectedPane) ?? .general },
                set: { selectedPane = $0.rawValue }
            )) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(width: 200)

            Divider()

            // No pane repeats its own name as a heading — the selected sidebar row already says which pane this is,
            // and a second copy is the kind of redundancy that makes a settings window feel busy.
            Group {
                switch SettingsPane(rawValue: selectedPane) ?? .general {
                case .general: GeneralSettingsPane(settings: settings)
                case .appearance: AppearanceSettingsPane(settings: settings)
                case .browsing: BrowsingSettingsPane()
                case .about: AboutSettingsPane()
                }
            }
            // A real minimum instead of a fixed size, so a validation message or a larger text size can grow the
            // window rather than clip. `Form` scrolls itself; a ScrollView around it would fight the grouped layout.
            .frame(minWidth: 440, maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
        }
        // A minimum, not a fixed size: the window is resizable and Form scrolls. The starting size is a separate
        // concern and lives on the scene (`Settings.defaultSize`); pinning it here would forbid the user to resize.
        .frame(minWidth: 640, minHeight: 380)
    }
}

// MARK: - General Pane

struct GeneralSettingsPane: View {
    let settings: AppSettings
    @State private var customURLInput: String = ""
    @State private var errorMessage: String?

    var body: some View {
        // `grouped` is the System Settings layout: inset rows on the window background, no drawn boxes. Building the
        // grouping from GroupBox instead reads as a web form dropped into a window.
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
                .pickerStyle(.segmented)

                if settings.newTabDestinationType == .custom {
                    LabeledContent("Address") {
                        HStack(spacing: 8) {
                            TextField("URL", text: $customURLInput)
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
                                .onSubmit { commitCustomURL() }
                                .accessibilityLabel("Custom New Tab URL")

                            Button("Save") { commitCustomURL() }
                                .disabled(customURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                    == settings.customNewTabURL)
                        }
                    }

                    // Inline, under the field it belongs to, not as a modal — Apple's "validate inline, not on submit".
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Validation Error: \(errorMessage)")
                    } else {
                        Text("Supports http://, https://, or about:blank.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("New tabs")
            }

            // The rest of the settings surface belongs to the engine. Linking out keeps one copy of each value, which
            // is the point: a native mirror could disagree with what the engine actually uses.
            Section {
                LabeledContent {
                    Button("Open about:settings…") {
                        BrowserCommandRouter.shared.openEngineSettingsAndDismissSettingsWindow()
                    }
                    .accessibilityLabel("Open engine settings page")
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("More settings")
                        Text("Search provider, privacy, website data, network and content blocking are owned by the web "
                            + "engine.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                Picker("Appearance:", selection: Binding(
                    get: { settings.appearance },
                    set: { settings.setAppearance($0) }
                )) {
                    ForEach(AppAppearance.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("App")
            } footer: {
                Text("Applies to the browser window, sidebar, settings chrome, and the pages you have open.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Browsing Pane

struct BrowsingSettingsPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Sidebar width") {
                    Text("Remembered automatically")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Sidebar")
            } footer: {
                Text("Drag the sidebar edge to resize it; the width is kept for next time.")
            }

            // Reserved for behaviour that needs engine support Ava does not have yet. Disabled on purpose: the layout
            // is designed now, and each control lights up when the capability lands. Kept to the controls that are
            // actually planned rather than a wall of dead switches.
            Section {
                Toggle("Restore previous windows and tabs at launch", isOn: .constant(false))
                    .disabled(true)
                Toggle("Close the window when the last tab closes", isOn: .constant(true))
                    .disabled(true)
                LabeledContent("Default page zoom") {
                    Picker("", selection: .constant(1.0)) {
                        Text("100%").tag(1.0)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                    .disabled(true)
                }
            } header: {
                Text("Behaviour")
            } footer: {
                Text("These are not available yet.")
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
        // Not a Form. About has no rows to lay out, and a grouped Section around a single centered block stretches
        // its grey background across the whole pane, which reads as a huge empty card rather than an identity panel.
        VStack(spacing: 6) {
            if let icon = AppIcon.image {
                // The asset carries its own transparent margin (the 824-in-1024 macOS icon grid), so the visible
                // plate is about 80% of this.
                icon
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 128, height: 128)
                    .accessibilityHidden(true)
                    .padding(.bottom, 6)
            }
            Text("Ava")
                .font(.title2.bold())
            Text(versionString)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text("Powered by the Ladybird web engine.")
                Link("ladybird.org", destination: URL(string: "https://ladybird.org")!)
            }
            .font(.subheadline)
            .padding(.top, 2)
        }
        // Centred in the pane, which is the macOS About convention and removes the top-anchored dead space.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
