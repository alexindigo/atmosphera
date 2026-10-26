.pragma library

function identity(item) {
    if (!item)
        return null;
    for (var field of ["windowId", "clipboardId", "appId", "usageKey", "id", "name"]) {
        if (item[field] !== undefined && item[field] !== null && item[field] !== "")
            return {field: field, value: item[field], provider: item.provider};
    }
    return null;
}

function afterRefresh(items, previous, previousIndex, reset) {
    if (items.length === 0)
        return -1;
    if (reset)
        return 0;
    var key = identity(previous);
    if (key) {
        for (var i = 0; i < items.length; i++) {
            var candidate = identity(items[i]);
            if (candidate && candidate.field === key.field && candidate.value === key.value && candidate.provider === key.provider)
                return i;
        }
    }
    return Math.max(0, Math.min(previousIndex, items.length - 1));
}

function sameIdentity(a, b) {
    var x = identity(a);
    var y = identity(b);
    if (!x || !y)
        return x === y && a === b;
    return x.field === y.field && x.value === y.value && x.provider === y.provider;
}

// View rows keyed by the same identity that preserves the selection. Rows that
// share an identity, or have none, are told apart by their order of occurrence,
// so every key is unique. Keys never depend on rank or score: a refresh keeps
// the delegates of surviving rows and only adds, moves and removes the others.
function keyedRows(items, providers) {
    var seen = {};
    var rows = [];
    for (var i = 0; i < items.length; i++) {
        var item = items[i];
        var id = identity(item);
        var provider = item && item.provider ? providers.indexOf(item.provider) : -1;
        var base = provider + "\u001f" + (id ? id.field + "\u001f" + String(id.value) : "");
        var occurrence = seen[base] || 0;
        seen[base] = occurrence + 1;
        rows.push({key: base + "\u001f" + occurrence, row: item});
    }
    return rows;
}
