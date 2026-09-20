import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Details panel for the Midnight Royale bar widget. Detects the installed
// game, reads its version, checks the public release record for a newer
// version, and — when the game is missing — installs the official Linux
// release into the user's ~/.local/bin (no sudo). Updates are still delegated
// to the game's own signed updater, which this plugin does not reimplement.
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
    refresh()
    root.controller.show()
  }

  function close() { root.controller.hide() }

  function toggle() { root.opened ? root.close() : root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Re-run detection and the update check. Called on open, Retry, and after a
  // successful install. Detection first asks `which` — unlike running the game
  // binary directly, `which` always exists, so its exit code reliably tells us
  // whether the game is installed even when the binary is absent.
  function refresh() {
    statusKey = Model.STATUS_CHECKING
    installedVersion = ""
    latestVersion = ""
    updateState = Model.UPDATE_UNAVAILABLE
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

  // Download and install the official Linux release into ~/.local/bin. No
  // sudo, no shell piping of downloaded content: the tarball is fetched with
  // curl, its SHA-256 is checked against the release record, and the binary is
  // extracted and installed with tar/install.
  function install() {
    installError = ""
    statusKey = Model.STATUS_INSTALLING
    installMetaProcess.command = ["curl", "-fsS", "--max-time", "10", Model.UPDATE_METADATA_URL]
    installMetaProcess.running = true
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
      root.checkUpdates()
    }
  }

  // ---- Update check: public stable release record (display-only) ----
  property string _updateOutput: ""

  function checkUpdates() {
    updateState = Model.UPDATE_UNAVAILABLE
    updateProcess.command = ["curl", "-fsS", "--max-time", "5", Model.UPDATE_METADATA_URL]
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

  // ---- Install pipeline: metadata -> download -> verify -> extract/install ----
  property string _installMetaOutput: ""
  property string _installUrl: ""
  property string _installSha256: ""
  property string _installVerifyOutput: ""

  Process {
    id: installMetaProcess
    command: []
    running: false
    stdout: StdioCollector { id: installMetaStdout; waitForEnd: true; onStreamFinished: root._installMetaOutput = text }
    stderr: StdioCollector { id: installMetaStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.installError = "Could not reach the release server."
        statusKey = Model.STATUS_NOT_INSTALLED
        return
      }
      var meta = Model.parseStableJson(String(root._installMetaOutput || installMetaStdout.text || ""))
      if (meta === null || meta.linuxAmd64 === null) {
        root.installError = "No Linux release is available."
        statusKey = Model.STATUS_NOT_INSTALLED
        return
      }
      root._installUrl = meta.linuxAmd64.url
      root._installSha256 = meta.linuxAmd64.sha256
      installDownloadProcess.command = ["curl", "-fSs", "--max-time", "180", "-o", "/tmp/mr-download.tar.gz", root._installUrl]
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
        root.installError = "Download failed."
        statusKey = Model.STATUS_NOT_INSTALLED
        return
      }
      installVerifyProcess.command = ["sha256sum", "/tmp/mr-download.tar.gz"]
      installVerifyProcess.running = true
    }
  }

  Process {
    id: installVerifyProcess
    command: []
    running: false
    stdout: StdioCollector { id: installVerifyStdout; waitForEnd: true; onStreamFinished: root._installVerifyOutput = text }
    stderr: StdioCollector { id: installVerifyStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.installError = "Could not verify the download."
        statusKey = Model.STATUS_NOT_INSTALLED
        return
      }
      var hash = Model.parseSha256Sum(String(root._installVerifyOutput || installVerifyStdout.text || ""))
      if (hash === null || hash !== root._installSha256) {
        root.installError = "Checksum mismatch; install aborted."
        statusKey = Model.STATUS_NOT_INSTALLED
        return
      }
      installFinishProcess.command = ["bash", "-lc", "set -e; mkdir -p ~/.local/bin; rm -rf /tmp/mr-install; mkdir -p /tmp/mr-install; tar -xzf /tmp/mr-download.tar.gz -C /tmp/mr-install; install -m 755 /tmp/mr-install/midnight-royale ~/.local/bin/midnight-royale; rm -rf /tmp/mr-install /tmp/mr-download.tar.gz"]
      installFinishProcess.running = true
    }
  }

  Process {
    id: installFinishProcess
    command: []
    running: false
    stdout: StdioCollector { id: installFinishStdout; waitForEnd: true }
    stderr: StdioCollector { id: installFinishStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.installError = "Install failed."
        statusKey = Model.STATUS_NOT_INSTALLED
        return
      }
      // Installed — re-detect so the panel flips to the installed state.
      root.refresh()
    }
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
          onClicked: root.refresh()
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
