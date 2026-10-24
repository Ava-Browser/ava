# ladybird-mac

A native macOS frontend for the [Ladybird](https://ladybird.org) browser engine, in Swift.

Ladybird's Qt frontend is one *client* of `LibWebView`, not a requirement: the engine exposes a
toolkit-agnostic callback API and publishes frames as shared IOSurfaces. This repo replaces that
client with Swift/SwiftUI, talking to the engine through a small C ABI.

```
Extern/ladybird/Libraries/LibPort/ladybird_port.h   ← the entire boundary: 79 lines of C11
```

## Status

The architecture is proven end to end — a Swift app has rendered a real page, taken input,
resized, and quit cleanly through this ABI. What exists today is the scaffolding plus a link test.

See `Documentation/Architecture.md` for the layer map and the known gaps (packaging is the next
real unknown; everything else is product work).

## Quick start

The fork's work lives on branch `native-port` — check it out before building:

```bash
git -C Extern/ladybird checkout native-port
```

```bash
git clone --recurse-submodules <this-repo>
cd ladybird-mac

# Build the fork once (hours on a cold tree):
cd Extern/ladybird && ./Meta/ladybird.py build --build-dir Build/release && cd ..

./Scripts/build.sh    # shim (CMake) + Swift package
./Scripts/run.sh      # dev run; exports LADYBIRD_BINARY_PATH and DYLD_LIBRARY_PATH
```

`Scripts/run.sh` sets dev-only environment for finding helper processes. Production replaces both
variables with an `.app` bundle and `@loader_path` rpaths — see `Documentation/Architecture.md`.

## Documentation

| File | Contents |
|---|---|
| `Documentation/Architecture.md` | Layer map, why the boundary is where it is, known gaps |
| `Documentation/Rules.md` | R1–R8, the contract rules, and what each one prevents |
| `Documentation/Traps.md` | Measured engine gotchas, each with its fix |
| `Documentation/Decisions/` | Why the foundation looks like this (two repos, SwiftUI, C ABI, one loop) |

`AGENTS.md` covers how to work in this repo (read order, layer rules, fork discipline).

## The fork

`Extern/ladybird` is upstream plus exactly one added directory (`Libraries/LibPort/`) and the
probes under `Tests/LibWebView/TestNative*`. Nothing else may change there.

The probes are the regression net for engine behaviour and the executable spec for anything an
agent might otherwise guess from the Qt frontend:

```bash
Extern/ladybird/Build/release/bin/TestNativePresentation   # paint + IOSurface -> CALayer
Extern/ladybird/Build/release/bin/TestNativeInput          # wheel scroll + click navigation
Extern/ladybird/Build/release/bin/TestNativeEventLoop      # LibCore pumped from CFRunLoop
```

## Checks

```bash
./Scripts/check-layers.sh    # R2, R3, R4, R7 + layer boundaries
swift build --build-tests && swift test
```
