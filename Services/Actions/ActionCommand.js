.pragma library

// This is also the schema enforced by Scripts/dev/action_catalog.py. The shared
// fixture verdicts exercise both implementations; runtime never executes input.
var SAFE_WORD = /^[A-Za-z0-9_@%+=:,./-]+$/;
var ID = /^[a-z][a-z0-9-]*$/;
var ARG_NAME = /^[a-z][A-Za-z0-9]*$/;
var GROUPS = ["Panels", "Launcher", "Session", "Toggles", "Compositor"];
var COMPOSITORS = ["niri", "hyprland", "sway", "mango"];

function owns(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key);
}

function record(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function line(value) {
    // ECMAScript WhiteSpace + LineTerminator; the Python validator uses the
    // same explicit set rather than Python's broader/different strip().
    return typeof value === "string" && value.trim().length > 0 && !/[\r\n\x00]/.test(value);
}

function integer(value) {
    return typeof value === "number" && isFinite(value) && Math.abs(value) <= 9007199254740991 && Math.floor(value) === value;
}

function unknown(object, allowed) {
    return Object.keys(object).some(function(key) { return allowed.indexOf(key) < 0; });
}

function validValue(argument, value) {
    if (argument.type === "number")
        return integer(value) && (!owns(argument, "min") || value >= argument.min)
            && (!owns(argument, "max") || value <= argument.max);
    if (!line(value))
        return false;
    return argument.type === "text" || (argument.type === "choice"
        && argument.choices.some(function(choice) { return choice.value === value; }));
}

function validate(action, origin) {
    function fail(error) { return {valid: false, error: error}; }
    if (!record(action))
        return fail("action must be an object");
    var allowed = ["id", "label", "description", "icon", "command", "arguments"];
    if (origin === "core")
        allowed = allowed.concat(["group", "requiresPlugin", "compositor"]);
    if (unknown(action, allowed))
        return fail("unknown action key");
    if (typeof action.id !== "string" || !ID.test(action.id))
        return fail("invalid action id");
    if (!line(action.label) || !line(action.description) || !line(action.icon))
        return fail("label, description and icon must be non-empty single-line strings");
    if (typeof action.command !== "string")
        return fail("invalid command");
    var words = action.command.split(" ");
    if (!words.every(function(word) { return SAFE_WORD.test(word); }))
        return fail("command must contain safe words separated by single spaces");
    var ipc = words[0] === "atmosphera" && words[1] === "ipc";
    if ((origin !== "core" && !ipc) || (ipc && words.length !== 4))
        return fail("IPC command must be atmosphera ipc <target> <function>");
    if (origin === "core") {
        if (owns(action, "group") === owns(action, "requiresPlugin"))
            return fail("core action needs exactly one group or requiresPlugin");
        if (owns(action, "group") && GROUPS.indexOf(action.group) < 0)
            return fail("unknown core group");
        if (owns(action, "requiresPlugin") && (typeof action.requiresPlugin !== "string" || !ID.test(action.requiresPlugin)))
            return fail("invalid required plugin id");
        if (owns(action, "compositor") && COMPOSITORS.indexOf(action.compositor) < 0)
            return fail("unknown compositor");
    }
    if (owns(action, "arguments") && !Array.isArray(action.arguments))
        return fail("arguments must be a list");
    var names = [];
    var args = action.arguments || [];
    for (var i = 0; i < args.length; ++i) {
        var arg = args[i];
        if (!record(arg) || typeof arg.name !== "string" || !ARG_NAME.test(arg.name)
                || names.indexOf(arg.name) >= 0 || !line(arg.label))
            return fail("invalid or duplicate argument name or label");
        names.push(arg.name);
        var keys = ["name", "label", "type", "default"];
        if (arg.type === "choice") {
            keys.push("choices");
            if (!Array.isArray(arg.choices) || !arg.choices.length)
                return fail("choice needs choices");
            var values = [];
            for (var j = 0; j < arg.choices.length; ++j) {
                var choice = arg.choices[j];
                if (!record(choice) || unknown(choice, ["value", "label"]) || !line(choice.value)
                        || !line(choice.label) || values.indexOf(choice.value) >= 0)
                    return fail("invalid or duplicate choice");
                values.push(choice.value);
            }
        } else if (arg.type === "number") {
            keys = keys.concat(["min", "max", "unit"]);
            if ((owns(arg, "min") && !integer(arg.min)) || (owns(arg, "max") && !integer(arg.max))
                    || (owns(arg, "unit") && (typeof arg.unit !== "string" || /[\r\n\x00]/.test(arg.unit))))
                return fail("invalid number bounds or unit");
        } else if (arg.type !== "text") {
            return fail("unknown argument type");
        }
        if (unknown(arg, keys) || !owns(arg, "default") || !validValue(arg, arg.default))
            return fail("unknown argument key or invalid default");
    }
    return {valid: true, error: ""};
}

function available(action, context) {
    return (!action.compositor || action.compositor === context.compositor)
        && (!action.requiresPlugin || context.loadedPluginIds.indexOf(action.requiresPlugin) >= 0);
}

function quote(value) {
    var text = String(value);
    return SAFE_WORD.test(text) ? text : "'" + text.replace(/'/g, "'\\''") + "'";
}

// Missing values take their authored defaults; invalid edits produce no command.
function compose(action, values) {
    var output = action.command;
    var args = action.arguments || [];
    for (var i = 0; i < args.length; ++i) {
        var arg = args[i];
        var value = values && owns(values, arg.name) ? values[arg.name] : arg.default;
        if (!validValue(arg, value))
            return "";
        output += " " + quote(value);
    }
    return output;
}

// A deliberately small POSIX word reader, not a shell interpreter. Single-quoted
// segments and quote's escaped apostrophe may concatenate with safe bare words.
function splitWords(text) {
    var words = [];
    var word = "";
    var started = false;
    var quoted = false;
    for (var i = 0; i < text.length; ++i) {
        var c = text[i];
        if (quoted) {
            if (c === "'") quoted = false;
            else word += c;
        } else if (c === "'") {
            quoted = true;
            started = true;
        } else if (c === "\\" && text[i + 1] === "'") {
            word += "'";
            started = true;
            ++i;
        } else if (c === " ") {
            if (!started) return null;
            words.push(word);
            word = "";
            started = false;
        } else if (SAFE_WORD.test(c)) {
            word += c;
            started = true;
        } else {
            return null;
        }
    }
    if (quoted || !started) return null;
    words.push(word);
    return words;
}

function recognize(command, actions) {
    if (typeof command !== "string" || !command.length)
        return null;
    for (var i = 0; i < actions.length; ++i) {
        var action = actions[i];
        var args = action.arguments || [];
        if (!args.length) {
            if (command === action.command) return {action: action, values: {}};
            continue;
        }
        if (command.indexOf(action.command + " ") !== 0) continue;
        var words = splitWords(command.slice(action.command.length + 1));
        if (!words || words.length !== args.length) continue;
        var values = {};
        var valid = true;
        for (var j = 0; j < args.length; ++j) {
            var value = args[j].type === "number" ? Number(words[j]) : words[j];
            if (!validValue(args[j], value)) { valid = false; break; }
            values[args[j].name] = value;
        }
        if (valid && compose(action, values) === command)
            return {action: action, values: values};
    }
    return null;
}

function displayLabel(action, values) {
    var labels = (action.arguments || []).map(function(arg) {
        var value = values && owns(values, arg.name) ? values[arg.name] : arg.default;
        if (arg.type === "choice") {
            var choice = arg.choices.find(function(item) { return item.value === value; });
            return choice ? choice.label : String(value);
        }
        return String(value) + (arg.type === "number" && arg.unit ? " " + arg.unit : "");
    });
    return action.label + (labels.length ? ": " + labels.join(", ") : "");
}
