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

# A fresh `git submodule update --init` checks out master, which has no Libraries/LibPort. The
# submodule pin is recorded on the native-port branch, so put the tree on it before building.
if [[ -d "${FORK}/.git" || -f "${FORK}/.git" ]]; then
    current="$(git -C "${FORK}" branch --show-current 2>/dev/null || true)"
    if [[ "${current}" != "native-port" ]]; then
        echo "fork is on '${current:-detached}', switching to native-port"
        git -C "${FORK}" checkout -q native-port
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
