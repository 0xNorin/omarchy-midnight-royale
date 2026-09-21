# Midnight Royale for Omarchy

An optional [Omarchy](https://omarchy.org/) bar applet for installing,
launching and updating [Midnight Royale](https://0xnorin.app/midnight-royale/)
— a mature retro five-card-draw terminal game by [0xNorin](https://0xnorin.app).

This is an **Omarchy integration only**, not the game itself. It adds a small
spade glyph to the Omarchy bar that detects whether Midnight Royale is
installed, shows its version, installs it with one click when it is missing,
tells you when a newer signed release exists, and launches the game in your
configured terminal.

> Built for the terminal. At home on Omarchy.

> A mature-themed retro five-card-draw terminal game inspired by classic
> computer games of the 1980s and 1990s. Midnight Royale does not offer
> real-money gambling.

## Screenshot

<!-- TODO: replace with a real screenshot from the Omarchy VM. -->

## Features

- A minimal `♠` glyph in the Omarchy bar with a `Midnight Royale` tooltip.
- Detects whether Midnight Royale is installed and shows its version.
- One-click install of the pinned, reviewed Linux release into `~/.local/bin`.
- Checks for a newer signed release and shows an "Update available" hint.
- `Install`, `Play`, `Website`, and `Retry` actions.
- Never blocks the shell: detection, install and release checks run as
  short-lived subprocesses with strict timeouts.

## Requirements

- Omarchy 4 (Quattro shell) or later.

Midnight Royale is installed separately by the widget itself — no manual
download is required.

## Installation

```bash
omarchy plugin add https://github.com/0xNorin/omarchy-midnight-royale.git --enable
```

Place the widget in the bar section you prefer (right, by default):

```bash
omarchy bar move app.0xnorin.midnight-royale --section right
```

## Usage

Click the `♠` in the bar to open the details panel. Press `Escape` to close it.

- **Not installed** — `Install Midnight Royale` downloads the pinned official
  Linux release, verifies its checksum, and installs it to `~/.local/bin`.
- **Installed** — `Play` launches the game in your configured terminal.
- **Update available** — the panel shows the newer version. Updates are
  performed by the game's own signed updater, never by this plugin.
- `Website` opens the Midnight Royale website at any time.

## Plugin updating

This plugin and the game update independently.

```bash
omarchy plugin update app.0xnorin.midnight-royale
```

Updating the plugin does **not** update the game. The game is updated by its
own signed updater.

## Removal

```bash
omarchy plugin remove app.0xnorin.midnight-royale
```

Removing the plugin never touches the game or its saved data. To remove the
game itself, delete `~/.local/bin/midnight-royale`.

## Troubleshooting

- **Install fails with a checksum mismatch** — the download was corrupted or
  tampered with; try again. Nothing is installed unless the download matches
  the SHA-256 pinned in the reviewed plugin source.
- **The widget shows "not installed" but the game is there** — make sure
  `midnight-royale` is on your `PATH` (for example `/usr/bin/midnight-royale`
  from the AUR package, or `~/.local/bin/midnight-royale`).
- **"Unable to check for updates"** — the release check needs network access
  to `commerce.0xnorin.app`. The game still launches normally.
- **`Play` does nothing** — confirm a terminal is configured and that
  `xdg-terminal-exec` resolves it.

## Security

This plugin is deliberately thin. It contains no game binary, no payment
logic, no customer data, and no entitlement logic. Its trust model:

- **Bootstrap install is pinned.** The first-install artifact URL, version and
  SHA-256 digest are constants in the reviewed `Model.js`, not read from any
  network source. A bootstrap install downloads exactly that artifact from
  exactly the official host and verifies exactly that digest.
- **Unsigned release metadata is informational only.** `stable.json` is read
  solely to display whether a newer version exists; it never supplies an
  artifact URL or checksum and never decides what is installed or trusted.
- **Updates are delegated to the signed updater.** After installation, all
  application updates are performed by Midnight Royale's own signed updater;
  this plugin never re-implements signature verification or an updater.
- **Downloads are restricted** to the official host, over HTTPS, with no
  redirects followed and no arbitrary host accepted from remote metadata.
- **Metadata has strict limits** — a 64 KiB response-size cap plus a timeout;
  oversized, malformed or unavailable responses fail closed into "update
  unavailable".
- **Installation uses a private temporary directory** created with `mktemp -d`
  (mode 0700), cleaned up on both success and failure; no predictable shared
  `/tmp` paths are used.
- **Archive members are validated before extraction** — symlinks, hardlinks,
  devices, FIFOs, path traversal and out-of-layout entries are all rejected,
  and only the expected regular `midnight-royale` file is installed.
- **Installation is user-local** — it installs to `~/.local/bin/midnight-royale`,
  requires no elevated privileges, and never modifies system directories.
- It never runs `curl | sh`, never pipes downloaded content into a shell, and
  launches the game with a fixed argument array (no shell, no interpolation).

See [SECURITY.md](SECURITY.md).

## Development

Validate the manifest and repository layout:

```bash
omarchy plugin validate <plugin-directory>
```

Lint the QML against the installed shell imports (on an Omarchy machine):

```bash
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml
```

Run the unit tests for the pure logic (no shell required):

```bash
node test/Model.test.js
```

The logic in `Model.js` is pure and node-testable; the CI workflow runs it on
every push. The authoritative QML validation is the manual test on an Omarchy
VM — generic CI does not validate QML imports.

## License

[MIT](LICENSE) © 2026 0xNorin.

Midnight Royale is a separate, proprietary product by 0xNorin:
<https://0xnorin.app/midnight-royale/>.
