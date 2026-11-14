"""Insert test-only QML in its owning object's scope, not a file's outer root.

Full-shell probes belong to the elected session object declaring shellRoot.
Other component probes can name their own ID. Source layout and wrapper depth
are immaterial; missing or ambiguous owners fail before any source is written.
"""
import importlib.util
from pathlib import Path
import re


_spec = importlib.util.spec_from_file_location(
    "qml_identifiers", Path(__file__).with_name("qml-identifiers.py"))
_identifiers = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_identifiers)


def _owner_code(source, root_id):
    if not re.fullmatch(r"[a-z_][A-Za-z0-9_]*", root_id):
        raise ValueError(f"invalid QML probe owner ID: {root_id!r}")
    _tokens, spans = _identifiers.lex(source)
    code = list(source)
    for _kind, start, end in spans:
        code[start:end] = " " * (end - start)
    code = "".join(code)
    declarations = list(re.finditer(
        rf"(?<![\w$.])id\s*:\s*{re.escape(root_id)}(?![\w$])", code))
    return code, declarations


def probe_owner_path(shell, *, root_id="shellRoot"):
    """Select the unique declaring file, not the shell's bootstrap entry point."""
    shell = Path(shell)
    owners = []
    for name in ("shell.qml", "ShellSession.qml"):
        path = shell / name
        if path.is_file():
            _code, declarations = _owner_code(path.read_text(), root_id)
            owners.extend(path for _ in declarations)
    if len(owners) != 1:
        raise ValueError(f"expected one QML probe owner id: {root_id}; found {len(owners)}")
    return owners[0]


def inject_probe(source, probe, *, root_id="shellRoot"):
    """Insert in the unique owner's lexical scope, preserving its lifetime.

    Reuse the repository's QML/JS lexer so quoted/commented braces and fake ID
    declarations cannot move instrumentation across a component boundary.
    Imports, disposable copies and probe assertions remain caller-owned.
    """
    code, declarations = _owner_code(source, root_id)
    if len(declarations) != 1:
        raise ValueError(f"expected one QML probe owner id: {root_id}; found {len(declarations)}")
    anchor = declarations[0].start()
    stack, owner, insertion = [], None, None
    for offset, char in enumerate(code):
        if offset == anchor:
            if not stack:
                raise ValueError(f"QML probe owner id: {root_id} is outside an object")
            owner = stack[-1]
        if char == "{":
            stack.append(offset)
        elif char == "}":
            if not stack:
                raise ValueError("unmatched closing brace in QML probe source")
            if stack.pop() == owner:
                insertion = offset
    if stack or insertion is None:
        raise ValueError("unclosed object in QML probe source")
    return source[:insertion] + "\n" + probe + "\n" + source[insertion:]


def bootstrap_fixture(source):
    """Keep the original inert object behind the production readiness frontier."""
    code, _declarations = _owner_code(source, "root")
    roots = list(re.finditer(r"(?<![\w$.])ShellRoot\s*\{", code))
    if len(roots) != 1:
        raise ValueError(f"expected one inert ShellRoot; found {len(roots)}")
    position = roots[0].start()
    prelude, body = source[:position], source[position:]
    if not re.search(r"\bimport\s+qs\.Commons\b", code[:position]):
        prelude += "import qs.Commons\n"
    return (prelude + "ShellRoot {\n"
            "  SettingsBootstrap { id: fixtureDirectories }\n"
            "  Loader {\n"
            "    active: fixtureDirectories.ready\n"
            "    sourceComponent: Component {\n"
            "      Loader {\n"
            "        active: Settings.isLoaded\n"
            "        sourceComponent: Component {\n" + body +
            "\n        }\n      }\n    }\n  }\n}\n")
