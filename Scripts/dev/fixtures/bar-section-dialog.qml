// Drives the real live Popup through its public field-input/receipt interface.
import QtQuick
import qs.Modules.Panels.Settings.Bar as Bar

Bar.BarWidgetSettingsDialog {
  id: root
  onOpened: Qt.callLater(function () { root.queueSettings({i4Explicit: true}); })
  onSettingsSaveCompleted: result => {
    if (result.status !== "failed")
      Qt.callLater(function () { if (!root.settingsDirty) root.close(); });
  }
}
