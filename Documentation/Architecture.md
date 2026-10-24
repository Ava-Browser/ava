# Architecture

## Two repos, one boundary

```
┌──────────────────────────────┐        ┌─────────────────────────────────┐
│ ladybird (fork)              │        │ ladybird-mac (this repo)        │
│                              │        │                                 │
│ Libraries/                   │        │ Sources/LadybirdUI    SwiftUI   │
│ Services/                    │        │ Sources/LadybirdEngine  AppKit  │
│ Tests/LibWebView/TestNative* │  C11   │ Sources/LadybirdBridge  Swift   │
│ Libraries/LibPort/  ◀────────┼───────▶│ Sources/CLadybirdPort   module  │
│                              │  ABI   │                                 │
└──────────────────────────────┘        └─────────────────────────────────┘
        upstream + one additive directory          everything above the ABI
```

The fork is a **dependency you happen to control**, not a workspace. The app repo references it
via `Extern/ladybird` (a submodule once the fork has a remote; a symlink during bring-up). Pins
advance deliberately, like vcpkg pins advance in ladybird — never incidentally.

## Layers, and why the boundary is where it is

**`CLadybirdPort`** — the C ABI and nothing else: a forwarding header onto
`Extern/ladybird/Libraries/LibPort/ladybird_port.h`. No Swift, no logic.

The implementation builds in the fork as **`liblagom-port.dylib`** (tree naming convention), and
`LadybirdEngine` links it from `Extern/ladybird/Build/release/lib`. Note that importing the module
does **not** link it — see `Traps.md`.

**`LadybirdBridge`** — thin Swift wrappers. Owns the `@convention(c)` trampolines, the single
`Unmanaged<>` context, and error mapping. **Must not import AppKit or SwiftUI** — it is testable
with no window and no engine.

**`LadybirdEngine`** — the only target permitted to touch AppKit/CoreFoundation. Owns the pump
(`CFRunLoopTimer` in CommonModes), the session/tab model, event routing, and the
surface→`CALayer` policy.

**`LadybirdUI`** — SwiftUI chrome. Knows `LadybirdEngine`'s model objects, never the C ABI.

The rule has teeth because SwiftPM target dependencies make most violations compile errors: UI
cannot `import CLadybirdPort` because it does not depend on it. The rest are greppable in
`Scripts/check-layers.sh`.

## Why the C ABI is 79 lines and not 300

Ladybird's C++ API is unusable from Swift directly: `AK::Function` is a dependent-type template
Swift cannot import, the containers are AK's rather than `std`'s, and `NonnullRefPtr` /
`ErrorOr` have no mapping. A translation layer is unavoidable.

What *is* avoidable is writing it twice. Because the shim speaks C and CF pointers only (rule R2),
Swift's side is a plain C module — no interoperability flags, no type mapping, no per-callback
thunk allocation. The 108 `AK::Function` callbacks in `ViewImplementation` all reduce to the same
shape: `void (*)(void* ctx, …)` plus one static `@convention(c)` function pointer.

The spike proved this end to end: real page rendering, input, resize and clean shutdown through a
79-line header.

## The event loop

There is exactly one loop, and it is the main thread's. `CFRunLoopRun()` owns the thread; a 2 ms
`CFRunLoopTimer` registered in `kCFRunLoopCommonModes` gives LibCore one `PollForEvents` iteration
per tick. It is not two loops merged — it is one loop lending ticks to the other.

This is deliberate and should not be "improved" into a threads design:

- No threads means no `deferred_invoke` wakeup contract, no `@MainActor` hop, no join dance.
- The IOSurface borrow-then-retain is race-free **by construction**: on two threads there is a
  window between the shim handing out the ref and Swift retaining it, during which a frame swap
  could drop the surface.
- LibCore's loop is not thread-safe by design; pinning it to main removes a bug class rather than
  managing one.

See `Rules.md` R5 for the invariant, and `Documentation/Decisions/` for the reasoning in full.

## Known gaps

Not architecture risks; each is product work with a defined shape.

- **Packaging.** Helper process placement, bundle-relative resource root, codesigning entitlements
  for Mach-port helper spawn, signing the shim. Nothing here has been tested as a signed `.app`.
- **Multi-tab.** Only one tab was ever created in the spike; teardown ordering is constrained by it.
- **Idle CPU.** The 2 ms pump is ~500 wakeups/sec forever. Replace with a `CFRunLoopSource`
  signalled from the event loop's wake pipe, clamped to the nearest timer deadline.
- **The resized/dirty-window Cmd-Q flow** (teardown was tested via `applicationWillTerminate`).

## Status of the fork

The work lives on branch `native-port` in `Extern/ladybird`, one commit on top of upstream
`0203ab20ca`: `LibPort` plus the three probes, 8 files, additive only. It is **not pushed** — the
fork has no remote yet, so `Extern/ladybird` is a symlink rather than a submodule. When the fork
gets a remote, swap the symlink for a submodule pinned to that commit; nothing else needs to
change.
