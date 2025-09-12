import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: contentColumn
  spacing: Style.marginL * scaling
  width: root.width

  NToggle {
    label: "Auto-hide"
    description: "Automatically hide when not in use."
    checked: Settings.data.dock.autoHide
    onToggled: checked => Settings.data.dock.autoHide = checked
  }

  NToggle {
    label: "Exclusive Zone"
    description: "Ensure windows don't open underneath."
    checked: Settings.data.dock.exclusive
    onToggled: checked => Settings.data.dock.exclusive = checked
  }

  ColumnLayout {
    spacing: Style.marginXXS * scaling
    Layout.fillWidth: true

    NLabel {
      label: "Background Opacity"
      description: "Adjust the background opacity."
    }

    RowLayout {
      NSlider {
        Layout.fillWidth: true
        from: 0
        to: 1
        stepSize: 0.01
        value: Settings.data.dock.backgroundOpacity
        onMoved: Settings.data.dock.backgroundOpacity = value
        cutoutColor: Color.mSurface
      }

      NText {
        text: Math.floor(Settings.data.dock.backgroundOpacity * 100) + "%"
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: Style.marginS * scaling
        color: Color.mOnSurface
      }
    }
  }

  // ColumnLayout {
  //   spacing: Style.marginXXS * scaling
  //   Layout.fillWidth: true

  //   NLabel {
  //     label: "Dock Floating Distance"
  //     description: "Adjust the floating distance from the screen edge."
  //   }

  //   RowLayout {
  //     NSlider {
  //       Layout.fillWidth: true
  //       from: 0
  //       to: 4
  //       stepSize: 0.01
  //       value: Settings.data.dock.floatingRatio
  //       onMoved: Settings.data.dock.floatingRatio = value
  //       cutoutColor: Color.mSurface
  //     }

  //     NText {
  //       text: Math.floor(Settings.data.dock.floatingRatio * 100) + "%"
  //       Layout.alignment: Qt.AlignVCenter
  //       Layout.leftMargin: Style.marginS * scaling
  //       color: Color.mOnSurface
  //     }
  //   }
  // }
}
