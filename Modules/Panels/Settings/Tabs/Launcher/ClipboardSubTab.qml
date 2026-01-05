import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NToggle {
    label: I18n.tr("settings.launcher.settings.clipboard-history.label")
    description: I18n.tr("settings.launcher.settings.clipboard-history.description")
    checked: Settings.data.appLauncher.enableClipboardHistory
    onToggled: checked => Settings.data.appLauncher.enableClipboardHistory = checked
    isSettings: true
    defaultValue: Settings.getDefaultValue("appLauncher.enableClipboardHistory")
  }

  NToggle {
    label: I18n.tr("settings.launcher.settings.clip-preview.label")
    description: I18n.tr("settings.launcher.settings.clip-preview.description")
    checked: Settings.data.appLauncher.enableClipPreview
    onToggled: checked => Settings.data.appLauncher.enableClipPreview = checked
    isSettings: true
    defaultValue: Settings.getDefaultValue("appLauncher.enableClipPreview")
    visible: Settings.data.appLauncher.enableClipboardHistory
  }

  NToggle {
    label: I18n.tr("settings.launcher.settings.auto-paste.label")
    description: I18n.tr("settings.launcher.settings.auto-paste.description")
    checked: Settings.data.appLauncher.autoPasteClipboard
    onToggled: checked => Settings.data.appLauncher.autoPasteClipboard = checked
    isSettings: true
    defaultValue: Settings.getDefaultValue("appLauncher.autoPasteClipboard")
    visible: Settings.data.appLauncher.enableClipboardHistory
    enabled: ProgramCheckerService.wtypeAvailable
  }
}
