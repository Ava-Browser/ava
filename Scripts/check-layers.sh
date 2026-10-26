#!/bin/bash
# Enforces the contract rules from Documentation/Rules.md. CI runs this; run it before committing.
#
# Exit non-zero on the first violation.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FORK="${REPO_ROOT}/Extern/ladybird"
PORT_DIR="${FORK}/Libraries/LibPort"
fail=0

fail_if() { echo "FAIL: $1"; fail=1; }

# Every check below reads the fork's LibPort directory, so establish it exists first. This is the
# failure a fresh clone hits: the work lives on a branch that is not checked out.
if [[ ! -d "${PORT_DIR}" ]]; then
    fail_if "Libraries/LibPort is missing. The fork's work lives on branch 'ava-port': git -C Extern/ladybird checkout ava-port"
    exit 1
fi

# ---------------------------------------------------------------- R2: shim is C, never ObjC
# Strip // and /* */ comment bodies first: the header *discusses* objc_msgSend in prose, and a
# naive grep matches the discussion rather than the code.
# A full preprocess removes comment bodies; -P omits line markers.
# If clang fails we fall back to the raw text, which is strict (comments then count, so a prose
# mention of objc_msgSend fails the check) rather than permissive. A broken preprocess must never
# silently disable a guard.
strip_comments() {
    local out
    if out="$(clang -x c++ -E -P "$1" 2>/dev/null)"; then
        printf '%s\n' "${out}"
    else
        fail_if "R2: could not preprocess ${1} for the ObjC check (failing closed)"
        cat "$1"
    fi
}
objc_hits=""
for src in "${PORT_DIR}"/*.h "${PORT_DIR}"/*.cpp; do
    [[ -f "${src}" ]] || continue
    if strip_comments "${src}" | grep -qE '#import|objc_msgSend|@interface|@implementation|NS[A-Z][a-zA-Z]*\s*\*'; then
        objc_hits="${objc_hits}\n    ${src}"
    fi
done
if [[ -n "${objc_hits}" ]]; then
    echo -e "FAIL: R2: ObjC found in Libraries/LibPort (the shim must be C ABI + CF pointers only):${objc_hits}"
    fail=1
fi

# ---------------------------------------------------------------- R4: the header is pure C11
# NB: compile a TU that *includes* the header. Checking the header alone trips
# -Wpragma-once-outside-header and reports a false failure.
tmp_c="$(mktemp /tmp/lb-c11-XXXXXX.c)"
printf '#include "ladybird_port.h"\nint main(void){return 0;}\n' > "${tmp_c}"
if ! clang -x c -std=c11 -fsyntax-only -Wall -Wextra -Werror -I "${PORT_DIR}" "${tmp_c}" 2>&1; then
    fail_if "R4: Libraries/LibPort/ladybird_port.h does not compile as pure C11"
fi
rm -f "${tmp_c}"

# ---------------------------------------------------------------- R3: no display link / redraw loop
if grep -rqE 'CVDisplayLink|CADisplayLink|NSView.*display\(' "${REPO_ROOT}/Sources"; then
    fail_if "R3: a display link or manual redraw loop appeared in Sources/ (presentation is demand-driven)"
fi

# ---------------------------------------------------------------- R7: fork changes confined
# Compare against the merge-base, not upstream/master: otherwise every commit upstream has landed
# since this fork's HEAD looks like a local change, and the guard reports hundreds of irrelevant files.
# A fresh `git submodule update --init` clones from the fork, so `upstream` is absent. Add it on
# demand: the fork mirrors upstream, so all the objects are already present and the fetch is cheap.
if ! git -C "${FORK}" rev-parse --verify --quiet upstream/master >/dev/null; then
    if ! git -C "${FORK}" remote | grep -qx upstream; then
        git -C "${FORK}" remote add upstream https://github.com/LadybirdBrowser/ladybird.git 2>/dev/null || true
    fi
    # A shallow submodule (CI clones --depth 1) has no upstream history to merge-base against, so ask
    # for it explicitly. Without --depth this deepens the fetch enough to find the fork point.
    git -C "${FORK}" fetch -q upstream master 2>/dev/null \
        || git -C "${FORK}" fetch -q --unshallow upstream 2>/dev/null \
        || true
fi

base=""
if git -C "${FORK}" rev-parse --verify --quiet upstream/master >/dev/null; then
    base="$(git -C "${FORK}" merge-base upstream/master HEAD 2>/dev/null || true)"
fi

# FAIL CLOSED. An empty base means the diff below would error out and the `|| true` would turn a
# broken guard into an "OK". Never let a hygiene check pass because it could not run.
if [[ -z "${base}" ]]; then
    fail_if "R7: could not determine the upstream fork point, so the check cannot run. Deepen the submodule: git -C Extern/ladybird fetch --unshallow upstream"
else
    if ! stray="$(git -C "${FORK}" diff "${base}" --name-only -- . 2>&1)"; then
        fail_if "R7: git diff against ${base} failed: ${stray}"
        stray=""
    fi

    # Upstream-shaped patches, each explicitly reviewed and cryptographically pinned in a manifest.
    # A filename allowlist alone would permit arbitrary future mutations in those files.
    # Instead, each allowed file must match its exact approved SHA-256 hash.
    unapproved_stray=""
    for file in ${stray}; do
        if [[ "${file}" =~ ^(Libraries/LibPort/|Tests/LibWebView/TestNative|Libraries/CMakeLists\.txt$|Tests/LibWebView/CMakeLists\.txt$) ]]; then
            continue
        fi

        # Use case rather than associative arrays so macOS /bin/bash 3.2 can run the guard.
        case "${file}" in
            Libraries/LibWebView/BrowsingSession.h) expected_hash="05b73d401b6474697cdf8f48f40fb418434a66dd3c42a7dfc22ea623a85f571f" ;;
            Libraries/LibWebView/BrowsingSession.cpp) expected_hash="6f6a4adb5c5d442ac27f5452ef0fd69e7b149506ea019cc789d7c7c242192219" ;;
            Libraries/LibWebView/Application.h) expected_hash="5ceaf1373f66ed80db66941659c881a47c2750497600bb4295ca672689711caf" ;;
            Libraries/LibWebView/Application.cpp) expected_hash="048d04bf7bc280fd59a2752d16666223972fce6f54ce7961017d717813ca6cd9" ;;
            *) expected_hash="" ;;
        esac
        if [[ -n "${expected_hash}" ]]; then
            actual_hash="$(shasum -a 256 "${FORK}/${file}" 2>/dev/null | awk '{print $1}')"
            if [[ "${actual_hash}" != "${expected_hash}" ]]; then
                echo "FAIL: R7: Approved patch file ${file} has drifted from approved hash!"
                echo "    Expected: ${expected_hash}"
                echo "    Actual:   ${actual_hash}"
                fail=1
            fi
        else
            unapproved_stray="${unapproved_stray}\n    ${file}"
        fi
    done

    if [[ -n "${unapproved_stray}" ]]; then
        echo -e "FAIL: R7: fork modifies files outside LibPort/, native probes, and approved patch manifests:${unapproved_stray}"
        fail=1
    fi
fi

# ---------------------------------------------------------------- layering
if grep -rqE '^import (AppKit|SwiftUI)' "${REPO_ROOT}/Sources/LadybirdBridge"; then
    fail_if "Layer: LadybirdBridge must not import AppKit/SwiftUI"
fi
if grep -rqE '^import CLadybirdPort' "${REPO_ROOT}/Sources/LadybirdUI"; then
    fail_if "Layer: LadybirdUI must not import CLadybirdPort (go through LadybirdEngine)"
fi

# ---------------------------------------------------------------- S1: Unmanaged stays in Bridge
# LadybirdBridge owns all Unmanaged<> plumbing; upward layers never see an opaque context pointer.
bridge_src="${REPO_ROOT}/Sources/LadybirdBridge"
um_hits="$(grep -rlE 'Unmanaged' "${REPO_ROOT}/Sources" 2>/dev/null | grep -v "^${bridge_src}/" || true)"
if [[ -n "${um_hits}" ]]; then
    echo "FAIL: S1: Unmanaged used outside Sources/LadybirdBridge:"
    echo "${um_hits}" | sed 's/^/    /'
    fail=1
fi

# ---------------------------------------------------------------- S3: no hidden thread hops
# One thread, no exceptions: a DispatchQueue/Task.detached anywhere reintroduces every race R2/R5
# were designed to eliminate. If a need appears, re-litigate S3 in Documentation/Rules.md.
if grep -rqE 'DispatchQueue|Task\.detached' "${REPO_ROOT}/Sources"; then
    grep -rnE 'DispatchQueue|Task\.detached' "${REPO_ROOT}/Sources" | sed 's/^/    /'
    fail_if "S3: a thread hop appeared in Sources/ (the pump is main-thread; no exceptions)"
fi

# ---------------------------------------------------------------- provenance: audit what we build
# The guard reads ${FORK}, but the build reads ${FORK}/Build/release — and that is a *symlink* to a
# second checkout whenever one is reused instead of rebuilding for hours. Those two trees can and
# do diverge: the symlinked build tree records its own CMAKE_HOME_DIRECTORY. A guard that audits a
# tree the build never read is a green light over unknown code.
BUILD_TREE="${FORK}/Build/release"
if [[ -d "${BUILD_TREE}" ]]; then
    build_home="$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "${BUILD_TREE}/CMakeCache.txt" 2>/dev/null | head -1)"
    fork_real="$(cd "${FORK}" && pwd -P)"
    if [[ -n "${build_home}" && "${build_home}" != "${fork_real}" ]]; then
        # The build tree belongs to another checkout. That is legitimate during bring-up (a 3GB,
        # hours-long build is worth sharing), but it means a green guard does not vouch for the
        # dylib. Verify the sources actually agree, then warn rather than fail.
        drift=""
        for dir in Libraries/LibPort Tests/LibWebView; do
            [[ -d "${build_home}/${dir}" ]] || continue
            if ! diff -rq "${fork_real}/${dir}" "${build_home}/${dir}" >/dev/null 2>&1; then
                drift="${drift}\n    ${dir}"
            fi
        done
        if [[ -n "${drift}" ]]; then
            echo "FAIL: the build tree is a different checkout AND the sources have diverged:$(printf "${drift}")"
            echo "    build tree: ${build_home}"
            echo "    audited:    ${fork_real}"
            fail=1
        else
            echo "WARN: build tree is a separate checkout (${build_home})."
            echo "      Sources agree with ${fork_real} right now, but a green guard does not"
            echo "      vouch for the built dylib. Rebuild in this checkout to close the gap."
        fi
    fi
fi

if [[ ${fail} -eq 0 ]]; then
    echo "OK: all contract rules hold"
fi
exit ${fail}
