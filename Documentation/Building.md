# Building

Three scripts, three jobs. Run them in the order below the first time.

```
  ┌────────────────────────────────────────────────────────────────────────┐
  │ 1. build the engine            (hours, once)                          │
  │    cd Extern/ladybird && ./Meta/ladybird.py build --build-dir Build/release
  └───────────────────────────────┬────────────────────────────────────────┘
                                  ▼
  ┌────────────────────────────────────────────────────────────────────────┐
  │ 2. ./Scripts/build.sh          (seconds)                              │
  │    builds the LibPort shim, checks the ABI pin, then `swift build`     │
  └───────────────────────────────┬────────────────────────────────────────┘
                                  ▼
  ┌────────────────────────────────────────────────────────────────────────┐
  │ 3. ./Scripts/run.sh            (instant)                              │
  │    wraps the binary in .build/Ava.app and launches it                  │
  └────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼  ...and when you want something to hand out:
  ┌────────────────────────────────────────────────────────────────────────┐
  │ 4. ./Scripts/package.sh        (minutes)   → Ava-<version>.dmg         │
  └────────────────────────────────────────────────────────────────────────┘
```

## Requirements

- macOS 14.4 or later
- Xcode command-line tools with Swift 6
- Ladybird's [build dependencies](https://github.com/LadybirdBrowser/ladybird/blob/master/Documentation/BuildInstructionsLadybird.md)
- Disk: the engine build tree is several GB. The packaged app is ~227 MB.

## Step 1 — the engine

```bash
git clone --recurse-submodules https://github.com/Ava-Browser/ava.git ava
cd ava
(cd Extern/ladybird && ./Meta/ladybird.py build --build-dir Build/release)
```

This is the long one: vcpkg plus the whole engine. Hours, not minutes.

**Don't want to do it twice?** Reuse an existing tree by symlinking instead:

```bash
ln -s /path/to/existing/ladybird/Build/release Extern/ladybird/Build/release
```

That is a supported and common setup — and the source of the most expensive mistake in this repo.
Read the next section.

### The symlinked build tree trap

A build tree records which checkout it was made from (`CMAKE_HOME_DIRECTORY` in `CMakeCache.txt`).
When you symlink to a tree from a *different* checkout, that checkout can be at a different commit
than the pin — and then the shim you link was built from different source than the header Swift
compiles against.

```
   Extern/ladybird  (pinned at A)          build tree  (read-only link)
   ladybird_port.h  ── LbCallbacks(A) ──┐
                                        │   CMakeCache → checkout at B
                                        └──▶ liblagom-port.dylib built from LbCallbacks(B)
                                              │
                                              ▼
                                    every callback reads a wrong slot
```

`LbCallbacks` is positional. If B is older than A, field 4 is `on_request_alert` in the dylib but
`on_title_change` in the header: titles fire the alert handler, favicons never appear, and it may not
crash because some signatures coincide.

`Scripts/build.sh` now compares the pin against the commit of the tree **CMake actually read**, and
refuses with both hashes. To fix it:

```bash
git -C <that checkout> fetch origin ava-port
git -C <that checkout> checkout --detach <the pinned sha>
# then rebuild — a large jump under Libraries/ is hours
```

A matching separate checkout is fine and prints a `note:` so you know it happened.

## Step 2 — the app

```bash
./Scripts/build.sh              # builds shim + app
./Scripts/build.sh --swift-only # skips the shim build, keeps every check
```

What it does, in order:

1. Fast-forwards `Extern/ladybird` only when that is a no-op or a clean fast-forward; refuses
   otherwise rather than resetting the pin under you.
2. Verifies the build tree's commit matches the pin (see above), unless `--swift-only`.
3. Builds the `LibPort` target and stamps the commit it was actually built from.
4. Checks `liblagom-port.dylib` exists, then runs `swift build`.

## Step 3 — run it

```bash
./Scripts/run.sh
```

It creates `.build/Ava.app` (a real bundle with an `Info.plist`, with a symlink to the built binary),
exports `LADYBIRD_BINARY_PATH` and `DYLD_LIBRARY_PATH` for the engine, and launches it.

Why a bundle at all? A bare Mach-O cannot become the active application on current macOS: it launches,
creates a window, and that window never takes focus. Wrapping the same binary in a bundle is what makes
it a regular app. Measured, not inferred.

## Step 4 — package

```bash
./Scripts/package.sh                                    # ad hoc signed, runs locally
./Scripts/package.sh --identity "Developer ID Application: ..."
```

Self-contained `.app` plus a DMG. Details, including what is *not* verified, are in
[Packaging](Packaging.md).

## Keeping the engine current

```bash
git -C Extern/ladybird fetch origin ava-port
git -C Extern/ladybird checkout --detach <new-sha>
git add Extern/ladybird && git commit            # advance the pin deliberately
./Scripts/build.sh
```

Advance the pin **separately** from unrelated app changes, and see
[Upstream sync review](Upstream-Sync-Review.md) when the advance comes from Ladybird upstream rather
than this fork.

## Checks

```bash
swift test                        # needs a linked engine
bash ./Scripts/check-layers.sh    # rules + layer boundaries, no engine needed
bash ./Scripts/test-package.sh    # packaging, no engine needed
```

`check-layers.sh` also reports when your build tree is a separate checkout, and fails if the sources
have diverged — that is the guard that catches the trap above before it reaches a binary.

CI compiles the app and tests, runs both shell checks, and does **not** build the engine or execute
tests. A separate `package` job builds a real DMG only when the repository variable
`AVA_ENGINE_BUILD_DIR` names a prebuilt engine; otherwise it is skipped rather than faked.

## When something is wrong

| Symptom | Likely cause |
|---|---|
| `library 'lagom-port' not found` | shim not built, or wrong `--swift-only` |
| Window opens but never takes focus | run via `run.sh`, not the bare binary |
| Titles/loading/favicons never fire | ABI misalignment — see the symlink trap |
| Page renders in a fallback font | test mode is set; it overrides font matching entirely |
| `SIMD`/ABI crash at startup | dylib from a different commit than the header |
| Frozen during window resize | pump not in `kCFRunLoopCommonModes` |
