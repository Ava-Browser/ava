# Ava Documentation

Ava is a macOS browser: a Swift/SwiftUI application on top of a Ladybird engine it happens to
control. This directory is the map. If you are new, read the three pages in **Start here** in order —
they take about twenty minutes and nothing later will surprise you.

Some of this moves quickly. If something here is wrong, that is a bug in the docs; please fix it.

## Start here

| | Page | What it answers |
|---|---|---|
| 1 | [Architecture at a glance](Architecture-Overview.md) | What are the pieces, how does a click become pixels, how does a page load |
| 2 | [The ABI boundary](ABI.md) | How Swift and C++ talk, and why it is hand-written C |
| 3 | [Building](Building.md) | How to get a running app, and what each script really does |

## Reference

| Page | Contents |
|---|---|
| [Architecture](Architecture.md) | Layer responsibilities and why the boundary sits where it does |
| [Contract rules](Rules.md) | R1–R8 (boundary) and S1–S6 (Swift side) — the enforced invariants |
| [Measured traps](Traps.md) | Gotchas that cost real time, each with its fix and how it was measured |
| [Packaging](Packaging.md) | Bundle layout, rpaths, entitlements, DMG, what is and is not verified |
| [Upstream sync review](Upstream-Sync-Review.md) | Checklist for advancing the engine pin across a Ladybird resync |
| [Implementation handoff](Implementation-Handoff.md) | State of play for whoever picks this up next |

## Design documents

Product and design specs, written before implementation:

- [Spaces](TDD-Spaces.md) — persistent tab organization
- [Space settings](TDD-SpaceSettings.md)
- [Settings](PRD-Settings.md) · [Settings TDD](TDD-Settings.md)
- [Safari-style header](TDD-SafariHeader.md)

## Decisions

Short records of the calls that shaped the foundation, with the reasoning that outlived them:

| | Decision |
|---|---|
| 0001 | [Two repos, one boundary](Decisions/0001-two-repos-one-boundary.md) |
| 0002 | [SwiftUI, not GPUI](Decisions/0002-swiftui-not-gpui.md) |
| 0003 | [The boundary is a C ABI, not Swift/C++ interop](Decisions/0003-c-abi-at-the-boundary.md) |
| 0004 | [One event loop, pumped cooperatively](Decisions/0004-single-threaded-pump.md) |

## Investigation reports

Point-in-time findings. Useful as evidence; not maintained as current truth:

- [Favicon metadata](Reports/Favicon-Metadata-Investigation.md)
- [M6 readiness](Reports/M6-Readiness.md)
- [Safari header, first pass](Reports/SafariHeader-FirstPass.md)
- [Manual unload readiness](Reports/ManualUnload-Readiness.md)
- [Space settings, first pass](Reports/SpaceSettings-FirstPass.md)
- [Bridge gap inventory](Reports/Bridge-Gap-Inventory.md)

## Conventions

- **Cite symbols, never line numbers.** `ViewImplementation::server_did_paint`, not `ViewImplementation.cpp:293`.
  Line numbers rot on every upstream sync.
- **Claims about engine behaviour come from a probe or a test you read**, never from reading the Qt
  code and inferring. Qt is *a* path, not *the* path.
- **Diagrams use box-drawing characters in fenced blocks** so they stay greppable and diff cleanly.
