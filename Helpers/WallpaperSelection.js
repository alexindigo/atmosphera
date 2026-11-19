.pragma library

// Shared read-only interpretation of legacy and split wallpaper cache entries.
function effective(entry, darkMode) {
    if (!entry)
        return "";
    if (typeof entry === "string")
        return entry;
    return darkMode ? entry.dark || entry.light || "" : entry.light || entry.dark || "";
}

function select(wallpapers, screens, name, darkMode, fallback) {
    var own = effective(wallpapers[name], darkMode);
    if (own)
        return own;
    for (var i = 0; i < screens.length; ++i) {
        if (screens[i].name !== name && wallpapers[screens[i].name])
            return effective(wallpapers[screens[i].name], darkMode) || fallback || "";
    }
    return fallback || "";
}
