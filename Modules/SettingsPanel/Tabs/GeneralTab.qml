import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root

  // Profile section
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginL * scaling

    // Avatar preview
    NImageCircled {
      width: 108 * scaling
      height: 108 * scaling
      imagePath: Settings.data.general.avatarImage
      fallbackIcon: "person"
      borderColor: Color.mPrimary
      borderWidth: Math.max(1, Style.borderM * scaling)
      Layout.alignment: Qt.AlignTop
    }

    NTextInput {
      Layout.fillWidth: true
      label: `${Quickshell.env("USER") || "user"}'s profile picture`
      description: "Your profile picture that appears throughout the interface."
      text: Settings.data.general.avatarImage
      placeholderText: "/home/user/.face"
      onEditingFinished: {
        Settings.data.general.avatarImage = text
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }

  // User Interface
  ColumnLayout {
    spacing: Style.marginL * scaling
    Layout.fillWidth: true

    NText {
      text: "User Interface"
      font.pointSize: Style.fontSizeXXL * scaling
      font.weight: Style.fontWeightBold
      color: Color.mSecondary
      Layout.bottomMargin: Style.marginS * scaling
    }

    NToggle {
      label: "Dim Desktop"
      description: "Dim the desktop when panels or menus are open."
      checked: Settings.data.general.dimDesktop
      onToggled: checked => Settings.data.general.dimDesktop = checked
    }

    ColumnLayout {
      spacing: Style.marginXXS * scaling
      Layout.fillWidth: true

      NLabel {
        label: "Border radius"
        description: "Adjust the rounded border of all UI elements."
      }

      RowLayout {
        NSlider {
          Layout.fillWidth: true
          from: 0
          to: 1
          stepSize: 0.01
          value: Settings.data.general.radiusRatio
          onMoved: Settings.data.general.radiusRatio = value
          cutoutColor: Color.mSurface
        }

        NText {
          text: Math.floor(Settings.data.general.radiusRatio * 100) + "%"
          Layout.alignment: Qt.AlignVCenter
          Layout.leftMargin: Style.marginS * scaling
          color: Color.mOnSurface
        }
      }
    }

    // Animation Speed
    ColumnLayout {
      spacing: Style.marginXXS * scaling
      Layout.fillWidth: true

      NLabel {
        label: "Animation Speed"
        description: "Adjust global animation speed."
      }

      RowLayout {
        NSlider {
          Layout.fillWidth: true
          from: 0.1
          to: 2.0
          stepSize: 0.01
          value: Settings.data.general.animationSpeed
          onMoved: Settings.data.general.animationSpeed = value
          cutoutColor: Color.mSurface
        }

        NText {
          text: Math.round(Settings.data.general.animationSpeed * 100) + "%"
          Layout.alignment: Qt.AlignVCenter
          Layout.leftMargin: Style.marginS * scaling
          color: Color.mOnSurface
        }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }

  // Dock
  ColumnLayout {
    spacing: Style.marginL * scaling
    Layout.fillWidth: true
    NText {
      text: "Screen Corners"
      font.pointSize: Style.fontSizeXXL * scaling
      font.weight: Style.fontWeightBold
      color: Color.mSecondary
      Layout.bottomMargin: Style.marginS * scaling
    }

    NToggle {
      label: "Show Screen Corners"
      description: "Display rounded corners on the edge of the screen."
      checked: Settings.data.general.showScreenCorners
      onToggled: checked => Settings.data.general.showScreenCorners = checked
    }

    ColumnLayout {
      spacing: Style.marginXXS * scaling
      Layout.fillWidth: true

      NLabel {
        label: "Screen Corners Radius"
        description: "Adjust the rounded corners of the screen."
      }

      RowLayout {
        NSlider {
          Layout.fillWidth: true
          from: 0
          to: 2
          stepSize: 0.01
          value: Settings.data.general.screenRadiusRatio
          onMoved: Settings.data.general.screenRadiusRatio = value
          cutoutColor: Color.mSurface
        }

        NText {
          text: Math.floor(Settings.data.general.screenRadiusRatio * 100) + "%"
          Layout.alignment: Qt.AlignVCenter
          Layout.leftMargin: Style.marginS * scaling
          color: Color.mOnSurface
        }
      }
    }
  }
  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }

  // Fonts
  ColumnLayout {
    spacing: Style.marginL * scaling
    Layout.fillWidth: true
    NText {
      text: "Fonts"
      font.pointSize: Style.fontSizeXXL * scaling
      font.weight: Style.fontWeightBold
      color: Color.mSecondary
      Layout.bottomMargin: Style.marginS * scaling
    }

    // Font configuration section
    ColumnLayout {
      spacing: Style.marginL * scaling
      Layout.fillWidth: true

      NSearchableComboBox {
        label: "Default Font"
        description: "Main font used throughout the interface."
        model: FontService.availableFonts
        currentKey: Settings.data.ui.fontDefault
        placeholder: "Select default font..."
        searchPlaceholder: "Search fonts..."
        popupHeight: 420 * scaling
        minimumWidth: 300 * scaling
        onSelected: function (key) {
          Settings.data.ui.fontDefault = key
        }
      }

      NSearchableComboBox {
        label: "Fixed Width Font"
        description: "Monospace font used for terminal and code display."
        model: FontService.monospaceFonts
        currentKey: Settings.data.ui.fontFixed
        placeholder: "Select monospace font..."
        searchPlaceholder: "Search monospace fonts..."
        popupHeight: 320 * scaling
        minimumWidth: 300 * scaling
        onSelected: function (key) {
          Settings.data.ui.fontFixed = key
        }
      }

      NSearchableComboBox {
        label: "Billboard Font"
        description: "Large font used for clocks and prominent displays."
        model: FontService.displayFonts
        currentKey: Settings.data.ui.fontBillboard
        placeholder: "Select display font..."
        searchPlaceholder: "Search display fonts..."
        popupHeight: 320 * scaling
        minimumWidth: 300 * scaling
        onSelected: function (key) {
          Settings.data.ui.fontBillboard = key
        }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }
}
