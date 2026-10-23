# Yeoman security remediation re-review (historical)

> Superseded by `SECURITY_AUDIT_V0.2.1.md`. Its YEA-01 through YEA-06 findings identified gaps in the v0.2.1 approval below; the v0.2.2 implementation report tracks their remediation. Preserve this document as review history, not as the current release verdict.

Review date: 23 October 2026. Baseline: `c3c8e7535c48bd93be6525052aea33ef177d6c72`. Reviewed release: `v0.2.0` plus the v0.2.1 remediation in the commit containing this report. The implementation report was checked against code, probes, tests, built application bundles, and release tooling.

The project owner explicitly chose file-backed secrets because an ad-hoc signed application downloaded from the Internet should not request access to the macOS login Keychain. This is treated as an accepted product trust boundary. The design does not promise confidentiality against a malicious process running as the same user: such a process can read both `.secrets` and encrypted application data. No Keychain-to-file migration is required because the intermediate Keychain-backed build was not the tagged release; v0.2.1 does migrate keys written by the v0.2.0 file store.

Runtime verification used macOS 26.5, arm64, and Apple Swift 6.3.3. macOS 14 compatibility was inspected against the deployment target and SDK declarations but was not exercised on a macOS 14 host.

## 1. Executive verdict

**Overall rating: APPROVED WITH CONCERNS.**

The current implementation is substantially safer than the baseline. Signed update metadata is pinned to a configured Ed25519 key and binds the archive digest, size, version, and product identity. Archive extraction uses descriptor-relative operations with path, type, collision, entry-count, byte, and time limits. The installer binds staged and installed bundles to fresh metadata, the signed executable digest, and a mandatory code-directory hash. Native favicon networking is removed, WebKit profiles are separated, persistent clipboard and widget documents use AES-GCM, process termination binds PID, UID, and start time, and event/clipboard limits are enforced.

All findings `AUD-01` through `AUD-10` and follow-up findings `RR-01` through `RR-04` have been remediated for their demonstrated vectors. The remaining concerns are explicit operational boundaries: same-UID confidentiality is out of scope for the chosen file secret store, and macOS 14 runtime behavior has not been exercised in this environment.

**Security posture delta:** high-risk update, archive, clipboard-migration, WebKit-crash, and installer-integrity weaknesses from the first review have been removed or materially reduced. No remaining exploitable Critical, High, or Medium finding was demonstrated.

**Architectural elegance and maintainability: 8/10.** Shared bounded-I/O and cryptographic primitives, injected secret stores, fresh bundle metadata reads, mandatory bundle identity, lifecycle generations, migration-before-exposure, and descriptor-relative archive work form a coherent design. Remaining complexity is concentrated in the handwritten ZIP pre-parser, asynchronous WebKit cleanup, and the custom executable test harness.

## 2. Findings matrix

No open vulnerability or functional regression with Critical, High, Medium, or Low severity was demonstrated after remediation.

| Remediation | Previous severity | Result | Verification |
|---|---:|---|---|
| RR-01: repaired widget UUID was not persisted | Medium | Repaired identifiers are written atomically before load succeeds, so the same persistent WebKit profile is selected after restart. Full-data clearing enumerates every application-owned persistent store, including orphaned identifiers. | An encrypted zero-UUID document was loaded twice; the non-zero identifier was stable and present in the committed ciphertext. |
| RR-02: secret account filename collisions | Low | New filenames use a versioned SHA-256 mapping of the exact UTF-8 account name. Reads migrate the three known v0.2.0 names only after the new file is committed. | `a.b` and `a_b` retain independent values; a legacy `github-token.key` migrates and is removed. |
| RR-03: optional code-directory identity | Low | `BundleVerifier` now requires a non-empty `kSecCodeInfoUnique` value and fails closed when signing identity cannot be read. | Separately signed bundles with identical metadata and source executable but different resources produce different identities; substitution rolls back. |
| RR-04: contradictory release documentation | Low | The implementation report now documents the file store, same-UID boundary, first-bounded-frame behavior, current test count, external signing requirement, and the historical status of the original rejection. | Manual comparison of reports, source, test output, and built v0.2.1 bundle. |

### Accepted risk: file-backed secrets

`SecureFileSecretStore` uses `SecureDirectory` ownership, type, ACL, link-count, `0700` directory, `0600` file, descriptor-relative access, and atomic-write checks. This protects against other local user accounts and accidental disclosure. AES-GCM documents remain authenticated and reject tampering without the key.

It does not protect secrets from a malicious same-UID process. Clipboard and widget keys and the GitHub token are files available to that process, so AES-GCM does not provide same-UID confidentiality. The GitHub token is stored directly in a permission-restricted file. This accurately implements the owner's decision to avoid Keychain authorization prompts and must remain visible in product documentation.

## 3. Deep-dive analysis

### 3.1 Updater and CArchive (`SEC-01` to `SEC-06`)

The Ed25519 public key is configured and invalid or missing keys fail closed. Metadata verification occurs before extraction and binds product identifier, semantic version, archive filename, exact byte count, and SHA-256. Downgrades and malformed versions are rejected. URL policy restricts initial, API, asset, redirect, and authorization origins.

`BundleVerifier` reads bounded `Info.plist` bytes directly, avoiding Foundation bundle caching. It validates the bundle ID/version, strict static signature including nested code, main executable digest, and mandatory code-directory hash. `InstallTransaction` compares the identity before and after replacement and rolls back differences. Ad-hoc signing remains an integrity mechanism rather than Apple publisher identity, while publisher authenticity comes from the Ed25519 manifest.

The archive layer rejects traversal, absolute paths, links, devices, FIFOs, aliases, case collisions including implicit parents, excessive entries, excessive bytes, and overlong extraction. Writes are descriptor-relative. Time limits are evaluated between archive calls and cannot interrupt one blocking C/kernel operation.

The GitHub token uses the chosen file store. UserDefaults migration validates and commits the destination before deleting plaintext. File-store names are collision-resistant and migrate known v0.2.0 accounts without creating a generic ambiguous legacy namespace.

### 3.2 WebPanel and favicon (`SEC-07` to `SEC-12`)

Favicon requests execute inside the existing `WKWebView`, require HTTPS and exact same origin, omit credentials, reject redirects, and enforce candidate, time, byte, pixel, frame, concurrency, and cache limits. No native `URLSession` favicon path remains. Multi-frame images are bounded to 32 frames and the first representation satisfying the pixel limit is decoded into a bounded thumbnail.

Valid stable UUIDs select persistent per-widget stores, while preview or invalid identifiers use non-persistent storage. Invalid legacy UUIDs are repaired and committed before returning. Delayed controller callbacks are invalidated on disposal. Full-data clearing enumerates all persistent WebKit profile identifiers and also clears the legacy default store.

### 3.3 Clipboard and persistence (`SEC-13` to `SEC-18`)

Clipboard capture enforces item, type, text, image, history, and total-document limits, checks `changeCount` around materialization, carries tracking markers, and bounds image work. AES-GCM uses CryptoKit-generated nonces and record-specific associated data; opening validates the authentication tag. No nonce reuse mechanism or unauthenticated fallback was found.

Persistence distinguishes a missing preference from explicit opt-out. Legacy records merge into an existing encrypted snapshot, and source cleanup follows a committed write. Missing keys fail closed without replacing ciphertext. Filesystem helpers validate ownership, type, links, permissions, and ACL state and use atomic writes.

### 3.4 System statistics, events, and limits (`SEC-19` to `SEC-22`)

Process collection drains stdout and stderr concurrently, caps aggregate output, enforces deadlines, and parses numeric fields losslessly. Termination converts PID exactly and revalidates PID, UID, and start time immediately before signaling while excluding self/system processes. Darwin has no atomic check-and-signal primitive, leaving the documented narrow kernel race.

Scroll multiplication uses overflow-reporting arithmetic, numeric preferences reject non-finite/extreme values, and the event tap accepts only scroll-wheel events. State transitions and permission loss have unit coverage. Real TCC reset and high-rate physical hardware input were not exercised.

## 4. Test-suite assessment

The executable `YeomanTests` harness contains **70 tests**. Normal and ThreadSanitizer executions passed:

- `swift run --scratch-path .build/v021-run YeomanTests`: 70/70 passed.
- `swift run --scratch-path .build/v021-tsan --sanitize thread YeomanTests`: 70/70 passed with no ThreadSanitizer diagnostics.
- `./Scripts/build_app.sh development`: passed.
- `./Scripts/build_app.sh release`: passed; bundle version is 0.2.1.
- `codesign --verify --deep --strict dist/Yeoman.app`: passed.
- `.build/release/YeomanReleaseSign --check-trust`: passed.
- `Scripts/package_release.sh`: passed with the external `0600` key; the v0.2.1 Ed25519 manifest and ZIP digest verified independently.
- `git diff --check`: passed.

`swift test` cannot run tests with the installed Command Line Tools because neither XCTest nor Swift Testing is exposed to SwiftPM. A proposed test-target conversion was therefore removed instead of committing a platform-specific package configuration. `swift run YeomanTests` remains the supported command and is used by project CI.

The suite contains negative tests for signatures, keys, downgrades, archive digests and paths, links and special files, quotas, URL policy, ciphertext tampering, migration ordering, image limits, process identity, numeric bounds, secret-name collisions, persistent UUID repair, delayed WebPanel disposal, and signed-resource substitution. Remaining environment coverage gaps are a real macOS 14 run and real TCC revocation.

## 5. Prioritized action plan

1. Run the existing CI job on a macOS 14 host to cover the minimum supported runtime.
2. Publish v0.2.1 as the maintenance replacement for v0.2.0 and preserve the accepted same-UID secret-store boundary in release documentation.

No source-level security remediation remains open from this review. The release artifacts and signed manifest are complete; minimum-OS execution remains an environment coverage concern.
