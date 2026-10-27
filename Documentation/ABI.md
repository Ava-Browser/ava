# The C ABI boundary

How Swift talks to Ladybird, and why the boundary looks the way it does.

## Why not Swift/C++ interop

Ladybird's C++ API is not usable from Swift directly:

- `AK::Function` is a dependent-type template Swift cannot import.
- Containers are AK's, not `std`'s.
- `NonnullRefPtr` and `ErrorOr` have no Swift mapping.

A translation layer is unavoidable. What *is* avoidable is writing it twice. Because the shim speaks
C and CoreFoundation pointers only (R2), Swift's side is a **plain C module**: no
`-enable-experimental-cxx-interop`, no per-callback thunk allocation, no type mapping table.

All 108 `AK::Function` callbacks in `ViewImplementation` reduce to one shape:

```c
void (*callback)(void* context, uint64_t tab, /* payload */);
```

## The interface

`Extern/ladybird/Libraries/LibPort/ladybird_port.h` — 215 lines, pure C11, one opaque handle
(`LbApp`), 21 functions and one callback struct.

```
                      LbApp  (opaque: the engine application + its tabs)
                        │
   ┌────────────────────┼─────────────────────┐
   │                    │                     │
  app-level          tab-level            teardown
   │                    │                     │
   LbAppCreate          LbTabCreate           LbTabDestroy
   LbAppPump            LbTabLoad             LbAppDestroy
   LbAppStartPump       LbTabGetSurface
   LbAppStopPump        LbTabSetViewport
                        LbTabSendMouse
   LbResolveUserInput   LbTabSendKey
   LbStringFree         LbTabTypeText
                        LbTabTraverseHistory
   dialogs              LbTabCanTraverseHistory
   LbTabAnswerAlert     ─────────────────
   LbTabAnswerConfirm
   LbTabAnswerPrompt
   LbTabAnswerBeforeUnload
```

### `LbCallbacks` — positional and ordered

Ten function pointers plus a context. **Order is the ABI**: the Swift side bakes in field offsets at
compile time, so inserting a field anywhere but the end silently misaligns every callback after it.

```
  ┌───┬──────────────────────────────┬────────────────────────────────────────────┐
  │ # │ field                        │ fired when                                 │
  ├───┼──────────────────────────────┼────────────────────────────────────────────┤
  │ 0 │ context                      │ your pointer, handed back to every callback │
  │ 1 │ on_ready_to_paint            │ a new frame exists (demand-driven, R3)     │
  │ 2 │ on_url_change                │ the displayed URL changed                   │
  │ 3 │ on_load_finish               │ a navigation finished                       │
  │ 4 │ on_title_change              │ the document title changed                  │
  │ 5 │ on_loading_state_change      │ started/stopped loading                     │
  │ 6 │ on_favicon_change            │ icon changed; NULL data means cleared       │
  │ 7 │ on_request_alert             │ alert(), blocking                           │
  │ 8 │ on_request_confirm           │ confirm(), blocking                         │
  │ 9 │ on_request_prompt            │ prompt(), blocking                          │
  │10 │ on_request_before_unload     │ leave-page prompt, blocking                 │
  └───┴──────────────────────────────┴────────────────────────────────────────────┘
```

**This layout has already caused a real bug.** A build tree 737 commits behind the pin had only
fields 1–3 and 7–10, so every field from 4 up was read from the wrong offset: `on_title_change` was
invoked as `on_request_alert`, and favicons could never appear. It did not crash, because several of
those signatures happen to be compatible. `Scripts/build.sh` now refuses to build against a dylib
whose source tree is not the pinned commit.

> Adding a callback means appending it at index 11 and bumping the header's version. Never insert.

### The four blocking dialogs

These are the only callbacks the engine **waits on**. The page's script is stopped inside WebContent
until one is answered:

```
  WebContent                    LibPort                   your app
      │                            │                         │
  alert("hi") ──▶ on_request_alert ──────────────▶  show a sheet
      │  (page stopped)            │                         │
      │                            │◀── LbTabAnswerAlert ────┘
      │◀───────── continue ────────┘
```

Install all four or none. Absent is safe (the engine answers itself). **Present-but-silent hangs the
page** — the app looks alive while nothing responds. That asymmetry is why `LadybirdBridge` checks
`installsAllDialogs` before wiring any of them.

## Memory ownership

Three rules, and they are the whole contract:

```
 strings      borrowed for the duration of the callback; copy if you keep it
              (the header says so per-parameter; LbStringFree exists for
               LbResolveUserInput, which returns owned memory)

 surfaces     borrowed. Retain → assign to layer.contents → release.
              All inside the callback. The frame swap reclaims it on return (S5).

 app / tab    owned by you. Create and destroy in pairs; ids can go stale,
              so every entry point tolerates an unknown tab id.
```

Rule R1 forbids cropping or cloning a surface-backed bitmap: `Bitmap::cropped()` calls `clone()`,
which trips a `VERIFY` because an IOSurface's pitch need not be `width * 4`. Crop with
`CALayer.contentsRect` instead.

## Where the code lives

| Concern | File |
|---|---|
| The interface | `Extern/ladybird/Libraries/LibPort/ladybird_port.h` |
| Its implementation | `Extern/ladybird/Libraries/LibPort/ladybird_port.cpp` |
| Swift module wrapper | `Sources/CLadybirdPort/` (a modulemap and a header, 10 lines) |
| Trampolines & `Unmanaged` | `Sources/LadybirdBridge/Port.swift` |

The only `Unmanaged<>` in the codebase is in `LadybirdBridge` — that is rule S1, machine-checked.

## Testing the boundary without a window

`Tests/LibWebView/TestNative*` in the fork are the executable spec for engine behaviour. They link
`liblagom-port` directly and drive it as a C program, so they need no Swift and no AppKit. **Read them
before asserting anything about the engine.** On this side, `Tests/LadybirdBridgeTests` covers the
Swift wrappers with no engine at all.

## Traps specific to this boundary

- Importing the C module does **not** link the dylib. Nothing links until a Swift file references a
  symbol; by then the error is a bare `library 'lagom-port' not found`.
- Narrow UTF-16 to bytes with `to_byte_string()`. The header speaks bytes and the engine speaks
  UTF-16; getting it wrong compiles either way.
- `LbAppPump` uses `PollForEvents` (`poll(0)`) because `WaitForEvents` blocks forever in a
  cooperative host.

See [Traps](Traps.md) for the full, measured list.
