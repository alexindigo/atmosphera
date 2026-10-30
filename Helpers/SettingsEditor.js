.pragma library

// Transitional selected-value adapter for the old owner. I5 replaces this
// factory with revision-fenced configqml drafts; UI only consumes the interface.
// Never snapshot, merge or diff the complete settings graph here.
function create(read, write, save, later) {
    var base = read();
    var busy = false;
    var closed = false;
    function failed(code, callback) {
        later(function () {
            if (typeof callback === "function")
                callback({status: "failed", error: {code: code}});
        });
    }
    return {
        initialValue: base,
        apply: function (value, callback) {
            if (closed || busy) {
                failed(closed ? "editor-closed" : "editor-busy", callback);
                return;
            }
            // These selected leaves are scalar (including idle's JSON string).
            // Checking before assignment prevents stale placement/index writes.
            if (read() !== base) {
                failed("editor-conflict", callback);
                return;
            }
            busy = true;
            try {
                write(value);
                base = value;
                save(function (result) {
                    busy = false;
                    if (typeof callback === "function")
                        callback(result);
                });
            } catch (error) {
                busy = false;
                failed("editor-input", callback);
            }
        },
        discard: function () {
            if (busy)
                return false;
            closed = true;
            return true;
        }
    };
}
