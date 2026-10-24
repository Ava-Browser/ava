/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Thin Swift wrappers over the C ABI. No AppKit, no SwiftUI: this target is testable with no window and no engine.
 */

import CLadybirdPort
import Foundation

/// A frame the engine has published.
///
/// `iosurface` is borrowed and is only valid until the next paint, so hand it to `CALayer` on the same call stack
/// rather than storing it (R1, R6). The painted size can be smaller than the surface; crop with `contentsRect`.
public struct PortSurface {
    public let iosurface: UnsafeMutableRawPointer
    public let paintedWidth: Int
    public let paintedHeight: Int
    public let surfaceWidth: Int
    public let surfaceHeight: Int

    public init(iosurface: UnsafeMutableRawPointer, paintedWidth: Int, paintedHeight: Int, surfaceWidth: Int, surfaceHeight: Int) {
        self.iosurface = iosurface
        self.paintedWidth = paintedWidth
        self.paintedHeight = paintedHeight
        self.surfaceWidth = surfaceWidth
        self.surfaceHeight = surfaceHeight
    }
}

/// Swift-side shape of `LbCallbacks`. Every closure is invoked inside the pump, on the main thread.
public struct PortCallbacks {
    public var onReadyToPaint: (UInt64) -> Void
    public var onURLChange: (UInt64, String) -> Void
    public var onLoadFinish: (UInt64, String) -> Void

    public init(
        onReadyToPaint: @escaping (UInt64) -> Void = { _ in },
        onURLChange: @escaping (UInt64, String) -> Void = { _, _ in },
        onLoadFinish: @escaping (UInt64, String) -> Void = { _, _ in }
    ) {
        self.onReadyToPaint = onReadyToPaint
        self.onURLChange = onURLChange
        self.onLoadFinish = onLoadFinish
    }
}

/// Decodes the `url`/`len` pair the ABI hands across. The bytes are valid for that call only.
private func decode(_ url: UnsafePointer<CChar>?, _ len: Int) -> String {
    guard let url, len > 0 else { return "" }
    return String(decoding: UnsafeRawBufferPointer(start: url, count: len), as: UTF8.self)
}

/// The single `Unmanaged<>` context for one app: the C trampolines carry this, never an object graph.
private final class CallbackContext: @unchecked Sendable {
    let callbacks: PortCallbacks

    init(_ callbacks: PortCallbacks) {
        self.callbacks = callbacks
    }

    static func resolve(_ raw: UnsafeMutableRawPointer?) -> CallbackContext? {
        guard let raw else { return nil }
        return Unmanaged<CallbackContext>.fromOpaque(raw).takeUnretainedValue()
    }
}

@MainActor
public final class PortApp {
    private var handle: OpaquePointer?
    private let context: CallbackContext

    public init?(
        argv0: String = CommandLine.arguments.first ?? "LadybirdMac",
        callbacks: PortCallbacks
    ) {
        let context = CallbackContext(callbacks)
        self.context = context

        var c = LbCallbacks()
        c.context = Unmanaged.passUnretained(context).toOpaque()
        // R5: there is no pump thread, so `assumeIsolated` is the runtime assert on every entry point. It traps on a
        // real violation rather than hopping, because there is nowhere to hop to. Everything crossing into the
        // closure is Sendable first (the context is @unchecked Sendable, the URL is decoded outside).
        c.on_ready_to_paint = { raw, tab in
            guard let context = CallbackContext.resolve(raw) else { return }
            MainActor.assumeIsolated { context.callbacks.onReadyToPaint(tab) }
        }
        c.on_url_change = { raw, tab, url, len in
            guard let context = CallbackContext.resolve(raw) else { return }
            let string = decode(url, len)
            MainActor.assumeIsolated { context.callbacks.onURLChange(tab, string) }
        }
        c.on_load_finish = { raw, tab, url, len in
            guard let context = CallbackContext.resolve(raw) else { return }
            let string = decode(url, len)
            MainActor.assumeIsolated { context.callbacks.onLoadFinish(tab, string) }
        }

        guard let handle = argv0.withCString({ LbAppCreate($0, &c) }) else { return nil }
        self.handle = handle
    }

    /// The header's own pump driver: a `CFRunLoopTimer` in `kCFRunLoopCommonModes`, so a live resize or a held menu
    /// cannot starve the engine (R8). The host keeps its run loop.
    public func startPump(interval: Double = 0.002) {
        guard let handle else { return }
        LbAppStartPump(handle, interval)
    }

    public func stopPump() {
        guard let handle else { return }
        LbAppStopPump(handle)
    }

    /// Main thread, after `stopPump` (R5).
    public func destroy() {
        guard let handle else { return }
        LbAppStopPump(handle)
        LbAppDestroy(handle)
        self.handle = nil
    }

    public func createTab() -> UInt64 {
        guard let handle else { return 0 }
        return LbTabCreate(handle)
    }

    public func load(_ url: String, in tab: UInt64) {
        guard let handle else { return }
        let normalized = PortApp.normalizedURL(url)
        normalized.withCString { LbTabLoad(handle, tab, $0, normalized.utf8.count) }
    }

    public func surface(in tab: UInt64) -> PortSurface? {
        guard let handle else { return nil }
        var raw = LbSurface()
        guard LbTabGetSurface(handle, tab, &raw) == 1, let iosurface = raw.iosurface else { return nil }
        return PortSurface(
            iosurface: iosurface,
            paintedWidth: Int(raw.painted_width),
            paintedHeight: Int(raw.painted_height),
            surfaceWidth: Int(raw.surface_width),
            surfaceHeight: Int(raw.surface_height)
        )
    }

    /// `width`/`height` are CSS pixels; the engine multiplies by `scale` itself (Traps.md, headless viewport).
    public func setViewport(in tab: UInt64, width: Int32, height: Int32, scale: Double) {
        guard let handle else { return }
        LbTabSetViewport(handle, tab, width, height, scale)
    }

    /// What the address bar's text actually means. `LbTabLoad` parses with `URL::Parser::basic_parse`, which reads
    /// `localhost:8080` as a scheme, so a bare host needs `https://` added before it crosses the ABI.
    public nonisolated static func normalizedURL(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let knownSchemes: Set<String> = ["http", "https", "about", "data", "file", "blob", "javascript", "mailto", "view-source"]
        if let colon = trimmed.firstIndex(of: ":") {
            let scheme = trimmed[trimmed.startIndex..<colon].lowercased()
            if knownSchemes.contains(scheme) { return trimmed }
        }
        return "https://" + trimmed
    }
}
