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

    // The four blocking dialogs. Every one MUST be answered through `PortApp`'s matching `answer*` call: the page's
    // script is stopped until it is, and the stall is inside WebContent, so a host that ignores one looks healthy while
    // the page is wedged. Installing any of these without answering is worse than leaving all of them nil — with no
    // callback the engine answers itself.
    public var onRequestAlert: ((UInt64, String) -> Void)?
    public var onRequestConfirm: ((UInt64, String) -> Void)?
    /// `defaultText` is what the prompt's field starts with.
    public var onRequestPrompt: ((UInt64, String, String) -> Void)?
    /// `accept: true` ALLOWS the navigation. The sense is inverted relative to the name — see the header.
    public var onRequestBeforeUnload: ((UInt64, String) -> Void)?

    public init(
        onReadyToPaint: @escaping (UInt64) -> Void = { _ in },
        onURLChange: @escaping (UInt64, String) -> Void = { _, _ in },
        onLoadFinish: @escaping (UInt64, String) -> Void = { _, _ in },
        onRequestAlert: ((UInt64, String) -> Void)? = nil,
        onRequestConfirm: ((UInt64, String) -> Void)? = nil,
        onRequestPrompt: ((UInt64, String, String) -> Void)? = nil,
        onRequestBeforeUnload: ((UInt64, String) -> Void)? = nil
    ) {
        self.onReadyToPaint = onReadyToPaint
        self.onURLChange = onURLChange
        self.onLoadFinish = onLoadFinish
        self.onRequestAlert = onRequestAlert
        self.onRequestConfirm = onRequestConfirm
        self.onRequestPrompt = onRequestPrompt
        self.onRequestBeforeUnload = onRequestBeforeUnload
    }

    /// Whether all four are installed. The ABI treats a nil callback as "engine answers itself", so the host must
    /// install all four or none; a partial set would auto-answer some dialogs and hang on others.
    public var installsAllDialogs: Bool {
        onRequestAlert != nil && onRequestConfirm != nil && onRequestPrompt != nil && onRequestBeforeUnload != nil
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

        // Dialogs. Installed only when the host supplied all four — a partial set would let the engine auto-answer some
        // and leave the page stopped on the rest, which is the one failure mode worse than absence.
        if callbacks.installsAllDialogs {
            c.on_request_alert = { raw, tab, message, len in
                guard let context = CallbackContext.resolve(raw) else { return }
                let string = decode(message, len)
                MainActor.assumeIsolated { context.callbacks.onRequestAlert?(tab, string) }
            }
            c.on_request_confirm = { raw, tab, message, len in
                guard let context = CallbackContext.resolve(raw) else { return }
                let string = decode(message, len)
                MainActor.assumeIsolated { context.callbacks.onRequestConfirm?(tab, string) }
            }
            c.on_request_prompt = { raw, tab, message, len, defaultText, defaultLen in
                guard let context = CallbackContext.resolve(raw) else { return }
                let text = decode(message, len)
                let initial = decode(defaultText, defaultLen)
                MainActor.assumeIsolated { context.callbacks.onRequestPrompt?(tab, text, initial) }
            }
            c.on_request_before_unload = { raw, tab, source, len in
                guard let context = CallbackContext.resolve(raw) else { return }
                let string = decode(source, len)
                MainActor.assumeIsolated { context.callbacks.onRequestBeforeUnload?(tab, string) }
            }
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

    // MARK: - Dialog answers
    //
    // Each of these answers one pending dialog and is what unblocks the page. Calling one with no dialog pending is a
    // no-op in the shim, so a tab being torn down can be answered and closed without checking first.

    public func answerAlert(in tab: UInt64) {
        guard let handle else { return }
        LbTabAnswerAlert(handle, tab)
    }

    /// `accept: false` declines, which is the safe default.
    public func answerConfirm(in tab: UInt64, accept: Bool) {
        guard let handle else { return }
        LbTabAnswerConfirm(handle, tab, accept ? 1 : 0)
    }

    /// `response: nil` is Cancel. An empty string is "accepted with no text" — a different outcome, kept distinct.
    public func answerPrompt(in tab: UInt64, response: String?) {
        guard let handle else { return }
        guard let response else {
            LbTabAnswerPrompt(handle, tab, nil, 0)
            return
        }
        response.withCString { LbTabAnswerPrompt(handle, tab, $0, response.utf8.count) }
    }

    /// `accept: true` ALLOWS the navigation, not blocks it.
    public func answerBeforeUnload(in tab: UInt64, accept: Bool) {
        guard let handle else { return }
        LbTabAnswerBeforeUnload(handle, tab, accept ? 1 : 0)
    }

    /// Navigates the tab, returning the URL actually navigated to -- which differs from the argument whenever the input
    /// was a search query, so the caller can show what happened in the address bar.
    @discardableResult
    public func load(_ input: String, in tab: UInt64) -> String? {
        guard let handle, let url = PortApp.resolveUserInput(input) else { return nil }
        url.withCString { LbTabLoad(handle, tab, $0, url.utf8.count) }
        return url
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

    /// What the address bar's text means: a URL to navigate to, or a search query turned into one.
    ///
    /// Delegates the decision to the engine. A host cannot classify this correctly alone -- "ladybird.dev" versus
    /// "ladybird browser" needs the public suffix list, and "localhost:8080" parses as a scheme -- and the previous
    /// host-side version simply prefixed `https://`, so any search text became a bogus host and failed to load.
    ///
    /// Returns nil only when the engine can resolve the input as neither a URL nor a search, which happens for a bare
    /// word with no search engine configured. Callers should surface that rather than navigating.
    public nonisolated static func resolveUserInput(_ input: String) -> String? {
        var outURL: UnsafeMutablePointer<CChar>?
        var outLength = 0
        let resolved = input.withCString { cString in
            LbResolveUserInput(cString, input.utf8.count, &outURL, &outLength)
        }
        guard resolved == 1, let outURL else { return nil }
        defer { LbStringFree(outURL) }
        // `outLength` is authoritative: the buffer is not NUL-terminated, because the engine string's bytes are copied
        // verbatim and a length-carrying API should not depend on a sentinel the producer never promised.
        return String(decoding: UnsafeRawBufferPointer(start: outURL, count: outLength), as: UTF8.self)
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
