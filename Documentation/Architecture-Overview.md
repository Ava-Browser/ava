# Architecture at a glance

New here? Read this first, then [the ABI boundary](ABI.md), then [building](Building.md).

Ava is two programs in two Git repositories: a Swift/SwiftUI **macOS app** (this repo) and a
**Ladybird engine fork** (`Extern/ladybird`, from `Ava-Browser/ava-engine`). They meet at one
hand-written C interface. Everything below follows from that sentence.

## The two repos

```
┌─────────────────────────────────────┐         ┌──────────────────────────────────────┐
│ ava-engine  (Ladybird fork)         │         │ ava  (this repo)                     │
│                                     │         │                                      │
│  Libraries/                         │         │  Sources/LadybirdUI      2121 lines  │
│  Services/                          │   C11   │  Sources/LadybirdEngine  2581 lines  │
│                                     │   ABI   │  Sources/LadybirdBridge   433 lines  │
│  Libraries/LibPort/                 │◀───────▶│  Sources/CLadybirdPort     10 lines  │
│    ladybird_port.h     215 lines    │         │  Sources/LadybirdMac       47 lines  │
│    ladybird_port.cpp   714 lines    │         │                                      │
└─────────────────────────────────────┘         └──────────────────────────────────────┘
   upstream Ladybird + one additive dir              everything above the boundary
```

The fork is **a dependency you happen to control**, not a workspace. It is pinned as a submodule and
the pin advances deliberately, never incidentally. Changing `Extern/ladybird/Libraries/LibPort/` is
allowed; changing anything else there is rebase debt (rule R7).

## Layers, top to bottom

Each layer may only talk to the one below it. Arrows point at *permitted* dependencies.

```
        ┌──────────────────────────────────────────────┐
        │  LadybirdUI          SwiftUI views           │  BrowserWindow, TabSidebar,
        │  "the chrome"                                │  AddressBarView, SettingsView
        └───────────────────┬──────────────────────────┘
                            │  model objects only, never the C ABI
        ┌───────────────────▼──────────────────────────┐
        │  LadybirdEngine      AppKit / CoreFoundation │  BrowserModel, PortWebView,
        │  "the only AppKit layer"                     │  the pump, CALayer policy
        └───────────────────┬──────────────────────────┘
                            │
        ┌───────────────────▼──────────────────────────┐
        │  LadybirdBridge      Swift, no AppKit        │  trampolines, one Unmanaged
        │  "shape conversion"                          │  context, error mapping
        └───────────────────┬──────────────────────────┘
                            │
        ┌───────────────────▼──────────────────────────┐
        │  CLadybirdPort       C module                │  module.modulemap + header
        │  "the ABI"                                   │
        └───────────────────┬──────────────────────────┘
                            │  liblagom-port.dylib
        ┌───────────────────▼──────────────────────────┐
        │  LibPort             C++ / CoreFoundation    │  inside the fork
        └──────────────────────────────────────────────┘
```

The boundary has teeth because SwiftPM makes most violations *compile* errors: `LadybirdUI` cannot
`import CLadybirdPort` because it does not depend on that target. The rest are greppable and checked
by `Scripts/check-layers.sh` on every commit.

Why is AppKit confined to one layer? So `LadybirdBridge` can be tested with no window and no engine,
and so no view code can quietly start puppeteering the engine.

## One click, end to end

A click is the clearest path through every layer. Note that it never crosses into Swift concurrency —
there is exactly one thread.

```
 user clicks in the window
        │
        ▼
 ① PortWebView (Engine)              NSView receives the event, converts to CSS pixels,
        │                            divides by its own isFlipped/backing scale
        ▼
 ② LadybirdBridge                     LbTabSendMouse(app, tab, x, y, button, clickCount)
        │
        ▼
 ③ LibPort                            PortWebView::mouse_event(...)
        │
        ▼
 ④ engine (LibWeb)                    hit-test, dispatch, script, style, layout, paint
        │
        ▼
 ⑤ compositor publishes a frame  ──┐
        │                          │  only when something changed (R3): a settled page
        ▼                          │  emits exactly one frame, not a stream
 ⑥ on_ready_to_paint fires  ◀──────┘
        │
        ▼
 ⑦ PortWebView asks LbTabGetSurface   returns an IOSurfaceRef + painted/surface sizes
        │                            retained for the duration of this callback only (S5)
        ▼
 ⑧ layer.contents = surface           assigned on the main thread, then returns (R6)
        │
        ▼
    the window server composites it
```

Two things surprise people here:

- **Step ⑥ is demand-driven.** There is no display link, no redraw timer, no frame counter. If the
  page did not change, nothing is called. Polling would be both wasteful and wrong (R3).
- **Step ⑦ hands over a borrowed reference.** Retain, assign, release — all inside the callback. The
  frame swap can reclaim the surface the moment the callback returns (S5).

## One page load, end to end

```
 LbTabLoad(app, tab, url)
        │
        ▼
 LibPort: PortWebView::load(url)
        │
        ▼
 engine → helper processes (spawned by name from Contents/MacOS)
        │
        ├── RequestServer    network, DNS, TLS, cookies
        ├── WebContent       parse, script, style, layout
        ├── WebWorker        workers (JIT)
        ├── ImageDecoder     decode
        ├── Compositor       paints
        └── MediaServer / AudioServer / VideoDecoderServer
        │
        ▼
 callbacks, in rough order:
     on_load_finish ──▶ address bar settles
     on_title_change ──▶ tab title
     on_favicon_change ──▶ tab icon
     on_ready_to_paint ──▶ the frame (see above)
```

`on_ready_to_paint` can fire **before** `on_load_finish` — that first paint is blank. Asserting "the
page rendered" on paint #1 lets an empty view pass. See [Traps](Traps.md).

## The event loop

There is one loop and it is the main thread's. `CFRunLoopRun()` owns the thread; a 2 ms
`CFRunLoopTimer` registered in `kCFRunLoopCommonModes` gives the engine one non-blocking poll per
tick.

```
  main thread, one CFRunLoop
  ┌────────────────────────────────────────────────────────────┐
  │  AppKit events ──┐                                         │
  │                  ├──▶  CFRunLoopRun()  ──▶  you           │
  │  engine pump  ───┘        ▲                                │
  │   (2 ms, CommonModes) ────┘                                │
  └────────────────────────────────────────────────────────────┘
            engine callbacks run synchronously inside the pump,
            on this thread, between your normal iterations
```

`CommonModes` is not a detail. During a live window resize or a menu drag, AppKit switches the loop
to `NSEventTrackingRunLoopMode`; a default-mode timer stops firing entirely and the engine freezes for
the whole gesture (R8, measured in `Traps.md`).

Because there is one thread, nothing in `Sources/` may use `DispatchQueue` or `Task.detached` (S3) and
presentation uses `MainActor.assumeIsolated` rather than a hop (R5). The IOSurface hand-off is
race-free *by construction* only while this holds.

## Where to go next

- How Swift and C++ actually talk, and why hand-written C → [ABI](ABI.md)
- How to build and run → [Building](Building.md)
- The rules that are enforced, and by what → [Rules](Rules.md)
- Things that cost people hours → [Traps](Traps.md)
