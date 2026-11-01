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
    public var onTitleChange: ((UInt64, String) -> Void)?
    public var onLoadingStateChange: ((UInt64, Bool) -> Void)?
    public var onFaviconChange: ((UInt64, Data?, String?) -> Void)?

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
        onTitleChange: ((UInt64, String) -> Void)? = nil,
        onLoadingStateChange: ((UInt64, Bool) -> Void)? = nil,
        onFaviconChange: ((UInt64, Data?, String?) -> Void)? = nil,
        onRequestAlert: ((UInt64, String) -> Void)? = nil,
        onRequestConfirm: ((UInt64, String) -> Void)? = nil,
        onRequestPrompt: ((UInt64, String, String) -> Void)? = nil,
        onRequestBeforeUnload: ((UInt64, String) -> Void)? = nil
    ) {
        self.onReadyToPaint = onReadyToPaint
        self.onURLChange = onURLChange
        self.onLoadFinish = onLoadFinish
        self.onTitleChange = onTitleChange
        self.onLoadingStateChange = onLoadingStateChange
        self.onFaviconChange = onFaviconChange
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

/// Page-created and page-closed tabs.
public struct PortPageCallbacks {
    /// The engine has already created and registered `newTab`; the host must adopt that id rather than creating another.
    public var onNewTab: ((UInt64, UInt64, Bool, Bool) -> Void)?
    /// The engine has already destroyed `tab`; the host must remove its UI state without calling destroy again.
    public var onTabClosed: ((UInt64) -> Void)?

    public init() {}
}

public struct PortSelectOption: Equatable, Sendable {
    public let id: UInt32
    public let label: String
    public let enabled: Bool
    public let selected: Bool
}

public enum PortSelectItem: Equatable, Sendable {
    case option(PortSelectOption)
    case separator
    case group(label: String, options: [PortSelectOption])
}

public struct PortPickerCallbacks {
    public var onSelectDropdown: ((UInt64, UInt64, Int32, Int32, Int32, [PortSelectItem]) -> Void)?

    public init() {}
}

/// Hover feedback: everything a page asks for that is not a click.
///
/// `onCursorChange` is what makes the pointer a pointing hand over a link and an I-beam over text. Without it the page's
/// cursor never reaches AppKit and every element looks inert, however correctly it is styled.
public struct PortUICallbacks {
    public var onCursorChange: ((UInt64, PortCursor) -> Void)?
    public var onLinkHover: ((UInt64, String) -> Void)?
    public var onLinkUnhover: ((UInt64) -> Void)?
    public var onTooltipOverride: ((UInt64, Int32, Int32, String) -> Void)?
    public var onStopTooltipOverride: ((UInt64) -> Void)?
    public var onEnterTooltipArea: ((UInt64, String) -> Void)?
    public var onLeaveTooltipArea: ((UInt64) -> Void)?

    public init() {}

    var hasCursorCallback: Bool { onCursorChange != nil }
}

/// One cursor the page asked for: either a standard system cursor, or an image with a hotspot to tip it at.
public enum PortCursor {
    /// A `Gfx::StandardCursor` ordinal. `PortStandardCursor` names the ones a browser actually needs.
    case standard(Int32)
    /// PNG-encoded image plus the hotspot, in image pixels from its top-left.
    case image(Data, hotspotX: Int32, hotspotY: Int32)
}

/// The `Gfx::StandardCursor` ordinals the ABI passes through. The engine's own numbering, so these are the values from
/// `Libraries/LibGfx/Cursor.h` rather than a renumbering.
public enum PortStandardCursor {
    public static let hidden: Int32 = 1
    public static let arrow: Int32 = 2
    public static let crosshair: Int32 = 3
    public static let iBeam: Int32 = 4
    public static let resizeHorizontal: Int32 = 5
    public static let resizeVertical: Int32 = 6
    public static let resizeDiagonalTLBR: Int32 = 7
    public static let resizeDiagonalBLTR: Int32 = 8
    public static let resizeColumn: Int32 = 9
    public static let resizeRow: Int32 = 10
    public static let hand: Int32 = 11
    public static let help: Int32 = 12
    public static let openHand: Int32 = 13
    public static let drag: Int32 = 14
    public static let dragCopy: Int32 = 15
    public static let move: Int32 = 16
    public static let wait: Int32 = 17
    public static let disallowed: Int32 = 18
    public static let eyedropper: Int32 = 19
    public static let zoom: Int32 = 20
}

/// Decodes the `url`/`len` pair the ABI hands across. The bytes are valid for that call only.
private func decode(_ url: UnsafePointer<CChar>?, _ len: Int) -> String {
    guard let url, len > 0 else { return "" }
    return String(decoding: UnsafeRawBufferPointer(start: url, count: len), as: UTF8.self)
}

func decodeSelectItems(_ bytes: UnsafePointer<CChar>?, _ length: Int) -> [PortSelectItem]? {
    guard let bytes, length > 0,
          let array = try? JSONSerialization.jsonObject(with: Data(bytes: bytes, count: length)) as? [[String: Any]]
    else { return nil }

    func option(_ object: [String: Any]) -> PortSelectOption? {
        guard object["type"] as? String == "option",
              let number = object["id"] as? NSNumber,
              number.uint64Value <= UInt32.max,
              let label = object["label"] as? String,
              let enabled = object["enabled"] as? Bool,
              let selected = object["selected"] as? Bool
        else { return nil }
        return PortSelectOption(id: number.uint32Value, label: label, enabled: enabled, selected: selected)
    }

    var items: [PortSelectItem] = []
    for object in array {
        switch object["type"] as? String {
        case "option":
            guard let value = option(object) else { return nil }
            items.append(.option(value))
        case "separator":
            items.append(.separator)
        case "group":
            guard let label = object["label"] as? String,
                  let children = object["items"] as? [[String: Any]]
            else { return nil }
            let options = children.compactMap(option)
            guard options.count == children.count else { return nil }
            items.append(.group(label: label, options: options))
        default:
            return nil
        }
    }
    return items
}

/// The single `Unmanaged<>` context for one app: the C trampolines carry this, never an object graph.
private final class CallbackContext: @unchecked Sendable {
    let callbacks: PortCallbacks
    /// The hover group. Held here rather than in a second context so the C trampolines keep carrying exactly one pointer
    /// (S1: the `Unmanaged` box is created once, per app).
    let ui: PortUICallbacks
    let page: PortPageCallbacks
    let picker: PortPickerCallbacks

    init(_ callbacks: PortCallbacks, ui: PortUICallbacks, page: PortPageCallbacks, picker: PortPickerCallbacks) {
        self.callbacks = callbacks
        self.ui = ui
        self.page = page
        self.picker = picker
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

    /// The installed UI group, kept so the registration can report whether the dylib accepted it. A refusal costs the
    /// feature and nothing else, which is the whole point of the size-tagged groups.
    private var uiCallbacks: PortUICallbacks

    /// Whether this dylib accepted the UI group. False means it predates the group, or the struct was refused.
    public private(set) var uiCallbacksInstalled = false
    public private(set) var pageCallbacksInstalled = false

    public init?(
        argv0: String = CommandLine.arguments.first ?? "Ava",
        callbacks: PortCallbacks,
        ui: PortUICallbacks = PortUICallbacks(),
        page: PortPageCallbacks = PortPageCallbacks(),
        picker: PortPickerCallbacks = PortPickerCallbacks()
    ) {
        let context = CallbackContext(callbacks, ui: ui, page: page, picker: picker)
        self.context = context
        self.uiCallbacks = ui

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
        c.on_title_change = { raw, tab, title, len in
            guard let context = CallbackContext.resolve(raw) else { return }
            let string = decode(title, len)
            MainActor.assumeIsolated { context.callbacks.onTitleChange?(tab, string) }
        }
        c.on_loading_state_change = { raw, tab, isLoading in
            guard let context = CallbackContext.resolve(raw) else { return }
            let loading = isLoading != 0
            MainActor.assumeIsolated { context.callbacks.onLoadingStateChange?(tab, loading) }
        }
        c.on_favicon_change = { raw, tab, data, len, hash, hashLen in
            guard let context = CallbackContext.resolve(raw) else { return }
            let iconData: Data? = (data != nil && len > 0) ? Data(bytes: data!, count: len) : nil
            let hashString: String? = (hash != nil && hashLen > 0) ? decode(hash, hashLen) : nil
            MainActor.assumeIsolated { context.callbacks.onFaviconChange?(tab, iconData, hashString) }
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

        installUICallbacks()
        installPageCallbacks()
        installPickerCallbacks()
    }

    private func installPickerCallbacks() {
        guard let handle else { return }

        var group = LbPickerCallbacks()
        group.struct_size = UInt32(MemoryLayout<LbPickerCallbacks>.size)
        group.version = UInt32(LB_CALLBACKS_VERSION)
        if context.picker.onSelectDropdown != nil {
            group.on_request_select_dropdown = { raw, tab, requestID, x, y, minimumWidth, json, length in
                guard let context = CallbackContext.resolve(raw) else { return }
                let items = decodeSelectItems(json, length) ?? []
                MainActor.assumeIsolated {
                    context.picker.onSelectDropdown?(tab, requestID, x, y, minimumWidth, items)
                }
            }
        }
        _ = LbAppSetPickerCallbacks(handle, &group)
    }

    private func installPageCallbacks() {
        guard let handle else { return }

        var group = LbPageCallbacks()
        group.struct_size = UInt32(MemoryLayout<LbPageCallbacks>.size)
        group.version = UInt32(LB_CALLBACKS_VERSION)
        group.on_new_tab = { raw, parentTab, newTab, activateTab, isPopup in
            guard let context = CallbackContext.resolve(raw) else { return }
            let callback = context.page.onNewTab
            MainActor.assumeIsolated { callback?(parentTab, newTab, activateTab != 0, isPopup != 0) }
        }
        group.on_tab_closed = { raw, tab in
            guard let context = CallbackContext.resolve(raw) else { return }
            let callback = context.page.onTabClosed
            MainActor.assumeIsolated { callback?(tab) }
        }
        pageCallbacksInstalled = LbAppSetPageCallbacks(handle, &group) == 1
    }

    /// Registers the hover group. Called once, after the app exists: the group is size-tagged, so a dylib that predates it
    /// returns 0 and the app simply has no hover feedback rather than misreading the struct.
    private func installUICallbacks() {
        guard let handle else { return }

        var group = LbUiCallbacks()
        group.struct_size = UInt32(MemoryLayout<LbUiCallbacks>.size)
        group.version = UInt32(LB_CALLBACKS_VERSION)

        group.on_cursor_change = { raw, tab, standard, png, pngLen, hotspotX, hotspotY in
            guard let context = CallbackContext.resolve(raw) else { return }
            let callback = context.ui.onCursorChange
            guard callback != nil else { return }
            let cursor: PortCursor
            if standard == Int32(LbCursorImage), let png, pngLen > 0 {
                cursor = .image(Data(bytes: png, count: pngLen), hotspotX: hotspotX, hotspotY: hotspotY)
            } else {
                cursor = .standard(standard)
            }
            MainActor.assumeIsolated { callback?(tab, cursor) }
        }
        group.on_link_hover = { raw, tab, url, len in
            guard let context = CallbackContext.resolve(raw) else { return }
            let callback = context.ui.onLinkHover
            guard callback != nil else { return }
            let string = decode(url, len)
            MainActor.assumeIsolated { callback?(tab, string) }
        }
        group.on_link_unhover = { raw, tab in
            guard let context = CallbackContext.resolve(raw) else { return }
            let callback = context.ui.onLinkUnhover
            MainActor.assumeIsolated { callback?(tab) }
        }
        group.on_request_tooltip_override = { raw, tab, x, y, text, len in
            guard let context = CallbackContext.resolve(raw) else { return }
            let callback = context.ui.onTooltipOverride
            guard callback != nil else { return }
            let string = decode(text, len)
            MainActor.assumeIsolated { callback?(tab, x, y, string) }
        }
        group.on_stop_tooltip_override = { raw, tab in
            guard let context = CallbackContext.resolve(raw) else { return }
            let callback = context.ui.onStopTooltipOverride
            MainActor.assumeIsolated { callback?(tab) }
        }
        group.on_enter_tooltip_area = { raw, tab, text, len in
            guard let context = CallbackContext.resolve(raw) else { return }
            let callback = context.ui.onEnterTooltipArea
            guard callback != nil else { return }
            let string = decode(text, len)
            MainActor.assumeIsolated { callback?(tab, string) }
        }
        group.on_leave_tooltip_area = { raw, tab in
            guard let context = CallbackContext.resolve(raw) else { return }
            let callback = context.ui.onLeaveTooltipArea
            MainActor.assumeIsolated { callback?(tab) }
        }

        uiCallbacksInstalled = LbAppSetUiCallbacks(handle, &group) == 1
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

    public func setActiveTab(_ tab: UInt64) {
        guard let handle else { return }
        LbAppSetActiveTab(handle, tab)
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

    public func answerSelectDropdown(in tab: UInt64, requestID: UInt64, selection: UInt32?) {
        guard let handle else { return }
        LbTabAnswerSelectDropdown(handle, tab, requestID, selection == nil ? 0 : 1, selection ?? 0)
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

    /// Reloads the tab's current document. Not a substitute for `load(currentURL)`: the engine marks the history visit
    /// a reload, so a navigation stopped before its document committed is retried instead of becoming a new entry.
    /// `bypassCache` re-fetches from the network.
    public func reload(in tab: UInt64, bypassCache: Bool = false) {
        guard let handle else { return }
        LbTabReload(handle, tab, bypassCache ? 1 : 0)
    }

    /// Stops the tab's current navigation and leaves the document that was showing.
    public func stopLoading(in tab: UInt64) {
        guard let handle else { return }
        LbTabStopLoading(handle, tab)
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
        wheelDeltaY: Double = 0,
        modifiers: UInt32 = 0
    ) {
        guard let handle else { return }
        LbTabSendMouseWithModifiers(
            handle, tab, type.cValue, x, y,
            button.cValue, buttons.cValue, clickCount, wheelDeltaY, modifiers
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
    // The letters, needed only for the Command editing shortcuts: without them ⌘C sends no key and the engine's
    // `KeyCode::Key_C` check never matches. A bare letter still travels as `code_point`, which is what inserts text.
    public static let keyA: Int32 = 0x41
    public static let keyC: Int32 = 0x43
    public static let keyV: Int32 = 0x56
    public static let keyX: Int32 = 0x58
    public static let keyZ: Int32 = 0x5A

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
