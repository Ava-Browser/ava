/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The bundle icon, exposed so `LadybirdUI` shows it without importing AppKit.
 */

import AppKit
import SwiftUI

@MainActor
public enum AppIcon {
    /// `nil` when there is no running application to ask, as in a headless test process.
    public static var image: Image? {
        guard let icon = NSApp?.applicationIconImage else { return nil }
        return Image(nsImage: icon)
    }
}
