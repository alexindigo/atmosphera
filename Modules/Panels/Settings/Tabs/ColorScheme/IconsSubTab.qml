import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  readonly property var iconSetPlugins: {
    // Re-evaluate when plugins load/unload/enable/disable or order changes
    var _c = root.refreshCounter;

    var result = [];
    var installed = PluginRegistry.installedPlugins;
    for (var key in installed) {
      var mf = installed[key];
      if (mf && mf.entryPoints && mf.entryPoints.icons) {
        var parsed = PluginRegistry.parseCompositeKey(key);
        var isFloor = parsed && parsed.pluginId === "atmosphera-icons";
        var isLoaded = IconRegistry.iconSets[key] !== undefined;
        result.push({
                      "key": key,
                      "bareId": parsed ? parsed.pluginId : key,
                      "name": mf.name || parsed.pluginId || key,
                      "version": mf.version || "",
                      "enabled": PluginRegistry.isPluginEnabled(key),
                      "isFloor": isFloor,
                      "isLoaded": isLoaded,
                      "iconCount": isLoaded && IconRegistry.iconSets[key].manifest && IconRegistry.iconSets[key].manifest.icons ? Object.keys(IconRegistry.iconSets[key].manifest.icons).length : 0
                    });
      }
    }
    return result;
  }

  readonly property var setsOrdered: {
    var userOrder = Settings.data.icons.setOrder || [];
    var seen = {};
    var ordered = [];
    for (var ui = 0; ui < userOrder.length; ui++) {
      for (var si = 0; si < iconSetPlugins.length; si++) {
        if (iconSetPlugins[si].key === userOrder[ui] && !seen[userOrder[ui]]) {
          ordered.push(iconSetPlugins[si]);
          seen[userOrder[ui]] = true;
          break;
        }
      }
    }
    for (var ti = 0; ti < iconSetPlugins.length; ti++) {
      if (!seen[iconSetPlugins[ti].key]) {
        ordered.push(iconSetPlugins[ti]);
        seen[iconSetPlugins[ti].key] = true;
      }
    }
    return ordered;
  }

  property string query: ""
  property string activeSetFilter: ""
  property int refreshCounter: 0

  Connections {
    target: PluginRegistry
    function onPluginsChanged() {
      root.refreshCounter++;
    }
  }

  Connections {
    target: IconRegistry
    function onActiveOrderChanged() {
      root.refreshCounter++;
    }
  }

  // Per-set filtered icons (keys + resolved entries for the preview grid)
  readonly property var filteredIcons: {
    var src;
    if (activeSetFilter !== "" && IconRegistry.iconSets[activeSetFilter] !== undefined) {
      var setInfo = IconRegistry.iconSets[activeSetFilter];
      if (setInfo.manifest && setInfo.manifest.icons) {
        src = Object.keys(setInfo.manifest.icons);
      }
    }
    if (!src) {
      src = Object.keys(Icons.icons);
    }
    var q = query.toLowerCase();
    var result = [];
    for (var i = 0; i < src.length; i++) {
      var name = src[i];
      if (q && name.toLowerCase().indexOf(q) === -1) {
        continue;
      }
      result.push(name);
    }
    return result;
  }

  readonly property int activeSetCount: {
    var n = 0;
    for (var i = 0; i < setsOrdered.length; i++) {
      if (setsOrdered[i].enabled) {
        n++;
      }
    }
    return n;
  }

  NHeader {
    label: I18n.tr("panels.icons.title")
    description: I18n.tr("panels.icons.description")
    Layout.fillWidth: true
  }

  // Icon Sets — management list with drag-reorder + toggles
  NBox {
    Layout.fillWidth: true
    implicitHeight: setsColumn.implicitHeight + Style.margin2L
    color: Color.mSurface
    clip: true

    ColumnLayout {
      id: setsColumn
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginXS

      NText {
        text: I18n.tr("panels.icons.sets-title") + " (" + activeSetCount + " " + I18n.tr("panels.icons.sets-active") + ")"
        font.weight: Style.fontWeightMedium
      }

      NText {
        text: I18n.tr("panels.icons.priority-hint")
        pointSize: Style.fontSizeXS
        color: Color.mOutline
        visible: setsOrdered.length > 1
      }

      // Drag-reorder list (SessionMenu/ActionsSubTab pattern)
      Item {
        Layout.fillWidth: true
        implicitHeight: setsListView.contentHeight

        NListView {
          id: setsListView
          anchors.fill: parent
          spacing: Style.marginS
          interactive: false
          reserveScrollbarSpace: false
          model: root.setsOrdered

          delegate: Item {
            id: setDelegate
            width: setsListView.availableWidth
            height: setRow.height

            required property int index
            required property var modelData

            property bool dragging: false
            property int dragStartY: 0
            property int dragStartIndex: -1
            property int dragTargetIndex: -1

            Rectangle {
              anchors.fill: parent
              radius: Style.radiusM
              color: setDelegate.dragging ? Color.mSurfaceVariant : "transparent"
              border.color: setDelegate.dragging ? Color.mOutline : "transparent"
              border.width: Style.borderS

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }
            }

            RowLayout {
              id: setRow
              width: parent.width
              spacing: Style.marginS

              // Drag handle (3 horizontal lines icon)
              Rectangle {
                Layout.preferredWidth: Style.baseWidgetSize * 0.7
                Layout.preferredHeight: Style.baseWidgetSize * 0.7
                Layout.alignment: Qt.AlignVCenter
                radius: Style.radiusXS
                color: dragHandleMa.containsMouse ? Color.mSurfaceVariant : "transparent"

                Behavior on color {
                  ColorAnimation {
                    duration: Style.animationFast
                  }
                }

                ColumnLayout {
                  anchors.centerIn: parent
                  spacing: 2
                  Repeater {
                    model: 3
                    Rectangle {
                      Layout.preferredWidth: Style.baseWidgetSize * 0.28
                      Layout.preferredHeight: 2
                      radius: 1
                      color: Color.mOutline
                    }
                  }
                }

                MouseArea {
                  id: dragHandleMa
                  anchors.fill: parent
                  cursorShape: Qt.SizeVerCursor
                  hoverEnabled: true
                  preventStealing: false
                  z: 1000

                  onPressed: mouse => {
                    setDelegate.dragStartIndex = setDelegate.index;
                    setDelegate.dragTargetIndex = setDelegate.index;
                    setDelegate.dragStartY = setDelegate.y;
                    setDelegate.dragging = true;
                    setDelegate.z = 999;
                    preventStealing = true;
                  }
                  onPositionChanged: mouse => {
                    if (setDelegate.dragging) {
                      var dy = mouse.y - height / 2;
                      var newY = setDelegate.y + dy;
                      newY = Math.max(0, Math.min(newY, setsListView.contentHeight - setDelegate.height));
                      setDelegate.y = newY;
                      var targetIndex = Math.floor((newY + setDelegate.height / 2) / (setDelegate.height + Style.marginS));
                      targetIndex = Math.max(0, Math.min(targetIndex, setsListView.count - 1));
                      setDelegate.dragTargetIndex = targetIndex;
                    }
                  }
                  onReleased: {
                    preventStealing = false;
                    if (setDelegate.dragStartIndex !== -1 && setDelegate.dragTargetIndex !== -1 && setDelegate.dragStartIndex !== setDelegate.dragTargetIndex) {
                      root._commitReorder(setDelegate.dragStartIndex, setDelegate.dragTargetIndex);
                    }
                    setDelegate.dragging = false;
                    setDelegate.dragStartIndex = -1;
                    setDelegate.dragTargetIndex = -1;
                    setDelegate.z = 0;
                  }
                  onCanceled: {
                    preventStealing = false;
                    setDelegate.dragging = false;
                    setDelegate.dragStartIndex = -1;
                    setDelegate.dragTargetIndex = -1;
                    setDelegate.z = 0;
                  }
                }
              }

              // Enable/disable toggle
              Item {
                Layout.alignment: Qt.AlignVCenter
                width: setToggle.implicitWidth
                height: setToggle.implicitHeight

                NToggle {
                  id: setToggle
                  checked: modelData.enabled
                  enabled: !modelData.isFloor
                  baseSize: Style.baseWidgetSize * 0.7
                  onToggled: checked => {
                    if (checked) {
                      PluginService.enablePlugin(modelData.key);
                    } else {
                      PluginService.disablePlugin(modelData.key);
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: modelData.isFloor
                  cursorShape: Qt.ForbiddenCursor
                  hoverEnabled: true
                  onEntered: TooltipService.show(setToggle, I18n.tr("panels.icons.floor-tooltip"))
                  onExited: TooltipService.hide()
                }
              }

              // Clickable label area (filters the icon grid)
              Item {
                Layout.fillWidth: true
                Layout.preferredHeight: setLabelCol.implicitHeight
                Layout.alignment: Qt.AlignVCenter

                ColumnLayout {
                  id: setLabelCol
                  width: parent.width
                  spacing: 1

                  NText {
                    text: modelData.name + (modelData.version ? "  " + modelData.version : "")
                    color: Color.mOnSurface
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  NText {
                    text: modelData.enabled ? (modelData.iconCount + " icons") : I18n.tr("panels.icons.set-disabled")
                    color: Color.mOutline
                    pointSize: Style.fontSizeXS
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  hoverEnabled: true
                  onClicked: {
                    if (root.activeSetFilter === modelData.key) {
                      root.activeSetFilter = "";
                    } else {
                      root.activeSetFilter = modelData.key;
                    }
                  }
                }
              }
            }

            // Position binding for non-dragging state (reflow animation)
            y: {
              if (setDelegate.dragging) {
                return setDelegate.y;
              }
              var draggedIndex = -1;
              var targetIndex = -1;
              for (var i = 0; i < setsListView.count; i++) {
                var item = setsListView.itemAtIndex(i);
                if (item && item.dragging) {
                  draggedIndex = item.dragStartIndex;
                  targetIndex = item.dragTargetIndex;
                  break;
                }
              }
              if (draggedIndex !== -1 && targetIndex !== -1 && draggedIndex !== targetIndex) {
                var ci = setDelegate.index;
                if (draggedIndex < targetIndex) {
                  if (ci > draggedIndex && ci <= targetIndex) {
                    return (ci - 1) * (setDelegate.height + Style.marginS);
                  }
                } else {
                  if (ci >= targetIndex && ci < draggedIndex) {
                    return (ci + 1) * (setDelegate.height + Style.marginS);
                  }
                }
              }
              return setDelegate.index * (setDelegate.height + Style.marginS);
            }

            Behavior on y {
              enabled: !setDelegate.dragging
              NumberAnimation {
                duration: Style.animationNormal
                easing.type: Easing.OutQuad
              }
            }
          }
        }
      }
    }
  }

  // Search + filter controls
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NTextInput {
      id: searchInput
      label: I18n.tr("common.search")
      placeholderText: I18n.tr("placeholders.search-icons")
      Layout.fillWidth: true
      onTextChanged: root.query = text.trim().toLowerCase()
    }

    AtmoIconButton {
      icon: Icon.close
      baseSize: Style.baseWidgetSize * 0.8
      visible: searchInput.text !== ""
      colorBg: "transparent"
      colorBorder: "transparent"
      colorFg: Color.mOutline
      colorBgHover: Color.mSurfaceVariant
      colorBorderHover: "transparent"
      colorFgHover: Color.mOnSurface
      onClicked: {
        searchInput.text = "";
        root.query = "";
      }
    }
  }

  // Active filter chip
  RowLayout {
    visible: activeSetFilter !== ""
    spacing: Style.marginS

    NText {
      text: I18n.tr("panels.icons.filter-by")
      color: Color.mOutline
      pointSize: Style.fontSizeXS
    }

    Rectangle {
      radius: Style.radiusXS
      color: Color.mPrimary
      height: Style.baseWidgetSize * 0.55
      width: filterChipRow.implicitWidth + Style.marginS
      clip: true

      RowLayout {
        id: filterChipRow
        anchors.centerIn: parent
        spacing: Style.marginXS

        NText {
          text: root._setName(root.activeSetFilter)
          color: Color.mOnPrimary
          pointSize: Style.fontSizeXS
        }

        NText {
          text: "×"
          color: Color.mOnPrimary
          pointSize: Style.fontSizeXS
          font.weight: Style.fontWeightBold

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activeSetFilter = ""
          }
        }
      }
    }
  }

  // Count
  NText {
    text: I18n.tr("panels.icons.count", {
                    "count": filteredIcons.length,
                    "total": activeSetFilter ? root._setIconCount(root.activeSetFilter) : Object.keys(Icons.icons).length
                  })
    color: Color.mOutline
    pointSize: Style.fontSizeXS
  }

  // Icon grid (fixed-height virtualized, per-set preview)
  NGridView {
    id: iconGrid
    Layout.fillWidth: true
    implicitHeight: Math.round(440 * Style.uiScaleRatio)
    model: root.filteredIcons
    cellWidth: Math.floor(availableWidth / 8)
    cellHeight: Math.round(cellWidth * 0.6 + 32 * Style.uiScaleRatio)
    reserveScrollbarSpace: false
    reuseItems: true
    cacheBuffer: 200

    delegate: Rectangle {
      id: cell
      property string iconName: modelData
      width: iconGrid.cellWidth
      height: iconGrid.cellHeight
      color: cellMouse.containsMouse ? Color.mSurfaceVariant : "transparent"
      radius: Style.radiusS

      Behavior on color {
        ColorAnimation {
          duration: Style.animationFast
        }
      }

      MouseArea {
        id: cellMouse
        anchors.fill: parent
        hoverEnabled: true
      }

      ColumnLayout {
        anchors.centerIn: parent
        anchors.margins: Style.marginS
        spacing: Style.marginXS

        Item {
          Layout.preferredHeight: Style.marginXS
        }

        AtmoIcon {
          Layout.alignment: Qt.AlignHCenter
          icon: cell.iconName
          pointSize: Math.max(Style.fontSizeXS, Math.round(iconGrid.cellWidth * 0.18))
          color: Color.mOnSurface
        }

        NText {
          Layout.alignment: Qt.AlignHCenter
          Layout.fillWidth: true
          text: cell.iconName
          pointSize: Math.max(6, Style.fontSizeXS * 0.85)
          color: Color.mOutline
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignHCenter
          maximumLineCount: 1
        }

        Item {
          Layout.preferredHeight: Style.marginXS
        }
      }
    }
  }

  // Empty state
  Item {
    Layout.fillWidth: true
    implicitHeight: emptyLabel.visible ? emptyLabel.implicitHeight + Style.margin2L : 0
    visible: root.filteredIcons.length === 0

    NText {
      id: emptyLabel
      anchors.centerIn: parent
      text: I18n.tr("panels.icons.empty")
      color: Color.mOutline
    }
  }

  function _commitReorder(fromIndex, toIndex) {
    var newOrder = setsOrdered.slice();
    var item = newOrder.splice(fromIndex, 1)[0];
    newOrder.splice(toIndex, 0, item);
    var keys = [];
    for (var i = 0; i < newOrder.length; i++) {
      keys.push(newOrder[i].key);
    }
    IconRegistry.setSetOrder(keys);
  }

  function _setName(key) {
    var mf = PluginRegistry.getPluginManifest(key);
    if (mf && mf.name) {
      return mf.name;
    }
    var parsed = PluginRegistry.parseCompositeKey(key);
    return parsed ? parsed.pluginId : key;
  }

  function _setIconCount(key) {
    var setInfo = IconRegistry.iconSets[key];
    if (setInfo && setInfo.manifest && setInfo.manifest.icons) {
      return Object.keys(setInfo.manifest.icons).length;
    }
    return 0;
  }
}
