#!/usr/bin/env python3
"""Audit authored core record fields against the inert preparation schema."""
import importlib.util
import json
from pathlib import Path
import sys
from tree_sitter import Language, Parser
import tree_sitter_qmljs

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("record_schema", ROOT / "Scripts/dev/build-settings-schema.py")
schema = importlib.util.module_from_spec(spec)
spec.loader.exec_module(schema)
overlay = schema.load(Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "Configs/settings-schema-overlay.json")
widget = schema.resolve(overlay["definitions"]["widget"], overlay["definitions"])
parser = Parser(Language(tree_sitter_qmljs.language()))


def walk(node):
    yield node
    for child in node.named_children:
        yield from walk(child)


def literal_object(path, name):
    text = schema.uncomment(path.read_text())
    tail = text.split("property var " + name + ": (", 1)[1]
    return json.JSONDecoder().raw_decode(tail)[0]


metadata = {}
writers = {}
errors = []
for registry, folder in [("Bar", "Bar"), ("Desktop", "DesktopWidgets"), ("ControlCenter", "ControlCenter")]:
    path = ROOT / ("Services/UI/" + registry + "WidgetRegistry.qml")
    defaults = literal_object(path, "widgetMetadata")
    # Control-center has one core editor, selected explicitly by its dialog.
    links = {"CustomButton": "WidgetSettings/CustomButtonSettings.qml"} if registry == "ControlCenter" else literal_object(path, "widgetSettingsMap")
    for name, values in defaults.items():
        for key, value in values.items():
            metadata.setdefault(key, []).append(registry + ":" + name)
            if key not in widget["fields"]:
                errors.append("metadata undeclared: " + key)
            else:
                schema.validate(value, widget["fields"][key], (registry, name, key))
        page = ROOT / "Modules/Panels/Settings" / folder / links[name]
        source = page.read_bytes()
        tree = parser.parse(source)
        assert not tree.root_node.has_error, page
        for node in walk(tree.root_node):
            if node.type != "call_expression":
                continue
            function = node.child_by_field_name("function")
            text = source[function.start_byte:function.end_byte].decode()
            if text.split(".")[-1] not in ("save", "saveSettings", "settingsChanged"):
                continue
            args = node.child_by_field_name("arguments")
            for arg in args.named_children if args else []:
                if arg.type != "object":
                    continue  # Injected forwarding boundaries are reviewed separately.
                for pair in arg.named_children:
                    if pair.type != "pair":
                        continue
                    key = pair.child_by_field_name("key")
                    spelling = source[key.start_byte:key.end_byte].decode().strip('"\'')
                    writers.setdefault(spelling, []).append(str(page.relative_to(ROOT)) + ":" + str(pair.start_point.row + 1))
                    if spelling not in widget["fields"]:
                        errors.append("writer undeclared: " + spelling)

assert len(metadata) == 141, len(metadata)
for key in set(metadata) | set(writers) | {"x", "y", "scale", "widgetId", "instanceSettings"}:
    if key in widget["fields"]:
        assert widget["fields"][key].get("optional") is True, key
entries = {tuple(entry["path"]): schema.resolve({k: v for k, v in entry.items() if k != "path"}, overlay["definitions"]) for entry in overlay["entries"] if entry.get("type") in ("List", "Map", "Record") or "ref" in entry}
expected = {
    ("bar", "screenOverrides"): {"name", "enabled", "position", "density", "displayMode", "widgets"},
    ("sessionMenu", "powerOptions"): {"action", "enabled", "keybind", "countdownEnabled", "command"},
    ("wallpaper", "monitorDirectories"): {"name", "directory", "wallpaper"},
    ("wallpaper", "monitorPools"): {"name", "pools"},
    ("wallpaper", "favorites"): {"path", "appearance", "colorScheme", "darkMode", "useWallpaperColors", "generationMethod", "paletteColors"},
    ("inputMethod", "switches"): {"keys", "target", "mode", "label"},
    ("brightness", "backlightDeviceMappings"): {"output", "device"},
    ("templates", "activeTemplates"): {"id", "enabled"},
    ("calendar", "cards"): {"id", "enabled"},
    ("controlCenter", "cards"): {"id", "enabled"},
    ("desktopContextMenu", "items"): {"id"},
    ("desktopWidgets", "monitorWidgets"): {"name", "widgets"},
}
for path, fields in expected.items():
    missing = fields - set(entries[path]["element"]["fields"])
    errors.extend("record undeclared: " + ".".join(path) + "." + key for key in missing)
if not errors:
    assert set(entries[("wallpaper", "monitorPools")]["element"]["fields"]["pools"]["element"]["fields"]) == {"id", "active", "rotate"}
    assert widget["fields"]["pinned"]["type"] == "List" and widget["fields"]["pinned"]["element"]["type"] == "String"
    assert widget["fields"]["params"]["element"]["type"] == "String"
    assert set(widget["fields"]["environmentVars"]["element"]["fields"]) == {"key", "value"}
    assert entries[("desktopWidgets", "monitorWidgets")]["element"]["fields"]["widgets"]["optional"]
print(json.dumps(dict(metadataFields=len(metadata), authoredWidgetFields=len(writers), declaredWidgetFields=len(widget["fields"]), writers=writers, errors=sorted(set(errors))), indent=2))
assert not errors, "record declarations incomplete"
print("I4_RECORD_CONTRACTS: PASS")
