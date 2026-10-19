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

  ScrollView {
    anchors.fill: parent
    anchors.margins: Style.marginM
    contentWidth: availableWidth
    clip: true
    ColumnLayout {
      width: parent.width
      spacing: Style.marginXS
      Repeater {
        model: FilePlaces.places
        ChooserButton {
          required property var modelData
          Layout.fillWidth: true
          horizontalAlignment: Qt.AlignLeft
          text: modelData.name
          icon: modelData.kind === "home" ? Icon.filepickerHome : Icon.filepickerFolder
          textColor: root.browser.currentPath === modelData.path ? AtmoColor.mPrimary : AtmoColor.mOnSurface
          onClicked: root.browser.navigate(modelData.path)
        }
      }
      Rectangle { Layout.fillWidth: true; Layout.topMargin: Style.marginM; Layout.bottomMargin: Style.marginM; implicitHeight: Style.borderS; color: AtmoColor.mOutline }
      NText { text: I18n.tr("widgets.file-picker.recent"); pointSize: Style.fontSizeS; color: AtmoColor.mOnSurfaceVariant; Layout.leftMargin: Style.marginM }
      Repeater {
        model: FilePlaces.recentFiles
        ChooserButton {
          required property var modelData
          Layout.fillWidth: true
          horizontalAlignment: Qt.AlignLeft
          text: modelData.name
          tooltipText: modelData.path
          icon: FileTypes.icon(modelData.name, false)
          onClicked: root.browser.navigate(root.browser.parentPath(modelData.path))
        }
      }
      NText { text: I18n.tr("widgets.file-picker.recent-locations"); pointSize: Style.fontSizeS; color: AtmoColor.mOnSurfaceVariant; Layout.leftMargin: Style.marginM; Layout.topMargin: Style.marginL }
      Repeater {
        model: FileChooserMemory.recentLocations
        ChooserButton {
          required property string modelData
          Layout.fillWidth: true
          horizontalAlignment: Qt.AlignLeft
          text: modelData.slice(modelData.lastIndexOf("/") + 1) || "/"
          tooltipText: modelData
          icon: Icon.filepickerFolder
          onClicked: root.browser.navigate(modelData)
        }
      }
      NText { visible: FilePlaces.removable.length > 0; text: I18n.tr("widgets.file-picker.removable"); pointSize: Style.fontSizeS; color: AtmoColor.mOnSurfaceVariant; Layout.leftMargin: Style.marginM; Layout.topMargin: Style.marginL }
      Repeater {
        model: FilePlaces.removable
        ChooserButton {
          required property var modelData
          Layout.fillWidth: true
          text: modelData.name
          horizontalAlignment: Qt.AlignLeft
          icon: Icon.filepickerFolder
          onClicked: root.browser.navigate(modelData.path)
        }
      }
    }
  }
}
