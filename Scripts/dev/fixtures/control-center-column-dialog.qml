// Real Popup with one explicit page-input event, relocated by the VM controller.
import QtQuick
import qs.Modules.Panels.Settings.ControlCenter as CC

CC.ControlCenterWidgetSettingsDialog {
  id: root
  onOpened: Qt.callLater(function () { root.queueSettings({i4Explicit: true}); })
}
