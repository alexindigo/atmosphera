import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Modules.OSD
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  property var addType
  property var removeType

  Repeater {
    model: [
      {
        type: OSD.Type.Volume,
        key: "volume"
      },
      {
        type: OSD.Type.InputVolume,
        key: "input-volume"
      },
      {
        type: OSD.Type.Brightness,
        key: "brightness"
      },
      {
        type: OSD.Type.LockKey,
        key: "lockkey"
      },
      {
        type: OSD.Type.CustomText,
        key: "custom-text"
      }
    ]
    delegate: NCheckbox {
      required property var modelData
      Layout.fillWidth: true
      label: I18n.tr("settings.osd.types." + modelData.key + ".label")
      description: I18n.tr("settings.osd.types." + modelData.key + ".description")
      checked: (Settings.data.osd.enabledTypes || []).includes(modelData.type)
      onToggled: checked => {
                   if (checked) {
                     Settings.data.osd.enabledTypes = root.addType(Settings.data.osd.enabledTypes, modelData.type);
                   } else {
                     Settings.data.osd.enabledTypes = root.removeType(Settings.data.osd.enabledTypes, modelData.type);
                   }
                 }
    }
  }
}
