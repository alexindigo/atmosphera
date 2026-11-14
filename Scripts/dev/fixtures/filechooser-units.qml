import QtQuick
import Quickshell
import Quickshell.Io
import "../../../Helpers/PortalPaths.js" as PortalPaths
import "filechooser-icon-cases.js" as IconCases
import qs.Commons
import qs.Modules.FileChooser
import qs.Services.Files
import qs.Services.UI
import "filechooser-extensions.js" as ExtensionCases
import "filechooser-navigation.js" as NavigationCases
import "filechooser-paths.js" as PathCases

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("FILECHOOSER_UNIT_ROOT")
  readonly property string aux: Quickshell.env("FILECHOOSER_UNIT_AUX")
  property var steps: []
  property int phase: 0
  property int ticks: 0
  property var request: null
  property var responses: []
  property string beforeMemory: ""
  property var beforeNames: []
  property double staleStarted: 0
  property var tooltipOwner: null
  property var expectedRecentFolders: []
  property int selectionChanges: 0
  property bool appearingArmed: false
  property bool appearedAfterCheck: false
  Component { id: tooltipOwnerFactory; Item {} }

  FilePreview {
    id: preview
  }
  FilePlayback {
    id: playback
  }

  FileBrowser {
    id: fileBrowser
  }
  FileCompletion { id: pathCompletion; basePath: root.base }
  FileChooserHeader {
    id: breadcrumbs
    width: 1200
    request: ({
                browser: fileBrowser,
                viewMode: "grid"
              })
  }
  FileSelection {
    id: selection
    browser: fileBrowser
    onSelectedPathsChanged: root.selectionChanges++
  }
  Component {
    id: requestFactory
    FileRequest {}
  }
  FileView {
    id: memoryView
    path: Settings.cacheDir + "filechooser.json"
    printErrors: false
  }
  FileView {
    id: appearingTarget
    path: root.aux + "/overwrite/appeared.txt"
    blockWrites: true
    printErrors: false
  }
  Connections {
    target: root.request
    function onBusyChanged() {
      if (root.request && root.request.appId === "unit.appearing" && root.appearingArmed && !root.appearedAfterCheck && !root.request.busy && !root.request.settled) {
        root.appearedAfterCheck = true;
        appearingTarget.setText("arrived before return\n");
      }
    }
  }
  Process {
    id: mutate
    stdout: StdioCollector { id: mutateOutput }
  }
  function sampleWatchers() {
    mutate.command = ["timeout", "3", "python3", "-c", `
import os, pathlib
parent = pathlib.Path('/proc') / str(os.getppid())
pid = int((parent / 'stat').read_text().rsplit(')', 1)[1].split()[1])
proc = pathlib.Path('/proc') / str(pid)
assert (proc / 'exe').resolve().name in ('qs', 'quickshell')
count = 0
for info in (proc / 'fdinfo').iterdir():
    try: count += sum(line.startswith('inotify wd:') for line in info.read_text().splitlines())
    except FileNotFoundError: pass
print(count)
`];
    mutate.running = true;
  }
  function watcherSampleReady() { return !mutate.running; }
  function watcherCount() { return Number(mutateOutput.text.trim()); }

  function report(name, passed, actual) {
    Logger.i("FileChooserUnits", "FILECHOOSER_UNITS|" + JSON.stringify({
                                                                         "case": name,
                                                                         "pass": !!passed,
                                                                         "actual": actual
                                                                       }));
  }

  function names() {
    var result = [];
    for (var i = 0; i < fileBrowser.count; i++)
      result.push(fileBrowser.entry(i).name);
    return result;
  }

  function canonical(value) {
    if (Array.isArray(value))
      return value.map(canonical);
    if (value && typeof value === "object") {
      var sorted = {};
      for (var key of Object.keys(value).sort())
        sorted[key] = canonical(value[key]);
      return sorted;
    }
    return value;
  }

  function same(name, actual, expected) {
    // Normalize Qt sequence wrappers before comparing JSON objects by value.
    report(name, JSON.stringify(canonical(JSON.parse(JSON.stringify(actual)))) === JSON.stringify(canonical(JSON.parse(JSON.stringify(expected)))), actual);
  }

  function step(wait, run) {
    steps.push({
                 wait: wait,
                 run: run
               });
  }
  function ready() {
    return fileBrowser.status === "ready";
  }
  function requestReady() {
    return request && request.browser.status === "ready";
  }
  function answered() {
    return responses.length > 0;
  }
  function index(name) {
    return fileBrowser.indexOfPath(base + "/" + name);
  }

  function createRequest(method, options, appId) {
    if (request)
      request.destroy();
    responses = [];
    request = requestFactory.createObject(root, {
                                            method: method,
                                            appId: appId === undefined ? "unit.app" : appId,
                                            options: options || {
                                              current_folder: PortalPaths.encodeBytePath(base).bytes
                                            }
                                          });
    request.finished.connect(function (response, results) {
      root.responses = root.responses.concat([
                                               {
                                                 response: response,
                                                 results: results
                                               }
                                             ]);
    });
  }

  function buildOverwriteTests() {
    var folder = aux + "/overwrite";
    function save(name, app) {
      createRequest("save", {current_folder: PortalPaths.encodeBytePath(folder).bytes, current_name: name}, app || "unit.safety");
    }
    function batch() {
      createRequest("saveFiles", {current_folder: PortalPaths.encodeBytePath(folder).bytes,
        files: ["protected.txt", "other.txt"].map(name => PortalPaths.encodeBytePath(name).bytes)}, "unit.safety");
    }
    function pending() { return request.pendingReplace !== ""; }
    step(() => true, function () { save("appeared.txt", "unit.appearing"); });
    step(requestReady, function () { root.appearingArmed = true; request.accept(); });
    step(() => pending() || answered(), function () {
      report("overwrite.appears-before-return", root.appearedAfterCheck && request.pendingReplace === folder + "/appeared.txt" && responses.length === 0, {pending: request.pendingReplace, responses: responses});
      root.appearingArmed = false;
      request.cancel();
      save("protected.txt");
    });
    step(requestReady, function () { request.accept(); });
    step(pending, function () {
      request.declineReplace();
      same("overwrite.decline-keeps-request", [request.settled, request.pendingReplace, responses], [false, "", []]);
      same("overwrite.decline-keeps-name", request.saveName, "protected.txt");
      request.accept();
    });
    step(pending, function () {
      request.saveName = "other.txt";
      same("overwrite.name-invalidates", request.pendingReplace, "");
      request.accept();
    });
    step(pending, function () {
      same("overwrite.final-target", request.pendingReplace, folder + "/other.txt");
      request.declineReplace();
      request.saveName = "new target.txt";
      request.accept();
    });
    step(answered, function () {
      same("overwrite.changed-name-result", responses[0].results.uris, [PortalPaths.pathToUri(folder + "/new target.txt").uri]);
      save("A.txt");
    });
    step(requestReady, function () { request.accept(); });
    step(answered, function () {
      same("overwrite.case-sensitive", [responses[0].response, request.pendingReplace], [0, ""]);
    });
    for (let name of ["directory", "unwritable.txt", "fifo", "dangling", "directory-link"]) {
      step(() => true, function () { save(name); });
      step(requestReady, function () { request.accept(); });
      step(() => !request.busy && request.errorText !== "", function () {
        report("overwrite.refuse-" + name, !request.settled && !request.pendingReplace && responses.length === 0, request.errorText);
        request.cancel();
      });
    }
    step(() => true, function () { save("regular-link"); });
    step(requestReady, function () { request.accept(); });
    step(pending, function () {
      same("overwrite.regular-link", request.pendingReplace, folder + "/regular-link");
      request.confirmReplace();
    });
    step(answered, function () {
      same("overwrite.regular-link-result", responses[0].results.uris, [PortalPaths.pathToUri(folder + "/regular-link").uri]);
      save("protected.txt");
    });
    step(requestReady, function () { request.accept(); });
    step(pending, function () {
      same("overwrite.request-scope", responses, []);
      request.cancel();
      batch();
    });
    step(requestReady, function () { request.accept(); });
    step(pending, function () { request.confirmReplace(); });
    step(pending, function () {
      same("overwrite.batch-no-partial", [request.pendingReplace, responses], [folder + "/other.txt", []]);
      request.declineReplace();
      request.accept();
    });
    step(pending, function () {
      same("overwrite.batch-decline-clears-all", request.pendingReplace, folder + "/protected.txt");
      request.confirmReplace();
    });
    step(pending, function () { request.confirmReplace(); });
    step(answered, function () {
      same("overwrite.batch-all-approved", responses[0].results.uris, ["protected.txt", "other.txt"].map(name => PortalPaths.pathToUri(folder + "/" + name).uri));
      batch();
    });
    step(requestReady, function () { request.accept(); });
    step(pending, function () { request.confirmReplace(); });
    step(pending, function () {
      request.currentFilter = ["Text", [[0, "*.txt"]]];
      request.accept();
    });
    step(pending, function () {
      same("overwrite.filter-clears-approval", request.pendingReplace, folder + "/protected.txt");
      request.cancel();
      batch();
    });
    step(requestReady, function () { request.accept(); });
    step(pending, function () { request.confirmReplace(); });
    step(pending, function () { request.browser.navigate(folder + "/child"); });
    step(requestReady, function () { request.browser.navigate(folder); });
    step(requestReady, function () { request.accept(); });
    step(pending, function () {
      same("overwrite.folder-clears-approval", request.pendingReplace, folder + "/protected.txt");
      request.cancel();
    });
  }

  function buildTests() {
    step(() => true, function () {
      same("playback.initial", [playback.status, playback.playing, playback.seekable], ["idle", false, false]);
      playback.toggle();
      playback.seek(10000);
      same("playback.inactive-intents", [playback.playing, playback.position], [false, 0]);
      playback.setVolume(-1);
      same("playback.volume-low", playback.volume, 0);
      playback.setVolume(3);
      same("playback.volume-high", playback.volume, 1);
      playback.setVolume(0.5);
      playback.volumeBy(-0.05);
      report("playback.volume-step", Math.abs(playback.volume - 0.45) < 0.00001, playback.volume);
      playback.setVolume(NaN);
      report("playback.invalid-volume", Math.abs(playback.volume - 0.45) < 0.00001, playback.volume);
      same("playback.times", [playback.time(-1000), playback.time(65000), playback.time(3661000)], ["0:00", "1:05", "1:01:01"]);
      var measure = text => Array.from(text).length;
      same("labels.extension-attached", FileLabels.lines("Weekend itinerary.pdf", 14, measure), ["Weekend", "itinerary.pdf"]);
      same("labels.dots", FileLabels.lines("release.v1 notes.md", 12, measure), ["release.v1", "notes.md"]);
      same("labels.long-word", FileLabels.lines("Supercalifragilistic.txt", 8, measure), ["Supercalifragilistic.txt"]);
      same("labels.cjk", FileLabels.lines("週末旅行計画書.pdf", 5, measure), ["週末旅行計画書.pdf"]);
      same("labels.extension-only", FileLabels.lines(".extension", 5, measure), [".extension"]);
      same("labels.two-lines-only", FileLabels.lines("one two three four.txt", 7, measure), ["one two", "three four.txt"]);
      same("breadcrumbs.home", fileBrowser.breadcrumbParts("/home/tester/Documents", "/home/tester"), ["Home", "Documents"]);
      same("breadcrumbs.outside", fileBrowser.breadcrumbParts("/var/log", "/home/tester"), ["var", "log"]);
      same("breadcrumbs.component-boundary", fileBrowser.breadcrumbParts("/home/tester2/Documents", "/home/tester"), ["home", "tester2", "Documents"]);
    });
    step(() => true, function () {
      playback.source = PortalPaths.pathToUri(aux + "/previews/unit.wav").uri;
      playback.active = true;
    });
    // PlayingState precedes asynchronous output initialization. Observe the
    // actual clock before exercising pause/seek against that initialized output.
    step(() => playback.status === "ready" && playback.playing && playback.duration > 0 && playback.position > 0, function () {
      report("playback.clock-running", playback.position > 0, playback.position);
      report("playback.autoplay", playback.seekable && playback.duration === 8000, playback.snapshot);
      playback.toggle();
      playback.seek(-1000);
    });
    step(() => !playback.playing && playback.position === 0, function () {
      same("playback.seek-low", playback.position, 0);
      playback.seek(playback.duration + 1000);
    });
    step(() => playback.position === playback.duration, function () {
      same("playback.seek-high", playback.position, 8000);
      playback.active = false;
    });
    step(() => playback.status === "idle" && !playback.playing && playback.position === 0, function () {
      same("playback.close-stops", playback.status, "idle");
      same("playback.close-destroys-engine", playback.snapshot.engineActive, false);
    });
    step(() => !FilePlaces.loading && Object.keys(FilePlaces.xdgFolders).length > 0, function () {
      IconCases.run(FileTypes, FilePlaces, AtmoColor, JSON.parse(Quickshell.env("FILECHOOSER_ICON_SCHEMES")), report, same);
    });
    step(() => FileChooserMemory.ready && I18n.isLoaded, function () {
      createRequest("open", undefined, "dev.filechooser.Fieldwork");
    });
    step(() => requestReady() && request.appEntry !== null, function () {
      same("request.app-entry", [request.appName, request.appIcon, request.appOptionsLabel], ["Fieldwork", Quickshell.env("XDG_DATA_HOME") + "/applications/fieldwork.svg", "Options from Fieldwork"]);
      request.cancel();
      createRequest("open", undefined, "");
    });
    step(requestReady, function () {
      same("request.app-empty", [request.appName, request.appIcon, request.appOptionsLabel], ["", "", "Options from the app"]);
      request.cancel();
      createRequest("open", undefined, "dev.filechooser.Unknown");
    });
    step(requestReady, function () {
      same("request.app-unknown", [request.appName, request.appIcon, request.appOptionsLabel], ["", "", "Options from the app"]);
      request.cancel();
    });
    step(() => I18n.isLoaded && preview.pdfDetectionDone, function () {
      same("preview.idle", preview.status, "idle");
      report("preview.pdf-detection", typeof preview.pdfAvailable === "boolean", preview.pdfAvailable);
      preview.item = {
        path: aux + "/previews/small.txt"
      };
    });
    step(() => preview.status !== "loading", function () {
      same("preview.small", [preview.kind, preview.status, preview.text, preview.truncated], ["text", "ready", "Hello, 世界\n", false]);
      preview.item = {
        path: aux + "/previews/large.txt"
      };
    });
    step(() => preview.status !== "loading", function () {
      same("preview.large", [preview.text.length, preview.truncated, preview.status], [262144, true, "ready"]);
      preview.item = {
        path: aux + "/previews/limit.txt"
      };
    });
    step(() => preview.status !== "loading", function () {
      same("preview.exact-limit", [preview.text.length, preview.truncated, preview.status], [262144, false, "ready"]);
      preview.item = {
        path: aux + "/previews/cut.txt"
      };
    });
    step(() => preview.status !== "loading", function () {
      same("preview.multibyte-cut", [preview.text.length, preview.truncated, preview.status, preview.text.endsWith("c")], [262143, true, "ready", true]);
      preview.item = {
        path: aux + "/previews/invalid.txt"
      };
    });
    step(() => preview.status !== "loading", function () {
      same("preview.invalid-utf8", [preview.status, preview.text, preview.errorText], ["error", "", I18n.tr("widgets.file-picker.preview-unavailable")]);
      preview.item = {
        path: aux + "/previews/nul.txt"
      };
    });
    step(() => preview.status !== "loading", function () {
      same("preview.binary-nul", preview.status, "error");
      preview.item = {
        path: aux + "/previews/invalid-cut.txt"
      };
    });
    step(() => preview.status !== "loading", function () {
      same("preview.invalid-before-cut", preview.status, "error");
      preview.item = {
        path: aux + "/previews/missing.txt"
      };
    });
    step(() => preview.status !== "loading", function () {
      same("preview.missing", [preview.status, preview.text], ["error", ""]);
      preview.item = {
        path: aux + "/previews/unreadable.txt"
      };
    });
    step(() => preview.status !== "loading", function () {
      same("preview.unreadable", preview.status, "error");
      preview.item = {
        path: aux + "/previews/stale.txt"
      };
      staleStarted = Date.now();
    });
    step(() => Date.now() - staleStarted > 200, function () {
      preview.item = {
        path: aux + "/image.png"
      };
      same("preview.kind-switch", [preview.kind, preview.status, preview.text, preview.truncated], ["image", "ready", "", false]);
      mutate.command = ["timeout", "3", "python3", "-c", "import sys; open(sys.argv[1], 'w').write('outdated')", aux + "/previews/stale.txt"];
      mutate.running = true;
      staleStarted = Date.now();
    });
    step(() => !mutate.running && Date.now() - staleStarted > 300, function () {
      same("preview.stale-reply", [preview.kind, preview.status, preview.text], ["image", "ready", ""]);
      preview.item = null;
      same("preview.clear", [preview.status, preview.text, preview.path], ["idle", "", ""]);
    });
    step(() => FileChooserMemory.ready && I18n.isLoaded, function () {
      for (var name of ["With space", "hash#name", "percent%20literal", "question?mark", "résumé", "a b/c d"]) {
        var path = aux + "/escaped/" + name;
        same("paths.helper." + name, PortalPaths.qmlUrlToPath(Qt.url(PortalPaths.pathToUri(path).uri).toString()), {
               ok: true,
               path: path
             });
      }
      same("paths.helper.strict-portal-spaces", PortalPaths.uriToPath("file:///With space").ok, false);
      same("paths.helper.invalid-urls", ["file:///bad%ZZ", "file://remote/folder", "file:///hash#name", "file:///question?mark"].map(url => PortalPaths.qmlUrlToPath(url).ok), [false, false, false, false]);
      same("types.bytes-zero", FileTypes.formatSize(0), "0 B");
      same("types.bytes-small", [3, 40, 648, 1023].map(bytes => FileTypes.formatSize(bytes)), ["3 B", "40 B", "648 B", "1023 B"]);
      same("types.size-scaled", [1024, 1536, 1048576].map(bytes => FileTypes.formatSize(bytes)), ["1.0 KiB", "1.5 KiB", "1.0 MiB"]);
      same("types.size-german", FileTypes.formatSize(1536, Qt.locale("de_DE")), "1,5 KiB");
      var date = new Date(2026, 9, 18, 2, 0, 0);
      same("types.date-us", FileTypes.formatDate(date, Qt.locale("en_US")), "10/18/26 2:00\u202fAM");
      same("types.date-british", FileTypes.formatDate(date, Qt.locale("en_GB")), "18/10/2026 02:00");
      same("types.date-german", FileTypes.formatDate(date, Qt.locale("de_DE")), "18.10.26 02:00");
      same("types.date-system", FileTypes.formatDate(date), date.toLocaleString(Qt.locale(), Locale.ShortFormat));
      same("memory.initial-home", FileChooserMemory.folderFor("unknown"), FileChooserMemory.home);
      same("memory.initial-recent", FileChooserMemory.recentLocations, []);
      same("types.webp", FileTypes.previewKind("photo.webp"), "animatedImage");
      same("types.image", FileTypes.previewKind("photo.png"), "image");
      same("types.media", [FileTypes.previewKind("clip.mp4"), FileTypes.previewKind("song.flac"), FileTypes.previewKind("doc.pdf"), FileTypes.previewKind("main.qml"), FileTypes.previewKind("blob.bin")], ["video", "audio", "pdf", "text", "none"]);
      report("types.glob-brackets", FileTypes.matchesGlob("photo1.png", "photo[0-9].png", true), "photo1.png");
      fileBrowser.navigate(base);
    });
    step(ready, function () {
      same("browser.navigate", fileBrowser.currentPath, base);
      same("browser.natural-name", names(), ["empty", "folder", "Alpha.txt", "item2.txt", "item10.png"]);
      report("browser.has-hidden", fileBrowser.hasHidden, fileBrowser.hasHidden);
      beforeNames = names();
      fileBrowser.navigate(base + "/missing");
    });
    step(() => fileBrowser.status === "error", function () {
      same("browser.failure-keeps-folder", fileBrowser.currentPath, base);
      same("browser.failure-keeps-listing", names(), beforeNames);
      report("browser.failure-inline", fileBrowser.errorText.length > 0, fileBrowser.errorText);
      same("browser.missing-copy", fileBrowser.errorText, "Can't open missing: the folder doesn't exist. Choose another folder.");
      fileBrowser.navigate(aux + "/no-search");
    });
    step(() => fileBrowser.status !== "loading", function () {
      same("browser.search-permission-keeps-folder", fileBrowser.currentPath, base);
      same("browser.search-permission-copy", fileBrowser.errorText, "Can't open no-search: you don't have permission. Choose another folder.");
      fileBrowser.navigate(base + "/Alpha.txt");
    });
    step(() => fileBrowser.status === "error", function () {
      same("browser.not-folder-copy", fileBrowser.errorText, "Can't open Alpha.txt: it isn't a folder. Choose another folder.");
      fileBrowser.navigate(base + "/folder");
    });
    step(ready, function () {
      same("browser.empty", names(), []);
      fileBrowser.back();
    });
    step(ready, function () {
      same("browser.back", fileBrowser.currentPath, base);
      fileBrowser.forward();
    });
    step(ready, function () {
      same("browser.forward", fileBrowser.currentPath, base + "/folder");
      fileBrowser.up();
    });
    step(ready, function () {
      same("browser.up", fileBrowser.currentPath, base);
      fileBrowser.sortDescending = true;
    });
    step(ready, function () {
      same("browser.descending-folders-first", names(), ["folder", "empty", "item10.png", "item2.txt", "Alpha.txt"]);
      fileBrowser.sortDescending = false;
      fileBrowser.sortKey = "size";
    });
    step(ready, function () {
      same("browser.size", names().slice(2), ["item10.png", "Alpha.txt", "item2.txt"]);
      fileBrowser.sortDescending = true;
    });
    step(ready, function () {
      same("browser.size-descending", names().slice(2), ["item2.txt", "Alpha.txt", "item10.png"]);
      fileBrowser.sortDescending = false;
      fileBrowser.sortKey = "type";
    });
    step(ready, function () {
      same("browser.type", names().slice(2), ["item10.png", "Alpha.txt", "item2.txt"]);
      fileBrowser.sortDescending = true;
    });
    step(ready, function () {
      same("browser.type-descending", names().slice(2), ["item2.txt", "Alpha.txt", "item10.png"]);
      fileBrowser.sortDescending = false;
      fileBrowser.sortKey = "modified";
    });
    step(ready, function () {
      same("browser.modified", names().slice(2), ["item2.txt", "Alpha.txt", "item10.png"]);
      fileBrowser.sortDescending = true;
    });
    step(ready, function () {
      same("browser.modified-descending", names().slice(2), ["item10.png", "Alpha.txt", "item2.txt"]);
      fileBrowser.sortKey = "name";
      fileBrowser.sortDescending = false;
      fileBrowser.showHidden = true;
    });
    step(ready, function () {
      report("browser.show-hidden", names().includes(".hidden.txt"), names());
      fileBrowser.showHidden = false;
      fileBrowser.nameFilter = ["Text", [[0, "*.txt"]]];
    });
    step(ready, function () {
      same("browser.glob-filter-keeps-folders", names(), ["empty", "folder", "Alpha.txt", "item2.txt"]);
      fileBrowser.nameFilter = ["Images", [[1, "image/png"]]];
    });
    step(() => ready() && FileTypes.matchesFilter("item10.png", ["Images", [[1, "image/png"]]]), function () {
      same("browser.mime-filter", names(), ["empty", "folder", "item10.png"]);
      report("types.mime-subclass", FileTypes.matchesFilter("main.py", ["Text", [[1, "text/plain"]]]), "main.py");
      report("types.mime-wildcard", FileTypes.matchesFilter("photo.webp", ["Images", [[1, "image/*"]]]), "photo.webp");
      fileBrowser.nameFilter = null;
    });
    step(ready, function () {
      selection.click(index("folder"), Qt.NoModifier);
      same("selection.file-kind", selection.selectedPaths, []);
      same("selection.folder-cursor", selection.cursor, index("folder"));
      selection.click(index("Alpha.txt"), Qt.NoModifier);
      same("selection.single", selection.selectedPaths, [base + "/Alpha.txt"]);
      selection.multiple = true;
      selection.click(index("item10.png"), Qt.ShiftModifier);
      same("selection.range", selection.selectedPaths, [base + "/Alpha.txt", base + "/item2.txt", base + "/item10.png"]);
      selection.click(index("item2.txt"), Qt.ControlModifier);
      same("selection.toggle", selection.selectedPaths, [base + "/Alpha.txt", base + "/item10.png"]);
      selection.clear();
      selection.move(1, false);
      same("selection.move-to-first", selection.cursor, 0);
      selection.click(index("Alpha.txt"), Qt.NoModifier);
      selection.move(1, true);
      same("selection.shift-move", selection.selectedPaths, [base + "/Alpha.txt", base + "/item2.txt"]);
      selection.clear();
      selection.typeAhead("a");
      same("selection.type-ahead", selection.selectedPaths, [base + "/Alpha.txt"]);
      selection.selectAll();
      same("selection.all-files", selection.selectedPaths.length, 3);
      selection.multiple = false;
      same("selection.single-revalidation", selection.selectedPaths.length, 1);
      selection.selectable = "folders";
      same("selection.kind-revalidation", selection.selectedPaths, []);
      selection.multiple = true;
      selection.selectAll();
      same("selection.all-folders", selection.selectedPaths, [base + "/empty", base + "/folder"]);
      selection.selectable = "files";
      selection.click(index("item10.png"), Qt.NoModifier);
      fileBrowser.nameFilter = ["Text", [[0, "*.txt"]]];
    });
    step(ready, function () {
      same("selection.filter-revalidation", selection.selectedPaths, []);
      fileBrowser.nameFilter = null;
      selection.click(index("Alpha.txt"), Qt.NoModifier);
      fileBrowser.sortDescending = true;
    });
    step(ready, function () {
      same("selection.sort-preserves-path", selection.selectedPaths, [base + "/Alpha.txt"]);
      same("selection.sort-remaps-cursor", fileBrowser.entry(selection.cursor).path, base + "/Alpha.txt");
      fileBrowser.refresh();
    });
    step(ready, function () {
      same("selection.refresh-preserves-path", selection.selectedPaths, [base + "/Alpha.txt"]);
      fileBrowser.navigate(base + "/folder");
    });
    step(ready, function () {
      same("selection.navigation-clears", selection.selectedPaths, []);
      fileBrowser.navigate(base);
      createRequest("save", {
                      current_folder: PortalPaths.encodeBytePath(base).bytes,
                      current_name: "draft.txt",
                      accept_label: "Upload"
                    });
    });
    step(requestReady, function () {
      same("request.accept-label", request.acceptLabel, "Upload");
      same("request.prefilled-name", request.saveName, "draft.txt");
      same("request.no-memory-before-accept", FileChooserMemory.recentLocations, []);
      memoryView.reload();
      memoryView.waitForJob();
      same("request.no-disk-before-accept", memoryView.loaded, false);
      request.cancel();
      request.accept();
      request.cancel();
      same("request.cancel-once", responses.map(r => r.response), [1]);
      same("request.cancel-no-memory", FileChooserMemory.recentLocations, []);
      createRequest("open", {
                      current_folder: [47, 0, 47]
                    });
    });
    step(answered, function () {
      same("request.bad-path-settles-failed", responses.map(r => r.response), [2]);
      request.cancel();
      request.fail("service lost");
      same("request.failed-once", responses.length, 1);
      createRequest("open", {
                      current_file: PortalPaths.encodeBytePath(base + "/Alpha.txt").bytes,
                      choices: [["quality", "Quality", [["low", "Low"], ["high", "High"]], "low"], ["enabled", "Enabled", [], "true"], ["fallback", "Fallback", [["first", "First"], ["next", "Next"]], ""], ["unchecked", "Unchecked", [], ""]],
                      filters: [["Text", [[0, "*.txt"]]]],
                      current_filter: ["Text", [[0, "*.txt"]]]
                    });
    });
    step(requestReady, function () {
      same("request.current-file-folder", request.browser.currentPath, base);
      same("request.preselection", request.selection.selectedPaths, [base + "/Alpha.txt"]);
      same("request.choices-order", request.choices.map(choice => choice[0]), ["quality", "enabled", "fallback", "unchecked"]);
      same("request.choices-defaults", request.choiceValues, {
             quality: "low",
             enabled: "true",
             fallback: "first",
             unchecked: "false"
           });
      request.setChoice("quality", "high");
      request.setChoice("enabled", "false");
      request.accept();
      request.accept();
    });
    step(answered, function () {
      same("request.open-success", responses[0].response, 0);
      same("request.open-uri", responses[0].results.uris, [PortalPaths.pathToUri(base + "/Alpha.txt").uri]);
      same("request.choices", responses[0].results.choices, [["quality", "high"], ["enabled", "false"], ["fallback", "first"], ["unchecked", "false"]]);
      same("request.current-filter", responses[0].results.current_filter, ["Text", [[0, "*.txt"]]]);
      same("request.writable", responses[0].results.writable, true);
      request.cancel();
      request.accept();
      same("request.success-once", responses.length, 1);
      same("memory.success-recorded", FileChooserMemory.folderFor("unit.app"), base);
      createRequest("save", {
                      current_folder: PortalPaths.encodeBytePath(base).bytes,
                      current_name: "item2.txt"
                    });
    });
    step(requestReady, function () {
      request.accept();
    });
    step(() => request.pendingReplace !== "", function () {
      same("request.replace-path", request.pendingReplace, base + "/item2.txt");
      same("request.replace-not-settled", responses, []);
      request.saveName = "new # résumé.txt";
      same("request.edit-invalidates-replace", request.pendingReplace, "");
      request.accept();
    });
    step(answered, function () {
      same("request.save-byte-safe", responses[0].results.uris, [PortalPaths.pathToUri(base + "/new # résumé.txt").uri]);
      createRequest("save", {
                      current_folder: PortalPaths.encodeBytePath(base).bytes,
                      current_name: "item2.txt"
                    });
    });
    step(requestReady, function () {
      request.accept();
    });
    step(() => request.pendingReplace !== "", function () {
      request.browser.navigate(base + "/folder");
      same("request.navigation-invalidates-replace", request.pendingReplace, "");
      request.confirmReplace();
    });
    step(requestReady, function () {
      same("request.navigation-no-stale-result", responses, []);
      request.browser.navigate(base);
    });
    step(requestReady, function () {
      request.accept();
    });
    step(() => request.pendingReplace !== "", function () {
      request.confirmReplace();
    });
    step(answered, function () {
      same("request.replace-confirmed", responses[0].response, 0);
      createRequest("saveFiles", {
                      current_folder: PortalPaths.encodeBytePath(base).bytes,
                      files: [PortalPaths.encodeBytePath("item10.png").bytes, PortalPaths.encodeBytePath("brand-new.txt").bytes, PortalPaths.encodeBytePath("item2.txt").bytes]
                    });
    });
    step(requestReady, function () {
      request.accept();
    });
    step(() => request.pendingReplace !== "", function () {
      same("request.saveFiles-first-replace", request.pendingReplace, base + "/item10.png");
      request.confirmReplace();
    });
    step(() => request.pendingReplace !== "", function () {
      same("request.saveFiles-second-replace", request.pendingReplace, base + "/item2.txt");
      same("request.saveFiles-not-partial", responses, []);
      request.confirmReplace();
    });
    step(answered, function () {
      same("request.saveFiles-order", responses[0].results.uris, ["item10.png", "brand-new.txt", "item2.txt"].map(name => PortalPaths.pathToUri(base + "/" + name).uri));
      createRequest("saveFiles", {
                      current_folder: PortalPaths.encodeBytePath(base).bytes,
                      files: [PortalPaths.encodeBytePath("child.txt").bytes]
                    });
    });
    step(requestReady, function () {
      request.selection.click(request.browser.indexOfPath(base + "/folder"), Qt.NoModifier);
      request.accept();
    });
    step(answered, function () {
      same("request.saveFiles-selected-folder", responses[0].results.uris, [PortalPaths.pathToUri(base + "/folder/child.txt").uri]);
      createRequest("save", {
                      current_folder: PortalPaths.encodeBytePath(base).bytes
                    });
    });
    step(requestReady, function () {
      for (var name of ["", ".", "..", "bad\u0000name"]) {
        request.saveName = name;
        request.accept();
        report("request.invalid-name-" + JSON.stringify(name), request.errorText !== "" && !request.settled, request.errorText);
      }
      request.saveName = "stale.txt";
      request.accept();
      request.cancel();
    });
    step(() => !request.busy, function () {
      same("request.cancel-inflight", responses.map(r => r.response), [1]);
      createRequest("open", {
                      current_folder: PortalPaths.encodeBytePath(base).bytes,
                      directory: true
                    });
    });
    step(requestReady, function () {
      request.accept();
    });
    step(answered, function () {
      same("request.open-current-directory", responses[0].results.uris, [PortalPaths.pathToUri(base).uri]);
      createRequest("open", {
                      current_folder: PortalPaths.encodeBytePath(base).bytes,
                      multiple: true
                    });
    });
    step(requestReady, function () {
      request.selection.selectAll();
      request.accept();
    });
    step(answered, function () {
      same("request.multiple-open", responses[0].results.uris.length, 3);
      createRequest("open", {
                      current_folder: PortalPaths.encodeBytePath(aux + "/vanish").bytes
                    });
    });
    step(requestReady, function () {
      request.selection.click(0, Qt.NoModifier);
      mutate.command = ["timeout", "5", "rm", aux + "/vanish/selected.txt"];
      mutate.running = true;
    });
    step(() => !mutate.running && request.selection.selectedPaths.length === 0, function () {
      same("selection.removed-file-revalidated", request.selection.selectedPaths, []);
      request.accept();
      report("request.removed-file-not-accepted", request.errorText !== "" && !request.settled, request.errorText);
      request.fail("service lost");
      request.cancel();
      same("request.service-loss-once", responses.map(r => r.response), [2]);
      createRequest("open", {
                      current_folder: PortalPaths.encodeBytePath(aux + "/unreadable").bytes
                    });
    });
    step(requestReady, function () {
      request.selection.click(0, Qt.NoModifier);
      request.accept();
    });
    step(() => !request.busy && request.errorText !== "", function () {
      report("request.unreadable-file-inline", !request.settled && responses.length === 0, request.errorText);
      request.cancel();
    });
    buildOverwriteTests();
    step(() => true, function () {
      fileBrowser.navigate(aux + "/denied");
    });
    step(() => fileBrowser.status === "error", function () {
      same("browser.permission-keeps-folder", fileBrowser.currentPath, base);
      same("browser.permission-copy", fileBrowser.errorText, "Can't open denied: you don't have permission. Choose another folder.");
      fileBrowser.navigate(base);
    });
    step(ready, function () {
      createRequest("open", {
                      current_folder: PortalPaths.encodeBytePath(base).bytes
                    });
    });
    step(requestReady, function () {
      var currentPreferences = [request.browser.sortKey, request.browser.sortDescending, request.browser.showHidden, request.viewMode];
      FileChooserMemory.remember("app.a", aux + "/memory0", {
                                   view: "list",
                                   sortKey: "size",
                                   sortDescending: true,
                                   showHidden: true
                                 });
      same("request.preferences-isolated", [request.browser.sortKey, request.browser.sortDescending, request.browser.showHidden, request.viewMode], currentPreferences);
      request.cancel();
      FileChooserMemory.remember("app.b", aux + "/memory1");
      same("memory.per-app-a", FileChooserMemory.folderFor("app.a"), aux + "/memory0");
      same("memory.per-app-b", FileChooserMemory.folderFor("app.b"), aux + "/memory1");
      same("memory.shared-fallback", FileChooserMemory.folderFor(""), aux + "/memory1");
      same("memory.unknown-fallback", FileChooserMemory.folderFor("missing.app"), aux + "/memory1");
      for (var i = 2; i < 12; i++)
        FileChooserMemory.remember("app." + i, aux + "/memory" + i);
      FileChooserMemory.remember("", aux + "/memory10");
      same("memory.top-ten", FileChooserMemory.recentLocations.length, 10);
      same("memory.newest-first-dedupe", FileChooserMemory.recentLocations, [10, 11, 9, 8, 7, 6, 5, 4, 3, 2].map(i => aux + "/memory" + i));
      mutate.command = ["timeout", "5", "rmdir", aux + "/memory9"];
      mutate.running = true;
    });
    step(() => !mutate.running, function () {
      FileChooserMemory.refresh();
    });
    step(() => !FileChooserMemory.recentLocations.includes(aux + "/memory9"), function () {
      report("memory.missing-hidden", !FileChooserMemory.recentLocations.includes(aux + "/memory9"), FileChooserMemory.recentLocations);
      createRequest("open", {}, "app.a");
    });
    step(requestReady, function () {
      same("request.remembered-folder-drives-listing", [request.browser.currentPath, request.browser.count], [aux + "/memory0", 0]);
      request.cancel();
      mutate.command = ["timeout", "5", "rmdir", aux + "/memory1"];
      mutate.running = true;
    });
    step(() => !mutate.running, function () {
      createRequest("open", {}, "app.b");
    });
    step(() => request.browser.status !== "loading", function () {
      same("request.missing-app-folder-fallback", [request.browser.currentPath, request.browser.status], [aux + "/memory10", "ready"]);
      request.cancel();
      fileBrowser.navigate(aux + "/removed");
    });
    step(ready, function () {
      mutate.command = ["timeout", "5", "rmdir", aux + "/removed"];
      mutate.running = true;
    });
    step(() => fileBrowser.currentPath === aux && ready(), function () {
      same("browser.removed-parent-fallback", fileBrowser.currentPath, aux);
      FilePlaces.refresh();
    });
    step(() => !FilePlaces.loading && FilePlaces.places.length > 1, function () {
      report("places.xdg-user-dir", FilePlaces.places.some(p => p.path === aux + "/documents"), FilePlaces.places);
      report("places.bookmark", FilePlaces.places.some(p => p.path === aux + "/bookmark" && p.name === "Test bookmark"), FilePlaces.places);
      report("places.recent-xbel", FilePlaces.recentFiles.some(p => p.path === base + "/Alpha.txt"), FilePlaces.recentFiles);
      memoryView.reload();
      memoryView.waitForJob();
    });
    step(() => memoryView.loaded, function () {
      var state = JSON.parse(memoryView.text());
      same("memory.persisted-app", state.appFolders["app.a"], aux + "/memory0");
      same("memory.persisted-preferences", state.preferences, {
             view: "list",
             sortKey: "size",
             sortDescending: true,
             showHidden: true
           });
    });
    for (let name of ["With space", "hash#name", "percent%20literal", "question?mark", "résumé", "a b/c d"]) {
      let folder = aux + "/escaped/" + name;
      let prefix = "paths." + name + ".";
      step(() => true, function () {
        fileBrowser.navigate(folder);
        staleStarted = Date.now();
      });
      step(() => ready() || Date.now() - staleStarted > 1500, function () {
        same(prefix + "ready", [fileBrowser.currentPath, fileBrowser.status], [folder, "ready"]);
        same(prefix + "listing", names(), ["fixture.txt"]);
        var segments = breadcrumbs.breadcrumbItems.filter(item => item.kind === "segment").map(item => item.text);
        same(prefix + "breadcrumbs", segments.slice(-name.split("/").length), name.split("/"));
        createRequest("open", {
                        current_file: PortalPaths.encodeBytePath(folder + "/fixture.txt").bytes
                      });
        staleStarted = Date.now();
      });
      step(() => requestReady() || Date.now() - staleStarted > 1500, function () {
        same(prefix + "request-ready", [request.browser.currentPath, request.browser.status, request.selection.selectedPaths], [folder, "ready", [folder + "/fixture.txt"]]);
        if (requestReady())
          request.accept();
        else
          request.cancel();
      });
      step(answered, function () {
        var uris = responses[0].results.uris || [];
        var expected = "file://" + (folder + "/fixture.txt").split("/").map(encodeURIComponent).join("/");
        same(prefix + "request-result", [responses[0].response, uris, uris.map(uri => PortalPaths.uriToPath(uri).path)], [0, [expected], [folder + "/fixture.txt"]]);
      });
    }
    step(() => true, function() { fileBrowser.navigate(base); });
    step(ready, function () {
      fileBrowser.nameFilter = null;
      fileBrowser.showHidden = false;
      fileBrowser.filterText = "ALP";
    });
    step(() => fileBrowser.count === 1, function () {
      same("filter.substring-case", names(), ["Alpha.txt"]);
      fileBrowser.nameFilter = ["PNG", [[0, "*.png"]]];
    });
    step(() => fileBrowser.count === 0, function () {
      same("filter.type-intersection", names(), []);
      fileBrowser.nameFilter = null;
      fileBrowser.filterText = "FOLD";
    });
    step(() => fileBrowser.count === 1, function () {
      same("filter.folders", names(), ["folder"]);
      fileBrowser.filterText = "hidden";
    });
    step(() => fileBrowser.count === 0, function () {
      same("filter.hidden-respected", names(), []);
      fileBrowser.showHidden = true;
    });
    step(() => fileBrowser.count === 1, function () {
      same("filter.hidden-opt-in", names(), [".hidden.txt"]);
      fileBrowser.filterText = "item";
      fileBrowser.saveFilterText = "10";
    });
    step(() => fileBrowser.count === 1, function () {
      same("filter.combined-substrings", names(), ["item10.png"]);
      fileBrowser.saveFilterText = "";
      fileBrowser.navigate(aux + "/documents");
    });
    step(ready, function () {
      same("filter.navigation-clears", fileBrowser.filterText, "");
      createRequest("save", {current_folder: PortalPaths.encodeBytePath(base).bytes, current_name: "prefilled.md"});
    });
    step(requestReady, function () {
      same("filter.save-prefill", request.browser.saveFilterText, "");
      request.selection.click(request.browser.indexOfPath(base + "/Alpha.txt"), Qt.NoModifier);
      request.editSaveName("A draft.txt");
    });
    step(() => request.browser.count === 0, function () {
      request.browser.listingChanged();
      same("filter.save-name-revalidation", [request.saveName, request.browser.saveFilterText], ["A draft.txt", "A draft"]);
      request.saveFilterEnabled = false;
      request.editSaveName("Another draft.txt");
    });
    step(() => request.browser.indexOfPath(base + "/Alpha.txt") >= 0, function () {
      same("filter.save-toggle", [request.saveName, request.browser.saveFilterText], ["Another draft.txt", ""]);
      request.cancel();
      fileBrowser.navigate(aux + "/creation");
    });
    step(ready, function () {
      fileBrowser.showHidden = false;
      for (var i = 0, invalid = ["", ".", "..", "child/name", "bad\u0000name"]; i < invalid.length; i++) {
        fileBrowser.createFolder(invalid[i]);
        report("create.invalid-" + i, fileBrowser.creatingFolder && fileBrowser.createFolderError !== "", fileBrowser.createFolderError);
        fileBrowser.cancelCreateFolder();
      }
      fileBrowser.createFolder("Created");
    });
    step(() => ready() && !fileBrowser.creatingFolder, function () {
      report("create.success-model", fileBrowser.indexOfPath(aux + "/creation/Created") >= 0, names());
      fileBrowser.createFolder("Taken");
    });
    step(() => !fileBrowser.createFolderBusy && fileBrowser.createFolderError !== "", function () {
      same("create.exists-directory", fileBrowser.createFolderError, I18n.tr("widgets.file-picker.create-folder-exists"));
      fileBrowser.createFolder("Existing.txt");
    });
    step(() => !fileBrowser.createFolderBusy && fileBrowser.createFolderError !== "", function () {
      same("create.exists-file", fileBrowser.createFolderError, I18n.tr("widgets.file-picker.create-folder-exists"));
      fileBrowser.navigate(aux + "/write-denied");
    });
    step(ready, function () { fileBrowser.createFolder("Denied"); });
    step(() => !fileBrowser.createFolderBusy && fileBrowser.createFolderError !== "", function () {
      same("create.permission", fileBrowser.createFolderError, I18n.tr("widgets.file-picker.create-folder-permission"));
      fileBrowser.navigate(aux + "/readonly");
    });
    step(ready, function () { fileBrowser.createFolder("Read only"); });
    step(() => !fileBrowser.createFolderBusy && fileBrowser.createFolderError !== "", function () {
      same("create.readonly", fileBrowser.createFolderError, I18n.tr("widgets.file-picker.create-folder-readonly"));
      createRequest("open", {current_folder: PortalPaths.encodeBytePath(aux + "/creation").bytes, directory: true});
    });
    step(requestReady, function () { request.beginCreateFolder(); request.browser.createFolder("Folder selection"); });
    step(() => requestReady() && !request.browser.creatingFolder, function () {
      same("create.folder-selection", request.selection.selectedPaths, [aux + "/creation/Folder selection"]);
      request.cancel();
      createRequest("save", {current_folder: PortalPaths.encodeBytePath(aux + "/creation").bytes, current_name: "draft.txt"});
    });
    step(requestReady, function () { request.beginCreateFolder(); request.browser.createFolder("Save folder"); });
    step(() => requestReady() && !request.browser.creatingFolder, function () {
      same("create.save-stays-in-folder", [request.browser.currentPath, request.saveName, request.selection.cursor >= 0], [aux + "/creation", "draft.txt", true]);
      request.cancel();
      tooltipOwner = tooltipOwnerFactory.createObject(root);
      TooltipService.show(tooltipOwner, "Folder action", "auto", 5000);
      tooltipOwner.destroy();
      tooltipOwner = null;
    });
    step(() => !TooltipService.pendingTooltip && !TooltipService.activeTooltip, function () {
      report("tooltip.owner-lifetime", true, null);
      var recent = FileChooserMemory.recentEntries;
      root.expectedRecentFolders = [recent[0].path].concat([0, 6, 5, 4, 3, 2, 1].map(i => aux + "/recent" + i), recent.slice(1, 3).map(entry => entry.path));
      mutate.command = ["timeout", "3", "python3", "-c", `
import json, pathlib, sys, xml.etree.ElementTree as ET
target, aux, memory = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), json.loads(sys.argv[3])
root = ET.Element('xbel')
for i in range(7):
    ET.SubElement(root, 'bookmark', href=(aux / ('recent' + str(i)) / 'removed.txt').as_uri(), modified=f'2099-01-{i + 1:02d}T00:00:00Z')
ET.SubElement(root, 'bookmark', href=(aux / 'recent0/another-removed.txt').as_uri(), modified='2099-01-08T00:00:00Z')
ET.SubElement(root, 'bookmark', href=(pathlib.Path(memory[0]['path']) / 'removed.txt').as_uri(), modified='2100-01-01T00:00:00Z')
ET.SubElement(root, 'bookmark', href=(aux / 'missing-recent/file.txt').as_uri(), modified='2200-01-01T00:00:00Z')
ET.ElementTree(root).write(target, encoding='unicode')
`, Quickshell.env("XDG_DATA_HOME") + "/recently-used.xbel", aux, JSON.stringify(recent)];
      mutate.running = true;
    });
    step(() => !mutate.running, function () { FilePlaces.refresh(); });
    step(() => !FilePlaces.loading && FilePlaces.recentFolders.some(entry => entry.path === aux + "/recent0"), function () {
      var paths = FilePlaces.recentFolders.map(entry => entry.path);
      same("places.recent-folders-merge-order", paths, root.expectedRecentFolders);
      report("places.recent-folders-dedup", paths.filter((path, i) => paths.indexOf(path) === i).length === paths.length, paths);
      report("places.recent-folders-missing", !paths.includes(aux + "/missing-recent"), paths);
      same("places.recent-folders-limit", paths.length, 10);
      report("places.recent-folders-directories", FilePlaces.recentFolders.every(entry => entry.directory === true), FilePlaces.recentFolders);
      fileBrowser.sortKey = "name";
      fileBrowser.sortDescending = false;
      fileBrowser.showHidden = false;
      fileBrowser.navigate(base);
    });
    step(ready, function () {
      selection.selectable = "files";
      selection.multiple = true;
      var alpha = fileBrowser.indexOfPath(base + "/Alpha.txt");
      var second = fileBrowser.indexOfPath(base + "/item2.txt");
      selection.click(alpha, Qt.NoModifier);
      selection.click(second, Qt.ControlModifier);
      selection.click(alpha, Qt.ControlModifier);
      same("selection.ctrl-toggle-removes", selection.selectedPaths, [base + "/item2.txt"]);
      selection.click(alpha, Qt.ControlModifier);
      report("selection.ctrl-toggle-adds", selection.selectedPaths.length === 2 && selection.selectedPaths.includes(base + "/Alpha.txt"), selection.selectedPaths);
      selection.moveTo(fileBrowser.count - 1, false);
      selection.moveTo(alpha, true);
      same("selection.anchor-stable-range", selection.selectedPaths, ["Alpha.txt", "item2.txt", "item10.png"].map(name => base + "/" + name));
      selection.moveTo(fileBrowser.count - 2, true);
      same("selection.range-shrinks-from-anchor", selection.selectedPaths, [base + "/item2.txt", base + "/item10.png"]);
      selection.selectable = "folders";
      selection.moveTo(0, false);
      selection.moveTo(fileBrowser.count - 1, true);
      same("selection.folder-range-kinds", selection.selectedPaths, [base + "/empty", base + "/folder"]);
      selection.multiple = false;
      selection.selectable = "files";
      selection.moveTo(alpha, false);
      selection.moveTo(fileBrowser.count - 1, true);
      selection.selectAll();
      same("selection.single-range-keeps-one", selection.selectedPaths, [base + "/item10.png"]);
      same("browser.path-index-no-prototype-keys", fileBrowser.indexOfPath("constructor"), -1);
      var changed = root.selectionChanges;
      fileBrowser.listingChanged();
      same("selection.revalidation-noop", root.selectionChanges, changed);
    });
    ExtensionCases.build(root, PortalPaths, FileTypes, FileChooserMemory);
    NavigationCases.build(root, fileBrowser, selection);
    PathCases.build(root, PortalPaths, FileChooserMemory, pathCompletion, fileBrowser);
  }

  Component.onCompleted: {
    if (Quickshell.env("FILECHOOSER_UNIT_RELOAD") === "1") {
      step(() => FileChooserMemory.ready, function () {
        same("memory.reload-app", FileChooserMemory.folderFor("app.a"), aux + "/memory0");
        // The escaped-path requests finish successfully after the memory tests.
        same("memory.reload-shared", FileChooserMemory.folderFor(""), aux + "/escaped/a b/c d");
        same("memory.reload-preferences", FileChooserMemory.preferences.view, "list");
        report("memory.reload-missing-hidden", !FileChooserMemory.recentLocations.includes(aux + "/memory9"), FileChooserMemory.recentLocations);
      });
    } else
      buildTests();
  }

  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (++root.ticks > 100) {
        root.report("watchdog", false, {
                      phase: root.phase,
                      status: fileBrowser.status,
                      error: fileBrowser.errorText,
                      requestError: root.request ? root.request.errorText : "",
                      names: root.names()
                    });
        Qt.exit(2);
      }
      if (root.phase >= root.steps.length) {
        Logger.i("FileChooserUnits", "FILECHOOSER_UNITS|" + JSON.stringify({
                                                                             complete: true
                                                                           }));
        Qt.exit(0);
      } else if (root.steps[root.phase].wait()) {
        root.steps[root.phase].run();
        root.phase++;
        root.ticks = 0;
      }
    }
  }
}
