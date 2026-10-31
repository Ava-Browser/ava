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
    public var onMouse: ((PortMouseEventType, Double, Double, PortMouseButton, PortMouseButton, Int32, Double, UInt32) -> Void)?

    /// Keyboard input. The engine dispatches these asynchronously (see `PortApp.sendKey`).
    public var onKey: ((Int32, UInt32, UInt32, Bool) -> Void)?
    public var onTypeText: ((String) -> Void)?

    /// The cursor the page most recently asked for. Applied through `resetCursorRects`, which AppKit recomputes on
    /// scroll and resize, so the pointer cannot be left showing a shape the page no longer wants.
    private var pageCursor: NSCursor = .arrow { didSet { window?.invalidateCursorRects(for: self) } }

    /// The view must be first responder for key events to arrive at all.
    public override var acceptsFirstResponder: Bool { true }

    // MARK: - Hover

    /// AppKit delivers `mouseMoved` only through a tracking area (or with `window.acceptsMouseMovedEvents`), so without
    /// this the engine never sees a pointer move: no `:hover`, no cursor change, no tooltips. Clicks keep working, which
    /// is what made the omission look like a styling problem rather than a missing event.
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        ))
    }

    /// Sets the pointer for the whole view. `resetCursorRects` is the sanctioned way to make it stick through scrolling;
    /// calling `NSCursor.set()` alone is undone by the next cursor-rect pass.
    public func applyCursor(_ cursor: PortCursor) {
        switch cursor {
        case let .standard(ordinal):
            pageCursor = PortWebView.cursor(for: ordinal)
        case let .image(data, hotspotX, hotspotY):
            if let image = NSImage(data: data) {
                pageCursor = NSCursor(image: image, hotSpot: NSPoint(x: CGFloat(hotspotX), y: CGFloat(hotspotY)))
            }
        }
        pageCursor.set()
    }

    public override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: pageCursor)
    }

    public override func cursorUpdate(with event: NSEvent) {
        pageCursor.set()
    }

    /// `Gfx::StandardCursor` ordinals to AppKit. The image case is handled by the caller; anything unmapped stays an arrow
    /// rather than guessing at a shape the engine did not name.
    static func cursor(for ordinal: Int32) -> NSCursor {
        switch ordinal {
        case PortStandardCursor.hidden: .init()
        case PortStandardCursor.crosshair: .crosshair
        case PortStandardCursor.iBeam: .iBeam
        case PortStandardCursor.resizeHorizontal, PortStandardCursor.resizeColumn: .resizeLeftRight
        case PortStandardCursor.resizeVertical, PortStandardCursor.resizeRow: .resizeUpDown
        case PortStandardCursor.hand: .pointingHand
        case PortStandardCursor.openHand: .openHand
        case PortStandardCursor.drag: .closedHand
        case PortStandardCursor.move: .openHand
        case PortStandardCursor.disallowed: .operationNotAllowed
        default: .arrow
        }
    }

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
        contentLayer.contentsGravity = .bottomLeft
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
        // Launch activation is not here: the start page mounts no web view. See LaunchActivation.
    }

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
        onMouse?(.down, x, y, .primary, .primary, Int32(event.clickCount), 0, PortWebView.engineModifiers(from: event.modifierFlags))
    }

    public override func mouseUp(with event: NSEvent) {
        let (x, y) = point(event)
        // Nothing is held after a mouse-up, which is what the engine expects in `buttons`.
        onMouse?(.up, x, y, .primary, .none, Int32(event.clickCount), 0, PortWebView.engineModifiers(from: event.modifierFlags))
    }

    public override func mouseDragged(with event: NSEvent) {
        let (x, y) = point(event)
        onMouse?(.move, x, y, .none, .primary, 0, 0, PortWebView.engineModifiers(from: event.modifierFlags))
    }

    public override func mouseMoved(with event: NSEvent) {
        let (x, y) = point(event)
        onMouse?(.move, x, y, .none, .none, 0, 0, PortWebView.engineModifiers(from: event.modifierFlags))
    }

    public override func otherMouseDown(with event: NSEvent) {
        let (x, y) = point(event)
        onMouse?(.down, x, y, .middle, .middle, Int32(event.clickCount), 0, PortWebView.engineModifiers(from: event.modifierFlags))
    }

    public override func otherMouseUp(with event: NSEvent) {
        let (x, y) = point(event)
        onMouse?(.up, x, y, .middle, .none, Int32(event.clickCount), 0, PortWebView.engineModifiers(from: event.modifierFlags))
    }

    public override func rightMouseDown(with event: NSEvent) {
        let (x, y) = point(event)
        onMouse?(.down, x, y, .secondary, .secondary, Int32(event.clickCount), 0, PortWebView.engineModifiers(from: event.modifierFlags))
    }

    public override func rightMouseUp(with event: NSEvent) {
        let (x, y) = point(event)
        onMouse?(.up, x, y, .secondary, .none, Int32(event.clickCount), 0, PortWebView.engineModifiers(from: event.modifierFlags))
    }

    public override func scrollWheel(with event: NSEvent) {
        let (x, y) = point(event)
        onMouse?(.wheel, x, y, .none, .none, 0, PortWebView.wheelDelta(from: event), PortWebView.engineModifiers(from: event.modifierFlags))
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
    static func engineModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.option) { modifiers |= PortKey.modAlt }
        if flags.contains(.control) { modifiers |= PortKey.modCtrl }
        if flags.contains(.shift) { modifiers |= PortKey.modShift }
        if flags.contains(.command) { modifiers |= PortKey.modSuper }
        return modifiers
    }

    private static func translate(_ event: NSEvent) -> (Int32, UInt32, UInt32) {
        let flags = event.modifierFlags
        let modifiers = engineModifiers(from: flags)

        // Web's KeyCode ordinals. The letters are here only for the Command shortcuts: a bare letter still travels as a
        // `code_point`, because that is what inserts text, and mapping it here would deliver a key the engine resolves
        // as a command instead of a character.
        let key: Int32
        if flags.contains(.command), let letter = PortWebView.commandLetterKey(event) {
            return (letter, 0, modifiers)
        }
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

        // Never take characters for a command shortcut: those belong to the menu bar, not the page. The key itself must
        // still cross, though, because the engine's editing shortcuts match `KeyCode::Key_C` and friends under
        // `Mod_PlatformCtrl` (which is `Mod_Super` on macOS) -- see EventHandler. Sending `(invalid, 0, Mod_Super)`, as
        // this did, is delivered, handled and does nothing, so copy/paste/cut/select-all/undo were all silent no-ops.
        var codePoint: UInt32 = 0
        if !flags.contains(.command), let characters = event.characters, let first = characters.unicodeScalars.first {
            // Control characters are what AppKit gives for Return/Tab/Backspace; the engine wants the key, not the byte.
            if first.value >= 0x20, first.value != 0x7F {
                codePoint = first.value
            }
        }

        return (key, codePoint, modifiers)
    }

    /// The `KeyCode` for the letter behind a Command shortcut, or nil when the key is not one the engine matches.
    ///
    /// `EventHandler` compares against `KeyCode::Key_A/C/V/X/Z` under `Mod_PlatformCtrl`, so those five are the ones worth
    /// mapping; the rest of the alphabet has no editing command and is left to the menu bar.
    static func commandLetterKey(_ event: NSEvent) -> Int32? {
        switch event.keyCode {
        case 0: PortKey.keyA
        case 8: PortKey.keyC
        case 9: PortKey.keyV
        case 7: PortKey.keyX
        case 6: PortKey.keyZ
        default: nil
        }
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
        // This view is always flipped (see `isFlipped`), so the layer's y-axis points down. Anchoring the painted part
        // at the visual top-left means y-origin 0, not (1 - heightRatio). Vertical gravity inverts with it: .bottomLeft
        // pins to the top-left. Reading it back from the layer instead would be inferring our own constant from AppKit
        // incidental behaviour, and R1 still holds either way: the crop stays a contentsRect, never a bitmap clone.
        contentLayer.contentsGravity = .bottomLeft
        contentLayer.contentsRect = CGRect(
            x: 0,
            y: 0,
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
