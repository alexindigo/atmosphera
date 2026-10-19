import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.Files
import qs.Widgets

RowLayout {
  id: root
  required property var request
  readonly property bool editing: pathField.visible
  readonly property var pathParts: request.browser.currentPath === "/" ? ["/"] : request.browser.currentPath.split("/").filter(part => part !== "")
  readonly property var breadcrumbItems: {
    var items = [];
    var segments = pathParts.slice(-3);
    var leading = pathParts.length > 3;
    if (leading)
      items.push({
                   kind: "ellipsis",
                   text: "…"
                 });
    for (var i = 0; i < segments.length; ++i) {
      if (leading || i > 0)
        items.push({
                     kind: "separator",
                     text: "›"
                   });
      items.push({
                   kind: "segment",
                   text: segments[i]
                 });
    }
    return items;
  }
  signal listingFocusRequested
  spacing: Style.marginXS

  function editPath(initial) {
    pathField.visible = true;
    pathField.text = initial === undefined ? request.browser.currentPath : initial;
    pathField.inputItem.forceActiveFocus();
    if (initial === undefined)
      pathField.inputItem.selectAll();
  }
  function leavePathEditing() {
    pathField.visible = false;
    listingFocusRequested();
  }
  function breadcrumbGeometry() {
    var gaps = [];
    var previous = null;
    var separator = null;
    for (var i = 0; i < crumbParts.count; ++i) {
      var delegate = crumbParts.itemAt(i);
      if (!delegate || !delegate.visible)
        continue;
      var part = delegate.geometry();
      if (part.kind === "separator") {
        separator = part;
      } else {
        if (part.kind === "segment" && separator && previous !== null)
          gaps.push({
                      before: separator.left - previous,
                      after: part.left - separator.right,
                      clipped: part.width + 0.5 < part.naturalWidth
                    });
        previous = part.right;
        separator = null;
      }
    }
    return gaps;
  }

  ChooserButton {
    icon: Icon.chevronLeft
    tooltipText: I18n.tr("widgets.file-picker.back")
    enabled: root.request.browser.canBack
    onClicked: root.request.browser.back()
  }
  ChooserButton {
    icon: Icon.chevronRight
    tooltipText: I18n.tr("widgets.file-picker.forward")
    enabled: root.request.browser.canForward
    onClicked: root.request.browser.forward()
  }
  ChooserButton {
    icon: Icon.filepickerArrowUp
    tooltipText: I18n.tr("widgets.file-picker.parent-folder")
    onClicked: root.request.browser.up()
  }
  Item {
    Layout.fillWidth: true
    Layout.minimumWidth: 100 * Style.uiScaleRatio
    implicitHeight: Style.baseWidgetSize * 1.1 * Style.uiScaleRatio

    Rectangle {
      anchors.fill: parent
      color: "transparent"
      radius: Style.iRadiusS
      border.color: AtmoColor.mPrimary
      border.width: pathButton.activeFocus ? Style.borderM : 0
    }
    Item {
      id: pathButton
      anchors.fill: parent
      visible: !root.editing
      activeFocusOnTab: true
      Accessible.role: Accessible.Button
      Accessible.name: root.request.browser.currentPath
      Keys.onReturnPressed: root.editPath()
      Keys.onSpacePressed: root.editPath()
      RowLayout {
        id: breadcrumbLine
        anchors.fill: parent
        anchors.margins: Style.marginXS
        spacing: Style.marginXS
        Repeater {
          id: crumbParts
          model: root.breadcrumbItems
          NText {
            required property var modelData
            Layout.fillWidth: modelData.kind === "segment" && breadcrumbLine.implicitWidth > breadcrumbLine.width
            text: modelData.text
            color: modelData.kind === "segment" ? AtmoColor.mOnSurface : AtmoColor.mOnSurfaceVariant
            pointSize: Style.fontSizeM
            elide: Text.ElideMiddle
            function geometry() {
              return {
                kind: modelData.kind,
                left: mapToItem(root, 0, 0).x,
                right: mapToItem(root, width, 0).x,
                width: width,
                naturalWidth: implicitWidth
              };
            }
          }
        }
        Item {
          Layout.fillWidth: true
        }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: root.editPath()
      }
    }
    ChooserTextField {
      id: pathField
      anchors.fill: parent
      visible: false
      fontSize: Style.fontSizeM
      accessibleName: I18n.tr("widgets.file-picker.location")
      onAccepted: {
        root.request.browser.navigate(text);
        root.leavePathEditing();
      }
    }
  }
  ChooserButton {
    icon: Icon.filepickerRefresh
    tooltipText: I18n.tr("widgets.file-picker.refresh")
    onClicked: root.request.browser.refresh()
  }
  ChooserComboBox {
    minimumWidth: 150
    accessibleName: I18n.tr("widgets.file-picker.sort-by")
    model: [
      {
        key: "name",
        name: I18n.tr("widgets.file-picker.name")
      },
      {
        key: "size",
        name: I18n.tr("widgets.file-picker.size")
      },
      {
        key: "type",
        name: I18n.tr("widgets.file-picker.type")
      },
      {
        key: "modified",
        name: I18n.tr("widgets.file-picker.modified")
      }
    ]
    currentKey: root.request.browser.sortKey
    onSelected: key => root.request.browser.sortKey = key
  }
  ChooserButton {
    text: root.request.browser.sortDescending ? "↓" : "↑"
    tooltipText: I18n.tr("widgets.file-picker.reverse-sort")
    onClicked: root.request.browser.sortDescending = !root.request.browser.sortDescending
  }
  ChooserButton {
    icon: Icon.filepickerEye
    tooltipText: I18n.tr("widgets.file-picker.show-hidden")
    textColor: root.request.browser.showHidden ? AtmoColor.mPrimary : AtmoColor.mOnSurfaceVariant
    onClicked: root.request.browser.showHidden = !root.request.browser.showHidden
  }
  ChooserButton {
    icon: Icon.filepickerLayoutGrid
    tooltipText: I18n.tr("widgets.file-picker.grid-view")
    textColor: root.request.viewMode === "grid" ? AtmoColor.mPrimary : AtmoColor.mOnSurfaceVariant
    onClicked: root.request.viewMode = "grid"
  }
  ChooserButton {
    icon: Icon.filepickerList
    tooltipText: I18n.tr("widgets.file-picker.list-view")
    textColor: root.request.viewMode === "list" ? AtmoColor.mPrimary : AtmoColor.mOnSurfaceVariant
    onClicked: root.request.viewMode = "list"
  }
}
