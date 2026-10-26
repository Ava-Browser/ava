# Space settings — functional first-pass review

**Status:** Functional slice accepted locally; exact Arc visual-parity gate remains open.
**Design:** [TDD-SpaceSettings.md](../TDD-SpaceSettings.md).

Implemented: UUID-targeted shared row/dock menus; validated rename/icon/theme drafts;
space management/reorder; confirmed deletion with Essentials and unrelated spaces preserved;
sidebar hierarchy, adaptive Essentials tiles, collapsible pinned region, normal-tab clearing,
keyboard adjacency, and horizontally scrollable space dock. Unsupported Arc profile/folder/
sharing/export commands remain visibly disabled; this is not a container-support release.

Initial independent verification used a temporary scratch directory. Reproduction commands:

```sh
DYLD_LIBRARY_PATH="$(cd Extern/ladybird/Build/release/lib && pwd -P)" \
  swift test --scratch-path .build/verification
/bin/bash Scripts/check-layers.sh
git diff --check
```

Result: **35 tests in 7 suites passed**, layer guard passed, no whitespace errors. The guard
warned that the engine build belongs to a separate checkout; the compared sources agree,
but this does not certify a fresh engine build. The Swift build used a scratch directory
because the original build cache referenced the checkout's old path.

Compared the actual `.toolbar` source region with the committed baseline: **byte-identical**.
No Safari header, address input, navigation controls, or shortcuts changed in this slice.

Review fixes included invalid reorder bounds/duplicate UUIDs, active-space presentation
cleanup before handle destruction, real container-field preservation tests, narrow grid/dock
overflow, sibling tab-close actions, empty-tier drag targets, keyboard/focus/accessibility,
safe manager-sheet routes, and one tested keyboard-order implementation.

Resting and menu captures were inspected privately; they are not published review assets
and some predate final small fixes. They do not comprehensively verify every final UI state
or provide a normalized pixel comparison. Site icons currently use real fallbacks,
not the reference's site-specific favicons. Native menu/material differences remain.

**Still unverified:** final matched-fixture measurements against both Arc references,
complete dark/inactive/accessibility-state screenshots, native picker serialization across
all color spaces, and real-engine handle cleanup under all deletion/error scenarios.
Model tests and worker manual checks do not substitute for those visual/runtime gates.
