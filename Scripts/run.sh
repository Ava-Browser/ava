#!/bin/bash
# Copyright (c) 2026-present, the Ladybird developers.
# SPDX-License-Identifier: BSD-2-Clause
#
# Development runner. Exports the paths the engine needs to find its helper processes and the
# Lagom dylibs. PRODUCTION REPLACES BOTH with an .app bundle and @loader_path rpaths — see
# Documentation/Architecture.md, "Known gaps".
#
# Usage: ./Scripts/run.sh [app arguments]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/Extern/ladybird/Build/release"

if [[ ! -f "${BUILD_DIR}/lib/liblagom-port.dylib" ]]; then
    cat >&2 <<'MSG'
error: the shim dylib is missing. Build the fork first:

    cd Extern/ladybird
    ./Meta/ladybird.py build --build-dir Build/release

That is a multi-hour cold build (vcpkg plus the engine). If you already have a
build tree elsewhere, point the package at it by symlinking rather than rebuilding:

    ln -s /path/to/existing/ladybird/Build/release Extern/ladybird/Build/release
MSG
    exit 1
fi

# Resolve symlinks before handing the path to the engine. The renderer's seatbelt profile grants read access to
# s_ladybird_resource_root, which the engine derives from this path; a symlinked build tree yields a path the sandbox
# did not grant, so every font stat fails with EPERM and WebContent aborts on a missing default font.
BINARY_PATH="$(cd "${BUILD_DIR}/bin/Ladybird.app/Contents/MacOS" && pwd -P)"

export LADYBIRD_BINARY_PATH="${BINARY_PATH}"
export DYLD_LIBRARY_PATH="$(cd "${BUILD_DIR}/lib" && pwd -P)"

exec "$(swift build --show-bin-path)/LadybirdMac" "$@"
