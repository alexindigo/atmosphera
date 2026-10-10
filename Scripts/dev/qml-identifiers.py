#!/usr/bin/env python3
"""String- and comment-aware identifier tooling for QML/JS sources.

  rename --from OLD --to NEW [--check] [--report FILE] PATH...
      Rename code tokens exactly equal to OLD, unless the previous non-space
      code character is "." (a member of something else). Text inside
      strings, comments, template-literal text and regex literals is never
      touched. --check writes nothing and exits 1 if anything is pending.

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
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
