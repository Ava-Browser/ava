/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Bridges the engine's NSView into SwiftUI. Kept separate so the engine never sees SwiftUI and the view stays the
 * engine target's own type.
 */

import LadybirdEngine
import SwiftUI

public struct WebContentView: NSViewRepresentable {
    public let webView: PortWebView

    public init(webView: PortWebView) {
        self.webView = webView
    }

    public func makeNSView(context: Context) -> PortWebView { webView }

    public func updateNSView(_ nsView: PortWebView, context: Context) {}
}
