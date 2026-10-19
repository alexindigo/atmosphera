import QtQuick
import Quickshell
import Quickshell.Io
import "../../../Helpers/PortalPaths.js" as PortalPaths
import qs.Commons
import qs.Modules.FileChooser
import qs.Services.Files

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

  FilePreview {
    id: preview
  }

  FileBrowser {
    id: fileBrowser
  }
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
  Process {
    id: mutate
    stdout: StdioCollector {}
  }

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

  function buildTests() {
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
      same("request.choices-defaults", request.choiceValues, {quality: "low", enabled: "true", fallback: "first", unchecked: "false"});
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
      for (var name of ["", ".", "..", "bad/name", "bad\u0000name"]) {
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
    for (let name of ["With space", "résumé", "a b/c d"]) {
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
    for (let name of ["hash#name", "percent%20literal", "question?mark"]) {
      let folder = aux + "/escaped/" + name;
      let prefix = "paths." + name + ".";
      step(() => true, function () {
        fileBrowser.navigate(base);
      });
      step(ready, function () {
        beforeNames = names();
        fileBrowser.navigate(folder);
        staleStarted = Date.now();
      });
      step(() => fileBrowser.status === "error" || Date.now() - staleStarted > 1500, function () {
        same(prefix + "error", [fileBrowser.status, fileBrowser.errorText], ["error", "Can't open " + name + ": folder names with #, ? or % aren't supported yet."]);
        same(prefix + "keeps-folder", fileBrowser.currentPath, base);
        same(prefix + "keeps-listing", names(), beforeNames);
        report(prefix + "not-loading", fileBrowser.status !== "loading", fileBrowser.status);
        fileBrowser.navigate(base);
      });
      step(ready, function () {
        same(prefix + "recovers", [fileBrowser.currentPath, names()], [base, beforeNames]);
      });
    }
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
