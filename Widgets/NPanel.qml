import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services

Loader {
  id: root

  property ShellScreen screen

  property Component panelContent: null
  property real preferredWidth: 700
  property real preferredHeight: 900
  property real preferredWidthRatio
  property real preferredHeightRatio
  property color panelBackgroundColor: Color.mSurface
  property bool draggable: false
  property var buttonItem: null
  property string buttonName: ""

  property bool panelAnchorHorizontalCenter: false
  property bool panelAnchorVerticalCenter: false
  property bool panelAnchorTop: false
  property bool panelAnchorBottom: false
  property bool panelAnchorLeft: false
  property bool panelAnchorRight: false

  // Properties to support positioning relative to the opener (button)
  property bool useButtonPosition: false
  property point buttonPosition: Qt.point(0, 0)
  property int buttonWidth: 0
  property int buttonHeight: 0

  property bool panelKeyboardFocus: false
  property bool backgroundClickEnabled: true

  // Animation properties
  readonly property real originalScale: 0.0
  property real scaleValue: originalScale
  property real dimmingOpacity: 0

  signal opened
  signal closed

  active: false
  asynchronous: true

  Component.onCompleted: {
    PanelService.registerPanel(root)
  }

  // -----------------------------------------
  // Functions to control background click behavior
  function disableBackgroundClick() {
    backgroundClickEnabled = false
  }

  function enableBackgroundClick() {
    // Add a small delay to prevent immediate close after drag release
    enableBackgroundClickTimer.restart()
  }

  Timer {
    id: enableBackgroundClickTimer
    interval: 100
    repeat: false
    onTriggered: backgroundClickEnabled = true
  }

  // -----------------------------------------
  function toggle(buttonItem, buttonName) {
    if (!active) {
      open(buttonItem, buttonName)
    } else {
      close()
    }
  }

  // -----------------------------------------
  function open(buttonItem, buttonName) {
    root.buttonItem = buttonItem
    root.buttonName = buttonName || ""

    setPosition()

    PanelService.willOpenPanel(root)

    backgroundClickEnabled = true
    active = true
    root.opened()
  }

  // -----------------------------------------
  function close() {
    dimmingOpacity = 0
    scaleValue = originalScale
    root.closed()
    active = false
    useButtonPosition = false
    backgroundClickEnabled = true
    PanelService.closedPanel(root)
  }

  // -----------------------------------------
  function setPosition() {
    // If we have a button name, we are landing here from an IPC call.
    // IPC calls have no idead on which screen they panel will spawn.
    // Resolve the button name to a proper button item now that we have a screen.
    if (buttonName !== "" && root.screen !== null) {
      buttonItem = BarService.lookupWidget(buttonName, root.screen.name)
    }

    // Get the button position if provided
    if (buttonItem !== undefined && buttonItem !== null) {
      useButtonPosition = true
      var itemPos = buttonItem.mapToItem(null, 0, 0)
      buttonPosition = Qt.point(itemPos.x, itemPos.y)
      buttonWidth = buttonItem.width
      buttonHeight = buttonItem.height
    } else {
      useButtonPosition = false
    }
  }

  // -----------------------------------------
  sourceComponent: Component {
    // PanelWindow has its own screen property inherited of QsWindow
    NPanelWindow {
      loggerPrefix: "NPanel"
    }
  }
}
