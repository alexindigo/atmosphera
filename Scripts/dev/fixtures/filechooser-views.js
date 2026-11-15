// View preferences are request-local until the existing successful finish gate.
function build(root, Paths, Memory) {
    var previous, previousFolder, expected;
    function ready() { return root.requestReady() && !root.request.busy; }
    root.step(() => true, function() {
        previous = JSON.parse(JSON.stringify(Memory.preferences));
        previousFolder = Memory.folderFor("");
        root.createRequest("open", {current_folder: Paths.encodeBytePath(root.base).bytes}, "unit.views");
    });
    root.step(ready, function() {
        var v = root.request.viewSettings;
        root.report("views.owner", !!v, null);
        if (!v) return;
        root.same("views.defaults", [v.mode, v.zoom, v.iconSize, v.thumbnails], ["list", 1, 20, true]);
        v.mode = "grid"; v.setZoom(4);
        v.mode = "compact"; v.setZoom(2);
        v.mode = "list"; v.setZoom(3);
        v.mode = "grid";
        root.same("views.per-mode-zoom", [v.zoom, v.iconSize], [4, 112]);
        v.setZoom(100); root.same("views.zoom-upper-bound", v.zoom, 6);
        v.setZoom(-20); root.same("views.zoom-lower-bound", v.zoom, 0);
        v.wheelZoom(60, false); root.same("views.partial-wheel", v.zoom, 0);
        v.wheelZoom(60, false); root.same("views.accumulated-wheel", v.zoom, 1);
        v.wheelZoom(-20, true); v.wheelZoom(-20, true);
        root.same("views.pixel-wheel", v.zoom, 0);
        v.setZoom(4); v.thumbnails = false;
        var before = v.widths(700);
        v.resizeColumn(0, 35, 700);
        var after = v.widths(700);
        root.report("views.column-adjacent-resize", Math.abs(after[0] - before[0] - 35) < .01
            && Math.abs(after[1] - before[1] + 35) < .01 && Math.abs(after[2] - before[2]) < .01, after);
        v.resizeColumn(1, 10000, 700);
        root.report("views.column-minima", v.widths(700).every((w, i) => w >= v.columnMinima[i]), v.widths(700));
        v.setDialogSize(6000, 5000);
        root.same("views.no-arbitrary-dialog-cap", [v.dialogWidth, v.dialogHeight], [6000, 5000]);
        v.setDialogSize(1180, 720);
        expected = v.snapshot();
        root.same("views.no-write-before-success", Memory.preferences, previous);
        root.request.selection.click(root.request.browser.indexOfPath(root.base + "/Alpha.txt"), Qt.NoModifier);
        root.request.accept();
    });
    root.step(() => root.answered() || !root.request.viewSettings, function() {
        if (!root.request.viewSettings) return;
        root.same("views.persist-success", Memory.preferences.views, expected);
        root.createRequest("open", {current_folder: Paths.encodeBytePath(root.base).bytes}, "unit.views.next");
    });
    root.step(ready, function() {
        var v = root.request.viewSettings;
        if (!v) return;
        root.same("views.next-request", v.snapshot(), expected);
        v.mode = "compact"; v.setZoom(5); v.setDialogSize(1000, 600);
        root.request.cancel();
        root.same("views.cancel-no-write", Memory.preferences.views, expected);
        v.restore({mode: "bogus", zooms: {grid: -1, compact: 50, list: "bad"}, columns: [null, -1, 0], width: "bad", height: -5});
        root.same("views.sanitize", [v.mode, v.zooms, v.columnShares, v.dialogWidth, v.dialogHeight],
            ["grid", {grid: 0, compact: 6, list: 1}, [.55, .16, .29], 1100, 740]);
        // Leave the old folder/top-level preferences intact, with a distinctive
        // view snapshot for the separate-process reload consumer below.
        Memory.remember("", previousFolder, Object.assign({}, previous, {views: Object.assign({}, expected, {mode: "list"})}));
    });
}
