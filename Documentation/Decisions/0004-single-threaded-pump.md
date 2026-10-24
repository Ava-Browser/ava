# 0004 — One event loop, pumped cooperatively

**Status:** accepted
**Date:** 2026-10-24

## Context

LibCore has its own event loop; AppKit has `CFRunLoop`. Two loops, one main thread. The obvious
alternative — run the engine on a dedicated thread with its own loop — was considered seriously and
is worse.

## Decision

**One loop, on the main thread.** `CFRunLoopRun()` owns the thread; a 2 ms `CFRunLoopTimer`
registered in `kCFRunLoopCommonModes` gives LibCore one `PollForEvents` iteration per tick.

`LbAppPump` exists for hosts that want to drive it themselves. There is deliberately no blocking
`LbAppRun`: it would fight SwiftUI for the main thread.

## Why single-threaded

1. **No threads, no rules.** The `deferred_invoke` wakeup contract, the `@MainActor` hop, and the
   engine-thread join dance all evaporate. It is not two loops merged; it is one loop lending ticks
   to the other.
2. **The surface borrow-then-retain becomes race-free by construction.** On two threads there is a
   window between the shim handing out the `IOSurfaceRef` and Swift retaining it, during which a
   frame swap could drop the surface. On one thread that window does not exist.
3. **LibCore's loop is not thread-safe by design.** Pinning it to the main thread removes a bug
   class rather than managing one.

## Consequences

- **R5 becomes an invariant, not a preference.** Presentation uses `MainActor.assumeIsolated`
  rather than a detached hop — correct *because* everything is on one thread. If a second loop ever
  appears, R5 must be re-litigated, not bypassed.
- **R6 matters:** a blocking callback blocks the engine's rendering *and* input. The presentation
  callback retains the surface, assigns `layer.contents`, and returns.
- **R8 matters:** the timer must be in `kCFRunLoopCommonModes`. A default-mode timer starves to
  **zero** during live resize and menu tracking. Measured: two timers, 0.3 s of tracking mode →
  common-mode 151 ticks, default-mode 0.

## Measured

`Tests/LibWebView/TestNativeEventLoop` (10/10 runs): 10 ms heartbeat timer with 10 ms max gap,
full Mach-port IPC round-trips, paints arriving normally, nested `pump()` from inside
`on_ready_to_paint` safe (`ThreadEventQueue::process()` moves the queue out under a lock before
dispatching), and **150 pumps in 301 ms of real `NSEventTrackingRunLoopMode`**.

The 2 ms poll is ~500 wakeups/sec forever, which is wrong for a browser left open all day. Replacing
it with a `CFRunLoopSource` signalled from the event loop's wake pipe is recorded in
`Architecture.md` under known gaps.
