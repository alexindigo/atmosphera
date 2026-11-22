.pragma library

// Owned display projection, never a synchronized store or publication input.
// Preserve absent/false/zero/empty values and isolate compound aliases.
function freeze(value) {
    if (value === null || typeof value !== "object") return value;
    var result = Array.isArray(value) ? [] : Object.create(null);
    for (var key of Object.keys(value))
        Object.defineProperty(result, key, {value: freeze(value[key]), enumerable: true});
    return Object.freeze(result);
}

function values(source, keys, copyValue) {
    var result = Object.create(null);
    for (var key of keys) {
        var value = source ? source[key] : undefined;
        if (value !== undefined) result[key] = copyValue(value);
    }
    return freeze(result);
}

function context(lifetime, readSettings, current) {
    var result = Object.create(null);
    var retiredValues = freeze(Object.create(null));
    // The JS token outlives its QObject. Never invoke a retained owner callback
    // after destruction, even to ask that destroyed owner whether it is current.
    Object.defineProperty(result, "settingsView", {get: function () {
        return lifetime.alive ? readSettings() : retiredValues;
    }, enumerable: true});
    // Identity is the captured API, not configuration equality or a row index.
    Object.defineProperty(result, "current", {value: function () {
        return lifetime.alive && current() === true;
    }});
    return Object.freeze(result);
}
