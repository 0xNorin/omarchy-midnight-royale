# Security Policy

This plugin runs inside the long-lived Omarchy shell process, so it is kept
deliberately small and side-effect-free.

## Trust boundaries

The plugin's installation trust boundary is pinned in the reviewed source:

- The bootstrap artifact URL, version and SHA-256 digest are constants in
  `Model.js`, independently confirmed against the production release material
  when the pin was prepared. A first install downloads exactly that artifact
  from exactly the official host and verifies exactly that digest.
- The unsigned `stable.json` release record is **informational only**: it is
  read to show whether a newer version exists and never supplies an artifact
  URL or checksum, and never decides what is installed or trusted.
- After installation, every application update is delegated to Midnight
  Royale's own signed updater. This plugin never re-implements signature
  verification or an updater.

## Scope

This plugin is an integration layer. It:

- never contains the Midnight Royale binary, payment logic, customer data,
  entitlement logic, or an independent updater;
- never requests elevated privileges and never adds installation hooks;
- never runs `curl | sh` and never pipes downloaded content into a shell — the
  game is downloaded as a file, its SHA-256 is verified against the pinned
  digest, its archive is validated entry-by-entry, and only the expected
  regular `midnight-royale` file is extracted and installed;
- never interpolates remote or user-controlled values into shell commands —
  every network download and process launch uses a fixed argument array;
- never stores credentials, tokens, or customer information;
- never communicates with payment APIs and never exposes purchase or
  entitlement details.

## Install

When the game is missing, the `Install Midnight Royale` action:

1. creates a unique, private, mode-0700 temporary directory with `mktemp -d`,
2. downloads the pinned official Linux artifact over HTTPS (no redirects),
   restricted to the allowlisted host,
3. verifies its SHA-256 against the digest pinned in `Model.js`,
4. inspects every archive entry and rejects symlinks, hardlinks, devices,
   FIFOs, absolute paths, path traversal, and any entry outside the allowed
   release layout,
5. extracts only the expected `midnight-royale` regular file, and
6. installs it to `~/.local/bin/midnight-royale`.

The temporary directory is removed on both success and failure. The checksum
is a cryptographic digest of a pinned artifact; a mismatch aborts the install
completely. Remote metadata cannot replace the digest.

## Network

Network access is limited to `commerce.0xnorin.app` over HTTPS:

- The bootstrap download targets only the pinned official URL.
- The update metadata check fetches the fixed official `stable.json` URL with
  a strict timeout and a 64 KiB response-size cap; oversized, malformed,
  unavailable or unexpected responses fail closed into the "update
  unavailable" state and never prevent the installed game from launching.

The update check is throttled: network metadata is fetched only when the
previous automatic check is at least six hours old, or when the user chooses
Retry. Local installation/version detection still runs every time the panel
opens.

## Reporting a vulnerability

Please report security issues privately to the 0xNorin team via
<https://0xnorin.app/>. Do not open a public issue for a suspected
vulnerability.
