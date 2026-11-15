// Pure filename/type policy. Filesystem existence and request ownership stay in
// FileRequest; no view derives or silently appends a destination suffix.
function literalSuffix(pattern) {
    if (!pattern.startsWith("*.")) return "";
    var text = pattern.slice(2).replace(/\[([^\]]+)\]/g, function(all, letters) {
        var lower = letters.toLowerCase();
        return lower.length > 0 && Array.from(lower).every(ch => ch === lower[0]) ? lower[0] : all;
    });
    return /^[A-Za-z0-9_+-]+(?:\.[A-Za-z0-9_+-]+)*$/.test(text) ? text : "";
}

function suffixes(filter, mimeGlobs, aliases) {
    var result = [];
    if (!filter || !filter[1] || typeof filter[1].length !== "number") return result;
    for (var rule of filter[1]) {
        var patterns = rule[0] === 0 ? [rule[1]] : [];
        if (rule[0] === 1 && !/[?*]/.test(rule[1])) {
            var mime = aliases[rule[1]] || rule[1];
            patterns = mimeGlobs.filter(entry => entry.mime === mime).map(entry => entry.pattern);
        }
        for (var pattern of patterns) {
            var suffix = literalSuffix(pattern);
            if (suffix && !result.some(value => value.toLowerCase() === suffix.toLowerCase())) result.push(suffix);
        }
    }
    return result;
}

function matchingSuffix(name, allowed) {
    var lower = name.toLowerCase();
    return allowed.slice().sort((a, b) => b.length - a.length).find(suffix =>
        name.length > suffix.length + 1 && lower.endsWith("." + suffix.toLowerCase())) || "";
}

function append(name, allowed) {
    if (!name || !allowed.length) return name;
    if (name.endsWith(".")) return name.slice(0, -1);
    return matchingSuffix(name, allowed) ? name : name + "." + allowed[0];
}

function changeType(name, previous, next) {
    if (!name || !next.length || name.endsWith(".") || matchingSuffix(name, next)) return name;
    var dot = name.lastIndexOf(".");
    if (dot <= 0) return name; // Dotfiles and unspecified suffixes wait for Save.
    var old = matchingSuffix(name, previous);
    return old ? name.slice(0, -(old.length + 1)) + "." + next[0] : name;
}
