#!/bin/bash
# Copyright (c) 2026-present, the Ladybird developers.
# SPDX-License-Identifier: BSD-2-Clause
#
# Build Ava's approved Quiet Breath drag-to-Applications disk image.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-${ROOT}/.build/package/Ava.app}"
OUTPUT="${2:-${ROOT}/.build/package/Ava-0.1.0.dmg}"
BACKGROUND="${ROOT}/installer/quiet-breath-background@2x.png"
ICON="${ROOT}/Resources/app_icon.icns"

command -v create-dmg >/dev/null || { echo "error: create-dmg is required" >&2; exit 1; }
[[ -d "${APP}" ]] || { echo "error: app not found: ${APP}" >&2; exit 1; }
[[ -f "${BACKGROUND}" ]] || { echo "error: background not found: ${BACKGROUND}" >&2; exit 1; }
codesign --verify --deep --strict "${APP}"

out_dir="$(dirname "${OUTPUT}")"
mkdir -p "${out_dir}"
# create-dmg deletes an existing output before building; stage inside a unique sibling directory on the same filesystem
# so a failed or concurrent run leaves previous/other disk images intact and atomically renames on completion.
staged_dir="$(mktemp -d "${out_dir}/.ava-dmg-stage.XXXXXX")"
staged="${staged_dir}/$(basename "${OUTPUT}")"

work="$(mktemp -d "${TMPDIR:-/tmp}/ava-dmg.XXXXXX")"
trap 'rm -rf "${work}" "${staged_dir}"' EXIT HUP INT TERM
mkdir -p "${work}/staging"
ditto "${APP}" "${work}/staging/Ava.app"

create-dmg \
    --overwrite \
    --volname "Ava" \
    --volicon "${ICON}" \
    --background "${BACKGROUND}" \
    --window-size 660 386 \
    --icon-size 112 \
    --icon "Ava.app" 155 200 \
    --hide-extension "Ava.app" \
    --app-drop-link 505 200 \
    "${staged}" \
    "${work}/staging"

hdiutil verify -quiet "${staged}"
mv -f "${staged}" "${OUTPUT}"
echo "${OUTPUT}"
