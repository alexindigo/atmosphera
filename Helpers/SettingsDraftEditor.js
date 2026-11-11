.pragma library

// Selected scalar UI adapter. The native draft owns the baseline, intent and
// ABA/conflict fences; this object contains only UI lifetime and callbacks.
function create(store, path, later) {
    var parts = typeof path === "string" ? path.split(".") : path.slice();
    var draft;
    try { draft = store.draft([parts]); }
    catch (error) { return null; }
    if (!draft)
        return null;
    var closed = false;
    function node() {
        var value = draft.values;
        for (var i = 0; i < parts.length - 1; ++i)
            value = value[parts[i]];
        return value;
    }
    var editor = {
        initialValue: node()[parts[parts.length - 1]],
        apply: function (value, callback) {
            if (closed || draft.busy) {
                later(function () {
                    if (typeof callback === "function")
                        callback({status: "failed", error: {code: closed ? "editor-closed" : "editor-busy"}});
                });
                return false;
            }
            try {
                node()[parts[parts.length - 1]] = value;
                return draft.apply(function (result) {
                    if (result.status !== "failed")
                        editor.initialValue = node()[parts[parts.length - 1]];
                    if (typeof callback === "function")
                        callback(result);
                });
            } catch (error) {
                later(function () {
                    if (typeof callback === "function")
                        callback({status: "failed", error: {code: "editor-input"}});
                });
                return false;
            }
        },
        discard: function () {
            if (closed || draft.busy)
                return false;
            draft.detach();
            closed = true;
            return true;
        }
    };
    return editor;
}
