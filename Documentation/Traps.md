# Measured traps

Each of these cost real time during the spike. None of them are guessable from reading the API.

## Engine

**`EventLoop::pump()` defaults to blocking.**
`Core::EventLoop::WaitMode::WaitForEvents` will `poll(-1)` forever when no timer is pending. There
is no `DontWaitForEvents`. Use `PollForEvents` (`poll(0)`) in a cooperative host, or the host
hangs. *Fix: `LbAppPump` always passes `PollForEvents`.*

**A settled page emits exactly one paint.**
The compositor publishes on change, not continuously. `on_ready_to_paint` means "a new frame is
available", not a frame tick. *Fix: to prove liveness, load a second page; never wait for N paints
after one load.*

**Paint #1 arrives before `on_load_finish`.**
It is the early blank paint. Asserting "the page rendered" on paint #1 lets an empty view pass.
*Fix: key render assertions on a paint that arrives strictly after load finished.*

**Navigating before the initial `about:blank` load finishes drops the navigation.**
*Fix: wait out the first `on_load_finish` before loading anything.*

**`about:srcdoc` counts as an `on_load_finish`.**
*Fix: navigation assertions must compare URLs or load counts, never "did another load happen".*

**Wheel events are consumed by the compositor, not forwarded to WebContent.**
The scroll still lands and is observable, but no WebContent-side callback fires. *Fix: observe the
page's own state (a `scroll` listener), never a callback.*

**A headless viewport is in device pixels.**
900×600 at 2× is 1800×1200. Passing CSS sizes straight through renders the page at half scale.
*Fix: `LbTabSetViewport` takes CSS size + ratio and multiplies.*

**`URL::serialize()` is UTF-16.** Any `char*` callback built from an AK string must narrow with
`to_byte_string()` first. It compiles either way, so this fails at runtime.

**`ViewImplementation`'s bitmap members are `protected`.**
`m_front_bitmap`, `m_backup_shared_image_buffer`, `m_backup_bitmap_size` are only reachable by
subclassing. Copy `WebContentView::current_paintable()` verbatim — its `m_has_usable_bitmap` gate
and backup fallback are load-bearing; checking only `shared_image_buffer != nullptr` hands you a
stale bitmap mid-swap.

## Tooling

**`--headless=screenshot` needs `--screenshot-delay=6`.**
The default 1 s yields a blank white PNG. Every colour comparison against it is then meaningless.

**The R4 header check must compile a TU that includes the header.**
Checking the header file alone trips `-Wpragma-once-outside-header` and reports a false failure.

**The R2 ObjC check must strip comments first.**
The header discusses `objc_msgSend` in prose; a naive grep matches the discussion. Preprocess
(`clang -x c++ -E -P`) before grepping.

**The R7 fork-diff guard must diff against the merge-base, not `upstream/master`.**
Otherwise every commit upstream has landed since this fork's HEAD looks like a local change and the
guard reports hundreds of irrelevant files. Measured: `upstream/master` reported 300 files and
13,649 deletions; the merge-base reports 4 paths.

**Importing a C module does not link its library.**
`import CLadybirdPort` compiles fine with no `linkerSettings` at all, because nothing references a
symbol. The link only happens when Swift touches one. *Fix: `LadybirdEngine` carries
`-L Extern/ladybird/Build/release/lib -llagom-port`, and `Engine.swift` touches a symbol so the
dependency is real. Verify with `otool -L`.

**The fork builds for macOS 14.4** (`CMAKE_OSX_DEPLOYMENT_TARGET`). A package targeting `.v14`
links with a "built for newer version" warning. *Fix: `platforms: [.macOS("14.4")]`.

## Verified non-issues

**Pump-during-live-drag is safe.** The freeze-during-gesture bug is real — a default-mode timer
starves completely in `NSEventTrackingRunLoopMode` — and CommonModes avoids it. Measured two ways:

- Synthetic control: two timers on one run loop, 0.3 s of tracking mode → common-mode 151 ticks,
  default-mode **0** ticks.
- `TestNativeEventLoop` drives the real tracking mode after the main phase:
  **150 pumps in 301 ms** of `NSEventTrackingRunLoopMode`, against ~150 expected at a 2 ms timer.
  The probe now asserts this (`tracking-mode pump: true`), so a regression fails the build rather
  than freezing a user's window.

No manual menu-holding test is needed. Do not "simplify" the timer to the default mode.
