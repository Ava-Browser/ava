# 0002 — SwiftUI, not GPUI

**Status:** accepted
**Date:** 2026-10-24

## Context

The chrome layer needs a toolkit. SwiftUI is the native default on macOS; [GPUI](https://gpui.rs)
(Zed's Rust framework) was the credible alternative, and would in principle give cross-platform
chrome from one codebase.

## Decision

SwiftUI (with AppKit where it is the better fit — the surface host is a plain `NSView` +
`CALayer`). Not GPUI.

## Reasons

Ranked by how much they actually mattered:

1. **Zero-copy presentation only works one way.** Ladybird hands the UI a **BGRA `IOSurface`**.
   `CALayer.contents` accepts it in one line, today. GPUI's `paint_surface` only accepts YCbCr;
   BGRA support is an unmerged PR. Choosing GPUI would have meant either a colour conversion per
   frame or waiting on upstream.
2. **Accessibility.** SwiftUI gives VoiceOver nearly free. GPUI has no accessibility layer (no
   AccessKit integration at the time of the decision).
3. **Stability.** GPUI was pre-1.0 with breaking changes between releases and community work
   deprioritized upstream. A browser chrome is not a place to absorb that churn.
4. **Its one real advantage is worthless here.** Cross-platform chrome would matter, but Windows
   support is deferred, and on Linux Ladybird's backing stores are shared memory — GPUI would take
   the CPU-copy path there anyway, losing the zero-copy benefit that motivated it.

## Revisit trigger

Reopen this decision if **cross-platform chrome becomes a hard product requirement**. That is the
one condition the choice was contingent on. It is cheap to revisit: the C ABI is language-agnostic,
so only `LadybirdUI` and `LadybirdEngine`'s window layer would be replaced — the boundary, the
pump, and the surface policy all survive.

## Consequences

- macOS only. Accepted deliberately; Windows was already deferred.
- Revisiting this costs no spike rework, because the C ABI is language-agnostic. If
  cross-platform chrome ever becomes a hard requirement, only `LadybirdUI` and
  `LadybirdEngine`'s window layer are replaced.
