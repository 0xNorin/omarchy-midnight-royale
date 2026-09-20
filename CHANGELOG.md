# Changelog

All notable changes to this plugin are documented here. The plugin follows
[Semantic Versioning](https://semver.org/). This version number tracks the
**plugin**, not the game.

## [0.1.0] - 2026-09-20

### Added

- Initial Omarchy bar widget (a minimal `♠` glyph) with a details panel.
- Detection of an installed Midnight Royale and its version
  (`midnight-royale --version`).
- Display-only update-availability check against the public release record.
- `Play`, `Website`, `Get Midnight Royale`, and `Installation & Updates`
  actions.
- Safe update fallback: no one-click installer; updates are delegated to the
  game's own signed updater.
