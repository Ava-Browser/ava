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
# different commit is not a stale build — it is a different ABI. Widening `LbCallbacks` and running the
# host against the older dylib is an immediate startup SIGSEGV, and `swift build` cannot see it: it only
# links a symbol, and the field offsets are baked into the Swift side at compile time.
#
# So the built shim is checked against the pin, and a mismatch stops the build rather than shipping the
# crash.
#
# The check must read the commit CMake actually compiles, not what a previous run intended to build.
# Build/release is usually a symlink to a second checkout, reused instead of rebuilt for hours, so
# `cmake --build` can read sources from a tree that is not $FORK at all. A stamp written from `pin_now`
# therefore records a wish: measured, the stamp said 4b042dd while the dylib had been compiled from a
# checkout 737 commits behind, and this guard passed while every LbCallbacks slot was misaligned.
# CMakeCache.txt names the real source tree, so that is the authority.
BUILD_TREE="${FORK}/Build/release"
PIN_STAMP="${BUILD_DIR}/lib/.libport-pin"
pin_now="$(git -C "${FORK}" rev-parse HEAD 2>/dev/null || echo unknown)"

# The checkout CMake compiles from, and its commit. Falls back to the stamp only when there is no
# cache to read, which is the one case where the stamp is the best available evidence.
built_home="$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "${BUILD_TREE}/CMakeCache.txt" 2>/dev/null | head -1)"
if [[ -n "${built_home}" ]]; then
    built_sha="$(git -C "${built_home}" rev-parse HEAD 2>/dev/null || echo unknown)"
else
    built_sha="$(cat "${PIN_STAMP}" 2>/dev/null || echo none)"
    built_home="<unknown; no CMakeCache in ${BUILD_TREE}>"
fi

if [[ "${1:-}" != "--swift-only" ]]; then
    if [[ ! -d "${BUILD_DIR}" ]]; then
        echo "error: no build directory at ${BUILD_DIR}" >&2
        echo "       build the fork first: cd Extern/ladybird && ./Meta/ladybird.py build --build-dir Build/release" >&2
        exit 1
    fi
    cmake --build "${BUILD_DIR}" --target LibPort
    # Record the commit of the tree CMake just read, so the stamp describes the dylib.
    built_home="$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "${BUILD_TREE}/CMakeCache.txt" 2>/dev/null | head -1)"
    built_sha="$(git -C "${built_home:-${FORK}}" rev-parse HEAD 2>/dev/null || echo unknown)"
    printf '%s\n' "${built_sha}" > "${PIN_STAMP}"
fi

if [[ "${built_sha}" != "${pin_now}" ]]; then
    cat >&2 <<MSG
error: the LibPort shim would be built from a different engine commit than the pin.

    pinned submodule:    ${pin_now}
    build tree sources:  ${built_sha}
    build tree checkout: ${built_home}

The shim's C structs (LbCallbacks) differ between those commits, and the offsets are positional. The
Swift side is compiled against the pinned header, so a dylib from the other tree makes every callback
read the wrong slot: field 4 is on_title_change in the pin but on_request_alert in an older tree. That
is a silent misalignment, not a missing feature, and it does not always crash.

Point the build tree at the pin (detached is normal for a submodule pin; do not switch to this
repo's branch, which may be unrelated work):

    git -C "${built_home}" fetch origin ava-port
    git -C "${built_home}" checkout --detach ${pin_now}

...then rebuild (a large jump under Libraries/ is hours, not minutes):

    cd "${built_home}" && ./Meta/ladybird.py build --build-dir Build/release

Or, deliberately, repin this repo to what that tree actually is:

    git -C . checkout ${built_sha} && git add Extern/ladybird && git commit
MSG
    exit 1
fi

# The build tree being a separate checkout is legitimate (a multi-GB, hours-long build is worth
# sharing) but it is also how the above happens, so say it out loud rather than failing silently later.
fork_real="$(cd "${FORK}" && pwd -P)"
if [[ -n "${built_home}" && "${built_home}" != "${fork_real}" ]]; then
    echo "note: building from a separate checkout at ${built_home} (same commit as the pin)."
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
