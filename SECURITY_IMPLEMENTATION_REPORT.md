# Security Implementation Report

As of: 22 October 2026  
Audit Baseline: `c3c8e75`  
Platform: macOS 14+, Swift/AppKit/SwiftUI  
Status: Remediated, verified, and configured for release.

## Trust Model

Per explicit user direction, Apple Developer ID signing and notarization are not required. Release application bundles are strictly ad-hoc codesigned to ensure code tampering detection after packaging. Independent of codesigning, update origins are cryptographically authenticated via an Ed25519 signature covering product identifier, semantic version, ZIP archive name, archive byte length, and SHA-256 digest.

`UpdateTrust.publicKeyBase64` is configured with the production Ed25519 release verification public key. Private keys remain strictly outside the repository in secure local custody with `0600` permissions.

## Security Controls Mapping

| ID | Implementation | Regression Verification | Residual Boundary |
|---|---|---|---|
| SEC-01 | Pinned Ed25519 metadata, pre-extraction archive SHA-256 validation, strict Bundle-ID/version verification, and deep static code signature verification | Signature, key, downgrade, digest, bundle forgery, and ad-hoc tamper tests | Release publisher identity is established via Ed25519; ad-hoc codesigning alone provides local integrity rather than Apple Developer Identity |
| SEC-02 | Segregated API, asset, redirect, and release URL policies; exclusive HTTPS/443 without userinfo; exact repository paths; maximum 4 redirects; Authorization header restricted to API origin | Foreign path, subdomain, userinfo, port, DMG asset, foreign redirect, redirect count, and official CDN host assertions | Documented changes to GitHub official CDN infrastructure must be explicitly reflected in policy |
| SEC-03 | Custom ZIP header policy validation combined with system libarchive; descriptor-relative extraction; rejection of symlinks and special files; path, collision, entry, byte, and wall-clock limits | Path traversal, absolute paths, app/component symlinks, FIFOs, duplicate entries, case collisions, quota breaches, and genuine `/usr/bin/zip -X` profile | Time limits are evaluated between libarchive reads and do not pre-emptively interrupt a blocking kernel/C call |
| SEC-04 | Bundled standalone `YeomanInstaller` helper binary; removal of temporary shell scripts; minimal process environment; pre-validation handshake before host app termination | Helper bundle integrity verified in test suite; missing trust anchor fails closed prior to handoff | No protection against arbitrary malicious processes running under the same UID |
| SEC-05 | Advisory lock file, process identity validation beyond PID, grace period, staging on destination volume, backup, rollback, transaction journal, recovery, and launch confirmation | Move/disk space errors, final verification failure, rollback, missing target, existing target recovery | Application installation requires write privileges on the target volume; no privileged helper daemon is used |
| SEC-06 | GitHub API token stored in macOS Login Keychain; validated, crash-safe migration from UserDefaults without plaintext fallbacks | Migration success/failure, deletion, invalid token preservation tests | Interactive keychain prompt on ad-hoc update replacement may occur if Keychain ACL prompts user |
| SEC-07 | Removal of native favicon network requests; retrieval strictly within existing WebKit context restricted to current HTTPS origin | Foreign host, loopback, HTTP, and cross-origin attempts rejected natively | Opened websites retain standard WebKit browser networking capabilities |
| SEC-08 | Maximum 8 candidates, 2 active fetch tasks, global 4-second fetch window, 2 MiB, 4 MP, ImageIO metadata verification, and 64-px thumbnail clamping | Byte/pixel quotas, image format decoding validation | WebKit handles DNS and transport for page assets |
| SEC-09 | Main-thread-isolated favicon state, request tokens/timeouts, profile- and option-bound SHA-256 keys, bounded NSCache | Profile-scoped collision-resistant keys and ThreadSanitizer verification | In-memory ephemeral favicon cache only; no unencrypted offline disk cache |
| SEC-10 | Complete removal of Google/DuckDuckGo third-party favicon fetching and base-domain heuristics | Source code audit: zero native favicon `URLSession` network paths | Third-party favicon fallbacks intentionally removed |
| SEC-11 | Persistent, isolated `WKWebsiteDataStore` per stable widget UUID; preview mode is strictly non-persistent; widget URLs stored with AES-GCM encryption | Cookie and storage isolation between identical domains; deletion of one widget preserves others | WebKit may retain container file descriptors until process exit; website data is purged explicitly |
| SEC-12 | Automatic popups and HTML5 element fullscreen disabled; dangerous schemes blocked; navigation allowed only on explicit link click; origin bar visible; scripts isolated without native bridge | WebKit configuration, scheme blocking, and origin formatting tests | Page JavaScript remains enabled for web application execution |
| SEC-13 | Bounded clipboard snapshots, maximum 16 items / 64 types, changeCount verified before and after materialization, tracking markers on all items; pause and app exclusions | Markers, generation shifts, sensitive snapshot exclusions | First pasteboard materialization memory allocation is managed by the source application |
| SEC-14 | Image filenames strictly validated UUIDs; secure descriptor-relative legacy read/delete operations; no plaintext image paths | Directory traversal, symlinks, hardlinks, and FIFOs rejected | Unrecognized third-party legacy files are preserved rather than deleted |
| SEC-15 | Directory permissions `0700`, files `0600`; ownership, type, hardlink, and ACL validation; atomic write operations | POSIX mode, ACL, symlink, hardlink, and FIFO enforcement | APFS snapshots and backups may retain prior filesystem blocks |
| SEC-16 | Ephemeral history available; AES-GCM authenticated encryption for entire persistent snapshot including images; SecureFileSecretStore in private 0700/0600 directory (eliminating invasive macOS Keychain prompts); record identity binding | Tampered ciphertext, missing key, roundtrip, and plaintext search rejection | Private POSIX permissions protect user data without system authorization popups |
| SEC-17 | Quotas: 1 MiB text, 20 MiB encoded image, 16 MP, 500 items, 2 image jobs, 70 MiB raw payload cap within 100 MiB document size | Size limits, metadata validation, pinned quotas, and total capacity checks | Decoding and JSON encoding utilize temporary memory within these bounds |
| SEC-18 | Serial store mutations, batched commits, committed snapshot rollback, generation tracking for images, and coalesced thumbnail jobs | Deletions take precedence over pending saves and deferred background jobs | Physical secure block erasure is not guaranteed on copy-on-write filesystems |
| SEC-19 | Simultaneous stdout/stderr draining, aggregate output cap, deadlines, cancellation, single-flight execution; lossless `ps` parser | Pipe capacity deadlock prevention, stderr load, size limits, timeouts, and lossy numeric input rejection | Subprocesses must not leave orphan daemons with inherited pipes |
| SEC-20 | Exact PID verification (`pid_t(exactly:)`), PID + UID + start time binding, libproc re-verification, single signal pathway, protection of self and system processes | PID recycling, UID checks, self-termination protection, signal handling | Darwin kernel offers no atomic check-and-signal syscall; residual race window is minimized |
| SEC-21 | Centralized bounds for URLs, strings, widget counts/IDs, width, height, user zoom, auto-fit zoom, scroll multipliers, menu spacing; overflow-safe arithmetic | Negative/extreme/NaN/infinite inputs, duplicates, integer overflows | Direct operating system memory exhaustion follows standard error paths |
| SEC-22 | Event tap mask strictly `scrollWheel`; event type validation; pure tap state machine; periodic re-verification; graceful teardown upon TCC revocation | Permission revocation, failed creation, idempotent start/stop, non-scroll events | Real TCC state reset is not executed in automated unit tests |

## Audit Remediation (Findings from SECURITY_REVIEW.md)

| Audit ID | Finding | Remediation / Implementation | Status |
|---|---|---|---|
| **AUD-01** | `Bundle(url:)` cache prevents legitimate in-place version upgrades | `BundleVerifier.readPlist` & `BundleVerifier.verify` read `Info.plist` fresh from disk with bounded size checks without relying on Foundation's cached bundle state. | Resolved & Verified |
| **AUD-02** | Clipboard persistence opt-out overwritten on restart if old directory exists | `defaults.object(forKey:)` checks explicit user preference; legacy directory existence no longer overrides explicit user opt-out. | Resolved & Verified |
| **AUD-03** | Potential data loss: unimported legacy clipboard files deleted on launch | `migrate` merges unimported legacy items into active encrypted snapshot; `cleanLegacy` runs only after committed snapshot transaction. | Resolved & Verified |
| **AUD-04** | Potential installer substitution by another ad-hoc signed bundle | `BundleIdentity` binds executable SHA-256 digest and `cdhash`; `InstallTransaction.replace` verifies identity equality before replacement. | Resolved & Verified |
| **AUD-05** | All-zero UUID crashes WebKit DataStore with `NSInvalidArgumentException` | `UUID.isValidWebKitIdentifier` validates non-nil identifier; `WidgetStorage.decode` repairs invalid legacy UUIDs automatically. | Resolved & Verified |
| **AUD-06** | Delayed WebPanel cache purge dereferences nil webView after `dispose()` | Added `isDisposed` flag, lifecycle generation counter, and safe optional guarding of `webView` prior to cache purge. | Resolved & Verified |
| **AUD-07** | Release tests failed when production public key was configured | `UpdateTrust.parseKey` decouples test suite assertions (empty, malformed, valid) from the production trust constant. | Resolved & Verified |
| **AUD-08** | Website data clearing missed default WebKit store | `clearAllWebsiteData` wipes both widget-specific stores and `WKWebsiteDataStore.default()`. | Resolved & Verified |
| **AUD-09** | Multi-representation ICO favicons rejected by single-frame decoder | `BoundedImage.decode` supports 1 to 32 frames, selecting the optimal frame within thumbnail bounds. | Resolved & Verified |
| **AUD-10** | Path case collisions possible on intermediate directories | `SafeArchive` & `ZIPHeaderPolicy` track canonical case across all intermediate directory prefixes. | Resolved & Verified |

## Verification Results

- `swift build`: Successful.
- `swift run YeomanTests`: **66/66 unit tests passed**.
- `swift run --sanitize thread YeomanTests`: **66/66 unit tests passed**, 0 ThreadSanitizer warnings.
- `./Scripts/build_app.sh release`: Successful; app bundle and helper signed with ad-hoc signatures.
- `codesign --verify --deep --strict dist/Yeoman.app`: Valid.
- `./Scripts/package_release.sh`: Successful; produced `dist/Yeoman.dmg`, `dist/Yeoman.zip`, and signed `dist/Yeoman.update.json`.
- `git diff --check`: Clean; no whitespace or syntax errors.
