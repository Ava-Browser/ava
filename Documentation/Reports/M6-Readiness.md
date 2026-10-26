# Ava Milestone 6 Readiness Audit: Gated Analysis of Containers, Unload Policy, and Gestures

**Status:** Gated readiness audit against `Documentation/TDD-Spaces.md`, current pinned `Extern/ladybird`, and app sources.
**Evidence:** Source/probe review; proposed M6 behavior still requires runtime verification.
**Scope:** Forensic evaluation of M6 prerequisites, separating verified facts from unproven binding hypotheses.

---

## 1. Executive Summary & Gated Readiness Status

Milestone 6 encompasses three distinct capabilities:
1. **Per-space Containers:** Isolated cookie and storage jars per container ID, persistent across app restarts.
2. **Unload Policy:** Evicting WebContent processes for inactive spaces while preserving durable graph state.
3. **Gestures:** 1:1 finger-tracking horizontal trackpad swipe between spaces.

### Readiness Summary

| Area | Status | Critical Blocker / Reality |
|---|---|---|
| **Containers Core** | **BLOCKED** | M5.5 probe only proved low-level SQLite/CookieJar primitives with default+private views; does not test two named container views or process restart. |
| **Engine Session Binding** | **BLOCKED (HYPOTHESIS REFUTED)** | `PortWebView` cannot simply re-assign `m_session`. `ViewImplementation::initialize_tab` calls `Application::open_page_for_new_tab`, which routes to `m_spare_web_content_process` or `create_web_content_client` hardcoded to the default session's RequestServer. |
| **Unload Policy** | **READY FOR APP IMPLEMENTATION** | This work is independent of engine container changes. Can be built entirely in `LadybirdEngine` via existing `app.destroyTab` and `tab.detach()` primitives. |
| **1:1 Swipe Gestures** | **NEEDS DESIGN / PROTOTYPE** | Past experiments used threshold-on-ended fling triggers; true 1:1 finger tracking requires interactive presentation and conflict resolution with horizontal page scrolling. |
| **Profile UI Boundary** | **PROTECTED** | "Set Profile" menu item must remain disabled. Container IDs must not be conflated with full user profile semantics. |

---

## 2. Forensic Audit of M5.5 Probe (`TestNativeContainers.cpp`)

A rigorous review of `Extern/ladybird/Tests/LibWebView/TestNativeContainers.cpp` reveals that while it demonstrates low-level storage capabilities, it does **not** constitute end-to-end acceptance of M6 containers:

1. **Default + Private Views, Not Named Containers:**
   - In Phase 1, the probe instantiates:
     - `view_a = HeadlessWebView::create(..., IsPrivate::No)`
     - `view_b = HeadlessWebView::create(..., IsPrivate::Yes)`
   - It verifies concurrent loading between a default view and an ephemeral private view. It never instantiates two simultaneous *named container views* through the view hierarchy.
2. **Direct In-Memory Jar Manipulation:**
   - Cookie isolation is tested by directly invoking `jar_a.set_cookie(...)` and `jar_b.get_cookie(...)` in C++ memory.
   - It does not test real WebContent HTTP cookie exchange, network request header injection via `RequestServer`, or `document.cookie` DOM isolation.
3. **No Process Relaunch in Q(c):**
   - Persistence is tested by nulling `work_session->cookie_jar = nullptr` and reopening SQLite (`Database::Database::create(database_path, "Container_Work"sv)`) **within the same running process**.
   - It does not execute a true quit and cold relaunch of the binary to verify directory discovery, lock cleanup, or multi-process coordination.
4. **Unchecked Exit Codes and Timing Hazards:**
   - The probe prints `PASS` or `FAIL` via `outln`, but unconditionally returns `0` (`return 0;`). A failure in `isolation_passed` or `persistence_passed` does not fail the executable or CI.
   - `spin_until` lacks a timeout guard. Furthermore, awaiting `view_a_loaded && view_a_painted` risks latching early blank paint #1 before real content settles (as documented in `Traps.md`).

**Conclusion:** The M5.5 probe provides valuable proof-of-concept evidence that `LibWebView`'s underlying database layer can manage partitioned SQLite stores. However, it is not an end-to-end verification of containerized browsing sessions in the web view pipeline.

---

## 3. Engine Architecture: Why Direct `m_session` Rebinding Fails

It was hypothesized that because `m_session` is `protected` in `Libraries/LibWebView/ViewImplementation.h`, `PortWebView` in `Libraries/LibPort/` could simply assign:
```cpp
// HYPOTHESIS: Unsafe and non-functional
view->m_session = Application::session_for_new_view(IsPrivate::No, container_name);
```

Tracing the view lifecycle through `ViewImplementation.cpp` and `Application.cpp` proves why this hypothesis is invalid:

1. **Tab Initialization Lifecycle:**
   - `PortWebView::create` calls `view->initialize_tab(Web::HTML::VisibilityState::Visible)`.
   - `ViewImplementation::initialize_tab` calls:
     ```cpp
     auto page = MUST(Application::the().open_page_for_new_tab(m_is_private));
     ```
2. **Spare Process Hijacking:**
   - In `Application::open_page_for_new_tab(IsPrivate is_private)`:
     ```cpp
     if (is_private == IsPrivate::Yes) {
         web_content_client = TRY(create_web_content_client(IsPrivate::Yes, allocate_page_id()));
     } else if (m_spare_web_content_process) {
         web_content_client = m_spare_web_content_process.release_nonnull();
         launch_spare_web_content_process();
     } else {
         web_content_client = TRY(create_web_content_client(IsPrivate::No, allocate_page_id()));
     }
     ```
   - For any non-private tab (`IsPrivate::No`), `open_page_for_new_tab` immediately grabs `m_spare_web_content_process`.
   - The spare process was pre-warmed during application startup and is already permanently connected to the **default session's** `RequestServer`.
3. **RequestServer Connection Is Hardcoded:**
   - Even when launching a fresh client, `create_web_content_client` executes:
     ```cpp
     auto request_server_connection = TRY(connect_new_request_server_client(
         session_for_new_view(is_private), // Hardcoded without container_name!
         RequestServer::SiteBinding::Bound));
     ```
   - It calls `session_for_new_view(is_private)` without `container_name`, hardcoding the connection to `default_session()`.

**Consequence:** Merely overwriting `m_session` on the host side in `PortWebView` leaves the underlying `WebContentClient` communicating with a `RequestServer` tied to the default cookie jar. The tab appears to have a container session on the UI object, but executes all network loads under the default session.

**Engine Requirement:** Containerized tabs cannot be achieved purely in `LibPort`. `Application::open_page_for_new_tab` and `create_web_content_client` must be extended with an optional container identifier, and spare process reuse must be gated or bypassed for named containers.

---

## 4. Unload Policy: Architecture and App-Side Feasibility

Unlike containers, the **Unload Policy** requires zero engine modifications and can proceed immediately within `LadybirdEngine`.

### 4.1 Invariants (TDD-Spaces §1 & §2)
1. Descriptors remain durable in `WorkspaceManager`; `runtimeTabs` maintains stable observable wrapper identities.
2. Unloading a tab clears `tab.engineID`, destroys the engine page via `app.destroyTab(engineID)`, and detaches surface bindings.
3. Unloading an inactive workspace closes all its tab engine pages, destroying their engine handles. Page-resource and helper reclamation must be measured; do not assume immediate process exit, even for a dedicated helper.
4. Re-selecting an unloaded tab enters `BrowserModel.select -> rehydrate`, recreating the engine tab on demand.

### 4.2 App Implementation Surface
- `BrowserModel.unloadTab(BrowserTab)`:
  - Guard: cannot unload currently presented tab.
  - Resolves pending dialogs via `answerPendingDialog`.
  - Destroys engine handle: `app.destroyTab(engineID)`.
  - Removes entry from `engineToTab`.
  - Marks tab detached: `tab.detach()`.
- `BrowserModel.unloadWorkspace(Workspace)`:
  - Guard: cannot unload active workspace (`workspace.id != workspaceManager.activeSpaceID`).
  - Iterates through all normal and pinned tabs in the target space and calls `unloadTab`.
- Model & UI Tests:
  - Verify descriptors survive, `isLoaded` transitions to `false`, and rehydration recovers page on selection.

---

## 5. Trackpad Gestures: 1:1 Interaction vs Fling Triggers

### 5.1 The Flaw in Threshold Fling Triggers
Prior spikes implemented horizontal space switching by listening to `NSEvent.phase == .ended` and checking `abs(cumulativeDeltaX) >= 40.0`.
- **Not 1:1:** The user moves their fingers with zero visual feedback during the gesture; the space abruptly jumps only after lifting fingers.
- **Scroll Contention:** In macOS AppKit, `scrollWheel` events dispatch to the view under the cursor. Naively accumulating horizontal deltas intercepts horizontal scrolling within web content (such as code blocks, wide tables, horizontal carousels, and map canvas).

### 5.2 True 1:1 Swipe Requirements (TDD §6 & Architecture)
1. **Interactive Visual Feedback:** During `.changed`, the active space view and neighbor space must slide in real-time tracking the finger offset.
2. **Cancellation & Snap:** If the gesture ends below the velocity/distance threshold, it springs back to the current space; if it exceeds, it completes the transition.
3. **Scroll Arbitration:**
   - WebContent consumes wheel events inside the compositor.
   - Disambiguation requires testing whether the target element has scrollable horizontal overflow, or restricting edge swipes to the window edge/sidebar region, or honoring native AppKit fluid swipe tracking (`NSEvent.trackSwipeEventWithOptions`).

---

## 6. Gated Task Roadmap

To maintain stability and contract compliance, M6 must be delivered in strictly gated, sequential steps:

### Phase 1: Unload Policy (App-Side, Immediately Actionable)
- **Task 1.1:** Implement `BrowserModel.unloadTab` and `BrowserModel.unloadWorkspace` in `LadybirdEngine`.
- **Task 1.2:** Add unit and integration tests verifying WebContent handle destruction, descriptor survival, and lazy rehydration.
- **Task 1.3:** Add "Unload Space Tabs" affordance to inactive space context menus in `LadybirdUI`.
- **Acceptance:** Verify destruction of engine page handles and durable descriptor survival with successful rehydration on selection; verify process reclamation for dedicated Ava-owned WebContent instances while preserving all tabs in `spaces.json`.

### Phase 2: Upstream-Shaped Container Lifecycle Probe (Fork Verification)
- **Task 2.1:** Write a dedicated, rigorous native probe in `Extern/ladybird/Tests/LibWebView/TestNativeContainerLifecycle.cpp` against a separately approved upstream-shaped `Application` container-identifier patch on an isolated fork branch. This prerequisite must land on the probe branch before execution; do not bypass R7 or hide production changes as test support.
- **Task 2.2:** Probe must:
  - Launch two distinct named container views through `Application`.
  - Verify that `open_page_for_new_tab` connects each view to its specific container `RequestServer`.
  - Execute real HTTP loads and assert non-zero exit codes on failure.
  - Quit and cold-relaunch a secondary helper process to verify cross-process disk jar recovery.
- **Acceptance:** Probe passes with exit code 0; fails closed if cookie leaks across containers.

### Phase 3: Fork Seam & Bridge Integration (Gated on Phase 2)
- **Task 3.1:** Land upstream-shaped patch updating `Application::open_page_for_new_tab` and `create_web_content_client` to support container names, bypassing spare processes for named containers.
- **Task 3.2:** Update approved patch manifests in `Scripts/check-layers.sh`.
- **Task 3.3:** Add `LbTabCreateInContainer` in `Libraries/LibPort/` and `PortApp.createTab(containerID:)` in `LadybirdBridge`.
- **Task 3.4:** Wire `BrowserModel.rehydrate` to forward `workspace.containerID`.

### Phase 4: 1:1 Interactive Gesture Navigation
- **Task 4.1:** Prototype AppKit gesture recognizer or `trackSwipeEventWithOptions` that does not steal web content horizontal scroll.
- **Task 4.2:** Connect finger delta to interactive space card transition with spring release.
- **Acceptance:** Smooth 1:1 tracking; horizontal web page scrolling operates without triggering space switch.
