# Implementation handoff — 2026-10-25

## Reviewed baseline and current scope

- `TDD-SpaceSettings.md`: functional sidebar/settings slice committed as `6155b4e`.
  Coordinator independently verified **36 tests in 7 suites**, layer guard, and exact
  toolbar source identity. See `Reports/SpaceSettings-FirstPass.md` for remaining visual
  and runtime gaps. This is NOT a claim of exact Arc pixel parity.
- `PRD-Settings.md` + `TDD-Settings.md`: engine inventory remains useful, but the native
  Search/DNS plan is superseded. Ladybird's working `about:settings` page is the source of
  truth for engine-owned settings; Ava-native Settings stays app-owned.
- `TDD-SafariHeader.md`: first real-control pass revised after native focus/blur review.
  Worker reported Accessibility selection/blur evidence; coordinator independently ran
  the STACKED sidebar + header app: **58 tests in 10 suites passed**, layer guard passed.
  Final native/UI/measurement review remains an open post-merge polish item.
- Engine baseline remains `66616b4deeb42fbc7ce722075f22b1b1e5f5891a` on `ava-port`.
  The experimental search-settings PR was closed without merging and its branch discarded.
  The app pin remains unchanged.

## Pull requests and preserved evidence

- [Ava #2 — sidebar/settings foundation](https://github.com/Ava-Browser/ava/pull/2), merged
- [Ava #3 — Safari header](https://github.com/Ava-Browser/ava/pull/3), merged
- [ava-engine #1 — abandoned native search-settings experiment](https://github.com/Ava-Browser/ava-engine/pull/1), closed

Header screenshots and its revised report are in #3. See [M6 readiness](Reports/M6-Readiness.md) and
[manual-unload readiness](Reports/ManualUnload-Readiness.md). Manual unload stopped at
investigation: **no implementation or test pass is claimed**. Do not open/merge an empty
implementation PR for that checkpoint.

## Resume order and open gates

1. Keep engine-owned search/network/privacy settings in `about:settings`. Do not revive the
   discarded native search ABI, add duplicate persistence, or advance the engine pin for it.
2. Preserve the merged sidebar/header behavior and existing preferences/graph paths.
   Native UI tests must not alter the general clipboard.
3. Manual inactive-space unload is a separate pending slice. Preserve descriptors and
   global Essentials; never unload the displayed tab; confirm potential live form-state
   loss; prove scoped helper reclamation without killing other processes. Do not infer
   one process per tab or exact memory reduction from model-only tests.
4. Containers remain blocked: historical TestNativeContainers exercises default/private
   views and direct CookieJars, with in-process database reopen—not two named-container
   page/network sessions or a cold app restart. It also lacks fail-closed assertions
   for some printed results and bounded waiting. Rebinding protected `m_session` alone
   does not prove the WebContent/RequestServer session changed. Add rigorous probes;
   upstream-shaped client/session plumbing requires separate approval. Keep Set Profile
   disabled; a named container is not a complete profile.
5. Gestures are not implemented. A threshold at gesture end is not the specified 1:1
   interaction. Define page-horizontal-scroll arbitration, cancellation, reduced motion,
   and a safe interactive presentation path before source work.
6. Finish normalized Arc comparisons using final-source screenshots at matched sidebar
    width/scale, including dark/inactive, empty/collapsed tiers, overflow, and keyboard
    focus. Current fallbacks are not Arc site favicons. Missing Safari Share/overview/
    downloads/bookmarks controls remain omitted until they have real implementations.

## Verification and work preservation

Use the PR branches and their technical reports for source/test state. Draft PRs preserve
incomplete work; they are not merge approval. Keep local agent/task/terminal metadata out
of public documentation. Use isolated worktrees with one writer each.

The build guard supports macOS `/bin/bash` 3.2. When reusing an engine build from another
checkout, compare source bytes and report provenance warnings.
Never repoint copied submodule `.git` metadata. Do not write shared CMake/generated/lib
outputs from a different worktree. Check available disk space before cold engine builds.

Setting up a worktree means initializing its own submodule clone — `git worktree add` records the
pin but leaves `Extern/ladybird/` empty (`Documentation/Traps.md`):

    git worktree add ../<name> -b <branch>
    cd ../<name>
    git -c protocol.file.allow=always submodule update --init Extern/ladybird
    git submodule status                      # no leading '-' means it is populated
    git -C Extern/ladybird rev-parse --show-toplevel   # must print THIS worktree
    ./Scripts/check-layers.sh

To work on the fork too, `git -C Extern/ladybird checkout ava-port` — a detached pin will not build
the fork's branch changes. Then cold-build `Extern/ladybird/Build/release`; history is hardlinked
across worktrees, the build tree is not.

Isolated temporary shim/probe output
may reuse audited cached dependencies read-only, but record exact commands and prove the
new shim is the one loaded. Never claim a dry-run built/tested the code.

Use temporary UserDefaults suites, graph files, and named pasteboards in tests. Serialize
Ava launches because default app/profile paths are shared; record/close only your launched
PID. No broad pkill. Local `/tmp` captures/reports are not durable CI artifacts: preserve
sanitized evidence needed for review in the PR or repository, and label missing evidence.

Gitleaks 8.30.1 found no detections across all local app Git refs or the outgoing engine
search changes during review. This is not a full upstream-engine history scan, an image/PII
audit, or proof that no secret exists. Local paths and coordination identifiers were removed
from current app documentation; prior published commits are unchanged. Signed/self-contained
packaging and universal runtime/visual verification remain outstanding. Public visibility is
not a release-readiness certificate.
