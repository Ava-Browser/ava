/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The surface-to-CALayer policy, and nothing else. This is `present` from TestNativePresentation.mm, in Swift.
 */

import AppKit
import LadybirdBridge

public final class PortWebView: NSView {
    private let contentLayer = CALayer()

    /// Called when the viewport changes, in CSS pixels plus the backing scale. The model pushes it to the engine.
    public var onViewportChange: ((Int32, Int32, Double) -> Void)?

    private var lastViewport: (width: Int32, height: Int32, scale: Double)?

    public override init(frame: NSRect) {
        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.masksToBounds = true

        contentLayer.isOpaque = true
        // Without this every frame cross-fades in and geometry changes slide (TestNativePresentation).
        contentLayer.actions = [
            "contents": NSNull(),
            "contentsRect": NSNull(),
            "contentsScale": NSNull(),
            "bounds": NSNull(),
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
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        reportViewport()
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
        // The pointer *is* the IOSurfaceRef the shim handed across. Taking it unretained is safe because the layer
        // retains it on assignment, on this same stack.
        contentLayer.contents = Unmanaged<CFTypeRef>.fromOpaque(surface.iosurface).takeUnretainedValue()
        CATransaction.commit()
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
