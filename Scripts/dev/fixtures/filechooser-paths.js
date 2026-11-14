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
    root.step(() => root.request.browser.currentPath === folder || Date.now() - root.staleStarted > 1500, function() {
        root.same("path-entry.navigation-keeps-save-name", root.request.saveName, "keep.txt");
        if (typeof root.request.beginNameEdit === "function") root.request.beginNameEdit();
        root.request.editSaveName(root.base + "/folder/");
        root.request.accept();
        root.staleStarted = Date.now();
    });
    root.step(() => root.request.browser.currentPath === root.base + "/folder" || Date.now() - root.staleStarted > 1500, function() {
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
}
