# Yeoman Engineering, Security, and Test Standard

This file is binding guidance for coding agents and contributors working in this repository. Read it before changing code. Apply the stricter rule when a change spans multiple areas. Inspect the implementation and tests directly; security reports are evidence and history, not a substitute for source review.

## Product and trust decisions

- Support macOS 14 and newer. Keep APIs and package deployment targets compatible with macOS 14.
- Release bundles are ad-hoc signed. Publisher authenticity for updates comes from the pinned Ed25519 public key and signed manifest, while code signing supplies bundle integrity checks.
- Do not require Apple Developer ID signing or notarization unless the owner changes this product decision.
- The default secret store is `SecureFileSecretStore`. Do not change the default to Login Keychain. This deliberately avoids Keychain prompts for an Internet-downloaded, ad-hoc-signed app.
- State the file-store boundary accurately: permissions and AES-GCM protect against other accounts, accidental disclosure, and ciphertext tampering; they do not provide confidentiality against a malicious process running as the same UID.
- Never commit, print, copy into build output, or infer the Ed25519 private key. Release signing must receive an external `0600` file through `YEOMAN_UPDATE_PRIVATE_KEY_FILE`.
- Pre-built releases currently target arm64. Do not claim Intel or universal-binary support without building and testing that artifact.

## General implementation standard

- Prefer small, explicit types and pure validation functions. Centralize shared limits and policy in the security layer instead of duplicating magic values.
- Treat all remote data, archives, WebKit content, clipboard data, persisted documents, preferences, process output, and filesystem state as untrusted.
- Fail closed on missing trust material, malformed state, validation errors, authentication failures, ambiguous identity, and partial migrations. Never add an insecure fallback.
- Put a finite limit on externally influenced bytes, item counts, dimensions, recursion/path depth, concurrency, and execution time before allocating or processing them.
- Preserve user data on failure. Commit a replacement or encrypted destination before deleting its source. Cleanup must remove only files whose provenance was established by the successful operation.
- Keep mutations serialized where ordering matters. Asynchronous callbacks must use cancellation tokens or generations and must remain safe after owner disposal.
- Avoid force unwraps for untrusted or lifecycle-dependent state. A force unwrap is acceptable only where a locally constructed invariant is immediate and obvious.
- Do not use shell interpolation for untrusted values. Launch fixed executable paths with argument arrays and bounded, concurrently drained stdout/stderr.
- Never weaken access control solely to make preview, screenshot, or test tooling compile. Add narrow test fixtures or public behavior-oriented APIs instead.
- Keep UI claims precise. Do not promise complete password detection, timer termination, secure erasure, same-UID secrecy, universal architecture support, or recovery properties that tests do not establish.

## Update and release pipeline

- Verify the Ed25519 manifest before using its metadata. The signature must bind product identifier, semantic version, archive name, exact size, and SHA-256.
- Enforce a strictly newer semantic version and the expected bundle identifier. Missing or malformed public keys must stop the update.
- Download only through the explicit HTTPS origin and redirect policy. Never forward API authorization to asset or redirect origins.
- Keep authenticated archive bytes immutable through extraction. Extract from the verified in-memory `Data`; do not verify one path and later extract another mutable path.
- Capture `BundleIdentity` from the extracted authenticated bundle before the host shutdown boundary. Require that exact identity immediately before replacement and after the final move. Do not derive a new expected identity from mutable staging.
- Verify fresh on-disk bundle metadata, main executable digest, strict nested static signature, and mandatory code-directory hash. Do not rely on cached `Bundle` metadata.
- Preserve transactional rollback and the identity-bearing install receipt. Launch acknowledgement must verify the installed bundle against the receipt before deleting the backup.
- Never overwrite an existing recovery backup automatically. Recovery must not replace a present target.
- Bump semantic version and build number for a new release. Never move or rewrite an already published tag.
- Release packaging must run tests, build, sign the app and helper, create ZIP/DMG, sign the update manifest, and verify hashes and signatures. CI must not receive the private release key.
- Every release must update `README.md` (and any affected captures or graphics under `Resources/Mockups/`) before tagging and publishing so documentation and visuals match the shipped behavior.

## Filesystem and archive safety

- Use `SecureDirectory` and descriptor-relative operations for application-owned mutable paths. Validate ownership, file type, link count, ACL state, and `0700`/`0600` permissions.
- Open every application-owned path component relative to a trusted descriptor. `O_NOFOLLOW` on only the final component is insufficient.
- Reject absolute paths, `..`, empty components, backslashes, alternate separators, NULs, excessive depth, links, aliases, devices, FIFOs, duplicate entries, Unicode/case collisions, and inconsistent ZIP headers.
- Keep archive entry, per-file byte, total byte, archive byte, and elapsed-time limits. Files from an update archive must remain inside one `Yeoman.app` root.
- Do not use `archive_write_disk`, shell extraction, or pathname-based writes for untrusted archives.
- Temporary tooling must use private, unique temporary directories and clean them up.

## Secrets, encryption, and persistence

- Use CryptoKit AES-GCM with a fresh system-generated nonce for every seal and record-specific associated data. Opening must authenticate before plaintext is consumed.
- Encryption keys must be 256 bits. A missing key for existing ciphertext is an error; never generate a replacement key and overwrite unreadable data.
- Secret filenames must use the versioned SHA-256 account mapping. Only explicitly listed legacy names may migrate.
- Keep `.secrets` under the validated `Application Support/Yeoman` hierarchy with `0700` directories and `0600` files.
- Validate tokens before storage. Remove a plaintext/defaults source only after the protected destination write succeeds.
- Migrations must be idempotent, conflict-aware, and crash-safe. Conflicting records or image bytes must stop migration and preserve all source data.

## WebKit and network content

- Use a stable, valid `WKWebsiteDataStore(forIdentifier:)` per persistent widget and `.nonPersistent()` for previews. Reject and repair both reserved UUID sentinels ending in `…0000` and `…0001` before WebKit receives them.
- Keep untrusted pages isolated from native privileges. Do not add a script-message bridge, custom privileged scheme, unrestricted external URL dispatch, or automatic popup capability without a separate threat review and negative tests.
- External protocol dispatch and new-window behavior must require an explicit user link activation. Display only sanitized origin information, never secrets from URL paths or queries.
- Favicon retrieval must stay in the widget WebKit context, use exact same-origin HTTPS, omit credentials, reject redirects, and retain candidate, byte, pixel, frame, time, concurrency, and cache bounds.
- Report website-data container deletion errors honestly. Data purge completion and container removal are different outcomes.
- Assume web pages remain adversarial after load. Visibility or throttling is not proof that all JavaScript timers stopped.

## Clipboard, process, and event handling

- Clipboard privacy filtering is best effort. Keep transient/concealed markers, before/after `changeCount` checks, source exclusions, and strict item/type/text/image/history limits.
- Decode images through bounded metadata and pixel checks. Limit concurrent image work, and prevent stale work from resurrecting deleted entries.
- Clipboard persistence must remain optional. Explicit opt-out always wins over legacy-directory discovery.
- Process sampling must drain stdout and stderr concurrently, enforce aggregate byte and time limits, and parse numeric values losslessly.
- Task-manager termination must bind PID, effective UID, and process start time, then revalidate immediately before signaling. Reject self, system PIDs, protected processes, and lossy integer conversion.
- Event taps must request only scroll-wheel events, verify event types, handle permission revocation, and use overflow-reporting arithmetic for transformed deltas.

## Required tests

- Use the executable `YeomanTests` harness in `Tests/`. Every security or persistence bug fix must include a regression test that fails on the vulnerable implementation and passes on the fix.
- Test security invariants through public or internal behavior, not by duplicating the implementation in the assertion.
- Include negative tests for malformed, oversized, tampered, conflicting, linked, raced, or partially migrated input. A happy-path test alone is insufficient for a security boundary.
- Use real primitives where practical: genuine ZIP files, CryptoKit signatures, AES-GCM documents, ad-hoc signed fixture bundles, WebKit data stores, filesystem symlinks/hardlinks/FIFOs, and real pipe pressure.
- Use synthetic data only. Tests must not read, modify, migrate, delete, or print production secrets or user data.
- Make asynchronous tests deterministic with bounded waits and explicit completion conditions. Do not use arbitrary long sleeps.
- Preserve source data in failure tests and assert that it remains unchanged. For race fixes, control the exact handoff or mutation point.
- Do not add superficial tests that merely restate a constant or mirror the code. Low-impact visual-only changes need no test unless they affect behavior.
- Required local gate for ordinary changes:

  ```bash
  swift build
  swift run YeomanTests
  git diff --check
  ```

- Additional gate for concurrency, persistence, updater, WebKit lifecycle, process, or event changes:

  ```bash
  swift run --sanitize thread YeomanTests
  ./Scripts/build_app.sh development
  codesign --verify --deep --strict dist/Yeoman.app
  ```

- Release gate additionally requires a macOS 14 CI run, the intended release architecture, external-key packaging, independent manifest verification, and recorded ZIP/DMG SHA-256 hashes.
- Do not weaken, skip, or delete a failing security test to obtain a green build. Correct an obsolete expectation only when the intended contract changed, and document that contract.

## README and release documentation standard

- Update `README.md` as an explicit step of every release before tagging or publishing. Synchronize module descriptions, new settings or workflows, required permissions, platform/architecture scope, build/test commands, and visual assets under `Resources/Mockups/` with the actual shipped code.
- Write `README.md` and all GitHub-facing content in concise, technical English. Never use emojis in headings, badges, tables, prose, or rendered graphics.
- Maintain the canonical `README.md` structure:
  - Centered hero header: `Resources/AppIcon.png`, title, one-line technical summary, flat-square `shields.io` badges, anchor navigation links, and the full-width real settings screenshot (`Resources/Mockups/yeoman_settings_window.png`).
  - `## Overview`: summary table (`Module`, `Purpose`, `Permissions`) kept in exact 1:1 sync with numbered subsections under `## Modules`.
  - `## Installation` (pre-built Apple Silicon `arm64` binary download plus accurate Gatekeeper, ad-hoc signing, SHA-256, and Ed25519 verification guidance, alongside source build instructions), `## Architecture & Security` (linking `SECURITY.md` and `docs/security/SECURITY_IMPLEMENTATION_REPORT.md`), `## Building & Testing`, `## Motivation & Background`, and `## License`.
- Preserve both the personal motivation paragraphs and the `> **AI Transparency:**` blockquote inside `## Motivation & Background` verbatim in substance unless the owner explicitly directs changes to them.
- Visual asset and screenshot standard:
  - Prefer real AppKit/SwiftUI captures of actual application views over fabricated mockups whenever native UI exists (`Scripts/capture_real_screenshots.swift`). All screenshot/render scripts must run inside a private `0700` temporary sandbox using English localization and synthetic data only—never read or expose production user data.
  - Use clean, compact, authentic renders via `Scripts/generate_menubar_comparison.swift` and `Scripts/generate_tool_graphics.swift` only where a single live settings pane cannot show the behavior (e.g., macOS menu bar notch clearance, Finder Cut overlay workflow, Scroll Reverser routing, live Terminal Saver ASCII showcase, and custom media background cutout comparison). Avoid bloated marketing cards, fake telemetry dashboards, or emojis.
  - Visually inspect every newly generated or updated PNG under `Resources/Mockups/` and `Resources/AppIcon.png` before committing to verify framing, contrast, legibility, and representative frames (for example, an immediately recognizable 3D Donut orientation).
  - Keep `Resources/AppIcon.png` and `Resources/AppIcon.icns` synchronized via `Scripts/generate_app_icon.swift` whenever the app icon changes.
- Keep all `README.md` claims strictly factual and bounded: state supported macOS 14+ `arm64` pre-built coverage, ad-hoc code signing + pinned Ed25519 manifest authentication, best-effort clipboard privacy filtering, same-UID secret-store limits, and zero external Swift dependencies accurately.

## Git and GitHub version control

- Coding agents are responsible for maintaining clean version control and keeping GitHub (`origin/main`) synchronized with completed, verified work rather than leaving finished changes uncommitted locally.
- Group changes into small, focused, atomic commits with clear English commit messages (for example `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`). Only commit genuine, verified progress; never create empty or filler commits.
- Stage only files belonging to the completed task. Inspect `git status` and `git diff --check` before committing, and never stage secrets, private keys, temporary files, or build outputs (`dist/`, `.build/`).
- Run the applicable local verification gate before pushing. Push verified commits to `origin/main` proactively unless the owner explicitly asks to hold changes locally or work on a separate branch/PR.
- Never force-push `main`, rewrite published history, or move published release tags.

## Review and documentation

- Review the complete diff from the relevant baseline and inspect call sites, migrations, error paths, and cleanup behavior. Do not trust implementation reports blindly.
- Update `README.md` and the current security report whenever behavior, storage, networking, trust boundaries, supported architecture, tests, or release steps change.
- Keep old audits as historical evidence and label superseded verdicts clearly. Never rewrite an old published result to imply it evaluated later code.
- Record commands actually run, test counts, platform/architecture limitations, and artifact hashes. Do not claim a platform, format, race, failure mode, or security property was verified unless evidence exists.
- Classify accepted product boundaries separately from fixable vulnerabilities. The accepted file-secret same-UID limitation does not excuse unrelated same-UID substitution, symlink, deletion, or integrity bugs.
