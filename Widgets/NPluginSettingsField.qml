import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Field chrome knows only its injected capability and child controls. Native
// inheritance/intent/admission are owned by the session, not this presentation.
ColumnLayout {
  id: root
  required property var field
  default property alias content: controls.data
  Layout.fillWidth: true
  spacing: Style.marginS
  enabled: field !== null
  property var _releasePresentation: null
  function _updatePresentation() {
    if (_releasePresentation)
      _releasePresentation();
    _releasePresentation = field && visible ? field.presented() : null;
  }
  onFieldChanged: _updatePresentation()
  onVisibleChanged: _updatePresentation()
  Component.onCompleted: _updatePresentation()
  Component.onDestruction: {
    if (_releasePresentation)
      _releasePresentation();
  }

  ColumnLayout {
    id: controls
    Layout.fillWidth: true
    spacing: Style.marginS
  }
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginS
    NText {
      Layout.fillWidth: true
      pointSize: Style.fontSizeS
      text: root.field ? I18n.tr(root.field.pendingIntent === "reset" ? "panels.plugins.field-reset-pending" : root.field.pendingIntent === "set" ? "panels.plugins.field-edit-pending" : root.field.overridden ? "panels.plugins.field-overridden" : "panels.plugins.field-inherited") : ""
    }
    NButton {
      text: I18n.tr("common.reset")
      outlined: true
      enabled: !!root.field && (root.field.overridden || root.field.pendingIntent === "set")
      onClicked: root.field.reset()
    }
  }
}
