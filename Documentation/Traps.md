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
not a deadlock. All four blocking rows were run-verified by the page-self-reporting fixture;
the private callback-audit scratch document is not a reproducible public artifact.

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

**A build stamp records an intention, not a build.**
`build.sh` used to write the *pinned* commit into `.libport-pin` and then compare the pin against that
stamp — so it verified a number it had just written, and passed whenever the two matched, regardless of
what `cmake --build` actually read. Measured: the stamp said `4b042dd` while the dylib had been compiled
from a checkout 737 commits behind at `de81058a39b`. `LbCallbacks` is positional, so every field from 4
up was read from the wrong slot — `on_title_change` invoked as `on_request_alert` — and because several
of those signatures coincide the app ran, with titles wired to the wrong handler and favicons silently
dead. The symptom presented as "a merged feature is missing from the build", and the pin was correct the
whole time. *Fix: compare the pin against the `CMAKE_HOME_DIRECTORY` checkout's HEAD, stamp the commit
that was actually built, and print a `note:` when a separate checkout is in use rather than passing
quietly.* Only `check-layers.sh` caught this before; now both do.

**A new worktree never shares `Build/release`.** Git shares submodule *history* between worktrees
(hardlinked objects) but not the build tree, so a fresh worktree costs a cold engine build however
cheap its checkout was. The one sanctioned shortcut is a `Build/release` symlink to another checkout,
and the provenance check above is what makes it safe: it compares the pin against the checkout
`CMAKE_HOME_DIRECTORY` actually names, so a symlink at the wrong commit is refused rather than
silently compiled.

**A stale remote-tracking ref will make you doubt a real push.**
`git cat-file -t <sha>` against a submodule fails until `git fetch` — the ref is local and stale,
the object genuinely absent. *Fix: fetch before concluding a push did not happen.*

**A worktree inherits the submodule pin but none of its bytes.**
`git worktree add` checks out the superproject commit, so `git rev-parse HEAD:Extern/ladybird`
reports the correct pin immediately — while `Extern/ladybird/` is an empty directory with no
`.git`. `git submodule status` prints a leading `-` (`-4b042dd... Extern/ladybird`), which is the
only signal that nothing is checked out. A build or `check-layers.sh` in that worktree then fails
for a reason that looks nothing like a missing submodule.
*Fix: `git -c protocol.file.allow=always submodule update --init Extern/ladybird` in each new
worktree. Never copy `Extern/ladybird/.git` from another checkout to skip this.*

**A copied submodule `.git` file can make Git inspect a different worktree than the bytes you build.**
An Orca worktree inherited `Extern/ladybird/.git` pointing at the main checkout's module gitdir,
then that gitdir's `core.worktree` was repointed at Orca. In the main checkout, `git status`,
`git diff-files`, and even `git restore` therefore operated on Orca's bytes while `clang`, SwiftPM,
and `diff` read the main bytes. Same HEAD plus clean status was true — for the wrong directory.
*Fix: each outer worktree gets isolated submodule git metadata. Verify both
`git -C Extern/ladybird rev-parse --show-toplevel` and raw file hashes; never infer byte identity
from HEAD/status alone. Preserve both trees before repairing a pointer.*

The mechanism, measured on git 2.56: a worktree's submodule clone lives at
`.git/worktrees/<id>/modules/Extern/ladybird`, and its working copy's `.git` file points there
(`gitdir: ../../../.git/worktrees/<id>/modules/Extern/ladybird`). Objects are **hardlinks** into the
main checkout's `.git/modules/Extern/ladybird` — same inode, so the shared engine history costs no
extra disk — while HEAD, refs, index and config are per-worktree files. That directory is what
`core.worktree` in `.git/modules/Extern/ladybird/config` must name, and it can only name one path.

**Sibling worktrees' submodule clones are isolated, not merely separate refs.**
A commit made on a local branch inside one worktree's submodule is not readable from another's
(`git cat-file -t <sha>` fails). So a fetch, branch or detached checkout in one worktree does not
propagate: `git submodule update` in the second worktree is what moves it, and it moves only to that
worktree's recorded pin. This is why one writer per worktree is safe, and why "I pushed from the
other checkout" is not evidence about this one.

**`git worktree remove` refuses a worktree that contains a submodule.**
It fails with `working trees containing submodules cannot be moved or removed`. `-f` removes it and
cleans `.git/worktrees/<id>`; the main checkout's submodule is untouched afterwards. A second `-f`
reports `is not a working tree` — that is success, not an error.

**An absent dialog callback does NOT make the engine answer itself.**
`ladybird_port.h` claims the four blocking dialogs are safe to omit because "the engine answers itself".
It does not, for this shim: `PortWebView` derives from `HeadlessWebView`, whose constructor already
installed handlers that only record `m_pending_dialog`. `LibPort` replaces those handlers when the host
supplies a callback and leaves the recording ones otherwise, and nothing then calls `alert_closed` /
`confirm_closed` / `prompt_closed`. `Page::did_request_alert` is parked in
`spin_event_loop_until_dialog_closed`, so the tab wedges permanently. The guarantee holds for a fresh
`ViewImplementation`, which a `HeadlessWebView` is not. *Fix: every request callback the shim adds must
have its own always-installed handler that answers "unavailable" when the host's callback is absent;
never inherit the absent-means-safe assumption. Grouped host callbacks stay all-or-none.*

**A `mouseMoved` override receives nothing without a tracking area.**
AppKit delivers move events to a view only through an `NSTrackingArea` (or with
`window.acceptsMouseMovedEvents`). `PortWebView` overrides the method and installs neither, so CSS `:hover`,
the pointing-hand cursor over links, and tooltips were all silently absent while clicks worked.
*Fix: tracking area with `.mouseMoved`/`.mouseEntered`/`.mouseExited`/`.activeInKeyWindow`/`.inVisibleRect`,
plus cursor rects (or `cursorUpdate`) for the pointer.*

**⌘-modified letter keys must cross the ABI as a `KeyCode`, not as `code_point`.**
The engine's editing shortcuts match `KeyCode::Key_C` / `Key_V` / `Key_X` / `Key_A` / `Key_Z` under
`Mod_PlatformCtrl` (which is `Mod_Super` on macOS) — see `EventHandler`. A host that suppresses
`code_point` when Command is held and maps only non-text virtual key codes delivers
`(invalid, 0, Mod_Super)` for every one of them, so copy, paste, cut, select-all and undo do nothing and
report no error. *Fix: map the letter virtual key codes too, and send the key with Command still set.*

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

**A hybrid compile against another checkout's generated headers invents upstream breakage.**
Reusing a shared build tree's compile command but pointing `-I` at a different fork checkout mixes
that tree's *stale generated* IPC headers with the new sources. The result is a wall of
`no type named 'ConnectToStorageAreaResponse'`, `marked 'override' but does not override`, and
`abstract class is marked 'final'` — none of it real. *Fix: never report those as sync findings, and
do not read their absence as a pass. Only a real build of the tree in question proves anything.*

**A sync can delete the symbol our presentation gate mirrors, and nothing notices.**
`PortWebView::current_frame()` is a *copy* of Qt's `current_paintable()` logic, not a call to it, so
upstream removing or reshaping that function produces no compile error here. Measured: the
`7e61093` → `4b042dd` sync dropped `WebContentView::current_paintable` from the header surface while
our copy stayed correct — luck, not a guarantee. *Fix: after every sync, diff our gate against
`UI/Qt/WebContentView.cpp` by hand. See [Upstream sync review](Upstream-Sync-Review.md).*

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

**Signing the bundle after the executable silently removes its entitlements.**
`codesign --sign ... Ava.app` re-signs `Contents/MacOS/Ava` as part of sealing the bundle, and it does
so *without* the entitlements passed to the inner call. Sign the executable and the bundle in one step,
passing `--entitlements` to the bundle sign. Measured: the first packaged DMG exited at once with
`dyld: ... liblagom-port.0.dylib ... mapping process and mapped file (non-platform) have different Team
IDs` — the shim was ad hoc signed and `disable-library-validation` was gone from the app. `codesign
--verify --strict` passed the whole time, because it does not exercise dyld. *Fix: sign the bundle with
the app's entitlements, and prove it by executing the binary rather than by verifying the signature.*

**The engine's rpaths are absolute paths into the build tree.**
`otool -l` on the helpers and every dylib lists the build directory itself. On a user's machine they
dangle; on a developer's machine they *resolve* — to another checkout's dylib, which is the ABI
mismatch `Scripts/build.sh` exists to prevent, delivered through `dyld` instead of the linker. A bundle
can pass a dependency-completeness check and still load the wrong engine. *Fix: delete every absolute
rpath and add `@loader_path/../lib` (binaries) or `@loader_path` (dylibs); assert no build-tree path
survives anywhere in the bundle.*

**A versioned dylib must be copied under its install name, not its real path.**
`liblagom-core.0.dylib` is a symlink to `liblagom-core.0.1.0.dylib`, and install names name the short
form. Copying by `realpath` produces a bundle where every dependency is present and nothing resolves.
*Fix: `cp` the resolved file to `<Contents/lib>/<name from the install name>`.*

**Packaging can break without any Swift file changing.**
It did, twice, on `main`: an uncommented comment line in `Scripts/build.sh` (the commit adding the ABI
pin) made the script die on `LbCallbacks: command not found`, and the signing order above shipped a DMG
that could not start. Neither is catchable by `swift build`, and CI only compiled. *Fix:
`Scripts/test-package.sh` runs the real `package.sh` against a synthetic engine tree — real dylib chain,
real helpers, real `@rpath` install names — and asserts the closure is complete, no build-tree path
survives, the entitlements land where they belong, and the executables actually load. It also has a
negative case: an unsatisfiable dependency must fail the build. CI runs it on every push and PR.*

That test covers assembly and signing. It passes `--no-build`, so it never executes `Scripts/build.sh`
and the `LbCallbacks` breakage remains hand-verified only — do not describe it as covered. The `package`
CI job (real engine, real DMG, launched from the mounted image) does run the full path, but only when
the repository variable `AVA_ENGINE_BUILD_DIR` points at a prebuilt engine. It is skipped otherwise
rather than faked: a fabricated green there would claim a bundle nobody built.

**A self-containment guard that greps for one literal prefix does not guard anything here.**
The build tree is normally a *symlink* to a second checkout, so a stale rpath in the bundle reads
`.../browsers/ladybird/Build/release/lib` — no `/ava/Extern/ladybird/Build` in it. A check written as
`grep -q "${FORK}/Build"` passes a bundle that still points at the build tree, which is exactly the
dylib-mismatch the whole relocation step exists to prevent. *Fix: enumerate every `LC_RPATH` and fail
on anything that is not `@`-relative or `/usr/lib/swift`; never pattern-match one absolute prefix.*
Related: `otool -l | grep -q` can exit early and, under `pipefail`, report failure via SIGPIPE — a
second way for the same guard to silently disable itself. Read the load commands before matching.

**Test mode is a layout-test switch, and it overrides font matching.**
`FontPlugin::generic_font_name()` returns `SerenitySans` for every generic family when
`m_is_layout_test_mode` is set, skipping matching entirely. It is reached from
`WebContentOptions::is_test_mode`, which defaults to `No`. A browser must leave it alone; only the
probes should set it. Symptom if you get it wrong: every page renders in the bundled fallback face
and system fonts are silently ignored — while pages that ship their own WOFF files still look
correct, which makes it look like a font-resolution bug rather than a configuration one.
*Fix: never set `is_test_mode` outside a test harness.*
