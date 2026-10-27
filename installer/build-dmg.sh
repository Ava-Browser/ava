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
# create-dmg deletes an existing output before building; build at a sibling temporary path instead so a failed run
# leaves the previous disk image intact.
staged="${out_dir}/.$(basename "${OUTPUT}").partial.dmg"

work="$(mktemp -d "${TMPDIR:-/tmp}/ava-dmg.XXXXXX")"
trap 'rm -rf "${work}" "${staged}"' EXIT HUP INT TERM
mkdir -p "${work}/staging" "${out_dir}"
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
