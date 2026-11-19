.pragma library

// copyValue leaves only native exact-number atoms frozen. Ordinary records,
// including authored {decimal: ...} data, become mutable detached dictionaries.
// Emit those atoms as numeric JSON tokens for ConfigQml's lossless file reader.
function encode(value) {
    if (typeof value === "number" && Object.is(value, -0))
        return "-0";
    if (value === null || typeof value !== "object")
        return JSON.stringify(value);
    if (Object.isFrozen(value) && typeof value.decimal === "string")
        return value.decimal;
    if (Array.isArray(value))
        return "[" + value.map(encode).join(",") + "]";
    return "{" + Object.keys(value).map(function (key) {
        return JSON.stringify(key) + ":" + encode(value[key]);
    }).join(",") + "}";
}

function capture(data, store) {
    var result = Object.create(null);
    result.settingsVersion = data.settingsVersion;
    for (var path of store.inputPaths) {
        var value = data;
        for (var part of path)
            value = value[part];
        if (value === undefined)
            continue;
        var target = result;
        for (var i = 0; i < path.length - 1; ++i) {
            if (!Object.prototype.hasOwnProperty.call(target, path[i]))
                target[path[i]] = Object.create(null);
            target = target[path[i]];
        }
        target[path[path.length - 1]] = store.copyValue(value);
    }
    return encode(result);
}
