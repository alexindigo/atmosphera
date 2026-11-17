"""Action schema and source-backed IPC checks, shared by lint and regression.

Read-only tooling; run only inside the assigned guest or CI. Runtime parity is
covered by fixtures/action-schema-cases.json and Services/Actions/ActionCommand.js.
"""
import importlib.util
import json
import math
from pathlib import Path
import re
from urllib.parse import urlsplit

ID = re.compile(r"[a-z][a-z0-9-]*\Z")
ARG_NAME = re.compile(r"[a-z][A-Za-z0-9]*\Z")
SAFE_WORD = re.compile(r"[A-Za-z0-9_@%+=:,./-]+\Z")
GROUPS = {"Panels", "Launcher", "Session", "Toggles", "Compositor"}
COMPOSITORS = {"niri", "hyprland", "sway", "mango"}


def line(value):
    return isinstance(value, str) and bool(value.strip()) and not any(c in value for c in "\r\n\0")


def integer(value):
    return type(value) in (int, float) and math.isfinite(value) and int(value) == value


def valid_value(argument, value):
    if argument["type"] == "number":
        return (integer(value) and ("min" not in argument or value >= argument["min"])
                and ("max" not in argument or value <= argument["max"]))
    return line(value) and (argument["type"] == "text" or
                           any(choice["value"] == value for choice in argument["choices"]))


def validate_action(action, origin):
    """Return {valid, error}; origin is 'core' or a plugin source key."""
    def fail(error):
        return {"valid": False, "error": error}
    if not isinstance(action, dict):
        return fail("action must be an object")
    allowed = {"id", "label", "description", "icon", "command", "arguments"}
    if origin == "core":
        allowed |= {"group", "requiresPlugin", "compositor"}
    if action.keys() - allowed:
        return fail("unknown action key")
    if not isinstance(action.get("id"), str) or not ID.fullmatch(action["id"]):
        return fail("invalid action id")
    if not all(line(action.get(key)) for key in ("label", "description", "icon")):
        return fail("label, description and icon must be non-empty single-line strings")
    if not isinstance(action.get("command"), str):
        return fail("invalid command")
    words = action["command"].split(" ")
    if not all(SAFE_WORD.fullmatch(word) for word in words):
        return fail("command must contain safe words separated by single spaces")
    ipc = words[:2] == ["atmosphera", "ipc"]
    if (origin != "core" and not ipc) or (ipc and len(words) != 4):
        return fail("IPC command must be atmosphera ipc <target> <function>")
    if origin == "core":
        if ("group" in action) == ("requiresPlugin" in action):
            return fail("core action needs exactly one group or requiresPlugin")
        if "group" in action and (not isinstance(action["group"], str) or action["group"] not in GROUPS):
            return fail("unknown core group")
        if "requiresPlugin" in action and (not isinstance(action["requiresPlugin"], str)
                                           or not ID.fullmatch(action["requiresPlugin"])):
            return fail("invalid required plugin id")
        if "compositor" in action and (not isinstance(action["compositor"], str) or action["compositor"] not in COMPOSITORS):
            return fail("unknown compositor")
    if "arguments" in action and not isinstance(action["arguments"], list):
        return fail("arguments must be a list")
    names = set()
    for arg in action.get("arguments", []):
        if (not isinstance(arg, dict) or not isinstance(arg.get("name"), str)
                or not ARG_NAME.fullmatch(arg["name"]) or arg["name"] in names or not line(arg.get("label"))):
            return fail("invalid or duplicate argument name or label")
        names.add(arg["name"])
        keys = {"name", "label", "type", "default"}
        if arg.get("type") == "choice":
            keys.add("choices")
            if not isinstance(arg.get("choices"), list) or not arg["choices"]:
                return fail("choice needs choices")
            values = set()
            for choice in arg["choices"]:
                if (not isinstance(choice, dict) or choice.keys() - {"value", "label"}
                        or not line(choice.get("value")) or not line(choice.get("label"))
                        or choice["value"] in values):
                    return fail("invalid or duplicate choice")
                values.add(choice["value"])
        elif arg.get("type") == "number":
            keys |= {"min", "max", "unit"}
            if (any(key in arg and not integer(arg[key]) for key in ("min", "max"))
                    or ("unit" in arg and (not isinstance(arg["unit"], str)
                                           or any(c in arg["unit"] for c in "\r\n\0")))):
                return fail("invalid number bounds or unit")
        elif arg.get("type") != "text":
            return fail("unknown argument type")
        if arg.keys() - keys or "default" not in arg or not valid_value(arg, arg["default"]):
            return fail("unknown argument key or invalid default")
    return {"valid": True, "error": ""}


def quote(value):
    text = str(int(value)) if integer(value) else str(value)
    return text if SAFE_WORD.fullmatch(text) else "'" + text.replace("'", "'\\''") + "'"


def compose(action):
    return action["command"] + "".join(" " + quote(arg["default"]) for arg in action.get("arguments", []))


def load_lexer(shell):
    spec = importlib.util.spec_from_file_location("action_qml_lexer", shell / "Scripts/dev/qml-identifiers.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def ipc_handlers(path, lexer):
    """{target: {function: [parameter types]}} from actual IpcHandler objects.

    Braces and declaration offsets come from code only. Literal targets are
    read from the original source; comments, strings and nested JS functions
    cannot manufacture handlers or depth-1 functions.
    """
    source = Path(path).read_text()
    tokens, spans = lexer.lex(source)
    code, comments = list(source), list(source)
    for kind, start, end in spans:
        for i in range(start, end):
            if source[i] != "\n":
                code[i] = " "
                if kind == "comment":
                    comments[i] = " "
    code, comments = "".join(code), "".join(comments)
    depths, ends, stack = [], {}, []
    for i, char in enumerate(code):
        depths.append(len(stack))
        if char == "{":
            stack.append(i)
        elif char == "}" and stack:
            ends[stack.pop()] = i
    handlers = {}
    for token in tokens:
        if token.text != "IpcHandler":
            continue
        opening = re.match(r"\s*\{", code[token.end:])
        if not opening:
            continue
        start = token.end + opening.end() - 1
        end = ends.get(start)
        if end is None:
            continue
        depth = depths[start] + 1
        targets = []
        for m in re.finditer(r"\btarget\s*:\s*(['\"])([^'\"\r\n]+)\1", comments[start:end]):
            offset = start + m.start()
            if depths[offset] == depth and code[offset:offset + 6] == "target":
                targets.append(m.group(2))
        if len(targets) != 1:
            continue
        functions = handlers.setdefault(targets[0], {})
        for m in re.finditer(r"\bfunction\s+([A-Za-z_$][\w$]*)\s*\(([^()]*)\)\s*(?::\s*[\w.]+)?\s*\{", code[start:end]):
            if depths[start + m.start()] != depth:
                continue
            params = []
            for param in m.group(2).split(",") if m.group(2).strip() else []:
                p = re.fullmatch(r"\s*[A-Za-z_$][\w$]*\s*(?::\s*([\w.]+))?\s*", param)
                params.append(p.group(1) or "" if p else "unsupported")
            functions[m.group(1)] = params
    return handlers


def action_checks(actions, origin, icons, handlers, core_commands=()):
    errors, ids, commands = [], set(), set()
    if not isinstance(actions, list):
        return ["actions must be a list"]
    for index, action in enumerate(actions):
        prefix = f"actions[{index}]"
        verdict = validate_action(action, origin)
        if not verdict["valid"]:
            errors.append(f"{prefix}: {verdict['error']}")
            continue
        if action["id"] in ids:
            errors.append(f"{prefix}: duplicate action id {action['id']}")
        ids.add(action["id"])
        if action["icon"] not in icons:
            errors.append(f"{prefix}: missing icon {action['icon']}")
        command = compose(action)
        if command in commands or command in core_commands:
            errors.append(f"{prefix}: duplicate composed command {command}")
        commands.add(command)
        words = action["command"].split(" ")
        if words[:2] != ["atmosphera", "ipc"]:
            continue
        target, function = words[2:]
        if target not in handlers:
            errors.append(f"{prefix}: unknown IPC target {target}")
            continue
        params = handlers[target].get(function)
        if params is None:
            errors.append(f"{prefix}: unknown IPC function {target}.{function}")
            continue
        args = action.get("arguments", [])
        if len(params) != len(args):
            errors.append(f"{prefix}: IPC arity mismatch for {target}.{function}")
        elif any(t not in ("", "string", "int") or (t == "int" and arg["type"] != "number")
                 for t, arg in zip(params, args)):
            errors.append(f"{prefix}: unsupported IPC parameter type for {target}.{function}")
    return errors


def read_core(shell):
    data = json.loads((shell / "Assets/Actions/core.json").read_text())
    if not isinstance(data, dict) or set(data) != {"version", "actions"} or type(data["version"]) is not int or data["version"] != 1:
        raise ValueError("core catalog must contain version 1 and actions")
    return data["actions"]


def read_icons(shell):
    return json.loads((shell / "builtin/plugins/atmosphera-icons/icons.json").read_text())["icons"]


def check_core(shell):
    shell = Path(shell)
    lexer, handlers = load_lexer(shell), {}
    for path in sorted((shell / "Services").rglob("*.qml")):
        if "Plugins" not in path.relative_to(shell / "Services").parts:
            for target, functions in ipc_handlers(path, lexer).items():
                handlers.setdefault(target, {}).update(functions)
    return action_checks(read_core(shell), "core", read_icons(shell), handlers)


def check_plugin(manifest, directory, shell):
    if "actions" not in manifest:
        return []
    directory, shell = Path(directory), Path(shell)
    main = manifest.get("entryPoints", {}).get("main")
    if not isinstance(main, str):
        return ["declared actions require entryPoints.main"]
    url = urlsplit(main)
    if url.scheme or url.netloc or Path(url.path).is_absolute() or ".." in Path(url.path).parts:
        return ["declared actions require a safe main entry point"]
    path = directory / url.path
    if not path.is_file():
        return ["declared actions require an existing main entry point"]
    core = [compose(a) for a in read_core(shell) if validate_action(a, "core")["valid"]]
    return action_checks(manifest["actions"], "plugin", read_icons(shell),
                         ipc_handlers(path, load_lexer(shell)), core)
