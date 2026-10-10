import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Setup wizard — Bindings step content (chrome comes from WizardPanel)
ColumnLayout {
  id: root
  property string selection: "none"
  property var select: null
  property bool selectionEnabled: true
  spacing: Style.marginM

  Repeater {
    model: [
      {
        "value": "none",
        "label": I18n.tr("setup.bindings.none-label"),
        "description": I18n.tr("setup.bindings.none-description")
      },
      {
        "value": "macos",
        "label": I18n.tr("setup.bindings.macos-label"),
        "description": I18n.tr("setup.bindings.macos-description")
      }
    ]
    delegate: Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 80
      radius: Style.radiusL
      color: root.selection === modelData.value ? (AtmoColor.mPrimaryContainer || "transparent") : (AtmoColor.mSurfaceVariant || "transparent")
      border.color: root.selection === modelData.value ? (AtmoColor.mPrimary || "transparent") : (AtmoColor.mOutline || "transparent")
      border.width: root.selection === modelData.value ? 2 : 1

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: root.selectionEnabled
        onClicked: {
          if (typeof root.select === "function")
            root.select(modelData.value);
        }
      }

      RowLayout {
        anchors.fill: parent
        anchors.margins: Style.marginL
        spacing: Style.marginM

        Rectangle {
          width: 20
          height: 20
          radius: width / 2
          color: "transparent"
          border.color: root.selection === modelData.value ? AtmoColor.mPrimary : AtmoColor.mOutline
          border.width: 2

          Rectangle {
            anchors.centerIn: parent
            width: 10
            height: 10
            radius: width / 2
            color: AtmoColor.mPrimary
            visible: root.selection === modelData.value
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginXS

          NText {
            text: modelData.label
            pointSize: Style.fontSizeM
            font.weight: Style.fontWeightBold
            color: AtmoColor.mPrimary
          }

          NText {
            text: modelData.description
            pointSize: Style.fontSizeS
            color: AtmoColor.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }
        }
      }
    }
  }

  Item {
    Layout.fillWidth: true
    Layout.fillHeight: true
  }
}
