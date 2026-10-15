.pragma library

// Single owner of every conversion between portal byte paths, filesystem path
// strings and file:// URIs (M17). Pure JavaScript: no Qt, no IO. QML's JS has
// no TextEncoder/TextDecoder, so UTF-8 is implemented here.
//
// Results are plain objects so callers can branch on ok:
//   decodeBytePath(value)  -> {ok:true, path} | {ok:false, error}
//   encodeBytePath(path)   -> {ok:true, bytes} | {ok:false, error}
//   pathToUri(path)        -> {ok:true, uri}   | {ok:false, error}
//   uriToPath(uri)         -> {ok:true, path}  | {ok:false, error}
//
// Error strings are a fixed set: "unsupported input type", "invalid byte value",
// "embedded NUL", "invalid UTF-8", "invalid UTF-16", "not an absolute path",
// "not a file URI", "unsupported host", "query or fragment not allowed",
// "forbidden character", "invalid escape".

var NUL = "\u0000";

function fail(error) {
    return { "ok": false, "error": error };
}

// Reads the bytes of a D-Bus "ay" value. Real portal input arrives as an
// ArrayBuffer (no length); it must never go through String(value).
function inputBytes(value) {
    var view = null;
    if (Object.prototype.toString.call(value) === "[object ArrayBuffer]") {
        view = new Uint8Array(value);
    } else if (value !== null && typeof value === "object" && value.buffer !== undefined && typeof value.byteLength === "number") {
        view = new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
    } else if (value !== null && typeof value === "object" && typeof value.length === "number") {
        var list = [];
        for (var i = 0; i < value.length; i++) {
            var b = value[i];
            if (typeof b !== "number" || b % 1 !== 0 || b < 0 || b > 255)
                return fail("invalid byte value");
            list.push(b);
        }
        return { "ok": true, "bytes": list };
    } else {
        return fail("unsupported input type");
    }
    var bytes = [];
    for (var j = 0; j < view.length; j++)
        bytes.push(view[j]);
    return { "ok": true, "bytes": bytes };
}

// Strict UTF-8 decoder (RFC 3629): rejects overlong forms, surrogates, code
// points above U+10FFFF and truncated sequences. Returns null when invalid.
function decodeUtf8(bytes) {
    var out = "";
    var i = 0;
    var n = bytes.length;
    while (i < n) {
        var b0 = bytes[i];
        var cp = 0;
        var need = 0;
        if (b0 < 0x80) {
            cp = b0;
        } else if (b0 >= 0xC2 && b0 <= 0xDF) {
            cp = b0 & 0x1F;
            need = 1;
        } else if (b0 >= 0xE0 && b0 <= 0xEF) {
            cp = b0 & 0x0F;
            need = 2;
        } else if (b0 >= 0xF0 && b0 <= 0xF4) {
            cp = b0 & 0x07;
            need = 3;
        } else {
            return null;
        }
        // The first continuation byte has tighter bounds for E0, ED, F0 and F4.
        var lo = 0x80;
        var hi = 0xBF;
        if (b0 === 0xE0)
            lo = 0xA0;
        else if (b0 === 0xED)
            hi = 0x9F;
        else if (b0 === 0xF0)
            lo = 0x90;
        else if (b0 === 0xF4)
            hi = 0x8F;
        for (var k = 1; k <= need; k++) {
            if (i + k >= n)
                return null;
            var b = bytes[i + k];
            var min = k === 1 ? lo : 0x80;
            var max = k === 1 ? hi : 0xBF;
            if (b < min || b > max)
                return null;
            cp = (cp << 6) | (b & 0x3F);
        }
        if (cp < 0x10000) {
            out += String.fromCharCode(cp);
        } else {
            cp -= 0x10000;
            out += String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF));
        }
        i += need + 1;
    }
    return out;
}

// UTF-8 encoder for a JS string. Returns null for a lone surrogate.
function encodeUtf8(text) {
    var out = [];
    for (var i = 0; i < text.length; i++) {
        var c = text.charCodeAt(i);
        if (c >= 0xDC00 && c <= 0xDFFF)
            return null;
        if (c >= 0xD800 && c <= 0xDBFF) {
            var next = text.charCodeAt(i + 1);
            if (!(next >= 0xDC00 && next <= 0xDFFF))
                return null;
            c = 0x10000 + ((c - 0xD800) << 10) + (next - 0xDC00);
            i++;
        }
        if (c < 0x80) {
            out.push(c);
        } else if (c < 0x800) {
            out.push(0xC0 | (c >> 6), 0x80 | (c & 0x3F));
        } else if (c < 0x10000) {
            out.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F));
        } else {
            out.push(0xF0 | (c >> 18), 0x80 | ((c >> 12) & 0x3F), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F));
        }
    }
    return out;
}

// Byte path -> string. Exactly one trailing 0 byte is the terminator; any other
// 0 byte is an embedded NUL. A string input gets the same rule with U+0000.
function decodeBytePath(value) {
    if (typeof value === "string") {
        var text = value;
        if (text.length > 0 && text.charAt(text.length - 1) === NUL)
            text = text.slice(0, text.length - 1);
        if (text.indexOf(NUL) >= 0)
            return fail("embedded NUL");
        return { "ok": true, "path": text };
    }
    var got = inputBytes(value);
    if (!got.ok)
        return got;
    var bytes = got.bytes;
    if (bytes.length > 0 && bytes[bytes.length - 1] === 0)
        bytes = bytes.slice(0, bytes.length - 1);
    for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] === 0)
            return fail("embedded NUL");
    }
    var path = decodeUtf8(bytes);
    if (path === null)
        return fail("invalid UTF-8");
    return { "ok": true, "path": path };
}

// String -> byte path: UTF-8 plus one terminating 0, as an array of numbers.
function encodeBytePath(path) {
    if (typeof path !== "string")
        return fail("unsupported input type");
    if (path.indexOf(NUL) >= 0)
        return fail("embedded NUL");
    var bytes = encodeUtf8(path);
    if (bytes === null)
        return fail("invalid UTF-16");
    bytes.push(0);
    return { "ok": true, "bytes": bytes };
}

function isUriUnreserved(b) {
    return (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39)
            || b === 0x2D || b === 0x2E || b === 0x5F || b === 0x7E || b === 0x2F;
}

function hexByte(b) {
    return ("0" + b.toString(16)).slice(-2).toUpperCase();
}

// Absolute filesystem path -> file:// URI. Every byte outside RFC 3986
// unreserved characters and "/" is percent-encoded (uppercase hex, over UTF-8).
function pathToUri(path) {
    if (typeof path !== "string")
        return fail("unsupported input type");
    if (path.indexOf(NUL) >= 0)
        return fail("embedded NUL");
    if (path.charAt(0) !== "/")
        return fail("not an absolute path");
    var bytes = encodeUtf8(path);
    if (bytes === null)
        return fail("invalid UTF-16");
    var uri = "file://";
    for (var i = 0; i < bytes.length; i++) {
        var b = bytes[i];
        if (isUriUnreserved(b))
            uri += String.fromCharCode(b);
        else
            uri += "%" + hexByte(b);
    }
    return { "ok": true, "uri": uri };
}

// file:///path or file://localhost/path -> absolute path. Percent escapes are
// decoded as UTF-8. Raw "#" and "?" are rejected (a portal file URI carries no
// query or fragment), as are raw control characters and spaces.
function uriToPath(uri) {
    if (typeof uri !== "string")
        return fail("unsupported input type");
    if (uri.slice(0, 7) !== "file://")
        return fail("not a file URI");
    var rest = uri.slice(7);
    if (rest.slice(0, 9) === "localhost")
        rest = rest.slice(9);
    if (rest.charAt(0) !== "/")
        return fail("unsupported host");
    for (var i = 0; i < rest.length; i++) {
        var c = rest.charCodeAt(i);
        if (c === 0x23 || c === 0x3F)
            return fail("query or fragment not allowed");
        if (c <= 0x20 || c === 0x7F)
            return fail("forbidden character");
    }
    var parts = rest.split("%");
    var bytes = encodeUtf8(parts[0]);
    if (bytes === null)
        return fail("invalid UTF-16");
    for (var j = 1; j < parts.length; j++) {
        var hex = parts[j].slice(0, 2);
        if (!/^[0-9A-Fa-f]{2}$/.test(hex))
            return fail("invalid escape");
        bytes.push(parseInt(hex, 16));
        var tail = encodeUtf8(parts[j].slice(2));
        if (tail === null)
            return fail("invalid UTF-16");
        bytes = bytes.concat(tail);
    }
    for (var k = 0; k < bytes.length; k++) {
        if (bytes[k] === 0)
            return fail("embedded NUL");
    }
    var path = decodeUtf8(bytes);
    if (path === null)
        return fail("invalid UTF-8");
    return { "ok": true, "path": path };
}
