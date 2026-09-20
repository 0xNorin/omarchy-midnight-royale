import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// A minimal spade glyph in the Omarchy bar. Left click toggles the details
// panel, which detects the installed game, reports its version, and offers
// Play / Website / Installation & Updates actions. The game itself remains
// fully independent of this plugin; nothing here contains the binary, payment
// logic, entitlements or an updater.
BarWidget {
  id: root
  moduleName: "app.0xnorin.midnight-royale"

  // ---- Panel lifecycle. The bar identifies this widget as the panel's
  //      owner, so these names are the contract Quattro summons and hides.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "app.0xnorin.midnight-royale"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u2660"
    tooltipText: "Midnight Royale"
    onPressed: function(b) {
      if (b === Qt.LeftButton) root.toggle()
    }
  }
}
