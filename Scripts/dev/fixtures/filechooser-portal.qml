import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Panels.Settings.DesktopWidgets.WidgetSettings
import qs.Portals
import qs.Services.Files
import qs.Services.UI

ShellRoot {
  id: root
  property var saved: null
  property int accepts: 0
  property int cancels: 0
  property var picker: null
  property bool connectedPicker: false

  // Dev-only discovery of the real consumer's private picker/control.
  function descendants(object) {
    var list = [];
    for (var child of object.children || object.data || []) {
      list.push(child);
      list = list.concat(descendants(child));
    }
    return list;
  }
  function settingsOpen() {
    page.visible = true;
    if (!picker)
      picker = descendants(settings).find(child => typeof child.openFilePicker === "function");
    picker.initialPath = Quickshell.env("FILECHOOSER_FIXTURES");
    if (!connectedPicker) {
      picker.accepted.connect(paths => {
        root.accepts++;
      });
      picker.cancelled.connect(() => {
        root.cancels++;
      });
      connectedPicker = true;
    }
    var button = descendants(settings).find(child => child.text === I18n.tr("panels.desktop-widgets.app-shortcut-icon-file") && typeof child.clicked === "function");
    button.clicked();
  }
  FloatingWindow {
    id: page
    visible: false
    implicitWidth: 900
    implicitHeight: 700
    color: AtmoColor.mSurface
    ScrollView {
      anchors.fill: parent
      contentWidth: availableWidth
      AppShortcutSettings {
        id: settings
        width: 850
        widgetData: ({
                       appId: "fixture.desktop",
                       iconType: "icons",
                       iconSource: "/original.svg",
                       customLabel: "Fixture"
                     })
        onSettingsChanged: value => root.saved = value
      }
    }
  }
  FileView {
    path: Quickshell.shellDir + "/builtin/plugins/atmosphera-icons/icons.json"
    onLoaded: IconRegistry.register("dev:filechooser-icons", JSON.parse(text()), Quickshell.shellDir + "/builtin/plugins/atmosphera-icons")
  }
  Component.onCompleted: {
    FileChooserPortal.init();
    SettingsPortal.init();
  }
  IpcHandler {
    target: "filechooserRegression"
    function state(): string {
      var entries = Object.values(FileChooserPortal.activeRequests).map(entry => ({
        handle: entry.handle,
        method: entry.method,
        appId: entry.appId,
        parent: entry.parentWindow,
        title: entry.options.title,
        modal: entry.options.modal,
        label: entry.request.acceptLabel,
        path: entry.request.browser.currentPath,
        status: entry.request.browser.status,
        error: entry.request.browser.errorText || entry.request.errorText,
        filter: entry.request.currentFilter,
        choices: entry.request.choiceValues,
        selected: entry.request.selection.selectedPaths,
        saveName: entry.request.saveName,
        replace: entry.request.pendingReplace,
        names: Array.from({
                            length: entry.request.browser.count
                          }, (_, i) => entry.request.browser.entry(i).name)
      }));
      return JSON.stringify({
                              requests: entries,
                              accepts: root.accepts,
                              cancels: root.cancels,
                              saved: root.saved,
                              icon: settings.valueIconSource,
                              iconType: settings.valueIconType,
                              recent: FileChooserMemory.recentLocations
                            });
    }
    function select(path: string): void {
      var r = Object.values(FileChooserPortal.activeRequests)[0].request;
      r.selection.click(r.browser.indexOfPath(path), Qt.NoModifier);
    }
    function accept(): void {
      Object.values(FileChooserPortal.activeRequests)[0].request.accept();
    }
    function replace(): void {
      Object.values(FileChooserPortal.activeRequests)[0].request.confirmReplace();
    }
    function navigate(path: string): void {
      Object.values(FileChooserPortal.activeRequests)[0].request.browser.navigate(path);
    }
    function filter(): void {
      var r = Object.values(FileChooserPortal.activeRequests)[0].request;
      r.currentFilter = r.options.filters[1];
    }
    function choice(id: string, value: string): void {
      Object.values(FileChooserPortal.activeRequests)[0].request.setChoice(id, value);
    }
    function cancelTwice(): void {
      var r = Object.values(FileChooserPortal.activeRequests)[0].request;
      r.cancel();
      r.cancel();
    }
    function settingsOpen(): void {
      root.settingsOpen();
    }
    function settingsClose(): void {
      root.picker.close();
    }
    function quit(): void {
      Qt.quit();
    }
  }
}
