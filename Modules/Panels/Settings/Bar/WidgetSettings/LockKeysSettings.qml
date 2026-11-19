import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var screen: null
  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  // Local state
  property bool valueShowCapsLock: widgetData.showCapsLock !== undefined ? widgetData.showCapsLock : widgetMetadata.showCapsLock
  property bool valueShowNumLock: widgetData.showNumLock !== undefined ? widgetData.showNumLock : widgetMetadata.showNumLock
  property bool valueShowScrollLock: widgetData.showScrollLock !== undefined ? widgetData.showScrollLock : widgetMetadata.showScrollLock

  property string capsIcon: widgetData.capsLockIcon !== undefined ? widgetData.capsLockIcon : widgetMetadata.capsLockIcon
  property string numIcon: widgetData.numLockIcon !== undefined ? widgetData.numLockIcon : widgetMetadata.numLockIcon
  property string scrollIcon: widgetData.scrollLockIcon !== undefined ? widgetData.scrollLockIcon : widgetMetadata.scrollLockIcon

  property bool valueHideWhenOff: widgetData.hideWhenOff !== undefined ? widgetData.hideWhenOff : (widgetMetadata.hideWhenOff !== undefined ? widgetMetadata.hideWhenOff : false)

  function saveSettings(fields) {
    if (fields)
      settingsChanged(fields);
  }

  RowLayout {
    spacing: Style.marginM

    NToggle {
      label: I18n.tr("bar.lock-keys.show-caps-lock-label")
      description: I18n.tr("bar.lock-keys.show-caps-lock-description")
      checked: valueShowCapsLock
      onToggled: checked => {
        valueShowCapsLock = checked;
        saveSettings({showCapsLock: valueShowCapsLock});
      }
      defaultValue: widgetMetadata.showCapsLock
    }

    AtmoIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: capsIcon
      pointSize: Style.fontSizeXL
      visible: capsIcon !== ""
    }

    NButton {
      text: I18n.tr("common.browse")
      onClicked: capsPicker.open()
      enabled: valueShowCapsLock
    }
  }

  AtmoIconPicker {
    id: capsPicker
    initialIcon: capsIcon
    query: "letter-c"
    onIconSelected: function (iconName) {
      capsIcon = iconName;
      saveSettings({capsLockIcon: capsIcon});
    }
  }

  RowLayout {
    spacing: Style.marginM

    NToggle {
      label: I18n.tr("bar.lock-keys.show-num-lock-label")
      description: I18n.tr("bar.lock-keys.show-num-lock-description")
      checked: valueShowNumLock
      onToggled: checked => {
        valueShowNumLock = checked;
        saveSettings({showNumLock: valueShowNumLock});
      }
      defaultValue: widgetMetadata.showNumLock
    }

    AtmoIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: numIcon
      pointSize: Style.fontSizeXL
      visible: numIcon !== ""
    }

    NButton {
      text: I18n.tr("common.browse")
      onClicked: numPicker.open()
      enabled: valueShowNumLock
    }
  }

  AtmoIconPicker {
    id: numPicker
    initialIcon: numIcon
    query: "letter-n"
    onIconSelected: function (iconName) {
      numIcon = iconName;
      saveSettings({numLockIcon: numIcon});
    }
  }

  RowLayout {
    spacing: Style.marginM

    NToggle {
      label: I18n.tr("bar.lock-keys.show-scroll-lock-label")
      description: I18n.tr("bar.lock-keys.show-scroll-lock-description")
      checked: valueShowScrollLock
      onToggled: checked => {
        valueShowScrollLock = checked;
        saveSettings({showScrollLock: valueShowScrollLock});
      }
      defaultValue: widgetMetadata.showScrollLock
    }

    AtmoIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: scrollIcon
      pointSize: Style.fontSizeXL
      visible: scrollIcon !== ""
    }

    NButton {
      text: I18n.tr("common.browse")
      onClicked: scrollPicker.open()
      enabled: valueShowScrollLock
    }
  }

  AtmoIconPicker {
    id: scrollPicker
    initialIcon: scrollIcon
    query: "letter-s"
    onIconSelected: function (iconName) {
      scrollIcon = iconName;
      saveSettings({scrollLockIcon: scrollIcon});
    }
  }

  NDivider {
    Layout.fillWidth: true
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.lock-keys.hide-when-off-label")
    description: I18n.tr("bar.lock-keys.hide-when-off-description")
    checked: valueHideWhenOff
    onToggled: checked => {
      valueHideWhenOff = checked;
      saveSettings({hideWhenOff: valueHideWhenOff});
    }
    defaultValue: widgetMetadata.hideWhenOff
  }
}
