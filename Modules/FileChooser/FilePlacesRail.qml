import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Files
import qs.Widgets

Rectangle {
  id: root
  required property var browser
  color: AtmoColor.mSurfaceVariant
  implicitWidth: 190 * Style.uiScaleRatio
  function recentRows() {
    var rows = [];
    for (var i = 0; i < recentRepeater.count; i++) {
      var item = recentRepeater.itemAt(i);
      if (item)
        rows.push({name: item.text, path: item.tooltipText});
    }
    return rows;
  }

  ScrollView {
    anchors.fill: parent
    anchors.margins: Style.marginM
    contentWidth: availableWidth
    clip: true
    ScrollBar.vertical: ScrollBar { Accessible.name: I18n.tr("widgets.file-picker.scroll-places") }
    ScrollBar.horizontal: ScrollBar { Accessible.name: I18n.tr("widgets.file-picker.scroll-places") }
    ColumnLayout {
      width: parent.width
      spacing: Style.marginXS
      Repeater {
        model: FilePlaces.places
        FilePlaceButton {
          required property var modelData
          Layout.fillWidth: true
          text: modelData.name
          icon: modelData.kind === "home" ? Icon.filepickerHome : Icon.filepickerFolder
          selected: root.browser.currentPath === modelData.path
          onClicked: root.browser.navigate(modelData.path)
        }
      }
      Rectangle { visible: FilePlaces.recentFolders.length > 0 || FilePlaces.removable.length > 0; Layout.fillWidth: true; Layout.topMargin: Style.marginM; Layout.bottomMargin: Style.marginM; implicitHeight: Style.borderS; color: AtmoColor.mOutline }
      NText { visible: FilePlaces.recentFolders.length > 0; text: I18n.tr("widgets.file-picker.recent"); pointSize: Style.fontSizeS; color: AtmoColor.mOnSurfaceVariant; Layout.leftMargin: Style.marginM }
      Repeater {
        id: recentRepeater
        model: FilePlaces.recentFolders
        FilePlaceButton {
          required property var modelData
          Layout.fillWidth: true
          text: modelData.name
          icon: Icon.filepickerFolder
          tooltipText: modelData.path
          selected: root.browser.currentPath === modelData.path
          onClicked: root.browser.navigate(modelData.path)
        }
      }
      NText { visible: FilePlaces.removable.length > 0; text: I18n.tr("widgets.file-picker.removable"); pointSize: Style.fontSizeS; color: AtmoColor.mOnSurfaceVariant; Layout.leftMargin: Style.marginM; Layout.topMargin: Style.marginL }
      Repeater {
        model: FilePlaces.removable
        FilePlaceButton {
          required property var modelData
          Layout.fillWidth: true
          text: modelData.name
          selected: root.browser.currentPath === modelData.path
          icon: Icon.filepickerFolder
          onClicked: root.browser.navigate(modelData.path)
        }
      }
    }
  }
}
