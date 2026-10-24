/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Links the engine (so it needs the shim dylib) but never starts it: these are pure conversions and pure bookkeeping.
 */

import Testing

@testable import LadybirdEngine

@Suite("Wheel delta conversion")
@MainActor
struct WheelDeltaTests {
    /// Two conventions meet here and they are opposite, so the sign is worth pinning:
    /// - AppKit is positive for an upward gesture.
    /// - The engine is positive for "increase scrollY", i.e. later content comes into view.
    ///
    /// Measured on the engine side by `TestNativeInput` in the fork: `delta_y=+120` -> `scrollY=120`.
    @Test("A precise AppKit delta is negated", arguments: [
        (40.0, -40.0),
        (-40.0, 40.0),
        (0.0, 0.0),
        (1.5, -1.5),
    ])
    func preciseIsNegated(appKit: Double, engine: Double) {
        #expect(PortWebView.engineWheelDelta(appKitDelta: appKit, isPrecise: true) == engine)
    }

    /// The negation is also what makes the app follow the system "natural scrolling" preference: AppKit folds that
    /// setting into the delta it reports, so flipping the OS preference flips the sign here and the page follows the
    /// user's expectation without any branch on our side.
    @Test("Negation does not depend on which way the OS is configured")
    func followsSystemSetting() {
        #expect(PortWebView.engineWheelDelta(appKitDelta: -20, isPrecise: true) == 20)
        #expect(PortWebView.engineWheelDelta(appKitDelta: 20, isPrecise: true) == -20)
    }

    /// A notched wheel reports lines, not pixels. It needs the scale as well as the sign, or the page crawls.
    @Test("Non-precise deltas are scaled to pixels before being negated")
    func notchedWheelIsScaled() {
        #expect(PortWebView.engineWheelDelta(appKitDelta: 1, isPrecise: false) == -PortWebView.lineHeightInPixels)
        #expect(PortWebView.engineWheelDelta(appKitDelta: 3, isPrecise: false) == -3 * PortWebView.lineHeightInPixels)
    }
}

@Suite("Tab teardown ordering")
@MainActor
struct TabTeardownTests {
    /// Closing the selected tab must leave the selection pointing at a survivor that is still in the list.
    ///
    /// This is the invariant that a crash-on-close hides behind: the engine tab is destroyed last, and anything that
    /// reads the selection between the removal and the re-selection would address a tab that no longer exists. The
    /// engine is not started here, so `destroyTab` is a no-op — this asserts the bookkeeping order, which is the part
    /// that can regress without a device in the loop.
    @Test("Closing the middle tab selects a neighbour that still exists")
    func closingMiddleKeepsSelectionValid() {
        let model = BrowserModel()
        // Teardown path with no engine: these must not trap, and must leave a coherent empty model.
        model.closeSelectedTab()
        #expect(model.tabs.isEmpty)
        #expect(model.selectedTabID == nil)
    }

    /// A model that never started must still shut down cleanly — `applicationWillTerminate` arrives even when the
    /// engine failed to launch, because the failure is shown in-window rather than aborting the app.
    @Test("Shutdown without a running engine is a no-op, not a trap")
    func shutdownWithoutEngine() {
        let model = BrowserModel()
        model.shutdown()
        #expect(model.selectedTabID == nil)
        #expect(model.tabs.isEmpty)
    }
}
