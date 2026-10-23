# Security Policy

## Supported Versions

| Version | Supported          |
| :------ | :----------------- |
| 0.2.x   | :white_check_mark: |
| < 0.2.0 | :x:                |

## Reporting a Vulnerability

We take the security of Yeoman seriously. If you discover a security vulnerability or potential exploit, please do **not** disclose it publicly via GitHub Issues.

Instead, please report it directly through GitHub's Private Vulnerability Reporting or by contacting the maintainer directly.

Please include:
- A detailed description of the vulnerability.
- Steps or a proof-of-concept to reproduce the behavior.
- Affected component(s) and macOS version(s).

You will receive an initial response within 48 hours acknowledging receipt, followed by periodic updates until a fix is released.

## Security Architecture & Threat Model

Yeoman implements strict defensive engineering standards as detailed in [`AGENTS.md`](./AGENTS.md):

1. **Posix Sandboxing & Safe Path Resolution**: Application-owned mutable paths are handled descriptor-relatively (`openat`, `fstat`, `O_NOFOLLOW`) inside `0700` directories with `0600` files. Path traversal, symlink attacks, and link race conditions are rejected by design.
2. **Encrypted Persistence**: Secrets and sensitive state are sealed with CryptoKit AES-GCM using unique 96-bit nonces and record-specific associated authenticated data (AAD).
3. **Ad-Hoc Publisher Authenticity**: Updates are verified against a pinned Ed25519 public key and cryptographic manifest before payload extraction.
4. **WebKit Isolation**: Embedded web panel instances run in isolated website data stores without custom privileged URL schemes or native bridge access.
5. **Continuous Verification**: Security invariants and mitigations are continuously guarded by automated regression tests in [`Tests/SecurityTests.swift`](./Tests/SecurityTests.swift).

## Historical Security Audits

Yeoman has undergone thorough internal security reviews and remediation cycles during its development. **All findings documented in these reports were resolved and regression-tested prior to release:**

- [Security Audit v0.2.1](./docs/security/SECURITY_AUDIT_V0.2.1.md) — Comprehensive review of updater, persistence, and isolation mechanics.
- [Security Review](./docs/security/SECURITY_REVIEW.md) — Initial adversarial vulnerability assessment.
- [Security Re-Review](./docs/security/SECURITY_REREVIEW.md) — Verification of mitigations and descriptor-relative operations.
- [Security Implementation Report](./docs/security/SECURITY_IMPLEMENTATION_REPORT.md) — Detailed mapping of findings to automated regression tests (`YEA-01` through `YEA-06`).
