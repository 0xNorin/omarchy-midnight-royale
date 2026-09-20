# Security Policy

This plugin runs inside the long-lived Omarchy shell process, so it is kept
deliberately small and side-effect-free.

## Scope

This plugin is an integration layer. It:

- never contains the Midnight Royale binary, payment logic, customer data,
  entitlement logic, or an independent updater;
- never uses `sudo` and never adds installation hooks;
- never runs `curl | sh` and never downloads or executes arbitrary code;
- never interpolates remote or user-controlled values into shell commands —
  process launches use fixed argument arrays;
- never stores credentials, tokens, or customer information;
- never communicates with payment APIs and never exposes purchase or
  entitlement details.

## Network

The plugin makes exactly one network request, only when the panel opens or
when the user selects Retry: a `curl` fetch of the public release record at
`https://commerce.0xnorin.app/releases/stable.json`, with a strict 5-second
timeout. The response is parsed defensively; a malformed response yields an
"unavailable" state, never a crash or a false update notification.

That record is **unsigned** and is used only as a "a newer version exists"
hint. It is not a trust boundary. Real updates are performed by Midnight
Royale's own signed updater, whose Ed25519 signature verification this plugin
never reimplements.

## Reporting a vulnerability

Please report security issues privately to the 0xNorin team via
<https://0xnorin.app/>. Do not open a public issue for a suspected
vulnerability.
