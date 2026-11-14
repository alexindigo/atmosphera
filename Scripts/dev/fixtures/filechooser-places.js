// Places edits are explicit actions, independent of accepting the chooser.
function build(root, Paths, Places) {
    var b, s, prettyAccepted = false, favorite = root.aux + "/escaped/hash#name";
    root.step(() => true, function() {
        root.report("places.editable-owner", typeof Places.addFavorite === "function", null);
        if (typeof Places.addFavorite === "function") {
            var watching = true;
            Places.editingChanged.connect(function() {
                if (watching && !Places.editing) {
                    watching = false;
                    root.report("places.favorite-edit-completes-at-consumer", Places.favorites.some(p => p.path === favorite), Places.favorites);
                }
            });
            Places.addFavorite(favorite);
        }
        root.createRequest("open", {current_folder: Paths.encodeBytePath(root.base).bytes, multiple: true}, "unit.places");
    });
    root.step(() => root.requestReady() && !Places.loading, function() {
        if (typeof Places.addFavorite === "function") {
            root.report("places.favorite-add", Places.favorites.some(p => p.path === favorite), Places.favorites);
            Places.moveFavorite(favorite, -1);
        }
        b = root.request.browser; s = root.request.selection;
        s.click(b.indexOfPath(root.base + "/Alpha.txt"), Qt.NoModifier);
        s.click(b.indexOfPath(root.base + "/item2.txt"), Qt.ControlModifier);
        b.navigate(root.base + "/empty");
    });
    root.step(() => root.requestReady() && b.currentPath.endsWith("/empty") && !Places.loading, function() {
        if (typeof Places.addFavorite === "function") {
            root.same("places.favorite-reorder", Places.favorites[0].path, favorite);
            Places.removeFavorite(favorite);
        }
        b.back();
    });
    root.step(() => root.requestReady() && b.currentPath === root.base && !Places.loading, function() {
        root.same("places.history-selection", s.selectedPaths, [root.base + "/Alpha.txt", root.base + "/item2.txt"]);
        root.same("places.history-cursor", b.entry(s.cursor) ? b.entry(s.cursor).name : "", "item2.txt");
        if (typeof Places.addFavorite === "function") root.report("places.favorite-remove", !Places.favorites.some(p => p.path === favorite), Places.favorites);
        root.report("places.drop-owner", typeof root.request.locateDrop === "function", null);
        if (typeof root.request.locateDrop === "function") root.request.locateDrop([Paths.pathToUri(root.aux + "/escaped/hash#name/fixture.txt").uri]);
    });
    root.step(() => typeof root.request.locateDrop !== "function" || (root.requestReady() && b.currentPath.endsWith("hash#name")), function() {
        if (typeof root.request.locateDrop === "function") {
            root.same("places.drop-locates-file", s.selectedPaths, [root.aux + "/escaped/hash#name/fixture.txt"]);
            root.same("places.drop-does-not-accept", root.responses.length, 0);
            var before = b.currentPath;
            root.same("places.drop-rejects-network", root.request.locateDrop(["https://example.invalid/file"]), false);
            root.same("places.drop-rejects-many", root.request.locateDrop(["file:///one", "file:///two"]), false);
            root.same("places.drop-invalid-keeps-path", b.currentPath, before);
        }
        if (typeof root.request.locateDrop === "function") {
            prettyAccepted = root.request.locateDrop([Paths.pathToUri(root.aux + "/escaped/With space/fixture.txt").uri.replace(/%20/g, " ")]);
            root.report("places.drop-pretty-QUrl", prettyAccepted, null);
        }
    });
    root.step(() => !prettyAccepted || (root.requestReady() && b.currentPath.endsWith("With space")), function() {
        if (prettyAccepted) root.same("places.drop-pretty-consumer", s.selectedPaths, [root.aux + "/escaped/With space/fixture.txt"]);
        root.request.cancel();
    });
}
