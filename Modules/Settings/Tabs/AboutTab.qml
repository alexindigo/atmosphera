import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root

  property string latestVersion: GitHubService.latestVersion
  property string currentVersion: UpdateService.currentVersion
  property var contributors: GitHubService.contributors

  spacing: Style.marginL

  NHeader {
    label: I18n.tr("settings.about.noctalia.section.label")
    description: I18n.tr("settings.about.noctalia.section.description")
  }

  RowLayout {
    spacing: Style.marginXL

    // Versions
    GridLayout {
      columns: 2
      rowSpacing: Style.marginXS
      columnSpacing: Style.marginS

      NText {
        text: I18n.tr("settings.about.noctalia.latest-version")
        color: Color.mOnSurface
      }

      NText {
        text: root.latestVersion
        color: Color.mOnSurface
        font.weight: Style.fontWeightBold
      }

      NText {
        text: I18n.tr("settings.about.noctalia.installed-version")
        color: Color.mOnSurface
      }

      NText {
        text: root.currentVersion
        color: Color.mOnSurface
        font.weight: Style.fontWeightBold
      }
    }

    // Update button
    NButton {
      visible: {
        if (root.latestVersion === "Unknown")
          return false

        const latest = root.latestVersion.replace("v", "").split(".")
        const current = root.currentVersion.replace("v", "").split(".")
        for (var i = 0; i < Math.max(latest.length, current.length); i++) {
          const l = parseInt(latest[i] || "0")
          const c = parseInt(current[i] || "0")
          if (l > c)
            return true

          if (l < c)
            return false
        }
        return false
      }
      icon: "download"
      text: I18n.tr("settings.about.noctalia.download-latest")
      outlined: !hovered
      fontSize: Style.fontSizeXS
      onClicked: {
        Quickshell.execDetached(["xdg-open", "https://github.com/Ly-sec/Noctalia/releases/latest"])
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL
    Layout.bottomMargin: Style.marginXL
  }

  // Contributors
  NHeader {
    label: I18n.tr("settings.about.contributors.section.label")
    description: root.contributors.length === 1 ? I18n.tr("settings.about.contributors.section.description", {
                                                            "count": root.contributors.length
                                                          }) : I18n.tr("settings.about.contributors.section.description_plural", {
                                                                         "count": root.contributors.length
                                                                       })
  }

  GridView {
    id: contributorsGrid
    Layout.alignment: Qt.AlignHCenter
    Layout.preferredWidth: cellWidth * 3 // Fixed 3 columns
    Layout.preferredHeight: {
      if (root.contributors.length === 0)
        return 0
      const columns = 3
      const rows = Math.ceil(root.contributors.length / columns)
      return rows * cellHeight
    }
    cellWidth: Math.round(Style.baseWidgetSize * 7)
    cellHeight: Math.round(Style.baseWidgetSize * 2.5)
    model: root.contributors

    delegate: Rectangle {
      width: contributorsGrid.cellWidth - Style.marginM
      height: contributorsGrid.cellHeight - Style.marginM
      radius: Style.radiusL
      color: contributorArea.containsMouse ? Color.mTertiary : Color.transparent

      Behavior on color {
        ColorAnimation {
          duration: Style.animationFast
        }
      }

      RowLayout {
        anchors.fill: parent
        anchors.margins: Style.marginS
        spacing: Style.marginM

        Item {
          Layout.alignment: Qt.AlignVCenter
          Layout.preferredWidth: Style.baseWidgetSize * 2
          Layout.preferredHeight: Style.baseWidgetSize * 2

          NImageCircled {
            imagePath: modelData.avatar_url || ""
            anchors.fill: parent
            anchors.margins: Style.marginXS
            fallbackIcon: "person"
            borderColor: contributorArea.containsMouse ? Color.mOnTertiary : Color.mPrimary
            borderWidth: Math.max(1, Style.borderM)

            Behavior on borderColor {
              ColorAnimation {
                duration: Style.animationFast
              }
            }
          }
        }

        ColumnLayout {
          spacing: Style.marginXS
          Layout.alignment: Qt.AlignVCenter
          Layout.fillWidth: true

          NText {
            text: modelData.login || "Unknown"
            font.weight: Style.fontWeightBold
            color: contributorArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          NText {
            text: (modelData.contributions || 0) + " " + ((modelData.contributions || 0) === 1 ? "commit" : "commits")
            pointSize: Style.fontSizeXS
            color: contributorArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
          }
        }
      }

      MouseArea {
        id: contributorArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (modelData.html_url)
            Quickshell.execDetached(["xdg-open", modelData.html_url])
        }
      }
    }
  }

  Item {
    Layout.fillHeight: true
  }
}
