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

EXECUTABLE="$(swift build --show-bin-path)/Ava"

# Launch from a minimal .app bundle, not as a bare executable.
#
# A bare Mach-O cannot become the active application on current macOS: it launches, creates a window, and that window
# reports kCGWindowIsOnscreen=nil and never takes focus, so the app appears not to have opened. Wrapping the same binary
# in a bundle with an Info.plist is what makes it a regular app — measured, not inferred: identical binary, bare run
# `active=false` and the window invisible; inside a bundle `frontmost=LadybirdMac` with red traffic lights.
#
# The executable stays in .build and the bundle's MacOS/ holds a symlink to it, so `swift build` keeps working without
# copying anything. rpaths still resolve through the real path.
# Keep the existing bundle identifier below so saved preferences survive the product rename.
BUNDLE_DIR="${REPO_ROOT}/.build/Ava.app"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
cat > "${BUNDLE_DIR}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Ava</string>
<key>CFBundleIdentifier</key><string>org.ladybird.mac.dev</string>
<key>CFBundleName</key><string>Ava</string>
<key>CFBundleDisplayName</key><string>Ava</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
ln -sfn "${EXECUTABLE}" "${BUNDLE_DIR}/Contents/MacOS/Ava"

exec "${BUNDLE_DIR}/Contents/MacOS/Ava" "$@"
