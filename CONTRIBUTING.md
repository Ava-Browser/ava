# Contributing to Ava

Ava is an experimental native macOS browser powered by Ladybird. Small, focused
contributions are welcome. Discuss larger features in an issue before implementing them.

## Get started

Follow the [README](README.md) to clone with submodules, build the engine, and run Ava.
Use the pinned engine commit; do not update the submodule as an incidental part of a UI change.
The engine fork is [Ava-Browser/ava-engine](https://github.com/Ava-Browser/ava-engine);
its local submodule path remains `Extern/ladybird`.

Before changing code, read these in order:

1. [Architecture](Documentation/Architecture.md)
2. [Contract rules](Documentation/Rules.md)
3. [Measured traps](Documentation/Traps.md)

The architecture document includes historical spike notes. The current package manifest,
submodule pin, and README describe the build today.

## Check your change

After building the real engine:

```bash
swift build
swift test
# Requires Bash 4+; use /opt/homebrew/bin/bash on Apple Silicon.
bash ./Scripts/check-layers.sh
```

CI compiles the Swift application and test targets and checks boundaries. It does not
link or run the engine or tests. For rendering or input changes, run the relevant
`TestNative*` probes in the engine checkout and report exactly which checks you ran.
Some probes require an interactive macOS desktop.

Keep the layer boundaries intact. In particular, UI must not import `CLadybirdPort`,
and bridge code must not import AppKit or SwiftUI. See the contract for threading
and surface-lifetime requirements.

## Pull requests

- Keep one concern per change, with an imperative commit summary.
- Include reproduction steps for fixes and a small regression test for nontrivial logic.
- Include screenshots for visible UI changes, with private information removed.
- Preserve copyright and license notices; use the existing BSD-2-Clause header on new source files.
- Keep app changes and engine-fork changes in separate commits.
- Do not change upstream engine files beyond the permitted port/probe paths.
  Any necessary upstream-shaped patch needs separate review.
- State what you tested and what you did not test.

## Reports

Search existing issues first. Include macOS and Swift versions, the app and engine
commit hashes, and minimal reproduction steps. Remove browsing history, cookies,
credentials, and other personal data from logs and screenshots.

See [SECURITY.md](SECURITY.md) for vulnerability reports.
