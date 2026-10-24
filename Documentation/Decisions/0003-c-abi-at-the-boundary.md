# 0003 — The boundary is a C ABI, not Swift/C++ interop

**Status:** accepted
**Date:** 2026-10-24

## Context

Swift cannot import Ladybird's C++ API. Measured against Swift's documented interop limits:

| Swift interop constraint | Ladybird reality |
|---|---|
| `std::vector`, `std::optional`, `std::string` supported | AK types only — `Vector` 24×, `Optional` 92×, `String` 97× in `ViewImplementation.h` |
| Class/struct **templates not available** | `AK::Function<Out(In...)>` — dependent-type template, explicitly unsupported |
| `std::function` supported | `AK::Function` carries all **108** callbacks in `ViewImplementation` |
| C++ exceptions cannot be caught by Swift | `VERIFY`/`MUST` abort paths throughout |
| — | `NonnullRefPtr` 18×, `RefPtr` 76× — no interop mapping |

AK is deliberately not `std`, so the entire interop fast path is unavailable. A translation layer
was mandatory regardless of the answer here.

## Decision

A **pure C11** boundary (`ladybird_port.h`, 79 lines), with the shim in plain C++ and
CoreFoundation containing **zero Objective-C**.

Three properties carry it:

- **Opaque handles and C function pointers.** No C++ type crosses the line.
- **The surface crosses as a borrowed `IOSurfaceRef`** (`void*`) plus painted/surface sizes. Pixels
  are never copied or cropped.
- **All ObjC lives in the app repo.** The shim hands out the ref; Swift retains it and owns every
  `CALayer` and `NSWindow`.

## Consequences

Measured, not predicted:

- `swiftc` runs with **zero interop flags** — no `-enable-experimental-cxx-interop`, no bridging
  header. Swift imports it as an ordinary C module.
- The shim dylib has **0 ObjC symbols** (`nm -u | grep -cE 'objc_|_OBJC_CLASS'` → `0`).
- **Trampolines need no per-callback allocation.** One `Unmanaged.passUnretained(target).toOpaque()`
  carries the context; each callback is a top-level `let` with `@convention(c)` and no capture
  list. Going from 5 to 108 callbacks costs 108 static function pointers, nothing per instance.

This is why the 108-callback table above stays in the docs as *motivation* while the answer is
"route around the question": the best translation layer is the one you never write.

## Alternative rejected

Wrapping `ViewImplementation` directly and writing per-method Swift glue. It would still have
needed a shim (for the AK types), but with far more surface: 108 callbacks and hundreds of methods,
each becoming bespoke translation instead of one mechanical shape.
