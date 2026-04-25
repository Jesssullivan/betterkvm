# Security Policy

## Reporting Vulnerabilities

Report security issues to jess@sulliwood.org. Do not open public issues for security vulnerabilities.

## Supported Versions

Only the latest commit on the default branch receives security updates.

## Security Practices

- Secrets encrypted with sops-nix (age keys)
- TruffleHog + Gitleaks scanning on every push
- Preseed scripts use secure deletion for boot partition secrets
- Serial consoles secured via Tailscale network boundary (ADR-002)
- SSH key-only authentication (no passwords)
