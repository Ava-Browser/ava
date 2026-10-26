/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Shared production state for inline space renaming in the sidebar header.
 */

import Foundation
import LadybirdEngine

@MainActor
struct SpaceRenameState: Sendable {
    var editingWorkspaceID: UUID?
    var draft: String = ""

    var isEditing: Bool {
        editingWorkspaceID != nil
    }

    mutating func begin(for workspace: Workspace) {
        editingWorkspaceID = workspace.id
        draft = workspace.name
    }

    mutating func commit(model: BrowserModel) {
        guard let targetID = editingWorkspaceID else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        // Reset state before mutating model to avoid reentrant blur commits
        editingWorkspaceID = nil
        draft = ""

        // Guard target is still active workspace; cancel if space switched before tab observer fired
        guard model.activeWorkspace?.id == targetID else { return }

        if !trimmed.isEmpty, let live = model.workspaces.first(where: { $0.id == targetID }) {
            _ = model.renameWorkspace(live, name: trimmed)
        }
    }

    mutating func cancel() {
        editingWorkspaceID = nil
        draft = ""
    }

    mutating func handleSpaceSwitch(newActiveID: UUID?) {
        if editingWorkspaceID != nil && editingWorkspaceID != newActiveID {
            cancel()
        }
    }
}
