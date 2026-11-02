.pragma library
.import "RecordListEditor.js" as Lists

// An interaction owns its original source row and possible destinations. UI
// components receive only this command interface, never persistence handles.
function capture(options, section, index) {
    var sections = Lists.copy(options.sections);
    var primary = sections.find(function (entry) { return entry.id === section; });
    if (!primary || !Number.isSafeInteger(index) || index < 0 || index >= primary.length)
        return null;
    var local = options.createEditor(primary.path, primary.listAddress);
    if (!local || index >= local.initialValue.length)
        return null;
    var transfers = [];
    for (var i = 0; i < sections.length; ++i) {
        var target = sections[i];
        if (target.id === section)
            continue;
        var editor = options.createEditor(primary.path, primary.listAddress, [
            {path: target.path, listAddress: target.listAddress}
        ]);
        if (!editor) {
            local.detach();
            transfers.forEach(function (entry) { entry.editor.detach(); });
            return null;
        }
        transfers.push({id: target.id, editor: editor, command: {
            op: "transfer", from: editor.endpoint(index), to: editor.endpoint(target.length, 1)
        }});
    }
    var initial = Lists.copy(local.initialValue[index]);
    var busy = false;
    var closed = false;
    var used = false;
    function fail(code, callback) {
        options.later(function () {
            if (typeof callback === "function")
                callback({status: "failed", error: {code: code}});
        });
        return false;
    }
    return {
        initialValue: Lists.copy(initial),
        submit: function (action, destination, callback) {
            if (closed || busy || used)
                return fail(closed || used ? "list-editor-closed" : "list-editor-busy", callback);
            if (options.isCurrent && !options.isCurrent())
                return fail("list-edit-conflict", callback);
            var editor = local;
            var edits;
            if (action === "remove") {
                edits = [{op: "remove", index: index}];
            } else if (action === "reorder") {
                edits = [{op: "move", index: index, to: destination}];
            } else if (action === "move") {
                var target = transfers.find(function (entry) { return entry.id === destination; });
                if (!target)
                    return fail("list-edit-operation", callback);
                editor = target.editor;
                edits = [target.command];
            } else {
                return fail("list-edit-operation", callback);
            }
            busy = true;
            var accepted = editor.submit(edits, function (result) {
                busy = false;
                if (result.status === "admitted" && result.refreshState === "current")
                    options.onChanged(action, Lists.copy(initial));
                if (typeof callback === "function")
                    callback(result);
            });
            // An interaction is one user action. Persistence retries never
            // replay a membership edit, and another action captures anew.
            used = accepted;
            return accepted;
        },
        detach: function () {
            closed = true;
            local.detach();
            transfers.forEach(function (entry) { entry.editor.detach(); });
        }
    };
}
