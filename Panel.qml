import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Details panel for the Midnight Royale bar widget. Detects the installed
// game, reads its version, and (display-only) checks the public release
// record for a newer version. It never downloads, installs, replaces or
// updates the game: any real update is delegated to the game's own signed
// updater, which this plugin does not reimplement.
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

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string titleText: Model.statusTitle(statusKey, installedVersion)
  readonly property string subtitleText: Model.statusSubtitle(statusKey, updateState, latestVersion)

  readonly property bool notInstalled: statusKey === Model.STATUS_NOT_INSTALLED
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

  // Re-run version detection and the update check. Called on open and Retry.
  // Nothing here blocks the shell: both stages run as short-lived subprocesses
  // and report back through onExited.
  function refresh() {
    statusKey = Model.STATUS_CHECKING
    installedVersion = ""
    latestVersion = ""
    updateState = Model.UPDATE_UNAVAILABLE
    versionProcess.command = ["midnight-royale", "--version"]
    versionProcess.running = true
  }

  // ---- Actions ----

  // Launch the game in the user's configured terminal. A fixed argv vector —
  // no shell, no interpolation, nothing user-controlled in the command line.
  // uwsm-app keeps the terminal in a proper session scope. The panel closes
  // after the launch request is handed off.
  function play() {
    // Verified against xdg-terminal-exec on Omarchy 4.0.4: --app-id and
    // --title set the Wayland app-id and terminal title.
    Quickshell.execDetached(["uwsm-app", "--", "xdg-terminal-exec", "--app-id=app.0xnorin.midnight-royale", "--title=Midnight Royale", "--", "midnight-royale"])
    root.close()
  }

  function openWebsite() { Qt.openUrlExternally(Model.WEBSITE_URL) }
  function openGet() { Qt.openUrlExternally(Model.INSTALL_URL) }
  function openInstallUpdates() { Qt.openUrlExternally(Model.INSTALL_UPDATES_URL) }

  // ---- Version detection: midnight-royale --version ----
  property string _versionStdout: ""

  Process {
    id: versionProcess
    command: []
    running: false
    stdout: StdioCollector { id: versionStdout; waitForEnd: true; onStreamFinished: root._versionStdout = text }
    stderr: StdioCollector { id: versionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        statusKey = Model.STATUS_NOT_INSTALLED
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
      // Any failure (network, non-200, malformed JSON) lands here as
      // "unavailable" — never a crash, never a false update notification,
      // and never a block on launching the installed game.
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
          text: "GET MIDNIGHT ROYALE"
          tooltipText: "Open the installation page"
          onClicked: root.openGet()
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
          visible: root.parsedInstalled
          text: "INSTALLATION & UPDATES"
          tooltipText: "Open installation and update instructions"
          onClicked: root.openInstallUpdates()
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
