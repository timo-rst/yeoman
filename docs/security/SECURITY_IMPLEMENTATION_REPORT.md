# Security Implementation Report

As of: 26 November 2026
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
| SEC-23 | Closed web widgets release their SwiftUI/AppKit rendering hierarchy without discarding live page state; autoplay requires user interaction, each widget retains its distinct persistent `WKWebsiteDataStore`, and transient boot/wake/network load failures recover via `NWPathMonitor`, wake observers, bounded retries, and presentation-time reload with cancellation on disposal | Data-store separation, autoplay policy, rendering detachment, wake/network/provisional-failure recovery, and timer-disposal tests | Public WebKit APIs do not guarantee reclamation of a live page's DOM or JavaScript heap |
| SEC-24 | The settings window is explicitly classified as a normal managed macOS window that participates in Mission Control, fullscreen mode, and window cycling until closed or minimized | Window-policy regression test verifies every collection-behavior flag | Standard macOS WindowServer behavior controls Mission Control layout and minimized-window presentation |
| SEC-25 | Clipboard and task-manager popovers use one persisted pin preference per module; pinned state maps to native `applicationDefined` behavior and the footer/settings controls share the same observable state. The clipboard non-modal image preview panel follows the same pin state for outside-click and app-deactivation dismissal, and the full-image window decodes bounded image data strictly in memory | Isolated-defaults persistence, native popover-behavior, pin-aware dismissal-policy, and bounded initial window-sizing regression tests | Pinned popovers and their child preview panels remain user-controlled foreground UI until explicitly closed or unpinned |
| SEC-26 | `FinderCutManager` monitors `.keyDown` events only while `com.apple.finder` is frontmost, excludes focused Accessibility text-input roles (`AXTextField`, `AXTextArea`, `AXSearchField`, `AXComboBox`, `AXWebArea`), validates pasteboard `changeCount` consistency, delegates file operations natively via Finder `AXMenuBar` press (`.privateState` synthetic fallback) without touching disk paths, stores zero keystrokes, uses `TapLifecycle` for TCC revocation, and bounds missing-permission fallback hotkeys to Finder with mute/cooldown controls. `FinderCutItemOverlayController` uses a click-through `.nonactivatingPanel` active only when Finder is frontmost with a pending cut, bounds AX element/depth scanning, and projects live WindowServer single-window bounds (`CGWindowListCopyWindowInfo`) during resize drags with zero polling when idle or outside Finder | Event-mask, shortcut classification, non-Finder pass-through, AX text-field exclusion, state-machine, pasteboard-mismatch, fallback-hotkey cooldown, header-clipping, adjacent-merge, and geometry-projection tests | Requires user-granted Accessibility permission; Finder retains full ownership of file moves, conflict resolution, and window visual ordering |
| SEC-27 | `TerminalSaverMediaStore` isolates config and imported media under `SecureDirectory` (`0700`/`0600`) with UUID filenames, rejects symlinks/non-regular imports, enforces byte (`25 MiB` image / `40 MiB` video), pixel (`16 MP`), frame (`300`), duration (`30 s`), library (`64`), and decode-time (`15 s`) / cutout (`25 s`) limits in `TerminalSaverMediaDecoder`. `YeomanTermSaver` enforces TTY-only raw mode, signal-safe `termios` and Alternate Screen restoration, `50 ms` / `64-byte` escape-sequence assembly, bounded Auto-Advance loop/cutoff handling, and zero background daemon polling. `TerminalSaverShellIntegrator` rejects symlinks/FIFOs/foreign-owned rc files, preserves one-time backups, and uses delimited idempotent managed blocks | Filigree edge/ramp/color tests, synthetic GIF/PNG/MP4 decode & symlink/corrupt rejection tests, config sanitization tests, random-mode/ASCII-transition/auto-advance-cutoff regressions, and isolated temp-home shell install/uninstall/symlink-rejection tests | Prompt-idle shell hooks (`zsh`/`bash`/`fish`) do not activate while an editor or foreground command owns the TTY unless run inside `tmux` |

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
- `swift run YeomanTests`: **107/107 tests passed**.
- `swift run --sanitize thread YeomanTests`: **107/107 tests passed**, 0 ThreadSanitizer warnings.
- `swift test`: unavailable with Command Line Tools; the repository's native executable test harness remains the supported entry point.
- `Scripts/capture_real_screenshots.swift`: typechecks cleanly with `YeomanCore` using public API methods.
- `./Scripts/build_app.sh release`: Successful; app bundle and nested `YeomanInstaller` signed with ad-hoc signatures.
- Release candidate `0.2.9 (11)`: `arm64` application and helper; ZIP integrity and DMG checksum verification successful.
- `Yeoman.zip` SHA-256: `e803d561bc4c6582ea2842dc981c549a411434b11900b7e5eef392e0cf709083`.
- `Yeoman.dmg` SHA-256: `0245ab22d6109c309781c353528674aa1cb2791e390ee0689ff940493655631e`.
- `codesign --verify --deep --strict dist/Yeoman.app`: Valid.
- `./Scripts/package_release.sh`: Successful for v0.2.9 using external `0600` release key; produced `dist/Yeoman.dmg`, `dist/Yeoman.zip`, and signed `dist/Yeoman.update.json`.
- Signed manifest verification: Successful; Ed25519 signature, version `0.2.9`, archive size `4247043`, and archive SHA-256 (`e803d561bc4c6582ea2842dc981c549a411434b11900b7e5eef392e0cf709083`) all match.
- `git diff --check`: Clean; no whitespace or syntax errors.

## Built-in Terminal Saver scene settings

Scene speed, palette, and the optional 3D Donut shading style use the existing descriptor-relative configuration file and its 512 KiB read/write limit. Configurations saved before these options were added retain the original colors, glyphs, and 1.0× speed. The config store clamps scene speeds to 0.1×–2.0×, falls back to 1.0× for non-finite values before saving, and discards style overrides for scenes with fixed glyphs.

The isolated config-store regression covers legacy defaults, independent scene overrides, and speed bounds. The renderer regression checks speed and color across all eight scenes and verifies that alternate Donut styles preserve the visible cell positions.

Local verification on macOS 26.7.3 (arm64):

- `swift build` and `git diff --check` passed. Untracked source and test files passed a separate whitespace check.
- `swift run YeomanTests` and `swift run --sanitize thread YeomanTests` each passed 135/135 tests. ThreadSanitizer reported no findings.
- The debug `YeomanTermSaver` loaded a synthetic per-scene config in an isolated pseudo-terminal, rendered the saved Amber palette and Strokes style, and exited on a wake key.
- `./Scripts/build_app.sh development` and `codesign --verify --deep --strict dist/Yeoman.app` passed in a temporary workspace. The development executable SHA-256 hashes were:
  - `Yeoman` — `01c4c665b3242c3d857bccba8d1afd039559a92f7f462b9d2ff20c58817fb216`
  - `YeomanTermSaver` — `429fff2d513aa83d96afe7d54699909cb473ce5d5ac7e5ddb1bb134b9c5e603b`
  - `YeomanInstaller` — `372dd5c431c0e8b7948677930055002132b6f5852a13f0037e3ab1ace8a5fd8c`

## Bouncing DVD Logo preset

The DVD preset draws a local ASCII logo at a reflected position within the existing bounded grid and advances the original palette on each impact. The former `moonlitRain` identifier decodes as `bouncingDVD` in saved selections, rotation state, scene settings, and CLI scene arguments. New saves use `bouncingDVD`.

On macOS 26.7.3 (arm64), `swift build` and `git diff --check` passed. Both `swift run YeomanTests` and `swift run --sanitize thread YeomanTests` passed 137/137 tests, including saved-scene compatibility and reflection against both grid edges. ThreadSanitizer reported no findings. In an isolated pseudo-terminal, both CLI identifiers rendered the DVD logo, changed colors, and exited on input.

`./Scripts/build_app.sh development` and `codesign --verify --deep --strict` passed for the locally installed bundle. Its executable SHA-256 hashes are:

- `Yeoman` — `e594ec618146ba6905c9ea91e4632a3e198d16ca3a37691a87ba3c4369b2ac7c`
- `YeomanTermSaver` — `d483545f651d5ad4e006379fda2d07630f69cce7846406bc854dd8a309ca989e`
- `YeomanInstaller` — `595b135ded38ee53aacf96bbd3e4e865568e101efd58921a98c2cd146b4c0b4f`


## Buffered terminal navigation

The helper assembles split key sequences across multiple reads within a monotonic 50 ms deadline and 64-byte cap. Terminal focus notifications and legacy status replies remain non-waking inputs. Frame pacing for buffered terminals uses a monotonic schedule without terminal status queries. One pending navigation action can carry across a scene transition while a wake key still interrupts immediately.

On macOS 26.7.3 (arm64), `swift build`, `git diff --check`, `./Scripts/build_app.sh development`, and strict deep signature verification passed. `swift run YeomanTests` and `swift run --sanitize thread YeomanTests` each passed 138/138 tests. The added regression uses separate socket datagrams to exercise multi-read arrows and Page Down along with expiration of a bare Escape.

The pre-fix helper exited on a Right Arrow split across three pseudo-terminal reads. The installed helper was exercised through an isolated pseudo-terminal paired with the headless xterm package (6.1.0-beta.213) bundled in VS Code 1.121.0. The test verified entry animation, transition frames in both directions, queued navigation, continued playback after switching, and return to the normal screen with the original terminal attributes restored. It did not exercise the graphical VS Code renderer.

Installed development executable SHA-256 hashes:

- `Yeoman` — `f9a889dd80d866d7aa2807afc9f6bcfdcaf53cdf3c2ec9212a72a9ae2c4fdbb7`
- `YeomanTermSaver` — `7ede165ce5d0a6bb625de2041ae058bf90e1537f40603fc52ded93590db23e28`
- `YeomanInstaller` — `147867a06b13a60a27ed4a9bddf478b25aa1fe188c1b5e2b72924a5feb102ad6`

## Repeating Terminal Saver scene order

The bounded rotation file retains a full permutation of the active sources and its remaining suffix. Navigation wraps in either direction and each activation resumes from the persisted cursor. Legacy saves retain their known unplayed suffix. Removing a source filters it from the order, while adding a source generates a new permutation. The store serializes rotation mutations using the existing private directory descriptor and rejects cursor writes from sessions whose saved snapshot has since changed.

On macOS 26.7.3 (arm64), `swift build`, `git diff --check`, and `./Scripts/build_app.sh development` passed. Both `swift run YeomanTests` and `swift run --sanitize thread YeomanTests` passed 140/140 tests. The installed helper kept one three-scene permutation through 17 forward/backward changes and six reactivations in an isolated pseudo-terminal. The development helper also passed the buffered xterm transition regression. `codesign --verify --deep --strict` passed on the installed bundle.

Installed development executable SHA-256 hashes:

- `Yeoman` — `dc247f78ac774fada030f40fa3bd8c18cd2595ad756877887ae02f6f0ce2188d`
- `YeomanTermSaver` — `bd3036a9b1c8c5c4e37bc777874ed00f6317fad511203e48addaec19c52b7c31`
- `YeomanInstaller` — `d24207f006ac2e7bb4d5b91b3e5da5c37c05aeb90a8cb2594af5abf5aa9ec18e`

## Terminal Saver settings retention

The module flushes pending settings during shutdown while preserving the saved activation flag for the shell helper. The manager distinguishes the last committed configuration from unsaved edits, keeps failed writes available for retry, and reports configuration and managed-hook write failures. An unreadable configuration disables manager writes for that app session and stays on disk for recovery.

On macOS 26.7.3 (arm64), `swift build`, `git diff --check`, and `./Scripts/build_app.sh development` passed. Both `swift run YeomanTests` and `swift run --sanitize thread YeomanTests` passed 143/143 tests. An isolated module shutdown test verified the full configuration, original imported GIF bytes and the updated managed zsh timeout after reloading. Negative tests preserved unreadable bytes and verified that a failed save could be retried. With a synthetic enabled config, the signed helper ran through repeated activations in a pseudo-terminal using `--run`. `codesign --verify --deep --strict` passed on the installed app.

Installed development executable SHA-256 hashes:

- `Yeoman` — `138f87cb5a1ec7b76b392cbfa63aeafae412ba57218170add7b13b072f98effc`
- `YeomanTermSaver` — `6b46f34cafdcbca3128dd83de36df61f08651355e444eaa00eee94a6b77368b5`
- `YeomanInstaller` — `49b6ab2a2381b332a4e5af28052c9de422794dba91bd41a654059731f97337b4`

## Terminal Saver color output and resize handling

Integrated IDE terminals now use the xterm 256-color palette for all frames to limit the number of glyph and color combinations the renderer caches. Native terminal color detection remains in effect. A resize invalidates the incremental frame baseline, interrupts animations tied to the old grid and coalesces resize bursts before a full redraw. Playback waits for a drawable size if the window is smaller than the supported grid.

An isolated pseudo-terminal reproduced old-grid writes during the entry animation in the prior helper. The updated helper passed resize checks during playback, entry, scene transitions and wake, including recovery from a window below the minimum size. In a 1.5-second Bonfire sample with the VS Code environment, the prior helper emitted 338 RGB colors and the updated helper emitted seven indexed colors. Pipes also used indexed colors. A Ghostty environment retained TrueColor and synchronized output. The headless xterm parser bundled with VS Code 1.121.0 decoded the expected Bonfire glyphs from both versions. The graphical IDE renderer and macOS 14 were outside this verification.

On macOS 26.7.3 (arm64), `swift build`, `git diff --check`, `./Scripts/build_app.sh development` and `codesign --verify --deep --strict dist/Yeoman.app` passed. Both `swift run YeomanTests` and `swift run --sanitize thread YeomanTests` passed 143/143 tests. ThreadSanitizer reported no findings.

Development bundle executable SHA-256 hashes

- `Yeoman` — `210a12c9dddf889045b2c11176570711d558e830b71a1d5a1c555d93e00a2030`
- `YeomanTermSaver` — `1d948fca6e221e5327a873bda7f24da7df0e946879c98a2eb8743fbfabfb8934`
- `YeomanInstaller` — `cc9e735d3451890c5d760b3f15cb12f39a915741c76015775663e9897a74a92d`

## Terminal Saver forward and reverse loops

The optional loop setting is stored per animated item in the existing bounded configuration. Older configurations default to forward playback. Preview and terminal playback share the same frame cursor and reuse the decoded frames. The cursor displays each turning frame once and leaves the imported media and cutout cache formats intact. The video decoder orders its bounded samples by their requested times before playback.

An isolated pseudo-terminal played a synthetic MP4 and GIF in both modes. Each reversed loop followed the frame order `0, 1, 2, 3, 2, 1, 0, 1` and preserved the original media bytes. An isolated live preview played the GIF in both modes and applied a setting change without reopening the preview. The configuration tests verified legacy defaults, per-item persistence and settings retention on shutdown.

On macOS 26.7.3 (arm64), `swift build`, `git diff --check`, `./Scripts/build_app.sh development` and `codesign --verify --deep --strict dist/Yeoman.app` passed. Both `swift run YeomanTests` and `swift run --sanitize thread YeomanTests` passed 144/144 tests. ThreadSanitizer reported no findings. Verification covered the local arm64 development bundle on macOS 26.7.3.

Development bundle executable SHA-256 hashes

- `Yeoman` — `0febd94907c6785a3eb0e780a3e38b75cc75b3f616eb2534193d2ca821360324`
- `YeomanInstaller` — `085b099fa2863b542ce83f75cd98c7b297149e2ee10462a64fc4d5d263bd7524`
- `YeomanTermSaver` — `e2de00ce37a9f17a4b98dd6b9d735974f2d02ffc9989c2037357e11368563618`

## Terminal Saver automatic scene advancement

The existing bounded settings document now stores the automatic advancement mode, duration and repetition count. Saved configurations predating the setting default to off. The helper counts complete media cycles, including the return leg of a forward and reverse loop. Built-in scenes and stills use the duration in repetition mode. Timed changes use the monotonic clock. Automatic and manual changes use the same navigation and rotation persistence path. The timer and repetition count restart on each source change.

An isolated pseudo-terminal exercised a right-arrow switch before the timer expired, a fresh five-second interval on the next source, automatic advancement and a subsequent left-arrow switch. Synthetic GIFs advanced after two forward or forward-and-reverse cycles, and a built-in scene advanced on the fallback duration. Off mode, a single active source and a forced-source session each suppressed automatic advancement.

On macOS 26.7.3 (arm64), `swift build`, `git diff --check`, `./Scripts/build_app.sh development` and `codesign --verify --deep --strict dist/Yeoman.app` passed. Both `swift run YeomanTests` and `swift run --sanitize thread YeomanTests` passed 146/146 tests. ThreadSanitizer reported no findings. Verification covered the local arm64 development bundle on macOS 26.7.3.

Development bundle executable SHA-256 hashes

- `Yeoman` — `171b1cf47207b6b442a9eb70f4b1b6201c4ce7b61e6fc5cd73aec23ec2219fb5`
- `YeomanTermSaver` — `deabb2cf0865e0c4fed38c936e57cd3b97f28cd33dcecff4d03bae8459b39c96`
- `YeomanInstaller` — `b084725fd49bedc2347bfae20b20a375b9849d072183dc6da7121500c3c41e1f`

## Terminal Saver timed advancement at loop boundaries

Timed advancement supersedes the earlier repetition mode. A saved repetition preference becomes timed advancement and retains its saved duration. Automatic changes wait for the current animated-media cycle to finish, including the reverse leg when enabled. Built-in scenes and still images advance on the timer. Automatic changes use a dissolve when the selected transition is instant. Manual navigation continues to use the selected transition.

An isolated pseudo-terminal expired a five-second timer during a synthetic forward loop and a forward-and-reverse loop. The helper played the rest of each loop before beginning a blended transition. A manual arrow press during the pending reverse leg switched immediately. A still image with the legacy repetition preference began its transition at the migrated deadline.

On macOS 26.7.3 (arm64), `swift build`, `git diff --check`, `./Scripts/build_app.sh development` and `codesign --verify --deep --strict dist/Yeoman.app` passed. Both `swift run YeomanTests` and `swift run --sanitize thread YeomanTests` passed 146/146 tests. ThreadSanitizer reported no findings.

Development bundle executable SHA-256 hashes

- `Yeoman` — `f3e3453946985ae82691cee2e0ee69fa42ac8c89b5f0ff098084e0ad4d92bc86`
- `YeomanTermSaver` — `2de414ef11ae5b1b0b442a762f321bc5b9328e96fd5ba11392464c1aec2c570b`
- `YeomanInstaller` — `174a67e5a9634c215372e0d7793bb728b27c89283a5290e9751a45db3458210c`


## Release 0.3.0 (12) Packaging & Verification

Verification executed on macOS 26.7.3 (`arm64`) for release `0.3.0 (12)`:

- `swift build`: Successful.
- `swift run YeomanTests`: **152/152 tests passed**.
- `swift run --sanitize thread YeomanTests`: **152/152 tests passed**, 0 ThreadSanitizer warnings.
- `Scripts/capture_real_screenshots.swift` and `Scripts/generate_tool_graphics.swift`: Compiled cleanly against `YeomanCore` without weakening access control and rendered updated module graphics in `Resources/Mockups/`.
- `./Scripts/package_release.sh`: Passed `YeomanTests` (`152/152`), `./Scripts/build_app.sh release` (`YeomanReleaseSign --check-trust`), and external-key signing; produced `dist/Yeoman.dmg`, `dist/Yeoman.zip`, and signed `dist/Yeoman.update.json`.
- Independent Ed25519 manifest verification (`dist/Yeoman.update.json` vs `UpdateTrust.publicKeyBase64`): Passed (`product=de.trst.Yeoman`, `version=0.3.0`, `archive=Yeoman.zip`, `size=7986112`, `sha256=57810a6b754e7535c955abd071f5011d503cea3f0f1ab3b7d741a43e093f0957`).
- `codesign --verify --deep --strict`: Passed for `dist/Yeoman.app`, `dist/Yeoman.app/Contents/Helpers/YeomanTermSaver`, `dist/Yeoman.app/Contents/Helpers/YeomanInstaller`, and `/Applications/Yeoman.app`.
- `git diff --check`: Clean; zero emojis detected across `README.md`, `RELEASE_NOTES.md`, `Scripts/capture_real_screenshots.swift`, and `Scripts/generate_tool_graphics.swift`.
- `Yeoman.zip` (`7986112` bytes) SHA-256: `57810a6b754e7535c955abd071f5011d503cea3f0f1ab3b7d741a43e093f0957`.
- `Yeoman.dmg` (`9969288` bytes) SHA-256: `b1c14da977b65060a8075d956d909633fe62d9a8514b225c92d9c16e625c7408`.

Release bundle executable SHA-256 hashes (`0.3.0 (12)`):

- `Yeoman` — `540320e9cdce04d989d2cc3e97d76f25d562efaf437bc58d6614f40b5dff754c`
- `YeomanInstaller` — `2fa4ef12df0ad90a2d1793e22f31c46a56172f1596fb5c017129518c8a5a3267`
- `YeomanTermSaver` — `73d842d8907494915bc9a037a4741543f53178e46a67e151f40c3f760e6b3fe9`
