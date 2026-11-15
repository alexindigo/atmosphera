function build(root, browser, selection) {
    root.step(() => root.ready(), function() {
        selection.selectable = "files";
        selection.multiple = true;
        var alpha = browser.indexOfPath(root.base + "/Alpha.txt");
        var other = browser.indexOfPath(root.base + "/item10.png");
        selection.click(alpha, Qt.NoModifier);
        selection.moveTo(other, false, true);
        root.same("navigation.cursor-only-keeps-selection", selection.selectedPaths, [root.base + "/Alpha.txt"]);
        root.same("navigation.cursor-only-keeps-anchor", selection.anchor, alpha);
        if (typeof selection.toggleCurrent === "function") {
            selection.toggleCurrent();
            root.same("navigation.keyboard-toggle-adds", selection.selectedPaths.slice().sort(), [root.base + "/Alpha.txt", root.base + "/item10.png"].sort());
            selection.toggleCurrent();
            root.same("navigation.keyboard-toggle-removes", selection.selectedPaths, [root.base + "/Alpha.txt"]);
        } else root.report("navigation.keyboard-toggle-available", false, null);
        selection.multiple = false;
        selection.click(alpha, Qt.NoModifier);
        selection.click(alpha, Qt.ControlModifier);
        root.same("navigation.single-Ctrl-deselects", selection.selectedPaths, []);
        selection.click(alpha, Qt.ControlModifier);
        selection.click(other, Qt.ControlModifier);
        root.same("navigation.single-Ctrl-keeps-one", selection.selectedPaths, [root.base + "/item10.png"]);
        selection.multiple = true;
        selection.click(alpha, Qt.NoModifier);
        if (typeof selection.beginBand === "function") {
            selection.beginBand(Qt.ControlModifier, alpha);
            selection.updateBand([alpha, other]);
            root.same("navigation.band-symmetric", selection.selectedPaths, [root.base + "/item10.png"]);
            selection.updateBand([alpha, other]);
            root.same("navigation.band-idempotent", selection.selectedPaths, [root.base + "/item10.png"]);
            selection.updateBand([]);
            root.same("navigation.band-retract-restores", selection.selectedPaths, [root.base + "/Alpha.txt"]);
            selection.endBand(alpha);
            selection.beginBand(Qt.ShiftModifier, alpha);
            selection.updateBand([other]);
            root.same("navigation.band-additive", selection.selectedPaths.slice().sort(), [root.base + "/Alpha.txt", root.base + "/item10.png"].sort());
            selection.endBand(other);
            selection.background(Qt.ControlModifier);
            root.same("navigation.modified-background-keeps", selection.selectedPaths.length, 2);
            selection.background(Qt.NoModifier);
            root.same("navigation.background-clears", [selection.selectedPaths, selection.cursor], [[], -1]);
            selection.multiple = false;
            selection.click(alpha, Qt.NoModifier);
            selection.beginBand(Qt.NoModifier, alpha);
            selection.updateBand([alpha, other]);
            selection.endBand(other);
            root.same("navigation.single-band-ignored", selection.selectedPaths, [root.base + "/Alpha.txt"]);
        } else root.report("navigation.band-available", false, null);
    });
}
