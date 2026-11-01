/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Lets the Settings window act on the browser without owning one.
 */

import AppKit
import Foundation

/// Routes a command from the Settings window to the browser window that is actually running an engine.
///
/// Settings must never create a `BrowserModel`: a second one would start a second `PortApp`, which the engine refuses
/// (`BrowserModel.start` guards on `processApp`). So the entry points that need to open a page register the model they
/// already have, and Settings calls through here. The reference is weak — a closed window unregisters itself by
/// deallocating, and a command with no live window does nothing.
@MainActor
public final class BrowserCommandRouter {
    public static let shared = BrowserCommandRouter()

    private weak var activeModel: BrowserModel?

    public init() {}

    /// Called by each window as it starts. The most recent window wins, which is the one the user was last looking at.
    public func register(_ model: BrowserModel) {
        activeModel = model
    }

    /// Opens the engine's own settings page, which owns search, privacy, network and blocking.
    ///
    /// Opens in a new tab rather than navigating the current one: the user opened Settings from the app menu, so the
    /// page they were reading is not theirs to discard.
    @discardableResult
    public func openEngineSettings() -> BrowserTab? {
        activeModel?.openTab(url: Self.engineSettingsURL)
    }

    public static let engineSettingsURL = "about:settings"

    /// Opens the engine's settings page and dismisses the Settings window that asked for it.
    ///
    /// The close lives here because it needs AppKit, and `LadybirdUI` is deliberately not allowed to touch it.
    public func openEngineSettingsAndDismissSettingsWindow() {
        openEngineSettings()
        // `keyWindow` is the Settings window: it is modal-free but key while the button is pressed. Guarded by class name
        // so a future non-Settings window cannot be closed by a stale call.
        if NSApp.keyWindow?.className.contains("Settings") == true {
            NSApp.keyWindow?.performClose(nil)
        }
    }
}
