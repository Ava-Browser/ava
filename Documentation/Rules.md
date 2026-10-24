# Contract rules

Enforced by `Scripts/check-layers.sh` where possible; the rest are code-review rules. These are
not style preferences — each one exists because the alternative produced a measured failure.

| # | Rule | Why | Enforcement |
|---|---|---|---|
| **R1** | **Never crop or clone a surface-backed bitmap.** Cross the ABI with the raw handle plus painted/surface sizes; crop with `CALayer.contentsRect`. CPU pixels → `IOSurfaceHandle::bytes_per_row()` scanline walk, or `ViewImplementation::take_screenshot()`. | `Bitmap::cropped()` calls `clone()`, which trips `VERIFY(size_in_bytes() == new_bitmap->size_in_bytes())` because an IOSurface's pitch need not be `width * 4`. It aborts even for a full-size no-op crop. | code review |
| **R2** | **The shim is C ABI + CF pointers only. All ObjC lives in this repo.** | Makes Swift's side a plain C module — no `-enable-experimental-cxx-interop`, no `AK::Function` translation, zero per-callback trampoline allocation. | `check-layers.sh` (preprocessed grep) |
| **R3** | **Presentation is demand-driven.** `on_ready_to_paint` → assign `layer.contents` → return. No display link, no invalidation timer, no frame counter. | The compositor publishes on change; a settled page emits exactly one frame. Anything polling is wasted CPU and wrong. | `check-layers.sh` greps for `CVDisplayLink` / `CADisplayLink` |
| **R4** | **`ladybird_port.h` is pure C11**, opaque handles, additive-only. No C++ types, no enum widening without a version bump. | It is the entire boundary. If it stops being C, the whole interop argument collapses. | `check-layers.sh` compiles a TU that includes it |
| **R5** | **The pump is main-thread — an invariant.** All engine access on the main thread; presentation uses `MainActor.assumeIsolated`, not a detached hop. | There is no pump thread. `assumeIsolated` is correct *because* of this and would become a data race if it ever changed. **If a second loop appears, re-litigate this rule; do not bypass it.** | runtime assert per entry point (debug) |
| **R6** | **Callbacks never block.** Retain the surface, assign it, return. Anything heavier gets queued. | Callbacks run inside the pump, on the main thread. A slow callback stalls rendering *and* input. | code review |
| **R7** | **Upstream ladybird is read-only.** Fork changes confined to `Libraries/LibPort/` and `Tests/LibWebView/TestNative*`, plus their two CMake registration lines. | Every other line is rebase debt that compounds on each upstream sync. | `check-layers.sh` diff guard against the merge-base |
| **R8** | **The pump driver is scheduled in `kCFRunLoopCommonModes`.** | During live resize, menu tracking and drag-tracking, AppKit runs the loop in `NSEventTrackingRunLoopMode`. A default-mode timer does not fire there, so the engine freezes for the whole gesture. | one line in `LadybirdEngine`; plus the menu-hold manual test (see `Traps.md`) |

## Why R2 is the load-bearing rule

It converts "Swift ↔ C++ interoperability" — templates Swift cannot import, `AK::Function`,
`NonnullRefPtr`, exceptions Swift cannot catch — into ordinary C FFI. The measured consequence:
`swiftc` runs with zero interop flags, and the shim dylib has zero ObjC symbols.
