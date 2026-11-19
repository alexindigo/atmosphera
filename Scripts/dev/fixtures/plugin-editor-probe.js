.pragma library

// Observe an actual editor without replacing its readiness, values or receipts.
// Callers own their assertions; this test-only proxy owns no preference state.
function observe(editor, onApply, deliver, afterApply) {
    if (!editor)
        throw new Error("editor probe requires an actual editor");
    var probe = Object.create(null);
    ["initialValue", "values", "previewValues", "ready", "busy", "dirty", "error", "fields", "rebased", "writable"].forEach(function (key) {
        Object.defineProperty(probe, key, {enumerable: true, get: function () { return editor[key]; }});
    });
    ["whenReady", "discard", "resetOverrides", "snapshot", "copyValue", "previewScope"].forEach(function (method) {
        if (typeof editor[method] === "function") {
            probe[method] = function () { return editor[method].apply(editor, arguments); };
        }
    });
    probe.apply = function (value, callback) {
        onApply(value);
        var request = editor.apply(value, function (result) {
            if (deliver) deliver(result, callback);
            else callback(result);
        });
        if (afterApply) afterApply();
        return request;
    };
    return probe;
}
