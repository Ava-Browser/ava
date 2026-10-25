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

if [[ "${1:-}" != "--swift-only" ]]; then
    if [[ ! -d "${BUILD_DIR}" ]]; then
        echo "error: no build directory at ${BUILD_DIR}" >&2
        echo "       build the fork first: cd Extern/ladybird && ./Meta/ladybird.py build --build-dir Build/release" >&2
        exit 1
    fi
    cmake --build "${BUILD_DIR}" --target LibPort
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
