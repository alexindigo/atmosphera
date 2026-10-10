#!/usr/bin/env python3
"""String- and comment-aware identifier tooling for QML/JS sources.

  rename --from OLD --to NEW [--check] [--report FILE] PATH...
      Rename code tokens exactly equal to OLD, unless the previous non-space
      code character is "." (a member of something else). Text inside
      strings, comments, template-literal text and regex literals is never
      touched. --check writes nothing and exits 1 if anything is pending.

  shadowing [--qt-qml-dir DIR] [--root DIR] PATH...
      Report Atmosphera type names (files reachable through a file's qs.*
      imports or its own directory) that an unqualified non-qs import also
      exports. Qt resolves imported modules' C++ types before QML composite
      singletons, so such a name silently reaches the foreign type. Exits 1
      if any code reference is shadowed.

The lexer distinguishes code, // and /* */ comments, ' and " strings,
template literals (text untouched; ${...} lexed as code, nesting allowed)
and regex literals (a "/" at input start, after an operator or one of
( , = : [ ! & | ? { } ; -- except postfix ++/-- -- or after a keyword such as
return/typeof/case). A spread "...Name" is code, not a member access.
"""
import argparse
import os
import re
import sys

SKIP_DIRS = {".git", "node_modules", ".opencode"}
EXTENSIONS = (".qml", ".js")
REGEX_PRECEDERS = set("(,=:[!&|?{};+-*%<>~^")
REGEX_KEYWORDS = {"return", "typeof", "case", "else", "in", "of", "instanceof",
                  "void", "delete", "throw", "new", "do", "yield", "await"}
IDENT_START = re.compile(r"[A-Za-z_$]")
IDENT = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")
NUMBER = re.compile(r"[0-9][A-Za-z0-9_.]*|\.[0-9][A-Za-z0-9_]*")


class Token:
    __slots__ = ("text", "start", "end", "prev_char", "prev_token", "next_char", "spread")

    def __init__(self, text, start, end, prev_char, prev_token):
        self.spread = False
        self.text = text
        self.start = start
        self.end = end
        self.prev_char = prev_char
        self.prev_token = prev_token
        self.next_char = ""


def lex(src):
    """Return (identifier tokens in code, non-code spans [(kind, start, end)])."""
    tokens = []
    spans = []
    n = len(src)
    i = 0
    prev_char = ""      # last significant code character
    prev_prev = ""      # code character before prev_char
    prev_token = None   # last identifier token, if it is the last code item
    pending_next = []   # tokens waiting for their next significant code char
    # Stack of contexts: ("code", brace_depth) or ("template",)
    stack = [["code", 0]]

    def code_char(c):
        nonlocal prev_char, prev_prev, prev_token, pending_next
        prev_prev = prev_char if prev_char else ""
        prev_char = c
        prev_token = None
        for t in pending_next:
            t.next_char = c
        pending_next = []

    while i < n:
        top = stack[-1]
        if top[0] == "template":
            start = i
            while i < n:
                c = src[i]
                if c == "\\":
                    i += 2
                    continue
                if c == "`":
                    break
                if c == "$" and i + 1 < n and src[i + 1] == "{":
                    break
                i += 1
            if i > start:
                spans.append(("template-text", start, min(i, n)))
            if i >= n:
                break
            if src[i] == "`":
                stack.pop()
                i += 1
                code_char("`")
            else:  # ${
                i += 2
                stack.append(["code", 0])
                code_char("{")
            continue

        c = src[i]
        if c in " \t\r\n":
            i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            end = src.find("\n", i)
            end = n if end < 0 else end
            spans.append(("comment", i, end))
            i = end
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            end = src.find("*/", i + 2)
            end = n if end < 0 else end + 2
            spans.append(("comment", i, end))
            i = end
            continue
        if c in "'\"":
            start = i
            i += 1
            while i < n and src[i] != c:
                i += 2 if src[i] == "\\" else 1
            i = min(i + 1, n)
            spans.append(("string", start, i))
            code_char(c)
            continue
        if c == "`":
            i += 1
            stack.append(["template"])
            continue
        if c == "/":
            postfix = prev_char in "+-" and prev_prev == prev_char  # i++ / 2
            is_regex = (prev_char == "" or (prev_char in REGEX_PRECEDERS and not postfix)
                        or (prev_token is not None and prev_token.text in REGEX_KEYWORDS))
            if is_regex:
                start = i
                i += 1
                in_class = False
                while i < n:
                    ch = src[i]
                    if ch == "\\":
                        i += 2
                        continue
                    if ch == "\n":
                        break
                    if in_class:
                        if ch == "]":
                            in_class = False
                    elif ch == "[":
                        in_class = True
                    elif ch == "/":
                        i += 1
                        break
                    i += 1
                while i < n and (src[i].isalnum() or src[i] == "_"):
                    i += 1  # flags
                spans.append(("regex", start, i))
                code_char("/")
                continue
            i += 1
            code_char("/")
            continue
        if IDENT_START.match(c):
            m = IDENT.match(src, i)
            tok = Token(m.group(), i, m.end(), prev_char, prev_token)
            tok.spread = prev_char == "." and src[:i].rstrip().endswith("...")
            for t in pending_next:
                t.next_char = m.group()[0]
            pending_next = [tok]
            tokens.append(tok)
            prev_prev = ""
            prev_char = m.group()[-1]
            prev_token = tok
            i = m.end()
            continue
        m = NUMBER.match(src, i)
        if m and (c.isdigit() or (c == "." and i + 1 < n and src[i + 1].isdigit())):
            i = m.end()
            code_char("0")
            continue
        if c == "{":
            top[1] += 1
        elif c == "}":
            if top[1] == 0 and len(stack) > 1:
                stack.pop()  # end of ${...}; back to template text
                i += 1
                continue
            top[1] -= 1
        i += 1
        code_char(c)
    return tokens, spans


def category(tok):
    if tok.prev_token is not None and tok.prev_token.text == "typeof":
        return "typeof"
    if tok.next_char == ".":
        return "member-root"
    if tok.next_char == "[":
        return "index"
    return "bare"


def analyze(src, old, new):
    """Return (renameable tokens, skipped [(kind, offset)], pre-existing new tokens)."""
    tokens, spans = lex(src)
    rename = []
    skipped = []
    existing = []
    word = re.compile(r"(?<![A-Za-z0-9_$])" + re.escape(old) + r"(?![A-Za-z0-9_$])")
    for tok in tokens:
        if tok.text == old:
            if tok.prev_char == "." and not tok.spread:
                skipped.append(("member", tok.start))
            else:
                rename.append(tok)
        elif tok.text == new:
            existing.append(tok)
    for kind, start, end in spans:
        for m in word.finditer(src, start, end):
            skipped.append((kind, m.start()))
    skipped.sort(key=lambda s: s[1])
    return rename, skipped, existing


def rename_text(src, old, new):
    rename, skipped, existing = analyze(src, old, new)
    out = src
    for tok in reversed(rename):
        out = out[:tok.start] + new + out[tok.end:]
    return out, rename, skipped, existing


def iter_files(paths):
    files = set()
    for path in paths:
        if os.path.islink(path):
            continue
        if os.path.isfile(path):
            if path.endswith(EXTENSIONS):
                files.add(os.path.normpath(path))
            continue
        for root, dirs, names in os.walk(path, followlinks=False):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for name in names:
                full = os.path.join(root, name)
                if name.endswith(EXTENSIONS) and not os.path.islink(full):
                    files.add(os.path.normpath(full))
    return sorted(files)


def line_of(src, offset):
    return src.count("\n", 0, offset) + 1


def context(src, offset):
    start = src.rfind("\n", 0, offset) + 1
    end = src.find("\n", offset)
    return src[start:(len(src) if end < 0 else end)].strip()


def cmd_rename(args):
    counts = {"member-root": 0, "bare": 0, "index": 0, "typeof": 0}
    changed_files = 0
    total = 0
    skipped_lines = []
    existing_lines = []
    for path in iter_files(args.paths):
        with open(path, encoding="utf-8") as fh:
            src = fh.read()
        out, rename, skipped, existing = rename_text(src, args.old, args.new)
        for tok in rename:
            counts[category(tok)] += 1
        for kind, off in skipped:
            skipped_lines.append(f"{path}:{line_of(src, off)}: {kind}: {context(src, off)}")
        for tok in existing:
            existing_lines.append(f"{path}:{line_of(src, tok.start)}: {context(src, tok.start)}")
        if rename:
            total += len(rename)
            changed_files += 1
            if not args.check:
                with open(path, "w", encoding="utf-8") as fh:
                    fh.write(out)
    verb = "pending" if args.check else "renamed"
    lines = [
        f"{verb} {total} in {changed_files} files ("
        + ", ".join(f"{k} {v}" for k, v in counts.items()) + ")",
        f"pre-existing {args.new}: {len(existing_lines)}",
        *(f"  {line}" for line in existing_lines),
        f"skipped: {len(skipped_lines)}",
        *(f"  {line}" for line in skipped_lines),
    ]
    report = "\n".join(lines) + "\n"
    sys.stdout.write(report)
    if args.report:
        with open(args.report, "w", encoding="utf-8") as fh:
            fh.write(report)
    return 1 if (args.check and total) else 0


IMPORT_RE = re.compile(r"^\s*import\s+([A-Za-z_][\w.]*)(?:\s+[\d.]+)?(\s+as\s+\w+)?\s*;?\s*$")
EXPORT_RE = re.compile(r'"([\w.]+)/(\w+)(?: [\d.]+)?"')


def file_imports(src):
    """Unqualified module imports declared in a QML file (comments ignored)."""
    _tokens, spans = lex(src)
    blanked = list(src)
    for kind, start, end in spans:
        if kind == "comment":
            for i in range(start, end):
                if blanked[i] != "\n":
                    blanked[i] = " "
    imports = []
    for line in "".join(blanked).splitlines():
        m = IMPORT_RE.match(line)
        if m and not m.group(2):
            imports.append(m.group(1))
    return imports


def atmosphera_names(root, directory, module):
    """{Name: (kind, module)} for capitalized .qml files in a directory."""
    names = {}
    if not os.path.isdir(directory):
        return names
    for entry in sorted(os.listdir(directory)):
        if entry.endswith(".qml") and entry[0].isupper():
            path = os.path.join(directory, entry)
            with open(path, encoding="utf-8", errors="replace") as fh:
                singleton = re.search(r"^\s*pragma\s+Singleton\b", fh.read(), re.M) is not None
            names[entry[:-4]] = ("singleton" if singleton else "type", module)
    return names


class ForeignModules:
    """Exported names of installed QML modules (qmldir + *.qmltypes), with qmldir imports."""

    def __init__(self, qml_dir):
        self.qml_dir = qml_dir
        self.cache = {}

    def exports(self, module, seen=None):
        if module in self.cache:
            return self.cache[module]
        seen = set() if seen is None else seen
        if module in seen:
            return {}
        seen.add(module)
        names = {}
        directory = os.path.join(self.qml_dir, *module.split("."))
        qmldir = os.path.join(directory, "qmldir")
        if os.path.isfile(qmldir):
            with open(qmldir, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    parts = line.split()
                    if not parts or parts[0] in ("module", "plugin", "classname", "typeinfo", "depends",
                                                 "designersupported", "prefer", "optional", "linktarget",
                                                 "internal", "default", "static", "system"):
                        continue
                    if parts[0] == "import" and len(parts) > 1:
                        for name in self.exports(parts[1], seen):
                            names.setdefault(name, module)
                        continue
                    if parts[0] == "singleton" and len(parts) > 1:
                        parts = parts[1:]
                    if parts[0][:1].isupper():
                        names[parts[0]] = module
        if os.path.isdir(directory):
            for entry in sorted(os.listdir(directory)):
                if entry.endswith(".qmltypes"):
                    with open(os.path.join(directory, entry), encoding="utf-8", errors="replace") as fh:
                        for line in fh:
                            if "exports:" in line:
                                for mod, name in EXPORT_RE.findall(line):
                                    if mod == module:
                                        names[name] = module
        self.cache[module] = names
        return names


def cmd_shadowing(args):
    foreign = ForeignModules(args.qt_qml_dir)
    root = os.path.abspath(args.root)
    lines = []
    total = 0
    files = 0
    for path in iter_files(args.paths):
        if not path.endswith(".qml"):
            continue
        with open(path, encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        imports = file_imports(src)
        own_dir = os.path.dirname(os.path.abspath(path))
        own_rel = os.path.relpath(own_dir, root)
        own_module = "qs" if own_rel == "." else "qs." + own_rel.replace(os.sep, ".")
        ours = dict(atmosphera_names(root, own_dir, own_module))
        theirs = {}
        for module in imports:
            if module == "qs" or module.startswith("qs."):
                directory = os.path.join(root, *module.split(".")[1:])
                for name, info in atmosphera_names(root, directory, module).items():
                    ours.setdefault(name, info)
            else:
                for name in foreign.exports(module):
                    theirs.setdefault(name, module)
        clashes = {name: theirs[name] for name in ours if name in theirs}
        if not clashes:
            continue
        tokens, _spans = lex(src)
        hit = False
        for name in sorted(clashes):
            refs = [t for t in tokens if t.text == name and (t.prev_char != "." or t.spread)]
            if refs:
                kind, via = ours[name]
                lines.append(f"{path}:{line_of(src, refs[0].start)}: {name} (Atmosphera {kind} via {via}) "
                             f"shadowed by {clashes[name]} ({len(refs)} refs)")
                total += len(refs)
                hit = True
        files += hit
    lines.append(f"shadowing: {total} reference(s) in {files} file(s)")
    sys.stdout.write("\n".join(lines) + "\n")
    return 1 if total else 0


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    r = sub.add_parser("rename", help="rename a code identifier")
    r.add_argument("--from", dest="old", required=True)
    r.add_argument("--to", dest="new", required=True)
    r.add_argument("--check", action="store_true")
    r.add_argument("--report")
    r.add_argument("paths", nargs="+", metavar="PATH")
    r.set_defaults(func=cmd_rename)
    sh = sub.add_parser("shadowing", help="report Atmosphera names shadowed by imported modules")
    sh.add_argument("--qt-qml-dir", default="/usr/lib/qt6/qml")
    sh.add_argument("--root", default=".")
    sh.add_argument("paths", nargs="+", metavar="PATH")
    sh.set_defaults(func=cmd_shadowing)
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
