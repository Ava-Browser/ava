# Ava — agent rules

## Read order, before any task

1. `Documentation/Architecture.md` — the layer map and why the boundary sits where it does
2. `Documentation/Rules.md` — R1-R8, the contract
3. `Documentation/Traps.md` — measured gotchas, each with its fix

The probes in `Extern/ladybird/Tests/LibWebView/TestNative*` are the executable spec for engine
behaviour. Read them before asserting anything about the engine.

## Public-repository safety

**Treat every commit, branch, draft PR, comment, attachment, release, CI log and artifact as
public and permanent.** These rules also apply to the engine fork and delegated workers.
A request to publish work is not permission to publish private inputs or local session state.

- Never commit or upload credentials: API/OAuth tokens, passwords, private/signing keys,
  certificates with private keys, cookies, authorization headers, `.env` contents or credential
  stores. Use secret references and clearly fake fixtures, never real values—even in tests.
- Never publish browser profiles/databases, browsing history, private URLs or query strings,
  user documents, clipboard contents, crash dumps, or raw request/response captures.
  Do not dump the environment or authenticated tool output into reports or public logs.
- Keep local agent conversations, prompts, memory, terminal transcripts, session/dispatch IDs,
  machine inventories and worktree metadata out of public deliverables. Summarize the technical
  decision instead. Use repository-relative paths or placeholders such as `<repo>` and `<build>`;
  remove personal home paths, usernames, private hosts/IPs and local temporary capture paths.
  Legitimate public attribution, license notices and public project URLs must be preserved.
- Documentation and build reports must be useful to other contributors, not copies of a local
  agent session. Publish minimal sanitized commands/results and reproducible synthetic fixtures.
  Use `example.com`, loopback or reserved test addresses rather than real private infrastructure.
- Screenshots/videos require visual review of the ENTIRE capture, including tabs, address bars,
  other windows, notifications and metadata. Prefer clean synthetic browsing state. Crop/redact
  private content irreversibly and inspect the exported result; do not publish raw pasted images
  or rely on reversible overlays. Review archives and binary attachments too.

### Before committing or publishing

1. Stage explicit paths; do not use blanket `git add .` / `git add -A` in a working checkout.
2. Inspect `git diff --cached --stat` AND the complete `git diff --cached`. Open staged images
   and review non-text files separately. Check new/untracked files deliberately. `.gitignore`
   is not a security control and does not protect already tracked files.
3. Run an available secret scanner against the staged/outgoing content. If unavailable, report
   that limitation and perform manual review; never claim a scan ran or the repo is secret-free.
4. Before pushing, review ALL outgoing commits and the full PR diff against its intended base,
   not only the latest file contents. Sanitize PR bodies/comments, logs and attachments too.
   Deleting sensitive text in a later commit does not remove it from earlier commits.
5. If any content is questionable, leave it unstaged/unpublished and ask the maintainer privately.
   Do not paste the suspected sensitive value into a public issue, PR or tool transcript.

If exposure is discovered, stop further publication and notify the maintainer privately without
repeating the secret. Exposed credentials must be revoked/rotated; deleting a file is insufficient.
Coordinate history/artifact cleanup with the maintainer—never force-push, rewrite shared history,
or delete public evidence unilaterally. Follow `SECURITY.md` for private vulnerability reporting.

## Layers

- `Sources/CLadybirdPort` — the C ABI. Nothing else.
- `Sources/LadybirdBridge` — C ABI only. **No AppKit, no SwiftUI.**
- `Sources/LadybirdEngine` — the **only** target that may touch AppKit/CoreFoundation.
- `Sources/LadybirdUI` — **must not import `CLadybirdPort`.** Go through the Engine.

Violations fail CI. Run `Scripts/check-layers.sh` before committing.

## Probe first

Any claim about engine behaviour must come from an in-tree probe or an existing test you have
actually read. **Do not infer engine behaviour from the Qt code** — Qt is *a* path, not *the* path.
When unsure, write a ~50-line probe in the fork and run it. This is how every rule in `Rules.md`
was derived.

## The fork is read-only

`Extern/ladybird` may only change in `Libraries/LibPort/` and `Tests/LibWebView/TestNative*`, plus
the two CMake registration lines for those. Every other edit is rebase debt and will be reverted.
If `LibWebView` genuinely needs a change, it lands in the fork as a separate upstream-shaped patch,
not folded into a feature commit.

## Cite symbols, never line numbers

Write `ViewImplementation::server_did_paint`, not `ViewImplementation.cpp:293`. Line numbers rot on
every upstream sync; agents following stale line numbers is the most common self-inflicted wound in
this repo.

## Commits

Mirror upstream style: one concern, imperative summary, BSD-2-Clause header on new files (copy the
existing spike files' style). Do not mix a fork change and an app-repo change in one commit.

## Generated code

None yet, deliberately. The spike proved shim generation is a renaming exercise, not a design
exercise, so it can wait. When the ABI passes ~20 functions, the generator becomes a `Scripts/`
tool — and the rule then is: **hand-edit the description, never the output.**

## Do not

- Do not introduce `Unmanaged` outside `LadybirdBridge` (S1; machine-checked).
- Do not use `DispatchQueue` or `Task.detached` anywhere (S3; machine-checked).
- Do not add a second event loop, a display link, or a redraw timer (R3, R5).
- Do not crop or clone a surface-backed bitmap (R1).
- Do not widen the C header's enums or change a struct layout without bumping a version (R4).
- Do not "fix" the engine from this repo.
