# Investigation Report: Delivering Favicons and Tab Metadata to Ava

**Status:** Complete Investigation & Architecture Plan
**Target Date:** 2026-10-26
**Document Location:** `Documentation/Reports/Favicon-Metadata-Investigation.md`
**Referenced Specifications:** `Documentation/Architecture.md`, `Documentation/Rules.md`, `Documentation/Traps.md`, `Documentation/TDD-Spaces.md`
**Referenced Executable Probes:**
- `Extern/ladybird/Tests/LibWebView/TestFavicon.cpp`
- `Extern/ladybird/Tests/LibWebView/TestFaviconStore.cpp`
- `Extern/ladybird/Tests/LibWeb/TestFaviconDecoding.cpp`
- `Extern/ladybird/Tests/LibWebView/TestNativeInput.cpp`
- `Extern/ladybird/Tests/LibWebView/TestNativeContainers.cpp`

---

## 1. Executive Summary

Favicons do not appear in Ava today because **the engine-to-UI pipeline is severed at the C ABI boundary (`LibPort`)**, with corresponding missing infrastructure in `LadybirdBridge`, `LadybirdEngine`, and `LadybirdUI`:

1. **Engine side is functional:** `LibWeb` parses `<link rel="icon">`, decodes images (SVG, PNG, ICO) via `ImageCodecPlugin`, sends them across IPC via `PageClient::page_did_change_favicon`, and delivers them to `ViewImplementation::set_favicon`. Inside `ViewImplementation::set_favicon`, the engine encodes the bitmap to PNG, deduplicates and stores it in `FaviconStore` by SHA-256 hash, and calls `ViewImplementation::on_favicon_change`.
2. **The C ABI gap:** `Libraries/LibPort/ladybird_port.cpp` never assigns `view->on_favicon_change`. The `LbCallbacks` struct in `ladybird_port.h` defines no favicon callback, and no ABI function exists to inspect or retrieve icon payloads.
3. **The Swift layer gaps:**
   - `PortCallbacks` and `PortApp` in `LadybirdBridge` have no favicon handling.
   - `BrowserTab` in `LadybirdEngine` has no property for an image, PNG bytes, or icon reference (though `TabDescriptor.faviconRef: String?` already exists dormant in schema).
   - `TabSidebar` in `LadybirdUI` hardcodes SF Symbols (`"circle.dotted"` for loading, `"moon.zzz"` for unloaded, `"globe"` for loaded) and never renders bitmap content.
4. **Title is also synthesized:** Ava does not receive real HTML document titles from the engine. `ViewImplementation::on_title_change` is unhooked in `ladybird_port.cpp`, forcing `BrowserTab.update(url:)` to synthesize titles from the URL hostname.

This report establishes the minimal, safe architecture to bridge favicons and other core metadata (real title, loading state, and audio/mute status) into Ava without architectural violations, extraneous network requests, or layer leaks.

---

## 2. End-to-End Trace: How Favicons and Titles Flow (and Where They Stop)

### 2.1 The Favicon Pipeline

```
[Web Page: <link rel="icon"> / /favicon.ico]
                  │
                  ▼
   HTMLLinkElement::process_icon_resource / load_fallback_favicon_if_needed
                  │
                  ▼
           decode_favicon (SVG rasterized at 32x32, PNG/ICO decoded)
                  │
                  ▼
   Document::check_favicon_after_loading_link_resource
                  │
                  ▼
   PageClient::page_did_change_favicon(Gfx::Bitmap const&)
                  │
                  ▼ (IPC: did_change_favicon)
   WebContentPage::did_change_favicon(Gfx::ShareableBitmap)
                  │
                  ▼
   ViewImplementation::set_favicon(Optional<Gfx::Bitmap const&>)
         ├─ Encodes bitmap to PNG via Gfx::PNGWriter::encode
         ├─ Stores PNG into session().favicon_store by SHA-256 hash
         ├─ Sets m_favicon_hash (SHA-256 hex string)
         └─ Calls on_favicon_change(favicon)
                  │
                  ▼
   ┌────────────────────────────────────────────────────────┐
   │ MISSING LINK: Libraries/LibPort/ladybird_port.cpp      │
   │ view->on_favicon_change is never assigned.             │
   │ LbCallbacks in ladybird_port.h has no favicon field.   │
   └────────────────────────────────────────────────────────┘
                  │
                  ▼
   ┌────────────────────────────────────────────────────────┐
   │ MISSING LINK: Sources/LadybirdBridge/Port.swift        │
   │ PortCallbacks has no onFaviconChange trampoline.       │
   └────────────────────────────────────────────────────────┘
                  │
                  ▼
   ┌────────────────────────────────────────────────────────┐
   │ MISSING LINK: Sources/LadybirdEngine/BrowserTab.swift  │
   │ BrowserTab has no favicon or faviconRef property.      │
   │ BrowserModel does not observe or route icon events.    │
   └────────────────────────────────────────────────────────┘
                  │
                  ▼
   ┌────────────────────────────────────────────────────────┐
   │ MISSING LINK: Sources/LadybirdUI/TabSidebar.swift      │
   │ TabRowView & EssentialTile hardcode SF Symbols         │
   │ ("globe", "circle.dotted", "moon.zzz").                │
   └────────────────────────────────────────────────────────┘
```

### 2.2 The Title and URL Pipeline Comparison

| Step | URL Path (Working) | Title Path (Current Ava) | Title Path (Required Engine) |
|---|---|---|---|
| **Engine Source** | `ViewImplementation::update_displayed_url` | Synthesized in Swift from `URL(string: url)?.host()` | `ViewImplementation::set_title` |
| **Engine Callback** | `ViewImplementation::on_url_change` | None | `ViewImplementation::on_title_change` |
| **LibPort Hook** | `view->on_url_change` in `ladybird_port.cpp` | None | Missing in `ladybird_port.cpp` |
| **C ABI (`ladybird_port.h`)** | `LbCallbacks.on_url_change` | None | Missing in `LbCallbacks` |
| **Bridge (`Port.swift`)** | `PortCallbacks.onURLChange` | None | Missing in `PortCallbacks` |
| **Engine Model** | `BrowserModel.handleURLChange` | `tab.update(url:)` sets `title = host` | Needs `tab.updateTitle(title)` |
| **UI Display** | Displayed in address bar & tooltip | Displayed in sidebar & tooltip | Real document `<title>` |

---

## 3. Metadata Inventory: Engine Capabilities vs Port Gaps

The engine does not treat all icons or metadata uniformly. Below is the forensic inventory separating verified engine features from missing LibPort hooks:

| Metadata Type | Source / Spec | Engine Availability | LibPort Availability | Invalidation / Timing Trigger | Recommended Action |
|---|---|---|---|---|---|
| **Document Favicon** | `<link rel="icon">`, fallback `/favicon.ico` | **Full** (`ViewImplementation::on_favicon_change`, `ViewImplementation::favicon_hash`, `FaviconStore`) | **Missing** | Cleared on `did_change_active_document`; set on decode resolution | **Expose in ABI** as PNG bytes + SHA-256 hash |
| **Shortcut Icon** | `<link rel="shortcut icon">` | **Full** (Token split recognizes `"icon"`) | **Missing** (same as favicon) | Same as document favicon | Handled automatically by favicon path |
| **Apple Touch Icon** | `<link rel="apple-touch-icon">` | **Unsupported** in LibWeb (only present in `DOMTokenList` WPT table; not fetched) | N/A | N/A | **Do not expose** (requires upstream engine support first) |
| **Web App Manifest** | `<link rel="manifest">` | **Unsupported** in LibWeb (no manifest fetcher or icon extractor) | N/A | N/A | **Do not expose** |
| **Page Title** | `<title>`, `document.title` | **Full** (`ViewImplementation::on_title_change`) | **Missing** | Provisional URL on navigation; updated on `<title>` tag parse | **Expose in ABI** as UTF-8 string |
| **Loading State** | Navigation lifecycle | **Full** (`ViewImplementation::on_loading_state_change`, `on_load_start`, `on_load_finish`) | **Partial** (`on_load_finish` only) | Set `true` on navigation start; `false` on finish or error | **Expose in ABI** (`on_loading_state_change`) |
| **Audio / Media State** | `<audio>`, `<video>`, WebAudio | **Full** (`ViewImplementation::on_audio_play_state_changed`, `audio_play_state()`, `page_mute_state()`, `toggle_page_mute_state()`) | **Missing** | Changes on element playback start/pause/end | **Expose in ABI** for tab mute affordance & speaker indicator |
| **Theme Color** | `<meta name="theme-color">` | **Full** (`ViewImplementation::on_theme_color_change`) | **Missing** | Emitted when meta element parsed or altered | Optional future enhancement for sidebar tinting |
| **Security / TLS** | HTTPS certificate state | **Unsupported** (LibWebView / WebContent expose no TLS or certificate inspection callbacks) | N/A | Derived in UI via URL scheme `url.hasPrefix("https://")` | Continue UI-side scheme check |

---

## 4. In-Tree Probe Evidence

Claims regarding engine behavior are verified against existing in-tree test probes in `Extern/ladybird/Tests/LibWebView/`:

### 4.1 `TestFavicon.cpp`
- **Symbols Cited:** `WebView::HeadlessWebView::create`, `view->on_favicon_change`, `view->load_html`, `view->run_javascript`.
- **Verified Findings:**
  1. `view->on_favicon_change` delivers `Optional<Gfx::Bitmap const&>`.
  2. Decodes both SVG and PNG data URIs without a window or display server.
  3. SVG favicons are automatically rasterized to a default 32×32 pixel `Gfx::Bitmap`.
  4. Dynamically changing icon href via DOM manipulation (`document.getElementById("preferred").href = ...`) re-triggers `on_favicon_change`.
  5. Invalid image sources trigger decoder failure in `ImageDecoderClient` and fall back to the next valid `<link rel="icon">`.

### 4.2 `TestFaviconStore.cpp`
- **Symbols Cited:** `WebView::FaviconStore::create`, `store->add_favicon`, `store->favicon_png`, `store->remove_unreferenced_favicons`.
- **Verified Findings:**
  1. `FaviconStore` accepts encoded PNG `ByteBuffer` and returns an `Optional<String>` containing the SHA-256 hex digest.
  2. Redundant insertions of identical PNG bytes deduplicate to the same hash.
  3. Favicon retrieval via `store->favicon_png(hash)` returns the exact identical byte payload.
  4. Favicons larger than `MAXIMUM_FAVICON_BYTE_COUNT` (1 MiB) are rejected.
  5. Transient (in-memory) and persistent (SQLite) storage implementations share identical semantics.

### 4.3 `TestNativeInput.cpp`
- **Symbols Cited:** `view->on_title_change`, `view->on_load_finish`, `view->on_ready_to_paint`.
- **Verified Findings:**
  1. `view->on_title_change` is an active callback on `ViewImplementation` passing `Utf16String const&`.
  2. The callback executes synchronously within the cooperative event pump on the main thread.

---

## 5. Architectural Proposal: Minimum Safe Design

### 5.1 Chosen Representation: Encoded PNG Bytes + SHA-256 Hash

When crossing the C ABI (`ladybird_port.h`), we evaluate three possible payloads:

1. **Option A: Encoded PNG Bytes + Hash (`const uint8_t* data, size_t len, const char* hash, size_t hash_len`)** — **RECOMMENDED**
   - *Why:* In `ViewImplementation::set_favicon()`, Ladybird **already encodes the bitmap to PNG** using `Gfx::PNGWriter::encode()` and adds it to the session's `FaviconStore`, deriving the SHA-256 hash. Passing this existing buffer across the ABI reuses work the engine already did.
   - *Memory:* A 32×32 PNG is ~200–800 bytes (vs. 4,096 bytes for raw uncompressed BGRA8888).
   - *UI Ingestion:* Cocoa's `NSImage(data:)` natively parses PNG in ~1 microsecond on the main thread, handling display density and Retina scaling automatically.
   - *Persistence & Offline Display:* `TabDescriptor.faviconRef: String?` is already stored in the persisted graph schema. Storing the SHA-256 hex string in `faviconRef` enables an immediate disk cache lookup (`Caches/Favicons/<hash>.png`). Unloaded tabs can display their cached favicon immediately upon application launch before waking the engine.
   - *Deduplication:* 20 tabs on the same domain share one in-memory `NSImage` via a simple `[String: NSImage]` cache.
   - *Zero UI Fetching:* The UI never makes independent HTTP requests for favicon URLs, preventing cookie leaks, container bypasses, and duplicate network traffic.

2. **Option B: Raw Decoded BGRA8888 Pixels (`uint8_t* pixels, int width, int height, int pitch`)**
   - *Rejected:* Requires complex `CGDataProvider` and `CGBitmapInfo` boilerplate in Swift to construct an `NSImage`, discards the engine's pre-computed PNG, and requires re-encoding to PNG in Swift to persist in `TabDescriptor.faviconRef`.

3. **Option C: CoreFoundation `CGImageRef`**
   - *Rejected:* Increases coupling in `Libraries/LibPort` to Apple frameworks and requires manual `CGImage` creation from `Gfx::Bitmap`. Option A remains pure C and portable.

### 5.2 Ownership and Lifetime Rules

- **Borrowed Buffer Rule (R1, S5):** The ABI callback hands borrowed pointers (`const uint8_t* data`, `const char* hash`). The pointers are valid only for the duration of the callback turn.
- **Immediate Capture (S1):** `LadybirdBridge` copies the bytes immediately into Swift `Data` and `String` before leaving the C trampoline.
- **No Retained Pointers (S5):** No raw C pointers or `Unmanaged` references are stored past the callback turn.
- **Thread Invariant (R5, S3):** Callbacks fire synchronously on the main thread inside `LbAppPump`. The Bridge wraps invocation in `MainActor.assumeIsolated`.

### 5.3 Invalidation and Timing Contract

1. **Navigation Initiation:**
   - When a tab navigates to a new URL, `ViewImplementation::did_change_active_document()` calls `set_favicon({})` and `set_title(url)`.
   - `on_favicon_change` fires with `data = NULL, len = 0, hash = NULL, hash_len = 0`.
   - Swift immediately clears `BrowserTab.favicon` and `BrowserTab.faviconRef`. The UI reverts to the loading indicator (`"circle.dotted"`) or default placeholder.
2. **Icon Arrival:**
   - Once `<link rel="icon">` or fallback `/favicon.ico` completes decoding in WebContent, `ViewImplementation::set_favicon()` fires with valid PNG bytes and hash.
   - Swift updates `BrowserTab.favicon` (decoded `NSImage`) and `BrowserTab.faviconRef` (hash), updating `WorkspaceManager.updateTab(...)` so the persisted graph records the new `faviconRef`.
3. **Tab Teardown:**
   - When a tab is destroyed via `LbTabDestroy`, it is removed from `app->tabs`. Any pending WebContent IPC messages arriving after destruction are dropped; no callback is dispatched to a destroyed tab.

---

## 6. Concrete Contract Definitions

### 6.1 C ABI (`Libraries/LibPort/ladybird_port.h`)

```c
typedef struct LbCallbacks {
    void* context;

    void (*on_ready_to_paint)(void* context, uint64_t tab);
    void (*on_url_change)(void* context, uint64_t tab, const char* url, size_t len);
    void (*on_load_finish)(void* context, uint64_t tab, const char* url, size_t len);

    // Document title updated from <title> or document.title. Not NUL-terminated.
    void (*on_title_change)(void* context, uint64_t tab, const char* title, size_t len);

    // Loading state changed (1 = loading started, 0 = loading finished/stopped).
    void (*on_loading_state_change)(void* context, uint64_t tab, int is_loading);

    // Favicon changed or cleared. When data is NULL or len is 0, the favicon was cleared.
    // data carries PNG encoded bytes; hash carries the ASCII hex SHA-256 digest. Valid for this call only.
    void (*on_favicon_change)(void* context, uint64_t tab, const uint8_t* data, size_t len, const char* hash, size_t hash_len);

    // Modal dialogs (retained from current ABI)
    void (*on_request_alert)(void* context, uint64_t tab, const char* message, size_t len);
    void (*on_request_confirm)(void* context, uint64_t tab, const char* message, size_t len);
    void (*on_request_prompt)(void* context, uint64_t tab, const char* message, size_t len, const char* default_text, size_t default_len);
    void (*on_request_before_unload)(void* context, uint64_t tab, const char* source, size_t len);
} LbCallbacks;
```

### 6.2 C Implementation (`Libraries/LibPort/ladybird_port.cpp`)

```cpp
view->on_title_change = [app, id](Utf16String const& title) {
    if (!app->callbacks.on_title_change)
        return;
    auto narrow = title.to_byte_string();
    app->callbacks.on_title_change(app->callbacks.context, id, narrow.characters(), narrow.length());
};

view->on_loading_state_change = [app, id](bool is_loading) {
    if (app->callbacks.on_loading_state_change)
        app->callbacks.on_loading_state_change(app->callbacks.context, id, is_loading ? 1 : 0);
};

view->on_favicon_change = [app, id, view = view.ptr()](Optional<Gfx::Bitmap const&> bitmap) {
    if (!app->callbacks.on_favicon_change)
        return;

    if (!bitmap.has_value()) {
        app->callbacks.on_favicon_change(app->callbacks.context, id, nullptr, 0, nullptr, 0);
        return;
    }

    auto const& hash = view->favicon_hash();
    if (!hash.has_value())
        return;

    auto png = view->session().favicon_store->favicon_png(*hash);
    if (!png.has_value() || png->is_empty())
        return;

    auto narrow_hash = hash->to_byte_string();
    app->callbacks.on_favicon_change(
        app->callbacks.context, id,
        png->data(), png->size(),
        narrow_hash.characters(), narrow_hash.length()
    );
};
```

### 6.3 Swift Bridge (`Sources/LadybirdBridge/Port.swift`)

```swift
public struct PortCallbacks {
    public var onReadyToPaint: (UInt64) -> Void
    public var onURLChange: (UInt64, String) -> Void
    public var onLoadFinish: (UInt64, String) -> Void
    public var onTitleChange: ((UInt64, String) -> Void)?
    public var onLoadingStateChange: ((UInt64, Bool) -> Void)?
    public var onFaviconChange: ((UInt64, Data?, String?) -> Void)?
    // ... dialogs
}
```

Inside `PortApp.init`:

```swift
c.on_title_change = { raw, tab, title, len in
    guard let context = CallbackContext.resolve(raw) else { return }
    let string = decode(title, len)
    MainActor.assumeIsolated { context.callbacks.onTitleChange?(tab, string) }
}
c.on_loading_state_change = { raw, tab, isLoading in
    guard let context = CallbackContext.resolve(raw) else { return }
    let loading = isLoading != 0
    MainActor.assumeIsolated { context.callbacks.onLoadingStateChange?(tab, loading) }
}
c.on_favicon_change = { raw, tab, data, len, hash, hashLen in
    guard let context = CallbackContext.resolve(raw) else { return }
    let iconData: Data? = (data != nil && len > 0) ? Data(bytes: data!, count: len) : nil
    let hashString: String? = (hash != nil && hashLen > 0) ? decode(hash, hashLen) : nil
    MainActor.assumeIsolated { context.callbacks.onFaviconChange?(tab, iconData, hashString) }
}
```

### 6.4 Engine Model (`Sources/LadybirdEngine/BrowserTab.swift`)

```swift
@MainActor
@Observable
public final class BrowserTab: Identifiable {
    public let id: TabID
    public private(set) var engineID: UInt64?
    public private(set) var currentURL: String
    public private(set) var title: String
    public private(set) var isLoading: Bool = false
    public private(set) var dialog: TabDialog?
    public private(set) var favicon: NSImage?
    public private(set) var faviconRef: String?

    public var isLoaded: Bool { engineID != nil }

    /// A real `<title>` always wins; an empty one leaves the URL-derived fallback in place.
    func updateTitle(_ newTitle: String) {
        if !newTitle.isEmpty {
            title = newTitle
        }
    }

    func updateFavicon(_ image: NSImage?, ref: String?) {
        favicon = image
        faviconRef = ref
    }

    func clearFavicon() {
        favicon = nil
        faviconRef = nil
    }
}
```

### 6.5 UI Rendering (`Sources/LadybirdUI/TabSidebar.swift`)

In `TabRowView` and `EssentialTile`:

```swift
@ViewBuilder
private var iconView: some View {
    if tab.isLoading {
        Image(systemName: "circle.dotted")
            .font(.system(size: 13))
            .foregroundStyle(isSelected ? .primary : .secondary)
    } else if let favicon = tab.favicon {
        Image(nsImage: favicon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 16, height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    } else if !tab.isLoaded {
        Image(systemName: "moon.zzz")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
    } else {
        Image(systemName: "globe")
            .font(.system(size: 13))
            .foregroundStyle(isSelected ? .primary : .secondary)
    }
}
```

---

## 7. Staged Implementation Plan

Implementation should proceed in five isolated, reviewable stages across the two repositories:

### Stage 1: Engine Fork (`ava-engine` / `Extern/ladybird`)
- **Files Modified:** `Libraries/LibPort/ladybird_port.h`, `Libraries/LibPort/ladybird_port.cpp`.
- **Work:** Add `on_title_change`, `on_loading_state_change`, and `on_favicon_change` to `LbCallbacks`. Connect `PortWebView` hooks.
- **Verification:** Run `cmake --build Build/release --target LibPort` and run `./Scripts/check-layers.sh` to confirm C11 compliance (R4) and no ObjC in LibPort (R2).
- **Deliverable:** Pull Request on `Ava-Browser/ava-engine`.

### Stage 2: Swift Bridge (`Sources/LadybirdBridge`)
- **Files Modified:** `Sources/LadybirdBridge/Port.swift`, `Tests/LadybirdBridgeTests/BridgeTests.swift`.
- **Work:** Add closures to `PortCallbacks`, implement C trampolines in `PortApp`, and add isolated unit tests verifying UTF-8 title and binary PNG Data extraction.
- **Verification:** Run `swift test --filter BridgeTests`.

### Stage 3: App Model & Cache (`Sources/LadybirdEngine`)
- **Files Modified:** `BrowserTab.swift`, `BrowserModel.swift`, `WorkspaceModel.swift`, `WorkspaceManager.swift`.
- **Work:**
  1. Add `favicon: NSImage?` and `faviconRef: String?` to `BrowserTab`.
  2. Implement an in-memory `[String: NSImage]` cache in `BrowserModel`.
  3. Route engine events in `BrowserModel`: `handleTitleChange` and `handleFaviconChange`.
  4. Write through `faviconRef` into `TabDescriptor` via `WorkspaceManager.updateTab(...)`.
  5. (Optional): Persist icon PNGs into `Library/Caches/org.ladybird.Ava/Favicons/<hash>.png` on write, populating unloaded tabs on launch.
- **Verification:** Run `swift test --filter SpaceSettingsTests` and add `FaviconMetadataTests`.

### Stage 4: UI Chrome (`Sources/LadybirdUI`)
- **Files Modified:** `Sources/LadybirdUI/TabSidebar.swift`.
- **Work:** Update `TabRowView` (16×16 pt) and `EssentialTile` (24×24 pt) to display `tab.favicon` when available, falling back smoothly to loading spinner, sleep icon, or globe.
- **Verification:** Live UI run via `./Scripts/run.sh` to visual check synthetic pages with SVG and PNG favicons.

---

## 8. Verification Strategy & Unresolved Claims

### 8.1 Automated Test Plan

1. **Native Probe Verification:** Run `TestFavicon` and `TestFaviconStore` in `Extern/ladybird/Build/release/bin/` to ensure engine-level decoding invariants hold across updates.
2. **Bridge Unit Tests:** Test `PortCallbacks.onFaviconChange` with null, zero-length, and mock PNG data buffers.
3. **Model Integration Tests:**
   - Test that navigating to a page clears previous favicon.
   - Test that identical favicons across two tabs reuse the same cached image reference.
   - Test that `TabDescriptor.faviconRef` round-trips through JSON persistence in `WorkspaceManager`.
4. **Hygiene Checks:** Run `./Scripts/check-layers.sh` and `git diff --check` to verify all layer boundary rules (R1–R8, S1–S6).

### 8.2 Unresolved & Deferred Items

- **Apple Touch Icons (`apple-touch-icon`):** Deferred. LibWeb does not download or parse touch icons. Any touch icon support requires an upstream LibWeb patch to `HTMLLinkElement.cpp`.
- **Web App Manifest Icons:** Deferred. No manifest downloader exists in Ladybird.
- **TLS Certificate Detail Sheet:** Deferred. `LibWebView` exposes no security handshake info. Scheme-based indication (`https://`) remains standard.
- **Icon persistence to disk:** Implemented in `Sources/LadybirdEngine/FaviconStore.swift`
  (`~/Library/Application Support/LadybirdMac/Favicons/<sha256>.png`, beside `spaces.json`). Application Support rather
  than Caches because these bytes are what a restored, unloaded tab draws: macOS may purge Caches under disk pressure,
  which would undo exactly that. `BrowserModel.handleFaviconChange` writes the engine's PNG, and `BrowserModel.init` /
  `runtime(for:)` hydrate `BrowserTab.favicon` from the hash already present in `TabDescriptor.faviconRef`, so a
  restored or unloaded row draws its icon before the engine exists. Pruning keeps the directory bounded by the
  referenced hashes and now also runs when tabs close, when a space is deleted, and when an icon is cleared.

### 8.3 ABI mismatch is a build-time hazard, not a runtime one to document away

Adding fields to `LbCallbacks` changes the struct's field offsets. The Swift side bakes those offsets in at
compile time, so a host built against the new header and linked against an older `liblagom-port.dylib` reads the
dialog function pointers at the wrong offsets and crashes on startup.

`Scripts/build.sh` therefore records the submodule commit that produced the dylib in `lib/.libport-pin` and
refuses to continue when it disagrees with the pinned commit ("built from" vs "pinned submodule"). A fresh clone
with no stamp fails closed rather than guessing.

This matters most when the build directory is a symlink to another checkout: cmake then rebuilds from that
checkout's sources while the outer repo pins a different commit, and the run would silently load foreign code.

---

## 9. Conclusion

Favicons fail today simply because the engine's working favicon pipeline terminates at the un-wired `LibPort` boundary. By passing the engine's pre-encoded PNG bytes and SHA-256 hash across a lightweight C ABI callback, Ava can deliver fast, deduplicated, and persistently cached favicons to the sidebar with minimal new code and zero unsafe UI-level network fetching.
