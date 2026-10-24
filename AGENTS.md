# ladybird-mac — agent rules

## Read order, before any task

1. `Documentation/Architecture.md` — the layer map and why the boundary sits where it does
2. `Documentation/Rules.md` — R1-R8, the contract
3. `Documentation/Traps.md` — measured gotchas, each with its fix

The probes in `Extern/ladybird/Tests/LibWebView/TestNative*` are the executable spec for engine
behaviour. Read them before asserting anything about the engine.

## Layers

- `Sources/CLadybirdPort` — the C ABI. Nothing else.
- `Sources/LadybirdBridge` — C ABI only. **No AppKit, no SwiftUI.**
- `Sources/LadybirdEngine` — the **only** target that may touch AppKit/CoreFoundation.
- `Sources/LadybirdUI` — **must not import `CLadybirdPort`.** Go through the Engine.

Violations fail CI. Run `Scripts/check-layers.sh` before committing.

## Probe first

Any claim about engine behaviour must come from an in-tree probe or an existing test you have
actually read. **Do not infer engine behaviour from the Qt code** — Qt is *a* path, not *the* path.
When unsure, write a ~50-line probe in the fork and run it. This is how every rule in `Rules.md`
was derived.

## The fork is read-only

`Extern/ladybird` may only change in `Libraries/LibPort/` and `Tests/LibWebView/TestNative*`, plus
the two CMake registration lines for those. Every other edit is rebase debt and will be reverted.
If `LibWebView` genuinely needs a change, it lands in the fork as a separate upstream-shaped patch,
not folded into a feature commit.

## Cite symbols, never line numbers

Write `ViewImplementation::server_did_paint`, not `ViewImplementation.cpp:293`. Line numbers rot on
every upstream sync; agents following stale line numbers is the most common self-inflicted wound in
this repo.

## Commits

Mirror upstream style: one concern, imperative summary, BSD-2-Clause header on new files (copy the
existing spike files' style). Do not mix a fork change and an app-repo change in one commit.

## Generated code

None yet, deliberately. The spike proved shim generation is a renaming exercise, not a design
exercise, so it can wait. When the ABI passes ~20 functions, the generator becomes a `Scripts/`
tool — and the rule then is: **hand-edit the description, never the output.**

## Do not

- Do not add a second event loop, a display link, or a redraw timer (R3, R5).
- Do not crop or clone a surface-backed bitmap (R1).
- Do not widen the C header's enums or change a struct layout without bumping a version (R4).
- Do not "fix" the engine from this repo.
