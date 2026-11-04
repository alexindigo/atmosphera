.pragma library

// Selected editor/display values only, never the live Settings graph. Native
// value types (including QColor) expose their value members through this bridge.
function equal(first, second) {
    if (first === second)
        return true;
    if (first === null || second === null || typeof first !== typeof second || typeof first !== "object")
        return false;
    if (Array.isArray(first) !== Array.isArray(second))
        return false;
    var keys = Object.keys(first).sort();
    var other = Object.keys(second).sort();
    if (keys.length !== other.length)
        return false;
    for (var i = 0; i < keys.length; ++i) {
        if (keys[i] !== other[i] || !equal(first[keys[i]], second[keys[i]]))
            return false;
    }
    return true;
}
