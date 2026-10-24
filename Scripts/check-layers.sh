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
    fail_if "Libraries/LibPort is missing. The fork's work lives on branch 'native-port': git -C Extern/ladybird checkout native-port"
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
    git -C "${FORK}" fetch -q upstream master 2>/dev/null || true
fi

if git -C "${FORK}" rev-parse --verify --quiet upstream/master >/dev/null; then
    base="$(git -C "${FORK}" merge-base upstream/master HEAD)"
    stray="$(git -C "${FORK}" diff "${base}" --name-only -- . \
        | grep -vE '^(Libraries/LibPort/|Tests/LibWebView/TestNative|Libraries/CMakeLists\.txt$|Tests/LibWebView/CMakeLists\.txt$)' || true)"
    if [[ -n "${stray}" ]]; then
        echo "FAIL: R7: fork modifies files outside LibPort/ and the native probes:"
        echo "${stray}" | sed 's/^/    /'
        fail=1
    fi
else
    fail_if "R7: the fork has no upstream remote. Run: git -C Extern/ladybird remote add upstream https://github.com/LadybirdBrowser/ladybird.git && git -C Extern/ladybird fetch upstream"
fi

# ---------------------------------------------------------------- layering
if grep -rqE '^import (AppKit|SwiftUI)' "${REPO_ROOT}/Sources/LadybirdBridge"; then
    fail_if "Layer: LadybirdBridge must not import AppKit/SwiftUI"
fi
if grep -rqE '^import CLadybirdPort' "${REPO_ROOT}/Sources/LadybirdUI"; then
    fail_if "Layer: LadybirdUI must not import CLadybirdPort (go through LadybirdEngine)"
fi

if [[ ${fail} -eq 0 ]]; then
    echo "OK: all contract rules hold"
fi
exit ${fail}
