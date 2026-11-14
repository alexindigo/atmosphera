import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "../../../Helpers/PortalPaths.js" as PortalPaths
import qs.Commons
import qs.Modules.FileChooser
import qs.Services.Files
import qs.Services.UI

ShellRoot {
  id: root
  property var touchSequence: null
  TestEvent {
    id: nativeTouch
  }
  readonly property string base: Quickshell.env("FILECHOOSER_UI_ROOT")
  property var request: null
  property var replies: []
  property var imageDecodeSamples: []
  property var iconMountFixture: null
  property bool tracingScroll: false
  property var scrollFrames: []
  property var scrollClock: null
  FrameAnimation {
    running: root.tracingScroll
    onTriggered: root.scrollFrames.push({
                                          time: root.scrollClock.wallMs(),
                                          cpuMs: root.scrollClock.cpuMs(),
                                          frameMs: frameTime * 1000,
                                          view: windowLoader.item.scrollState()
                                        })
  }
  Connections {
    target: FileTypes
    function on_MountsChanged() {
      // The mixed-icon test substitutes mount data, not a real remote mount.
      // Keep that input deterministic across the normal mount refresh timer.
      if (root.iconMountFixture !== null && JSON.stringify(FileTypes._mounts) !== JSON.stringify(root.iconMountFixture))
        FileTypes._mounts = root.iconMountFixture;
    }
  }
  Timer {
    interval: 16
    repeat: true
    running: !!windowLoader.item && windowLoader.item.quickLookOpen && windowLoader.item.preview.kind === "image"
    onRunningChanged: if (running)
                        root.imageDecodeSamples = []
    onTriggered: {
      var window = windowLoader.item;
      var renderer = window.previewRenderer;
      if (renderer && renderer.decodeSize !== undefined)
        root.imageDecodeSamples = root.imageDecodeSamples.concat([
                                                                   {
                                                                     width: renderer.decodeSize.width,
                                                                     height: renderer.decodeSize.height,
                                                                     sheetWidth: window.previewMotion.geometry.width,
                                                                     sheetHeight: window.previewMotion.geometry.height,
                                                                     growing: window.previewMotion.running
                                                                   }
                                                                 ]);
    }
  }
  Component {
    id: requests
    FileRequest {}
  }
  Loader {
    id: windowLoader
    active: root.request !== null
    sourceComponent: FileChooserWindow {
      request: root.request
    }
  }
  function open(mode) {
    windowLoader.active = false;
    if (request)
      request.destroy();
    replies = [];
    var options = {
      title: mode === "save" ? "Save field notes" : "Choose a file",
      current_folder: PortalPaths.encodeBytePath(mode === "empty" ? base + "/Empty" : base).bytes,
      multiple: mode !== "save",
      current_name: "Field notes.md",
      accept_label: mode === "save" ? "Save" : "Upload",
      filters: [["All files", [[0, "*"]]], ["Images", [[1, "image/*"]]], ["Text", [[0, "*.md"], [0, "*.txt"]]]],
      choices: [["quality", "Quality", [["original", "Original"], ["compact", "Compact"]], "original"], ["metadata", "Keep metadata", [], "true"]]
    };
    request = requests.createObject(root, {
                                      method: mode === "save" ? "save" : "open",
                                      options: options,
                                      appId: "dev.filechooser"
                                    });
    request.finished.connect((response, results) => {
      root.replies = root.replies.concat([
                                           {
                                             response: response,
                                             results: results
                                           }
                                         ]);
    });
    windowLoader.active = true;
  }
  function snapshot() {
    var window = windowLoader.item;
    var selected = request ? request.selection : null;
    var entry = request ? request.browser.entry(selected.cursor) : null;
    return JSON.stringify({
                            ready: !!request && request.browser.status === "ready",
                            status: request ? request.browser.status : "",
                            path: request ? request.browser.currentPath : "",
                            error: request ? request.errorText || request.browser.errorText : "",
                            count: request ? request.browser.count : 0,
                            names: request ? Array.from({
                                                          length: request.browser.count
                                                        }, (_, i) => request.browser.entry(i).name) : [],
                            recentLocations: FileChooserMemory.recentLocations,
                            places: FilePlaces.places,
                            recentFiles: FilePlaces.recentFiles,
                            recentFolders: FilePlaces.recentFolders,
                            recentRows: window ? window.recentRows() : [],
                            removable: FilePlaces.removable,
                            cursor: selected ? selected.cursor : -1,
                            name: entry ? entry.name : "",
                            selected: selected ? selected.selectedPaths : [],
                            view: request ? request.viewMode : "",
                            views: window && typeof window.viewState === "function" ? window.viewState() : {},
                            scroll: window ? window.scrollState() : {},
                            sort: request ? request.browser.sortKey : "",
                            descending: request ? request.browser.sortDescending : false,
                            filter: request && request.currentFilter ? request.currentFilter[0] : "",
                            filterText: request ? request.browser.filterText || "" : "",
                            saveFilterText: request ? request.browser.saveFilterText || "" : "",
                            saveFilterEnabled: request ? request.saveFilterEnabled === true : false,
                            autoExtension: request ? request.autoExtension === true : false,
                            preferredSuffix: request ? request.preferredSuffix || "" : "",
                            creatingFolder: request ? request.browser.creatingFolder === true : false,
                            createFolderError: request ? request.browser.createFolderError || "" : "",
                            folderEditor: window && window.folderEditorState ? window.folderEditorState() : {},
                            operations: window && window.operationState ? window.operationState() : {},
                            choices: request ? request.choiceValues : {},
                            layoutGeometry: window ? window.layoutGeometry() : {},
                            appName: request ? request.appName : "",
                            appIcon: request ? request.appIcon : "",
                            appOptionsLabel: request ? request.appOptionsLabel : "",
                            bottomGeometry: window ? window.bottomGeometry : {},
                            choicesFit: window ? window.choiceValuesFit() : false,
                            dropdownsFit: window ? window.dropdownValuesFit() : false,
                            thumbnails: window ? window.thumbnailState() : {},
                            icons: window ? window.iconState() : [],
                            palette: {
                              primary: AtmoColor.mPrimary.toString(),
                              standout: AtmoColor.mStandout.toString(),
                              surface: AtmoColor.mSurface.toString()
                            },
                            hidden: request ? request.browser.showHidden : false,
                            saveName: request ? request.saveName : "",
                            replace: request ? request.pendingReplace : "",
                            settled: request ? request.settled : false,
                            focus: window ? window.focusArea : "",
                            focusedControl: window ? window.focusedControl : "",
                            nativeActive: !!window && window.contentItem.Window.active,
                            motion: window ? window.previewMotion : {},
                            nameSelection: window ? window.nameSelection : [],
                            columnGeometry: window ? window.columnGeometry : {},
                            choiceCenters: window ? window.choiceGeometry() : [],
                            breadcrumbGaps: window ? window.breadcrumbGeometry() : [],
                            breadcrumbText: window ? window.breadcrumbText : [],
                            pathEntry: window && window.pathEntryState ? window.pathEntryState() : {},
                            selectionCountVisible: window ? window.selectionCountVisible : false,
                            localeName: Qt.locale().name,
                            preview: window ? window.quickLookOpen : false,
                            playback: window ? window.playbackState : {},
                            transportGeometry: window ? window.transportGeometry() : [],
                            pathEditing: window ? window.pathEditing : false,
                            kind: window ? window.preview.kind : "",
                            previewStatus: window ? window.preview.status : "",
                            previewText: window ? window.preview.text.slice(0, 100) : "",
                            pdfAvailable: window ? window.preview.pdfAvailable : false,
                            rendered: window && window.previewRenderer ? window.previewRenderer.previewState : "",
                            imageDecodeSamples: root.imageDecodeSamples,
                            frame: window && window.previewRenderer && window.preview.kind === "animatedImage" ? window.previewRenderer.frame : -1,
                            frames: window && window.previewRenderer && window.preview.kind === "animatedImage" ? window.previewRenderer.frames : 0,
                            position: window && window.previewRenderer && ["video", "audio"].includes(window.preview.kind) ? window.previewRenderer.position : -1,
                            replies: replies
                          });
  }
  FileView {
    path: Quickshell.shellDir + "/builtin/plugins/atmosphera-icons/icons.json"
    onLoaded: IconRegistry.register("dev:atmosphera-icons", JSON.parse(text()), Quickshell.shellDir + "/builtin/plugins/atmosphera-icons")
  }
  Component.onCompleted: Qt.callLater(() => open("open"))
  IpcHandler {
    target: "filechooserHarness"
    function open(mode: string): void {
      root.open(mode);
    }
    function openRequest(method: string, appId: string, options: string): void {
      windowLoader.active = false;
      if (root.request)
        root.request.destroy();
      root.replies = [];
      root.request = requests.createObject(root, {
                                             method: method,
                                             appId: appId,
                                             options: JSON.parse(options)
                                           });
      root.request.finished.connect((response, results) => {
        root.replies = root.replies.concat([
                                             {
                                               response: response,
                                               results: results
                                             }
                                           ]);
      });
      windowLoader.active = true;
    }
    function state(): string {
      return root.snapshot();
    }
    function touchStart(x: real, y: real): void {
      root.touchSequence = nativeTouch.touchEvent(windowLoader.item.contentItem);
      root.touchSequence.press(0, windowLoader.item.contentItem, x, y).commit();
    }
    function touchMove(x: real, y: real): void {
      root.touchSequence.move(0, windowLoader.item.contentItem, x, y).commit();
    }
    function touchEnd(x: real, y: real): void {
      root.touchSequence.release(0, windowLoader.item.contentItem, x, y).commit();
      root.touchSequence = null;
    }
    function startScrollTrace(): void {
      if (!root.scrollClock)
        root.scrollClock = Qt.createQmlObject('import FileChooserTest 1.0; FrameClock {}', root, "scroll-frame-clock");
      Logger.i("ScrollTrace", "BEGIN " + root.request.viewMode);
      root.scrollFrames = [];
      root.tracingScroll = true;
    }
    function scrollTrace(): string {
      root.tracingScroll = false;
      Logger.i("ScrollTrace", "END " + root.request.viewMode);
      return JSON.stringify(root.scrollFrames);
    }
    function scrollState(): string {
      return JSON.stringify(windowLoader.item.scrollState());
    }
    function visibleText(): string {
      var texts = [];
      function visit(node) {
        if (!node.visible)
          return;
        if (typeof node.text === "string" && node.text)
          texts.push(node.text);
        for (var i = 0; i < node.children.length; ++i)
          visit(node.children[i]);
      }
      visit(windowLoader.item.contentItem);
      return JSON.stringify(texts);
    }
    function list(): void {
      root.request.viewMode = "list";
      root.request.browser.sortKey = "modified";
      root.request.browser.sortDescending = true;
      windowLoader.item.focusListing();
    }
    function grid(): void {
      root.request.viewMode = "grid";
      windowLoader.item.focusListing();
    }
    function focusListing(): void {
      windowLoader.item.focusListing();
    }
    function thumbnails(value: bool): void {
      if (root.request.viewSettings)
        root.request.viewSettings.thumbnails = value;
    }
    function panelWidth(width: real): void {
      windowLoader.item.preferredPanelWidth = width;
    }
    function panelHeight(height: real): void {
      windowLoader.item.preferredPanelHeight = height;
    }
    function failFolder(): void {
      root.request.browser.navigate(root.base + "/Missing");
    }
    function reducedMotion(value: bool): void {
      Settings.data.general.animationDisabled = value;
    }
    function iconMounts(text: string): void {
      root.iconMountFixture = FileTypes.parseMounts(text);
      FileTypes._mounts = root.iconMountFixture;
    }
    function refreshPlaces(): void {
      FilePlaces.refresh();
    }
    function quit(): void {
      Qt.quit();
    }
  }
}
