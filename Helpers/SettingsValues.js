.pragma library

// Selected editor/display values only, never the live Settings graph. Native
// value types (including QColor) expose their value members through this bridge.
function sequence(value) {
    // The same QML list<var>/list<string> boundary as RecordListEditor.copy.
    // JSON records cannot contain a callable slice member.
    return Array.isArray(value) || (Number.isSafeInteger(value.length) && value.length >= 0 && typeof value.slice === "function");
}

function equal(first, second) {
    if (first === second)
        return true;
    if (first === null || second === null || typeof first !== typeof second || typeof first !== "object")
        return false;
    var firstSequence = sequence(first);
    var secondSequence = sequence(second);
    if (firstSequence !== secondSequence)
        return false;
    if (firstSequence) {
        if (first.length !== second.length)
            return false;
        for (var index = 0; index < first.length; ++index) {
            if (!equal(first[index], second[index]))
                return false;
        }
        return true;
    }
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
