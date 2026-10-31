.pragma library

// Transitional command adapter for the old Settings owner, not a raw settings
// mirror. I5 replaces the factory with configqml's captured editRecordList calls.
function nextGeneration(value) {
    var digits = value.split("");
    for (var i = digits.length - 1; i >= 0; --i) {
        if (digits[i] !== "9") {
            digits[i] = String(Number(digits[i]) + 1);
            return digits.join("");
        }
        digits[i] = "0";
    }
    return "1" + digits.join("");
}

// Null-prototype records avoid QV4's QVariant conversion interpreting an own
// __proto__ member as prototype metadata. Sort keys for stable value fences:
// the old QObject owner may reorder dictionary members during admission.
function copy(value, ancestors) {
    if (value === null || typeof value === "string" || typeof value === "boolean")
        return value;
    if (typeof value === "number" && Number.isFinite(value))
        return value;
    if (typeof value !== "object")
        throw new Error("list-edit-input");
    var parents = ancestors || [];
    if (parents.length >= 64 || parents.indexOf(value) !== -1)
        throw new Error("list-edit-input");
    var next = parents.concat([value]);
    // The legacy owner exposes QML list<var> sequences, not JS Arrays. Like the
    // existing consumer slice boundaries, copy their indexed values explicitly.
    if (Array.isArray(value) || (Number.isSafeInteger(value.length) && value.length >= 0 && typeof value.slice === "function")) {
        var items = [];
        for (var i = 0; i < value.length; ++i)
            items.push(copy(value[i], next));
        return items;
    }
    var result = Object.create(null);
    Object.keys(value).sort().forEach(function (key) { result[key] = copy(value[key], next); });
    return result;
}

function stamp(value) { return JSON.stringify(copy(value)); }

function listAt(value, address) {
    for (var i = 0; i < address.length; ++i) {
        var segment = address[i];
        if (!segment || Object.keys(segment).length !== 1)
            return null;
        if (Object.prototype.hasOwnProperty.call(segment, "index")) {
            if (!Number.isSafeInteger(segment.index) || segment.index < 0 || !Array.isArray(value) || segment.index >= value.length)
                return null;
            value = value[segment.index];
        } else if (typeof segment.key === "string" && value && Object.prototype.hasOwnProperty.call(value, segment.key)) {
            value = value[segment.key];
        } else {
            return null;
        }
    }
    return Array.isArray(value) ? value : null;
}

function record(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }

// Validate the complete batch on a private selected leaf before any owner write.
// Existing records receive only explicit field intent, never a display-row copy.
function edited(value, address, edits) {
    var candidate = copy(value);
    var list = listAt(candidate, address);
    if (!list || !Array.isArray(edits) || edits.length === 0)
        throw new Error("list-edit-operation");
    for (var i = 0; i < edits.length; ++i) {
        var edit = edits[i];
        if (!record(edit) || !Number.isSafeInteger(edit.index) || edit.index < 0)
            throw new Error("list-edit-operation");
        var fields = {set: "field,index,op,value", unset: "field,index,op", remove: "index,op", insert: "index,op,value", move: "index,op,to"};
        if (!Object.prototype.hasOwnProperty.call(fields, edit.op) || Object.keys(edit).sort().join(",") !== fields[edit.op])
            throw new Error("list-edit-operation");
        if (edit.op === "insert") {
            if (edit.index > list.length || !record(edit.value))
                throw new Error("list-edit-operation");
            list.splice(edit.index, 0, copy(edit.value));
            continue;
        }
        if (edit.index >= list.length || !record(list[edit.index]))
            throw new Error("list-edit-operation");
        if (edit.op === "remove") {
            list.splice(edit.index, 1);
        } else if (edit.op === "move") {
            if (!Number.isSafeInteger(edit.to) || edit.to < 0 || edit.to >= list.length)
                throw new Error("list-edit-operation");
            var row = list.splice(edit.index, 1)[0];
            list.splice(edit.to, 0, row);
        } else {
            if (typeof edit.field !== "string" || edit.field.length === 0)
                throw new Error("list-edit-operation");
            if (edit.op === "unset")
                delete list[edit.index][edit.field];
            else
                Object.defineProperty(list[edit.index], edit.field, {value: copy(edit.value), enumerable: true, configurable: true, writable: true});
        }
    }
    return candidate;
}

function create(options) {
    var address = copy(options.listAddress);
    var base = copy(options.read());
    if (!listAt(base, address))
        return null;
    var generation = options.generation();
    var expected = stamp(base);
    var closed = false;
    var busy = false;
    var conflicted = false;
    var editor;
    function matches() { return options.generation() === generation && stamp(options.read()) === expected; }
    function failed(code, callback) {
        options.later(function () {
            if (typeof callback === "function")
                callback({status: "failed", error: {code: code}});
        });
    }
    editor = {
        initialValue: copy(listAt(base, address)),
        generation: generation,
        submit: function (edits, callback) {
            if (closed || busy) {
                failed(closed ? "list-editor-closed" : "list-editor-busy", callback);
                return false;
            }
            if (conflicted || !matches()) {
                conflicted = true;
                failed("list-edit-conflict", callback);
                return false;
            }
            var candidate;
            try {
                candidate = edited(base, address, copy(edits));
            } catch (error) {
                failed("list-edit-operation", callback);
                return false;
            }
            busy = true;
            try {
                options.write(candidate);
            } catch (error) {
                busy = false;
                conflicted = true;
                failed("list-edit-input", callback);
                return false;
            }
            // Signal listeners may already have submitted a newer owner value.
            // Never adopt it as this session's base, including before callback.
            generation = options.generation();
            expected = stamp(candidate);
            options.later(function () {
                var current = matches();
                conflicted = !current;
                if (current) {
                    base = copy(candidate);
                    editor.initialValue = copy(listAt(base, address));
                    editor.generation = generation;
                }
                busy = false;
                if (typeof callback === "function")
                    callback({status: "admitted", refreshState: current ? "current" : "stale", generation: generation});
            });
            return true;
        },
        detach: function () { closed = true; }
    };
    return editor;
}
