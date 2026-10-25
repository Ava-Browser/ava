# 0001 — Two repos, one boundary

**Status:** accepted
**Date:** 2026-10-24

## Context

The shim that bridges `LibWebView` to a non-C++ UI must build **inside** the Ladybird tree: only
the in-tree CMake supplies the Lagom link line and the `LADYBIRD_*` compile definitions. It cannot
live in the app repo and be built there.

That makes the fork a hard build dependency of the app. The question was how to relate them.

## Decision

Two repositories:

- **`ladybird` (fork)** — upstream plus exactly one added directory (`Libraries/LibPort/`) and the
  probes under `Tests/LibWebView/TestNative*`. Consumed as a git submodule at a pinned commit.
- **`ladybird-mac`** — everything above the C ABI.

The fork is a **dependency you happen to control**, not a workspace. Pins advance deliberately,
the way vcpkg pins advance in Ladybird — never incidentally.

## Why not one repo with the app inside it

- Upstream sync is the dominant long-term cost. A fork that adds one directory stays trivially
  mergeable; a fork that also reworks `UI/` does not.
- Rule R7 exists because of this: every line changed outside `LibPort/` is rebase debt that
  compounds on each upstream sync. Keeping the app out of the fork makes R7 enforceable by a
  one-line diff guard.

## Consequences

- A cold clone needs `--recurse-submodules`; the submodule checks out the pinned commit
  detached. Port development uses `ava-port`, now the engine fork's default branch.
- The fork's build tree (3 GB, hours to produce) is not in the repo. `build.sh` and `run.sh` fail
  with instructions and offer symmetrically linking an existing tree.
- The ABI's single source of truth is `Extern/ladybird/Libraries/LibPort/ladybird_port.h`; the app
  repo forwards to it rather than copying it.
