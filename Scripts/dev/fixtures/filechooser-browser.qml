import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Portals
import qs.Services.Files
import qs.Services.Session
import qs.Services.UI

ShellRoot {
  FileView {
    path: Quickshell.shellDir + "/builtin/plugins/atmosphera-icons/icons.json"
    onLoaded: IconRegistry.register("dev:filechooser-icons", JSON.parse(text()), Quickshell.shellDir + "/builtin/plugins/atmosphera-icons")
  }
  Component.onCompleted: ShellRegistration.startPortals()
  IpcHandler {
    target: "filechooserRegression"
    function state(): string {
      return JSON.stringify({portalReady: ShellRegistration.portalReady,
        requests: Object.values(FileChooserPortal.activeRequests).map(entry => {
          var request = entry.request;
          var window = entry.observedWindow;
          var current = request.browser.entry(request.selection.cursor);
          return {method: entry.method, appId: entry.appId, options: entry.options,
            status: request.browser.status, path: request.browser.currentPath,
            error: request.errorText || request.browser.errorText,
            filterText: request.browser.filterText, saveName: request.saveName,
             autoExtension: request.autoExtension,
             pathEntry: window ? window.pathEntryState() : {},
            replace: request.pendingReplace, creatingFolder: request.browser.creatingFolder,
            createError: request.browser.createFolderError, name: current ? current.name : "",
            names: Array.from({length: request.browser.count}, (_, i) => request.browser.entry(i).name),
            focus: window ? window.focusArea : "", focusedControl: window ? window.focusedControl : "",
            nativeActive: !!window && window.contentItem.Window.active,
            nameSelection: window ? window.nameSelection : []};
        })});
    }
    function cancelTwice(): void { FileChooserPortal.cancelAll(); }
    function quit(): void { FileChooserPortal.cancelAll(); Qt.quit(); }
  }
}
