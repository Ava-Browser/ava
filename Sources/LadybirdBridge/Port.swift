/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Thin Swift wrappers over the C ABI. No AppKit, no SwiftUI: this target is testable with no window and no engine.
 */

import CLadybirdPort
import CoreFoundation
import Foundation
import IOSurface

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

    /// The `void*` crossed the ABI as a bare handle, so this cast is the one place it becomes a CF type — S1 keeps it
    /// in Bridge so the upward layers never spell `Unmanaged`.
    ///
    /// Borrowed, not owned: the shim hands out a reference it still owns, and a frame swap reclaims it. Assigning this
    /// to `CALayer.contents` on the same call stack is what retains it (S5).
    public var ref: IOSurfaceRef {
        Unmanaged<IOSurfaceRef>.fromOpaque(iosurface).takeUnretainedValue()
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

    /// Destroys one tab's engine page. Stop presenting its surface first — see the header's note on ordering.
    public func destroyTab(_ tab: UInt64) {
        guard let handle else { return }
        LbTabDestroy(handle, tab)
    }

    public func load(_ url: String, in tab: UInt64) {
        guard let handle else { return }
        let normalized = PortApp.normalizedURL(url)
        normalized.withCString { LbTabLoad(handle, tab, $0, normalized.utf8.count) }
    }

    /// Session history. `delta` is -1 for back, +1 for forward; anything else is treated as forward, matching the ABI.
    public enum HistoryDirection {
        case back
        case forward

        var delta: Int32 { self == .back ? -1 : 1 }
    }

    public func traverseHistory(_ direction: HistoryDirection, in tab: UInt64) {
        guard let handle else { return }
        LbTabTraverseHistory(handle, tab, direction.delta)
    }

    /// Whether the engine currently has anywhere to go in that direction. Reads the engine's own navigation actions, so
    /// this is the source of truth for enabling the button rather than an approximation from history depth.
    public func canTraverseHistory(_ direction: HistoryDirection, in tab: UInt64) -> Bool {
        guard let handle else { return false }
        return LbTabCanTraverseHistory(handle, tab, direction.delta) != 0
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

    // MARK: - Input

    /// Positions are CSS pixels relative to the tab's top-left; the shim scales them.
    ///
    /// `button` is the button this event concerns, `buttons` every button held during it — a mouse-up carries the set
    /// still held, which is why they are separate.
    public func sendMouse(
        in tab: UInt64,
        type: PortMouseEventType,
        x: Double,
        y: Double,
        button: PortMouseButton = .none,
        buttons: PortMouseButton = .none,
        clickCount: Int32 = 0,
        wheelDeltaY: Double = 0
    ) {
        guard let handle else { return }
        LbTabSendMouse(
            handle, tab, type.cValue, x, y,
            button.cValue, buttons.cValue, clickCount, wheelDeltaY
        )
    }

    /// One key transition. `key` is a Web `KeyCode` ordinal, or `PortKey.invalid` when only text is known.
    ///
    /// The engine dispatches keys **asynchronously**, through the compositor: returning from this means the event was
    /// queued, not that the page handled it. Nothing should read page state until a later pump and a frame (Traps.md).
    public func sendKey(in tab: UInt64, key: Int32 = 0, codePoint: UInt32 = 0, modifiers: UInt32 = 0, isKeyDown: Bool) {
        guard let handle else { return }
        LbTabSendKey(handle, tab, key, codePoint, modifiers, isKeyDown ? 1 : 0)
    }

    /// Types `text` as text. The shim fills the fields a partial `Web::KeyEvent` would silently omit.
    public func typeText(_ text: String, in tab: UInt64) {
        guard let handle else { return }
        text.withCString { LbTabTypeText(handle, tab, $0, text.utf8.count) }
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

/// Swift-side mirror of `LbMouseButton`, so callers never spell the C enum.
public struct PortMouseButton: OptionSet, Sendable {
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    public static let none = PortMouseButton([])
    public static let primary = PortMouseButton(rawValue: 1)
    public static let secondary = PortMouseButton(rawValue: 2)
    public static let middle = PortMouseButton(rawValue: 4)

    var cValue: LbMouseButton { LbMouseButton(UInt32(rawValue)) }
}

public enum PortMouseEventType: Sendable {
    case down
    case up
    case move
    case wheel

    var cValue: LbMouseEventType {
        switch self {
        case .down: LbMouseEventDown
        case .up: LbMouseEventUp
        case .move: LbMouseEventMove
        case .wheel: LbMouseEventWheel
        }
    }
}

/// Ordinals into Web's `KeyCode` enum, limited to the keys a browser chrome needs.
///
/// The header deliberately takes a raw `int32` rather than an enum of its own, because Web's enum is large and moves on
/// upstream syncs (R4: no enum widening without a version bump). This mirrors the few values the UI actually sends.
public enum PortKey {
    /// `Web::UIEvents::KeyCode::Key_Invalid`.
    public static let invalid: Int32 = 0

    // Web's `KeyCode` ordinals are the legacy character codes, not a dense 0..n sequence, so these are the values from
    // Libraries/LibWebCommon/UIEvents/KeyCode.h rather than a guess. Only the non-text keys are mirrored: a text key
    // crosses as `code_point` with `invalid` as the key, which is what the engine reads anyway.
    public static let backspace: Int32 = 0x08
    public static let tab: Int32 = 0x09
    public static let enter: Int32 = 0x0D
    public static let escape: Int32 = 0x1B
    public static let pageUp: Int32 = 0x21
    public static let pageDown: Int32 = 0x22
    public static let left: Int32 = 0x25
    public static let up: Int32 = 0x26
    public static let right: Int32 = 0x27
    public static let down: Int32 = 0x28
    public static let delete: Int32 = 0x2E

    // Modifier bitmask, matching Web::UIEvents::KeyModifier. On macOS `Mod_PlatformCtrl` is `Mod_Super`.
    public static let modAlt: UInt32 = 1 << 0
    public static let modCtrl: UInt32 = 1 << 1
    public static let modShift: UInt32 = 1 << 2
    public static let modSuper: UInt32 = 1 << 3
}
