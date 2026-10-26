# Ava

A native macOS browser powered by the [Ladybird](https://ladybird.org) web engine, built with Swift and SwiftUI.

Ava is exploring a calmer way to browse: vertical tabs, persistent Spaces, and native Mac controls. Inspired by the spatial browsing ideas of Arc and Zen, Ava is an independent project—not affiliated with either browser or the Ladybird project.

**Early development.** Ava runs locally, but it is not ready to replace your everyday browser. Expect bugs, incomplete features, and website compatibility limitations. There are no signed releases yet.

## What works today

- Native browser window with vertical tabs and back/forward navigation
- Spaces with Essential, pinned, and normal tabs
- Persistent tab organization and lazy restoration of saved tabs
- Mouse, keyboard, and scrolling input
- JavaScript alert, confirm, prompt, and leave-page dialogs
- Native Settings for appearance and new-tab destination

Spaces currently organize tabs; they **do not provide separate login or storage containers**. Container support is experimental and is not available as a finished feature.

## How it is built

Ava provides the Mac interface; Ladybird handles web content, JavaScript, networking, and rendering. A small C interface connects the C++ engine to the Swift application. Finished page frames are displayed through macOS IOSurfaces.

The app and engine live in separate repositories, with the engine fork pinned under `Extern/ladybird`. This keeps Mac interface development separate from engine changes.

## Build and run

### Requirements

- macOS 14.4 or later
- Xcode command-line tools with Swift 6 or later
- The dependencies required by Ladybird's [build instructions](https://github.com/LadybirdBrowser/ladybird/blob/master/Documentation/BuildInstructionsLadybird.md)

The engine's first build can take several hours and requires substantial disk space.

```bash
git clone --recurse-submodules https://github.com/Ava-Browser/ava.git ava
cd ava

# Build the engine and its dependencies.
(cd Extern/ladybird && ./Meta/ladybird.py build --build-dir Build/release)

# Build the bridge and Swift application.
./Scripts/build.sh

# Launch the local development app.
./Scripts/run.sh
```

The runner creates `.build/Ava.app` and configures development paths for the engine's libraries and helper processes. This is a local development bundle, not a self-contained distributable application.

### Checks

```bash
swift test
bash ./Scripts/check-layers.sh
```

The layer guard works with macOS's bundled Bash. GitHub Actions compiles the application and test targets and checks layer boundaries; it does not link the engine or execute tests.

The layer check validates architectural boundaries and the allowed changes to the engine fork. Native engine probes live under `Extern/ladybird/Tests/LibWebView/TestNative*`; some open windows and require an interactive desktop session.

## Project documentation

- [Architecture](Documentation/Architecture.md) — modules and the engine boundary
- [Contract rules](Documentation/Rules.md) — threading, presentation, and layer constraints
- [Spaces design](Documentation/TDD-Spaces.md) — persistent organization and planned container support
- [Settings requirements](Documentation/PRD-Settings.md) — scope of native preferences
- [Development notes](Documentation/Traps.md) — known pitfalls and lessons from testing
- [Agent instructions](AGENTS.md) — operating rules for coding agents

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Bug reports should include your macOS version, commit, and reproduction steps, with private browsing data removed.

For vulnerabilities, follow [SECURITY.md](SECURITY.md); do not post sensitive details in public issues. Ava is experimental and should not be used for sensitive browsing.

## License

The application source is licensed under [BSD-2-Clause](LICENSE), consistent with its existing source headers. Ladybird and bundled dependencies retain their own licenses and notices; see the engine checkout's `LICENSE` and third-party notices.

## Project and credits

Find the project at [Ava Browser on GitHub](https://github.com/Ava-Browser).

Ava would not be possible without the Ladybird engine and its contributors. Upstream source headers and license notices are retained; engine and third-party licensing information is included in the engine checkout.
