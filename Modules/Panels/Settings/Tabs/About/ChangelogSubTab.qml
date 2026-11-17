import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.Panels.Changelog
import qs.Services
import qs.Widgets

ColumnLayout {
  Layout.fillWidth: true
  Layout.fillHeight: true
  spacing: 0

  Component.onCompleted: Version.loadChangelog()

  ChangelogContent {
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.margins: Style.marginL
  }
}
