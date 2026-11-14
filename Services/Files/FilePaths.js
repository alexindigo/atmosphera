.pragma library
.import "../../Helpers/PortalPaths.js" as PortalPaths

function names(text, multiple) {
    if (typeof text !== "string" || !text || text.includes("\u0000"))
        return {ok: false, error: "invalid-name"};
    if (!text.startsWith('"'))
        return {ok: true, values: [text]};
    var values = [], value = "", quoted = false, closed = false;
    for (var i = 0; i < text.length; i++) {
        var c = text[i];
        if (quoted) {
            if (c === "\\" && ['"', "\\"].includes(text[i + 1])) value += text[++i];
            else if (c === '"') { quoted = false; closed = true; }
            else value += c;
        } else if (c === '"' && !closed) quoted = true;
        else if (/\s/.test(c) && closed) {
            if (value) values.push(value);
            value = ""; closed = false;
        } else return {ok: false, error: "invalid-name"};
    }
    if (quoted || !closed || !value) return {ok: false, error: "invalid-name"};
    values.push(value);
    return values.length > 1 && !multiple ? {ok: false, error: "invalid-name"} : {ok: true, values: values};
}

function local(text, base, home) {
    if (!text || text.includes("\u0000")) return {ok: false, error: "invalid-name"};
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(text)) {
        var uri = PortalPaths.uriToPath(text);
        if (!uri.ok) return {ok: false, error: "local-path-only"};
        text = uri.path;
    }
    if (text === "~" || text.startsWith("~/")) text = home + text.slice(1);
    else if (text.startsWith("~")) return {ok: false, error: "local-path-only"};
    if (!text.startsWith("/")) text = base + "/" + text;
    var parts = [];
    for (var part of text.split("/")) {
        if (!part || part === ".") continue;
        if (part === "..") parts.pop();
        else parts.push(part);
    }
    return {ok: true, path: "/" + parts.join("/")};
}

function quote(values) {
    if (values.length <= 1 && (!values.length || !values[0].startsWith('"'))) return values[0] || "";
    return values.map(value => '"' + value.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"').join(" ");
}

function parent(path) { return path.slice(0, path.lastIndexOf("/")) || "/"; }
function leaf(path) { return path.slice(path.lastIndexOf("/") + 1); }

function breadcrumbs(path, home) {
    if (!path) return [];
    var inside = path === home || path.startsWith(home === "/" ? "/" : home + "/");
    var result = [{name: inside ? "Home" : "/", path: inside ? home : "/"}];
    var current = inside ? home : "";
    for (var part of (inside ? path.slice(home.length) : path).split("/")) {
        if (!part) continue;
        current = (current === "/" ? "" : current) + "/" + part;
        result.push({name: part, path: current});
    }
    return result;
}
