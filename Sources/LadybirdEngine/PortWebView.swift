/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The surface-to-CALayer policy, and nothing else. This is `present` from TestNativePresentation.mm, in Swift.
 */

import AppKit
import LadybirdBridge

// S2: the annotation is explicit rather than inherited from NSView, so the invariant is stated where it is enforced
// rather than implied by an AppKit detail that could change.
@MainActor
public final class PortWebView: NSView {
    private let contentLayer = CALayer()

    /// Called when the viewport changes, in CSS pixels plus the backing scale. The model pushes it to the engine.
    public var onViewportChange: ((Int32, Int32, Double) -> Void)?

    /// Mouse input, in CSS pixels relative to this view's top-left.
    public var onMouse: ((PortMouseEventType, Double, Double, PortMouseButton, PortMouseButton, Int32, Double) -> Void)?

    /// Keyboard input. The engine dispatches these asynchronously (see `PortApp.sendKey`).
    public var onKey: ((Int32, UInt32, UInt32, Bool) -> Void)?
    public var onTypeText: ((String) -> Void)?

    /// The view must be first responder for key events to arrive at all.
    public override var acceptsFirstResponder: Bool { true }

    /// Which engine tab this view is currently showing. Owned by the model; the view only uses it to label benchmarks,
    /// so that a frame logged during a tab switch is attributable to the right page.
    public var currentTabID: UInt64 = 0

    private var lastViewport: (width: Int32, height: Int32, scale: Double)?

    public override init(frame: NSRect) {
        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.masksToBounds = true

        contentLayer.isOpaque = true
        contentLayer.contentsGravity = .topLeft
        contentLayer.masksToBounds = true
        // Without this every frame cross-fades in and geometry changes slide (TestNativePresentation).
        contentLayer.actions = [
            "contents": NSNull(),
            "contentsRect": NSNull(),
            "contentsScale": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
        ]
        layer?.addSublayer(contentLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    public override var isFlipped: Bool { true }

    public override func layout() {
        super.layout()
        contentLayer.frame = bounds
        reportViewport()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The scale is only known once AppKit has placed the view in a window, and it changes when the window moves
        // between a Retina and a non-Retina display.
        reportViewport()

        // Order the window front from here rather than from `applicationDidFinishLaunching`: at that point SwiftUI has
        // not created the window yet, so the app launched correctly but behind whatever was already frontmost, which
        // reads as "the app did not open". This is the first moment a window exists.
        //
        // Synchronous on purpose: S3 forbids a queue hop here, and none is needed because this is already the main
        // thread, inside the run loop that owns presentation.
        if let window, !hasOrderedFront {
            hasOrderedFront = true
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private var hasOrderedFront = false

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        reportViewport()
    }

    // MARK: - Input

    /// AppKit reports a click as points in this (flipped) view; the engine wants CSS pixels from the top-left, which is
    /// the same thing once `isFlipped` is true. The conversion to device pixels is the shim's job, so nothing here
    /// multiplies by the backing scale twice.
    private func point(_ event: NSEvent) -> (Double, Double) {
        let local = convert(event.locationInWindow, from: nil)
        return (Double(local.x), Double(local.y))
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let (x, y) = point(event)
        onMouse?(.down, x, y, .primary, .primary, Int32(event.clickCount), 0)
    }

    public override func mouseUp(with event: NSEvent) {
        let (x, y) = point(event)
        // Nothing is held after a mouse-up, which is what the engine expects in `buttons`.
        onMouse?(.up, x, y, .primary, .none, Int32(event.clickCount), 0)
    }

    public override func mouseDragged(with event: NSEvent) {
        let (x, y) = point(event)
        onMouse?(.move, x, y, .none, .primary, 0, 0)
    }

    public override func mouseMoved(with event: NSEvent) {
        let (x, y) = point(event)
        onMouse?(.move, x, y, .none, .none, 0, 0)
    }

    public override func otherMouseDown(with event: NSEvent) {
        let (x, y) = point(event)
        onMouse?(.down, x, y, .middle, .middle, Int32(event.clickCount), 0)
    }

    public override func otherMouseUp(with event: NSEvent) {
        let (x, y) = point(event)
        onMouse?(.up, x, y, .middle, .none, Int32(event.clickCount), 0)
    }

    public override func rightMouseDown(with event: NSEvent) {
        let (x, y) = point(event)
        onMouse?(.down, x, y, .secondary, .secondary, Int32(event.clickCount), 0)
    }

    public override func rightMouseUp(with event: NSEvent) {
        let (x, y) = point(event)
        onMouse?(.up, x, y, .secondary, .none, Int32(event.clickCount), 0)
    }

    public override func scrollWheel(with event: NSEvent) {
        let (x, y) = point(event)
        onMouse?(.wheel, x, y, .none, .none, 0, PortWebView.wheelDelta(from: event))
    }

    /// Converts AppKit's wheel delta to the engine's sign convention and units.
    ///
    /// Two conventions meet here and they are opposite:
    /// - The engine's `wheel_delta_y` is a scroll-offset delta: positive increases `scrollY`, so later content comes into
    ///   view. Measured by `TestNativeInput` (`delta_y=+120` -> `scrollY=120`).
    /// - AppKit's `scrollingDeltaY` is positive for an upward wheel/gesture, which *decreases* `scrollY`.
    ///
    /// So the delta is negated. That single negation is also what makes this follow the system "natural scrolling"
    /// setting rather than fighting it: AppKit already folds the preference into `scrollingDeltaY`, so when a user turns
    /// natural scrolling off the OS flips the sign it reports and the page follows their new expectation automatically.
    /// Consequently `isDirectionInvertedFromDevice` must NOT be applied as well — doing both double-inverts.
    ///
    /// Qt's backend does the same thing for the same reason (`-wheel_event.pixelDelta()` in UI/Qt/WebContentView.cpp).
    ///
    /// Precise devices (trackpads, Magic Mouse) report pixels. Legacy notched wheels report lines, which need a scale to
    /// pixels — a sign flip alone would move far too little.
    static func wheelDelta(from event: NSEvent) -> Double {
        engineWheelDelta(appKitDelta: event.scrollingDeltaY, isPrecise: event.hasPreciseScrollingDeltas)
    }

    /// The conversion itself, split out from `NSEvent` so it can be exercised without a trackpad.
    static func engineWheelDelta(appKitDelta: Double, isPrecise: Bool) -> Double {
        let pixels = isPrecise ? appKitDelta : appKitDelta * lineHeightInPixels
        return -pixels
    }

    /// A notched wheel reports whole lines; browsers use roughly this many CSS pixels per line.
    static let lineHeightInPixels: Double = 16

    public override func keyDown(with event: NSEvent) {
        let (key, codePoint, modifiers) = PortWebView.translate(event)
        onKey?(key, codePoint, modifiers, true)
    }

    public override func keyUp(with event: NSEvent) {
        let (key, codePoint, modifiers) = PortWebView.translate(event)
        onKey?(key, codePoint, modifiers, false)
    }

    /// Bridges an NSEvent to the ABI's (KeyCode ordinal, code point, modifier mask).
    ///
    /// Only the keys the chrome actually needs are mapped; everything else goes through as text with an unresolved key,
    /// which the engine handles via `code_point`. `invalidCharacters` is what carries “this keypress produced no text”
    /// (arrows, Escape), and those are sent by key code instead.
    private static func translate(_ event: NSEvent) -> (Int32, UInt32, UInt32) {
        var modifiers: UInt32 = 0
        let flags = event.modifierFlags
        if flags.contains(.option) { modifiers |= PortKey.modAlt }
        if flags.contains(.control) { modifiers |= PortKey.modCtrl }
        if flags.contains(.shift) { modifiers |= PortKey.modShift }
        if flags.contains(.command) { modifiers |= PortKey.modSuper }

        // Web's KeyCode ordinals for the non-text keys worth mapping, so Backspace and navigation work before the
        // full table is bridged. Text keys are left unresolved on purpose.
        let key: Int32
        switch event.keyCode {
        // These are AppKit's virtual key codes (ANSI layout), not characters.
        case 51: key = PortKey.backspace
        case 48: key = PortKey.tab
        case 36: key = PortKey.enter
        case 53: key = PortKey.escape
        case 117: key = PortKey.delete
        case 116: key = PortKey.pageUp
        case 121: key = PortKey.pageDown
        case 123: key = PortKey.left
        case 124: key = PortKey.right
        case 125: key = PortKey.down
        case 126: key = PortKey.up
        default: key = PortKey.invalid
        }

        // Never take characters for a command shortcut: those belong to the menu bar, not the page.
        var codePoint: UInt32 = 0
        if !flags.contains(.command), let characters = event.characters, let first = characters.unicodeScalars.first {
            // Control characters are what AppKit gives for Return/Tab/Backspace; the engine wants the key, not the byte.
            if first.value >= 0x20, first.value != 0x7F {
                codePoint = first.value
            }
        }

        return (key, codePoint, modifiers)
    }

    /// R3: assign and return. The surface is borrowed from the engine and is only valid on this call stack; `CALayer`
    /// retains it for us. `painted` may be smaller than `surface`, so crop with `contentsRect` (R1: never clone).
    public func present(_ surface: PortSurface) {
        let surfaceWidth = CGFloat(surface.surfaceWidth)
        let surfaceHeight = CGFloat(surface.surfaceHeight)
        let paintedWidth = CGFloat(surface.paintedWidth)
        let paintedHeight = CGFloat(surface.paintedHeight)
        guard surfaceWidth > 0, surfaceHeight > 0, paintedWidth > 0, paintedHeight > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.contentsScale = window?.backingScaleFactor ?? 1
        // The layer's unit rectangle has its origin at the bottom-left, so anchor the painted part at the top.
        contentLayer.contentsRect = CGRect(
            x: 0,
            y: 1 - paintedHeight / surfaceHeight,
            width: paintedWidth / surfaceWidth,
            height: paintedHeight / surfaceHeight
        )
        // Borrowed from the engine; the layer retains it on assignment, on this same stack (S5). The cast itself lives
        // in Bridge (S1).
        contentLayer.contents = surface.ref
        CATransaction.commit()
    }

    /// Removes the previous tab's retained surface while the newly selected tab has no frame yet. Leaving it attached
    /// shows the wrong page until paint #1, which is both a visual glitch and a privacy leak across tabs.
    public func clearSurface() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.contents = nil
        CATransaction.commit()
    }

    /// Pushes the current viewport again, even if it has not changed.
    ///
    /// `reportViewport` de-duplicates, which is right for layout passes but wrong at one moment: SwiftUI lays the view
    /// out before the engine has a tab, so the first report is dropped (there is no tab to tell) and then cached. The
    /// tab was left at the engine's 1024x768 default and the page rendered at the wrong scale — the painted surface was
    /// 1024x768 for a 900x398 viewport. Calling this right after the tab exists fixes it.
    public func reportViewportAfterTabCreation() {
        lastViewport = nil
        reportViewport()
    }

    private func reportViewport() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        // Points are CSS pixels; the engine multiplies by the scale itself (Traps.md, "A headless viewport is in
        // device pixels").
        let width = Int32(bounds.width.rounded())
        let height = Int32(bounds.height.rounded())
        let scale = Double(window?.backingScaleFactor ?? 1)
        guard lastViewport?.width != width || lastViewport?.height != height || lastViewport?.scale != scale else {
            return
        }
        lastViewport = (width, height, scale)
        onViewportChange?(width, height, scale)
    }
}
