#!/bin/bash
# Copyright (c) 2026-present, the Ladybird developers.
# SPDX-License-Identifier: BSD-2-Clause
#
# Builds the fork's C shim, then the Swift app. Swift is deliberately not in CMake: the shim is a
# normal CMake target so it inherits the Lagom link line, and SwiftPM consumes the resulting dylib.
#
# Usage: ./Scripts/build.sh [--swift-only]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORK="${REPO_ROOT}/Extern/ladybird"
BUILD_DIR="${FORK}/Build/release"

# A fresh `git submodule update --init` checks out the pinned SHA detached, and the branch it belongs
# to is ava-port. Earlier this silently force-checked-out ava-port, which reset the submodule
# underneath a staged pointer whenever the branch was not fast-forwarded — build.sh quietly undoing a
# deliberate pin. It now only switches when that is a no-op (same commit), and refuses otherwise.
if [[ -d "${FORK}/.git" || -f "${FORK}/.git" ]]; then
    current_branch="$(git -C "${FORK}" branch --show-current 2>/dev/null || true)"
    head_sha="$(git -C "${FORK}" rev-parse HEAD 2>/dev/null || true)"
    branch_sha="$(git -C "${FORK}" rev-parse --verify --quiet ava-port 2>/dev/null || true)"
    if [[ -n "${branch_sha}" && "${head_sha}" != "${branch_sha}" ]]; then
        if git -C "${FORK}" merge-base --is-ancestor "${head_sha}" "${branch_sha}" 2>/dev/null; then
            echo "fork is on '${current_branch:-detached}', fast-forwarding to ava-port"
            git -C "${FORK}" checkout -q ava-port
        else
            cat >&2 <<MSG
error: the fork is at ${head_sha}, which is not an ancestor of ava-port (${branch_sha}).

Refusing to switch branches and reset the submodule underneath the pin this repo records.
Fix it deliberately:

    cd Extern/ladybird
    git fetch origin ava-port
    git checkout ava-port && git merge --ff-only origin/ava-port

Or repin: git -C . checkout <the-sha-you-actually-want> and commit the submodule pointer.
MSG
            exit 1
        fi
    fi
fi

# The shim speaks a C ABI whose struct layouts live in the pinned submodule, so a dylib built from a
different commit is not a stale build — it is a different ABI. Widening `LbCallbacks` and running the
host against the older dylib is an immediate startup SIGSEGV, and `swift build` cannot see it: it only
links a symbol, and the field offsets are baked into the Swift side at compile time.
#
# So the dylib records which commit produced it, and a mismatch stops the build rather than shipping
the crash. The stamp lives beside the dylib because that is what the recorded commit describes.
PIN_STAMP="${BUILD_DIR}/lib/.libport-pin"
pin_now="$(git -C "${FORK}" rev-parse HEAD 2>/dev/null || echo unknown)"
pin_built="$(cat "${PIN_STAMP}" 2>/dev/null || echo none)"

if [[ "${1:-}" != "--swift-only" ]]; then
    if [[ ! -d "${BUILD_DIR}" ]]; then
        echo "error: no build directory at ${BUILD_DIR}" >&2
        echo "       build the fork first: cd Extern/ladybird && ./Meta/ladybird.py build --build-dir Build/release" >&2
        exit 1
    fi
    cmake --build "${BUILD_DIR}" --target LibPort
    printf '%s\n' "${pin_now}" > "${PIN_STAMP}"
    pin_built="${pin_now}"
fi

if [[ "${pin_built}" != "${pin_now}" ]]; then
    cat >&2 <<MSG
error: the LibPort shim does not match the pinned engine commit.

    pinned submodule: ${pin_now}
    built from:       ${pin_built}

The shim's C structs (LbCallbacks) changed between those commits. The Swift side is compiled against
the pinned header, so running it against this dylib reads the wrong field offsets and crashes at
startup. Rebuild the shim:

    ./Scripts/build.sh

If the build tree is a symlink to another checkout, that checkout must also be at ${pin_now} —
otherwise cmake rebuilds from the other checkout's sources and stamps a commit it did not build.
MSG
    exit 1
fi

# `swift build` cannot warn about this itself: it only links the dylib when a Swift file references a
# symbol, and by then the error is a bare `library 'lagom-port' not found`.
if [[ ! -f "${BUILD_DIR}/lib/liblagom-port.dylib" ]]; then
    cat >&2 <<'MSG'
error: the shim dylib is missing, so the package cannot link.

    cd Extern/ladybird
    ./Meta/ladybird.py build --build-dir Build/release

That is a multi-hour cold build (vcpkg plus the engine). To reuse a tree you
already have instead of rebuilding:

    ln -s /path/to/existing/ladybird/Build/release Extern/ladybird/Build/release
MSG
    exit 1
fi

cd "${REPO_ROOT}"
swift build
echo "built"
