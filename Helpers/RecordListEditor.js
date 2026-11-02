.pragma library

// Transitional selected-leaf command adapter. I5 replaces these value fences
// and ordinary legacy setters with the declared worker editRecordList command.
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
    // QML list<var> sequences are not JS Arrays.
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
    var owners = [];
    var selections = [];
    for (var i = 0; i < options.targets.length; ++i) {
        var target = options.targets[i];
        var owner = owners.find(function (entry) { return entry.id === target.ownerId; });
        if (!owner) {
            var base = copy(target.read());
            owner = {id: target.ownerId, read: target.read, write: target.write, generation: target.generation,
                     captured: target.generation(), base: base, expected: stamp(base)};
            owners.push(owner);
        }
        var address = copy(target.listAddress);
        if (!listAt(owner.base, address))
            return null;
        selections.push({policyId: target.policyId, address: address, owner: owner});
    }
    if (selections.length === 0)
        return null;
    var closed = false;
    var busy = false;
    var conflicted = false;
    var editor;
    function matches() {
        return owners.every(function (owner) {
            return owner.generation() === owner.captured && stamp(owner.read()) === owner.expected;
        });
    }
    function failed(code, callback) {
        options.later(function () {
            if (typeof callback === "function")
                callback({status: "failed", error: {code: code}});
        });
    }
    function refresh() {
        editor.initialValue = copy(listAt(selections[0].owner.base, selections[0].address));
        editor.generation = selections[0].owner.captured;
    }
    function endpoint(value) {
        if (!record(value) || Object.keys(value).sort().join(",") !== "generation,index,listAddress,policyId"
                || typeof value.policyId !== "string" || typeof value.generation !== "string"
                || !/^[0-9]+$/.test(value.generation) || !Number.isSafeInteger(value.index) || value.index < 0
                || !Array.isArray(value.listAddress))
            throw new Error("list-edit-operation");
        var selection = selections.find(function (entry) {
            return entry.policyId === value.policyId && stamp(entry.address) === stamp(value.listAddress);
        });
        if (!selection)
            throw new Error("list-edit-operation");
        if (value.generation !== selection.owner.captured)
            throw new Error("list-edit-conflict");
        return selection;
    }
    editor = {
        initialValue: null,
        generation: "",
        // The caller treats policyId as opaque. Both endpoints come from this
        // captured session, not the current owner at the later menu/drop callback.
        endpoint: function (index, targetIndex) {
            var selection = selections[targetIndex === undefined ? 0 : targetIndex];
            if (!selection || !Number.isSafeInteger(index) || index < 0 || index > listAt(selection.owner.base, selection.address).length)
                return null;
            return {policyId: selection.policyId, listAddress: copy(selection.address), generation: selection.owner.captured, index: index};
        },
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
            var candidates = owners.map(function (owner) { return {owner: owner, value: copy(owner.base), touched: false}; });
            function candidate(selection) { return candidates[owners.indexOf(selection.owner)]; }
            try {
                var commands = copy(edits);
                if (!Array.isArray(commands) || commands.length === 0)
                    throw new Error("list-edit-operation");
                // Check every endpoint against the initial captured generations
                // before any sequential operation changes an index or list.
                commands.forEach(function (edit) {
                    if (record(edit) && edit.op === "transfer") {
                        if (Object.keys(edit).sort().join(",") !== "from,op,to")
                            throw new Error("list-edit-operation");
                        endpoint(edit.from);
                        endpoint(edit.to);
                    }
                });
                commands.forEach(function (edit) {
                    if (record(edit) && edit.op === "transfer") {
                        var from = endpoint(edit.from);
                        var to = endpoint(edit.to);
                        var source = candidate(from);
                        var destination = candidate(to);
                        var sourceList = listAt(source.value, from.address);
                        if (!sourceList || edit.from.index >= sourceList.length || !record(sourceList[edit.from.index]))
                            throw new Error("list-edit-operation");
                        var moved = sourceList.splice(edit.from.index, 1)[0];
                        var destinationList = listAt(destination.value, to.address);
                        if (!destinationList || edit.to.index > destinationList.length)
                            throw new Error("list-edit-operation");
                        destinationList.splice(edit.to.index, 0, moved);
                        source.touched = true;
                        destination.touched = true;
                    } else {
                        var primary = candidate(selections[0]);
                        primary.value = edited(primary.value, selections[0].address, [edit]);
                        primary.touched = true;
                    }
                });
            } catch (error) {
                failed(error.message === "list-edit-conflict" ? "list-edit-conflict" : "list-edit-operation", callback);
                return false;
            }
            busy = true;
            try {
                candidates.forEach(function (entry) {
                    if (entry.touched)
                        entry.owner.write(entry.value);
                });
            } catch (error) {
                busy = false;
                conflicted = true;
                failed("list-edit-input", callback);
                return false;
            }
            candidates.forEach(function (entry) {
                if (entry.touched) {
                    entry.owner.captured = entry.owner.generation();
                    entry.owner.expected = stamp(entry.value);
                }
            });
            options.later(function () {
                var current = matches();
                conflicted = !current;
                if (current) {
                    candidates.forEach(function (entry) { entry.owner.base = copy(entry.value); });
                    refresh();
                }
                busy = false;
                if (typeof callback === "function")
                    callback({status: "admitted", refreshState: current ? "current" : "stale", generation: selections[0].owner.captured});
            });
            return true;
        },
        detach: function () { closed = true; }
    };
    refresh();
    return editor;
}
