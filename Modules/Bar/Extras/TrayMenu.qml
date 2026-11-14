import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

PopupWindow {
  id: root

  property ShellScreen shellScreen

  property var trayItem: null
  property var anchorItem: null
  property real anchorX
  property real anchorY
  property bool isSubMenu: false
  property int presentationGeneration: 0
  property bool _showRequested: false
  signal presentationInvalidated
  signal presentationClosed
  NPresentationAnchor {
    id: requestAnchor
    onInvalidated: {
      root.hideMenu();
      root.presentationInvalidated();
    }
  }
  onTrayItemChanged: {
    if (root._showRequested && !root.isSubMenu && root.trayItem !== requestAnchor.identity) {
      root.hideMenu();
      root.presentationInvalidated();
    }
  }
  function _queueRequestedShow() {
    if (root._showRequested && showTimer.item)
      showTimer.restart();
  }
  onVisibleChanged: {
    if (!visible) {
      requestAnchor.cancel();
      root._showRequested = false;
      presentationGeneration++;
      showTimer.stop();
      anchorTimer.stop();
    } else if (root.isSubMenu && !requestAnchor.armed) {
      requestAnchor.request(root.anchorItem);
    }
  }
  property string widgetSection: ""
  property int widgetIndex: -1
  property var _pinEditor: null
  property bool _pinBusy: false

  // The menu retains a concrete command session, not a later interpretation of
  // its displayed row index. Runtime callers can also capture explicitly.
  function capturePinEditor() {
    if (_pinBusy)
      return false;
    if (_pinEditor)
      _pinEditor.commands.detach();
    _pinEditor = null;
    var screenName = root.shellScreen?.name || "";
    var section = root.widgetSection;
    var index = root.widgetIndex;
    var item = root.trayItem;
    var itemName = item ? (item.tooltipTitle || item.name || item.id || "") : "";
    if (!itemName || index < 0 || !["left", "center", "right"].includes(section))
      return false;
    var screenOverride = Settings.getBarWidgetsForScreen(screenName) !== Settings.data.bar.widgets;
    var commands = null;
    if (screenOverride) {
      var monitors = Settings.data.bar.screenOverrides;
      for (var i = 0; i < monitors.length; ++i) {
        if (monitors[i].name === screenName) {
          commands = Settings.createRecordListEditor(["bar", "screenOverrides"], [
                                                       {
                                                         index: i
                                                       },
                                                       {
                                                         key: "widgets"
                                                       },
                                                       {
                                                         key: section
                                                       }
                                                     ]);
          break;
        }
      }
    } else {
      commands = Settings.createRecordListEditor(["bar", "widgets", section], []);
    }
    if (!commands || commands.initialValue[index]?.id !== "Tray") {
      if (commands)
        commands.detach();
      return false;
    }
    _pinEditor = {
      commands: commands,
      screenName: screenName,
      screenOverride: screenOverride,
      section: section,
      index: index,
      item: item,
      itemName: itemName
    };
    return true;
  }

  // Derive menu from trayItem (only used for non-submenus)
  readonly property QsMenuHandle menu: isSubMenu ? null : (trayItem ? trayItem.menu : null)
  onMenuChanged: {
    presentationGeneration++;
    root._queueRequestedShow();
  }

  // Compute if current tray item is pinned
  readonly property bool isPinned: {
    if (!trayItem || widgetSection === "" || widgetIndex < 0)
      return false;
    var widgets = Settings.getBarWidgetsForScreen(root.shellScreen?.name)[widgetSection];
    if (!widgets || widgetIndex >= widgets.length)
      return false;
    var widgetSettings = widgets[widgetIndex];
    if (!widgetSettings || widgetSettings.id !== "Tray")
      return false;
    var pinnedList = widgetSettings.pinned || [];
    const itemName = trayItem.tooltipTitle || trayItem.name || trayItem.id || "";
    for (var i = 0; i < pinnedList.length; i++) {
      if (pinnedList[i] === itemName)
        return true;
    }
    return false;
  }

  readonly property int menuWidth: 220

  implicitWidth: menuWidth

  // Use the content height of the Flickable for implicit height
  implicitHeight: Math.min(shellScreen?.height * 0.9, flickable.contentHeight + Style.margin2S)

  // When implicitHeight changes (menu content loads), force anchor recalculation
  onImplicitHeightChanged: {
    if (visible && anchorItem) {
      root.updateAnchor();
    }
  }

  visible: false
  color: "transparent"
  anchor.item: anchorItem
  anchor.rect.x: {
    if (anchorItem && shellScreen) {
      let baseX = anchorX;

      // Calculate position relative to current shellScreen
      let menuScreenX;
      if (isSubMenu && anchorItem.Window && anchorItem.Window.window) {
        const posInPopup = anchorItem.mapToItem(null, 0, 0);
        const parentWindow = anchorItem.Window.window;
        const windowXOnScreen = parentWindow.x - shellScreen.x;
        menuScreenX = windowXOnScreen + posInPopup.x + baseX;
      } else {
        const anchorGlobalPos = anchorItem.mapToItem(null, 0, 0);
        const anchorScreenX = anchorGlobalPos.x;
        menuScreenX = anchorScreenX + baseX;
      }

      const menuRight = menuScreenX + implicitWidth;
      const screenRight = shellScreen.width;
      const menuLeft = menuScreenX;

      // Only adjust if menu would clip off shellScreen boundaries
      // Don't adjust if the positioning is intentional (e.g., negative offset for right bar)
      if (menuRight > screenRight && menuLeft < screenRight) {
        // Clipping on right edge - shift left
        const overflow = menuRight - screenRight;
        return baseX - overflow - Style.marginS;
      } else if (menuLeft < 0 && menuRight > 0) {
        // Clipping on left edge - shift right
        return baseX - menuLeft + Style.marginS;
      }

      return baseX;
    }
    return anchorX;
  }
  anchor.rect.y: {
    if (anchorItem && shellScreen) {
      const barPosition = Settings.getBarPositionForScreen(root.shellScreen?.name);

      let baseY = anchorY;

      // Only apply bottom bar special positioning if:
      // 1. Not a submenu
      // 2. Bar is at bottom
      // 3. anchorY is not already negative (if negative, it's pre-calculated from drawer)
      const shouldApplyBottomBarLogic = !isSubMenu && barPosition === "bottom" && anchorY >= 0;

      if (shouldApplyBottomBarLogic) {
        // For bottom bar from the bar itself, position menu above the anchor with margin
        baseY = -(implicitHeight + Style.marginS);
      } else if (barPosition === "top" && !isSubMenu && anchorY >= 0) {
        // For top bar: position menu below bar with margin
        const barHeight = Style.getBarHeightForScreen(root.shellScreen?.name);
        baseY = barHeight + Style.marginS;
      }

      // Use a robust way to get shellScreen coordinates
      const posInWindow = anchorItem.mapToItem(null, 0, 0);
      const parentWindow = anchorItem.Window.window;

      // Calculate shellScreen-relative Y of the window
      let windowYOnScreen = (parentWindow && shellScreen) ? (parentWindow.y - shellScreen.y) : 0;

      // If window reported 0 but bar is at bottom, assume it's at shellScreen bottom
      if (windowYOnScreen === 0 && barPosition === "bottom" && shellScreen) {
        windowYOnScreen = shellScreen.height - (parentWindow ? parentWindow.height : Style.getBarHeightForScreen(shellScreen.name));
      }

      // Calculate the shellScreen Y of the menu top
      // Use a small guess for height if implicitHeight is 0 to avoid covering the bar on the first frame
      const effectiveHeight = implicitHeight > 0 ? implicitHeight : 200;
      const effectiveBaseY = shouldApplyBottomBarLogic ? -(effectiveHeight + Style.marginS) : baseY;

      const menuScreenY = windowYOnScreen + posInWindow.y + effectiveBaseY;
      const menuBottom = menuScreenY + (implicitHeight > 0 ? implicitHeight : effectiveHeight);
      const screenHeight = shellScreen ? shellScreen.height : 1080;

      // Adjust the final baseY (the actual value returned to anchor.rect.y)
      let finalBaseY = shouldApplyBottomBarLogic ? -(implicitHeight + Style.marginS) : baseY;

      // Adjust if menu would clip off the bottom
      if (menuBottom > screenHeight) {
        const overflow = menuBottom - screenHeight;
        finalBaseY -= (overflow + Style.marginS);
      }

      // Adjust if menu would clip off the top
      // menuScreenY < 0 means it's above the shellScreen edge
      if (menuScreenY < 0) {
        finalBaseY -= (menuScreenY - Style.marginS);
      }

      return finalBaseY;
    }

    // Fallback if no anchor/shellScreen
    if (isSubMenu) {
      return anchorY;
    }
    return anchorY + (Settings.getBarPositionForScreen(root.shellScreen?.name) === "bottom" ? -implicitHeight : Style.getBarHeightForScreen(root.shellScreen?.name));
  }

  function showAt(item, x, y) {
    root.capturePinEditor();
    presentationGeneration++;
    showTimer.stop();
    anchorTimer.stop();
    root._showRequested = true;
    requestAnchor.request(item, root.isSubMenu ? undefined : root.trayItem);
    if (!requestAnchor.valid)
      return;
    showTimer.item = item;
    showTimer.menuX = x;
    showTimer.menuY = y;
    _showAt(item, x, y);
  }

  function _showAt(item, x, y) {
    if (!requestAnchor.valid || item !== requestAnchor.anchorItem) {
      return;
    }

    if (!opener.children || opener.children.values.length === 0) {
      //Logger.w("TrayMenu", "Menu not ready, delaying show")
      showTimer.item = item;
      showTimer.menuX = x;
      showTimer.menuY = y;
      showTimer.restart();
      return;
    }

    anchorItem = item;
    anchorX = x;
    anchorY = y;

    visible = true;
    // NInputGuard owns focus within this popup; do not resolve an Item method
    // through the caller's context (PopupWindow has no forceActiveFocus()).

    // Force update after showing.
    root.updateAnchor();
  }

  function updateAnchor() {
    anchorTimer.restart();
  }

  Timer {
    id: showTimer
    interval: 0
    property var item: null
    property real menuX: 0
    property real menuY: 0
    property int generation: -1
    onRunningChanged: {
      if (running)
        generation = root.presentationGeneration;
    }
    onTriggered: {
      if (generation === root.presentationGeneration && root._showRequested && requestAnchor.valid && item === requestAnchor.anchorItem)
        root._showAt(item, menuX, menuY);
    }
  }

  Timer {
    id: anchorTimer
    interval: 0
    property int generation: -1
    onRunningChanged: {
      if (running)
        generation = root.presentationGeneration;
    }
    onTriggered: {
      if (generation === root.presentationGeneration && root.visible && requestAnchor.valid && root.anchorItem)
        root.anchor.updateAnchor();
    }
  }

  function hideMenu() {
    requestAnchor.cancel();
    root._showRequested = false;
    presentationGeneration++;
    showTimer.stop();
    anchorTimer.stop();
    visible = false;

    // Clean up all submenus recursively
    for (var i = 0; i < columnLayout.children.length; i++) {
      const child = columnLayout.children[i];
      if (child?.subMenu) {
        child.subMenu.hideMenu();
        child.subMenu.destroy();
        child.subMenu = null;
      }
    }
    presentationClosed();
  }

  Item {
    id: escapeScope
    NInputGuard {
      target: escapeScope
    }
    anchors.fill: parent
    Keys.onEscapePressed: root.hideMenu()
  }

  QsMenuOpener {
    id: opener
    menu: root.menu
  }

  Rectangle {
    anchors.fill: parent
    color: AtmoColor.mSurface
    border.color: AtmoColor.mOutline
    border.width: Math.max(1, Style.borderS)
    radius: Style.radiusM

    // Fade-in animation
    opacity: root.visible ? 1.0 : 0.0

    Behavior on opacity {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutQuad
      }
    }
  }

  Flickable {
    id: flickable
    anchors.fill: parent
    anchors.margins: Style.marginS
    contentHeight: columnLayout.implicitHeight
    interactive: true

    // Fade-in animation
    opacity: root.visible ? 1.0 : 0.0

    Behavior on opacity {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutQuad
      }
    }

    // Use a ColumnLayout to handle menu item arrangement
    ColumnLayout {
      id: columnLayout
      width: flickable.width
      spacing: 0

      Repeater {
        model: opener.children ? [...opener.children.values] : []

        delegate: Rectangle {
          id: entry
          readonly property var presentationIdentity: modelData
          required property var modelData

          Layout.preferredWidth: parent.width
          Layout.preferredHeight: {
            if (modelData?.isSeparator) {
              return 8;
            } else {
              // Calculate based on text content
              const textHeight = text.contentHeight || (Style.fontSizeS * 1.2);
              return Math.max(28, textHeight + Style.margin2S);
            }
          }

          color: "transparent"
          property var subMenu: null

          NDivider {
            anchors.centerIn: parent
            width: parent.width - Style.margin2M
            visible: modelData?.isSeparator ?? false
          }

          Rectangle {
            id: innerRect
            anchors.fill: parent
            color: mouseArea.containsMouse ? AtmoColor.mHover : "transparent"
            radius: Style.radiusS
            visible: !(modelData?.isSeparator ?? false)

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.marginM
              anchors.rightMargin: Style.marginM
              spacing: Style.marginS

              // Indicator Container
              Item {
                visible: (modelData?.buttonType ?? QsMenuButtonType.None) !== QsMenuButtonType.None

                implicitWidth: Math.round(Style.baseWidgetSize * 0.5)
                implicitHeight: Math.round(Style.baseWidgetSize * 0.5)
                Layout.alignment: Qt.AlignVCenter

                // Helper properties
                readonly property int type: modelData?.buttonType ?? QsMenuButtonType.None
                readonly property bool isRadio: type === QsMenuButtonType.RadioButton
                readonly property bool isChecked: modelData?.checkState === Qt.Checked || (modelData?.checked ?? false)

                // Color Logic
                readonly property color activeColor: mouseArea.containsMouse ? AtmoColor.mOnHover : AtmoColor.mPrimary
                readonly property color checkMarkColor: mouseArea.containsMouse ? AtmoColor.mHover : AtmoColor.mOnPrimary
                readonly property color borderColor: isChecked ? activeColor : (mouseArea.containsMouse ? AtmoColor.mOnHover : AtmoColor.mOnSurface)

                // Checkbox Visuals
                Rectangle {
                  visible: !parent.isRadio
                  anchors.centerIn: parent
                  width: Math.round(Style.baseWidgetSize * 0.5)
                  height: Math.round(Style.baseWidgetSize * 0.5)
                  radius: Style.iRadiusXS
                  color: "transparent" // Transparent to match RadioButton style
                  border.color: parent.borderColor
                  border.width: Style.borderM

                  Behavior on border.color {
                    ColorAnimation {
                      duration: Style.animationFast
                    }
                  }

                  AtmoIcon {
                    visible: parent.parent.isChecked
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -1
                    icon: Icon.check
                    color: parent.parent.activeColor
                    pointSize: Math.max(Style.fontSizeXXS, parent.width * 0.6)
                  }
                }

                // RadioButton Visuals
                Rectangle {
                  visible: parent.isRadio
                  anchors.centerIn: parent
                  width: Style.toOdd(Style.baseWidgetSize * 0.5)
                  height: Style.toOdd(Style.baseWidgetSize * 0.5)
                  radius: width / 2
                  color: "transparent"
                  border.color: parent.borderColor
                  border.width: Style.borderM // Slightly thicker for radio look

                  Behavior on border.color {
                    ColorAnimation {
                      duration: Style.animationFast
                    }
                  }

                  Rectangle {
                    visible: parent.parent.isChecked
                    anchors.centerIn: parent
                    width: Style.toOdd(parent.width * 0.5)
                    height: Style.toOdd(parent.height * 0.5)
                    radius: width / 2
                    color: parent.parent.activeColor

                    Behavior on color {
                      ColorAnimation {
                        duration: Style.animationFast
                      }
                    }
                  }
                }
              }

              NText {
                id: text
                Layout.fillWidth: true
                color: (modelData?.enabled ?? true) ? (mouseArea.containsMouse ? AtmoColor.mOnHover : AtmoColor.mOnSurface) : AtmoColor.mOnSurfaceVariant
                text: modelData?.text !== "" ? modelData?.text.replace(/[\n\r]+/g, ' ') : "..."
                pointSize: Style.fontSizeS
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
              }

              Image {
                Layout.preferredWidth: Style.marginL
                Layout.preferredHeight: Style.marginL
                source: modelData?.icon ?? ""
                visible: (modelData?.icon ?? "") !== ""
                fillMode: Image.PreserveAspectFit
              }

              AtmoIcon {
                icon: modelData?.hasChildren ? "menu" : ""
                pointSize: Style.fontSizeS
                applyUiScale: false
                verticalAlignment: Text.AlignVCenter
                visible: modelData?.hasChildren ?? false
                color: (mouseArea.containsMouse ? AtmoColor.mOnTertiary : AtmoColor.mOnSurface)
              }
            }

            MouseArea {
              id: mouseArea
              anchors.fill: parent
              hoverEnabled: true
              enabled: (modelData?.enabled ?? true) && !(modelData?.isSeparator ?? false) && root.visible
              acceptedButtons: Qt.LeftButton | Qt.RightButton

              onClicked: mouse => {
                if (modelData && !modelData.isSeparator) {
                  if (modelData.hasChildren) {
                    // Click on items with children toggles submenu
                    if (entry.subMenu) {
                      // Close existing submenu
                      entry.subMenu.hideMenu();
                      entry.subMenu.destroy();
                      entry.subMenu = null;
                    } else {
                      // Close any other open submenus first
                      for (var i = 0; i < columnLayout.children.length; i++) {
                        const sibling = columnLayout.children[i];
                        if (sibling !== entry && sibling.subMenu) {
                          sibling.subMenu.hideMenu();
                          sibling.subMenu.destroy();
                          sibling.subMenu = null;
                        }
                      }

                      // Determine submenu opening direction
                      let openLeft = false;
                      const barPosition = Settings.getBarPositionForScreen(root.shellScreen?.name);
                      const globalPos = entry.mapToItem(null, 0, 0);

                      if (barPosition === "right") {
                        openLeft = true;
                      } else if (barPosition === "left") {
                        openLeft = false;
                      } else {
                        openLeft = (root.widgetSection === "right");
                      }

                      // Open new submenu
                      entry.subMenu = Qt.createComponent("TrayMenu.qml").createObject(root, {
                                                                                        "menu": modelData,
                                                                                        "isSubMenu": true,
                                                                                        "shellScreen": root.shellScreen
                                                                                      });

                      if (entry.subMenu) {
                        const overlap = 60;
                        entry.subMenu.anchorItem = entry;
                        entry.subMenu.anchorX = openLeft ? -overlap : overlap;
                        entry.subMenu.anchorY = 0;
                        entry.subMenu.visible = true;
                        // Force anchor update with new position
                        entry.subMenu.updateAnchor();
                      }
                    }
                  } else {
                    // Click on regular items triggers them
                    modelData.triggered();
                    root.hideMenu();

                    // Close the drawer if it's open
                    if (root.shellScreen) {
                      const panel = PanelService.getPanel("trayDrawerPanel", root.shellScreen);
                      if (panel && panel.visible) {
                        panel.close();
                      }
                    }
                  }
                }
              }
            }
          }

          Component.onDestruction: {
            if (subMenu) {
              subMenu.destroy();
              subMenu = null;
            }
          }
        }
      }

      // PIN / UNPIN
      Rectangle {
        visible: {
          if (widgetSection === "" || widgetIndex < 0)
            return false;
          var widgets = Settings.getBarWidgetsForScreen(root.shellScreen?.name)[widgetSection];
          if (!widgets || widgetIndex >= widgets.length)
            return false;
          var widgetSettings = widgets[widgetIndex];
          if (!widgetSettings)
            return false;
          return widgetSettings.drawerEnabled ?? false;
        }
        Layout.preferredWidth: parent.width
        Layout.preferredHeight: 28
        color: pinUnpinMouseArea.containsMouse ? Qt.alpha(AtmoColor.mPrimary, 0.2) : Qt.alpha(AtmoColor.mPrimary, 0.08)
        radius: Style.radiusS
        border.color: Qt.alpha(AtmoColor.mPrimary, pinUnpinMouseArea.containsMouse ? 0.4 : 0.2)
        border.width: Style.borderS

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.marginM
          anchors.rightMargin: Style.marginM
          spacing: Style.marginS

          AtmoIcon {
            icon: root.isPinned ? "unpin" : "pin"
            pointSize: Style.fontSizeS
            applyUiScale: false
            verticalAlignment: Text.AlignVCenter
            color: AtmoColor.mPrimary
          }

          NText {
            Layout.fillWidth: true
            color: AtmoColor.mPrimary
            text: root.isPinned ? I18n.tr("panels.bar.tray-unpin-application") : I18n.tr("panels.bar.tray-pin-application")
            pointSize: Style.fontSizeS
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }
        }

        MouseArea {
          id: pinUnpinMouseArea
          anchors.fill: parent
          hoverEnabled: true
          enabled: !root._pinBusy

          onClicked: {
            if (root.isPinned) {
              root.removeFromPinned();
            } else {
              root.addToPinned();
            }
          }
        }
      }
    }
  }

  function addToPinned(callback) {
    return root._setPinned(true, callback);
  }

  function removeFromPinned(callback) {
    return root._setPinned(false, callback);
  }

  function _setPinned(pinned, callback) {
    var immediateEditor = false;
    var editor;
    function complete(result) {
      // A hidden direct call is one interaction, unlike an explicitly captured
      // menu session. Release its successful editor before callback reentry;
      // failed work and delayed menu captures keep their original fences.
      if (immediateEditor && result.status !== "failed" && root._pinEditor === editor) {
        editor.commands.detach();
        root._pinEditor = null;
      }
      if (result.status === "failed")
        Logger.w("TrayMenu", "Pin command failed:", result.error?.code || "settings-save-failed");
      if (typeof callback === "function")
        callback(result);
    }
    function refuse(code) {
      Qt.callLater(function () {
        complete({
                   status: "failed",
                   error: {
                     code: code
                   }
                 });
      });
      return false;
    }
    if (_pinBusy)
      return refuse("list-editor-busy");
    // Immediate, non-menu callers capture at submission. Delayed menu callbacks
    // must keep the session captured by showAt, including after a refusal.
    if (!_pinEditor && !visible && !_showRequested)
      immediateEditor = root.capturePinEditor();
    editor = _pinEditor;
    if (!editor || editor.item !== root.trayItem || editor.screenName !== (root.shellScreen?.name || "") || editor.section !== root.widgetSection || editor.index !== root.widgetIndex || editor.screenOverride !== (Settings.getBarWidgetsForScreen(editor.screenName) !== Settings.data.bar.widgets))
      return refuse("list-edit-conflict");
    var row = editor.commands.initialValue[editor.index];
    var names = (row.pinned || []).filter(function (name) {
      return name !== editor.itemName;
    });
    if (pinned)
      names.push(editor.itemName);
    _pinBusy = true;
    var accepted = editor.commands.submit([
                                            {
                                              op: "set",
                                              index: editor.index,
                                              field: "pinned",
                                              value: names
                                            }
                                          ], function (admission) {
                                            if (admission.status !== "admitted" || admission.refreshState !== "current") {
                                              root._pinBusy = false;
                                              complete({
                                                         status: "failed",
                                                         error: admission.error || {
                                                           code: "list-edit-conflict"
                                                         }
                                                       });
                                              return;
                                            }
                                            // Preserve live drawer resizing after admission. This is not saved feedback.
                                            if (pinned && root.shellScreen) {
                                              const panel = PanelService.getPanel("trayDrawerPanel", root.shellScreen);
                                              if (panel)
                                                panel.close();
                                            }
                                            Settings.saveResult(function (result) {
                                              root._pinBusy = false;
                                              complete(result);
                                            });
                                          });
    return accepted;
  }
}
