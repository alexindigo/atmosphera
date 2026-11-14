// Request-level extension consumer cases. Existing overwrite tests stay intact.
function build(root, Paths, Types, Memory) {
    var folder = root.aux + "/extensions";
    var png = ["PNG", [[0, "*.png"]]];
    var pdf = ["PDF", [[0, "*.pdf"]]];
    var archive = ["Archive", [[0, "*.tar.gz"]]];
    var previousFolder, previousPrefs;
    function step(wait, run) { root.step(wait, run); }
    function ready() { return root.requestReady() && !root.request.busy; }
    function answered() { return root.answered(); }
    function save(name, filter) {
        root.createRequest("save", {current_folder: Paths.encodeBytePath(folder).bytes,
            current_name: name, filters: [png, pdf, archive], current_filter: filter || png}, "unit.extensions");
    }
    function expect(name, target) {
        root.same("extensions." + name, [root.responses[0].response, root.responses[0].results.uris,
            root.request.saveName], [0, [Paths.pathToUri(folder + "/" + target).uri], target]);
    }
    step(() => true, function() {
        previousFolder = Memory.folderFor("");
        previousPrefs = JSON.parse(JSON.stringify(Memory.preferences));
        save("picture");
    });
    step(ready, function() {
        root.same("extensions.default-on", root.request.autoExtension === true, true);
        root.request.accept();
    });
    step(answered, function() { expect("append-and-display", "picture.png"); });
    for (let item of [["dotfile", ".hidden", png, ".hidden.png"],
                      ["compound", "bundle", archive, "bundle.tar.gz"],
                      ["suppression", "README.", png, "README"],
                      ["existing-raw", "raw", png, "raw"],
                      ["no-guess", "report", ["Special", [[0, "photo-*.p?g"]]], "report"],
                      ["allowed-alternative", "photo.jpeg", ["JPEG", [[0, "*.jpg"], [0, "*.jpeg"]]], "photo.jpeg"]]) {
        step(() => true, function() { save(item[1], item[2]); });
        step(ready, function() { root.request.accept(); });
        if (item[0] === "existing-raw") {
            step(() => root.request.pendingReplace !== "", function() {
                root.same("extensions.existing-raw-confirm", root.request.pendingReplace, folder + "/raw");
                root.request.confirmReplace();
            });
        }
        step(answered, function() { expect(item[0], item[3]); });
    }
    step(() => true, function() { save("bundle.tar.gz", archive); });
    step(ready, function() { root.request.currentFilter = pdf; });
    step(ready, function() {
        root.same("extensions.type-change-compound", root.request.saveName, "bundle.pdf");
        root.request.accept();
    });
    step(answered, function() { expect("type-change-result", "bundle.pdf"); save("ignored"); });
    step(ready, function() {
        root.request.selection.click(root.request.browser.indexOfPath(folder + "/protected.png"), Qt.NoModifier);
        root.request.currentFilter = pdf;
    });
    step(ready, function() {
        root.same("extensions.type-change-selected", root.request.saveName, "protected.pdf");
        root.request.cancel();
        save("protected");
    });
    step(ready, function() { root.request.accept(); });
    step(() => root.request.pendingReplace !== "" || answered(), function() {
        root.same("extensions.final-target-confirm", [root.request.pendingReplace, root.request.saveName, root.responses],
            [folder + "/protected.png", "protected.png", []]);
        root.request.cancel();
        save("directory");
    });
    step(ready, function() { root.request.accept(); });
    step(() => !root.request.busy && (root.request.errorText !== "" || answered()), function() {
        root.report("extensions.directory-not-retargeted", !root.request.settled && root.request.errorText !== ""
            && root.request.saveName === "directory" && !root.request.pendingReplace, root.request.errorText);
        root.request.cancel();
        save("plain");
    });
    step(ready, function() {
        if (root.request.autoExtension !== undefined) root.request.autoExtension = false;
        root.request.accept();
    });
    step(answered, function() { expect("opt-out", "plain"); save("next"); });
    step(ready, function() {
        root.same("extensions.opt-out-remembered", root.request.autoExtension === false, true);
        if (root.request.autoExtension !== undefined) root.request.autoExtension = true;
        root.request.cancel();
        Memory.remember("", previousFolder, previousPrefs);
    });
    step(() => Memory.ready, function() {
        if (typeof Types.saveSuffixes === "function") {
            root.same("extensions.bracket-glob", Types.saveSuffixes(["PNG", [[0, "*.[pP][nN][gG]"]]]), ["png"]);
            root.same("extensions.no-wildcard-invention", Types.saveSuffixes(["Any images", [[1, "image/*"]]]), []);
            root.report("extensions.mime-suffix", Types.saveSuffixes(["PNG", [[1, "image/png"]]]).includes("png"), null);
        } else root.report("extensions.policy-available", false, null);
    });
}
