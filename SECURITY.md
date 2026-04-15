# Security Policy

## Supported Versions

This project is currently pre-1.0. Security fixes are expected to target the latest development version on `main`.

| Version | Supported |
| --- | --- |
| `main` | Yes |
| Older tags | Best effort |

## Reporting a Vulnerability

Do not open a public issue for suspected vulnerabilities.

Please use one of these channels:

1. GitHub private vulnerability reporting for this repository, if enabled.
2. Direct contact with the maintainer before public disclosure.

Include the following when possible:

- Affected version or commit
- Impact summary
- Reproduction steps or proof of concept
- Any proposed mitigation

## Response Expectations

- Initial triage target: within 7 days
- Status updates: as fixes are investigated
- Public disclosure: after a fix or mitigation is available, when practical

## Scope

Please report issues involving:

- Command injection
- Credential or token exposure
- Unsafe file permissions for secrets
- Authentication or authorization bypass
- Memory safety issues with real security impact
- Supply-chain or dependency integrity concerns

## Disclosure Guidelines

- Give maintainers a reasonable window to investigate and patch
- Avoid publishing exploit details before a coordinated fix
- Keep proof-of-concept data minimal and do not include real secrets

## Hardening Expectations

Security-sensitive code in this project should:

- Avoid shell interpolation for untrusted input
- Avoid storing secrets in plaintext by default
- Fail explicitly for unimplemented auth or security features
- Prefer least-privilege file permissions for local secret material
