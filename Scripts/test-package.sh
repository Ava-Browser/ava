#!/bin/bash
# Copyright (c) 2026-present, the Ladybird developers.
# SPDX-License-Identifier: BSD-2-Clause
#
# Tests Scripts/package.sh's assembly without an engine build tree. CI has no way to produce one — it is
# a multi-hour vcpkg and Qt build, and packaging was the one script nothing executed on a push. So this
# builds a synthetic engine tree (a real dylib dependency chain, real helper executables) and asserts the
# properties that broke in practice: the closure is complete, no absolute build-tree path survives, and
# the entitlements land on the images that need them.
#
# It cannot prove the real engine runs from the DMG. It proves the assembly does not lie about what it
# shipped, which is the failure a push can introduce.
#
# Usage: ./Scripts/test-package.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ava-package-test.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

fail=0
ok() { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

# ---------------------------------------------------------------- synthetic engine tree
# The shape package.sh navigates: Build/release/{bin/Ladybird.app/Contents/{MacOS,Resources},lib},
# plus the vcpkg dynamic dir. The dylibs are real, with real @rpath install names, so otool and dyld see
# exactly what they would see in the real tree — stubs would make the closure walk meaningless.
FIXTURE="${WORK}/fixture"
mkdir -p "${FIXTURE}/bin/Ladybird.app/Contents/MacOS" "${FIXTURE}/bin/Ladybird.app/Contents/Resources/themes" "${FIXTURE}/lib" "${FIXTURE}/vcpkg"

cat > "${WORK}/leaf.c" <<'EOF'
int leaf_value(void) { return 7; }
EOF
cat > "${WORK}/mid.c" <<'EOF'
int leaf_value(void);
int mid_value(void) { return leaf_value() + 1; }
EOF

# A versioned leaf reachable only through a symlink, like liblagom-core.0.dylib -> .0.1.0.dylib: the
# install name names the short form, so a closure walk that copies by realpath loses the name dyld wants.
clang -dynamiclib -o "${FIXTURE}/lib/libleaf.1.2.3.dylib" "${WORK}/leaf.c" \
    -install_name "@rpath/libleaf.1.dylib"
ln -s libleaf.1.2.3.dylib "${FIXTURE}/lib/libleaf.1.dylib"
# The real lib dir carries the unversioned name too; that is the one `-lleaf` resolves at link time.
ln -s libleaf.1.dylib "${FIXTURE}/lib/libleaf.dylib"

# The mid library lives in the vcpkg dir and depends on the leaf, so the walk has to cross both roots.
clang -dynamiclib -o "${FIXTURE}/vcpkg/libmid.dylib" "${WORK}/mid.c" \
    -install_name "@rpath/libmid.dylib" \
    -L"${FIXTURE}/lib" -lleaf \
    -Xlinker -rpath -Xlinker "${FIXTURE}/vcpkg"

# The helper depends on the mid library. Its rpath is absolute and points into the fixture, which is
# what package.sh must delete and replace with @loader_path/../lib.
cat > "${WORK}/helper.c" <<'EOF'
int mid_value(void);
int main(void) { return mid_value() == 8 ? 0 : 1; }
EOF
clang -o "${FIXTURE}/bin/Ladybird.app/Contents/MacOS/WebContent" "${WORK}/helper.c" \
    -L"${FIXTURE}/vcpkg" -lmid \
    -Xlinker -rpath -Xlinker "${FIXTURE}/vcpkg" \
    -Xlinker -rpath -Xlinker "${FIXTURE}/lib"

for helper in WebWorker Compositor RequestServer MediaServer AudioServer ImageDecoder VideoDecoderServer ProcessReaper; do
    cp "${FIXTURE}/bin/Ladybird.app/Contents/MacOS/WebContent" "${FIXTURE}/bin/Ladybird.app/Contents/MacOS/${helper}"
done

cat > "${WORK}/app.c" <<'EOF'
int mid_value(void);
int main(void) { return mid_value() == 8 ? 0 : 1; }
EOF
clang -o "${WORK}/Ava" "${WORK}/app.c" \
    -L"${FIXTURE}/vcpkg" -lmid \
    -Xlinker -rpath -Xlinker "${FIXTURE}/vcpkg" \
    -Xlinker -rpath -Xlinker "${FIXTURE}/lib"

echo "themes" > "${FIXTURE}/bin/Ladybird.app/Contents/Resources/themes/Default.ini"

# ---------------------------------------------------------------- run the packager
# package.sh resolves everything from the repo root, so the fixture is presented at the path it expects.
# A copy of the script with the two roots repointed keeps the real script byte-identical.
PACKAGE="${WORK}/package.sh"
sed -e "s|^BUILD_DIR=.*|BUILD_DIR=\"${FIXTURE}\"|" \
    -e "s|^VCPKG_LIB=.*|VCPKG_LIB=\"${FIXTURE}/vcpkg\"|" \
    -e "s|^OUT_DIR=.*|OUT_DIR=\"${WORK}/out\"|" \
    "${REPO_ROOT}/Scripts/package.sh" > "${PACKAGE}"
chmod +x "${PACKAGE}"

echo "== packaging synthetic tree"
if ! AVA_BINARY="${WORK}/Ava" "${PACKAGE}" --no-build > "${WORK}/log" 2>&1; then
    echo "  FAIL package.sh exited non-zero"
    sed 's/^/       /' "${WORK}/log" | tail -20
    exit 1
fi
APP="${WORK}/out/Ava.app"
LIBS="${APP}/Contents/lib"

# ---------------------------------------------------------------- assertions
echo "== asserting bundle"

# The closure crossed both library roots and kept the name dyld asks for, not the realpath's.
[[ -f "${LIBS}/libmid.dylib" ]] && ok "dylib from the vcpkg root" || bad "libmid.dylib missing"
[[ -f "${LIBS}/libleaf.1.dylib" ]] && ok "versioned dylib under its install name" || bad "libleaf.1.dylib missing"
[[ ! -e "${LIBS}/libleaf.1.2.3.dylib" ]] && ok "not copied under its on-disk name" || bad "copied libleaf under the wrong name"

for helper in WebContent WebWorker Compositor RequestServer MediaServer AudioServer ImageDecoder VideoDecoderServer ProcessReaper; do
    [[ -x "${APP}/Contents/MacOS/${helper}" ]] || bad "helper ${helper} missing"
done
[[ -f "${APP}/Contents/Resources/themes/Default.ini" ]] && ok "resources copied" || bad "resources missing"

# Nothing may still name the build tree: that is the stale-rpath bug that loads another checkout's dylib.
stale=""
for image in "${APP}/Contents/MacOS/Ava" "${APP}/Contents/MacOS/"* "${LIBS}"/*.dylib; do
    case "${image}" in *.entitlements) continue ;; esac
    otool -l "${image}" 2>/dev/null | grep -q "${FIXTURE}" && stale="${stale} $(basename "${image}")"
    otool -L "${image}" 2>/dev/null | grep -q "${FIXTURE}" && stale="${stale} $(basename "${image}")(dep)"
done
[[ -z "${stale}" ]] && ok "no build-tree paths remain" || bad "still points into the build tree:${stale}"

# Every unresolved @rpath dependency is a runtime "library not loaded", so resolve all of them.
missing=""
for image in "${APP}/Contents/MacOS/Ava" "${APP}/Contents/MacOS/"* "${LIBS}"/*.dylib; do
    case "${image}" in *.entitlements) continue ;; esac
    while read -r dep; do
        case "${dep}" in
            @rpath/*|@loader_path/*|@executable_path/*)
                [[ -e "${LIBS}/${dep##*/}" ]] || missing="${missing} ${dep##*/}" ;;
        esac
    done < <(otool -L "${image}" | tail -n +2 | awk '{print $1}')
done
[[ -z "${missing}" ]] && ok "closure complete" || bad "unresolved:${missing}"

# Load it for real: codesign --verify does not exercise dyld, and a wrong Team ID or entitlements only
# shows up at load. This catches exactly the bug that shipped a DMG whose app could not start.
if "${APP}/Contents/MacOS/Ava"; then ok "executable loads and runs from the bundle"; else bad "executable failed to load"; fi
if "${APP}/Contents/MacOS/WebContent"; then ok "helper loads and runs from the bundle"; else bad "helper failed to load"; fi

# JIT is a renderer entitlement only; handing it to every helper is a sandbox weakening.
ents() { codesign -d --entitlements - "$1" 2>/dev/null; }
ents "${APP}/Contents/MacOS/WebContent" | grep -q allow-jit && ok "WebContent has allow-jit" || bad "WebContent lost allow-jit"
ents "${APP}/Contents/MacOS/RequestServer" | grep -q allow-jit && bad "RequestServer has allow-jit it does not need" || ok "RequestServer has no allow-jit"
# The app must keep disable-library-validation: signing the bundle re-signs the executable, and dropping
# it there is what made the first DMG die on "different Team IDs".
ents "${APP}/Contents/MacOS/Ava" | grep -q disable-library-validation \
    && ok "app keeps disable-library-validation" || bad "app lost disable-library-validation"

# ---------------------------------------------------------------- negative case
# A dependency that exists nowhere must stop the build, not produce a bundle with a hole in it.
echo "== packaging with an unsatisfiable dependency"
cat > "${WORK}/orphan.c" <<'EOF'
int orphan(void) { return 1; }
EOF
clang -dynamiclib -o "${WORK}/liborphan.dylib" "${WORK}/orphan.c" -install_name "@rpath/liborphan.dylib"
clang -o "${WORK}/Ava-bad" "${WORK}/app.c" \
    -L"${FIXTURE}/vcpkg" -lmid -L"${WORK}" -lorphan \
    -Xlinker -rpath -Xlinker "${FIXTURE}/vcpkg"
rm -f "${WORK}/liborphan.dylib"
if AVA_BINARY="${WORK}/Ava-bad" "${PACKAGE}" --no-build > "${WORK}/log-bad" 2>&1; then
    bad "packaged a bundle whose dependency does not exist"
else
    grep -q "liborphan" "${WORK}/log-bad" && ok "names the missing dependency" || bad "failed without naming liborphan"
fi

echo
if [[ ${fail} -eq 0 ]]; then
    echo "package assembly: all checks passed"
else
    echo "package assembly: FAILED"
fi
exit ${fail}
