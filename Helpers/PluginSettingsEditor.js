.pragma library

// Old-owner preparation only. The injected owner selects a plugin value and,
// for instances, its complete owning leaf. I5 replaces these value stamps with
// configqml draft/overlay handles; this adapter cannot detect equal-value ABA.
function create(options) {
    var expected = options.stamp();
    if (expected === null)
        return null;
    var closed = false;
    var busy = false;
    var editor = null;
    function copy(value) { return JSON.parse(JSON.stringify(value)); }
    function failed(code, callback) {
        options.later(function () {
            if (typeof callback === "function")
                callback({status: "failed", refreshState: "not_refreshed", error: {code: code}});
        });
    }
    function submit(value, reset, callback) {
        if (closed || busy) {
            failed(closed ? "editor-closed" : "editor-busy", callback);
            return;
        }
        if (options.stamp() !== expected) {
            failed("editor-conflict", callback);
            return;
        }
        var submitted = reset ? null : copy(value);
        busy = true;
        var admittedStamp = null;
        try {
            var accepted = options.commit(submitted, reset, function (result) {
                busy = false;
                var success = result && (result.status === "saved" || result.status === "nothing_to_save");
                var current = success && admittedStamp !== null && options.stamp() === admittedStamp;
                if (current)
                    editor.initialValue = copy(options.value());
                if (typeof callback === "function")
                    callback(Object.assign({}, result || {status: "failed", error: {code: "editor-save"}}, {
                        refreshState: success ? (current ? "current" : "stale") : "not_refreshed"
                    }));
            });
            if (accepted) {
                // An IO failure leaves admitted old-owner input live. Retry may
                // use that own value; it must not silently recapture foreign work.
                admittedStamp = options.stamp();
                expected = admittedStamp;
            }
        } catch (error) {
            busy = false;
            failed("editor-input", callback);
        }
    }
    editor = {
        initialValue: copy(options.value()),
        apply: function (value, callback) { submit(value, false, callback); },
        resetOverrides: function (callback) { submit(null, true, callback); },
        discard: function () {
            if (busy)
                return false;
            closed = true;
            return true;
        }
    };
    return editor;
}
