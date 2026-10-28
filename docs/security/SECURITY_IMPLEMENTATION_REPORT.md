# Security Implementation Report

As of: 28 October 2026
Audit Baseline: `c3c8e75`  
Platform: macOS 14+, Swift/AppKit/SwiftUI  
Status: v0.2.1 independently audited; YEA-01 through YEA-06 remediated for v0.2.2.

## Trust Model

Per explicit user direction, Apple Developer ID signing and notarization are not required. Release application bundles are strictly ad-hoc codesigned to ensure code tampering detection after packaging. Independent of codesigning, update origins are cryptographically authenticated via an Ed25519 signature covering product identifier, semantic version, ZIP archive name, archive byte length, and SHA-256 digest.

`UpdateTrust.publicKeyBase64` is configured with the production Ed25519 release verification public key. Private keys remain strictly outside the repository in secure local custody with `0600` permissions.

## Security Controls Mapping

| ID | Implementation | Regression Verification | Residual Boundary |
|---|---|---|---|
| SEC-01 | Pinned Ed25519 metadata, pre-extraction archive SHA-256 validation, strict Bundle-ID/version verification, and deep static code signature verification | Signature, key, downgrade, digest, bundle forgery, and ad-hoc tamper tests | Release publisher identity is established via Ed25519; ad-hoc codesigning alone provides local integrity rather than Apple Developer Identity |
| SEC-02 | Segregated API, asset, redirect, and release URL policies; exclusive HTTPS/443 without userinfo; exact repository paths; maximum 4 redirects; Authorization header restricted to API origin | Foreign path, subdomain, userinfo, port, DMG asset, foreign redirect, redirect count, and official CDN host assertions | Documented changes to GitHub official CDN infrastructure must be explicitly reflected in policy |
| SEC-03 | Custom ZIP header policy validation combined with system libarchive; descriptor-relative extraction; rejection of symlinks and special files; path, collision, entry, byte, and wall-clock limits | Path traversal, absolute paths, app/component symlinks, FIFOs, duplicate entries, case collisions, quota breaches, and genuine `/usr/bin/zip -X` profile | Time limits are evaluated between libarchive reads and do not pre-emptively interrupt a blocking kernel/C call |
| SEC-04 | Bundled standalone `YeomanInstaller` helper binary; authenticated archive bytes are extracted from memory and the resulting bundle identity is retained across the shutdown handoff | Pre-handoff staging substitution and final replacement identity tests; missing trust anchor fails closed prior to handoff | A same-UID process can still interfere with writable application files after installation; the authenticated transaction rejects the demonstrated staging substitution |
| SEC-05 | Advisory lock file, process identity validation beyond PID, grace period, staging on destination volume, backup, rollback, identity-bearing transaction receipt, recovery, and identity-checked launch confirmation | Move/disk space errors, final verification failure, rollback, missing target, existing target recovery | Application installation requires write privileges on the target volume; no privileged helper daemon is used |
| SEC-06 | GitHub API token stored by `SecureFileSecretStore` in the private `.secrets` directory; validated, crash-safe migration from UserDefaults without plaintext fallbacks | Migration success/failure, deletion, invalid token preservation and filename-collision tests | A malicious process running as the same UID can read the permission-restricted token file; avoiding Keychain authorization prompts is an explicit product decision |
| SEC-07 | Removal of native favicon network requests; retrieval strictly within existing WebKit context restricted to current HTTPS origin | Foreign host, loopback, HTTP, and cross-origin attempts rejected natively | Opened websites retain standard WebKit browser networking capabilities |
| SEC-08 | Maximum 8 candidates, 2 active fetch tasks, global 4-second fetch window, 2 MiB, 4 MP, ImageIO metadata verification, and 64-px thumbnail clamping | Byte/pixel quotas, image format decoding validation | WebKit handles DNS and transport for page assets |
| SEC-09 | Main-thread-isolated favicon state, request tokens/timeouts, profile- and option-bound SHA-256 keys, bounded NSCache | Profile-scoped collision-resistant keys and ThreadSanitizer verification | In-memory ephemeral favicon cache only; no unencrypted offline disk cache |
| SEC-10 | Complete removal of Google/DuckDuckGo third-party favicon fetching and base-domain heuristics | Source code audit: zero native favicon `URLSession` network paths | Third-party favicon fallbacks intentionally removed |
| SEC-11 | Persistent, isolated `WKWebsiteDataStore` per stable widget UUID; preview mode is strictly non-persistent; widget URLs stored with AES-GCM encryption | Cookie and storage isolation between identical domains; deletion of one widget preserves others | WebKit may retain container file descriptors until process exit; data is purged first and container-removal errors are reported to the caller |
| SEC-12 | Automatic popups and HTML5 element fullscreen disabled; dangerous schemes blocked; external protocol dispatch and new-window handling require explicit links; origin bar visible; no native script-message bridge | WebKit configuration, scheme blocking, and origin formatting tests | Page JavaScript remains enabled for web application execution |
| SEC-13 | Bounded clipboard snapshots, maximum 16 items / 64 types, changeCount verified before and after materialization, tracking markers on all items; pause and app exclusions | Markers, generation shifts, sensitive snapshot exclusions | First pasteboard materialization memory allocation is managed by the source application |
| SEC-14 | Image filenames strictly validated UUIDs; secure descriptor-relative legacy read/delete operations; cleanup records exact files imported before encrypted commit; no plaintext image paths | Directory traversal, symlinks, hardlinks, and FIFOs rejected | Unrecognized third-party legacy files are preserved rather than deleted |
| SEC-15 | Directory permissions `0700`, files `0600`; ownership, type, hardlink, ACL, and application-owned ancestor validation; atomic write operations | POSIX mode, ACL, symlink, hardlink, and FIFO enforcement | APFS snapshots and backups may retain prior filesystem blocks |
| SEC-16 | Ephemeral history available; AES-GCM authenticated encryption for the entire persistent snapshot including images; `SecureFileSecretStore` uses a private 0700/0600 directory, collision-resistant filenames, and migration of v0.2.0 file-store keys | Tampered ciphertext, missing key, roundtrip, plaintext search rejection, filename collision and legacy file-key migration | POSIX permissions protect against other user accounts and accidental disclosure, but do not provide confidentiality against a malicious same-UID process |
| SEC-17 | Quotas: 1 MiB text, 20 MiB encoded image, 16 MP, 500 items, 2 image jobs, 70 MiB raw payload cap within 100 MiB document size | Size limits, metadata validation, pinned quotas, and total capacity checks | Decoding and JSON encoding utilize temporary memory within these bounds |
| SEC-18 | Serial store mutations, batched commits, committed snapshot rollback, generation tracking for images, and coalesced thumbnail jobs | Deletions take precedence over pending saves and deferred background jobs | Physical secure block erasure is not guaranteed on copy-on-write filesystems |
| SEC-19 | Process sampling drains stdout/stderr simultaneously and applies aggregate output caps, deadlines, cancellation, and single-flight execution; lossless `ps` parser | Pipe capacity deadlock prevention, stderr load, size limits, timeouts, and lossy numeric input rejection | Subprocesses must not leave orphan daemons with inherited pipes |
| SEC-20 | Task-manager termination uses exact PID verification (`pid_t(exactly:)`), PID + UID + start time binding, libproc re-verification, a single signal pathway, and protection of self and system processes | PID recycling, UID checks, self-termination protection, signal handling | Darwin kernel offers no atomic check-and-signal syscall; residual race window is minimized |
| SEC-21 | Centralized bounds for URLs, strings, widget counts/IDs, width, height, user zoom, auto-fit zoom, scroll multipliers, menu spacing; overflow-safe arithmetic | Negative/extreme/NaN/infinite inputs, duplicates, integer overflows | Direct operating system memory exhaustion follows standard error paths |
| SEC-22 | Event tap mask strictly `scrollWheel`; tail placement after macOS acceleration/momentum processing; dedicated user-interactive thread and run loop isolated from UI work; event type validation; pure tap state machine; periodic TCC re-verification; direct timeout recovery; native device settings bypass delta processing; no callback diagnostics | Permission revocation, failed creation, idempotent start/stop, non-scroll events, mouse/trackpad no-op routing, and ThreadSanitizer suite | Real TCC state reset and physical scroll latency are not measured in automated tests |
| SEC-23 | Closed web widgets release their SwiftUI/AppKit rendering hierarchy without discarding live page state; autoplay requires user interaction and each widget retains its distinct persistent `WKWebsiteDataStore` | Data-store separation, autoplay policy, and rendering detachment tests | Public WebKit APIs do not guarantee reclamation of a live page's DOM or JavaScript heap |
| SEC-24 | The settings window is explicitly classified as a normal managed macOS window that participates in Mission Control, fullscreen mode, and window cycling until closed or minimized | Window-policy regression test verifies every collection-behavior flag | Standard macOS WindowServer behavior controls Mission Control layout and minimized-window presentation |
| SEC-25 | Clipboard and task-manager popovers use one persisted pin preference per module; pinned state maps to native `applicationDefined` behavior and the footer/settings controls share the same observable state | Isolated-defaults persistence and native popover-behavior regression test | Pinned popovers remain user-controlled foreground UI until explicitly closed or unpinned |

## Audit Remediation (Findings from SECURITY_REVIEW.md)

| Audit ID | Finding | Remediation / Implementation | Status |
|---|---|---|---|
| **AUD-01** | `Bundle(url:)` cache prevents legitimate in-place version upgrades | `BundleVerifier.readPlist` & `BundleVerifier.verify` read `Info.plist` fresh from disk with bounded size checks without relying on Foundation's cached bundle state. | Resolved & Verified |
| **AUD-02** | Clipboard persistence opt-out overwritten on restart if old directory exists | `defaults.object(forKey:)` checks explicit user preference; legacy directory existence no longer overrides explicit user opt-out. | Resolved & Verified |
| **AUD-03** | Potential data loss: unimported legacy clipboard files deleted on launch | `migrate` merges unimported legacy items into active encrypted snapshot; `cleanLegacy` runs only after committed snapshot transaction. | Resolved & Verified |
| **AUD-04** | Potential installer substitution by another ad-hoc signed bundle | `BundleIdentity` binds executable SHA-256 digest and `cdhash`; `InstallTransaction.replace` verifies identity equality before replacement. | Resolved & Verified |
| **AUD-05** | All-zero UUID crashes WebKit DataStore with `NSInvalidArgumentException` | `UUID.isValidWebKitIdentifier` validates the identifier; `WidgetStorage` repairs invalid legacy UUIDs and atomically persists the repaired value before returning it. | Resolved & Verified |
| **AUD-06** | Delayed WebPanel cache purge dereferences nil webView after `dispose()` | Added `isDisposed` flag, lifecycle generation counter, and safe optional guarding of `webView` prior to cache purge. | Resolved & Verified |
| **AUD-07** | Release tests failed when production public key was configured | `UpdateTrust.parseKey` decouples test suite assertions (empty, malformed, valid) from the production trust constant. | Resolved & Verified |
| **AUD-08** | Website data clearing missed default WebKit store | `clearAllWebsiteData` enumerates every application-owned persistent store, including orphaned profile identifiers, and wipes `WKWebsiteDataStore.default()`. | Resolved & Verified |
| **AUD-09** | Multi-representation ICO favicons rejected by single-frame decoder | `BoundedImage.decode` supports 1 to 32 frames and selects the first representation that satisfies the pixel bound. | Resolved & Verified |
| **AUD-10** | Path case collisions possible on intermediate directories | `SafeArchive` & `ZIPHeaderPolicy` track canonical case across all intermediate directory prefixes. | Resolved & Verified |

## Independent v0.2.1 Audit Remediation

| ID | Remediation |
|---|---|
| YEA-01 | The updater extracts directly from authenticated ZIP bytes, captures the verified bundle identity before the app shutdown boundary, and requires that exact identity at staging and final target verification. The launch receipt also carries that identity. |
| YEA-02 | UUID validation rejects both WebKit sentinel values (`…0000` and `…0001`); legacy records are repaired and persisted before use. |
| YEA-03 | The file secret store starts at the trusted Application Support/test root and opens both `Yeoman` and `.secrets` with descriptor-relative, no-follow validation. |
| YEA-04 | Clipboard migration records and removes only image files tied to successfully imported records; unrelated UUID-shaped files remain. |
| YEA-05 | CI now lives at `.github/workflows/ci.yml`, runs on macOS 14, and does not require or expose the external release private key. |
| YEA-06 | WebKit data-store container removal errors are returned to the caller instead of treating generic error code 1 as success. |

## Verification Results

- `swift build`: Successful.
- `swift run YeomanTests`: **88/88 tests passed**.
- `swift run --sanitize thread YeomanTests`: **88/88 tests passed**, 0 ThreadSanitizer warnings.
- `swift test`: unavailable with Command Line Tools; the repository's native executable test harness remains the supported entry point.
- `Scripts/capture_real_screenshots.swift`: typechecks cleanly with `YeomanCore` using public API methods.
- `./Scripts/build_app.sh release`: Successful; app bundle and nested `YeomanInstaller` signed with ad-hoc signatures.
- Release candidate `0.2.7 (9)`: `arm64` application and helper; ZIP integrity and DMG checksum verification successful.
- `Yeoman.zip` SHA-256: `5ae30f9819629ac0788c75aa973079ec42fcc30ad48f8e5291516bdadae65766`.
- `Yeoman.dmg` SHA-256: `49534dacc6545c3a8740087d53ac5a70203e18d560d58c383d703ade44bff186`.
- `codesign --verify --deep --strict dist/Yeoman.app`: Valid.
- `./Scripts/package_release.sh`: Successful for v0.2.7 using external `0600` release key; produced `dist/Yeoman.dmg`, `dist/Yeoman.zip`, and signed `dist/Yeoman.update.json`.
- Signed manifest verification: Successful; Ed25519 signature, version `0.2.7`, archive size `3691035`, and archive SHA-256 (`5ae30f9819629ac0788c75aa973079ec42fcc30ad48f8e5291516bdadae65766`) all match.
- `git diff --check`: Clean; no whitespace or syntax errors.
