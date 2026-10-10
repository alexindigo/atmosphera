#!/usr/bin/env python3
"""Fixture self-test for qml-identifiers.py. Prints "selftest: N passed"."""
import contextlib
import importlib.util
import io
import os
import sys
import tempfile

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


SHADOW_FILES = {
    # fake Qt module dir
    "qt/QtQuick/qmldir": "module QtQuick\nplugin qtquick2plugin\ntypeinfo plugins.qmltypes\nimport QtQml auto\n",
    "qt/QtQuick/plugins.qmltypes": 'Module {\n  Component { name: "QQuickColor"; exports: ["QtQuick/Color 6.12"] }\n'
                                   '  Component { name: "QQuickItem"; exports: ["QtQuick/Item 2.0", "QtQuick/Item 2.1"] }\n'
                                   '  Component { name: "Other"; exports: ["QtOther/Style 1.0"] }\n}\n',
    "qt/QtQml/qmldir": "module QtQml\nTimer 2.0 Timer.qml\nsingleton Logger 1.0 Logger.qml\n",
    # fake Atmosphera root
    "root/Commons/Color.qml": "pragma Singleton\nimport QtQuick\nQtObject { property color mPrimary }\n",
    "root/Commons/Style.qml": "pragma Singleton\nimport QtQuick\nQtObject {}\n",
    "root/Commons/Logger.qml": "pragma Singleton\nimport QtQuick\nQtObject {}\n",
    "root/Widgets/W.qml": "import QtQuick\nimport qs.Commons\nItem {\n  // Color.mPrimary in a comment\n"
                          "  property string s: \"Color\"\n  property color c: Color.mPrimary\n"
                          "  property color d: Color.mPrimary\n  property var st: Style\n  property var l: Logger\n}\n",
    "root/Widgets/Q.qml": "import QtQuick as Q\nimport qs.Commons\nQ.Item { property color c: Color.mPrimary }\n",
    "root/Widgets/N.qml": "import qs.Commons\nQtObject { property color c: Color.mPrimary }\n",
    "root/Commons/Own.qml": "import QtQuick\nItem { property color c: Color.mPrimary }\n",
}
SHADOW_EXPECTED = [
    "Commons/Own.qml:2: Color (Atmosphera singleton via qs.Commons) shadowed by QtQuick (1 refs)",
    "Widgets/W.qml:6: Color (Atmosphera singleton via qs.Commons) shadowed by QtQuick (2 refs)",
    "Widgets/W.qml:9: Logger (Atmosphera singleton via qs.Commons) shadowed by QtQuick (1 refs)",
    "shadowing: 4 reference(s) in 2 file(s)",
]


def shadowing_fixtures():
    passed, failures = 0, []
    with tempfile.TemporaryDirectory() as tmp:
        for rel, text in SHADOW_FILES.items():
            path = os.path.join(tmp, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
        cwd = os.getcwd()
        os.chdir(os.path.join(tmp, "root"))
        try:
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = tool.main(["shadowing", "--qt-qml-dir", os.path.join(tmp, "qt"), "--root", ".", "Commons", "Widgets"])
        finally:
            os.chdir(cwd)
    got = out.getvalue().splitlines()
    if got == SHADOW_EXPECTED and code == 1:
        passed += 1
    else:
        failures.append(f"shadowing: exit {code}, got {got}, expected {SHADOW_EXPECTED}")
    return passed, failures


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
    shadow_passed, shadow_failures = shadowing_fixtures()
    passed += shadow_passed
    failures += shadow_failures
    for failure in failures:
        print("FAIL:", failure)
    if failures:
        print(f"selftest: {passed} passed, {len(failures)} failed")
        return 1
    print(f"selftest: {passed} passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
