# Security Policy

This plugin runs inside the long-lived Omarchy shell process, so it is kept
deliberately small and side-effect-free.

## Scope

This plugin is an integration layer. It:

- never contains the Midnight Royale binary, payment logic, customer data,
  entitlement logic, or an independent updater;
- never uses `sudo` and never adds installation hooks;
- never runs `curl | sh` and never pipes downloaded content into a shell —
  the game is downloaded as a file and its SHA-256 is verified before it is
  extracted with `tar` and installed with `install`;
- never interpolates remote or user-controlled values into shell commands —
  network downloads and process launches use fixed argument arrays;
- never stores credentials, tokens, or customer information;
- never communicates with payment APIs and never exposes purchase or
  entitlement details.

## Install

When the game is missing, the `Install Midnight Royale` action:

1. fetches the public release record over HTTPS,
2. downloads the official Linux artifact,
3. verifies its SHA-256 against that record, and
4. installs it to `~/.local/bin/midnight-royale`.

The checksum provides integrity against a corrupted transfer; it is not a
cryptographic signature. The game's own signed updater is the
signature-verifying trust path, and this plugin never reimplements it.

## Network

Network access is limited to `commerce.0xnorin.app`, only when the panel opens
(update check), when the user selects Retry, or during an install. Every
request has a strict timeout. Responses are parsed defensively; malformed data
yields an "unavailable" or failed-install state, never a crash or a false
update notification.

## Reporting a vulnerability

Please report security issues privately to the 0xNorin team via
<https://0xnorin.app/>. Do not open a public issue for a suspected
vulnerability.
