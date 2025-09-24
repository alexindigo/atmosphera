import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root

  NHeader {
    label: I18n.tr("settings.general.profile.section.label")
    description: I18n.tr("settings.general.profile.section.description")
  }

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

    NTextInputButton {
      label: I18n.tr("settings.general.profile.picture.label", {
                       "user": Quickshell.env("USER" || "User")
                     })
      description: I18n.tr("settings.general.profile.picture.description")
      text: Settings.data.general.avatarImage
      placeholderText: "/home/user/.face"
      buttonIcon: "photo"
      buttonTooltip: "Browse for avatar image"
      onInputEditingFinished: Settings.data.general.avatarImage = text
      onButtonClicked: {
        filePicker.open()
      }
    }
  }

  NFilePicker {
    id: filePicker
    pickerType: "file"
    title: I18n.tr("settings.general.profile.select-avatar") //Select avatar image"
    initialPath: Settings.data.general.avatarImage.substr(0, Settings.data.general.avatarImage.lastIndexOf("/")) || Quickshell.env("HOME")
    nameFilters: ["Image files (*.jpg *.jpeg *.png *.gif *.pnm *.bmp *.face)", "All files (*)"]
    onAccepted: paths => Settings.data.general.avatarImage = paths[0]
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

    NHeader {
      label: I18n.tr("settings.general.ui.section.label")
      description: I18n.tr("settings.general.ui.section.description")
    }

    NToggle {
      label: I18n.tr("settings.general.ui.dim-desktop.label")
      description: I18n.tr("settings.general.ui.dim-desktop.description")
      checked: Settings.data.general.dimDesktop
      onToggled: checked => Settings.data.general.dimDesktop = checked
    }

    ColumnLayout {
      spacing: Style.marginXXS * scaling
      Layout.fillWidth: true

      NLabel {
        label: I18n.tr("settings.general.ui.border-radius.label")
        description: I18n.tr("settings.general.ui.border-radius.description")
      }

      NValueSlider {
        Layout.fillWidth: true
        from: 0
        to: 1
        stepSize: 0.01
        value: Settings.data.general.radiusRatio
        onMoved: value => Settings.data.general.radiusRatio = value
        text: Math.floor(Settings.data.general.radiusRatio * 100) + "%"
      }
    }

    // Animation Speed
    ColumnLayout {
      spacing: Style.marginXXS * scaling
      Layout.fillWidth: true

      NLabel {
        label: "Animation speed"
        description: "Adjust global animation speed."
      }

      NValueSlider {
        Layout.fillWidth: true
        from: 0.1
        to: 2.0
        stepSize: 0.01
        value: Settings.data.general.animationSpeed
        onMoved: value => Settings.data.general.animationSpeed = value
        text: Math.round(Settings.data.general.animationSpeed * 100) + "%"
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

    NHeader {
      label: "Screen corners"
      description: "Customize screen corner rounding and visual effects."
    }

    NToggle {
      label: "Show screen corners"
      description: "Display rounded corners on the edge of the screen."
      checked: Settings.data.general.showScreenCorners
      onToggled: checked => Settings.data.general.showScreenCorners = checked
    }

    NToggle {
      label: "Solid black corners"
      description: "Use solid black instead of the bar background color."
      checked: Settings.data.general.forceBlackScreenCorners
      onToggled: checked => Settings.data.general.forceBlackScreenCorners = checked
    }

    ColumnLayout {
      spacing: Style.marginXXS * scaling
      Layout.fillWidth: true

      NLabel {
        label: "Screen corners radius"
        description: "Adjust the rounded corners of the screen."
      }

      NValueSlider {
        Layout.fillWidth: true
        from: 0
        to: 2
        stepSize: 0.01
        value: Settings.data.general.screenRadiusRatio
        onMoved: value => Settings.data.general.screenRadiusRatio = value
        text: Math.floor(Settings.data.general.screenRadiusRatio * 100) + "%"
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

    NHeader {
      label: "Fonts"
      description: "Choose the fonts used throughout the interface."
    }

    // Font configuration section
    ColumnLayout {
      spacing: Style.marginL * scaling
      Layout.fillWidth: true

      NSearchableComboBox {
        label: "Default font"
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
        label: "Monospaced font"
        description: "Monospaced font used for numbers and stats display."
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
        label: "Accent font"
        description: "Large font used for prominent displays."
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
