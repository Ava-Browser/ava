# Implementation handoff — 2026-10-25

## Reviewed baseline and current scope

- `TDD-SpaceSettings.md`: functional sidebar/settings slice committed as `6155b4e`.
  Coordinator independently verified **36 tests in 7 suites**, layer guard, and exact
  toolbar source identity. See `Reports/SpaceSettings-FirstPass.md` for remaining visual
  and runtime gaps. This is NOT a claim of exact Arc pixel parity.
- `PRD-Settings.md` + `TDD-Settings.md`: inventory/design finalized in `8758a9d`, with
  migration/container evidence corrections in `d95832c`. New Settings capabilities have
  NOT shipped merely because the designs are approved.
- `TDD-SafariHeader.md`: first real-control pass revised after native focus/blur review.
  Worker reported Accessibility selection/blur evidence; coordinator independently ran
  the STACKED sidebar + header app: **58 tests in 10 suites passed**, layer guard passed.
  Final native/UI/measurement review remains a draft-PR gate.
- Engine baseline: `66616b4deeb42fbc7ce722075f22b1b1e5f5891a`, default branch `ava-port`.
  Search-settings PR head is `389091524c`. Independent audit found and corrected real-schema,
  custom-catalog, fallback-reset, status, and unbounded-wait defects. Coordinator reran the
  corrected isolated native probe with new-shim provenance. The app pin remains unchanged;
  advance it only in a deliberate post-review integration change.

## Pull requests and preserved evidence

- [Ava #2 — sidebar/settings foundation](https://github.com/Ava-Browser/ava/pull/2)
- [Ava #3 — Safari header draft](https://github.com/Ava-Browser/ava/pull/3), stacked on #2
- [ava-engine #1 — search settings/probe](https://github.com/Ava-Browser/ava-engine/pull/1)

The engine PR preserves portable isolated-build guidance and results in
`Tests/LibWebView/TestNativeSettingsSearch.md`. Header screenshots and its revised report
are in #3. See [M6 readiness](Reports/M6-Readiness.md) and
[manual-unload readiness](Reports/ManualUnload-Readiness.md). Manual unload stopped at
investigation: **no implementation or test pass is claimed**. Do not open/merge an empty
implementation PR for that checkpoint.

## Resume order and open gates

1. Review/merge the sidebar+design PR. Preserve the Safari-style header separation and
   the existing preferences/graph paths. Keep unrelated local `.gitignore` edits out.
2. Review the separate header PR. Re-run the COMBINED app suite after stacking onto the
   sidebar commit. Confirm native first/repeated Cmd-L selects the full UTF-16 URL,
   focus requests survive window attachment, blur/Escape discard without submitting,
   and sidebar commands/sheets still work. A screenshot without a selected range is
   not select-all evidence. Native UI tests must not alter the general clipboard.
3. Complete the search engine fork/probe review before Bridge or Settings UI work.
   Require actual loaded-shim provenance and bounded native probe execution—not just
   C++ source inspection, a generated compile command, or an in-memory round-trip.
   New/old resolver APIs must honor explicit search-off; missing custom providers fail
   closed; raw URLs/host:port still work; policy must reset with engine lifetime.
4. Migration must preserve current/legacy custom/provider/suggestions data. Raw
   `searchEngine.engine = null` is ambiguous: unrelated upstream saves also write null.
   Do not infer user intent or silently start sending searches to a fallback provider.
5. Only after that gate: implement the reviewed atomic desired-preferences record,
   typed Bridge/Engine adapter, then populated General/Search panes. Existing chrome
   preferences remain in UserDefaults. No suggestions UI before real native integration.
6. DNS remains UNVERIFIED: actual System/UDP/TLS routing, TLS authentication/no-downgrade,
   DNSSEC, hostname bootstrap, proxy full/partial/PAC applicability, CLI overrides,
   running/new helpers and cache semantics need deterministic probes. No DoH or fake
   resolver-health success. A setter enqueues configuration; it does not verify DNS.
7. Manual inactive-space unload is a separate pending slice. Preserve descriptors and
   global Essentials; never unload the displayed tab; confirm potential live form-state
   loss; prove scoped helper reclamation without killing other processes. Do not infer
   one process per tab or exact memory reduction from model-only tests.
8. Containers remain blocked: historical TestNativeContainers exercises default/private
   views and direct CookieJars, with in-process database reopen—not two named-container
   page/network sessions or a cold app restart. It also lacks fail-closed assertions
   for some printed results and bounded waiting. Rebinding protected `m_session` alone
   does not prove the WebContent/RequestServer session changed. Add rigorous probes;
   upstream-shaped client/session plumbing requires separate approval. Keep Set Profile
   disabled; a named container is not a complete profile.
9. Gestures are not implemented. A threshold at gesture end is not the specified 1:1
   interaction. Define page-horizontal-scroll arbitration, cancellation, reduced motion,
   and a safe interactive presentation path before source work.
10. Finish normalized Arc comparisons using final-source screenshots at matched sidebar
    width/scale, including dark/inactive, empty/collapsed tiers, overflow, and keyboard
    focus. Current fallbacks are not Arc site favicons. Missing Safari Share/overview/
    downloads/bookmarks controls remain omitted until they have real implementations.

## Verification and work preservation

Use the PR branches and their technical reports for source/test state. Draft PRs preserve
incomplete work; they are not merge approval. Keep local agent/task/terminal metadata out
of public documentation. Use isolated worktrees with one writer each.

The build guard supports macOS `/bin/bash` 3.2. When reusing an engine build from another
checkout, compare source bytes and report provenance warnings.
Never repoint copied submodule `.git` metadata. Do not write shared CMake/generated/lib
outputs from a different worktree. Check available disk space before cold engine builds.
Isolated temporary shim/probe output
may reuse audited cached dependencies read-only, but record exact commands and prove the
new shim is the one loaded. Never claim a dry-run built/tested the code.

Use temporary UserDefaults suites, graph files, and named pasteboards in tests. Serialize
Ava launches because default app/profile paths are shared; record/close only your launched
PID. No broad pkill. Local `/tmp` captures/reports are not durable CI artifacts: preserve
sanitized evidence needed for review in the PR or repository, and label missing evidence.

Gitleaks 8.30.1 found no detections across all local app Git refs or the outgoing engine
search changes during review. This is not a full upstream-engine history scan, an image/PII
audit, or proof that no secret exists. Local paths and coordination identifiers were removed
from current app documentation; prior published commits are unchanged. Signed/self-contained
packaging and universal runtime/visual verification remain outstanding. Public visibility is
not a release-readiness certificate.
