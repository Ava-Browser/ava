# Measured traps

Each of these cost real time during the spike. None of them are guessable from reading the API.

## Engine

**`EventLoop::pump()` defaults to blocking.**
`Core::EventLoop::WaitMode::WaitForEvents` will `poll(-1)` forever when no timer is pending. There
is no `DontWaitForEvents`. Use `PollForEvents` (`poll(0)`) in a cooperative host, or the host
hangs. *Fix: `LbAppPump` always passes `PollForEvents`.*

**A settled page emits exactly one paint.**
The compositor publishes on change, not continuously. `on_ready_to_paint` means "a new frame is
available", not a frame tick. *Fix: to prove liveness, load a second page; never wait for N paints
after one load.*

**Paint #1 arrives before `on_load_finish`.**
It is the early blank paint. Asserting "the page rendered" on paint #1 lets an empty view pass.
*Fix: key render assertions on a paint that arrives strictly after load finished.*

**Navigating before the initial `about:blank` load finishes drops the navigation.**
*Fix: wait out the first `on_load_finish` before loading anything.*

**`about:srcdoc` counts as an `on_load_finish`.**
*Fix: navigation assertions must compare URLs or load counts, never "did another load happen".*

**Wheel events are consumed by the compositor, not forwarded to WebContent.**
The scroll still lands and is observable, but no WebContent-side callback fires. *Fix: observe the
page's own state (a `scroll` listener), never a callback.*

**A headless viewport is in device pixels.**
900×600 at 2× is 1800×1200. Passing CSS sizes straight through renders the page at half scale.
*Fix: `LbTabSetViewport` takes CSS size + ratio and multiplies.*

**`URL::serialize()` is UTF-16.** Any `char*` callback built from an AK string must narrow with
`to_byte_string()` first. It compiles either way, so this fails at runtime.

**`ViewImplementation`'s bitmap members are `protected`.**
`m_front_bitmap`, `m_backup_shared_image_buffer`, `m_backup_bitmap_size` are only reachable by
subclassing. Copy `WebContentView::current_paintable()` verbatim — its `m_has_usable_bitmap` gate
and backup fallback are load-bearing; checking only `shared_image_buffer != nullptr` hands you a
stale bitmap mid-swap.

**Absent is safer than present-but-silent.**
Uninstalled callbacks get auto-answered by the engine (`WebContentPage` checks the `Function`
for emptiness and replies with a default); an installed callback that is never answered hangs
forever. Wire only what you actually answer — do not install defensive stubs. Only four
callbacks genuinely block the page (`Page::did_request_alert` spins the dialog loop):
`on_request_alert` → `alert_closed()`; `on_request_confirm` → `confirm_closed(false)`;
`on_request_prompt` → `prompt_closed(OptionalNone {})` (empty string is OK-with-no-text, a
different outcome); `on_request_before_unload` → invoke the given `Function<void(bool)>`
**with true meaning ALLOW navigation, not block**. Also `on_request_external_url_confirmation`'s
bool means "open it?", not "rejected?". Everything else is a notification or a leaked request,
not a deadlock. (Audit: `~/Documents/browsers/callback-audit.md`; read-verified, not yet
run-verified — the unanswered-alert probe is still owed.)

## Tooling

**`--headless=screenshot` needs `--screenshot-delay=6`.**
The default 1 s yields a blank white PNG. Every colour comparison against it is then meaningless.

**The R4 header check must compile a TU that includes the header.**
Checking the header file alone trips `-Wpragma-once-outside-header` and reports a false failure.

**The R2 ObjC check must strip comments first.**
The header discusses `objc_msgSend` in prose; a naive grep matches the discussion. Preprocess
(`clang -x c++ -E -P`) before grepping.

**A green guard can audit a tree the build never read.**
`Scripts/build.sh` builds from `Extern/ladybird/Build/release`, which is usually a *symlink* to a
second checkout (reusing a 3 GB build tree beats a multi-hour rebuild). That tree records its own
`CMAKE_HOME_DIRECTORY`. So `check-layers.sh` can pass over `Extern/ladybird` while the dylib came
from somewhere else entirely. Measured state at the time of writing: submodule pinned at
`bef0ffa5be`, build tree at `c0af4465f6` — a real divergence, not a hypothetical. *Fix: the guard
compares the build tree's `CMAKE_HOME_DIRECTORY` against the checkout it audits, fails if the
sources differ, and warns if they merely happen to agree.*

**A stale remote-tracking ref will make you doubt a real push.**
`git cat-file -t <sha>` against a submodule fails until `git fetch` — the ref is local and stale,
the object genuinely absent. *Fix: fetch before concluding a push did not happen.*

**The R7 fork-diff guard must diff against the merge-base, not `upstream/master`.**
Otherwise every commit upstream has landed since this fork's HEAD looks like a local change and the
guard reports hundreds of irrelevant files. Measured: `upstream/master` reported 300 files and
13,649 deletions; the merge-base reports 4 paths.

**Importing a C module does not link its library.**
`import CLadybirdPort` compiles fine with no `linkerSettings` at all, because nothing references a
symbol. The link only happens when Swift touches one. *Fix: `LadybirdEngine` carries
`-L Extern/ladybird/Build/release/lib -llagom-port`, and `Engine.swift` touches a symbol so the
dependency is real. Verify with `otool -L`.

**The fork builds for macOS 14.4** (`CMAKE_OSX_DEPLOYMENT_TARGET`). A package targeting `.v14`
links with a "built for newer version" warning. *Fix: `platforms: [.macOS("14.4")]`.

## Verified non-issues

**Pump-during-live-drag is safe.** The freeze-during-gesture bug is real — a default-mode timer
starves completely in `NSEventTrackingRunLoopMode` — and CommonModes avoids it. Measured two ways:

- Synthetic control: two timers on one run loop, 0.3 s of tracking mode → common-mode 151 ticks,
  default-mode **0** ticks.
- `TestNativeEventLoop` drives the real tracking mode after the main phase:
  **150 pumps in 301 ms** of `NSEventTrackingRunLoopMode`, against ~150 expected at a 2 ms timer.
  The probe now asserts this (`tracking-mode pump: true`), so a regression fails the build rather
  than freezing a user's window.

No manual menu-holding test is needed. Do not "simplify" the timer to the default mode.

## Tooling, continued

**A stale window outlives `pkill` and answers CGWindow queries with old geometry.**
After killing and relaunching, a `CGWindowListCopyWindowInfo` query can still return the previous
run's window (same owner name, same PID-recycled process), so the app appears to ignore a resize,
a `defaultSize`, or a window-style change that is in fact applied. Measured the hard way: 40 minutes
concluding `defaultSize` was broken when it was working, because every reading came from a dead
window still reporting 1200x800. *Fix: print the frame from inside the process
(`NSApp.windows.map(\.frame)`), not from outside. Trust the app's own report.*

**A bare positional command-line argument stops SwiftUI creating a window at all.**
`LadybirdMac https://example.com` launches, runs, and never creates a window: AppKit reads the
argument as a document-open request. The process looks alive, which sends you looking for a
rendering or activation bug. *Fix: require a `--url` flag; never pass a bare URL.* This is why
`--url` exists rather than a positional argument.
