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
