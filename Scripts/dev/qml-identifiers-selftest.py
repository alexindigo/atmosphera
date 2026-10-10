#!/usr/bin/env python3
"""Fixture self-test for qml-identifiers.py. Prints "selftest: N passed"."""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("qml_identifiers", os.path.join(HERE, "qml-identifiers.py"))
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

# (input, expected output, expected categories of renamed tokens)
RENAME_FIXTURES = [
    ("Color.mPrimary", "AtmoColor.mPrimary", ["member-root"]),
    ("target: Color", "target: AtmoColor", ["bare"]),
    ("typeof Color", "typeof AtmoColor", ["typeof"]),
    ("Color[key]", "AtmoColor[key]", ["index"]),
    ("f(Color, Color.x)", "f(AtmoColor, AtmoColor.x)", ["bare", "member-root"]),
    ('"Color.x"', '"Color.x"', []),
    ("'Color'", "'Color'", []),
    ("`Color ${Color.mPrimary} ${`n ${Color.x}`}`",
     "`Color ${AtmoColor.mPrimary} ${`n ${AtmoColor.x}`}`", ["member-root", "member-root"]),
    ("// Color.x", "// Color.x", []),
    ("/* Color */", "/* Color */", []),
    ("/Color/.test(s)", "/Color/.test(s)", []),
    ("x = /Color/.test(s)", "x = /Color/.test(s)", []),
    ("a / Color.x / 2", "a / AtmoColor.x / 2", ["member-root"]),
    ("Foo.Color", "Foo.Color", []),
    ("NColorPicker", "NColorPicker", []),
    ('"Noto Color Emoji"', '"Noto Color Emoji"', []),
    ('"esc \\" Color" + Color.x', '"esc \\" Color" + AtmoColor.x', ["member-root"]),
    ("color: Color.mPrimary // Color note\n", "color: AtmoColor.mPrimary // Color note\n", ["member-root"]),
    ("xs.filter(s => /^Color/.test(s))", "xs.filter(s => /^Color/.test(s))", []),
    ("q = c => /[\"']/.test(c)\nfont: \"Noto Color Emoji\"\nc: Color.x",
     "q = c => /[\"']/.test(c)\nfont: \"Noto Color Emoji\"\nc: AtmoColor.x", ["member-root"]),
    ("case /Color/.test(s): Color.x", "case /Color/.test(s): AtmoColor.x", ["member-root"]),
    ("p = \"^\" + /Color/.source", "p = \"^\" + /Color/.source", []),
    ("n = i++ / Color.k", "n = i++ / AtmoColor.k", ["member-root"]),
    ("return /[/]Color/.test(s) ? Color.a : 1", "return /[/]Color/.test(s) ? AtmoColor.a : 1", ["member-root"]),
    ("f({...Color})", "f({...AtmoColor})", ["bare"]),
    ("a?.Color", "a?.Color", []),
    ("`\\${Color} ${ {k: Color.x}.k }`", "`\\${Color} ${ {k: AtmoColor.x}.k }`", ["member-root"]),
    ("w: 2.15 * Color.s", "w: 2.15 * AtmoColor.s", ["member-root"]),
    ("AtmoColor.mPrimary", "AtmoColor.mPrimary", []),
]

# (input, expected skipped kinds)
SKIP_FIXTURES = [
    ('"Color.x"', ["string"]),
    ("// Color.x", ["comment"]),
    ("`Color ${x}`", ["template-text"]),
    ("/Color/.test(s)", ["regex"]),
    ("Foo.Color", ["member"]),
    ("NColorPicker", []),
]


def main():
    passed = 0
    failures = []
    for src, expected, cats in RENAME_FIXTURES:
        out, rename, _skipped, _existing = tool.rename_text(src, "Color", "AtmoColor")
        got_cats = [tool.category(t) for t in rename]
        if out == expected and got_cats == cats:
            passed += 1
        else:
            failures.append(f"rename {src!r}: got {out!r} {got_cats}, expected {expected!r} {cats}")
        again, rename2, _s, existing = tool.rename_text(out, "Color", "AtmoColor")
        if again == out and not rename2:
            passed += 1
        else:
            failures.append(f"idempotence {src!r}: second pass changed {again!r}")
    for src, kinds in SKIP_FIXTURES:
        _rename, skipped, _existing = tool.analyze(src, "Color", "AtmoColor")
        got = [k for k, _off in skipped]
        if got == kinds:
            passed += 1
        else:
            failures.append(f"skip {src!r}: got {got}, expected {kinds}")
    _r, _s, existing = tool.analyze("AtmoColor.mPrimary", "Color", "AtmoColor")
    if len(existing) == 1:
        passed += 1
    else:
        failures.append(f"pre-existing AtmoColor not reported: {existing}")
    for failure in failures:
        print("FAIL:", failure)
    if failures:
        print(f"selftest: {passed} passed, {len(failures)} failed")
        return 1
    print(f"selftest: {passed} passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
