function build(root, Paths) {
    var folder = root.aux + "/operations", ops;
    function ready() { return root.requestReady() && (!ops || !ops.busy); }
    function choose(name) { root.request.selection.click(root.request.browser.indexOfPath(folder + "/" + name), Qt.NoModifier); }
    root.step(() => true, function() {
        root.createRequest("save", {current_folder: Paths.encodeBytePath(folder).bytes, current_name: "keep.txt"}, "unit.operations");
    });
    root.step(() => root.requestReady(), function() {
        ops = root.request.browser.operations;
        root.report("operations.single-owner", !!ops, !!ops);
    });
    // Old trees report red without throwing or truncating the preceding suite.
    root.step(ready, function() { if (ops) { choose("first.txt"); ops.beginRename(); ops.rename("renamed #%.txt"); } });
    root.step(() => ready() && (!ops || root.request.browser.indexOfPath(folder + "/renamed #%.txt") >= 0), function() {
        if (!ops) return;
        root.same("operations.rename-model-selection-name", [root.request.selection.selectedPaths, root.request.saveName, ops.renaming], [[folder + "/renamed #%.txt"], "renamed #%.txt", false]);
        ops.beginRename(); ops.rename("taken.txt");
    });
    root.step(() => ready() && (!ops || ops.renameError !== ""), function() {
        if (!ops) return;
        root.report("operations.rename-no-overwrite", ops.renaming && ops.renameError !== "", ops.renameError);
        ops.rename("../outside");
        root.report("operations.rename-invalid", ops.renameError !== "", ops.renameError);
        ops.cancelRename();
        choose("renamed #%.txt"); ops.trash();
    });
    root.step(() => ready() && (!ops || root.request.browser.indexOfPath(folder + "/renamed #%.txt") < 0), function() {
        if (!ops) return;
        root.same("operations.trash-reconciles", [root.request.selection.selectedPaths, root.request.selection.cursor], [[], -1]);
        choose("directory"); ops.requestDelete();
    });
    root.step(() => ready() && (!ops || ops.pendingDelete.length > 0), function() {
        if (!ops) return;
        root.report("operations.delete-awaits-confirmation", root.request.browser.indexOfPath(folder + "/directory") >= 0, ops.pendingDelete);
        ops.declineDelete();
        root.same("operations.delete-decline-retains", [ops.pendingDelete, root.request.settled], [[], false]);
        ops.requestDelete();
    });
    root.step(() => ready() && (!ops || ops.pendingDelete.length > 0), function() { if (ops) ops.confirmDelete(); });
    root.step(() => ready() && (!ops || root.request.browser.indexOfPath(folder + "/directory") < 0), function() {
        if (!ops) return;
        root.same("operations.delete-reconciles", [root.request.selection.selectedPaths, ops.pendingDelete], [[], []]);
        root.request.browser.beginCreateFolder(); root.request.browser.createFolder("new folder");
    });
    root.step(() => ready() && (!ops || root.request.browser.indexOfPath(folder + "/new folder") >= 0), function() {
        if (!ops) return;
        root.same("operations.create-shares-owner", [ops.creatingFolder, root.request.selection.cursor], [false, root.request.browser.indexOfPath(folder + "/new folder")]);
        choose("taken.txt"); ops.beginRename(); root.request.browser.navigate(root.base);
    });
    root.step(ready, function() {
        if (ops) root.same("operations.navigation-retires-intents", [ops.renaming, ops.pendingDelete], [false, []]);
        root.request.cancel();
        root.createRequest("open", {current_folder: Paths.encodeBytePath(folder).bytes, current_filter: ["Text", [[0, "*.txt"]]]}, "unit.operations-filter");
        ops = null;
    });
    root.step(() => root.requestReady(), function() {
        ops = root.request.browser.operations;
        if (ops) { choose("taken.txt"); ops.beginRename(); ops.rename("filtered-out.png"); }
        root.staleStarted = Date.now();
    });
    root.step(() => !ops || !ops.busy || Date.now() - root.staleStarted > 1500, function() {
        if (ops) root.report("operations.rename-filtered-out-finishes", !ops.busy && !ops.renaming && root.request.browser.indexOfPath(folder + "/filtered-out.png") < 0, ops.busy);
        root.request.cancel();
    });
}
