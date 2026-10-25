/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Space context menus, rename/icon/theme editors, and space management sheet.
 */

import LadybirdEngine
import SwiftUI

@MainActor
@Observable
final class SpaceActionState {
    enum Sheet: Identifiable {
        case rename(UUID)
        case icon(UUID)
        case theme(UUID)
        case manage

        var id: String {
            switch self {
            case let .rename(id): return "rename-\(id)"
            case let .icon(id): return "icon-\(id)"
            case let .theme(id): return "theme-\(id)"
            case .manage: return "manage"
            }
        }
    }

    var activeSheet: Sheet?
    var pendingDeleteWorkspace: Workspace?

    func rename(_ workspace: Workspace) {
        activeSheet = .rename(workspace.id)
    }

    func changeIcon(_ workspace: Workspace) {
        activeSheet = .icon(workspace.id)
    }

    func editTheme(_ workspace: Workspace) {
        activeSheet = .theme(workspace.id)
    }

    func manageSpaces() {
        activeSheet = .manage
    }

    func requestDelete(_ workspace: Workspace) {
        pendingDeleteWorkspace = workspace
    }
}

// MARK: - SpaceContextMenu

struct SpaceContextMenu: View {
    let workspace: Workspace
    let model: BrowserModel
    let actionState: SpaceActionState

    var body: some View {
        // Group 1: Identity
        Button("Change Space Icon…") { actionState.changeIcon(workspace) }
        Button("Rename Space…") { actionState.rename(workspace) }
        Button("Edit Theme Color…") { actionState.editTheme(workspace) }
        Button("Set Profile") {}.disabled(true)

        Divider()

        // Group 2: Structure
        Button("New Folder") {}.disabled(true)
        Button("Live Folders") {}.disabled(true)

        Divider()

        // Group 3: Sharing
        Button("Share Space…") {}.disabled(true)
        Button("Export “\(workspace.name)” into Folder") {}.disabled(true)

        Divider()

        // Group 4: Management
        Button("Manage Spaces…") { actionState.manageSpaces() }

        Divider()

        // Group 5: Destructive
        Button("Delete Space", role: .destructive) {
            actionState.requestDelete(workspace)
        }
        .disabled(model.workspaces.count <= 1)
    }
}

// MARK: - RenameSpaceSheet

struct RenameSpaceSheet: View {
    let workspaceID: UUID
    let model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var isNameFocused: Bool

    init(workspace: Workspace, model: BrowserModel) {
        self.workspaceID = workspace.id
        self.model = model
        _name = State(initialValue: workspace.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Space")
                .font(.headline)

            TextField("Space Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit(commit)

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 280)
        .onAppear {
            isNameFocused = true
        }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let live = model.workspaceManager.workspaces.first(where: { $0.id == workspaceID }) else {
            dismiss()
            return
        }
        _ = model.renameWorkspace(live, name: trimmed)
        dismiss()
    }
}

// MARK: - ChangeSpaceIconSheet

struct ChangeSpaceIconSheet: View {
    let workspaceID: UUID
    let model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIcon: String
    @State private var customInput: String = ""
    @State private var validationError: String?

    init(workspace: Workspace, model: BrowserModel) {
        self.workspaceID = workspace.id
        self.model = model
        _selectedIcon = State(initialValue: workspace.icon)
    }

    private var currentWorkspace: Workspace? {
        model.workspaceManager.workspaces.first(where: { $0.id == workspaceID })
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Change Space Icon")
                .font(.headline)

            // Preview badge
            if let space = currentWorkspace {
                WorkspaceIconView(icon: selectedIcon.isEmpty ? "circle.grid.2x2.fill" : selectedIcon)
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 52, height: 44)
                    .background {
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color(hex: space.theme.startHex), Color(hex: space.theme.endHex)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    }
                    .accessibilityLabel("Selected icon preview: \(selectedIcon)")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Symbols")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 8), count: 6), spacing: 8) {
                    ForEach(Workspace.standardSymbols, id: \.self) { sym in
                        Button {
                            selectedIcon = sym
                            customInput = ""
                            validationError = nil
                        } label: {
                            Image(systemName: sym)
                                .font(.system(size: 14))
                                .frame(width: 32, height: 32)
                                .background(selectedIcon == sym ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accessibleSymbolName(sym))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Emoji")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 8), count: 6), spacing: 8) {
                    ForEach(Workspace.standardEmojis, id: \.self) { emo in
                        Button {
                            selectedIcon = emo
                            customInput = ""
                            validationError = nil
                        } label: {
                            Text(emo)
                                .font(.system(size: 16))
                                .frame(width: 32, height: 32)
                                .background(selectedIcon == emo ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Emoji \(emo)")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("Custom emoji or symbol", text: $customInput)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: customInput) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            validationError = nil
                        } else if Workspace.isValidIcon(trimmed) {
                            selectedIcon = trimmed
                            validationError = nil
                        } else {
                            validationError = "Enter a valid single emoji or symbol name."
                        }
                    }

                if let validationError {
                    Text(validationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(validationError != nil || !Workspace.isValidIcon(selectedIcon))
            }
        }
        .padding(20)
        .frame(minWidth: 300)
    }

    private func accessibleSymbolName(_ sym: String) -> String {
        sym.replacingOccurrences(of: ".fill", with: "")
            .replacingOccurrences(of: ".", with: " ")
    }

    private func commit() {
        guard validationError == nil, Workspace.isValidIcon(selectedIcon) else { return }
        guard let live = currentWorkspace else {
            dismiss()
            return
        }
        _ = model.updateWorkspaceIcon(live, icon: selectedIcon)
        dismiss()
    }
}

// MARK: - EditSpaceThemeSheet

struct EditSpaceThemeSheet: View {
    let workspaceID: UUID
    let model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var startColor: Color
    @State private var endColor: Color

    init(workspace: Workspace, model: BrowserModel) {
        self.workspaceID = workspace.id
        self.model = model
        _startColor = State(initialValue: Color(hex: workspace.theme.startHex))
        _endColor = State(initialValue: Color(hex: workspace.theme.endHex))
    }

    private var currentWorkspace: Workspace? {
        model.workspaceManager.workspaces.first(where: { $0.id == workspaceID })
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Theme Color")
                .font(.headline)

            // Preview
            if let space = currentWorkspace {
                WorkspaceIconView(icon: space.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 64, height: 50)
                    .background {
                        Capsule()
                            .fill(LinearGradient(
                                colors: [startColor, endColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    }
                    .accessibilityLabel("Theme gradient preview")
            }

            // Presets palette
            VStack(alignment: .leading, spacing: 6) {
                Text("Presets")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(GradientSpec.palette, id: \.self) { spec in
                        Button {
                            startColor = Color(hex: spec.startHex)
                            endColor = Color(hex: spec.endHex)
                        } label: {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color(hex: spec.startHex), Color(hex: spec.endHex)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Theme preset from \(spec.startHex) to \(spec.endHex)")
                    }
                }
            }

            // Native color pickers
            HStack(spacing: 20) {
                ColorPicker("Start", selection: $startColor, supportsOpacity: false)
                    .accessibilityLabel("Start color")
                ColorPicker("End", selection: $endColor, supportsOpacity: false)
                    .accessibilityLabel("End color")
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { commit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 280)
    }

    private func commit() {
        guard let live = currentWorkspace else {
            dismiss()
            return
        }
        let startHex = startColor.toHex()
        let endHex = endColor.toHex()
        _ = model.updateWorkspaceTheme(live, theme: GradientSpec(startHex: startHex, endHex: endHex))
        dismiss()
    }
}

// MARK: - ManageSpacesSheet

struct ManageSpacesSheet: View {
    let model: BrowserModel
    let actionState: SpaceActionState
    @Environment(\.dismiss) private var dismiss

    enum SubSheet: Identifiable {
        case rename(Workspace)
        case icon(Workspace)
        case theme(Workspace)

        var id: String {
            switch self {
            case let .rename(w): return "rename-\(w.id)"
            case let .icon(w): return "icon-\(w.id)"
            case let .theme(w): return "theme-\(w.id)"
            }
        }
    }

    @State private var localSubSheet: SubSheet?
    @State private var localDeleteWorkspace: Workspace?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Manage Spaces")
                    .font(.headline)
                Spacer()
                Button {
                    _ = model.createWorkspace()
                } label: {
                    Label("New Space", systemImage: "plus")
                }
                .accessibilityLabel("Create new space")
            }

            List {
                ForEach(Array(model.workspaces.enumerated()), id: \.element.id) { index, space in
                    HStack(spacing: 10) {
                        Button {
                            model.selectWorkspace(space)
                        } label: {
                            HStack(spacing: 10) {
                                WorkspaceIconView(icon: space.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 26, height: 22)
                                    .background {
                                        Capsule()
                                            .fill(LinearGradient(
                                                colors: [Color(hex: space.theme.startHex), Color(hex: space.theme.endHex)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                    }

                                Text(space.name)
                                    .font(.body)

                                if model.activeWorkspace?.id == space.id {
                                    Text("Active")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary, in: Capsule())
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select space \(space.name)")

                        Spacer()

                        // Move Up / Down
                        Button {
                            model.moveWorkspace(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.plain)
                        .disabled(index == 0)
                        .accessibilityLabel("Move \(space.name) up")
                        .help("Move Up")

                        Button {
                            model.moveWorkspace(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.plain)
                        .disabled(index == model.workspaces.count - 1)
                        .accessibilityLabel("Move \(space.name) down")
                        .help("Move Down")

                        Menu {
                            Button("Rename Space…") { localSubSheet = .rename(space) }
                            Button("Change Space Icon…") { localSubSheet = .icon(space) }
                            Button("Edit Theme Color…") { localSubSheet = .theme(space) }
                            Divider()
                            Button("Delete Space", role: .destructive) {
                                localDeleteWorkspace = space
                            }
                            .disabled(model.workspaces.count <= 1)
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .accessibilityLabel("Edit options for \(space.name)")

                        Button(role: .destructive) {
                            localDeleteWorkspace = space
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .disabled(model.workspaces.count <= 1)
                        .accessibilityLabel("Delete space \(space.name)")
                        .help("Delete Space")
                    }
                    .padding(.vertical, 2)
                }
                .onMove { indices, newOffset in
                    model.moveWorkspace(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .frame(minHeight: 180, maxHeight: 300)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 400)
        .sheet(item: $localSubSheet) { sub in
            switch sub {
            case let .rename(space):
                RenameSpaceSheet(workspace: space, model: model)
            case let .icon(space):
                ChangeSpaceIconSheet(workspace: space, model: model)
            case let .theme(space):
                EditSpaceThemeSheet(workspace: space, model: model)
            }
        }
        .confirmationDialog(
            "Delete “\(localDeleteWorkspace?.name ?? "Space")”? Tabs in this space will close. Essentials will remain.",
            isPresented: Binding(
                get: { localDeleteWorkspace != nil },
                set: { if !$0 { localDeleteWorkspace = nil } }
            ),
            titleVisibility: .visible,
            presenting: localDeleteWorkspace
        ) { space in
            Button("Delete Space", role: .destructive) {
                model.deleteWorkspace(space)
                localDeleteWorkspace = nil
            }
            Button("Cancel", role: .cancel) {
                localDeleteWorkspace = nil
            }
        } message: { _ in
            Text("Tabs in this space will be closed. Global Essentials and other spaces will not be affected.")
        }
    }
}

// MARK: - WorkspaceIconView

struct WorkspaceIconView: View {
    let icon: String

    var body: some View {
        Group {
            if Workspace.isSymbolIcon(icon) {
                Image(systemName: icon)
            } else {
                Text(icon)
            }
        }
    }
}

// MARK: - SpaceActionModifier

struct SpaceActionModifier: ViewModifier {
    let model: BrowserModel
    @Bindable var actionState: SpaceActionState

    func body(content: Content) -> some View {
        content
            .sheet(item: $actionState.activeSheet) { sheet in
                switch sheet {
                case let .rename(id):
                    if let workspace = model.workspaceManager.workspaces.first(where: { $0.id == id }) {
                        RenameSpaceSheet(workspace: workspace, model: model)
                    }
                case let .icon(id):
                    if let workspace = model.workspaceManager.workspaces.first(where: { $0.id == id }) {
                        ChangeSpaceIconSheet(workspace: workspace, model: model)
                    }
                case let .theme(id):
                    if let workspace = model.workspaceManager.workspaces.first(where: { $0.id == id }) {
                        EditSpaceThemeSheet(workspace: workspace, model: model)
                    }
                case .manage:
                    ManageSpacesSheet(model: model, actionState: actionState)
                }
            }
            .confirmationDialog(
                "Delete “\(actionState.pendingDeleteWorkspace?.name ?? "Space")”? Tabs in this space will close. Essentials will remain.",
                isPresented: Binding(
                    get: { actionState.pendingDeleteWorkspace != nil },
                    set: { if !$0 { actionState.pendingDeleteWorkspace = nil } }
                ),
                titleVisibility: .visible,
                presenting: actionState.pendingDeleteWorkspace
            ) { space in
                Button("Delete Space", role: .destructive) {
                    model.deleteWorkspace(space)
                    actionState.pendingDeleteWorkspace = nil
                }
                Button("Cancel", role: .cancel) {
                    actionState.pendingDeleteWorkspace = nil
                }
            } message: { _ in
                Text("Tabs in this space will be closed. Global Essentials and other spaces will not be affected.")
            }
    }
}

// MARK: - Color Hex Extensions

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x808080
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255,
            opacity: 1
        )
    }

    func toHex() -> String {
        let resolved = self.resolve(in: EnvironmentValues())
        let r = Int(round(resolved.red * 255))
        let g = Int(round(resolved.green * 255))
        let b = Int(round(resolved.blue * 255))
        return String(format: "#%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }
}
