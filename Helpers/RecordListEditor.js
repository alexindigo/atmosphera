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

function record(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }

function selector(segment) {
    if (!record(segment))
        throw new Error("list-edit-operation");
    var keys = Object.keys(segment).sort().join(",");
    if (keys === "key" && typeof segment.key === "string" && segment.key.length)
        return "key";
    if (keys === "index" && Number.isSafeInteger(segment.index) && segment.index >= 0)
        return "index";
    if (keys === "equals,field" && typeof segment.field === "string" && segment.field.length && typeof segment.equals === "string")
        return "match";
    throw new Error("list-edit-operation");
}

// Resolves only a private candidate when creation is requested. The legacy
// adapter's supported paths determine container kind structurally; C2 uses schema.
function resolveList(value, address, ensure, createFinal) {
    if (!Array.isArray(address))
        throw new Error("list-edit-operation");
    var missing = false;
    for (var i = 0; i < address.length; ++i) {
        var segment = address[i];
        var kind = selector(segment);
        if (kind === "index") {
            if (!Array.isArray(value) || segment.index >= value.length)
                throw new Error("list-edit-operation");
            value = value[segment.index];
        } else if (kind === "match") {
            if (!Array.isArray(value) || !value.every(record))
                throw new Error("list-edit-operation");
            var found = value.find(function (entry) { return typeof entry[segment.field] === "string" && entry[segment.field] === segment.equals; });
            if (!found) {
                if (!ensure)
                    return null;
                found = Object.create(null);
                Object.defineProperty(found, segment.field, {value: segment.equals, enumerable: true, configurable: true, writable: true});
                value.push(found);
                missing = true;
            }
            value = found;
        } else {
            if (!record(value))
                throw new Error("list-edit-operation");
            if (!Object.prototype.hasOwnProperty.call(value, segment.key)) {
                if (!ensure && !(createFinal && i === address.length - 1))
                    return null;
                var next = i + 1 < address.length ? selector(address[i + 1]) : "list";
                Object.defineProperty(value, segment.key, {value: next === "key" ? Object.create(null) : [], enumerable: true, configurable: true, writable: true});
                missing = true;
            }
            value = value[segment.key];
        }
    }
    if (!Array.isArray(value))
        throw new Error("list-edit-operation");
    return {list: value, present: !missing};
}

function listAt(value, address) {
    try {
        var resolved = resolveList(value, address, false, false);
        return resolved ? resolved.list : null;
    } catch (error) { return null; }
}

function edited(value, address, edits, ensure) {
    var candidate = copy(value);
    var resolved = resolveList(candidate, address, ensure === true, false);
    var list = resolved ? resolved.list : null;
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
        try {
            if (!resolveList(copy(owner.base), address, target.ensure === true, false))
                return null;
        } catch (error) { return null; }
        selections.push({policyId: target.policyId, address: address, ensure: target.ensure === true, owner: owner});
    }
    if (selections.length === 0)
        return null;
    var closed = false;
    var busy = false;
    var conflicted = false;
    var editor;
    function matches(selectedOwners) {
        return selectedOwners.every(function (owner) {
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
        var primary = selections[0];
        var resolved = resolveList(copy(primary.owner.base), primary.address, primary.ensure, false);
        editor.initialValue = copy(resolved.list);
        editor.generation = selections[0].owner.captured;
    }
    function endpoint(value, indexed, source) {
        var fields = indexed ? "generation,index,listAddress,policyId" : "generation,listAddress,policyId";
        if (!record(value))
            throw new Error("list-edit-operation");
        var ensured = Object.prototype.hasOwnProperty.call(value, "ensure");
        if ((ensured && (source || typeof value.ensure !== "boolean"))
                || Object.keys(value).filter(function (key) { return key !== "ensure"; }).sort().join(",") !== fields
                || typeof value.policyId !== "string" || typeof value.generation !== "string"
                || !/^[0-9]+$/.test(value.generation) || !Array.isArray(value.listAddress)
                || (indexed && (!Number.isSafeInteger(value.index) || value.index < 0)))
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
    function capturedTarget(targetIndex, ensure) {
        var selection = selections[targetIndex === undefined ? 0 : targetIndex];
        if (!selection || (ensure !== undefined && typeof ensure !== "boolean"))
            return null;
        var result = {policyId: selection.policyId, listAddress: copy(selection.address), generation: selection.owner.captured};
        if (ensure === true || (ensure === undefined && selection.ensure))
            result.ensure = true;
        return result;
    }
    editor = {
        initialValue: null,
        generation: "",
        // The caller treats policyId as opaque. Both endpoints come from this
        // captured session, not the current owner at the later menu/drop callback.
        target: capturedTarget,
        endpoint: function (index, targetIndex, ensure) {
            var result = capturedTarget(targetIndex, ensure);
            if (!result || !Number.isSafeInteger(index) || index < 0)
                return null;
            // Bounds are evaluated sequentially at submit, after any copy/ensure.
            result.index = index;
            return result;
        },
        submit: function (edits, callback) {
            if (closed || busy) {
                failed(closed ? "list-editor-closed" : "list-editor-busy", callback);
                return false;
            }
            var activeOwners = [selections[0].owner];
            if (conflicted || !matches(activeOwners)) {
                conflicted = true;
                failed("list-edit-conflict", callback);
                return false;
            }
            var candidates = owners.map(function (owner) { return {owner: owner, value: copy(owner.base), touched: false}; });
            function candidate(selection) { return candidates[owners.indexOf(selection.owner)]; }
            function activate(selection) {
                if (activeOwners.indexOf(selection.owner) === -1)
                    activeOwners.push(selection.owner);
            }
            try {
                var commands = copy(edits);
                if (!Array.isArray(commands) || commands.length === 0)
                    throw new Error("list-edit-operation");
                // Check every endpoint against the initial captured generations
                // before any sequential operation changes an index or list.
                commands.forEach(function (edit) {
                    if (record(edit) && (edit.op === "transfer" || edit.op === "copy")) {
                        if (Object.keys(edit).sort().join(",") !== "from,op,to")
                            throw new Error("list-edit-operation");
                        activate(endpoint(edit.from, edit.op === "transfer", true));
                        activate(endpoint(edit.to, edit.op === "transfer", false));
                    } else if (record(edit) && Object.prototype.hasOwnProperty.call(edit, "at")) {
                        activate(endpoint(edit.at, false, false));
                    }
                });
                if (!matches(activeOwners)) {
                    conflicted = true;
                    throw new Error("list-edit-conflict");
                }
                commands.forEach(function (edit) {
                    if (record(edit) && (edit.op === "transfer" || edit.op === "copy")) {
                        var from = endpoint(edit.from, edit.op === "transfer", true);
                        var to = endpoint(edit.to, edit.op === "transfer", false);
                        var source = candidate(from);
                        var destination = candidate(to);
                        var sourceList = listAt(source.value, from.address);
                        if (!sourceList || !sourceList.every(record))
                            throw new Error("list-edit-operation");
                        if (edit.op === "copy") {
                            var inherited = copy(sourceList);
                            var resolved = resolveList(destination.value, to.address, edit.to.ensure === true, true);
                            if (!resolved || resolved.present)
                                throw new Error("list-edit-operation");
                            // Old-owner projection is identity. The C2 worker
                            // checks source/destination display equivalence here.
                            inherited.forEach(function (row) { resolved.list.push(row); });
                            destination.touched = true;
                            return;
                        }
                        if (!sourceList || edit.from.index >= sourceList.length || !record(sourceList[edit.from.index]))
                            throw new Error("list-edit-operation");
                        var moved = sourceList.splice(edit.from.index, 1)[0];
                        var targetList = resolveList(destination.value, to.address, edit.to.ensure === true, false);
                        var destinationList = targetList ? targetList.list : null;
                        if (!destinationList || edit.to.index > destinationList.length)
                            throw new Error("list-edit-operation");
                        destinationList.splice(edit.to.index, 0, moved);
                        source.touched = true;
                        destination.touched = true;
                    } else {
                        var selected = Object.prototype.hasOwnProperty.call(edit || {}, "at") ? endpoint(edit.at, false, false) : selections[0];
                        var local = copy(edit);
                        var ensure = Object.prototype.hasOwnProperty.call(local, "at") ? local.at.ensure === true : selected.ensure;
                        delete local.at;
                        var owner = candidate(selected);
                        owner.value = edited(owner.value, selected.address, [local], ensure);
                        owner.touched = true;
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
                var current = matches(activeOwners);
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
