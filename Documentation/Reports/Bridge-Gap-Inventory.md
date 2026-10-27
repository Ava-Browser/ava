# Bridge Gap Inventory: Qt surface vs the C ABI

**Status:** Measured inventory. Nothing here is inferred from the Qt *app* code alone — every "used by Qt"
claim names the `ViewImplementation` symbol Qt calls, and every "missing" claim names the absence in
`Libraries/LibPort/ladybird_port.h`.

**Goal:** make the ABI complete enough that new Mac UI work never requires another engine change. The
thing to get right once is the *shape*; the *tiers* below say what is worth bridging at all.

**Method:** the complete `ViewImplementation` surface (90 `on_*` callback members, the public methods Qt
calls) was diffed against the 21 exported `Lb*` functions and the 10 `LbCallbacks` fields. Every row below
is one of those two lists.

---

## 0. Read this first: most of these are bugs, not gaps

B1–B7 are not "a feature we have not built yet". They are things the app does today that are wrong or dead,
and four of them make ordinary pages look broken. B8 is a false promise in the header that will mislead the
next person who adds a request callback.

### B1. ⌘C / ⌘V / ⌘X / ⌘A / ⌘Z in page content do nothing

`PortWebView.translate` maps AppKit virtual key codes through a switch whose `default` arm is
`PortKey.invalid`, and it deliberately suppresses `code_point` whenever `.command` is held:

```swift
if !flags.contains(.command), let characters = event.characters, ...
```

So ⌘C crosses the ABI as `(key = invalid, code_point = 0, modifiers = Mod_Super)`. The engine's editing
shortcuts require the key itself — `EventHandler` checks `key == UIEvents::KeyCode::Key_C` and friends
under `Mod_PlatformCtrl`, which is `Mod_Super` on macOS. `PortKey` mirrors only non-text keys, so no
letter ever reaches it.

There is no Edit menu either: `Sources/LadybirdMac/main.swift` declares no `Commands`, so the standard
`copy:`/`paste:` selectors go down the responder chain and `PortWebView` does not implement them.

Consequence: copying text out of a page is impossible. This is the single most user-visible defect here.

### B2. `<select>` and `<input type="file">` are dead controls

`ViewImplementation::did_request_select_dropdown` and `did_request_file_picker` both record the requesting
page and then only call the host callback **if it exists**. No ABI callback is installed, so:

- the dropdown never opens, and the `HTMLSelectElement` stays `is_open` forever;
- no file chooser ever appears, and the input stays open.

Clicking again does not help: the engine treats a request from the *same* page as non-conflicting and takes
the same silent path. Any form with a `<select>` or a file input is unusable.

### B3. `target="_blank"` and `window.open()` appear to do nothing, and leak

`HeadlessWebView`'s constructor installs its own `on_new_web_view`, which builds a child
`HeadlessWebView` and adopts it. `LibPort` never overrides it and never learns a child exists, so a popup
is created inside the engine and never displayed. `HeadlessWebView::close_child_web_views` has no callers
anywhere, so those children live until the app quits.

### B4. A WebContent crash leaves a frozen frame with no explanation

`on_web_content_crashed` is assigned only by `HeadlessWebView::adopt_child_web_view`, for child views.
For the root view `LibPort` creates it stays empty, so nothing crosses the ABI when a renderer dies. The
engine sets its crash state and gates presentation on it; the tab keeps showing its last frame forever.
Reload does recover, because `ViewImplementation::load` calls `prepare_for_navigation_after_crash`.

### B5. Reload is a fresh navigation, not a reload

`BrowserModel.reload()` calls `load(currentURL)`, which reaches `ViewImplementation::load` — never
`ViewImplementation::reload`. So `m_history_visit_transition_for_next_load` stays `Link` instead of
`Reload`, `on_before_browser_initiated_navigation` never fires, cache bypass is impossible, and a stopped
navigation is not retried. There is no `LbTabReload` in the ABI at all.

### B6. Pages cannot be dark, on a dark-mode Mac

`LbTabCreate` loads `themes/Default.ini` unconditionally, and `HeadlessWebView::system_theme` hands that
same buffer to every page. `Base/res/themes/Dark.ini` is never selected. Qt instead builds the palette
from the native appearance and translates it into a system theme.

`AppSettings.applyAppearance` only touches `NSApp.appearance`, so the chrome goes dark while page content
stays light and `prefers-color-scheme` reports light. Two more pieces are missing for a real fix:
`set_preferred_color_scheme` (no ABI) and a themed `system_theme` (needs a shim-side override).

### B7. No hover at all: no `:hover`, no pointer cursor, no tooltips

`Sources/` contains no `NSTrackingArea`. AppKit delivers `mouseMoved` only for a tracking area (or with
`acceptsMouseMovedEvents`), so `PortWebView.mouseMoved` is never called. No cursor rects or
`cursorUpdate` are installed either.

So CSS `:hover` never applies, the cursor never becomes a pointing hand over a link, and `title=`/tooltips
never show. Links look inert until clicked.

### B8. The header's "absent is safe" claim is false — and it is load-bearing

`ladybird_port.h` says, of the four blocking dialogs:

> All four are optional, and absent is safe: with no callback installed the engine answers itself
> (alert closes, confirm declines, prompt cancels, before_unload allows).

Measured, that is not true for this shim. `PortWebView` derives from `HeadlessWebView`, whose constructor
already installed `on_request_alert` / `on_request_confirm` / `on_request_prompt` handlers that only set
`m_pending_dialog`. `LibPort` then either replaces those handlers (when the host supplies a callback) or
leaves the recording ones in place (when it does not). Nothing ever calls `Page::alert_closed` /
`confirm_closed` / `prompt_closed` in the second case.

`Page::did_request_alert` blocks in `spin_event_loop_until_dialog_closed` until an answer arrives, so a
host that installs no dialogs does not get a self-answering engine — it gets a permanently wedged tab. The
safe-to-omit guarantee holds for a fresh `ViewImplementation`, which this shim is not.

This matters beyond the header's wording: it is the reason `PortCallbacks.installsAllDialogs` exists as an
all-or-none gate, and the reason any *future* request group cannot copy the "absent means the engine answers
itself" assumption. Every request callback in this shim must be paired with an explicit answer path, and
an absent one must be treated as "this feature is unavailable", never as "the engine will cope".

---

## 1. What the ABI has today

21 functions and 10 callback fields (the last four optional-when-present).

| Group | Present |
|---|---|
| Lifecycle | `LbAppCreate`, `LbAppPump`, `LbAppStartPump`, `LbAppStopPump`, `LbAppDestroy` |
| Tabs | `LbTabCreate`, `LbTabDestroy`, `LbTabLoad`, `LbTabGetSurface`, `LbTabSetViewport` |
| Input | `LbTabSendMouse`, `LbTabSendKey`, `LbTabTypeText` |
| History | `LbTabTraverseHistory`, `LbTabCanTraverseHistory` |
| Address bar | `LbResolveUserInput`, `LbStringFree` |
| Dialogs | `LbTabAnswerAlert`, `LbTabAnswerConfirm`, `LbTabAnswerPrompt`, `LbTabAnswerBeforeUnload` |
| Callbacks | ready-to-paint, url_change, load_finish, title, loading, favicon, + the four dialogs |

---

## 2. Gap table

`Qt` = the symbol `UI/Qt/` actually uses. "Cost" is the shape of the C-side work, not the UI work.

### 2.1 Callbacks Qt installs that the ABI cannot express

| # | Engine callback | Qt's use | Tier |
|---|---|---|---|
| C1 | `on_load_start` | clears popovers, starts the spinner | 2 |
| C2 | `on_top_level_navigation_commit` | resets content-blocking popover state | 2 |
| C3 | `on_browser_history_traversal_complete` | same reset | 2 |
| C4 | `on_web_content_crashed` | crash overlay (B4) | 2 |
| C5 | `on_crash_overlay_state_change` | shows/hides the overlay | 2 |
| C6 | `on_cursor_change` | pointer/ibeam/text cursor | 2 |
| C7 | `on_link_hover` / `on_link_unhover` | hover URL label | 2 |
| C8 | `on_request_tooltip_override`, `on_stop_tooltip_override`, `on_enter_tooltip_area`, `on_leave_tooltip_area` | tooltips | 2 |
| C9 | `on_audio_play_state_changed` | mute badge on the tab | 2 |
| C10 | `on_screen_wake_lock_state_changed` | sleep inhibitor | 3 |
| C11 | `on_find_in_page` | "3 of 17" | 2 |
| C12 | `on_theme_color_change`, `on_page_background_color_change` | chrome tint, window colour | 3 |
| C13 | `on_content_blocking_change` | blocker badge | 3 |
| C14 | `on_performance_stats` | dev monitor | 4 |
| C15 | `on_new_web_view` | popup / `target=_blank` (B3) | 2 |
| C16 | `on_close`, `on_activate_tab` | popup lifecycle | 2 |
| C17 | `on_input_method_state_change` | IME caret placement | 3 |
| C18 | `on_finish_handling_key_event` | native text-editing bindings | 3 |
| C19 | `on_request_permission` | microphone prompt | 3 |
| C20 | `on_request_external_url_confirmation` | "open in another app?" | 3 |
| C21 | `on_request_select_dropdown` | `<select>` popup (B2) | **1** |
| C22 | `on_request_file_picker` | file input (B2) | **1** |
| C23 | `on_request_color_picker` | `<input type=color>` | 3 |
| C24 | `on_request_set_prompt_text` | prompt retry text | 3 |
| C25 | `on_request_dictionary_lookup` | AppKit dictionary | 4 |
| C26 | `on_network_request_started` … `_finished`, `on_console_message`, `on_resource_status_change`, `on_received_js_console_result` | DevTools | 4 |
| C27 | the whole `on_received_*` / `on_dom_mutation_received` / `on_debugger_*` family | DevTools | 4 |
| C28 | `on_received_accessibility_tree`, `on_accessibility_focus_changed` | accessibility bridge | 3 |
| C29 | context menus: `page_context_menu`, `link_context_menu`, `selected_text_link_context_menu`, `image_context_menu`, `media_context_menu` | right-click menus | 3 |
| C30 | `on_request_website_issue_report`, `on_crash_report_saved` | issue reporting | 4 |

### 2.2 Methods Qt calls that the ABI cannot express

| # | Engine method | Qt's use | Tier |
|---|---|---|---|
| M1 | `reload(BypassCache)`, `stop_loading` | the reload/stop button (B5) | **1** |
| M2 | `set_preferred_color_scheme`, `set_preferred_contrast`, `set_preferred_motion` | page dark mode (B6) | **1** |
| M3 | `zoom_in`, `zoom_out`, `set_zoom`, `reset_zoom`, `zoom_level` | ⌘+ / ⌘- / ⌘0 | 2 |
| M4 | `select_all`, `undo`, `redo`, `paste_from_clipboard`, `selected_text`, `cut_selected_text` | Edit menu (B1) | **1** |
| M5 | `find_in_page`, `find_in_page_next_match`, `find_in_page_previous_match`, `find_in_page_end` | ⌘F | 2 |
| M6 | `toggle_page_mute_state`, `page_mute_state` | mute button | 2 |
| M7 | `set_is_fullscreen`, `is_fullscreen`, `exit_fullscreen` | page fullscreen | 3 |
| M8 | `set_system_visibility_state`, `set_has_system_focus` | background-tab throttle, `document.hasFocus()` | 2 |
| M9 | `request_close`, `request_close_preflight`, `prepare_for_close_without_prompting`, `force_close`, `needs_beforeunload_check` | close-with-unsaved-work (today Ava answers a `beforeunload` it never asked for) | 2 |
| M10 | `set_window_size`, `set_window_position`, `set_display_metadata`, `update_screen_rects` | `window.resizeTo`, screen info, frame pacing | 3 |
| M11 | `session_history_snapshot`, `restore_session_history_from_snapshot` | real session restore | 3 |
| M12 | `traverse_the_history_to_step`, `session_history_traversal_menu_items`, `recent_history_entries` | back/forward long-press menu | 3 |
| M13 | `get_source` | View Source | 3 |
| M14 | `take_screenshot(ScreenshotType)` | screenshot tool | 4 |
| M15 | `set_viewport_corner_radius`, `set_has_rounded_corners` | rounded page corners | 3 |
| M16 | `set_marked_text_from_input_method`, `commit_text_from_input_method`, `unmark_text_from_input_method` | IME | 3 |
| M17 | `web_content_pid`, `crash_report_name`, `crash_overlay_failed_url` | crash reporting | 4 |
| M18 | `set_next_history_visit_transition` | correct history classification | 2 |
| M19 | `initialize_tab(VisibilityState)` / `set_device_pixel_ratio_for_testing` | already used, but the only public scale setter is named `_for_testing` | **1** |
| M20 | `set_scales_frames_to_fit`, `enable_picture_in_picture_controls`, `inspect_*`, `run_javascript`, `debug_request` | PiP, DevTools | 4 |

Tier 1 = Ava's current UI is wrong without it. Tier 2 = the obvious next features, and needed for the app to
feel finished. Tier 3 = Qt parity minus DevTools. Tier 4 = deliberately never (DevTools, WebDriver, PiP,
bookmarkets internals, session store, crash upload).

---

## 3. The shape to build, and why it is the whole point

The header's rule R4 says additive-only, and a previous review already rejected the naive solution —
appending fields to `LbCallbacks` — for a concrete reason: field offsets are baked into Swift at compile
time, so a widened struct run against an older dylib is an immediate startup `SIGSEGV`, not a stale build.

So each new concern gets **its own size-tagged struct and its own registration function**:

```c
typedef struct LbPageCallbacks {
    uint32_t struct_size;   // sizeof(this struct), written by the caller
    uint32_t version;       // LB_CALLBACKS_VERSION
    void (*on_load_start)(void* ctx, uint64_t tab);
    void (*on_navigation_commit)(void* ctx, uint64_t tab);
    void (*on_history_traversal_complete)(void* ctx, uint64_t tab);
    void (*on_crash)(void* ctx, uint64_t tab, int32_t reason);
    void (*on_new_tab)(void* ctx, uint64_t parent_tab, uint64_t new_tab, int activate);
    // ...
} LbPageCallbacks;

// Returns 1 when applied, 0 when this dylib predates the group or the size is short. A host that
// fails to register simply loses the feature, and never crashes.
int LbAppSetPageCallbacks(LbApp*, const LbPageCallbacks*);
```

Why this shape earns its boilerplate:

- **Never a layout change to `LbCallbacks`.** The four existing groups stay untouched; new groups arrive as
  new functions. An old host and a new dylib, or the reverse, both stay alive.
- **One group per concern**, so adding "zoom" later touches one struct and one setter, never the shared one.
- **`on_new_tab` returns a tab id owned by the shim, not a `CanonicalTraversable&`.** This is the one place
  the engine's type genuinely cannot cross a C ABI — `HeadlessWebView` hands out a traversable the host is
  expected to adopt. The shim does the adopting, registers an `LbTab`, and reports its id. The Mac side
  then decides whether to show it. That also fixes B3 without exposing engine types.
- **`struct_size` means a new field is a new minor version, not a break.** A host compiled against an older
  header passes a smaller size and the shim zero-fills.

Cross-cutting rules for everything below, matching the existing house style:

- Strings cross as `(const char*, size_t)` UTF-8, never NUL-terminated. `Utf16String::to_byte_string()` is
  the only correct narrowing (see `Traps.md`).
- Structured payloads (select items, file filters, content-blocking snapshot, session history, performance
  stats, a whole context menu) cross as **JSON text**, because they are `Vector<Struct>` graphs with no C
  shape and each would otherwise become its own bespoke ABI.
- Any request the engine waits on gets a `uint64_t request_id` and a matching `LbTabAnswer*`; anything that
  is not answered hangs a page. Grouping a "present-but-silent" callback is the failure mode the header
  already warns about.
- Every new group gets a native probe in `Tests/LibWebView/TestNative*`, per `AGENTS.md`.

---

## 4. Proposed phasing

One fork commit + one app commit + one probe per phase. Never a fork change and an app change in the same
commit, and never two writers in one worktree.

| Phase | Content | Fixes | Why first |
|---|---|---|---|
| **P0** | Tracking area + cursor rects; letter key codes for ⌘C/X/V/A/Z; Edit menu wired to `LbTabSendKey`; `LbTabReload`; `LbTabStopLoading`; real theme selection; **correct the header's "absent is safe" paragraph** | B1, B5, B7, half of B6, B8 (docs) | No new callback groups. Pure defects. The header fix is text-only and stops the next group inheriting a false guarantee. |
| **P1** | `LbPageCallbacks`: load_start, navigation_commit, history_complete, crash, crash_overlay, new_tab, audio, find | B3, B4 | Unblocks popups and stops silent renderer deaths. |
| **P2** | `LbPickerCallbacks` + answers: select dropdown, file picker, color picker, permission, external URL — **each with an explicit "unavailable" answer on the absent path** (B8) | B2, B8 | Dead form controls are a compatibility wall. |
| **P3** | `LbUICallbacks`: cursor, link hover, tooltips | B7 remainder | Cheap, very visible. |
| **P4** | Commands: zoom, find, mute, visibility/focus, close-with-prompt, color scheme/contrast/motion, editing (undo/redo/copy/cut/paste/select-all) | B1 remainder, B6 | Editing needs both the key fix and these. |
| **P5** | IME: marked text, `commit_text_from_input_method`, `input_method_state`, `on_finish_handling_key_event` | CJK/diacritics | Not urgent, but it is the last hard blocker for non-English input. |
| **P6** | Context menus: menu model → JSON + action dispatch | right-click | Largest single item; a `Menu` is a tree of `Action`s with enabled/checked/visible state. |
| **P7** | Accessibility tree bridge | VoiceOver | Independent and large. |

The phasing is what stops the engine being touched "again and again" for two different reasons:
P0–P5 add **groups**, and after P3 the shape has proved itself, so P6/P7 are additions to an existing pattern
rather than new design.

**One rule applies to every group from P2 onward, derived from B8:** an absent callback must never mean "the
engine will answer itself". For anything the engine blocks on, the shim registers its own handler that
answers *unavailable* immediately, and only hands the request to the host when the host's callback exists.
The host groups stay all-or-none; the shim always has an answer.

### Deliberately out of scope

DevTools (`inspect_*`, `on_debugger_*`, the network/console observers, `on_received_*`), WebDriver,
Picture-in-Picture, bookmark store internals, session store, crash-report upload, download UI. Ava has no UI
for these and bridging them would be permanent rebase debt for zero user-visible behaviour. Everything in
Tier 4 above is intentionally unbudgeted.

---

## 5. Verified non-issues

Worth recording so nobody "fixes" them:

- **`is_page_covered_by_overlay` / overlay painting is Qt-only.** A headless view needs none of it; the
  crash overlay is a host concern (see C4/C5), not a shim one.
- **`clipboard_item` / `insert_clipboard_item` are already virtual on `WebView::Application` and the base
  implementation keeps an in-process clipboard.** So the shim can implement paste without ObjC, by
  overriding in `PortApplication` and reading the pasteboard in the host through a `LbTabAnswerPaste`.
  The engine side is not blocked — only the ABI is.
- **`ViewImplementation::load(std::move(navigation))` already calls `prepare_for_navigation_after_crash`,**
  which is why reload-after-crash recovers today despite B4.
- **A wheel event is a `MouseEvent`**, and the tick fields must be derived with
  `wheel_tick_120ths_from_pixel_delta(..., WheelDeltaPrecision::Precise)` — already handled, and the reason
  trackpad scrolling works while a notched wheel needed the host-side line height in `PortWebView`.
