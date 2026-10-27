# Reviewing an upstream sync of the engine fork

**Read this before pinning a resynced `ava-port`.** A sync merges `LadybirdBrowser:master` into the
fork. It is the highest-risk routine operation in this project, because the two things that break
loudest — the C ABI's field offsets and the presentation gate — are exactly the things no automated
check in this repo covers.

Measured example: the `7e61093` → `4b042dd` sync carried **733 commits**, left `LibPort` byte-identical,
silently removed `WebContentView::current_paintable`, and invalidated two R7 hash pins. Only one of
those three announced itself.

---

## Why a sync is dangerous here

The fork is **upstream plus one additive directory**. Everything we own sits on top of code that
moves underneath it. Three specific hazards, in descending order of nastiness:

### 1. The C ABI is positional, and nothing checks it

`LbCallbacks` is a struct of function pointers crossed by value. Swift bakes the **field offsets** in
at compile time. If upstream (or we) change the struct and the host runs against a dylib built from a
different commit, the host reads the wrong pointer and calls it. That is a startup SIGSEGV, not an
exception.

Nothing catches this automatically:

- `swift build` only needs the *symbol* to link. It cannot see offsets.
- CI compiles Swift and runs the layer guard. **It does not build the shim.**
- `check-layers.sh` R4 proves the header is still valid C11. It does not prove it matches the dylib.

Only a rebuild of both sides catches it. `Scripts/build.sh` now stamps `lib/.libport-pin` and refuses
on a mismatch — that is the backstop, not a substitute for review.

### 2. Presentation can break without a compile error

`PortWebView::current_frame()` mirrors Qt's `current_paintable()` gate: `m_has_usable_bitmap`, then
the backup buffer, then `VERIFY(m_front_bitmap.shared_image_buffer)`. Upstream renames, inlines, or
deletes these freely. Our copy is a *reimplementation*, so the compiler cannot notice when the
canonical version changes and ours does not.

### 3. The R7 hash manifest will fail, correctly

`check-layers.sh` pins exact SHA-256 hashes for the four approved `LibWebView` patch files. Upstream
editing **the same files we patched** changes those hashes even when our patch is untouched. The guard
is designed to force a human decision here. Use the protocol below — do not just paste new hashes.

---

## Checklist

Run in order. Do not skip to the pin.

### 1. Fetch and size the sync

```bash
git -C Extern/ladybird fetch origin ava-port
git -C Extern/ladybird log --oneline HEAD..origin/ava-port | wc -l
git -C Extern/ladybird rev-parse HEAD origin/ava-port
```

### 2. Confirm our ABI survived, byte for byte

```bash
git -C Extern/ladybird diff HEAD origin/ava-port -- Libraries/LibPort
```

**Empty output is the pass condition.** Non-empty means our callbacks moved — stop and treat it as an
ABI change requiring a coordinated dylib rebuild and a host review.

### 3. Confirm every engine API `LibPort` depends on still exists

The APIs we reach into, and the reason each matters:

| Symbol | Why it breaks us |
|---|---|
| `ViewImplementation::favicon_hash()` | the hash we key icons by |
| `ViewImplementation::on_favicon_change` | favicon delivery |
| `ViewImplementation::on_title_change` | real page titles |
| `ViewImplementation::on_loading_state_change` | loading indicator |
| `BrowsingSession::favicon_store` | where the PNG bytes live |
| `FaviconStore::favicon_png` | reading those bytes back |
| `Gfx::PNGWriter::encode` | fallback encoding path |
| `HeadlessWebView` + `initialize_tab` | our `PortWebView` subclasses it |
| `reset_viewport_size`, `set_device_pixel_ratio_for_testing` | viewport, in device pixels |
| `m_has_usable_bitmap`, `m_front_bitmap`, `m_backup_shared_image_buffer`, `m_backup_bitmap_size` | protected members the presentation gate needs |
| `WebView::sanitize_url` | address-bar input resolution |

```bash
cd Extern/ladybird
for f in Libraries/LibWebView/ViewImplementation.h Libraries/LibWebView/BrowsingSession.h \
         Libraries/LibWebView/FaviconStore.h Libraries/LibWebView/HeadlessWebView.h \
         Libraries/LibGfx/ImageFormats/PNGWriter.h Libraries/LibWebView/URL.h; do
    echo "== $f"; git show "origin/ava-port:$f" >/dev/null 2>&1 || echo "  FILE GONE"
done
# then grep each symbol you actually call:
git show origin/ava-port:Libraries/LibWebView/ViewImplementation.h | grep -n "favicon_hash\|on_favicon_change"
```

Beware the false negative: a grep for `class HeadlessWebView` misses
`class WEBVIEW_API HeadlessWebView`. Read the hit, do not trust a bare count.

### 4. Re-derive the presentation gate against Qt

`PortWebView::current_frame()` must still match `WebContentView::current_paintable()`. Compare the
two by hand:

```bash
git show origin/ava-port:UI/Qt/WebContentView.cpp | sed -n '/current_paintable() const/,/^}/p'
sed -n '/Optional<Frame> current_frame/,/^    }/p' Libraries/LibPort/ladybird_port.cpp
```

Same order: `m_has_usable_bitmap` → `VERIFY(m_front_bitmap.shared_image_buffer)` → else
`m_backup_shared_image_buffer` with `m_backup_bitmap_size`. If upstream changed the shape, ours is now
wrong even though it compiles.

### 5. Verify the fork's scope still satisfies R7

```bash
git -C Extern/ladybird fetch upstream master
base=$(git -C Extern/ladybird merge-base upstream/master origin/ava-port)
git -C Extern/ladybird diff "$base" origin/ava-port --name-only
```

Expected: `Libraries/LibPort/*`, `Tests/LibWebView/TestNative*`, the two CMake registration lines, and
the four approved `LibWebView` patch files. Anything else is rebase debt that will be reverted — find
out how it got there before pinning it.

### 6. Re-approve drifted hashes deliberately

`check-layers.sh` will name the files and both hashes. For each drifted approved-patch file:

```bash
# What changed across the sync?
git -C Extern/ladybird diff HEAD origin/ava-port -- Libraries/LibWebView/Application.h

# Did the sync remove any of OUR lines? (this is the actual question)
git -C Extern/ladybird diff HEAD origin/ava-port -- Libraries/LibWebView/Application.cpp \
    | grep '^-' | grep -v '^---' | grep -iE 'container|session_for_new_view'
```

Re-approve **only** when the diff is upstream additions around our patch and no line of ours was
removed. Then update the hash in `Scripts/check-layers.sh` and record the old→new pair in the commit
message, so the re-approval is reviewable next to its reason.

### 7. Build, test, then pin

```bash
./Scripts/build.sh          # rebuilds the shim and stamps lib/.libport-pin
swift build && swift test
git add Extern/ladybird Scripts/check-layers.sh
git commit -m "Extern/ladybird: Pin the ava-port upstream sync"
```

Keep the pin and the manifest update in **one commit**. Splitting them produces a commit where the
guard fails for no visible reason.

---

## What CI does and does not prove

App CI (`.github/workflows/ci.yml`) does exactly four things: deepen the submodule history for the R7
guard, run `check-layers.sh`, `swift build --target Ava`, and `swift build` of the two test targets.

It **compiles without linking** — there is no engine dylib on the runner, so a link would fail. And it
**does not build the shim** or run `swift test`; the workflow says so in a comment: "CI checks source
compilation and boundaries, not runtime behavior."

So a green PR after a sync means: the Swift tree typechecks, the layer rules hold, the header is still
C11, and the submodule pin resolves publicly. It does **not** mean the shim compiles or links against
the new upstream — only a real fork build shows that, and it is hours cold and not wired into CI.

State this honestly in a sync PR rather than implying CI covered it.

## Local traps that produce false readings

- **A hybrid compile is not a build.** Mixing our fork's headers with a shared build tree's stale
  *generated* IPC headers yields `no type named 'ConnectToStorageAreaResponse'`,
  `marked 'override' but does not override`, `abstract class is marked 'final'`. Those are artefacts of
  the mix, not upstream breakage. Do not report them as findings, and do not take their absence as a
  pass.
- **`Extern/ladybird/Build/release` is usually a symlink** to another checkout. `check-layers.sh` fails
  its provenance branch when that tree sits at a different commit. Expected in a worktree; on CI's
  clean checkout it is self-contained and passes.
- **`git cat-file` on an unfetched submodule commit fails.** Fetch first, or you will conclude a real
  push never landed.

## Failure catalogue

| Symptom | Cause | Fix |
|---|---|---|
| Instant SIGSEGV on launch, no output | host compiled against a wider `LbCallbacks` than the dylib | rebuild shim; `build.sh` now refuses first |
| Blank or wrong-region page, no build error | `current_frame()` gate drifted from Qt's | re-derive by hand (step 4) |
| `R7: Approved patch file … has drifted` | upstream edited a file we patch | re-approve via step 6 |
| `R7: fork modifies files outside …` | a stray edit smuggled into the sync | find the commit; revert to an upstream-shaped patch |
| `library 'lagom-port' not found` | dylib missing after a fresh clone | build the fork, or symlink an existing build tree |
| Guard green but dylib stale | symlinked build tree from another checkout | `build.sh` stamp; rebuild in this checkout |

## After merging

Anyone pulling the commit must rebuild the shim before running. A pin move of a few hundred commits
guarantees the dylib is stale, and the failure mode is a crash with no stack worth reading. Say so in
the PR body.
