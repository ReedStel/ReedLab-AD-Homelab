# Security policy

## Scope

ReedLab is intended only for disposable, isolated virtual machines using the default fictional domain and subnet. It is not supported on production systems or any machine joined to an unrelated domain.

## Reporting a vulnerability

Please use GitHub's private security-advisory feature for a suspected vulnerability. Include the affected file, expected behaviour, observed behaviour, and a minimal reproduction that contains no credentials or third-party data.

Do not publish active secrets, personal data, private network details, or exploitation instructions in a public issue.

## Secret hygiene

The repository must never contain passwords, password hashes, recovery keys, API tokens, certificates with private keys, VM exports, event-log exports, or screenshots that reveal a LAPS password. If a secret is committed, revoke or rotate it first; deleting the visible line is not sufficient because Git retains history.

## Supported versions

Security fixes target the latest repository version and currently serviced Windows Server 2022/2025 and Windows 11 builds.
