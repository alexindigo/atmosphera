import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root

  // Process to check if swww is installed
  Process {
    id: swwwCheck
    command: ["which", "swww"]
    running: false

    onExited: function (exitCode) {
      if (exitCode === 0) {
        // SWWW exists, enable it
        Settings.data.wallpaper.swww.enabled = true
        WallpaperService.startSWWWDaemon()
        ToastService.showNotice("Swww", "Enabled")
      } else {
        // SWWW not found
        ToastService.showWarning("Swww", "Not installed")
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  NTextInput {
    label: "Wallpaper Directory"
    description: "Path to your wallpaper directory."
    text: Settings.data.wallpaper.directory
    Layout.fillWidth: true
    onEditingFinished: {
      Settings.data.wallpaper.directory = text
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }

  ColumnLayout {
    spacing: Style.marginL * scaling
    Layout.fillWidth: true

    NText {
      text: "Automation"
      font.pointSize: Style.fontSizeXXL * scaling
      font.weight: Style.fontWeightBold
      color: Color.mSecondary
    }

    // Random Wallpaper
    NToggle {
      label: "Random Wallpaper"
      description: "Automatically select random wallpapers from the folder."
      checked: Settings.data.wallpaper.isRandom
      onToggled: checked => {
                   Settings.data.wallpaper.isRandom = checked
                 }
    }

    // Interval (slider + H:M inputs)
    ColumnLayout {
      RowLayout {
        NLabel {
          label: "Wallpaper Interval"
          description: "How often to change wallpapers automatically."
          Layout.fillWidth: true
        }

        NText {
          // Show friendly H:MM format from current settings
          text: {
            const s = Settings.data.wallpaper.randomInterval
            const h = Math.floor(s / 3600)
            const m = Math.floor((s % 3600) / 60)
            return (h > 0 ? (h + "h ") : "") + (m > 0 ? (m + "m") : (h === 0 ? "0m" : ""))
          }
          Layout.alignment: Qt.AlignBottom | Qt.AlignRight
        }
      }

      // Preset chips
      RowLayout {
        id: presetRow
        spacing: Style.marginS * scaling

        // Preset seconds list
        property var presets: [15 * 60, 30 * 60, 45 * 60, 60 * 60, 90 * 60, 120 * 60]
        // Whether current interval equals one of the presets
        property bool isCurrentPreset: presets.indexOf(Settings.data.wallpaper.randomInterval) !== -1
        // Allow user to force open the custom input; otherwise it's auto-open when not a preset
        property bool customForcedVisible: false

        function setIntervalSeconds(sec) {
          Settings.data.wallpaper.randomInterval = sec
          WallpaperService.restartRandomWallpaperTimer()
          // Hide custom when selecting a preset
          customForcedVisible = false
        }

        // Helper to color selected chip
        function isSelected(sec) {
          return Settings.data.wallpaper.randomInterval === sec
        }

        // 15m
        Rectangle {
          radius: height * 0.5
          color: presetRow.isSelected(15 * 60) ? Color.mPrimary : Color.mSurfaceVariant
          implicitHeight: Math.max(Style.baseWidgetSize * 0.55 * scaling, 24 * scaling)
          implicitWidth: label15.implicitWidth + Style.marginM * 1.5 * scaling
          border.width: 1
          border.color: presetRow.isSelected(15 * 60) ? Color.transparent : Color.mOutline
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: presetRow.setIntervalSeconds(15 * 60)
          }
          NText {
            id: label15
            anchors.centerIn: parent
            text: "15m"
            font.pointSize: Style.fontSizeS * scaling
            font.weight: Style.fontWeightMedium
            color: presetRow.isSelected(15 * 60) ? Color.mOnPrimary : Color.mOnSurface
          }
        }

        // 30m
        Rectangle {
          radius: height * 0.5
          color: presetRow.isSelected(30 * 60) ? Color.mPrimary : Color.mSurfaceVariant
          implicitHeight: Math.max(Style.baseWidgetSize * 0.55 * scaling, 24 * scaling)
          implicitWidth: label30.implicitWidth + Style.marginM * 1.5 * scaling
          border.width: 1
          border.color: presetRow.isSelected(30 * 60) ? Color.transparent : Color.mOutline
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: presetRow.setIntervalSeconds(30 * 60)
          }
          NText {
            id: label30
            anchors.centerIn: parent
            text: "30m"
            font.pointSize: Style.fontSizeS * scaling
            font.weight: Style.fontWeightMedium
            color: presetRow.isSelected(30 * 60) ? Color.mOnPrimary : Color.mOnSurface
          }
        }

        // 45m
        Rectangle {
          radius: height * 0.5
          color: presetRow.isSelected(45 * 60) ? Color.mPrimary : Color.mSurfaceVariant
          implicitHeight: Math.max(Style.baseWidgetSize * 0.55 * scaling, 24 * scaling)
          implicitWidth: label45.implicitWidth + Style.marginM * 1.5 * scaling
          border.width: 1
          border.color: presetRow.isSelected(45 * 60) ? Color.transparent : Color.mOutline
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: presetRow.setIntervalSeconds(45 * 60)
          }
          NText {
            id: label45
            anchors.centerIn: parent
            text: "45m"
            font.pointSize: Style.fontSizeS * scaling
            font.weight: Style.fontWeightMedium
            color: presetRow.isSelected(45 * 60) ? Color.mOnPrimary : Color.mOnSurface
          }
        }

        // 1h
        Rectangle {
          radius: height * 0.5
          color: presetRow.isSelected(60 * 60) ? Color.mPrimary : Color.mSurfaceVariant
          implicitHeight: Math.max(Style.baseWidgetSize * 0.55 * scaling, 24 * scaling)
          implicitWidth: label1h.implicitWidth + Style.marginM * 1.5 * scaling
          border.width: 1
          border.color: presetRow.isSelected(60 * 60) ? Color.transparent : Color.mOutline
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: presetRow.setIntervalSeconds(60 * 60)
          }
          NText {
            id: label1h
            anchors.centerIn: parent
            text: "1h"
            font.pointSize: Style.fontSizeS * scaling
            font.weight: Style.fontWeightMedium
            color: presetRow.isSelected(60 * 60) ? Color.mOnPrimary : Color.mOnSurface
          }
        }

        // 1h 30m
        Rectangle {
          radius: height * 0.5
          color: presetRow.isSelected(90 * 60) ? Color.mPrimary : Color.mSurfaceVariant
          implicitHeight: Math.max(Style.baseWidgetSize * 0.55 * scaling, 24 * scaling)
          implicitWidth: label90.implicitWidth + Style.marginM * 1.5 * scaling
          border.width: 1
          border.color: presetRow.isSelected(90 * 60) ? Color.transparent : Color.mOutline
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: presetRow.setIntervalSeconds(90 * 60)
          }
          NText {
            id: label90
            anchors.centerIn: parent
            text: "1h 30m"
            font.pointSize: Style.fontSizeS * scaling
            font.weight: Style.fontWeightMedium
            color: presetRow.isSelected(90 * 60) ? Color.mOnPrimary : Color.mOnSurface
          }
        }

        // 2h
        Rectangle {
          radius: height * 0.5
          color: presetRow.isSelected(120 * 60) ? Color.mPrimary : Color.mSurfaceVariant
          implicitHeight: Math.max(Style.baseWidgetSize * 0.55 * scaling, 24 * scaling)
          implicitWidth: label2h.implicitWidth + Style.marginM * 1.5 * scaling
          border.width: 1
          border.color: presetRow.isSelected(120 * 60) ? Color.transparent : Color.mOutline
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: presetRow.setIntervalSeconds(120 * 60)
          }
          NText {
            id: label2h
            anchors.centerIn: parent
            text: "2h"
            font.pointSize: Style.fontSizeS * scaling
            font.weight: Style.fontWeightMedium
            color: presetRow.isSelected(120 * 60) ? Color.mOnPrimary : Color.mOnSurface
          }
        }

        // Custom… opens inline input
        Rectangle {
          radius: height * 0.5
          color: customRow.visible ? Color.mPrimary : Color.mSurfaceVariant
          implicitHeight: Math.max(Style.baseWidgetSize * 0.55 * scaling, 24 * scaling)
          implicitWidth: labelCustom.implicitWidth + Style.marginM * 1.5 * scaling
          border.width: 1
          border.color: customRow.visible ? Color.transparent : Color.mOutline
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: presetRow.customForcedVisible = !presetRow.customForcedVisible
          }
          NText {
            id: labelCustom
            anchors.centerIn: parent
            text: customRow.visible ? "Custom" : "Custom…"
            font.pointSize: Style.fontSizeS * scaling
            font.weight: Style.fontWeightMedium
            color: customRow.visible ? Color.mOnPrimary : Color.mOnSurface
          }
        }
      }

      // Custom HH:MM inline input
      RowLayout {
        id: customRow
        visible: presetRow.customForcedVisible || !presetRow.isCurrentPreset
        spacing: Style.marginS * scaling
        Layout.topMargin: Style.marginS * scaling

        NTextInput {
          label: "Custom Interval"
          description: "Enter time as HH:MM (e.g., 1:30)."
          text: {
            const s = Settings.data.wallpaper.randomInterval
            const h = Math.floor(s / 3600)
            const m = Math.floor((s % 3600) / 60)
            return h + ":" + (m < 10 ? ("0" + m) : m)
          }
          Layout.fillWidth: true
          onEditingFinished: {
            const m = text.trim().match(/^(\d{1,2}):(\d{2})$/)
            if (m) {
              let h = parseInt(m[1])
              let min = parseInt(m[2])
              if (isNaN(h) || isNaN(min))
                return
              h = Math.max(0, Math.min(24, h))
              min = Math.max(0, Math.min(59, min))
              Settings.data.wallpaper.randomInterval = (h * 3600) + (min * 60)
              WallpaperService.restartRandomWallpaperTimer()
              // Keep custom visible after manual entry
              presetRow.customForcedVisible = true
            }
          }
        }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }

  // -------------------------------
  // Swww
  ColumnLayout {
    spacing: Style.marginL * scaling
    Layout.fillWidth: true

    NText {
      text: "Swww"
      font.pointSize: Style.fontSizeXXL * scaling
      font.weight: Style.fontWeightBold
      color: Color.mSecondary
    }

    // Use SWWW
    NToggle {
      label: "Use Swww"
      description: "Use Swww daemon for advanced wallpaper management."
      checked: Settings.data.wallpaper.swww.enabled
      onToggled: checked => {
                   if (checked) {
                     // Check if swww is installed
                     swwwCheck.running = true
                   } else {
                     Settings.data.wallpaper.swww.enabled = false
                     ToastService.showNotice("Swww", "Disabled")
                   }
                 }
    }

    // SWWW Settings (only visible when useSWWW is enabled)
    ColumnLayout {
      spacing: Style.marginS * scaling
      Layout.fillWidth: true
      Layout.topMargin: Style.marginS * scaling
      visible: Settings.data.wallpaper.swww.enabled

      // Resize Mode
      NComboBox {
        label: "Resize Mode"
        description: "How Swww should resize wallpapers to fit the screen."
        model: ListModel {
          ListElement {
            key: "no"
            name: "No"
          }
          ListElement {
            key: "crop"
            name: "Crop"
          }
          ListElement {
            key: "fit"
            name: "Fit"
          }
          ListElement {
            key: "stretch"
            name: "Stretch"
          }
        }
        currentKey: Settings.data.wallpaper.swww.resizeMethod
        onSelected: key => {
                      Settings.data.wallpaper.swww.resizeMethod = key
                    }
      }

      // Transition Type
      NComboBox {
        label: "Transition Type"
        description: "Animation type when switching between wallpapers."
        model: ListModel {
          ListElement {
            key: "none"
            name: "None"
          }
          ListElement {
            key: "simple"
            name: "Simple"
          }
          ListElement {
            key: "fade"
            name: "Fade"
          }
          ListElement {
            key: "left"
            name: "Left"
          }
          ListElement {
            key: "right"
            name: "Right"
          }
          ListElement {
            key: "top"
            name: "Top"
          }
          ListElement {
            key: "bottom"
            name: "Bottom"
          }
          ListElement {
            key: "wipe"
            name: "Wipe"
          }
          ListElement {
            key: "wave"
            name: "Wave"
          }
          ListElement {
            key: "grow"
            name: "Grow"
          }
          ListElement {
            key: "center"
            name: "Center"
          }
          ListElement {
            key: "any"
            name: "Any"
          }
          ListElement {
            key: "outer"
            name: "Outer"
          }
          ListElement {
            key: "random"
            name: "Random"
          }
        }
        currentKey: Settings.data.wallpaper.swww.transitionType
        onSelected: key => {
                      Settings.data.wallpaper.swww.transitionType = key
                    }
      }

      // Transition FPS
      ColumnLayout {
        NLabel {
          label: "Transition FPS"
          description: "Frames per second for transition animations."
        }

        RowLayout {
          spacing: Style.marginL * scaling
          NSlider {
            Layout.fillWidth: true
            from: 30
            to: 500
            stepSize: 5
            value: Settings.data.wallpaper.swww.transitionFps
            onMoved: Settings.data.wallpaper.swww.transitionFps = Math.round(value)
            cutoutColor: Color.mSurface
          }
          NText {
            text: Settings.data.wallpaper.swww.transitionFps + " FPS"
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
          }
        }
      }

      // Transition Duration
      ColumnLayout {
        NLabel {
          label: "Transition Duration"
          description: "Duration of transition animations in seconds."
        }

        RowLayout {
          spacing: Style.marginL * scaling
          NSlider {
            Layout.fillWidth: true
            from: 0.25
            to: 10
            stepSize: 0.05
            value: Settings.data.wallpaper.swww.transitionDuration
            onMoved: Settings.data.wallpaper.swww.transitionDuration = value
            cutoutColor: Color.mSurface
          }
          NText {
            text: Settings.data.wallpaper.swww.transitionDuration.toFixed(2) + "s"
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
          }
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
