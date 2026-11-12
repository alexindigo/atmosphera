#!/usr/bin/env python3
"""Probe-owner contract tests; run only in the assigned project test VM."""
import ast
from pathlib import Path
import tempfile
import unittest

from qml_probe import inject_probe


HERE = Path(__file__).resolve().parent
PROBE = 'property string injectedProbe: "consumer"'


class ProbeScopeTests(unittest.TestCase):
    def inject_at_marker(self, text, *, root_id="shellRoot"):
        source = text.replace("INSERT_HERE", "")
        expected = text.replace("INSERT_HERE", "\n" + PROBE + "\n")
        self.assertEqual(inject_probe(source, PROBE, root_id=root_id), expected)

    def test_legacy_root(self):
        self.inject_at_marker("import QtQuick\nShellRoot { id: shellRoot; INSERT_HERE}\n")

    def test_elected_component_and_trailing_siblings(self):
        self.inject_at_marker('''import QtQuick
ShellRoot {
  Loader {
    active: ShellRegistration.elected
    sourceComponent: Item {
      id: shellRoot
      Timer { onTriggered: { const value = ({a: {b: 1}}); } }
    INSERT_HERE}
  }
  Item { property string sibling: "outside" }
}
// trailing braces: }}} id: shellRoot
''')

    def test_id_not_first_property(self):
        self.inject_at_marker("Item { Item { property int before: 1; id: shellRoot; INSERT_HERE} }")

    def test_comments_and_quoted_braces(self):
        self.inject_at_marker(r'''Item {
  // id: shellRoot; }
  /* } { id: shellRoot */
  property string fake: "id: shellRoot { } \\\""
  property string single: 'id: shellRoot \' { }'
  Item { id /* comment */ : shellRoot; INSERT_HERE}
}''')

    def test_templates_regex_and_division(self):
        self.inject_at_marker(r'''Item {
  property var fake: `id: shellRoot } ${({x: /[{}]/, value: "}"})} {`
  property var pattern: /id: shellRoot[{}]/g
  Item {
    id: shellRoot
    function number(x) { return x / 2; }
  INSERT_HERE}
}''')

    def test_explicit_component_owner(self):
        self.inject_at_marker("Singleton { id: root; Item { id: other } INSERT_HERE}", root_id="root")

    def test_repeated_injections_keep_owner(self):
        source = "Item { Loader { sourceComponent: Item { id: shellRoot; } } }"
        first = inject_probe(source, PROBE)
        second = inject_probe(first, "property bool anotherProbe: true")
        self.assertIn(PROBE + "\n\nproperty bool anotherProbe: true\n}", second)

    def test_missing_and_ambiguous_owners_fail(self):
        for source in ("Item {}", 'Item { property string fake: "id: shellRoot" }',
                       "Item { id: shellRoot; Item { id: shellRoot; } }"):
            with self.subTest(source=source), self.assertRaisesRegex(ValueError, "expected one QML probe owner"):
                inject_probe(source, PROBE)

    def test_invalid_owner_fails(self):
        with self.assertRaisesRegex(ValueError, "invalid QML probe owner"):
            inject_probe("Item {}", PROBE, root_id="shellRoot.*")

    def test_malformed_scopes_fail(self):
        for source in ("id: shellRoot", "Item { id: shellRoot;", "Item { id: shellRoot; }}"):
            with self.subTest(source=source), self.assertRaises(ValueError):
                inject_probe(source, PROBE)

    def test_generic_chooser_instrumenter_uses_explicit_owner(self):
        tree = ast.parse((HERE / "filechooser-isolation-regression.py").read_text())
        instrument = next(node for node in tree.body if isinstance(node, ast.FunctionDef)
                          and node.name == "instrument")
        scope = {"inject_probe": inject_probe}
        exec(compile(ast.Module(body=[instrument], type_ignores=[]), "instrument", "exec"), scope)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name, source, owner in (
                    ("shell.qml", "ShellRoot { Loader { sourceComponent: Item { id: shellRoot; } } }", "shellRoot"),
                    ("Picker.qml", "Window { id: root; Item {} }", "root")):
                (root / name).write_text(source)
                scope["instrument"](root, name, PROBE, root_id=owner)
                self.assertEqual((root / name).read_text(),
                                 "import Quickshell.Io\n" + inject_probe(source, PROBE, root_id=owner))

    def test_all_full_shell_probe_payloads(self):
        source = (HERE.parents[1] / "shell.qml").read_text()
        # Both versions identify the same session owner, at different depths.
        shapes = (source, "ShellRoot { id: shellRoot; }",
                  "ShellRoot { Loader { active: elected; sourceComponent: Item { id: shellRoot; } } }")
        runners = []
        for path in sorted(HERE.glob("*.py")):
            if path.name == Path(__file__).name:
                continue
            tree = ast.parse(path.read_text(), filename=str(path))
            if not any(isinstance(node, ast.ImportFrom) and node.module == "qml_probe"
                       for node in tree.body):
                continue
            assignments = [node for node in tree.body if isinstance(node, ast.Assign)
                           and any(isinstance(t, ast.Name) and t.id in ("PROBE", "OBSERVER")
                                   for t in node.targets)]
            if not assignments:  # Generic component instrumenters have inline payloads.
                continue
            name, assignment = path.name, assignments[0]
            runners.append(name)
            payload = ast.literal_eval(assignment.value)
            self.assertTrue(any(isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                                and node.func.id == "inject_probe" for node in ast.walk(tree)), name)
            for shape in shapes:
                with self.subTest(runner=name, shape=shape[:50]):
                    observed = inject_probe(shape, payload)
                    self.assertEqual(observed.count(payload), 1)
                    self.assertEqual(observed.replace("\n" + payload + "\n", "", 1), shape)
        self.assertIn("panel-cold-load.py", runners)
        self.assertIn("plugin-panel-lifecycle.py", runners)
        self.assertIn("launcher-flow-e2e.py", runners)


if __name__ == "__main__":
    unittest.main(verbosity=2)
