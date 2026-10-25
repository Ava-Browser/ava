# Safari-Style Header First Pass Implementation Report

**Status:** Implemented — partial reference parity; final UI acceptance remains open.
**Reference Document:** `Documentation/TDD-SafariHeader.md`
**Reference Asset:** `Documentation/Screenshots/safari-header-reference-sanitized.png`

---

## 1. Executive Summary

This pass implements and verifies the real-control first pass of the Safari-reference header specified in `Documentation/TDD-SafariHeader.md` within the isolated `safari-header` worktree.

Following coordinator review, the implementation was revised to:
1. Wire real blur handling in `AddressNativeField.Coordinator.controlTextDidEndEditing` so focus loss exits editing and restores the resting host display without reentrant duplicate cancellations.
2. Implement an attachment-aware native field subclass (`FocusableAddressTextField`) that defers focus requests until `viewDidMoveToWindow()` is called on the main thread, consuming the focus token only after `makeFirstResponder` and `selectText(nil)` actually execute.
3. Add `performKeyEquivalent(with:)` for Cmd-L in `FocusableAddressTextField` to ensure repeated Cmd-L while editing re-selects the entire URL text.
4. Replace `focusRingType.none` and the constant gray border with an explicit semantic focus ring (`Color.accentColor` with 1.5 pt stroke border) during editing.
5. Expand the resting `Button` click target to span the full middle area of the capsule (`frame(maxWidth: .infinity, maxHeight: .infinity)` within `padding(.horizontal, 32)`), activating editing anywhere in the middle without intercepting the independent reload button or leading affordance.
6. Verify full-URL selection, live blur, and fresh evidence screenshots with synthetic `example.com` state.

The implementation has automated state/native-field coverage and sanitized UI captures. Current
stack verification results are recorded below; exact Safari parity and final native review remain open.

---

## 2. Measured Dimensions vs Reference

| Element | Reference Capture (2× backing) | Point Equivalent (at 2×) | Ava Build (Measured) | Match / Variance |
| --- | --- | --- | --- | --- |
| **Visible window width** | 1920 px | 960 pt | 960 pt (window bounds) | **Exact** |
| **Header height** | 106 px | 53 pt | ~52–54 pt | **~1 pt** (native toolbar) |
| **Capsule height** | 70 px | 35 pt | 32 pt | **~3 pt** (system macOS control standard) |
| **Address capsule width** | 720 px | 360 pt | 360 pt ideal (296 pt with open sidebar) | **Exact ideal**; adapts to split-view |
| **Traffic light diameter** | 28 px | 14 pt | 14 pt | **Exact** (native AppKit) |
| **Address text font size** | ~26 px | ~13 pt | 13 pt regular | **Exact** |
| **Leading / Trailing icons**| ~28 px | ~14 pt | 14 pt inside 28×28 pt boxes | **Exact** |

---

## 3. Evidence-Based Feature Parity Table

| Control / Behavior | Implemented | Verified via Automated Test | Verified via Live UI / AX | Parity Status | Notes |
| --- | :---: | :---: | :---: | --- | --- |
| **Native Traffic Lights** | Yes | Yes (AppKit) | Yes (screencapture) | **Verified Parity** | System-owned close, minimize, zoom controls. |
| **Sidebar Toggle** | Yes | Yes (AppKit) | Yes (screencapture) | **Partial Parity** | Native split-view toggle retained (⌃⌘S). Disclosure menu omitted (no sidebar options yet). |
| **History Group (Back/Forward)** | Yes | Yes (test) | Yes (screencapture, AX) | **Verified Parity** | Grouped in `ControlGroup` with `.controlGroupStyle(.navigation)`. |
| **Standalone Reload Removed** | Yes | Yes (test) | Yes (screencapture, AX) | **Verified Parity** | Redundant standalone button removed from navigation group. |
| **Quiet Address Capsule** | Yes | Yes (UI) | Yes (screencapture) | **Verified Parity** | Rounded 8 pt continuous radius, semantic fill, 32 pt height. |
| **Centered Resting Host** | Yes | Yes (test) | Yes (screencapture, AX) | **Verified Parity** | Host centered; subdomains preserved; ports 80/443 omitted; unusual ports shown. |
| **Full URL Click-to-Edit** | Yes | Yes (test) | Yes (AX: loc=0, len=20) | **Verified Parity** | Clicking middle capsule enters edit mode and loads full URL. |
| **Native Select-All on Entry** | Yes | Yes (test) | Yes (AX: loc=0, len=20) | **Verified Parity** | `FocusableAddressTextField` calls `selectText(nil)`. |
| **Repeated Cmd-L Selection** | Yes | Yes (test) | Yes (AX: loc=0, len=20) | **Verified Parity** | Handled via `performKeyEquivalent:` and `editRequestToken`. |
| **Escape Draft Discard** | Yes | Yes (test) | Yes (screencapture) | **Verified Parity** | `cancelOperation:` cancels draft and restores resting host. |
| **Blur Draft Discard** | Yes | Yes (test) | Yes (AX: restores resting button) | **Verified Parity** | Focus loss invokes `controlTextDidEndEditing` -> `onCancel()`. |
| **Visible Focus Ring** | Yes | Yes (UI) | Yes (screencapture) | **Verified Parity** | `state.isEditing ? Color.accentColor : secondary` (1.5 pt stroke). |
| **In-field Trailing Reload** | Yes | Yes (test) | Yes (screencapture, AX) | **Verified Parity** | Sits at trailing capsule edge, wired to `model.reload()` (⌘R). |
| **Resting Click Target** | Yes | Yes (UI) | Yes (Accessibility activation) | **Partial Parity** | Spans full middle area between 32 pt margins; final geometry review remains open. |
| **Tab Isolation** | Yes | Yes (test) | Verified in model | **Verified Parity** | Tab switch discards active draft; no leakage between tabs. |
| **Stale Callback Protection** | Yes | Yes (test) | Verified in state | **Verified Parity** | Engine callbacks update URL without overwriting active user typing. |
| **Full URL Copying** | Yes | Yes (test) | Verified with isolated PB | **Verified Parity** | Copies complete URL (scheme, host, path, query), not visible host. |
| **New Tab Action (`+`)** | Yes | Yes (test) | Yes (screencapture, AX) | **Verified Parity** | Retained in `.primaryAction`, wired to `openTab()` (⌘T). |
| **Downloads / Bookmarks / Extensions** | No | N/A | N/A | **Omitted (Planned)** | Real engine features absent; dead fake controls omitted per spec. |
| **Share Sheet & Tab Overview** | No | N/A | N/A | **Omitted (Planned)** | Awaiting engine-owned Share seam and real tab overview graph. |
| **Autocomplete / Search Suggestions**| No | N/A | N/A | **Omitted** | Explicitly out of scope for first visual pass. |

---

## 4. Test Suite Execution & Layer Discipline

### Automated Tests
Command: `swift test`
Result on the sanitized stack: **58 tests in 10 suites passed**. The engine library came from
a source-matching shared build; this is not proof of a fresh engine build in this checkout.

Suites executed:
1. `Native address text field behavior` (5 tests):
   - `deferredFocusOnWindowAttachment`: Verifies focus request is deferred until attached to window, then consumes token and selects full string.
   - `repeatedFocusTokenReselectsAll`: Verifies token increment re-selects entire text after deselection.
   - `performKeyEquivalentCmdLReselectsAll`: Verifies Cmd-L key event directly re-selects entire text in field editor.
   - `blurInvokesCancelCallback`: Verifies moving first responder away invokes `onCancel()` without submit.
   - `submitDoesNotTriggerBlurCancel`: Verifies Enter key calls `onSubmit()` without triggering blur cancel.
2. `Address bar resting display formatting` (8 tests):
   - Ordinary hosts, subdomains, standard ports, unusual ports, IPv6 brackets, empty/blank strings, non-HTTP schemes safe raw display, unparseable input safe raw display.
3. `Address bar draft lifecycle and tab isolation` (9 tests):
   - Resting state vs copyable URL, beginEditing with full URL, repeated Cmd-L token, blank tab initialization, discard draft, commit draft, stale callback preservation, tab switch draft isolation, isolated pasteboard copy.
4. `Address bar input resolution` (5 tests).
5. `App Settings persistence and validation` (6 tests).
6. `Workspace persistence` (5 tests).
7. `Wheel delta conversion` (4 tests).
8. `Surface ref conversion` (1 test).
9. `Runtime teardown` (2 tests).

### Contract & Layer Guard
Command: `/bin/bash ./Scripts/check-layers.sh`
Result: **`OK: all contract rules hold`**, with the documented shared-build provenance warning.
- Pure C ABI in LibPort (R2, R4).
- No display links or manual redraw loops (R3).
- Fork changes confined (R7).
- Layer boundary: `LadybirdBridge` has zero AppKit/SwiftUI imports; `LadybirdUI` has zero `CLadybirdPort` imports.
- `Unmanaged` confined strictly to `LadybirdBridge` (S1).
- Single-thread pump invariant: zero `DispatchQueue` or `Task.detached` in `Sources/` (S3).
- Provenance audit: warning noted regarding symlinked build tree; sources match checked-out commit `66616b4deeb42fbc7ce722075f22b1b1e5f5891a`.

---

## 5. UI Evidence Artifacts

Captured from a dedicated synthetic `example.com` window and saved in `Documentation/Screenshots/`:

1. `header-resting-960pt.png` (960×700 px): Reference width resting header with centered `example.com`, quiet capsule, leading globe, trailing in-field reload, grouped history chevrons, trailing New Tab.
2. `header-editing-960pt.png` (960×700 px): Editing mode showing full URL (`https://example.com/`) leading-aligned in `FocusableAddressTextField` with complete selection highlight and visible accent-color focus outline.
3. `header-repeated-cmdl.png` (960×700 px): Repeated Cmd-L re-triggering full text selection (`location=0, length=20`) verified via Accessibility API.
4. `header-after-escape.png` (960×700 px): Escape key discards draft without navigating, immediately restoring centered resting host `example.com`.
5. `header-after-blur.png` (960×700 px): Focus loss (clicking outside in sidebar or detail) immediately discards draft and restores the resting button affordance.
6. Collapsed-sidebar recapture remains required; the previous asset was removed because it did not show the claimed state.
7. `header-narrow-620pt.png` (620×500 px): Narrow window minimum width showing native macOS toolbar overflow handling (`»`).
8. `header-narrow-620pt-collapsed.png` (620×500 px): Narrow 620 pt window with collapsed sidebar.
9. `header-dark-960pt.png` (960×700 px): Dark mode appearance showing proper semantic coloring of capsule surface and native controls.

---

## 6. Remaining Evidence Gates

- Recapture the collapsed-sidebar state and verify it is visually distinct before merge.
- Re-run Accessibility focus/selection/blur checks against the final stacked commit.
- Verify no Ava-owned test process remains after runtime review; do not publish local process identifiers.
