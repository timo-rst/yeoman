# Independent adversarial audit of Yeoman v0.2.1

Date: 23 October 2026. Target: `e307ace1170ccb455839690c7f48c4a209cdaa5d`. HEAD and the peeled annotated tag `v0.2.1` both match this commit. The tracked tree was clean at audit start. Baseline comparison: `c3c8e7535c48bd93be6525052aea33ef177d6c72`.

**Verdict: changes required before security approval.** Four concrete defects were reproduced, including an installer authenticity failure and a persistent WebKit crash vector. The previous “APPROVED WITH CONCERNS” conclusion and claim that no source remediation remains are not supported by the current implementation. No remote signature forgery, privilege escalation, native remote-code execution, or C memory-corruption exploit was demonstrated. The installer attack requires same-UID filesystem access; its severity is Medium, not a claim of a new privilege boundary being crossed.

The requested product decisions are respected: ad-hoc signing is acceptable; file-backed secrets and their same-UID confidentiality limitation are accepted; the release private key was neither displayed, copied, rotated, nor changed. Same-UID filesystem integrity and denial-of-service defects remain in scope. Application source, configuration, tags, installed application, and existing release artifacts were not changed. This report and disposable build/probe artifacts are the audit outputs.

## Findings

| ID | Severity | Finding | Evidence |
|---|---|---|---|
| YEA-01 | Medium | Installer accepts an unauthenticated replacement after successful signed-archive preflight | Reproduced through the actual `UpdateInstaller.install` implementation using the real release ZIP and signed manifest |
| YEA-02 | Medium | UUID `00000000-0000-0000-0000-000000000001` passes validation and crashes WebKit | Reproduced in a separate process: uncaught `NSInvalidArgumentException` |
| YEA-03 | Medium | Secret-store root opening follows symlinks in ancestor directories | Reproduced with a redirected `Yeoman/.secrets` path |
| YEA-04 | Low | Legacy cleanup deletes UUID-named image files never imported into the encrypted snapshot | Reproduced using an unreferenced synthetic image file |
| YEA-05 | Low | Claimed CI gate is not an executable GitHub Actions workflow | Repository/configuration evidence; no `.github/workflows` directory |
| YEA-06 | Low | WebKit container-removal errors are silently converted to success | Code-proven; no surviving private browser data demonstrated |

### YEA-01 — authenticated archive identity is lost before replacement

Locations: `Sources/Yeoman/Core/Security/InstallTransaction.swift:74–102`, especially line 90 and line 17; `Sources/Yeoman/Core/Security/UpdateSecurity.swift:154–192`; `Sources/YeomanInstaller/main.swift:19`.

The helper verifies the signed manifest and archive hash, writes the archive to a mutable pathname, extracts it, and verifies the staged bundle. It **discards** the identity returned by this first bundle verification. After signaling readiness and waiting for the old process, `InstallTransaction.replace` reads the staging path again and adopts whatever valid bundle is there as the expected identity. Matching bundle ID/version plus a valid new ad-hoc signature suffice at this point.

Reproduction used a disposable signed 0.2.0 target, the unmodified 0.2.1 release ZIP and manifest, and a separately ad-hoc-signed 0.2.1 fixture containing a harmless system executable and a different resource. The `ready` callback substituted the extracted directory at the precise preflight/wait boundary. The actual installer then completed successfully:

```text
Release manifest valid: 0.2.1 3425184 926951d69a9ccfc921312d4d47d2555dcb5783b5e45074cae0672ff887c99cca
Installer accepted substitute: true differs from authenticated extracted bundle: true
Installed marker: UNAUTHENTICATED REPLACEMENT
Acknowledgment success
```

No signing-key forgery or alteration was needed. The callback deterministically models a same-UID filesystem substitution during the real helper's readiness/wait interval. The test did not run the GUI updater, kill the installed application, or launch the replacement fixture. It demonstrates the full installation function, not just an injected permissive transaction verifier.

The existing AUD-04 tests substitute a bundle **after** `replace` captures its baseline. They correctly reject that later substitution but miss this earlier window. Acknowledgment only checks the version and current ad-hoc validity and consequently also accepted this fixture and removed its disposable backup.

Remediation: derive the expected installed content identity from the authenticated archive and carry it explicitly through preflight, replacement, acknowledgment, and launch checks. Hash and extract the same authenticated byte source; a path reopen after writing `archive.zip` introduces an additional substitution window. Use descriptor-relative operations for mutable installation paths and preserve authenticated identity in the recovery record. Merely saving the line-90 result fixes the demonstrated timing window but does not by itself prove that earlier extraction consumed the authenticated bytes. Add substitutions before extraction, before readiness, during the wait, and after rename to the integration tests. Do not claim complete isolation from arbitrary same-UID mutation.

### YEA-02 — WebKit reserves more than the zero UUID

Locations: `Sources/Yeoman/Core/Security/SecurityPolicy.swift:41–45`; `Sources/Yeoman/Modules/WebPanel/WidgetStorage.swift:14–32,44–49`; `Sources/Yeoman/Modules/WebPanel/WebPanelView.swift:43–46`.

`isValidWebKitIdentifier` accepts every UUID containing a nonzero byte. The following identifier therefore passes both widget decoding and the controller's data-store guard:

```text
00000000-0000-0000-0000-000000000001
```

The isolated runtime probe printed:

```text
Yeoman UUID validator accepts: true
WidgetStorage preserves UUID: true
*** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason:
'Identifier (00000000-0000-0000-0000-000000000001) is invalid for data store'
```

A legacy widget record can supply this value. `WidgetStorage.load` persists unencrypted legacy configuration before exposing it; because this identifier is not repaired, the resulting encrypted record can cause repeated startup crashes when the enabled widget is constructed. Same-UID configuration manipulation is sufficient; a web page alone was not shown to control widget IDs. The all-zero repair works, but its generalization to “valid WebKit identifier” is incomplete.

WebKit's UUID implementation reserves both empty and deleted sentinel values, and its data-store API rejects invalid identifiers. The installed macOS runtime independently confirmed the failure; upstream source is explanatory evidence, not a substitute for that run. [WebKit UUID implementation](https://github.com/WebKit/WebKit/blob/main/Source/WTF/wtf/UUID.h), [data-store implementation](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebsiteDataStore.mm).

Remediation: reject/repair both reserved identifiers before persistent storage and at every data-store creation/deletion entry point. Persist repaired IDs before returning them, as the zero-ID migration already does. Add a separate-process crash regression and an encrypted reload test for the second reserved value.

### YEA-03 — ancestor symlinks bypass secret-directory validation

Locations: `Sources/Yeoman/Core/Security/SecureDirectory.swift:8–15`; `Sources/Yeoman/Core/Security/SecretStore.swift:104–128`.

The secret store opens `Yeoman/.secrets` as one pathname. `O_NOFOLLOW` protects its final component, not an intermediate `Yeoman` directory. Ownership/type/ACL checks apply to the opened leaf directory and cannot establish that its ancestors were safe. Other components opening `Yeoman` separately do not bind the secret store to their validated descriptors.

The disposable probe created `Yeoman` as a symlink to a separate directory, then used the unmodified `SecureFileSecretStore` API:

```text
Ancestor symlink followed and secret readable: true
Redirected secret directory exists: true
```

The store wrote and read a synthetic token in the redirected location. This is a failure of the specified no-symlink/directory-substitution property. It is **not** reported as new same-UID secret disclosure: that confidentiality limitation is accepted. Integrity, wrong-location writes/deletes, and denial of service remain relevant.

Remediation: open a trusted application-support root, validate the relevant path components, and derive `Yeoman` and `.secrets` using retained directory descriptors and `child`. Avoid independently reopening the same logical root through mutable absolute paths. Add ancestor-link and concurrent parent-replacement tests; keep the existing leaf-link, ACL, hardlink, and FIFO checks.

### YEA-04 — migration cleanup has no per-file provenance

Locations: `Sources/Yeoman/Modules/Clipboard/ClipboardHistoryStore.swift:243–287`, particularly the enumeration and unlink at lines 276–281.

Migration tracks source directories, not the exact imported image files. Cleanup deletes every filename shaped like a generated UUID PNG or recognized thumbnail, even when the imported JSON contains no reference to it. A successful encrypted commit does not establish that those additional files were imported.

The probe migrated a text-only history alongside an unrelated UUID-named file in `clipboard_images`. It observed `Unimported UUID image deleted: true`. The fixture contained synthetic bytes; this proves unauthorized cleanup by filename pattern, not loss of a specific real user photograph. A partially restored legacy directory or orphaned image is a realistic data-preservation case. Separately, line 261 skips comparing legacy image bytes when an encrypted image with the same item ID already exists; conflicting image content deserves a regression test.

Remediation: record exact source filenames and content identities included in a committed migration. Delete only those sources and their proven derivatives; preserve or quarantine unrecognized/conflicting files. Ordinary text-item merging from AUD-03 is fixed, but the broader provenance guarantee is not.

### YEA-05 — release validation is not wired into CI

Locations: `Scripts/ci.yml:1–35`; `Scripts/package_release.sh:30–31`.

The only tracked workflow-shaped YAML is under `Scripts/ci.yml`. GitHub Actions discovers workflows under `.github/workflows`; the repository contains none. Thus the reports' statement that the supported harness “is used by project CI,” and instruction to run the “existing CI job” on macOS 14, overstate what this checkout supplies. [GitHub workflow discovery](https://docs.github.com/en/actions/concepts/workflows-and-actions/workflows).

Moving the YAML alone is insufficient: its packaging step requires `YEOMAN_UPDATE_PRIVATE_KEY_FILE`, but the workflow supplies no external key, and its upload list omits `Yeoman.update.json`. No private key should be made available to untrusted pull-request builds.

Remediation: install a test/build workflow in the correct location, separate ordinary builds from authorized release signing, and publish the signed manifest with the ZIP. Pin action revisions and specify minimum permissions as release-process hardening. This is a verification gap, not an demonstrated account compromise.

### YEA-06 — generic WebKit failures are treated as successful deletion

Location: `Sources/Yeoman/Modules/WebPanel/WebPanelView.swift:320–338`.

After retries, every error with domain `WKWebSiteDataStore` and code 1 is converted to `nil` on the assumption that it means an in-use empty container. WebKit maps generic removal failures to this unknown-error code; it does not uniquely establish the assumed condition. [WebKit removal error mapping](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebsiteDataStore.mm).

The preceding `removeData` operation is real and useful; this finding does not demonstrate that cookies or other sensitive contents survived. The defect is suppressed cleanup failures and unsupported success reporting. The original review already identified this concern, and it remains in the current source.

Remediation: propagate the error or report content purge and container removal as separate outcomes. Test generic failures explicitly. Full-data clearing now includes default and orphaned stores, but does not stop live pages or await all removals in a coordinated operation; test repopulation and completion semantics separately.

## Verification and release artifacts

Runtime: macOS 26.5 build 25F71, arm64; Apple Swift 6.3.3. macOS 14 and Intel runtime behavior were not exercised.

| Check | Result |
|---|---|
| `swift run YeomanTests` | 70/70 passed |
| `swift run --scratch-path .build/adversarial-audit/tsan --sanitize thread YeomanTests` | 70/70 passed; no ThreadSanitizer diagnostics; legacy Keychain deprecation warnings |
| Fresh `swift build -c release --scratch-path .build/adversarial-audit/release` | Passed |
| Shell syntax checks for build/packaging scripts | Passed |
| `codesign --verify --deep --strict dist/Yeoman.app` | Passed; ad-hoc signature with hardened-runtime flag |
| Existing ZIP manifest | Ed25519 signature, product, version 0.2.1, size 3,425,184, and SHA-256 verified against source trust anchor |
| ZIP application files | All five regular files match the existing `dist/Yeoman.app` byte-for-byte |
| DMG contents | Mounted read-only; application files match `dist/Yeoman.app`; strict signature check passed; Applications link points to `/Applications`; detached afterward |
| External key metadata | Current user UID 501, regular file, one link, mode 0600; no extended ACL displayed |
| Freshly built release signer | `--check-trust` and signing an audit-output manifest succeeded, confirming the external key matches the embedded public key |
| Screenshot script typecheck | Fails: inaccessible setters for `widgets`, `items`, and `currentSpacing` |

ZIP SHA-256: `926951d69a9ccfc921312d4d47d2555dcb5783b5e45074cae0672ff887c99cca`.

DMG SHA-256: `9da8579d1b27941b788548a6b7b0841839f6a47de7becfb1ebd541bf05ddf290`.

Both shipped executables are thin arm64 Mach-O files. The README advertises Apple Silicon and Intel without distinguishing source compatibility from the downloadable binary. Build scripts use the host architecture and provide no universal-binary assembly. Correct the distribution claim or supply validated Intel/universal artifacts.

An unauthenticated request to GitHub's release-tag API returned HTTP 404. This may indicate a private repository or unavailable release; it does not establish which. Remote published assets were therefore not verified. The artifact results above concern the local `dist` files. A fresh source build was verified, but reproducible binary equivalence between that build and the packaged artifacts was not established. Packaging was inspected rather than rerun over the existing release files.

## Complete-application coverage and security properties

The review inventoried all 77 tracked files and covered all application modules, UI entry points, security primitives, helper/signer executables, C bridge, executable tests, scripts, and release resources. Security-relevant data flow and OS interactions received detailed inspection; static assets and layout code are not claimed to have undergone exhaustive fuzzing.

| Area | Verified implementation and remaining limits |
|---|---|
| Updates and transport | Exact Ed25519 payload verification precedes metadata use; product, increasing version, archive name/size/hash are checked. API and asset origins are separated, asset Authorization is removed, redirects/status/streamed bytes are bounded. No unsigned fallback found. YEA-01 breaks the later archive-to-install binding. Signed freshness/expiry and highest-ever-version retention are absent; this is not a signature forgery. |
| Archive/C ABI | CArchive is an ABI declaration shim for system libarchive, not a custom C decompressor. Fixed buffers, deferred descriptor/reader cleanup, path/type/link checks, ZIP header agreement, byte/count/depth limits and descriptor-relative output are present. The release ZIP extracted successfully in the installer probe. Header validation is outside the cooperative extraction timer and has quadratic region-overlap checks. No memory-corruption exploit demonstrated; TSan does not establish system-libarchive memory safety. ABI declarations were compared with upstream headers. [libarchive headers](https://github.com/libarchive/libarchive/blob/master/libarchive/archive.h). |
| Secrets and crypto | File store is the actual default; Keychain implementation remains optional/dead for defaults. SHA-256 account filenames distinguish `a.b` and `a_b`; known v0.2.0 names migrate after destination write. Leaf ownership/type/link/ACL checks and 0700/0600 modes work in tests. AES-GCM uses random nonces and record-bound associated data. Missing keys and authentication failures block writes without overwriting ciphertext. YEA-03 concerns ancestor binding. Same-UID confidentiality, snapshot rollback resistance, and physical secure erasure are not promised. |
| Clipboard | Generation checks surround materialization; sensitive markers, pause/exclusions, input quotas, two image operations, bounded ImageIO conversion, serialized persistence, and deletion generations are present. First promised-value materialization can still allocate/block before a size check. Explicit persistence opt-out now wins over old directory presence. YEA-04 limits the migration cleanup claim. No hostile live pasteboard provider was exercised. |
| WebPanel/favicon | Persistent widget UUIDs isolate WebKit stores; previews use nonpersistent storage. Cookie isolation/deletion was exercised by the harness. No native favicon URLSession path, third-party fallback, or script-message native bridge found. Favicon fetch runs in an isolated client world, requires same HTTPS origin, omits credentials, rejects redirects and bounds candidates/bytes/decoding. Normal HTTP(S) navigation remains automatic; external mailto/tel dispatch is link-gated. Origin UI and fullscreen/popup restrictions exist. YEA-02 and YEA-06 remain. |
| System stats/processes | BoundedProcess drains both pipes, limits aggregate output and child lifetime; actual subprocess tests pass. Task-manager termination rechecks PID/UID/start time/name, excludes self/protected names and uses exact PID conversion. A residual check-to-kill race remains. The UI passes a PID and the provider reselects the current row, rather than passing the displayed captured identity directly. No unrelated process was signaled during this audit. |
| Menu bar/spacing | Fixed executable paths and argument arrays avoid shell interpolation; numeric settings are clamped. ControlCenter restart still uses name-based `killall`; the scanner terminates apps by bundle identifier. These are outside the task manager's TerminationPolicy, so “single signal pathway” is not an application-wide property. Scanner plist reads lack explicit byte limits; a targeted FIFO test returned immediately on this host, so no FIFO-hang finding is asserted. AppKit private-selector swizzling remains a compatibility risk, not a demonstrated exploit. |
| Scroll/event handling | Scroll-only mask, event-type guard, overflow-safe multiplication, TCC reconciliation and teardown are present. Pure state-machine tests pass. Actual TCC revocation, live tap stress and physical hardware were not exercised or changed. Tooltip mouse/scroll monitors are local AppKit monitors, not an additional global keyboard tap. |
| App/UI/scripts | Startup, module lifecycle, settings actions, external-open sinks, persistence bindings and localization claims were inspected. No arbitrary script execution from webpage data found. Screenshot tooling is stale and would also need synthetic stores before being repaired to run safely. Icon generation uses predictable `/tmp/Yeoman.iconset` and ordinary path writes; replace with a private unique temporary directory. These tools were not run against user data. |

Installer rollback tests cover handled failures, not crash consistency. The version-only journal has no authenticated old/new content identity or complete phase state, and rename durability is not explicitly synchronized. Recovery refuses to replace an already-present broken app. Do not advertise verified power-loss or nonlaunching-target recovery without process/crash/failure-injection tests.

## Historical-report reconciliation

`SECURITY_REVIEW.md` is correctly labeled historical. Its original snapshot included untracked implementation files, so baseline commit `c3c8e75` alone cannot recreate that entire reviewed state. Its empty-key, Keychain-default, 58-test and old line-number claims must not be read as current facts. It already noted several unresolved broader concerns later approval text omits.

| Prior claim | Current assessment |
|---|---|
| AUD-01 fresh version reading | Fixed for ordinary replacement; real signed transaction regression passes. “Bounded fresh read” is not fully race-resistant: plist size is checked by pathname before `Data(contentsOf:)`; executable reads also lack an independent byte cap. |
| AUD-02 persistence opt-out | Demonstrated directory-presence bug fixed. Existing test asserts the initial published value without pumping the publish callback; inspecting stored preferences and a subsequent capture would strengthen it. |
| AUD-03 migration data loss resolved | Text-source merge improved; cleanup provenance remains incomplete (YEA-04). |
| AUD-04 installer substitution resolved | Later transaction substitution rejected, but preflight-to-transaction substitution succeeds (YEA-01). |
| AUD-05 / RR-01 invalid UUID repair | Zero UUID repaired and persisted; second WebKit sentinel still crashes (YEA-02). |
| AUD-06 delayed disposal crash | Demonstrated vector fixed; retained-controller timer regression passes. |
| AUD-07 configured-key packaging tests | Fixed: parser tests use injected empty/malformed/valid data independently of configured production key. |
| AUD-08 legacy/default-store cleanup | Default and enumerated orphan stores are included. Generic deletion errors still suppressed; completion/repopulation guarantees untested. |
| AUD-09 ICO support | Decoder now accepts 1–32 frames and selects a bounded frame. Test named “multi-frame ICO” actually generates TIFF, so that test is not direct ICO-format evidence. |
| AUD-10 implicit case aliases | Explicit intermediate-directory casing check added in both parsers; regression passes. Comprehensive filesystem normalization/fuzz coverage is not established. |
| RR-02 secret account collisions | Fixed mapping and known-name migration verified by tests and v0.2.0 source comparison. |
| RR-03 mandatory code-directory hash | Implemented; signed-resource changes alter identity and are rejected by the transaction test. Does not resolve YEA-01. |
| RR-04 documentation contradictions resolved | Only partly true; current README and broader security-report assertions remain inaccurate. |

Specific unsupported or misleading statements:

- `SECURITY_IMPLEMENTATION_REPORT.md` SEC-04 excludes arbitrary same-UID helper attacks. That is broader than the accepted confidentiality exception and cannot dismiss YEA-01.
- SEC-04 says helper integrity is verified “in test suite”; the signed fixtures do not contain a nested installer. This audit verified the actual release bundle's nested signature, but did not inject helper tampering into the harness.
- SEC-12 says navigation is allowed only on explicit link click. The delegate allows normal HTTP(S) actions regardless of navigation type; only external dispatch and new-window handling are link-gated. The viewport/visibility scripts also execute in the page world, while favicon fetching uses the isolated client world. No injected untrusted native executable source was found.
- SEC-19's single-flight property applies to process sampling, not all spacing/defaults operations. SEC-20's single signaling pathway applies to the task manager, not the whole app.
- The re-review's references to storage isolation are stronger than the tests: cookies were tested; IndexedDB, service workers, cross-process persistence and complete browser-data erasure were not.
- README “Networking: Local only” conflicts with default-enabled update checks and WebKit page traffic. No telemetry code was found, but that narrower observation does not make the app offline.
- README plaintext JSON/PNG storage is obsolete for normal persistent clipboard data. The README omits the file-backed key/same-UID limitation and does not explain how ad-hoc integrity differs from publisher identity. Its quarantine-removal instruction is not an authenticity check; explain initial-download trust separately from the signed updater.
- README claims closed-panel timers are halted; code throttles scheduling, suspends media, signals page visibility and removes caches. It does not terminate all page execution. The UI's password-exclusion wording should describe best-effort markers/heuristics, not guaranteed recognition of every secret.

## Required follow-up and evidence

Before security approval, fix YEA-01–03 and add integration tests for the demonstrated boundaries. Correct migration provenance and CI wiring, propagate cleanup errors, and update the contradictory claims. Run the existing harness plus those regressions on macOS 14 and the intended release architectures. Retain the chosen ad-hoc/file-secret design; neither Developer ID nor switching to Login Keychain is required by these findings.

Audit evidence is under `.build/adversarial-audit/`: `probes.swift` / `probes.log`, `uuid-probe.swift` / `uuid-one.log`, `tests.log`, `tsan.log`, `release-build.log`, `screenshot-typecheck.log`, and `tracked-file-inventory.json`. The standalone probes link the current normal-build YeomanCore object files and use temporary directories, synthetic defaults, harmless signed bundles, and no production secret data. Normal and TSan runs demonstrate tested paths, not proof that no other flaws exist.
