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


def inject_probe(source, probe, *, root_id="shellRoot"):
    """Return source with probe inside the unique object declaring root_id.

    Reuse the repository's QML/JS lexer so quoted/commented braces and fake ID
    declarations cannot move instrumentation across a component boundary.
    The caller retains ownership of imports, source copies and probe assertions.
    """
    if not re.fullmatch(r"[a-z_][A-Za-z0-9_]*", root_id):
        raise ValueError(f"invalid QML probe owner ID: {root_id!r}")
    _tokens, spans = _identifiers.lex(source)
    code = list(source)
    for _kind, start, end in spans:
        code[start:end] = " " * (end - start)
    code = "".join(code)
    declarations = list(re.finditer(
        rf"(?<![\w$.])id\s*:\s*{re.escape(root_id)}(?![\w$])", code))
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
