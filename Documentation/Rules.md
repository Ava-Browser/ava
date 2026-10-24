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

---

# Swift layer discipline

R1–R8 govern the boundary and below. **S1–S6 govern everything above it.** Their violations do
not look like Swift bugs — they look like *engine* bugs, which makes them expensive to debug.

| # | Rule | Why | Enforcement |
|---|---|---|---|
| **S1** | **`Unmanaged` and raw `ctx` pointers exist only in `LadybirdBridge`.** Upward layers see typed objects — `LbTab`, `LbSurface`, `LbError` — never an opaque context pointer. | `Unmanaged` is where every lifetime bug in this architecture would live. Confining it means auditing one target, not the whole repo. | `check-layers.sh` grep |
| **S2** | **`LadybirdEngine`'s public API is `@MainActor`-annotated.** R5's main-thread invariant goes in the type system, not in comments. | A comment can be ignored silently; the compiler cannot. An unannotated entry point is now a type error at the call site. | compiler |
| **S3** | **No `DispatchQueue` or `Task.detached` anywhere in `Sources/`.** No exceptions, no whitelist. | The entire design — R5's invariant, R2's race-free surface hand-off — rests on there being exactly one thread. A hidden hop reintroduces every race the design was built to avoid. If a genuine need appears, re-litigate S3 like R5 says; do not add a "temporary" async call. | `check-layers.sh` grep |
| **S4** | **Errors cross the Bridge boundary as `throws`, never as untyped codes, and never as crashes.** A `VERIFY` abort from the engine must never surface above Bridge. | Swift callers should not need to learn the C API's error convention; a crash crossing the boundary is indistinguishable from an engine bug at 2 a.m. | code review |
| **S5** | **No caching `IOSurface` refs across pump turns.** Retain, assign to `layer.contents`, release — inside the callback. | The shim borrows the ref; frame swaps reclaim it. Holding one past the callback's turn is the only UAF still reachable in this design (R2 eliminated the rest). | code review |
| **S6** | **C struct literals are built via helper functions — one per struct.** Field-order refreshes against `InputEvent.h` then live in exactly one place. | AK headers reshuffle on upstream syncs; the designated-initializer-order trap (see `Traps.md`) is survivable once, not once per call site. | code review |

Formatting is a formatter's job, not this document's. When `Sources/` holds real code, add a
`swift-format lint --strict` step to CI — and do not write a prose style guide to go with it.
