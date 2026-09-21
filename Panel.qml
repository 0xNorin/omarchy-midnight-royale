import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Details panel for the Midnight Royale bar widget. Detects the installed
// game, reads its version, checks the public release record for a newer
// version (display-only), and — when the game is missing — installs the
// pinned, reviewed Linux release into the user's ~/.local/bin. Installation
// requires no elevated privileges and never touches system directories.
// Future application updates are delegated to the game's own signed updater,
// which this plugin does not reimplement.
Panel {
  id: root
  moduleName: "app.0xnorin.midnight-royale"
  ipcTarget: "app.0xnorin.midnight-royale"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Status ----
  property string statusKey: Model.STATUS_CHECKING
  property string updateState: Model.UPDATE_UNAVAILABLE
  property string installedVersion: ""
  property string latestVersion: ""
  property string installError: ""

  // ---- Update-check throttle (per shell session, in-memory) ----
  property real _lastUpdateCheckEpochMs: 0
  property bool _pendingForceUpdate: false

  // ---- Install pipeline state ----
  property string _homeDir: ""
  property string _installTmpdir: ""

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string titleText: Model.statusTitle(statusKey, installedVersion)
  readonly property string subtitleText: Model.statusSubtitle(statusKey, updateState, latestVersion)

  readonly property bool notInstalled: statusKey === Model.STATUS_NOT_INSTALLED
  readonly property bool installing: statusKey === Model.STATUS_INSTALLING
  readonly property bool anyInstalled: statusKey === Model.STATUS_INSTALLED || statusKey === Model.STATUS_INSTALLED_UNPARSED
  readonly property bool parsedInstalled: statusKey === Model.STATUS_INSTALLED
  readonly property bool showRetry: statusKey === Model.STATUS_INSTALLED && updateState === Model.UPDATE_UNAVAILABLE

  function open() {
    refresh(false)
    root.controller.show()
  }

  function close() { root.controller.hide() }

  function toggle() { root.opened ? root.close() : root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Re-run local detection, then (unless fresh) the display-only update check.
  // Called on open (force=false), Retry (force=true) and after a successful
  // install. Detection first asks `which` — unlike running the game binary
  // directly, `which` always exists, so its exit code reliably tells us whether
  // the game is installed even when the binary is absent. The previous update
  // state is kept so a throttled (skipped) network check doesn't clear it.
  function refresh(force) {
    statusKey = Model.STATUS_CHECKING
    installedVersion = ""
    _pendingForceUpdate = !!force
    whichProcess.command = ["which", "midnight-royale"]
    whichProcess.running = true
  }

  // ---- Actions ----

  // Launch the game in the user's configured terminal. A fixed argv vector —
  // no shell, no interpolation. Verified against xdg-terminal-exec 4.0.4.
  function play() {
    Quickshell.execDetached(["uwsm-app", "--", "xdg-terminal-exec", "--app-id=app.0xnorin.midnight-royale", "--title=Midnight Royale", "--", "midnight-royale"])
    root.close()
  }

  function openWebsite() { Qt.openUrlExternally(Model.WEBSITE_URL) }

  // Install the pinned, reviewed Linux release into ~/.local/bin. The artifact
  // URL and SHA-256 come from Model.js constants, never from remote metadata.
  // Every step runs as a fixed argv Process — no shell, no interpolation of
  // remote or user-controlled values. The archive is downloaded into a unique
  // private temporary directory, checksum-verified against the pinned digest,
  // validated entry-by-entry, and only the expected regular executable is
  // installed.
  function install() {
    installError = ""
    statusKey = Model.STATUS_INSTALLING
    // Defense-in-depth: the pinned URL must be HTTPS on the allowlisted host.
    if (!Model.isAllowedHost(Model.BOOTSTRAP_URL)) {
      _installFail("Bootstrap URL is not on an allowed host.")
      return
    }
    if (_homeDir === "") {
      _installFail("Could not determine the home directory.")
      return
    }
    _installTmpdir = ""
    installMktempProcess.command = ["mktemp", "-d"]
    installMktempProcess.running = true
  }

  function _installFail(message) {
    installError = message
    statusKey = Model.STATUS_NOT_INSTALLED
    _cleanupInstallTmp()
  }

  function _cleanupInstallTmp() {
    if (_installTmpdir !== "") {
      installCleanupProcess.command = ["rm", "-rf", _installTmpdir]
      installCleanupProcess.running = true
      _installTmpdir = ""
    }
  }

  // Capture $HOME once for the session so the install destination can be built
  // without shell expansion.
  Component.onCompleted: homeProcess.running = true

  Process {
    id: homeProcess
    command: ["printenv", "HOME"]
    running: false
    stdout: StdioCollector { id: homeStdout; waitForEnd: true; onStreamFinished: root._homeDir = String(text || "").trim() }
    stderr: StdioCollector { id: homeStderr; waitForEnd: true }
  }

  // ---- Detection step 1: which midnight-royale ----
  Process {
    id: whichProcess
    command: []
    running: false
    stdout: StdioCollector { id: whichStdout; waitForEnd: true }
    stderr: StdioCollector { id: whichStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        statusKey = Model.STATUS_NOT_INSTALLED
        return
      }
      versionProcess.command = ["midnight-royale", "--version"]
      versionProcess.running = true
    }
  }

  // ---- Detection step 2: midnight-royale --version ----
  property string _versionStdout: ""

  Process {
    id: versionProcess
    command: []
    running: false
    stdout: StdioCollector { id: versionStdout; waitForEnd: true; onStreamFinished: root._versionStdout = text }
    stderr: StdioCollector { id: versionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        // `which` found it, but --version failed: installed, version unknown.
        statusKey = Model.STATUS_INSTALLED_UNPARSED
        return
      }
      var parsed = Model.parseVersion(String(root._versionStdout || versionStdout.text || ""))
      if (parsed === null) {
        statusKey = Model.STATUS_INSTALLED_UNPARSED
        return
      }
      installedVersion = parsed
      statusKey = Model.STATUS_INSTALLED
      var forced = _pendingForceUpdate
      _pendingForceUpdate = false
      if (Model.isUpdateCheckDue(forced, _lastUpdateCheckEpochMs, Date.now())) {
        _lastUpdateCheckEpochMs = Date.now()
        checkUpdates()
      }
    }
  }

  // ---- Update check: public stable release record (display-only) ----
  property string _updateOutput: ""

  function checkUpdates() {
    updateState = Model.UPDATE_UNAVAILABLE
    updateProcess.command = ["curl", "-fsS", "--proto", "=https", "--max-time", "5", "--max-filesize", String(Model.METADATA_MAX_BYTES), Model.UPDATE_METADATA_URL]
    updateProcess.running = true
  }

  Process {
    id: updateProcess
    command: []
    running: false
    stdout: StdioCollector { id: updateStdout; waitForEnd: true; onStreamFinished: root._updateOutput = text }
    stderr: StdioCollector { id: updateStderr; waitForEnd: true }
    onExited: function(exitCode) {
      // Any failure lands here as "unavailable" — never a crash, never a
      // false update notification, never a block on launching the game.
      if (exitCode !== 0) {
        updateState = Model.UPDATE_UNAVAILABLE
        return
      }
      var meta = Model.parseStableJson(String(root._updateOutput || updateStdout.text || ""))
      if (meta === null) {
        updateState = Model.UPDATE_UNAVAILABLE
        return
      }
      latestVersion = meta.version
      updateState = Model.compareVersions(installedVersion, meta.version) < 0
        ? Model.UPDATE_AVAILABLE
        : Model.UPDATE_CURRENT
    }
  }

  // ---- Install pipeline ----
  // mktemp -> download -> sha256sum -> tar -tvf -> tar extract -> find check
  // -> install. Each decision delegates to a pure Model.js function; each step
  // is a fixed argv Process. No remote or user-controlled value is ever
  // interpolated into a shell command, and the temporary directory is a unique
  // mode-0700 directory created with mktemp.

  Process {
    id: installMktempProcess
    command: []
    running: false
    stdout: StdioCollector { id: installMktempStdout; waitForEnd: true }
    stderr: StdioCollector { id: installMktempStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._installFail("Could not create a temporary directory.")
        return
      }
      var dir = String(installMktempStdout.text || "").trim()
      // mktemp -d returns an absolute, unique path; require it before use.
      if (dir === "" || dir[0] !== "/") {
        root._installFail("Invalid temporary directory.")
        return
      }
      root._installTmpdir = dir
      installDownloadProcess.command = ["curl", "-fS", "--proto", "=https", "--max-time", "180", "--max-filesize", "20000000", "-o", dir + "/archive", Model.BOOTSTRAP_URL]
      installDownloadProcess.running = true
    }
  }

  Process {
    id: installDownloadProcess
    command: []
    running: false
    stdout: StdioCollector { id: installDownloadStdout; waitForEnd: true }
    stderr: StdioCollector { id: installDownloadStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._installFail("Download failed.")
        return
      }
      installVerifyProcess.command = ["sha256sum", root._installTmpdir + "/archive"]
      installVerifyProcess.running = true
    }
  }

  Process {
    id: installVerifyProcess
    command: []
    running: false
    stdout: StdioCollector { id: installVerifyStdout; waitForEnd: true }
    stderr: StdioCollector { id: installVerifyStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._installFail("Could not verify the download.")
        return
      }
      if (!Model.verifyChecksum(String(installVerifyStdout.text || ""), Model.BOOTSTRAP_SHA256)) {
        root._installFail("Checksum mismatch; install aborted.")
        return
      }
      installListProcess.command = ["tar", "-tvf", root._installTmpdir + "/archive"]
      installListProcess.running = true
    }
  }

  Process {
    id: installListProcess
    command: []
    running: false
    stdout: StdioCollector { id: installListStdout; waitForEnd: true }
    stderr: StdioCollector { id: installListStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._installFail("Could not inspect the archive.")
        return
      }
      var verdict = Model.validateTarList(String(installListStdout.text || ""))
      if (!verdict.ok) {
        root._installFail("Unsafe archive: " + verdict.reason)
        return
      }
      installExtractProcess.command = ["tar", "--no-same-owner", "--no-same-permissions", "-xzf", root._installTmpdir + "/archive", "-C", root._installTmpdir, Model.BOOTSTRAP_EXECUTABLE]
      installExtractProcess.running = true
    }
  }

  Process {
    id: installExtractProcess
    command: []
    running: false
    stdout: StdioCollector { id: installExtractStdout; waitForEnd: true }
    stderr: StdioCollector { id: installExtractStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._installFail("Extraction failed.")
        return
      }
      installCheckProcess.command = ["find", root._installTmpdir, "-maxdepth", "1", "-type", "f", "-name", Model.BOOTSTRAP_EXECUTABLE, "-print"]
      installCheckProcess.running = true
    }
  }

  Process {
    id: installCheckProcess
    command: []
    running: false
    stdout: StdioCollector { id: installCheckStdout; waitForEnd: true }
    stderr: StdioCollector { id: installCheckStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var expected = root._installTmpdir + "/" + Model.BOOTSTRAP_EXECUTABLE
      var found = String(installCheckStdout.text || "").trim()
      // `find -type f` matches only a regular file (never a symlink), so this
      // independently confirms the extracted source exists and is a plain file.
      if (exitCode !== 0 || found !== expected) {
        root._installFail("Extracted executable is not the expected regular file.")
        return
      }
      installInstallProcess.command = ["install", "-D", "-m", "755", expected, root._homeDir + "/.local/bin/" + Model.BOOTSTRAP_EXECUTABLE]
      installInstallProcess.running = true
    }
  }

  Process {
    id: installInstallProcess
    command: []
    running: false
    stdout: StdioCollector { id: installInstallStdout; waitForEnd: true }
    stderr: StdioCollector { id: installInstallStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._installFail("Install failed.")
        return
      }
      // The pinned bootstrap release was just installed; it is, by definition,
      // the current stable version.
      updateState = Model.UPDATE_CURRENT
      latestVersion = Model.BOOTSTRAP_VERSION
      _cleanupInstallTmp()
      // Re-detect so the panel flips to the installed state.
      root.refresh(false)
    }
  }

  Process {
    id: installCleanupProcess
    command: []
    running: false
    // No collectors: `rm -rf` produces no output. The path being removed is
    // always a unique directory created by `mktemp -d` earlier in this
    // pipeline, never a predictable shared path.
  }

  // ---- Rendering ----

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: parent.width
          text: "\u2660 MIDNIGHT ROYALE"
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          font.letterSpacing: 1
        }

        Text {
          width: parent.width
          text: "Retro five-card draw after dark"
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          topPadding: Style.space(6)
          text: root.titleText
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: root.subtitleText !== ""
          text: root.subtitleText
          color: Qt.darker(root.contentForeground, 1.3)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: root.installError !== "" && root.statusKey === Model.STATUS_NOT_INSTALLED
          text: root.installError
          color: Color.urgent
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        component ActionButton: Button {
          width: content.width
          leftAlign: true
          bordered: true
          foreground: root.contentForeground
          accent: Color.accent
          fontFamily: root.contentFontFamily
        }

        ActionButton {
          visible: root.notInstalled
          text: "INSTALL MIDNIGHT ROYALE"
          tooltipText: "Download and install the game"
          onClicked: root.install()
        }

        ActionButton {
          visible: root.anyInstalled
          text: "PLAY"
          tooltipText: "Launch Midnight Royale in your terminal"
          onClicked: root.play()
        }

        ActionButton {
          visible: root.showRetry
          text: "RETRY"
          tooltipText: "Check for updates again"
          onClicked: root.refresh(true)
        }

        ActionButton {
          text: "WEBSITE"
          tooltipText: "Open the Midnight Royale website"
          onClicked: root.openWebsite()
        }
      }
    }
  }
}
