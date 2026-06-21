import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Theming
import qs.Widgets

Popup {
  id: root
  modal: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
  dim: true
  anchors.centerIn: parent

  width: 560 * Style.uiScaleRatio
  height: Math.min(520 * Style.uiScaleRatio, parent.height * 0.75)
  padding: Style.marginXL

  property var screen
  property int cacheVersion: 0
  property var editColors: ({})
  property var originalColors: ({})

  Component {
    id: pickerComponent
    NColorPickerDialog {}
  }

  background: Rectangle {
    color: Color.mSurface
    radius: Style.radiusL
    border.color: Color.mOutline
    border.width: Style.borderM
  }

  Component {
    id: colorListComponent

    ColumnLayout {
      spacing: Style.marginXS

      Repeater {
        model: [
          {
            key: "mPrimary",
            name: "Primary"
          },
          {
            key: "mOnPrimary",
            name: "On Primary"
          },
          {
            key: "mSecondary",
            name: "Secondary"
          },
          {
            key: "mOnSecondary",
            name: "On Secondary"
          },
          {
            key: "mTertiary",
            name: "Tertiary"
          },
          {
            key: "mOnTertiary",
            name: "On Tertiary"
          },
          {
            key: "mError",
            name: "Error"
          },
          {
            key: "mOnError",
            name: "On Error"
          },
          {
            key: "mSurface",
            name: "Surface"
          },
          {
            key: "mOnSurface",
            name: "On Surface"
          },
          {
            key: "mSurfaceVariant",
            name: "Surface Variant"
          },
          {
            key: "mOnSurfaceVariant",
            name: "On Surface Variant"
          },
          {
            key: "mOutline",
            name: "Outline"
          },
          {
            key: "mShadow",
            name: "Shadow"
          },
          {
            key: "mHover",
            name: "Hover"
          },
          {
            key: "mOnHover",
            name: "On Hover"
          }
        ]

        delegate: Rectangle {
          required property var modelData
          Layout.fillWidth: true
          Layout.preferredHeight: 40 * Style.uiScaleRatio
          radius: Style.radiusS
          color: "transparent"

          readonly property string colorKey: modelData.key
          readonly property string colorName: modelData.name
          readonly property bool dirty: root.isDirty(colorKey)

          Rectangle {
            visible: dirty
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 2
            width: 3 * Style.uiScaleRatio
            radius: 2
            color: Color.mSecondary
          }

          RowLayout {
            anchors.fill: parent
            anchors.margins: Style.marginXS
            anchors.leftMargin: dirty ? Style.marginM : Style.marginXS
            spacing: Style.marginM

            Rectangle {
              id: swatch
              width: 28 * Style.uiScaleRatio
              height: 28 * Style.uiScaleRatio
              radius: Style.radiusS
              color: root.getColor(colorKey) || "transparent"
              border.width: 1
              border.color: Color.mOutline
            }

            NText {
              text: colorName
              color: Color.mOnSurface
              pointSize: Style.fontSizeM
              Layout.preferredWidth: 100 * Style.uiScaleRatio
              elide: Text.ElideRight
            }

            Text {
              text: colorKey
              color: Color.mOnSurfaceVariant
              font.pointSize: Style.fontSizeXS
              font.family: "monospace"
              Layout.preferredWidth: 100 * Style.uiScaleRatio
              elide: Text.ElideRight
            }

            TextField {
              id: hexField
              text: root.getColor(colorKey) || "#000000"
              Layout.preferredWidth: 110 * Style.uiScaleRatio
              Layout.preferredHeight: 28 * Style.uiScaleRatio
              font.family: "monospace"
              font.pointSize: Style.fontSizeS
              color: Color.mOnSurface
              placeholderTextColor: Color.mOnSurfaceVariant
              background: Rectangle {
                color: Color.mSurfaceVariant
                radius: Style.radiusS
                border.width: 1
                border.color: Color.mOutline
              }
              onEditingFinished: {
                var t = text.trim();
                Logger.i("ColorCustomizer", `Hex edited for key=${colorKey}, value=${t}, valid=${/^#[0-9a-fA-F]{6}$/.test(t)}`);
                if (/^#[0-9a-fA-F]{6}$/.test(t)) {
                  root.setColor(colorKey, t);
                  swatch.color = t;
                }
              }
            }

            NButton {
              icon: "color-picker"
              Layout.preferredWidth: 28 * Style.uiScaleRatio
              Layout.preferredHeight: 28 * Style.uiScaleRatio
              buttonRadius: 14 * Style.uiScaleRatio
              onClicked: {
                Logger.i("ColorCustomizer", `Picker clicked for key=${colorKey}, color=${swatch.color}, screen=${root.screen}`);
                var picker = pickerComponent.createObject(Overlay.overlay, {
                                                            selectedColor: swatch.color,
                                                            screen: root.screen
                                                          });
                picker.colorSelected.connect(function (color) {
                  root.setColor(colorKey, color.toString());
                  swatch.color = color;
                  hexField.text = String(color);
                });
                picker.open();
              }
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            propagateComposedEvents: true
            onEntered: parent.color = Qt.alpha(Color.mHover, 0.1)
            onExited: parent.color = "transparent"
          }
        }
      }
    }
  }

  onOpened: {
    var source = JSON.parse(JSON.stringify(ColorSchemeService.lastPredefinedSchemeData || {}));
    editColors = source;
    originalColors = JSON.parse(JSON.stringify(source));
  }

  onClosed: {
    editColors = ({});
  }

  Connections {
    target: Settings.data.colorSchemes
    function onDarkModeChanged() {
      colorListLoader.active = false;
      colorListLoader.active = true;
    }
  }

  contentItem: ColumnLayout {
    id: contentColumn
    width: parent.width
    spacing: Style.marginM

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        text: I18n.tr("panels.color-scheme.customize-title")
        pointSize: Style.fontSizeXL
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
        Layout.fillWidth: true
      }

      NIconButton {
        icon: "close"
        tooltipText: I18n.tr("common.close")
        onClicked: root.close()
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Color.mOutline
    }

    NToggle {
      label: I18n.tr("tooltips.switch-to-dark-mode")
      description: I18n.tr("panels.color-scheme.dark-mode-switch-description")
      checked: Settings.data.colorSchemes.darkMode
      onToggled: checked => {
        Settings.data.colorSchemes.darkMode = checked;
        root.cacheVersion++;
      }
    }

    NScrollView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      horizontalPolicy: ScrollBar.AlwaysOff
      gradientColor: Color.mSurface

      Loader {
        id: colorListLoader
        width: parent.width
        active: true
        sourceComponent: colorListComponent
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Color.mOutline
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NButton {
        text: I18n.tr("common.reset")
        icon: "refresh"
        outlined: true
        onClicked: root.resetColors()
      }

      Item {
        Layout.fillWidth: true
      }

      NButton {
        text: I18n.tr("common.apply")
        icon: "check"
        onClicked: root.applyColors()
      }

      NButton {
        text: I18n.tr("common.close")
        outlined: true
        onClicked: root.close()
      }
    }
  }

  function isDirty(key) {
    var _ = cacheVersion;
    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light";
    if (!editColors || !editColors[mode] || !originalColors || !originalColors[mode])
      return false;
    return editColors[mode][key] !== originalColors[mode][key];
  }

  function getColor(key) {
    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light";
    if (!editColors || !editColors[mode])
      return null;
    return editColors[mode][key] || null;
  }

  function setColor(key, value) {
    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light";
    if (!editColors || !editColors[mode])
      return;
    editColors[mode][key] = value;
    cacheVersion++;
  }

  function applyColors() {
    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light";
    if (editColors && editColors[mode]) {
      ColorSchemeService.writeColorsToDisk(editColors[mode]);
      ColorSchemeService.lastPredefinedSchemeData[mode] = JSON.parse(JSON.stringify(editColors[mode]));
    }
    var fullData = {
      dark: (editColors && editColors["dark"]) || (ColorSchemeService.lastPredefinedSchemeData && ColorSchemeService.lastPredefinedSchemeData["dark"]) || {},
      light: (editColors && editColors["light"]) || (ColorSchemeService.lastPredefinedSchemeData && ColorSchemeService.lastPredefinedSchemeData["light"]) || {}
    };
    ColorSchemeService.saveCustomScheme(fullData);
    Settings.data.colorSchemes.predefinedScheme = "Custom";
    originalColors = JSON.parse(JSON.stringify(editColors));
    cacheVersion++;
    ColorSchemeService.loadColorSchemes();
  }

  function resetColors() {
    var schemeName = Settings.data.colorSchemes.predefinedScheme;
    if (schemeName) {
      ColorSchemeService.applyScheme(schemeName);
      var source = JSON.parse(JSON.stringify(ColorSchemeService.lastPredefinedSchemeData || {}));
      editColors = source;
      originalColors = JSON.parse(JSON.stringify(source));
    }
    colorListLoader.active = false;
    colorListLoader.active = true;
  }
}
