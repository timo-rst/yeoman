# Yeoman adversarial security review

> **Historical report:** This document records the findings against the original security implementation at `c3c8e75`. Its production rejection no longer describes the current tree. Remediation and current verification are documented in [`SECURITY_REREVIEW.md`](SECURITY_REREVIEW.md).

Review date: 22 October 2026. Baseline and current HEAD: `c3c8e7535c48bd93be6525052aea33ef177d6c72`. Scope: the modified working tree **and untracked security implementation files**, including the installer, signer, CArchive declarations, and tests. The implementation report was treated as a claim to verify, not evidence of correctness.

Runtime verification used macOS 26.5, arm64, Apple Swift 6.3.3. macOS 14 compatibility was inspected but not exercised on a macOS 14 host. Production application code was not modified during this review.

## 1. Executive verdict

**Overall rating: REJECTED for production tagging in its current state.**

The changes substantially improve security over the baseline. Publisher-authenticated update metadata replaces an HTTPS/host/bundle-ID trust model; archive extraction gains strict validation and descriptor-relative writes; native favicon fetching is removed; browser profiles are separated; private application records gain authenticated encryption; and process signaling now rechecks process identity.

However, passing tests conceal release-blocking defects. A real version-changing bundle replacement rolls back because verification reads cached bundle metadata. Clipboard persistence turns itself back on after an explicit opt-out when an old directory remains. Legacy clipboard files can be deleted without their contents being imported. Two additional WebPanel inputs/lifecycle sequences crash the process. The configured-key release path also conflicts with a test that requires the production key to remain unconfigured.

**Architectural elegance and maintainability: 6/10.** The small policy types, injectable secret store, isolated test defaults, and shared bounded I/O primitives are good foundations. The weaker areas are transaction state, migration provenance, asynchronous teardown, a handwritten second ZIP parser, and reliance on runtime main-thread conventions rather than actor isolation. Several dense implementations hide ordering requirements that the tests do not cover.

No remote Ed25519 forgery, AES-GCM authentication bypass, arbitrary native scheme bridge, or concrete C buffer overflow was demonstrated. This is a substantial security improvement with incomplete production acceptance, not evidence that the cryptographic primitives are broken.

## 2. Findings matrix

Severity reflects the stated utility-app threat model and includes privacy and functional regressions. “Reproduced” means an isolated executable linked against the reviewed `YeomanCore` code demonstrated the behavior. The local bundle substitution finding does not establish privilege escalation or defeat of Ed25519.

| ID | Severity | Component | Vulnerability / regression description | Exploitation / reproduction vector | Recommended remediation |
|---|---|---|---|---|---|
| AUD-01 | High | SEC-01/05: bundle verification | Final verification can read the previous version from Foundation's bundle cache and reject a legitimate upgrade. | **Reproduced:** verify a signed `1.0.0` target, replace it with a signed `2.0.0` bundle using `InstallTransaction.replace`; disk plist says `2.0.0`, `Bundle(url:)` says `1.0.0`, and the transaction rolls back. | Read bounded, fresh `Info.plist` bytes through verified filesystem handles; validate them alongside fresh static-code verification. Test real old-to-new signed bundles in the same process. |
| AUD-02 | High | SEC-16: clipboard privacy | An explicit persistence opt-out is overwritten on the next launch. | **Reproduced:** migrate a sibling `MacCustomizer` directory, disable persistence, and recreate the store. The now-empty old directory makes persistence true; subsequent clipboard content is written to the encrypted disk snapshot. | Distinguish an absent preference from explicit `false`. Record migration completion separately. Directory existence must never override user consent. |
| AUD-03 | High | SEC-14/16/18: clipboard migration | Existing ciphertext is treated as proof that all current legacy files were imported; unrelated/new legacy history is then deleted. | **Reproduced:** create a valid encrypted snapshot, introduce a different legacy history file, and reload. The legacy file disappears and its item is absent from the new history. An older app run or a backup restore can produce this state. | Track exactly which source snapshots and images were committed. Merge or quarantine unrecognized legacy data; delete only sources covered by the successful migration transaction. |
| AUD-04 | Med | SEC-01/03/05: local installer integrity | The extracted bundle's identity is not bound to the authenticated archive during later verification and path-based replacement. Another valid ad-hoc signature is accepted. | **Reproduced at transaction layer:** substitute a separately ad-hoc-signed fixture with the same bundle ID/version between staged verification and rename. Final verification accepts the changed executable. Requires same-UID filesystem access; a full signed-manifest installer exploit was not run. | Preserve an authenticated expected code/content identity through extraction and installation, compare it again before launch, and use descriptor-relative install operations. Document the remaining arbitrary-same-UID boundary; ad-hoc signing alone cannot supply publisher identity. |
| AUD-05 | Med | SEC-11/21: widget IDs | A syntactically valid all-zero UUID passes widget decoding but causes an uncaught WebKit exception. | **Reproduced:** decode widget ID `00000000-0000-0000-0000-000000000000`, then construct its controller. Process exits with `NSInvalidArgumentException`. Legacy configuration can supply this ID. | Reject WebKit-invalid identifiers before migration/save/controller creation; report or explicitly repair the affected record without creating a startup crash loop. |
| AUD-06 | Med | SEC-11/12: WebView teardown | A delayed cache purge dereferences the WebView after `dispose()` sets it to nil. | **Reproduced:** retain a controller, call `onPopoverClosed()`, then `dispose()`, and run the main loop for four seconds. The three-second callback traps at `WebPanelView.swift:247`. Production `cleanup()` uses that call order. | Cancel pending callbacks or invalidate them with a lifecycle generation; safely guard the optional WebView and make repeated teardown harmless. |
| AUD-07 | Med | Release validation | The release test suite requires the shipping trust anchor to be empty. Configuring a valid public key makes packaging fail at its first step. | **Code-proven:** `Tests/SecurityTests.swift:92` expects `UpdateTrust.key()` to throw; `package_release.sh:14` runs that test before its configured-key build. | Inject key material into parsing/validation tests. Test empty, malformed, and valid fixtures independently of the production constant; add a separate release configuration check. |
| AUD-08 | Med | SEC-11: browser-data deletion | The website-data clear operation stops clearing the legacy default store. Existing sessions/data from the baseline remain outside the new cleanup path. | **Code-proven:** the baseline used `WKWebsiteDataStore.default()`, while the new clear function visits only current widget IDs. No default-store migration cleanup exists in the reviewed WebPanel code. | Include the application's legacy default store in explicit full-data clearing; provide a migration cleanup path and account for orphaned profile IDs. |
| AUD-09 | Low | SEC-08/17: image compatibility | Requiring exactly one ImageIO image rejects valid multi-representation ICO favicons. | **Reproduced:** a small valid ICO with two PNG entries has image count 2 and is rejected before decoding. Similar multi-image containers need an explicit policy. | Bound representation count and select a suitable bounded frame instead of rejecting every multi-image icon. Retain encoded-byte and pixel limits. |
| AUD-10 | Low | SEC-03: archive namespace | Collision detection covers complete paths, but not alternate spellings of implicit parent directories. | **Reproduced:** `Yeoman.app/Foo/a` and `Yeoman.app/foo/b` are accepted. On a case-insensitive filesystem these share one directory. No path escape was demonstrated. | Track canonical identity and original spelling of every path component, including implicitly created directories; reject aliases and type conflicts consistently. |

### Evidence and precise code locations

- **AUD-01:** [cached metadata check](Sources/Yeoman/Core/Security/UpdateSecurity.swift#L116); target is read before replacement in [installer preflight](Sources/Yeoman/Core/Security/InstallTransaction.swift#L51), then verified at the same URL after rename. The probe observed:

  ```text
  Upgrade verification: staged disk: 2.0.0 Bundle: 2.0.0
  Upgrade verification: target disk: 2.0.0 Bundle: 1.0.0
  Real bundle version upgrade: failed: Falsches Update-Bundle oder falsche Version.
  ```

  The normal installer follows the same cache-warming sequence. This was a transaction/bundle-verifier test, not a live replacement of the installed application. The empty production trust key currently stops installation before this defect is reached.

- **AUD-02/03:** [clipboard load and migration cleanup](Sources/Yeoman/Modules/Clipboard/ClipboardHistoryStore.swift#L183). Line 191 ORs the preference with directory existence. Lines 194–203 skip import when ciphertext exists but still clean legacy sources. The probe observed:

  ```text
  Persistence after explicit opt-out: false
  Persistence after relaunch with empty legacy directory: true
  Disk snapshot after opt-out and relaunch: ["unexpectedly persisted"]
  New legacy file retained: false
  New legacy content imported: false
  ```

- **AUD-04:** [transaction verification and moves](Sources/Yeoman/Core/Security/InstallTransaction.swift#L14), [extraction and exit wait](Sources/Yeoman/Core/Security/InstallTransaction.swift#L68), and [ad-hoc validity check](Sources/Yeoman/Core/Security/UpdateSecurity.swift#L124). The fixture replaced a signed copy of `/bin/echo` with a separately signed copy of `/bin/cat`; neither was executed. The deterministic injection uses the transaction's move callback to model a filesystem substitution. It proves acceptance of the replacement identity, not a measured probability of winning a concurrent race. A process already able to rewrite the installed app has broader same-user capabilities regardless of this updater.

- **AUD-05:** [widget decoder](Sources/Yeoman/Modules/WebPanel/WidgetStorage.swift#L14) and [store construction](Sources/Yeoman/Modules/WebPanel/WebPanelView.swift#L41). WebKit's implementation explicitly raises an Objective-C exception for an invalid identifier; Swift `do/catch` around configuration loading does not turn that exception into a recoverable Swift error. [WebKit implementation](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebsiteDataStore.mm).

- **AUD-06:** [dispose](Sources/Yeoman/Modules/WebPanel/WebPanelView.swift#L135), [delayed callback and dereference](Sources/Yeoman/Modules/WebPanel/WebPanelView.swift#L235), and [production cleanup call order](Sources/Yeoman/Modules/WebPanel/WebPanelModule.swift#L637). The additional lifetime requirement is explicit: if the controller is immediately deallocated, the weak capture prevents the delayed crash; if it remains retained, it does not.

- **AUD-07:** [hardcoded unconfigured-key assertion](Tests/SecurityTests.swift#L92) and [packaging test gate](Scripts/package_release.sh#L14).
- **AUD-08:** [clear website data](Sources/Yeoman/Modules/WebPanel/WebPanelSettingsView.swift#L199). This is based on the baseline/current code comparison; the review did not read or delete the user's real browser data.
- **AUD-09:** [image-count guard](Sources/Yeoman/Core/Security/SecurityPolicy.swift#L41).
- **AUD-10:** [extraction canonicalization](Sources/Yeoman/Core/Security/SafeArchive.swift#L60) and [ZIP-header canonicalization](Sources/Yeoman/Core/Security/SafeArchive.swift#L145).

## 3. Deep dive analysis

### 3.1 Updater and CArchive — SEC-01 through SEC-06

**SEC-01: signature verification is correctly ordered for remote artifacts.** `SignedUpdate.verified` authenticates the exact payload bytes before JSON metadata is trusted. It checks the product, archive name, size, lowercase SHA-256 syntax, and strictly increasing parsed version. The UI also compares the asset tag with the signed version. Both app and helper check the archive hash before extraction. A correct bundle ID alone is insufficient; code-signature validity is also checked. AUD-01 and AUD-04 affect what happens after those checks.

Equal-version and lower-version replay are rejected against the installed version. There is no expiry or independently retained highest-seen version: an older, still-valid signed release newer than the local app can be presented. This is not an Ed25519 bypass, but the implementation should not claim general release freshness or freeze-attack resistance.

**Bootstrapping fails closed.** `UpdateTrust.publicKeyBase64` is empty. Both the update entry point and the signer reject it with a readable error. Running the built signer with `--check-trust` returned exit 1 and the expected unconfigured-key message. No fallback installs unsigned updates. A production public key and external private-key custody remain release prerequisites; configuring the key also requires fixing AUD-07. No Developer ID or notarization requirement is imposed by this review.

**SEC-02: transport policies are materially stronger.** Initial asset URLs are pinned to the repository and accepted filenames. HTTPS, standard port, no credentials, API isolation, redirect count, status, and streamed byte limits are enforced. Asset requests remove Authorization, and API redirects must return to the exact API URL. The native API download remains necessary; the eliminated native fetching is specifically the favicon path. Tests exercise URL predicates and mocked streaming, but do not simulate real redirect callbacks or verify headers at each hop.

**SEC-03: archive defenses are substantial but not complete.** `Sources/CArchive` contains ABI declarations, not a bespoke C decompressor. Swift drives system libarchive. Reader and file descriptors have deferred cleanup; data reads use a fixed 64 KiB buffer, checked lengths, and bounded accumulators. ZIP integer parsing is bytewise, avoiding unaligned integer loads. No concrete overflow, use-after-free, or normal-path descriptor leak was found in this bridge.

Absolute paths, `..`, empty components, backslashes, excessive depth, non-Yeoman roots, symlinks, hardlinks, and special files are rejected. `openat`, `O_NOFOLLOW`, exclusive temporary creation, and `renameat` protect extraction writes from ordinary archive-supplied link traversal. The central/local header cross-check also reduces parser disagreement and rejects unsupported ZIP64/encrypted/alternate-path formats. AUD-10 shows that the case-collision claim is broader than the actual check.

The defaults cap the archive at 128 MiB, entries at 10,000, per-file output at 128 MiB, and total output at 512 MiB. The 30-second check is cooperative: it does not interrupt a blocked libarchive call, and the preceding header-validation pass is outside that timer. Its overlap checks are quadratic in entry count. The entry cap bounds that work, but these are not hard CPU deadlines. The signed-before-extraction ordering substantially reduces remote reachability of arbitrary malformed archives.

Descriptor-relative extraction does not mean the entire update is descriptor-relative. Opening the archive by URL, verifying bundles by URL, and `FileManager` install moves reintroduce mutable path names. `O_NOFOLLOW` on a full path protects the final component, not every ancestor. AUD-04 and the explicitly acknowledged same-UID boundary remain relevant.

**SEC-04/05: the helper and recovery scheme improve safety, but tests do not establish crash consistency.** A bundled helper with a minimal environment replaces the temporary installation shell script. It checks the artifact and prepares same-volume staging before signaling readiness and waiting for the old process identity to disappear. `flock`, a preserved backup, rollback paths, and launch acknowledgment are useful safeguards.

The journal stores only the new version; it is not a complete transaction state machine. A failure followed by successful rollback can leave the new-version journal beside the restored old app. Directory moves are not individually followed by explicit directory durability barriers. Recovery deliberately refuses to overwrite a present target, including an invalid or non-launching new target. These cases require failure-injection and restart tests before claiming power-loss recovery. AUD-01 already demonstrates a normal version-changing path that the current simple file-move tests miss.

**SEC-06: Keychain failure handling is sensible within its scope.** Missing items are distinguished from access errors. Token migration removes defaults after successful Keychain storage; key creation refuses to replace missing keys when ciphertext already exists. There is no plaintext fallback file. Real login-Keychain ACL behavior, locked-keychain handling, and ad-hoc identity changes are untested. Tokens and key material still exist in ordinary Swift `String`/`Data` values while used; the code does not promise reliable explicit memory zeroization. The deprecation warnings for legacy Keychain access APIs are a maintenance issue, not proof that stored secrets are plaintext.

### 3.2 WebPanel and favicon — SEC-07 through SEC-12

**SEC-07/10:** inspection found no native favicon `URLSession` requests and no external Google/DuckDuckGo fallback. The favicon script runs in WebKit's client content world, accepts only HTTPS resources from the page's current origin, omits credentials, rejects redirects, and passes selected URLs as JavaScript arguments rather than interpolating executable source. Native code checks origin and limits again. Local/private hosts are not globally forbidden: a user-opened local origin can still use its normal WebKit networking. The test that rejects loopback uses an unrelated public page origin; it does not prove an IP-address denylist.

**SEC-08/09:** eight candidates, two active jobs, per-fetch byte bounds, a four-second fetch window, a six-second native result timeout, bounded decoding, and a bounded profile-specific cache are meaningful improvements. Two MiB is a per-candidate limit, not an aggregate eight-candidate limit. Base64 and bridge copies increase peak memory. Timeout invalidates result acceptance but cannot forcibly preempt ImageIO or WebKit. Normal UI calls are main-thread constrained with preconditions, although the class is not statically `@MainActor`. The tests do not execute the favicon script against hostile streaming pages. AUD-09 is a concrete compatibility regression.

**SEC-11:** `WKWebsiteDataStore(forIdentifier:)` is the intended persistent profile API. Separate stable identifiers provide separate website data stores; preview controllers use nonpersistent stores. WebKit documents this as the supported mechanism for separate persistent profiles, including cookie separation. [WebKit profile design](https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/).

The cookie test is substantive: it inserts cookies into two stores, deletes one, and verifies the other remains. It does not exercise localStorage, IndexedDB, service workers, disk cache, or persistence across process relaunch. Existing shared logins are intentionally not migrated, so reauthentication is an expected disclosed change. AUD-05, AUD-06, and AUD-08 remain unresolved.

The profile-removal wrapper additionally treats every `WKWebSiteDataStore` error with code 1 as benign “in use.” WebKit uses its generic unknown-error code for other removal failures too. The preceding `removeData` is a useful cleanup step, but a container-removal error should not be reported as success solely by that code. [WebKit removal implementation](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebsiteDataStore.mm).

**SEC-12:** standard web schemes and `about:blank` are allowed; local/script schemes are denied. `mailto` and `tel` dispatch require a link action. New-window handling accepts link-activated HTTP(S) navigation and reuses the existing view; automatic popups and element fullscreen are disabled. A native origin label is always shown. No registered JavaScript-to-native message-handler bridge was found. JavaScript dialogs are not explicitly implemented or tested. Restricting popup flows can break OAuth flows that depend on a separate window and opener relationship; that is a smoke-test requirement, not a demonstrated native privilege escalation.

### 3.3 Clipboard and persistence — SEC-13 through SEC-18

**SEC-13:** the capture path checks pasteboard generation before and after materialization, limits items/types, honors sensitive markers, and provides pause/application exclusions. It avoids eagerly constructing `NSImage` from the live pasteboard. These are useful controls, but the tests mostly exercise predicates rather than an actual hostile pasteboard provider. A promised pasteboard value may block or allocate before its size becomes known, as the implementation report acknowledges.

**SEC-14/15:** legacy image names must match the item's UUID. Secure file operations reject unexpected ownership, file type, multiple hardlinks, symlinks, and extended ACLs; data directories and files are tightened to 0700/0600. Atomic descriptor-relative writes prevent partial-file replacement in ordinary operation. These permissions do not exclude another process with the same UID. `cleanLegacy` is bounded by filename shape but does not prove the files belong to an authenticated completed migration; AUD-03 is the resulting loss scenario.

**SEC-16:** the requested `Crypto.swift` and `KeychainHelper.swift` functionality actually lives in `SecretStore.swift` and `EncryptedDocument.swift`. `RecordCipher` uses a 256-bit key and CryptoKit AES-GCM. It omits an explicit nonce, invoking random nonce generation; the combined format carries the nonce, ciphertext, and authentication tag. Additional authenticated data includes `Yeoman/v1/<record name>`, separating clipboard and widget documents. `AES.GCM.open` authenticates before returning plaintext. Apple's implementation documents a 12-byte default nonce and 16-byte tag. [Apple Swift Crypto AES-GCM implementation](https://github.com/apple/swift-crypto/blob/main/Sources/Crypto/AEADs/AES/GCM/AES-GCM.swift).

The existing tests reject modified ciphertext and incorrect associated data. An additional probe produced 1,000 distinct nonce prefixes for 1,000 encryptions of the same plaintext under one key. This is a sanity check, not a statistical proof of uniqueness. No deterministic nonce reuse or tag omission was found. Authentication does not prevent replay of an entire older valid encrypted document. There is no stored monotonic revision or key destruction on ordinary deletion, so the guarantees are integrity/confidentiality at rest, not rollback-proof or forensic secure deletion.

Missing keys or decryption errors block writes. Widget settings are encrypted as a whole document, so URLs are protected there; this does not imply that WebKit's own browser profile databases are encrypted by `RecordCipher`. AUD-02 undermines the clipboard's user-visible persistence choice even though the bytes are encrypted correctly.

**SEC-17/18:** text, encoded images, decoded pixels, history count, and total snapshot data have explicit limits. Serialization and encryption require temporary copies above the raw 70 MiB budget. New images are decoded through ImageIO metadata checks and constrained conversion. Mutation serialization, a committed snapshot for rollback, deletion generations, and coalesced writes improve consistency. However, count limits are not a substitute for migration provenance, and test success does not establish every delayed callback ordering. No cross-process persistence lock is provided; simultaneous application instances need an explicit policy or tests.

### 3.4 SystemStats, events, and limits — SEC-19 through SEC-22

**SEC-19:** stdout and stderr drain concurrently on background queues under a shared output limit. The process wrapper uses a timeout, termination escalation for its owned child, and a bounded wait for readers. The large-output and stderr tests execute real commands and are useful deadlock regressions. The `ps` caller uses a single-flight gate and a parser rejecting invalid/nonfinite numeric input. A daemonized descendant retaining a pipe can outlive the wrapper's reader wait; the API's documented non-daemonizing-child restriction is necessary.

**SEC-20:** the task-manager path does not blindly signal an arbitrary supplied PID. It requires a matching listed process identity, checks PID/UID/start time/name again using `libproc`, protects self and selected critical processes, and only removes the UI item after successful signaling. Tests inject recycled identities and denied signals rather than killing unrelated processes. The final identity-check-to-`kill` race remains. Passing the clicked row's captured identity directly into the provider would also be clearer than reselecting the current row by PID.

**SEC-21:** URL/string/widget count, view dimensions, zoom, scroll multiplier, and menu spacing now have bounds. CPU tick differences use wrapping subtraction for wrapping counters. Scroll multiplication uses reporting-overflow arithmetic and checks floating-point finiteness before changing the event. AUD-05 shows that “valid UUID syntax” is not sufficient validation for a downstream API.

**SEC-22:** the event mask selects only scroll-wheel events, and the callback checks event type again. Permission reconciliation, failed-tap creation handling, periodic checks, and explicit teardown improve lifecycle behavior. Pure state-machine tests are worthwhile but do not exercise a live event tap, actual TCC revocation, or resource teardown under real OS callbacks. No such permissions were changed during this review.

## 4. Test suite assessment

### Independently executed results

| Command / check | Result |
|---|---|
| `swift test` | Build succeeds; command exits 1 with “no tests found.” `YeomanTests` is an executable target, not a SwiftPM test target. |
| `swift run --scratch-path .build/audit-tests YeomanTests` | **58/58 pass**, exit 0. |
| `swift run --scratch-path .build/audit-tsan --sanitize thread YeomanTests` | **58/58 pass**, exit 0; no ThreadSanitizer diagnostic in captured output. |
| `.build/debug/YeomanReleaseSign --check-trust` | Expected exit 1: public key unconfigured. |
| `git diff --check` | Pass. |
| Additional isolated audit probes | Reproduced AUD-01–06, AUD-09, and AUD-10; nonce sanity check passed. AUD-07/08 are code-path findings. |

There are **58 tests across the entire runner, 46 in the security suites**. They are not all superficial. Actual crypto negative tests, filesystem permissions/link rejection, ZIP extraction, large-pipe output, two cookie stores, and real ad-hoc tampering provide useful evidence. The custom harness records failures and exits nonzero correctly.

The report nevertheless overstates parts of the evidence. The real signature fixture contains `Contents/MacOS/Yeoman` and `Info.plist`, not a nested `Contents/Helpers/YeomanInstaller`. It does not demonstrate nested-helper tamper detection. Installer rollback tests operate on simple files with injected verification closures; there is no successful real version-changing installer transaction, live handshake, or crash/restart recovery test. The timer test uses a zero-second limit, which proves a guard exists but not that expensive decompression can be interrupted.

### Required coverage additions

1. **Real update integration:** two differently versioned ad-hoc-signed app fixtures, a signed manifest using an injected test trust anchor, a nested installer helper, success/rollback/relaunch acknowledgment, and fresh metadata verification at the replaced path. Add a re-signed substitution negative test, not only unsigned byte tampering.
2. **Crash recovery:** stop after each journal write and move; restart recovery in a fresh process. Include failed rollback, target present but invalid, missing target, lock contention, ENOSPC, and cleanup failure.
3. **Privacy/migration:** explicit persistence opt-out across restart with leftover legacy directories; ciphertext plus independently changed legacy sources; conflicting IDs/images; cleanup interrupted after partial removal; valid oversized legacy records preserved without silent deletion. Test widget migration errors as well.
4. **WebKit:** zero/reserved identifiers; retained controllers after disposal; repeated cleanup; persistent store recreation across processes; localStorage/IndexedDB/cache separation; legacy default-store clearing and failed profile deletion.
5. **Favicon/image:** execute the script against oversized/chunked/slow responses and redirect attempts; test navigation during fetch, queue timeouts, valid multi-image ICOs, corrupted metadata, and maximum candidate aggregate memory.
6. **Archive:** component-level case aliases, normalization aliases, hardlinks, local/central header disagreement, overlapping records, unsupported extra fields, truncation/CRC corruption, resource limits with nontrivial work, and link/rename churn. Use fuzzing and appropriate memory sanitizers; TSan does not establish memory safety of the system libarchive binary.
7. **Secret/transport integration:** real disposable Keychain fixtures in a controlled environment, denial/lock/error cases, real redirect handling and Authorization stripping, and deterministic configured/unconfigured key tests.
8. **OS/UI:** controlled TCC revocation and event floods on a test account, clicked process identity through the UI, OAuth/login/popups, and macOS 14 smoke testing. The current run on macOS 26.5 is not evidence of runtime behavior across all supported OS versions.

Audit-only artifacts are in ignored build output: [.build/audit-repro.swift](.build/audit-repro.swift), [.build/audit-repro.log](.build/audit-repro.log), [.build/audit-zero-id.log](.build/audit-zero-id.log), [.build/audit-disposed.log](.build/audit-disposed.log), and [.build/audit-tsan.log](.build/audit-tsan.log). The reproducer links the already-built core objects and uses temporary directories, synthetic defaults, in-memory secret storage, and harmless signing fixtures. The two crash cases ran as separate processes. No installed app was replaced or launched by these probes.

## 5. Prioritized action plan

- [ ] **P0 — Restore reliable upgrades:** fix AUD-01 with fresh filesystem-backed metadata validation and add the real version-changing transaction regression before changing other updater behavior.
- [ ] **P0 — Preserve privacy and user data:** fix AUD-02/03 together using explicit consent and a migration journal identifying committed source data. Prove opt-out survives relaunch and unrelated legacy files survive cleanup.
- [ ] **P0 — Eliminate startup/teardown crashes:** reject invalid store IDs and make WebPanel disposal/callback handling idempotent and generation-aware (AUD-05/06).
- [ ] **P0 — Resolve the update trust boundary:** bind the installed content identity to the verified artifact (AUD-04), test local substitutions, and state precisely which arbitrary same-UID attacks remain outside the supported guarantee. Do not represent ad-hoc validity as publisher authentication.
- [ ] **P0 — Make configured releases testable:** decouple tests from the production trust constant (AUD-07), then install the intended public key. Keep the private key outside the repository and run configured-key packaging validation.
- [ ] **P1 — Complete browser-data deletion:** cover the legacy default store and orphaned profiles, and propagate generic removal failures instead of treating all code-1 errors as benign (AUD-08).
- [ ] **P1 — Close compatibility/parser gaps:** accept bounded multi-representation icons and reject component-level archive aliases (AUD-09/10).
- [ ] **P1 — Exercise failure recovery:** add transaction crash tests and confirm journal/rename durability, rollback behavior, helper verification, and launch acknowledgment under real bundle fixtures.
- [ ] **Release acceptance:** rerun the expanded normal and sanitizer suites; perform Keychain, OAuth, clipboard migration, TCC, macOS 14, and disposable full-update smoke tests. Review the resulting evidence before tagging. The current 58/58 results alone do not meet that acceptance bar.
