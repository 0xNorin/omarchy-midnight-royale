# Game updater contract (proposal)

> **Status: proposal, not an implemented contract.**
>
> Midnight Royale does not currently expose a safe, documented, non-interactive
> command-line update entry point, so this Omarchy plugin uses the safe
> fallback: it shows the installed version and update availability, but every
> update is delegated to the game's own signed updater (via its Settings UI or
> the official installation/update documentation). It never implements a
> one-click update.
>
> This document describes the smallest command-line interface the game would
> need to expose before this plugin could offer a one-click update button that
> still performs full signature verification. Nothing here is built yet.

## Rationale

`midnight-royale --self-update-now` exists but is marked *"development only"*
and requires `--commerce-dev` plus a development release-signing key pin, so it
is not a production updater. The plugin must not silently invent a production
updater on top of it.

## Proposed interface

One new flag, non-interactive by default:

```text
midnight-royale --check-update
```

Exit codes:

| Code | Meaning |
| --- | --- |
| `0` | An update is available. |
| `1` | Already up to date. |
| `2` | Could not check (offline, invalid metadata, etc.). |
| `3` | Update check is unsupported in this build. |

Standard output (stable, machine-readable, one line):

```text
midnight-royale: update available 1.0.3 -> 1.0.4
```

A `--update` companion (run visibly in a terminal, since it can be slow or
interactive) would perform the check→download→verify→apply→restart flow the
in-game Settings flow already uses, delegating all signature verification to
the existing pinned release key:

```text
midnight-royale --update
```

## Contract requirements

- **Signature verification ownership** — the game, not the plugin, verifies
  the Ed25519-signed release metadata against its pinned key. The plugin must
  never reimplement this.
- **Behaviour when already current** — `--check-update` exits `1`; `--update`
  is a no-op that exits `0`.
- **Behaviour when the game is running** — `--update` should refuse or
  coordinate (for example, exit non-zero with a clear message) rather than
  corrupt a live install.
- **Rollback and failure** — reuse the game's existing crash-safe swap and
  rollback-on-failed-startup behaviour; the plugin assumes no responsibility
  for recovery.
- **Output** — machine-readable and defensive; the plugin must treat any
  malformed output as "unavailable", never as an update.
