# Changelog

All notable changes to this plugin are documented here. The plugin follows
[Semantic Versioning](https://semver.org/). This version number tracks the
**plugin**, not the game.

## [0.1.1] - 2026-09-21

### Security

- Pinned the bootstrap install trust boundary: the first-install artifact URL,
  version and SHA-256 digest are now constants in `Model.js` (Midnight Royale
  1.0.9, Linux amd64), independently confirmed against the production release
  material. The unsigned `stable.json` record is now informational only and no
  longer supplies the artifact URL or checksum.
- Restricted downloads to the official host (`commerce.0xnorin.app`) over
  HTTPS, with no redirects followed and no arbitrary host accepted from remote
  metadata.
- Added a 64 KiB response-size cap (in addition to the timeout) on the release
  metadata fetch; oversized, malformed, unavailable or unexpected responses
  fail closed into "update unavailable".
- Replaced the predictable shared `/tmp` install paths with a unique private
  mode-0700 temporary directory created with `mktemp -d`, cleaned up on both
  success and failure.
- Added archive-entry validation before extraction: symlinks, hardlinks,
  devices, FIFOs, absolute paths, path traversal and out-of-layout entries are
  rejected, and only the expected regular `midnight-royale` file is installed.
- Replaced the shell-wrapped install step with fixed-argv `Process` commands (no
  shell, no interpolation of remote or user-controlled values).
- Throttled the display-only update check to a six-hour freshness window; a
  deliberate Retry still bypasses it.
- Reworded documentation to avoid privilege-elevation wording; installation
  requires no elevated privileges and is entirely user-local.

## [0.1.0] - 2026-09-20

### Added

- Initial Omarchy bar widget (a minimal `♠` glyph) with a details panel.
- Detection of an installed Midnight Royale and its version
  (`midnight-royale --version`).
- One-click install of the official Linux release into `~/.local/bin`.
- Display-only update-availability check against the public release record.
- `Install`, `Play`, `Website`, and `Retry` actions.
- Safe update fallback: no one-click updater; updates are delegated to the
  game's own signed updater.
