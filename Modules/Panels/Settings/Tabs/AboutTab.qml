import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Noctalia
import qs.Widgets

ColumnLayout {
  id: root

  property string latestVersion: GitHubService.latestVersion
  property string currentVersion: UpdateService.currentVersion
  property var contributors: GitHubService.contributors

  readonly property int topContributorsCount: 20

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
          return false;

        const latest = root.latestVersion.replace("v", "").split(".");
        const current = root.currentVersion.replace("v", "").split(".");
        for (var i = 0; i < Math.max(latest.length, current.length); i++) {
          const l = parseInt(latest[i] || "0");
          const c = parseInt(current[i] || "0");
          if (l > c)
            return true;

          if (l < c)
            return false;
        }
        return false;
      }
      icon: "download"
      text: I18n.tr("settings.about.noctalia.download-latest")
      outlined: !hovered
      fontSize: Style.fontSizeXS
      onClicked: {
        Quickshell.execDetached(["xdg-open", "https://github.com/Ly-sec/Noctalia/releases/latest"]);
      }
    }
  }

  // Ko-fi support button
  Rectangle {
    Layout.alignment: Qt.AlignHCenter
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
    width: supportRow.implicitWidth + Style.marginXL
    height: supportRow.implicitHeight + Style.marginM
    radius: Style.radiusS
    color: supportArea.containsMouse ? Qt.alpha(Color.mOnSurface, 0.05) : Color.transparent
    border.width: 0

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
      }
    }

    RowLayout {
      id: supportRow
      anchors.centerIn: parent
      spacing: Style.marginS

      NText {
        text: I18n.tr("settings.about.support")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurface
        opacity: supportArea.containsMouse ? Style.opacityFull : Style.opacityMedium
      }

      NIcon {
        icon: supportArea.containsMouse ? "heart-filled" : "heart"
        pointSize: 14
        color: Color.mOnSurface
        opacity: supportArea.containsMouse ? Style.opacityFull : Style.opacityMedium
      }
    }

    MouseArea {
      id: supportArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        Quickshell.execDetached(["xdg-open", "https://ko-fi.com/lysec"]);
        ToastService.showNotice(I18n.tr("settings.about.support"), I18n.tr("toast.kofi.opened"));
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXXXL
    Layout.bottomMargin: Style.marginL
  }

  // Contributors
  NHeader {
    label: I18n.tr("settings.about.contributors.section.label")
    description: root.contributors.length === 1 ? I18n.tr("settings.about.contributors.section.description", {
                                                            "count": root.contributors.length
                                                          }) : I18n.tr("settings.about.contributors.section.description_plural", {
                                                                         "count": root.contributors.length
                                                                       })
    enableDescriptionRichText: true
  }

  // Top 20 contributors with full cards (avoids GridView shader crashes on Qt 6.8)
  Flow {
    id: topContributorsFlow
    Layout.alignment: Qt.AlignHCenter
    Layout.preferredWidth: Math.round(Style.baseWidgetSize * 14)
    spacing: Style.marginM

    Repeater {
      model: Math.min(root.contributors.length, root.topContributorsCount)

      delegate: Rectangle {
        width: Math.round(Style.baseWidgetSize * 6.8)
        height: Math.round(Style.baseWidgetSize * 2.3)
        radius: Style.radiusM
        color: contributorArea.containsMouse ? Color.mHover : Color.transparent
        border.width: 1
        border.color: contributorArea.containsMouse ? Color.mPrimary : Color.mOutline

        Behavior on color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }

        Behavior on border.color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }

        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          // Avatar container with rectangular design (modern, no shader issues)
          Item {
            id: wrapper
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Style.baseWidgetSize * 1.8
            Layout.preferredHeight: Style.baseWidgetSize * 1.8

            property bool isRounded: false

            // Background and image container
            Item {
              anchors.fill: parent

              // Simple circular image (pre-rendered, no shaders)
              Image {
                anchors.fill: parent
                source: {
                  // Try cached circular version first
                  var username = root.contributors[index].login;
                  var cached = GitHubService.cachedCircularAvatars[username];
                  if (cached) {
                    wrapper.isRounded = true;
                    return cached;
                  }

                  // Fall back to original avatar URL
                  return root.contributors[index].avatar_url || "";
                }
                fillMode: Image.PreserveAspectFit // Fit since image is already circular with transparency
                mipmap: true
                smooth: true
                asynchronous: true
                visible: root.contributors[index].avatar_url !== undefined && root.contributors[index].avatar_url !== ""
                opacity: status === Image.Ready ? 1.0 : 0.0

                Behavior on opacity {
                  NumberAnimation {
                    duration: Style.animationFast
                  }
                }
              }

              // Fallback icon
              NIcon {
                anchors.centerIn: parent
                visible: !root.contributors[index].avatar_url || root.contributors[index].avatar_url === ""
                icon: "person"
                pointSize: Style.fontSizeL
                color: Color.mPrimary
              }
            }

            Rectangle {
              visible: wrapper.isRounded
              anchors.fill: parent
              color: Color.transparent
              radius: width * 0.5
              border.width: Style.borderM
              border.color: Color.mPrimary
            }
          }

          // Info column
          ColumnLayout {
            spacing: 2
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true

            NText {
              text: root.contributors[index].login || "Unknown"
              font.weight: Style.fontWeightBold
              color: contributorArea.containsMouse ? Color.mOnHover : Color.mOnSurface
              elide: Text.ElideRight
              Layout.fillWidth: true
              pointSize: Style.fontSizeS
            }

            RowLayout {
              spacing: Style.marginXS
              Layout.fillWidth: true

              NIcon {
                icon: "git-commit"
                pointSize: Style.fontSizeXS
                color: contributorArea.containsMouse ? Color.mOnHover : Color.mOnSurfaceVariant
              }

              NText {
                text: `${(root.contributors[index].contributions || 0).toString()} commits`
                pointSize: Style.fontSizeXS
                color: contributorArea.containsMouse ? Color.mOnHover : Color.mOnSurfaceVariant
              }
            }
          }

          // Hover indicator
          NIcon {
            Layout.alignment: Qt.AlignVCenter
            icon: "arrow-right"
            pointSize: Style.fontSizeS
            color: Color.mPrimary
            opacity: contributorArea.containsMouse ? 1.0 : 0.0

            Behavior on opacity {
              NumberAnimation {
                duration: Style.animationFast
              }
            }
          }
        }

        MouseArea {
          id: contributorArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.contributors[index].html_url)
              Quickshell.execDetached(["xdg-open", root.contributors[index].html_url]);
          }
        }
      }
    }
  }

  // Remaining contributors (simple text links)
  Flow {
    id: remainingContributorsFlow
    visible: root.contributors.length > root.topContributorsCount
    Layout.alignment: Qt.AlignHCenter
    Layout.preferredWidth: Math.round(Style.baseWidgetSize * 14)
    Layout.topMargin: Style.marginL
    spacing: Style.marginS

    Repeater {
      model: Math.max(0, root.contributors.length - root.topContributorsCount)

      delegate: Rectangle {
        width: nameText.implicitWidth + Style.marginM * 2
        height: nameText.implicitHeight + Style.marginS * 2
        radius: Style.radiusS
        color: nameArea.containsMouse ? Color.mHover : Color.transparent
        border.width: Style.borderS
        border.color: nameArea.containsMouse ? Color.mPrimary : Color.mOutline

        Behavior on color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }

        Behavior on border.color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }

        NText {
          id: nameText
          anchors.centerIn: parent
          text: root.contributors[index + root.topContributorsCount].login || "Unknown"
          pointSize: Style.fontSizeXS
          color: nameArea.containsMouse ? Color.mOnHover : Color.mOnSurface
          font.weight: Style.fontWeightMedium

          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
            }
          }
        }

        MouseArea {
          id: nameArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.contributors[index + root.topContributorsCount].html_url)
              Quickshell.execDetached(["xdg-open", root.contributors[index + root.topContributorsCount].html_url]);
          }
        }
      }
    }
  }
}
