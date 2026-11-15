function build(root, Paths, Memory, completion, browser) {
    var folder = root.aux + "/escaped/hash#name";
    var previousFolder, previousPrefs;
    var watcherCount;
    function request(mode, extra) {
        root.createRequest(mode, Object.assign({current_folder: Paths.encodeBytePath(root.base).bytes}, extra || {}), "unit.paths");
    }
    function submit(text, source) {
        if (typeof root.request.submitPath === "function") root.request.submitPath(text, source);
        else root.report("path-entry.resolver-available", false, text);
        root.staleStarted = Date.now();
    }
    root.step(() => true, function() {
        previousFolder = Memory.folderFor(""); previousPrefs = JSON.parse(JSON.stringify(Memory.preferences));
        request("open");
    });
    root.step(() => root.requestReady(), function() { submit("Alpha.txt", "name"); });
    root.step(() => root.answered() || Date.now() - root.staleStarted > 1000, function() {
        root.same("path-entry.relative-open", root.responses.length ? root.responses[0].results.uris : [], [Paths.pathToUri(root.base + "/Alpha.txt").uri]);
        request("open");
    });
    root.step(() => root.requestReady(), function() { submit(folder, "location"); });
    root.step(() => root.request.browser.currentPath === folder || Date.now() - root.staleStarted > 1500, function() {
        root.same("path-entry.location-navigates", [root.request.browser.currentPath, root.request.settled], [folder, false]);
        submit("fixture.txt", "name");
        root.request.browser.back();
        root.same("path-entry.history-invalidates-typed-intent", root.request.pathResolver.busy, false);
    });
    root.step(() => root.requestReady() && !root.request.busy, function() {
        root.same("path-entry.history-does-not-accept", [root.request.browser.currentPath, root.responses], [root.base, []]);
        root.request.browser.navigate(folder);
    });
    root.step(() => root.requestReady(), function() {
        submit("fixture.txt", "name");
    });
    root.step(() => root.answered() || Date.now() - root.staleStarted > 1000, function() {
        root.same("path-entry.literal-local-name", root.responses.length ? root.responses[0].results.uris : [], [Paths.pathToUri(folder + "/fixture.txt").uri]);
        request("open", {multiple: true});
    });
    root.step(() => root.requestReady(), function() { submit('"Alpha.txt" "item2.txt"', "name"); });
    root.step(() => root.answered() || Date.now() - root.staleStarted > 1000, function() {
        root.same("path-entry.quoted-multiple", root.responses.length ? root.responses[0].results.uris : [], ["Alpha.txt", "item2.txt"].map(n => Paths.pathToUri(root.base + "/" + n).uri));
        request("open");
    });
    root.step(() => root.requestReady(), function() { submit(Paths.pathToUri(folder + "/fixture.txt").uri, "name"); });
    root.step(() => root.answered() || Date.now() - root.staleStarted > 1000, function() {
        root.same("path-entry.local-uri", root.responses.length ? root.responses[0].results.uris : [], [Paths.pathToUri(folder + "/fixture.txt").uri]);
        request("save", {current_name: "keep.txt", filters: [["Text", [[0, "*.txt"]]]]});
    });
    root.step(() => root.requestReady(), function() { submit(folder, "location"); });
    root.step(() => (root.requestReady() && root.request.browser.currentPath === folder) || Date.now() - root.staleStarted > 1500, function() {
        root.same("path-entry.navigation-keeps-save-name", root.request.saveName, "keep.txt");
        if (typeof root.request.beginNameEdit === "function") root.request.beginNameEdit();
        root.request.editSaveName(root.base + "/folder/");
        root.request.accept();
        root.staleStarted = Date.now();
    });
    root.step(() => (root.requestReady() && root.request.browser.currentPath === root.base + "/folder") || Date.now() - root.staleStarted > 1500, function() {
        root.same("path-entry.typed-folder-keeps-save-leaf", [root.request.browser.currentPath, root.request.saveName], [root.base + "/folder", "keep.txt"]);
        submit(root.base + "/folder/new", "name");
    });
    root.step(() => root.answered() || Date.now() - root.staleStarted > 1000, function() {
        root.same("path-entry.save-path-extension", [root.request.saveName, root.responses.length ? root.responses[0].results.uris : []], ["new.txt", [Paths.pathToUri(root.base + "/folder/new.txt").uri]]);
        request("save", {current_name: "folder/report.png", current_filter: ["PNG", [[0, "*.png"]]]});
    });
    root.step(() => root.requestReady(), function() {
        root.request.currentFilter = ["PDF", [[0, "*.pdf"]]];
    });
    root.step(() => !root.request.busy, function() {
        root.same("path-entry.type-change-only-leaf", root.request.saveName, "folder/report.pdf");
        root.request.cancel();
        request("save", {current_name: "missing/name"});
    });
    root.step(() => root.requestReady(), function() { root.request.accept(); root.staleStarted = Date.now(); });
    root.step(() => !root.request.busy && (root.request.errorText || root.request.browser.errorText) !== "", function() {
        root.report("path-entry.missing-save-parent-keeps-input", !root.request.settled && root.request.saveName === "missing/name" && root.request.browser.currentPath === root.base, root.request.errorText || root.request.browser.errorText);
        root.request.cancel();
        request("open");
    });
    for (let value of ["https://example.org/file", "file://remote/file", "bad\u0000name", '"unclosed', '"Alpha.txt" "item2.txt"', "Alpha.txt/"]) {
        root.step(() => root.requestReady(), function() { submit(value, "name"); });
        root.step(() => !root.request.busy && (root.request.errorText !== "" || Date.now() - root.staleStarted > 1000), function() {
            root.report("path-entry.refuse-" + JSON.stringify(value), !root.request.settled && root.request.errorText !== "", root.request.errorText);
        });
    }
    root.step(() => true, function() {
        submit(root.base + "/missing.txt", "name");
    });
    root.step(() => !root.request.busy && (root.request.errorText !== "" || Date.now() - root.staleStarted > 1000), function() {
        root.report("path-entry.missing-keeps-dialog", !root.request.settled && root.request.errorText !== "", root.request.errorText);
        root.request.cancel();
        Memory.remember("", previousFolder, previousPrefs);
        completion.active = true;
        completion.text = "al";
    });
    root.step(() => !completion.busy && completion.suggestions.length > 0, function() {
        root.same("completion.case-prefix", completion.suggestions.map(e => e.name), ["Alpha.txt"]);
        completion.text = "";
        completion.directoriesOnly = true;
    });
    root.step(() => !completion.busy && completion.suggestions.length > 0, function() {
        root.same("completion.directories", completion.suggestions.map(e => e.text), ["empty/", "folder/"]);
        completion.directoriesOnly = false;
        completion.text = ".";
    });
    root.step(() => !completion.busy && completion.suggestions.length > 0, function() {
        root.same("completion.explicit-hidden", completion.suggestions.map(e => e.name), [".hidden.txt"]);
        completion.text = "item";
        completion.nameFilter = ["PNG", [[0, "*.png"]]];
    });
    root.step(() => !completion.busy && completion.suggestions.length > 0, function() {
        root.same("completion.type-filter", completion.suggestions.map(e => e.name), ["item10.png"]);
        completion.nameFilter = null;
        completion.text = folder + "/fix";
    });
    root.step(() => !completion.busy && completion.suggestions.length > 0, function() {
        root.same("completion.literal-folder", completion.suggestions.map(e => e.text), [folder + "/fixture.txt"]);
        completion.text = '"Alpha.txt" "item2';
    });
    root.step(() => !completion.busy && completion.suggestions.length > 0, function() {
        root.same("completion.quoted-last-name", completion.suggestions.map(e => e.text), ['"Alpha.txt" "item2.txt"']);
        completion.text = "item";
        completion.active = false;
        root.same("completion.inactive-invalidates", completion.suggestions, []);
        root.sampleWatchers();
    });
    root.step(() => root.watcherSampleReady(), function() {
        watcherCount = root.watcherCount();
    });
    for (let i = 0; i < 6; i++) {
        root.step(() => true, function() { browser.navigate(root.aux + "/model%watch" + i); });
        root.step(() => root.ready(), function() {});
    }
    root.step(() => true, function() { root.sampleWatchers(); });
    root.step(() => root.watcherSampleReady(), function() {
        root.report("path-entry.folder-watches-bounded", Number.isFinite(watcherCount) && watcherCount > 0 && root.watcherCount() <= watcherCount, {before: watcherCount, after: root.watcherCount()});
    });

    for (let intent of ["band", "all", "restore"]) {
        let expected;
        root.step(() => true, function() { request("open", {multiple: true}); });
        root.step(() => root.requestReady(), function() {
            var selection = root.request.selection, listing = root.request.browser;
            var alpha = listing.indexOfPath(root.base + "/Alpha.txt");
            var other = listing.indexOfPath(root.base + "/item2.txt");
            if (intent === "all") selection.selectAll();
            root.request.editOpenName("Alpha.txt");
            if (intent === "band") {
                selection.beginBand(Qt.NoModifier, other);
                selection.updateBand([other]);
                selection.endBand(other);
                expected = [root.base + "/item2.txt"];
            } else if (intent === "all") {
                selection.selectAll(); // Also replace Name when the path set is unchanged.
                expected = selection.selectedPaths.slice();
            } else {
                selection.restore({paths: [root.base + "/item2.txt"], cursor: root.base + "/item2.txt"});
                selection.moveTo(alpha, false, true);
                expected = [root.base + "/Alpha.txt"];
            }
            root.request.accept();
            root.staleStarted = Date.now();
        });
        root.step(() => root.answered() || Date.now() - root.staleStarted > 1500, function() {
            root.same("path-entry." + intent + "-name-intent", root.responses.length ? root.responses[0].results.uris : [], expected.map(path => Paths.pathToUri(path).uri));
        });
    }
    root.step(() => true, function() { request("open"); });
    root.step(() => root.requestReady(), function() {
        var selection = root.request.selection;
        var alpha = root.request.browser.indexOfPath(root.base + "/Alpha.txt");
        selection.click(alpha, Qt.NoModifier);
        root.request.accept();
        selection.click(alpha, Qt.NoModifier);
        root.staleStarted = Date.now();
    });
    root.step(() => root.answered() || Date.now() - root.staleStarted > 1500, function() {
        root.same("path-entry.same-selection-keeps-acceptance", root.responses.length ? root.responses[0].results.uris : [], [Paths.pathToUri(root.base + "/Alpha.txt").uri]);
    });
    root.step(() => true, function() { request("save", {current_name: "draft.txt"}); });
    root.step(() => root.requestReady(), function() {
        root.request.beginNameEdit();
        root.request.editSaveName("report.txt");
        submit(folder, "location");
    });
    root.step(() => (root.requestReady() && root.request.browser.currentPath === folder) || Date.now() - root.staleStarted > 1500, function() {
        root.report("path-entry.location-navigation-ready", root.requestReady() && root.request.browser.currentPath === folder,
            {path: root.request.browser.currentPath, status: root.request.browser.status});
        root.same("path-entry.location-keeps-edited-save-name", root.request.saveName, "report.txt");
        request("open");
    });
    var links = root.aux + "/path-links";
    root.step(() => root.requestReady(), function() { submit(links + "/link/../Report.txt", "name"); });
    root.step(() => root.answered() || Date.now() - root.staleStarted > 1500, function() {
        root.same("path-entry.symlink-parent-open", root.responses.length ? root.responses[0].results.uris : [], [Paths.pathToUri(links + "/target/Report.txt").uri]);
        request("save");
    });
    root.step(() => root.requestReady(), function() { submit(links + "/link/../New.txt", "name"); });
    root.step(() => root.answered() || Date.now() - root.staleStarted > 1500, function() {
        root.same("path-entry.symlink-parent-new-save", root.responses.length ? root.responses[0].results.uris : [], [Paths.pathToUri(links + "/target/New.txt").uri]);
        request("open");
    });
    root.step(() => root.requestReady(), function() { submit(links + "/missing/../Report.txt", "name"); });
    root.step(() => !root.request.busy && (root.answered() || root.request.errorText || Date.now() - root.staleStarted > 1500), function() {
        root.report("path-entry.missing-parent-not-invented", !root.request.settled && root.request.errorText !== "", root.responses);
        root.request.cancel();
        request("open");
    });
    root.step(() => root.requestReady(), function() { submit(links + "/target/Report.txt/.", "name"); });
    root.step(() => !root.request.busy && (root.answered() || root.request.errorText || Date.now() - root.staleStarted > 1500), function() {
        root.report("path-entry.file-dot-not-a-file", !root.request.settled && root.request.errorText !== "", root.responses);
        root.request.cancel();
        browser.navigate(links + "/link/..");
        root.staleStarted = Date.now();
    });
    root.step(() => root.ready() || Date.now() - root.staleStarted > 1500, function() {
        root.same("path-entry.symlink-parent-browser", browser.currentPath, links + "/target");
        completion.active = true;
        completion.text = Paths.pathToUri(root.aux + "/completion-uris/report").uri;
        root.staleStarted = Date.now();
    });
    root.step(() => !completion.busy && (completion.suggestions.length > 0 || Date.now() - root.staleStarted > 1500), function() {
        root.report("completion.file-uri-roundtrip", completion.suggestions.length === 5 && completion.suggestions.every(entry => {
            var decoded = Paths.uriToPath(entry.text);
            return decoded.ok && decoded.path === root.aux + "/completion-uris/" + entry.name;
        }), completion.suggestions);
        completion.text = Paths.pathToUri(root.aux + "/completion-uris/report%").uri;
        root.staleStarted = Date.now();
    });
    root.step(() => !completion.busy && (completion.suggestions.length > 0 || Date.now() - root.staleStarted > 1500), function() {
        root.same("completion.file-uri-encoded-stem", completion.suggestions.map(entry => entry.name), ["report%20draft.txt"]);
        completion.active = false;
        Memory.remember("", previousFolder, previousPrefs);
        browser.navigate(root.base);
    });
    root.step(() => root.ready(), function() {});
}
