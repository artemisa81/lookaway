# Security Policy

LookAway runs a Bluetooth helper and Quickshell code inside the user's
Omarchy shell. It is not sandboxed and is not a guaranteed security boundary.

## Reporting

Please report suspected vulnerabilities privately through
[GitHub Security Advisories](https://github.com/artemisa81/lookaway/security/advisories/new)
when possible. Include the affected commit, environment, reproduction steps,
and whether the issue affects screen privacy, arbitrary code execution, or
Bluetooth/device access.

Do not include private AirPods identifiers or other personal data in a public
issue.

## Scope

Security reports include unsafe command construction, unintended screen or
Bluetooth data exposure, privilege escalation, and dependency/supply-chain
issues. A lost Bluetooth connection opening the screen is a documented
fail-open mode unless `failSafe` is enabled.
