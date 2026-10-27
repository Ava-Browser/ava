# Packaging

`Scripts/package.sh` produces a self-contained `Ava.app` and a `Ava-<version>.dmg`. This page explains
the bundle layout, the two mechanisms that make it work, and what is still unverified.

## Bundle layout

```
Ava.app/Contents/
├── Info.plist                    org.ladybird.Ava, LSMinimumSystemVersion 14.4
├── MacOS/
│   ├── Ava                       the Swift app
│   ├── WebContent                ┐
│   ├── WebWorker                 │
│   ├── Compositor                │  helper processes. The engine spawns these by
│   ├── RequestServer             │  name from the application directory
│   ├── MediaServer               │  (LibWebView::get_paths_for_helper_process), so they
│   ├── AudioServer               │  live beside the app, not in a subdirectory.
│   ├── ImageDecoder              │
│   ├── VideoDecoderServer        │
│   └── ProcessReaper             ┘
├── Resources/                    the engine's resource root: platform_init derives
│   ├── themes/Default.ini        it as <app dir>/../Resources on macOS.
│   ├── fonts/                    themes/Default.ini is REQUIRED — LbTabCreate loads
│   ├── icons/                    it and returns tab id 0 without it.
│   ├── ladybird/                 about: pages, pdfjs, site-compatibility
│   └── app_icon.icns
└── lib/                          84 dylibs: the shim, its Lagom closure, vcpkg
```

Only the helpers are shipped, not the engine's own Qt-based `ladybird` binary — Ava is the UI, and
shipping it would drag Qt in.

## Mechanism 1 — the dependency closure

`otool -L` is walked from `Ava` and every helper, resolving `@rpath` names against the engine's `lib`
and the vcpkg dynamic directory, transitively.

```
  Ava ──▶ liblagom-port ──▶ liblagom-web ──▶ liblagom-js ──▶ ...
   │            │
   │            └──▶ libskia ──▶ libfreetype ──▶ libpng16
   │                    └─────▶ libharfbuzz
   └──▶ 84 dylibs, all of them now inside Contents/lib
```

Two rules that are easy to get wrong:

- **Copy under the install name, not the real path.** `liblagom-core.0.dylib` is a symlink to
  `liblagom-core.0.1.0.dylib`, and install names use the short form. Copying by `realpath` produces a
  bundle where every dependency is present and nothing resolves.
- **Anything absolute is a hard failure.** A path outside `/System` or `/usr/lib` (Qt, a stray
  Homebrew lib) would become a runtime "library not found" elsewhere, so packaging refuses.

## Mechanism 2 — rpaths

The engine's binaries and dylibs carry **absolute** rpaths into the build directory.

```
before:   /Users/<you>/.../ladybird/Build/release/lib        ← build tree
after:    @loader_path/../lib                                 ← binaries in Contents/MacOS
          @loader_path                                        ← dylibs in Contents/lib
```

Leaving the original in place is worse than a dangling path. On a developer's machine it *resolves* —
to a dylib from whichever commit that tree happens to be at, which is the ABI mismatch
`build.sh` exists to prevent, delivered through dyld instead of the linker.

The self-containment check enumerates **every** `LC_RPATH` and fails on anything that is not
`@`-relative or `/usr/lib/swift`. It does not pattern-match one prefix: the build tree is usually a
symlink to a second checkout, so a stale rpath may not contain this repo's path at all.

## Signing

Signed inside out, never `--deep`, with the hardened runtime:

| Image | `allow-jit` | `disable-library-validation` |
|---|---|---|
| `WebContent`, `WebWorker` | yes | yes |
| other helpers | no | yes |
| `Ava` | no | yes |
| `Contents/lib/*.dylib` | no | not applicable — dylibs are signed without an entitlement plist |

`allow-jit` only on the two renderers, because the kernel refuses W+X memory in a runtime process and
only they JIT. `disable-library-validation` everywhere because ad hoc images without a team identifier
would otherwise refuse to load each other.

**The bundle is signed last, carrying the executable's entitlements in the same step.** Signing
`Ava.app` re-signs `Contents/MacOS/Ava`; a separate sign of that binary would be replaced without its
entitlements, and the app then dies at startup with `mapping process and mapped file (non-platform)
have different Team IDs`. `codesign --verify --strict` passes throughout — it does not exercise dyld.

## What is verified, and what is not

Verified:

- `bash ./Scripts/test-package.sh` — drives the real `package.sh` against a synthetic engine tree
  (real dylib chain, real helpers, real `@rpath` names, a path containing a space). Asserts the closure
  is complete, no non-bundle rpath survives, entitlements land on the right images, and the executables
  actually **load**. Plus a negative case: an unsatisfiable dependency must fail the build.
- The DMG has been mounted and the app launched from it: 64 dylibs resolved from the image, none from
  the build tree, pages render.

Not verified:

- **Notarization.** The default signature is ad hoc, which is intended for local use: the app runs
  where it was built (no quarantine attribute) but is rejected by `spctl` and is not suitable for
  distribution. A downloaded copy would be refused by Gatekeeper. Shipping needs a Developer ID and
  notarization:
  ```bash
  ./Scripts/package.sh --identity "Developer ID Application: ..."
  xcrun notarytool submit Ava-0.1.0.dmg --keychain-profile <profile> --wait
  xcrun stapler staple Ava-0.1.0.dmg
  ```
- **The CI `package` job has never run.** It needs `AVA_ENGINE_BUILD_DIR` pointing at a prebuilt
  engine on a self-hosted runner. It is skipped, not faked, until then.
- **`test-package.sh` does not run `build.sh`** (it passes `--no-build`), so a failure there is not
  covered by CI.
- **Nothing is stripped.** 227 MB app / 73 MB DMG, with unstripped RelWithDebInfo dylibs. Stripping
  would shrink the download but costs crash-report fidelity.

## Bundle identifier

The packaged app is `org.ladybird.Ava`; the development bundle from `run.sh` is
`org.ladybird.mac.dev`. That is deliberate, so a local build never masquerades as the packaged app —
but it means preferences do not carry across, and the first launch of the DMG starts from defaults.

## Options

```
./Scripts/package.sh [--identity <codesign identity>] [--version <version>] [--no-build]

  AVA_SIGN_IDENTITY   default identity, same as --identity
  AVA_BINARY          executable to package (used with --no-build by the test)
```

`--no-build` skips the engine/shim build and the Swift build; it packages what is already there.
