# Security Policy

SmartClip handles clipboard content and stores encrypted payloads locally. Please report suspected vulnerabilities privately so they can be investigated before public disclosure.

## Supported versions

Security fixes target the latest published SmartClip release. Before reporting an issue, confirm that it also affects the current version from [GitHub Releases](https://github.com/reathloo/smartClip/releases).

## Reporting a vulnerability

Email vulnerability reports to [security@jmakau.de](mailto:security@jmakau.de).
Alternatively, use GitHub's private vulnerability reporting flow when it is
available:

1. Open [Report a vulnerability](https://github.com/reathloo/smartClip/security/advisories/new).
2. Describe the affected version, macOS version, impact, and reproducible steps.
3. Include logs or screenshots only after removing clipboard contents, access tokens, passwords, personal data, and other secrets.

Do not open a public issue for an unpatched vulnerability and do not include working exploits or sensitive clipboard data in public discussions.

You should receive an initial acknowledgement through the GitHub advisory. Investigation and remediation times depend on severity and reproducibility; no fixed resolution deadline is promised.

## Scope

Useful reports include:

- unintended disclosure of clipboard payloads, encryption keys, notes, or sensitive metadata;
- bypasses of sensitive-content masking or exclusion controls;
- unsafe update verification or package-integrity behavior;
- unauthorized access caused by SmartClip's Keychain, Accessibility, or file-reference handling;
- vulnerabilities in bundled dependencies that are reachable through SmartClip.

General feature requests, installation problems, and non-sensitive bugs belong in the [issue tracker](https://github.com/reathloo/smartClip/issues/new/choose).

## Security boundaries

SmartClip encrypts clipboard payloads with AES-GCM and stores its encryption key in the macOS Keychain. Metadata required to organize history—including content type, timestamps, and estimated source application—can remain unencrypted. SmartClip cannot protect clipboard content from software already running with the same user's privileges or from an attacker controlling an unlocked Mac.

Read [PRIVACY.md](PRIVACY.md) for the complete data-handling description and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for bundled components.
