.pragma library

// Names declared on the root object of a QML file (shared-loader design,
// section 3.2). Comments, string/template literals and regex literals are
// blanked before braces are counted, so only declarations at brace depth 1
// inside the root object are considered. Nested objects, function bodies and
// braced property values never contribute.
//
// Known limit: a regex literal is recognised from the preceding token only
// (punctuation or a keyword such as `return`). A miss can only hide names, and
// the loader then falls back to the late-assignment path.

var KEYWORDS_BEFORE_REGEX = ["return", "typeof", "instanceof", "in", "of", "new", "delete", "void", "throw", "case", "do", "else", "yield", "await"];
var PUNCTUATORS_BEFORE_REGEX = "(,=:[!&|?{};+-*%<>~^";

var ALIAS_RE = /^(?:(?:default|required|readonly)\s+)*property\s+alias\s+([A-Za-z_]\w*)(?!\w)/;
var TYPED_RE = /^(?:(?:default|required|readonly)\s+)*property\s+[A-Za-z_][\w.]*(?:\s*<.*?>)?\s+([A-Za-z_]\w*)(?!\w)/;
var REQUIRED_RE = /^required\s+([A-Za-z_]\w*)$/;

function isWordChar(ch) {
    return /^\w$/.test(ch);
}

// Same-length copy of `text` in which comment, string, template and regex
// literal contents are replaced by spaces. Newlines are kept so line structure
// survives.
function maskLiterals(text) {
    var out = [];
    var i = 0;
    var n = text.length;
    var prev = "";       // last non-space character outside literals
    var word = "";       // identifier being read right now
    var lastWord = "";   // last completed identifier

    function blank(ch) {
        out.push(ch === "\n" ? "\n" : " ");
    }

    function regexAllowed() {
        if (prev === "" || PUNCTUATORS_BEFORE_REGEX.indexOf(prev) >= 0)
            return true;
        if (!isWordChar(prev))
            return false;
        var token = word !== "" ? word : lastWord;
        return KEYWORDS_BEFORE_REGEX.indexOf(token) >= 0;
    }

    while (i < n) {
        var c = text.charAt(i);
        var d = text.charAt(i + 1);

        if (c === "/" && d === "/") {
            while (i < n && text.charAt(i) !== "\n") {
                blank(text.charAt(i));
                i++;
            }
            continue;
        }

        if (c === "/" && d === "*") {
            blank(c);
            blank(d);
            i += 2;
            while (i < n && !(text.charAt(i) === "*" && text.charAt(i + 1) === "/")) {
                blank(text.charAt(i));
                i++;
            }
            if (i < n) {
                blank("*");
                blank("/");
                i += 2;
            }
            continue;
        }

        if (c === "\"" || c === "'" || c === "`") {
            blank(c);
            i++;
            while (i < n && text.charAt(i) !== c) {
                var q = text.charAt(i);
                if (q === "\n" && c !== "`")
                    break;
                if (q === "\\" && i + 1 < n) {
                    blank(q);
                    blank(text.charAt(i + 1));
                    i += 2;
                    continue;
                }
                blank(q);
                i++;
            }
            if (i < n && text.charAt(i) === c) {
                blank(c);
                i++;
            }
            prev = ")";     // a literal is a value
            word = "";
            lastWord = "";
            continue;
        }

        if (c === "/" && regexAllowed()) {
            blank(c);
            i++;
            var inClass = false;
            while (i < n && text.charAt(i) !== "\n") {
                var r = text.charAt(i);
                if (r === "\\" && i + 1 < n && text.charAt(i + 1) !== "\n") {
                    blank(r);
                    blank(text.charAt(i + 1));
                    i += 2;
                    continue;
                }
                if (r === "[")
                    inClass = true;
                else if (r === "]")
                    inClass = false;
                else if (r === "/" && !inClass) {
                    blank(r);
                    i++;
                    break;
                }
                blank(r);
                i++;
            }
            prev = ")";
            word = "";
            lastWord = "";
            continue;
        }

        out.push(c);
        if (isWordChar(c)) {
            word += c;
        } else {
            if (word !== "")
                lastWord = word;
            word = "";
        }
        if (!/\s/.test(c))
            prev = c;
        i++;
    }
    return out.join("");
}

// Text of the root object's own body: everything at brace depth 1 (inside the
// first top-level brace pair), with nested braces and their contents blanked.
function rootBodyFlat(masked) {
    var start = masked.indexOf("{");
    if (start < 0)
        return "";
    var flat = [];
    var depth = 0;
    for (var i = start + 1; i < masked.length; i++) {
        var c = masked.charAt(i);
        if (c === "}" && depth === 0)
            break;
        if (c === "{") {
            depth++;
            flat.push(" ");
        } else if (c === "}") {
            depth--;
            flat.push(" ");
        } else if (depth > 0) {
            flat.push(c === "\n" ? "\n" : " ");
        } else {
            flat.push(c);
        }
    }
    return flat.join("");
}

// Sorted unique names declared on the root object of `text`.
function rootPropertyNames(text) {
    var names = [];
    var statements = rootBodyFlat(maskLiterals(String(text))).split(/[\n;]/);
    for (var i = 0; i < statements.length; i++) {
        var statement = statements[i].trim();
        if (statement === "" || /^(import|pragma)\b/.test(statement))
            continue;
        var match = ALIAS_RE.exec(statement) || TYPED_RE.exec(statement) || REQUIRED_RE.exec(statement);
        if (match && names.indexOf(match[1]) < 0)
            names.push(match[1]);
    }
    return names.sort();
}
