.pragma library

// Display DTOs and command envelopes only. Selection, raw row mapping, edits,
// validation and persistent intent belong to ConfigStore.editRecordList.
function own(value, key) {
    var descriptor = Object.getOwnPropertyDescriptor(value, key);
    return descriptor ? descriptor.value : undefined;
}

function copy(value, parents) {
    if (value === null || typeof value === "string" || typeof value === "boolean")
        return value;
    if (typeof value === "number" && Number.isFinite(value))
        return value;
    if (typeof value !== "object")
        throw new Error("list-edit-input");
    var ancestors = parents || [];
    if (ancestors.length >= 64 || ancestors.indexOf(value) !== -1)
        throw new Error("list-edit-input");
    var next = ancestors.concat([value]);
    if (Array.isArray(value) || (Number.isSafeInteger(value.length) && typeof value.slice === "function")) {
        var items = [];
        for (var i = 0; i < value.length; ++i)
            items.push(copy(value[i], next));
        return items;
    }
    var result = Object.create(null);
    Object.keys(value).forEach(function (key) { result[key] = copy(own(value, key), next); });
    return result;
}

function sequence(value) {
    return value !== null && typeof value === "object" && Number.isSafeInteger(value.length)
            && value.length >= 0 && typeof value.slice === "function";
}

function selector(value) {
    if (!value || typeof value !== "object" || Array.isArray(value))
        return "";
    var keys = Object.keys(value).sort().join(",");
    if (keys === "key" && typeof value.key === "string" && value.key.length)
        return "key";
    if (keys === "index" && Number.isSafeInteger(value.index) && value.index >= 0)
        return "index";
    if (keys === "equals,field" && value.field === "name" && typeof value.equals === "string")
        return "match";
    return "";
}

// Addresses are selectors, not serialized records. Native owned copies may
// reorder record keys without changing the selected row/container.
function addressIdentity(address) {
    if (!Array.isArray(address))
        return "";
    var parts = [];
    for (var i = 0; i < address.length; ++i) {
        var part = address[i];
        var kind = selector(part);
        if (!kind)
            return "";
        parts.push(kind === "match" ? [kind, part.field, part.equals]
            : [kind, kind === "index" ? part.index : part.key]);
    }
    return JSON.stringify(parts);
}

function policy(path, address) {
    if (!Array.isArray(path) || !Array.isArray(address))
        return "";
    var key = JSON.stringify(path);
    if (address.length === 0) {
        var fixed = {
            '["bar","widgets","left"]': "bar-left",
            '["bar","widgets","center"]': "bar-center",
            '["bar","widgets","right"]': "bar-right",
            '["controlCenter","shortcuts","left"]': "shortcuts-left",
            '["controlCenter","shortcuts","right"]': "shortcuts-right",
            '["bar","screenOverrides"]': "bar-screens",
            '["desktopWidgets","monitorWidgets"]': "desktop-monitors"
        };
        return own(fixed, key) || "";
    }
    if (["index", "match"].indexOf(selector(address[0])) === -1
            || selector(address[1]) !== "key" || address[1].key !== "widgets")
        return "";
    if (key === '["desktopWidgets","monitorWidgets"]' && address.length === 2)
        return "desktop-widgets";
    if (key === '["bar","screenOverrides"]' && address.length === 3
            && selector(address[2]) === "key" && ["left", "center", "right"].indexOf(address[2].key) !== -1)
        return "screen-" + address[2].key;
    return "";
}

function display(store, target) {
    var value = store.values;
    for (var p = 0; p < target.path.length; ++p)
        value = value[target.path[p]];
    for (var a = 0; a < target.address.length; ++a) {
        var part = target.address[a];
        var kind = selector(part);
        if (kind === "index") {
            if (!sequence(value) || part.index >= value.length)
                return null;
            value = value[part.index];
        } else if (kind === "match") {
            if (!sequence(value))
                return null;
            var match;
            for (var i = 0; i < value.length; ++i) {
                if (value[i] && own(value[i], part.field) === part.equals) {
                    match = value[i];
                    break;
                }
            }
            if (match === undefined)
                return target.ensure ? [] : null;
            value = match;
        } else {
            if (!value || typeof value !== "object")
                return null;
            value = own(value, part.key);
            if (value === undefined)
                return target.ensure ? [] : null;
        }
    }
    return sequence(value) ? store.copyValue(value) : null;
}

function settled(info) {
    // Decimal counters must never pass through JS Number.
    return typeof info.latestInput === "string" && typeof info.workerCovered === "string"
            && (info.latestInput.length < info.workerCovered.length
                || (info.latestInput.length === info.workerCovered.length && info.latestInput <= info.workerCovered));
}

function create(store, path, listAddress, additionalLists, captureOptions, later) {
    if (!store.ready || (additionalLists !== undefined && !Array.isArray(additionalLists)))
        return null;
    function optionsValid(options) {
        return options === undefined || options === null || (typeof options === "object" && !Array.isArray(options)
            && Object.keys(options).join(",") === "ensure" && typeof options.ensure === "boolean");
    }
    if (!optionsValid(captureOptions))
        return null;
    var selections = [{path: path, listAddress: listAddress, ensure: captureOptions?.ensure === true}].concat(additionalLists || []);
    var targets = [];
    try {
        for (var i = 0; i < selections.length; ++i) {
            var selected = selections[i];
            if (!selected || (selected.ensure !== undefined && typeof selected.ensure !== "boolean"))
                return null;
            var id = policy(selected.path, selected.listAddress);
            if (!id)
                return null;
            var info = store.info(selected.path);
            if (!info.declared || !settled(info))
                return null;
            var target = {policyId: id, path: selected.path.slice(), address: copy(selected.listAddress),
                          ensure: selected.ensure === true, captured: info};
            if (display(store, target) === null)
                return null;
            targets.push(target);
        }
    } catch (error) { return null; }
    var closed = false;
    var busy = false;
    var conflicted = false;
    var editor;
    function failed(code, callback) {
        later(function () {
            if (typeof callback === "function")
                callback({status: "failed", refreshState: "not_refreshed", error: {code: code}});
        });
        return false;
    }
    function current(target) {
        var info = store.info(target.path);
        return settled(info) && info.pathGeneration === target.captured.pathGeneration
                && info.publicationGeneration === target.captured.publicationGeneration;
    }
    function registeredEndpoint(endpoint) {
        return targets.find(function (target) {
            return endpoint && target.policyId === endpoint.policyId
                    && addressIdentity(target.address) === addressIdentity(endpoint.listAddress);
        });
    }
    function selectedEndpoint(endpoint) {
        var target = registeredEndpoint(endpoint);
        return target && target.captured.publicationGeneration === endpoint.generation ? target : null;
    }
    function endpoint(targetIndex, ensure) {
        var target = targets[targetIndex === undefined ? 0 : targetIndex];
        if (!target || (ensure !== undefined && typeof ensure !== "boolean"))
            return null;
        var value = {policyId: target.policyId, listAddress: copy(target.address), generation: target.captured.publicationGeneration};
        if (ensure === true || (ensure === undefined && target.ensure))
            value.ensure = true;
        return value;
    }
    // Preserve the command facade's synchronous shape/range refusal without
    // replaying preference values. Only list lengths change during validation;
    // row mapping, schema admission and all actual edits stay on the worker.
    function validateRanges(commands) {
        var lengths = targets.map(function (target) { return display(store, target).length; });
        function index(value, size, insertion) {
            if (!Number.isSafeInteger(value) || value < 0 || value > size || (!insertion && value === size))
                throw new Error("list-edit-operation");
        }
        commands.forEach(function (edit) {
            if (edit.op === "transfer" || edit.op === "copy") {
                var from = targets.indexOf(selectedEndpoint(edit.from));
                var to = targets.indexOf(selectedEndpoint(edit.to));
                if (from < 0 || to < 0) throw new Error("list-edit-operation");
                if (edit.op === "copy") {
                    // Copy inherits the entire raw list, not an indexed row.
                    // The worker checks destination absence and raw projection.
                    lengths[to] = lengths[from];
                    return;
                }
                index(edit.from.index, lengths[from], false);
                index(edit.to.index, lengths[to] - (from === to ? 1 : 0), true);
                lengths[from]--;
                lengths[to]++;
                return;
            }
            var target = edit.at ? targets.indexOf(selectedEndpoint(edit.at)) : 0;
            if (target < 0) throw new Error("list-edit-operation");
            var selected = edit.index;
            if (["set", "unset", "remove", "insert", "move"].indexOf(edit.op) === -1)
                throw new Error("list-edit-operation");
            index(selected, lengths[target], edit.op === "insert");
            if (edit.op === "insert") lengths[target]++;
            else if (edit.op === "remove") lengths[target]--;
            else if (edit.op === "move") index(edit.to, lengths[target], false);
            else if (typeof edit.field !== "string" || !edit.field.length) throw new Error("list-edit-operation");
        });
    }
    editor = {
        initialValue: display(store, targets[0]),
        generation: targets[0].captured.publicationGeneration,
        target: endpoint,
        endpoint: function (index, targetIndex, ensure) {
            var value = endpoint(targetIndex, ensure);
            if (!value || !Number.isSafeInteger(index) || index < 0)
                return null;
            value.index = index;
            return value;
        },
        submit: function (edits, callback) {
            if (closed || busy)
                return failed(closed ? "list-editor-closed" : "list-editor-busy", callback);
            if (conflicted || !current(targets[0])) {
                conflicted = true;
                return failed("list-edit-conflict", callback);
            }
            var commands;
            var active = [targets[0]];
            try {
                commands = store.copyValue(edits);
                if (!Array.isArray(commands) || commands.length === 0)
                    throw new Error("list-edit-operation");
                commands.forEach(function (edit) {
                    var endpoints = edit.op === "transfer" || edit.op === "copy" ? [edit.from, edit.to] : edit.at ? [edit.at] : [];
                    endpoints.forEach(function (value) {
                        var target = selectedEndpoint(value);
                        if (!target && registeredEndpoint(value) && typeof value.generation === "string"
                                && /^(0|[1-9][0-9]*)$/.test(value.generation))
                            throw new Error("list-edit-conflict");
                        if (!target)
                            throw new Error("list-edit-operation");
                        if (active.indexOf(target) === -1)
                            active.push(target);
                    });
                });
            } catch (error) { return failed(error.message === "list-edit-conflict" ? "list-edit-conflict" : "list-edit-operation", callback); }
            if (!active.every(current)) {
                conflicted = true;
                return failed("list-edit-conflict", callback);
            }
            try { validateRanges(commands); }
            catch (error) { return failed("list-edit-operation", callback); }
            busy = true;
            var submitted;
            try {
                store.editRecordList(targets[0].policyId, {
                    generation: editor.generation, listAddress: targets[0].address,
                    ensure: targets[0].ensure, edits: commands
                }, function (result) {
                    busy = false;
                    if (closed)
                        return;
                    var fresh = result.status === "admitted" && active.every(function (target, index) {
                        var now = store.info(target.path);
                        return settled(now) && now.pathGeneration === submitted[index].pathGeneration
                                && now.latestInput === submitted[index].latestInput;
                    });
                    if (result.status === "admitted") {
                        conflicted = !fresh;
                        if (fresh) {
                            targets.forEach(function (target) {
                                if (active.some(function (selected) { return JSON.stringify(selected.path) === JSON.stringify(target.path); }))
                                    target.captured = store.info(target.path);
                            });
                            editor.generation = targets[0].captured.publicationGeneration;
                            editor.initialValue = display(store, targets[0]);
                        }
                    } else if (result.error?.code === "list-edit-conflict") {
                        conflicted = true;
                    } else {
                        // A refused command covers its own ingress, not a user edit.
                        // Keep the original displayed generation; the worker remains
                        // authoritative if any selected content changed meanwhile.
                        targets.forEach(function (target) {
                            if (!active.some(function (selected) { return JSON.stringify(selected.path) === JSON.stringify(target.path); }))
                                return;
                            var now = store.info(target.path);
                            if (now.contentRevision === target.captured.contentRevision
                                    && now.intentRevision === target.captured.intentRevision && settled(now))
                                target.captured = now;
                        });
                        editor.generation = targets[0].captured.publicationGeneration;
                    }
                    if (typeof callback === "function")
                        callback(Object.assign({}, result, {
                            refreshState: result.status === "admitted" ? (fresh ? "current" : "stale") : "not_refreshed",
                            generation: editor.generation
                        }));
                });
                submitted = active.map(function (target) { return store.info(target.path); });
            } catch (error) {
                busy = false;
                var code = String(error).match(/configqml: ([a-z-]+)/);
                return failed(code ? code[1] : "list-edit-input", callback);
            }
            return true;
        },
        detach: function () { closed = true; }
    };
    return editor;
}
