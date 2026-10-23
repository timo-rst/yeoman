# Yeoman Documentation

Welcome to the Yeoman documentation directory. This folder contains architectural records, design guidelines, and historical security audits.

## Contents

- [Security Policy & Vulnerability Reporting](../SECURITY.md) — Responsible disclosure guidelines, support matrix, and architectural security standards.
- [Security Audits & Reports](security/) — Historical security evaluations and audit reports:
  - [Security Audit v0.2.1](security/SECURITY_AUDIT_V0.2.1.md) — Comprehensive review of updater, persistence, and isolation mechanics.
  - [Security Implementation Report](security/SECURITY_IMPLEMENTATION_REPORT.md) — Detailed mapping of findings to automated regression tests (`YEA-01` through `YEA-06`).
  - [Security Review](security/SECURITY_REVIEW.md) — Initial adversarial vulnerability assessment.
  - [Security Re-Review](security/SECURITY_REREVIEW.md) — Verification of mitigations and descriptor-relative operations.
- [Engineering & Security Standard](../AGENTS.md) — Binding guidelines for contributors, including POSIX sandboxing, ad-hoc codesigning, test harness expectations, and release verification.
