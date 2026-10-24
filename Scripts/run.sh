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

export LADYBIRD_BINARY_PATH="${BUILD_DIR}/bin/Ladybird.app/Contents/MacOS"
export DYLD_LIBRARY_PATH="${BUILD_DIR}/lib"

exec "$(swift build --show-bin-path)/LadybirdMac" "$@"
