import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets

// Generic full-shellScreen popup window for menus and context menus
// This is a top-level PanelWindow (sibling to MainScreen, not nested inside it)
// Provides click-outside-to-close functionality for any popup content
// Loads TrayMenu by default but can show context menus via showContextMenu()
PanelWindow {
  id: root

  required property ShellScreen shellScreen
  property string windowType: "popupmenu"  // Used for namespace and registration
  property int presentationGeneration: 0
  property bool _closing: false
  onVisibleChanged: {
    presentationGeneration++;
    if (!visible && !_closing)
      close();
  }
  onClosed: close()
  function requestPresentation() {
    return ++presentationGeneration;
  }

  // The host observes whichever menu/dialog it currently presents. A typed
  // reference also becomes null when externally owned content is destroyed.
  property QtObject popupContentItem: null
  onPopupContentItemChanged: {
    if (!popupContentItem && visible && !_closing)
      close();
  }

  Connections {
    target: root.popupContentItem
    enabled: !root._closing
    ignoreUnknownSignals: true
    function onVisibleChanged() {
      if (root.popupContentItem && !root.popupContentItem.visible)
        root.close();
    }
    function onClosed() {
      root.close();
    }
    function onPresentationClosed() {
      root.close();
    }
    function onPresentationInvalidated() {
      root.close();
    }
  }

  // Expose the trayMenu Loader directly (for backward compatibility)
  readonly property alias trayMenuLoader: trayMenuLoader

  // Dynamic context menu callback for items in other windows (e.g., desktop widgets)
  property var dynamicMenuCallback: null

  anchors.top: true
  anchors.left: true
  anchors.right: true
  anchors.bottom: true
  visible: false
  color: "transparent"

  // Use Top layer for proper event handling, but on labwc use Bottom
  // to avoid stealing input from popups while still catching outside clicks.
  // However, when a dialog is open, always use Top so dialogs appear above apps.
  WlrLayershell.layer: (CompositorService.isLabwc && !hasDialog) ? WlrLayer.Bottom : WlrLayer.Top
  WlrLayershell.keyboardFocus: hasDialog ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  WlrLayershell.namespace: "atmosphera-" + windowType + "-" + (shellScreen?.name || "unknown")
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  // Track if a dialog is currently open (needed for keyboard focus)
  property bool hasDialog: false

  // Register with PanelService so widgets can find this window
  Component.onCompleted: {
    objectName = "popupMenuWindow-" + (shellScreen?.name || "unknown");
    PanelService.registerPopupMenuWindow(shellScreen, root);
  }

  Component.onDestruction: {
    PanelService.unregisterPopupMenuWindow(shellScreen);
  }

  // Load TrayMenu as the default content
  Loader {
    id: trayMenuLoader
    source: Quickshell.shellDir + "/Modules/Bar/Extras/TrayMenu.qml"
    onLoaded: {
      if (item) {
        item.shellScreen = root.shellScreen;
      }
    }
  }

  // Dynamic context menu - created as child of this window (Top layer) so input works correctly
  // Used for items in other windows like desktop widgets (bottom layer)
  NPopupContextMenu {
    id: dynamicMenu
    visible: false
    shellScreen: root.shellScreen
    minWidth: 180

    onTriggered: (action, item) => {
      if (root.dynamicMenuCallback) {
        // Callback returns true if it will handle closing (e.g., opening a dialog)
        var handled = root.dynamicMenuCallback(action);
        if (!handled) {
          root.close();
        }
      } else {
        root.close();
      }
    }
  }

  function open() {
    if (!popupContentItem)
      popupContentItem = trayMenuLoader.item;
    visible = true;
    BarService.popupOpen = true;
  }

  // Adopt the actual menu, including caller-supplied tray/context menus.
  function showContextMenu(menu) {
    if (menu) {
      close();
      popupContentItem = menu;
      open();
    }
  }

  // Dialog callers prepare/open their content; this window owns its lifetime
  // as a presentation and observes closure just as it does for hosted menus.
  function showDialog(dialog) {
    close();
    popupContentItem = dialog;
    hasDialog = true;
    open();
  }

  // Show a dynamic context menu with model and callback at shellScreen coordinates
  // Used for items in other window layers (e.g., desktop widgets in bottom layer)
  function showDynamicContextMenu(model, screenX, screenY, callback) {
    close();
    dynamicMenu.model = model;
    dynamicMenuCallback = callback;

    // Use the anchor point item for positioning at absolute coordinates
    dynamicMenu.anchorItem = anchorPoint;
    anchorPoint.x = screenX;
    anchorPoint.y = screenY;

    popupContentItem = dynamicMenu;
    dynamicMenu.visible = true;
    open();
  }

  // Invisible anchor point for dynamic menu positioning
  Item {
    id: anchorPoint
    width: 1
    height: 1
  }

  // End the menu presentation; a dialog handoff explicitly adopts its content.
  function hideDynamicMenu() {
    dynamicMenu.close();
  }

  function close() {
    if (_closing)
      return;
    _closing = true;
    presentationGeneration++;
    visible = false;
    BarService.popupOpen = false;
    // Detach before asking the child to close: its signals cannot reenter
    // this transition or accidentally close a replacement presentation.
    const content = popupContentItem;
    popupContentItem = null;
    hasDialog = false;
    dynamicMenuCallback = null;
    if (dynamicMenu !== content)
      dynamicMenu.close();
    _closing = false;
    // All owner state is released before child callbacks can open new content.
    if (content) {
      if (typeof content.hideMenu === "function") {
        content.hideMenu();
      } else if (typeof content.close === "function") {
        content.close();
      }
    }
  }

  // Full-shellScreen click catcher - click anywhere outside content closes the window
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: root.close()
  }

  // Container for dialogs that need a full-shellScreen Item parent (e.g., Qt Popup)
  Item {
    id: dialogContainer
    anchors.fill: parent
  }

  // Expose the dialog container for external use
  readonly property alias dialogParent: dialogContainer
}
