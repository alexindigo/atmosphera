#!/usr/bin/env python3
"""Read-only Atmosphera plugin compatibility checks. Run in a VM or CI.

Uses the target shell's string/comment/template/regex-aware QML lexer. This is
a targeted compatibility gate, not a substitute for qmllint or runtime tests.
"""
import argparse
import importlib.util
import json
import re
import subprocess
from pathlib import Path
from urllib.parse import urlsplit

VERSION = re.compile(r"^\d+\.\d+\.\d+$")
SHELL_ROOT = Path(__file__).resolve().parents[2]
RETIRED = {
    "NIcon": "AtmoIcon", "NIconButton": "AtmoIconButton",
    "NIconButtonHot": "AtmoIconButtonHot", "NIconPicker": "AtmoIconPicker",
    "NAppIcon": "AtmoAppIcon", "NWallpaperBackground": "AtmoWallpaperBackground",
    "NFilePicker": "AtmoFilePicker", "NWidgetAppearance": "AtmoWidgetAppearance",
}


def load_lexer(shell):
    path = shell / "Scripts/dev/qml-identifiers.py"
    spec = importlib.util.spec_from_file_location("qml_identifiers", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def code_only(source, lexer):
    _, spans = lexer.lex(source)
    chars = list(source)
    for _, start, end in spans:
        for index in range(start, end):
            if chars[index] != "\n":
                chars[index] = " "
    return "".join(chars)


def root_members(path, lexer):
    """Only declarations on the root object, never nested implementation objects."""
    source = code_only(path.read_text(), lexer)
    depths = []
    depth = 0
    for char in source:
        depths.append(depth)
        depth += (char == "{") - (char == "}")
    pattern = re.compile(
        r"\b(?:property\s+(?:list\s*<[^>]+>|[\w.]+)\s+|"
        r"function\s+|signal\s+)([A-Za-z_$][\w$]*)")
    return {m.group(1) for m in pattern.finditer(source) if depths[m.start()] == 1}


def version(value):
    if not isinstance(value, str) or not VERSION.fullmatch(value):
        return None
    return tuple(map(int, value.split(".")))


def lint_source(path, shell, lexer, api, foreign):
    source = path.read_text()
    masked = code_only(source, lexer)
    tokens, spans = lexer.lex(source)
    errors = []

    def error(offset, message):
        errors.append(f"{path}:{lexer.line_of(source, offset)}: {message}")

    # Keep strings for import declarations, blank comments so commented imports
    # cannot accidentally grant access to a service or trigger an error.
    imports_text = list(source)
    for kind, start, end in spans:
        if kind == "comment":
            for i in range(start, end):
                if imports_text[i] != "\n":
                    imports_text[i] = " "
    imports = []
    for match in re.finditer(r"^\s*import\s+(qs(?:\.[\w]+)*)(?:\s+[\d.]+)?(?:\s+as\s+(\w+))?\s*;?\s*$",
                             "".join(imports_text), re.M):
        module, alias = match.groups()
        directory = shell.joinpath(*module.split(".")[1:])
        if not directory.is_dir():
            error(match.start(), f"missing shell module {module}")
        imports.append((module, alias, directory))

    accessible = {}
    for module, alias, directory in imports:
        if not alias:
            accessible.update(lexer.atmosphera_names(str(shell), str(directory), module))
    accessible.update(lexer.atmosphera_names(str(shell), str(path.parent), "local"))
    shadows = {}
    for module in lexer.file_imports(source):
        if not module.startswith("qs.") and module != "qs":
            for name in foreign.exports(module):
                if name in accessible:
                    shadows[name] = module

    aliases = {alias: directory for _, alias, directory in imports if alias}
    for token in tokens:
        name = token.text
        if token.prev_char == "." and not token.spread:
            continue
        if name in shadows:
            error(token.start, f"{name} is shadowed by imported {shadows[name]}")
        if name == "Color" and "AtmoColor" in accessible and token.next_char in ".[":
            error(token.start, "bare Color resolves to QtQuick's utility; use AtmoColor")
        if name in RETIRED and name not in accessible and RETIRED[name] in accessible:
            error(token.start, f"retired widget {name}; use {RETIRED[name]}")
        if name in api and name in accessible:
            member = re.match(r"\s*\.\s*([A-Za-z_$][\w$]*)", masked[token.end:])
            if member and member.group(1) not in api[name]:
                error(token.start, f"{name}.{member.group(1)} is not a root API member")
        if name in aliases:
            member = re.match(r"\s*\.\s*([A-Za-z_$][\w$]*)", masked[token.end:])
            if member and member.group(1) in RETIRED:
                retired = member.group(1)
                directory = aliases[name]
                if not (directory / (retired + ".qml")).exists():
                    error(token.start, f"retired widget {name}.{retired}; use {name}.{RETIRED[retired]}")
    return errors


def lint(root, shell=SHELL_ROOT, changes=None, qml_dir="/usr/lib/qt6/qml", paths=None, catalog=None):
    lexer = load_lexer(shell)
    foreign = lexer.ForeignModules(qml_dir)
    api = {name: root_members(shell / f"Commons/{name}.qml", lexer)
           for name in ("AtmoColor", "Style")}
    errors = []
    manifests = {}
    selected = None if changes is None else set(changes.get("checked_plugins", changes.get("previous_versions", {})))
    for path in sorted(root.glob("*/manifest.json")):
        try:
            manifest = json.loads(path.read_text())
        except (ValueError, OSError) as exc:
            errors.append(f"{path}: cannot read manifest: {exc}")
            continue
        manifests[path.parent.name] = manifest
        if manifest.get("id") != path.parent.name:
            errors.append(f"{path}: id must equal directory name {path.parent.name!r}")
        if version(manifest.get("version")) is None:
            errors.append(f"{path}: version must be plain x.y.z")
        for name, entry in manifest.get("entryPoints", {}).items():
            url = urlsplit(entry) if isinstance(entry, str) else None
            if url is None or url.scheme or url.netloc or Path(url.path).is_absolute() or ".." in Path(url.path).parts:
                errors.append(f"{path}: unsafe {name} entry point {entry!r}")
            elif not ((path.parent / url.path).is_dir() if name == "wallpapers" else
                      (path.parent / url.path).is_file()):
                errors.append(f"{path}: {name} entry point missing: {entry}")
        if selected is not None and path.parent.name not in selected:
            continue
        uses_palette = False
        files = sorted(path.parent.rglob("*.qml")) + sorted(path.parent.rglob("*.js"))
        for file in files:
            if file.is_symlink():
                errors.append(f"{file}: symlink source is not supported by the lint snapshot")
                continue
            if paths is None or file.relative_to(root).as_posix() in paths:
                errors.extend(lint_source(file, shell, lexer, api, foreign))
            uses_palette |= any(t.text == "AtmoColor" and (t.prev_char != "." or t.spread)
                                for t in lexer.lex(file.read_text())[0])
        minimum = version(manifest.get("minAtmospheraVersion"))
        if uses_palette and (minimum is None or minimum < (0, 8, 0)):
            errors.append(f"{path}: AtmoColor requires minAtmospheraVersion >= 0.8.0")

    registry_path = catalog if catalog is not None else root / "registry.json"
    if registry_path.exists():
        registry = json.loads(registry_path.read_text())["plugins"]
        ids = [entry["id"] for entry in registry]
        if len(ids) != len(set(ids)):
            errors.append(f"{registry_path}: duplicate plugin IDs")
        for missing in sorted(set(manifests) ^ set(ids)):
            errors.append(f"{registry_path}: {missing}: manifest/catalog membership mismatch")
        for entry in registry:
            manifest = manifests.get(entry["id"])
            if manifest:
                for key in ("version", "minAtmospheraVersion", "minNoctaliaVersion"):
                    if entry.get(key) != manifest.get(key):
                        errors.append(f"{registry_path}: {entry['id']}: {key} differs from manifest")

    for plugin, old in (changes or {}).get("previous_versions", {}).items():
        if plugin in manifests:
            current = version(manifests[plugin].get("version"))
            previous = version(old)
            if previous is None or current is None or current <= previous:
                errors.append(f"{root / plugin / 'manifest.json'}: changed plugin needs a version bump above {old}")
    return errors


def changes_from_snapshot(root, base):
    """Compare plugin content, not mtimes, and ignore documentation-only edits."""
    selected, previous = set(), {}
    for manifest in sorted(root.glob("*/manifest.json")):
        plugin = manifest.parent.name
        def contents(directory):
            return {p.relative_to(directory).as_posix(): (p.read_bytes(), p.stat().st_mode & 0o111)
                    for p in directory.rglob("*") if p.is_file() and p.suffix not in (".md", ".txt")}
        old = base / plugin
        if contents(manifest.parent) != contents(old):
            selected.add(plugin)
            if (old / "manifest.json").is_file():
                previous[plugin] = json.loads((old / "manifest.json").read_text())["version"]
    return {"checked_plugins": sorted(selected), "previous_versions": previous}


def changes_from_git(root, base):
    repo = Path(subprocess.check_output(["git", "-C", str(root), "rev-parse", "--show-toplevel"], text=True, timeout=30).strip())
    prefix = root.resolve().relative_to(repo.resolve()).as_posix()
    prefix = "" if prefix == "." else prefix + "/"
    if not base or set(base) == {"0"}:
        return None
    names = subprocess.check_output(["git", "-C", str(repo), "diff", "--name-only", "-z", base, "HEAD", "--"], timeout=30)
    selected, previous = set(), {}
    for raw in names.split(b"\0"):
        name = raw.decode("utf-8", "surrogateescape")
        if not name.startswith(prefix):
            continue
        relative = name[len(prefix):]
        if "/" not in relative or relative.endswith((".md", ".txt")):
            continue
        plugin = relative.split("/", 1)[0]
        if not (root / plugin / "manifest.json").is_file():
            continue
        selected.add(plugin)
        old = subprocess.run(["git", "-C", str(repo), "show", base + ":" + prefix + plugin + "/manifest.json"], capture_output=True, timeout=30)
        if old.returncode == 0:
            previous[plugin] = json.loads(old.stdout)["version"]
    return {"checked_plugins": sorted(selected), "previous_versions": previous}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, help="catalog JSON (default: ROOT/registry.json)")
    base = parser.add_mutually_exclusive_group()
    base.add_argument("--base-root", type=Path, help="base plugin snapshot for changed-plugin/version checks")
    base.add_argument("--base-ref", help="CI: lint changed plugins and require version bumps relative to this Git commit")
    parser.add_argument("--qml-dir", default="/usr/lib/qt6/qml")
    args = parser.parse_args()
    try:
        changes = (changes_from_snapshot(args.root, args.base_root) if args.base_root is not None else
                   changes_from_git(args.root, args.base_ref) if args.base_ref is not None else None)
        errors = lint(args.root.resolve(), changes=changes, qml_dir=args.qml_dir, catalog=args.catalog)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"plugin lint: configuration/input error: {exc}")
        return 2
    for error in errors:
        print(error)
    print(f"plugin compatibility: {len(errors)} problem(s)")
    return bool(errors)


if __name__ == "__main__":
    raise SystemExit(main())
