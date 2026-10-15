.pragma library

// Pure decision logic for the plugins.json v5 migration (M11). No file or
// process access: the caller reads plugins.json and the plugin settings
// directory, passes them in, and applies the returned plan (M12).
//
// Profiles created before 2026-08-30 have no "Built-in" source, built-in
// plugins keyed "builtin:<id>" (or hashed from the old ".../Plugins" URL), and
// retired built-ins such as "noctalia-icons-legacy". New profiles get what
// Registry.writeSeedJson writes: keys "<sha256(builtinSourceUrl)[:6]>:<id>".

var BUILTIN_TAIL = "/builtin/plugins";
var OLD_BUILTIN_TAIL = "/Plugins";
var WALLPAPERS_URL = "https://github.com/atmosphera/atmosphera-wallpapers";

function has(obj, key) {
    return Object.prototype.hasOwnProperty.call(obj, key);
}

function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

function endsWith(text, tail) {
    return text.length >= tail.length && text.slice(text.length - tail.length) === tail;
}

function bareId(key) {
    var i = key.indexOf(":");
    return i < 0 ? key : key.slice(i + 1);
}

function isBuiltinSourced(key, state) {
    if (key.indexOf("builtin:") === 0)
        return true;
    var url = state.sourceUrl;
    return typeof url === "string" && url.indexOf("file://") === 0
            && (endsWith(url, BUILTIN_TAIL) || endsWith(url, OLD_BUILTIN_TAIL));
}

function hasUrl(sources, url) {
    for (var i = 0; i < sources.length; i++) {
        if (sources[i] && sources[i].url === url)
            return true;
    }
    return false;
}

// input: { states, sources, shippedIds, builtinSourceUrl, currentHash, pluginSettingsFiles }
// Returns: { states, sources, rekeys, removals, dropped, unsourced, settingsFileMoves }
function planV5(input) {
    var shipped = input.shippedIds || [];
    var files = input.pluginSettingsFiles || [];
    var builtinUrl = input.builtinSourceUrl;
    var currentHash = input.currentHash;
    var inStates = input.states || {};
    var keys = Object.keys(inStates);

    var rekeys = [];
    var removals = [];
    var dropped = [];
    var unsourced = [];
    var settingsFileMoves = [];
    var out = {};
    // Every key that exists in the result so far (input keys plus rekey targets).
    var present = {};
    for (var p = 0; p < keys.length; p++)
        present[keys[p]] = true;

    for (var i = 0; i < keys.length; i++) {
        var key = keys[i];
        var state = inStates[key];

        // Rule 3: unsourced states are never touched.
        if (state === null || typeof state !== "object" || state.sourceUrl === null || state.sourceUrl === undefined) {
            if (state !== null && typeof state === "object")
                unsourced.push(key);
            out[key] = clone(state);
            continue;
        }

        // Rule 4: registry plugins are never touched.
        if (!isBuiltinSourced(key, state)) {
            out[key] = clone(state);
            continue;
        }

        var id = bareId(key);

        // Rule 2: built-in-sourced but no longer shipped.
        if (shipped.indexOf(id) < 0) {
            removals.push(key);
            continue;
        }

        var newKey = currentHash + ":" + id;
        // Already in the current form.
        if (newKey === key) {
            out[key] = clone(state);
            continue;
        }

        // Rule 1, duplicate: the current key already exists, keep it.
        if (has(present, newKey)) {
            dropped.push(key);
            continue;
        }

        // Rule 1: move the state to the current key.
        present[newKey] = true;
        var moved = clone(state);
        moved.sourceUrl = builtinUrl;
        out[newKey] = moved;
        rekeys.push({ from: key, to: newKey, id: id });

        // Settings file and its user config override, each skipped when its
        // own target already exists.
        var suffixes = ["", ".config"];
        for (var s = 0; s < suffixes.length; s++) {
            var suffix = suffixes[s];
            if (files.indexOf(key + suffix) >= 0 && files.indexOf(newKey + suffix) < 0)
                settingsFileMoves.push({ from: key + suffix + ".json", to: newKey + suffix + ".json" });
        }
    }

    // Rule 5: sources. Existing sources are never changed; no url is duplicated.
    var sources = clone(input.sources || []);
    if (!hasUrl(sources, builtinUrl))
        sources.unshift({ name: "Built-in", url: builtinUrl, enabled: true });
    if (!hasUrl(sources, WALLPAPERS_URL))
        sources.push({ name: "Atmosphera Wallpapers", url: WALLPAPERS_URL, enabled: false });

    return {
        states: out,
        sources: sources,
        rekeys: rekeys,
        removals: removals,
        dropped: dropped,
        unsourced: unsourced,
        settingsFileMoves: settingsFileMoves
    };
}

// Old key -> current key for every plugin key the migration rekeyed or dropped.
// Rekeys map to their target; a dropped key maps to the current key that
// already exists. Removed keys are not in the map: their references stay.
function keyMapFor(plan, currentHash) {
    var map = {};
    for (var i = 0; i < plan.rekeys.length; i++)
        map[plan.rekeys[i].from] = plan.rekeys[i].to;
    for (var j = 0; j < plan.dropped.length; j++)
        map[plan.dropped[j]] = currentHash + ":" + bareId(plan.dropped[j]);
    return map;
}

// Rewrites the id of one placement entry ("plugin:<key>") when <key> is in the
// map. Returns the new entry, or null when the entry is not affected. Every
// other property of the entry (instanceSettings, position, ...) is kept.
function rewriteEntry(entry, keyMap) {
    if (!entry || typeof entry !== "object" || typeof entry.id !== "string")
        return null;
    if (entry.id.indexOf("plugin:") !== 0)
        return null;
    var key = entry.id.slice(7);
    if (!has(keyMap, key))
        return null;
    return Object.assign({}, entry, { "id": "plugin:" + keyMap[key] });
}

// Copies an array-like value into a plain array. Settings.data's list<var>
// properties are not true JS arrays (Array.isArray is false), so they are read
// by length and index. Returns null for anything that is not array-like.
function toArray(value) {
    if (value === null || typeof value !== "object" || typeof value.length !== "number")
        return null;
    return Array.prototype.slice.call(value);
}

// Rewrites a list of placement entries. Returns { list, changed }. The result
// is a plain array (a copy when the input was array-like); a value that is not
// array-like is returned as it is.
function rewriteList(list, keyMap) {
    var items = toArray(list);
    if (items === null)
        return { list: list, changed: false };
    var changed = false;
    var out = [];
    for (var i = 0; i < items.length; i++) {
        var next = rewriteEntry(items[i], keyMap);
        if (next) {
            out.push(next);
            changed = true;
        } else {
            out.push(items[i]);
        }
    }
    return { list: out, changed: changed };
}

// Rewrites every list-valued section of a { left, center, right } object.
function rewriteSections(sections, keyMap) {
    if (!sections || typeof sections !== "object")
        return { value: sections, changed: false };
    var changed = false;
    var out = {};
    for (var name in sections) {
        var result = rewriteList(sections[name], keyMap);
        out[name] = result.list;
        if (result.changed)
            changed = true;
    }
    return { value: changed ? out : sections, changed: changed };
}

// refs: the placement-bearing settings, read from Settings.data:
//   { barWidgets: {left,center,right}, screenOverrides: [{name, widgets?: {...}}],
//     controlCenterShortcuts: {left,right}, monitorWidgets: [{name, widgets: [...]}],
//     lockScreenPlugin: "<key>" }
// Returns the same shape with rewritten values, plus touched: one boolean per
// group. The caller assigns only touched groups.
function rewriteSettingsReferences(refs, keyMap) {
    var bar = rewriteSections(refs.barWidgets, keyMap);
    var shortcuts = rewriteSections(refs.controlCenterShortcuts, keyMap);

    var overrides = toArray(refs.screenOverrides) || [];
    var overridesChanged = false;
    var overridesOut = [];
    for (var i = 0; i < overrides.length; i++) {
        var override = overrides[i];
        var section = override && typeof override === "object" ? rewriteSections(override.widgets, keyMap) : { changed: false };
        if (section.changed) {
            overridesChanged = true;
            overridesOut.push(Object.assign({}, override, { "widgets": section.value }));
        } else {
            overridesOut.push(override);
        }
    }

    var monitors = toArray(refs.monitorWidgets) || [];
    var monitorsChanged = false;
    var monitorsOut = [];
    for (var m = 0; m < monitors.length; m++) {
        var monitor = monitors[m];
        var widgets = monitor && typeof monitor === "object" ? rewriteList(monitor.widgets, keyMap) : { changed: false };
        if (widgets.changed) {
            monitorsChanged = true;
            monitorsOut.push(Object.assign({}, monitor, { "widgets": widgets.list }));
        } else {
            monitorsOut.push(monitor);
        }
    }

    var lock = refs.lockScreenPlugin;
    var lockChanged = typeof lock === "string" && has(keyMap, lock);

    return {
        barWidgets: bar.value,
        screenOverrides: overridesChanged ? overridesOut : overrides,
        controlCenterShortcuts: shortcuts.value,
        monitorWidgets: monitorsChanged ? monitorsOut : monitors,
        lockScreenPlugin: lockChanged ? keyMap[lock] : lock,
        touched: {
            barWidgets: bar.changed,
            screenOverrides: overridesChanged,
            controlCenterShortcuts: shortcuts.changed,
            monitorWidgets: monitorsChanged,
            lockScreenPlugin: lockChanged
        }
    };
}
