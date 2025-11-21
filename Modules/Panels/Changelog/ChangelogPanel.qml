import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(820 * Style.uiScaleRatio)
  preferredHeight: Math.round(620 * Style.uiScaleRatio)
  panelAnchorHorizontalCenter: true
  panelAnchorVerticalCenter: true

  readonly property string currentVersion: UpdateService.changelogCurrentVersion || UpdateService.currentVersion
  readonly property string previousVersion: UpdateService.previousVersion
  readonly property bool hasPreviousVersion: previousVersion && previousVersion.length > 0
  readonly property var releaseHighlights: UpdateService.releaseHighlights || []
  readonly property string subtitleText: hasPreviousVersion ? I18n.tr("changelog.panel.subtitle.updated", {
                                                                        "previousVersion": previousVersion
                                                                      }) : I18n.tr("changelog.panel.subtitle.fresh")

  panelContent: Rectangle {
    color: Color.mSurfaceVariant
    radius: Style.radiusM
    border.color: Color.mOutline
    border.width: Style.borderS

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NIcon {
          icon: "sparkles"
          color: Color.mPrimary
          pointSize: Style.fontSizeXXL
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginXS

          NText {
            text: I18n.tr("changelog.panel.title", {
                            "version": currentVersion || UpdateService.currentVersion
                          })
            pointSize: Style.fontSizeXL
            font.weight: Style.fontWeightBold
            color: Color.mPrimary
            wrapMode: Text.WordWrap
          }

          NText {
            text: subtitleText
            color: Color.mOnSurface
            opacity: Style.opacityMedium
            wrapMode: Text.WordWrap
          }
        }

        Item {
          Layout.fillWidth: true
        }

        NIconButton {
          icon: "close"
          tooltipText: I18n.tr("tooltips.close")
          onClicked: root.close()
          Layout.alignment: Qt.AlignTop | Qt.AlignRight
          Layout.preferredHeight: Style.baseWidgetSize
          Layout.preferredWidth: Style.baseWidgetSize
        }
      }

      Rectangle {
        clip: true
        Layout.fillWidth: true
        color: Qt.alpha(Color.mPrimary, 0.08)
        radius: Style.radiusS
        border.color: Color.mPrimary
        border.width: Style.borderS

        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginS

          NText {
            text: hasPreviousVersion ? previousVersion : I18n.tr("changelog.panel.version.new-user")
            font.weight: Style.fontWeightSemiBold
            color: Color.mPrimary
          }

          NIcon {
            icon: "arrow-right"
            color: Color.mPrimary
          }

          NText {
            text: currentVersion || UpdateService.currentVersion
            font.weight: Style.fontWeightSemiBold
            color: Color.mPrimary
          }
        }
      }

      NDivider {
        Layout.fillWidth: true
      }

      NScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        verticalPolicy: ScrollBar.AsNeeded
        padding: 0

        ColumnLayout {
          width: parent.width
          spacing: Style.marginM

          NText {
            visible: UpdateService.fetchError !== ""
            text: UpdateService.fetchError
            color: Color.mError
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: releaseHighlights
            delegate: ColumnLayout {
              width: parent.width
              spacing: Style.marginS

              NText {
                text: I18n.tr("changelog.panel.section.version", {
                                "version": modelData.version || I18n.tr("system.unknown-version")
                              })
                font.weight: Style.fontWeightBold
                color: Color.mOnSurface
                pointSize: Style.fontSizeL
              }

              NText {
                visible: modelData.date && modelData.date.length > 0
                text: I18n.tr("changelog.panel.section.released", {
                                "date": root.formatReleaseDate(modelData.date)
                              })
                color: Color.mOnSurfaceVariant
                pointSize: Style.fontSizeXS
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS

                Repeater {
                  model: modelData.entries
                  delegate: NText {
                    readonly property bool isHeading: root.isEmojiHeading(modelData)
                    text: modelData.length === 0 ? "\u00A0" : modelData
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    textFormat: Text.PlainText
                    color: isHeading ? Color.mPrimary : Color.mOnSurface
                    font.weight: isHeading ? Style.fontWeightBold : Style.fontWeightMedium
                    pointSize: isHeading ? Style.fontSizeXL : Style.fontSizeM
                    Layout.fillWidth: true
                  }
                }
              }

              NDivider {
                Layout.fillWidth: true
                visible: index < releaseHighlights.length - 1
              }
            }
          }

          NText {
            visible: releaseHighlights.length === 0
            text: I18n.tr("changelog.panel.empty")
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NButton {
          Layout.fillWidth: true
          icon: "brand-discord"
          text: I18n.tr("changelog.panel.buttons.discord")
          outlined: true
          onClicked: UpdateService.openDiscord()
        }

        NButton {
          Layout.fillWidth: true
          visible: UpdateService.feedbackUrl !== ""
          icon: "forms"
          text: I18n.tr("changelog.panel.buttons.feedback")
          outlined: true
          onClicked: UpdateService.openFeedbackForm()
        }

        NButton {
          Layout.fillWidth: true
          icon: "check"
          text: I18n.tr("changelog.panel.buttons.dismiss")
          onClicked: root.close()
        }
      }
    }
  }

  function isEmojiHeading(text) {
    if (!text)
      return false;
    const trimmed = text.trim();
    if (trimmed.length === 0)
      return false;
    if (/^##\s*/i.test(trimmed))
      return false;
    const emojiHeading = /^[\u2600-\u27BF\u{1F300}-\u{1FAFF}]\s+/u;
    return emojiHeading.test(trimmed);
  }

  onClosed: {
    if (UpdateService && UpdateService.clearReleaseCache) {
      UpdateService.clearReleaseCache();
    }
    if (UpdateService && UpdateService.changelogCurrentVersion) {
      UpdateService.markChangelogSeen(UpdateService.changelogCurrentVersion);
    }
  }

  function formatReleaseDate(dateString) {
    if (!dateString || dateString.length === 0)
      return "";
    try {
      const date = new Date(dateString);
      if (isNaN(date.getTime()))
        return dateString;
      return Qt.formatDate(date, Qt.DefaultLocaleLongDate);
    } catch (error) {
      return dateString;
    }
  }
}
