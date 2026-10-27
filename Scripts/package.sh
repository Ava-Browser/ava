#!/bin/bash
# Copyright (c) 2026-present, the Ladybird developers.
# SPDX-License-Identifier: BSD-2-Clause
#
# Builds a self-contained Ava.app and a DMG. Unlike Scripts/run.sh, nothing here points back into the
# engine build tree: the shim, its Lagom/vcpkg dependency closure, the helper processes and the engine's
# Resources all live inside the bundle, found the way the engine looks for them (Contents/MacOS for
# helpers, Contents/Resources for the resource root) and by @loader_path rpaths for the dylibs.
#
# Usage: ./Scripts/package.sh [--identity <codesign identity>] [--version <version>] [--no-build]
#
# Without --identity (or AVA_SIGN_IDENTITY) the bundle is signed ad hoc: it runs locally but Gatekeeper
# will not accept it on another machine. Notarization needs credentials and is not done here; see the
# note printed at the end.
#
# --no-build packages what is already built (AVA_BINARY overrides the executable). CI has no engine build
# tree, so it uses this to exercise the assembly below against a synthetic one: Scripts/test-package.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORK="${REPO_ROOT}/Extern/ladybird"
BUILD_DIR="${FORK}/Build/release"
VCPKG_LIB="${BUILD_DIR}/vcpkg_installed/arm64-osx-dynamic/lib"
OUT_DIR="${REPO_ROOT}/.build/package"
APP="${OUT_DIR}/Ava.app"
LIBS="${APP}/Contents/lib"

IDENTITY="${AVA_SIGN_IDENTITY:--}"
VERSION="0.1.0"
DO_BUILD=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --identity) IDENTITY="${2:?--identity needs a value}"; shift 2 ;;
        --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
        --no-build) DO_BUILD=0; shift ;;
        -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "error: unknown argument: $1" >&2; exit 1 ;;
    esac
done

# Helpers the engine spawns. Order matters only for what is copied; every one is launched by name from
# the application directory (LibWebView::get_paths_for_helper_process), so they belong in Contents/MacOS.
HELPERS=(WebContent WebWorker Compositor RequestServer MediaServer AudioServer ImageDecoder VideoDecoderServer ProcessReaper)

# Only the helpers, not the Qt-based `ladybird` binary: Ava is the UI, so shipping it would drag Qt in.
die() { echo "error: $*" >&2; exit 1; }

if [[ ${DO_BUILD} -eq 1 ]]; then
    # Scripts/build.sh owns the shim/ABI-pin checks; reuse them rather than duplicating the reasoning here.
    # It builds the shim and a debug app; the packaged binary is built in release below.
    echo "==> building engine shim and app"
    "${REPO_ROOT}/Scripts/build.sh"
    (cd "${REPO_ROOT}" && swift build -c release)
fi
AVA_BINARY="${AVA_BINARY:-$(cd "${REPO_ROOT}" && swift build -c release --show-bin-path)/Ava}"
[[ -x "${AVA_BINARY}" ]] || die "no app executable at ${AVA_BINARY}; build it or set AVA_BINARY"

echo "==> assembling ${APP}"
rm -rf "${OUT_DIR}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources" "${LIBS}"

cp "${AVA_BINARY}" "${APP}/Contents/MacOS/Ava"
for helper in "${HELPERS[@]}"; do
    [[ -x "${BUILD_DIR}/bin/Ladybird.app/Contents/MacOS/${helper}" ]] \
        || die "helper process ${helper} is missing; rebuild the engine"
    cp "${BUILD_DIR}/bin/Ladybird.app/Contents/MacOS/${helper}" "${APP}/Contents/MacOS/${helper}"
done
# themes/ is not optional: LbTabCreate loads Default.ini from the resource root and returns tab id 0 without it.
cp -R "${BUILD_DIR}/bin/Ladybird.app/Contents/Resources/." "${APP}/Contents/Resources/"

# ---------------------------------------------------------------- dependency closure
# Resolve @rpath dependencies the way dyld will: by name, from the engine's own library directories.
# Anything absolute and outside the system (Qt, a stray Homebrew lib) is a hard failure, because it would
# silently become a runtime "library not found" on a machine that does not have it.
resolve_dep() {
    local name="$1" dir
    for dir in "${BUILD_DIR}/lib" "${VCPKG_LIB}"; do
        [[ -e "${dir}/${name}" ]] && { echo "${dir}/${name}"; return 0; }
    done
    return 1
}

# macOS ships bash 3.2: no associative arrays, so the set of copied names is a newline-delimited string.
copied=""
queue=("${APP}/Contents/MacOS/Ava")
for helper in "${HELPERS[@]}"; do queue+=("${APP}/Contents/MacOS/${helper}"); done

while [[ ${#queue[@]} -gt 0 ]]; do
    image="${queue[0]}"
    queue=("${queue[@]:1}")
    while read -r dep; do
        [[ -z "${dep}" ]] && continue
        case "${dep}" in
            @rpath/*|@executable_path/*|@loader_path/*) name="${dep##*/}" ;;
            /usr/lib/*|/System/*) continue ;;
            *) die "$(basename "${image}") needs ${dep}, which is absolute and outside the system" ;;
        esac
        grep -qxF "${name}" <<< "${copied}" && continue
        src="$(resolve_dep "${name}")" || die "$(basename "${image}") needs ${name}, which is in neither ${BUILD_DIR}/lib nor ${VCPKG_LIB}"
        # Copy the real file under the name dyld looks for: the symlinked and versioned names all resolve
        # to the same image, and install names never mention the version suffix on disk.
        cp -c "$(realpath "${src}")" "${LIBS}/${name}" 2>/dev/null || cp "$(realpath "${src}")" "${LIBS}/${name}"
        copied="${copied}${name}
"
        queue+=("${LIBS}/${name}")
    done < <(otool -L "${image}" | tail -n +2 | awk '{print $1}')
done
echo "    $(grep -c . <<< "${copied}") dylibs"

# ---------------------------------------------------------------- rpaths
# Every LC_RPATH entry, one per line. Parsed by slicing between "path " and " (offset ...)" rather than
# by field: otool does not escape the path, so a checkout directory containing a space would be
# truncated to its first word — and deleting a truncated rpath fails, or worse, matches nothing.
read_rpaths() {
    otool -l "$1" | awk '/LC_RPATH/ { getline; getline; sub(/^[ \t]*path /, ""); sub(/ \(offset .*/, ""); print }'
}

# The engine tree's rpaths are absolute paths into the build directory. On a user's machine they do not
# exist, and on a developer's machine they *do* — pointing at a dylib built from some other commit, which
# is the ABI mismatch that crashes at startup. Drop them and point everything at the bundle instead.
relocate() {
    local image="$1" rpath
    while read -r rpath; do
        case "${rpath}" in
            @*|/usr/lib/swift) continue ;;
            # Fail loudly: a delete that does not take leaves a path into the build tree, and dyld would
            # prefer it over ours. The post-assembly check below reports it too, but not why.
            *) install_name_tool -delete_rpath "${rpath}" "${image}" \
                   || die "could not remove rpath ${rpath} from $(basename "${image}")" ;;
        esac
    done < <(read_rpaths "${image}")
}
for helper in "${HELPERS[@]}"; do
    relocate "${APP}/Contents/MacOS/${helper}"
    install_name_tool -add_rpath "@loader_path/../lib" "${APP}/Contents/MacOS/${helper}"
done
relocate "${APP}/Contents/MacOS/Ava"
install_name_tool -add_rpath "@loader_path/../lib" "${APP}/Contents/MacOS/Ava"
for lib in "${LIBS}"/*.dylib; do
    relocate "${lib}"
    install_name_tool -add_rpath "@loader_path" "${lib}" 2>/dev/null || true
done

# ---------------------------------------------------------------- Info.plist
# The identifier is the shipping one; Scripts/run.sh deliberately keeps org.ladybird.mac.dev so a local
# build never masquerades as the packaged app. First run of the DMG therefore starts from default settings.
cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Ava</string>
<key>CFBundleIdentifier</key><string>org.ladybird.Ava</string>
<key>CFBundleName</key><string>Ava</string>
<key>CFBundleDisplayName</key><string>Ava</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleShortVersionString</key><string>${VERSION}</string>
<key>CFBundleVersion</key><string>${VERSION}</string>
<key>CFBundleIconFile</key><string>app_icon.icns</string>
<key>LSMinimumSystemVersion</key><string>14.4</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Ava needs access to your microphone to give pages that request it audio capture.</string>
<key>NSLocationWhenInUseUsageDescription</key><string>Ava needs your location to give it to pages that request it.</string>
<key>CFBundleDocumentTypes</key><array><dict>
  <key>CFBundleTypeName</key><string>Web documents</string>
  <key>CFBundleTypeRole</key><string>Viewer</string>
  <key>LSItemContentTypes</key><array>
    <string>public.html</string><string>public.xhtml</string><string>public.svg-image</string>
  </array>
</dict></array>
<key>CFBundleURLTypes</key><array><dict>
  <key>CFBundleURLName</key><string>Web site URL</string>
  <key>CFBundleURLSchemes</key><array><string>http</string><string>https</string></array>
</dict></array>
</dict></plist>
PLIST

# ---------------------------------------------------------------- signing
# Inside out, and never --deep: helpers carry the hardened runtime, because the kernel refuses W+X memory
# in a runtime process and the renderers JIT. Library validation is off for the same reason the engine's
# own CMake turns it off — without a team identifier ad hoc images would refuse to load each other.
entitlements_for() {
    local plist_file="$1" allow_jit="$2"
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        echo '<plist version="1.0"><dict>'
        echo '<key>com.apple.security.cs.disable-library-validation</key><true/>'
        [[ "${allow_jit}" == "yes" ]] && echo '<key>com.apple.security.cs.allow-jit</key><true/>'
        echo '</dict></plist>'
    } > "${plist_file}"
}

sign() {
    local target="$1" ents="${2:-}"
    if [[ "${IDENTITY}" == "-" ]]; then
        if [[ -n "${ents}" ]]; then
            codesign --force --options runtime --sign - --entitlements "${ents}" "${target}"
        else
            codesign --force --options runtime --sign - "${target}"
        fi
    else
        if [[ -n "${ents}" ]]; then
            codesign --force --options runtime --timestamp --sign "${IDENTITY}" --entitlements "${ents}" "${target}"
        else
            codesign --force --options runtime --timestamp --sign "${IDENTITY}" "${target}"
        fi
    fi
}

echo "==> signing (${IDENTITY})"
for lib in "${LIBS}"/*.dylib; do sign "${lib}"; done
for helper in "${HELPERS[@]}"; do
    jit=no
    [[ "${helper}" == "WebContent" || "${helper}" == "WebWorker" ]] && jit=yes
    entitlements_for "${OUT_DIR}/${helper}.entitlements" "${jit}"
    sign "${APP}/Contents/MacOS/${helper}" "${OUT_DIR}/${helper}.entitlements"
done
# The bundle is signed last and carries the main executable's entitlements in the same step: signing the
# bundle re-signs Contents/MacOS/Ava, so a separate sign of that binary would be replaced without them —
# and without disable-library-validation the ad hoc shim fails to load ("different Team IDs").
entitlements_for "${OUT_DIR}/Ava.entitlements" no
sign "${APP}" "${OUT_DIR}/Ava.entitlements"

# ---------------------------------------------------------------- verify
echo "==> verifying"
codesign --verify --strict "${APP}" || die "signature verification failed"
for helper in "${HELPERS[@]}"; do
    codesign --verify --strict "${APP}/Contents/MacOS/${helper}" || die "${helper} signature verification failed"
done

# Every @rpath dependency must resolve inside the bundle, and nothing may still point into the build tree.
missing=()
for image in "${APP}/Contents/MacOS/Ava" "${APP}/Contents/MacOS/"* "${LIBS}"/*.dylib; do
    [[ "${image}" == *.entitlements || ! -f "${image}" ]] && continue
    while read -r dep; do
        case "${dep}" in
            @rpath/*|@executable_path/*|@loader_path/*)
                [[ -e "${LIBS}/${dep##*/}" ]] || missing+=("${dep##*/} (from $(basename "${image}"))") ;;
            /usr/lib/*|/System/*) ;;
            *) missing+=("${dep} (absolute, from $(basename "${image}"))") ;;
        esac
    done < <(otool -L "${image}" | tail -n +2 | awk '{print $1}')
    # Check every LC_RPATH by value, not by grepping for one literal prefix. The build tree is usually a
    # symlink to a *second* checkout, so a stale rpath reads .../browsers/ladybird/Build/... and an
    # ava-relative pattern misses it entirely. Read the load commands once, too: `otool -l | grep -q`
    # exits early and can report failure via SIGPIPE under pipefail, turning this guard off silently.
    while read -r rpath; do
        case "${rpath}" in
            @*|/usr/lib/swift) ;;
            *) missing+=("non-bundle rpath ${rpath} in $(basename "${image}")") ;;
        esac
    done < <(read_rpaths "${image}")
done
[[ ${#missing[@]} -eq 0 ]] || die "bundle is not self-contained: ${missing[*]}"

# ---------------------------------------------------------------- dmg
STAGE="${OUT_DIR}/dmg"
mkdir -p "${STAGE}"
cp -R "${APP}" "${STAGE}/Ava.app"
ln -s /Applications "${STAGE}/Applications"
DMG="${OUT_DIR}/Ava-${VERSION}.dmg"
echo "==> creating ${DMG}"
hdiutil create -quiet -volname "Ava" -srcfolder "${STAGE}" -fs APFS -format ULFO -ov "${DMG}"
hdiutil verify -quiet "${DMG}"

echo
echo "app: $(du -sh "${APP}" | cut -f1)  ${APP}"
echo "dmg: $(du -sh "${DMG}" | cut -f1)  ${DMG}"
if [[ "${IDENTITY}" == "-" ]]; then
    echo
    echo "Signed ad hoc. It runs from this machine; Gatekeeper rejects it elsewhere. To ship:"
    echo "  ./Scripts/package.sh --identity \"Developer ID Application: ...\""
    echo "  xcrun notarytool submit ${DMG} --keychain-profile <profile> --wait"
    echo "  xcrun stapler staple ${DMG}"
fi
