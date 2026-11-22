#!/usr/bin/env python3
"""Regression cases for actual upgrade failures; execute only in VM/CI."""
import argparse
import importlib.util
import json
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

parser = argparse.ArgumentParser()
args, remaining = parser.parse_known_args()
CHECKER = Path(__file__).with_name("plugin-lint.py")
spec = importlib.util.spec_from_file_location("plugin_lint", CHECKER)
lint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lint)


class Regression(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.plugin = self.root / "example"
        self.plugin.mkdir()
        self.manifest = {"id": "example", "version": "1.0.1",
                         "minAtmospheraVersion": "0.8.0", "entryPoints": {"barWidget": "Bar.qml"}}
        self.write("import QtQuick\nimport qs.Commons\nimport qs.Widgets\nAtmoIconButton { colorFg: AtmoColor.mPrimary }\n")

    def write(self, source):
        (self.plugin / "manifest.json").write_text(json.dumps(self.manifest))
        (self.plugin / "Bar.qml").write_text(source)

    def errors(self, changes=None):
        return lint.lint(self.root, changes=changes)

    def test_current_api_passes(self):
        self.assertEqual(self.errors(), [])

    def test_digest_and_lockscreen_retired_widgets(self):
        for name in ("NIconButton", "NIcon"):
            self.write(f"import QtQuick\nimport qs.Widgets\n{name} {{}}\n")
            self.assertTrue(any("retired widget" in e for e in self.errors()))

    def test_screenshot_missing_import(self):
        self.write("import QtQuick\nimport qs.Services.Noctalia\nItem {}\n")
        self.assertTrue(any("missing shell module" in e for e in self.errors()))

    def test_color_and_unknown_member(self):
        self.write("import QtQuick\nimport qs.Commons\nItem { property color p: Color.mPrimary; property color q: AtmoColor.mTypo }\n")
        self.assertTrue(any("bare Color" in e for e in self.errors()))
        self.assertTrue(any("AtmoColor.mTypo" in e for e in self.errors()))

    def test_nested_member_is_not_public(self):
        self.write("import QtQuick\nimport qs.Commons\nItem { property var p: AtmoColor.defaultColors }\n")
        self.assertTrue(any("not a root API member" in e for e in self.errors()))

    def test_comments_strings_regex_and_template_interpolation(self):
        self.write('import QtQuick\nimport qs.Commons\nItem {\n// Color.mPrimary NIconButton\nproperty string x: "Color.mPrimary NIconButton"\nproperty var r: /Color.mPrimary/\nproperty string t: `Color.mPrimary ${AtmoColor.mPrimary}`\n}\n')
        self.assertEqual(self.errors(), [])
        self.write('import QtQuick\nimport qs.Commons\nItem { property string t: `${Color.mPrimary}` }\n')
        self.assertTrue(any("bare Color" in e for e in self.errors()))

    def test_version_bump_is_required_for_changed_plugin(self):
        self.assertTrue(any("version bump" in e for e in
                            self.errors({"previous_versions": {"example": "1.0.1"}})))
        self.assertEqual(self.errors({"previous_versions": {"example": "1.0.0"}}), [])

    def test_manifest_catalog_and_missing_entrypoint(self):
        (self.root / "registry.json").write_text(json.dumps({"plugins": [{**self.manifest, "version": "1.0.0"}]}))
        self.assertTrue(any("differs from manifest" in e for e in self.errors()))
        (self.plugin / "Bar.qml").unlink()
        self.assertTrue(any("entry point missing" in e for e in self.errors()))

    def test_removed_shell_type_is_unknown(self):
        # AtmoFilePicker was removed from the shell (6f5d71402); panels naming
        # it no longer loaded. A misspelled Qt type is the same failure.
        for name in ("AtmoFilePicker", "Rectangel"):
            self.write(f"import QtQuick\nimport qs.Widgets\nItem {{ {name} {{ id: picker }} }}\n")
            self.assertTrue(any(f"unknown type {name}" in e for e in self.errors()), name)

    def test_resolvable_object_types_pass(self):
        (self.plugin / "Card.qml").write_text("import QtQuick\nItem {}\n")
        (self.plugin / "parts").mkdir()
        (self.plugin / "parts/Chip.qml").write_text("import QtQuick\nItem {}\n")
        self.write('import QtQuick\nimport QtQuick.Controls as QQC\nimport QtQuick.Layouts\nimport Quickshell\n'
                   'import qs.Widgets\nimport qs.Portals\nimport "parts"\n'
                   'RowLayout {\n  enum Mode { A, B }\n  component Pill: Rectangle {}\n  Pill {}\n  Card {}\n  Chip {}\n'
                   '  QQC.Button {}\n  PanelWindow {}\n  PortalFilePicker {}\n  AtmoIcon {}\n'
                   '  Behavior on opacity { NumberAnimation {} }\n'
                   '  function f() { if (x) { return { Key: 1 } } }\n}\n')
        self.assertEqual([e for e in self.errors() if "unknown type" in e], [])

    def test_minimum_shell_version(self):
        self.manifest["minAtmospheraVersion"] = "0.7.0"
        self.write("import QtQuick\nimport qs.Commons\nItem { property color p: AtmoColor.mPrimary }\n")
        self.assertTrue(any("minAtmospheraVersion" in e for e in self.errors()))

    def test_entrypoint_query_string_is_supported(self):
        self.manifest["entryPoints"]["barWidget"] = "Bar.qml?v=2"
        self.write("import QtQuick\nItem {}\n")
        self.assertEqual(self.errors(), [])

    def test_wallpaper_directory_entrypoint_is_supported(self):
        self.manifest["entryPoints"]["wallpapers"] = "."
        self.write("import QtQuick\nItem {}\n")
        self.assertEqual(self.errors(), [])

    def test_unchanged_legacy_plugin_does_not_block_unrelated_commit(self):
        self.write("import QtQuick\nimport qs.Widgets\nNIconButton {}\n")
        self.assertTrue(self.errors())
        self.assertEqual(self.errors({"checked_plugins": [], "previous_versions": {}}), [])


class ActionRegression(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.plugin = self.root / "example"
        self.plugin.mkdir()
        self.action = {"id": "show", "label": "Show example", "description": "Show the example.",
                       "icon": "terminal", "command": "atmosphera ipc plugin:example show"}
        self.manifest = {"id": "example", "version": "1.0.1", "minAtmospheraVersion": "0.10.0",
                         "entryPoints": {"main": "Main.qml"}, "actions": [self.action]}
        self.source = 'import QtQuick\nimport Quickshell.Io\nItem { IpcHandler { target: "plugin:example"; function show() {} } }\n'

    def errors(self, changes=None):
        (self.plugin / "manifest.json").write_text(json.dumps(self.manifest))
        (self.plugin / "Main.qml").write_text(self.source)
        return lint.lint(self.root, changes=changes)

    def has_error(self, text):
        self.assertTrue(any(text in error for error in self.errors()), text)

    def text_argument(self):
        return {"name": "message", "label": "Message", "type": "text", "default": "hello"}

    def test_valid_action(self):
        self.assertEqual(self.errors(), [])

    def test_unknown_key(self):
        self.action["unknown"] = True
        self.has_error("unknown action key")

    def test_bad_id(self):
        self.action["id"] = "Bad"
        self.has_error("invalid action id")

    def test_missing_icon(self):
        self.action["icon"] = "this-icon-does-not-exist"
        self.has_error("missing icon")

    def test_no_main(self):
        self.manifest["entryPoints"] = {}
        self.has_error("require entryPoints.main")

    def test_unknown_target(self):
        self.action["command"] = "atmosphera ipc plugin:missing show"
        self.has_error("unknown IPC target")

    def test_unknown_function(self):
        self.action["command"] = "atmosphera ipc plugin:example missing"
        self.has_error("unknown IPC function")

    def test_arity(self):
        self.action["arguments"] = [self.text_argument()]
        self.has_error("arity mismatch")

    def test_bool_parameter(self):
        self.action["arguments"] = [self.text_argument()]
        self.source = self.source.replace("function show()", "function show(flag: bool)")
        self.has_error("unsupported IPC parameter type")

    def test_number_parameter(self):
        self.action["arguments"] = [{"name": "seconds", "label": "Seconds", "type": "number", "default": 900, "min": 1}]
        for parameter in ("seconds: int", "seconds: string"):
            self.source = f'import QtQuick\nimport Quickshell.Io\nItem {{ IpcHandler {{ target: "plugin:example"; function show({parameter}) {{}} }} }}\n'
            self.assertEqual(self.errors(), [])

    def test_untyped_parameter(self):
        for argument in (self.text_argument(), {"name": "seconds", "label": "Seconds", "type": "number", "default": 900}):
            for annotation in ("", ": var"):
                with self.subTest(argument=argument["type"], annotation=annotation):
                    self.action["arguments"] = [argument]
                    self.source = f'import QtQuick\nimport Quickshell.Io\nItem {{ IpcHandler {{ target: "plugin:example"; function show(value{annotation}) {{}} }} }}\n'
                    self.has_error("unsupported IPC parameter type")

    def test_parameter_limit(self):
        for count in (10, 11):
            with self.subTest(count=count):
                self.action["arguments"] = [dict(self.text_argument(), name=f"arg{i}") for i in range(count)]
                params = ", ".join(f"arg{i}: string" for i in range(count))
                self.source = f'import QtQuick\nimport Quickshell.Io\nItem {{ IpcHandler {{ target: "plugin:example"; function show({params}) {{}} }} }}\n'
                if count > 10:
                    self.has_error("at most 10 IPC parameters")
                else:
                    self.assertEqual(self.errors(), [])

    def test_unsupported_return_type(self):
        self.source = self.source.replace("function show()", "function show(): date")
        self.has_error("unsupported IPC return type")

    def test_supported_return_types(self):
        original = self.source
        for annotation in ("", ": void", ": var", ": string", ": int", ": bool", ": real", ": color"):
            with self.subTest(annotation=annotation):
                self.source = original.replace("function show()", "function show()" + annotation)
                self.assertEqual(self.errors(), [])

    def test_duplicate_id(self):
        self.manifest["actions"].append(dict(self.action))
        self.has_error("duplicate action id")

    def test_duplicate_core_command(self):
        self.action["command"] = "atmosphera ipc controlCenter toggle"
        self.source = self.source.replace("plugin:example", "controlCenter").replace("function show()", "function toggle()")
        self.has_error("duplicate composed command")

    def test_choice_default(self):
        self.action["arguments"] = [{"name": "mode", "label": "Mode", "type": "choice", "default": "other",
                                     "choices": [{"value": "region", "label": "Region"}]}]
        self.has_error("invalid default")

    def test_number_range(self):
        self.action["arguments"] = [{"name": "seconds", "label": "Seconds", "type": "number", "default": 0, "min": 1}]
        self.has_error("invalid default")

    def test_actions_not_a_list(self):
        self.manifest["actions"] = {}
        self.has_error("actions must be a list")

    def test_import_minimum(self):
        self.source = "import qs.Services.Actions as Actions\n" + self.source
        self.manifest["minAtmospheraVersion"] = "0.9.3"
        self.has_error("qs.Services.Actions requires")
        self.manifest["minAtmospheraVersion"] = "0.9.4"
        self.has_error("qs.Services.Actions requires")
        self.manifest["minAtmospheraVersion"] = "0.10.0"
        self.assertEqual(self.errors(), [])

    def test_commented_import_does_not_require_minimum(self):
        self.source = "// import qs.Services.Actions\n" + self.source
        self.manifest["minAtmospheraVersion"] = "0.9.3"
        self.assertEqual(self.errors(), [])

    def test_semicolon_actions_import_requires_release(self):
        self.source = 'import qs.Services.Actions;\n' + self.source
        self.manifest['minAtmospheraVersion'] = '0.9.3'
        self.has_error('requires minAtmospheraVersion >= 0.10.0')
        self.manifest['minAtmospheraVersion'] = '0.10.0'
        self.assertEqual(self.errors(), [])

    def test_huge_numeric_default_is_rejected_without_overflow(self):
        self.source = self.source.replace('function show()', 'function show(value: string)')
        self.action['arguments'] = [dict(name='value', label='Value', type='number', default=10 ** 310)]
        self.has_error('invalid default')

    def test_unchanged_manifest_is_still_audited(self):
        self.action["id"] = "Bad"
        self.assertTrue(any("invalid action id" in error for error in
                            self.errors({"checked_plugins": [], "previous_versions": {}})))

    def test_scanner_ignores_comments_strings_and_nested_functions(self):
        self.source = '''import QtQuick
import Quickshell.Io
Item {
  // IpcHandler { target: "comment-only"; function show() {} }
  property string fake: 'IpcHandler { target: "string-only"; function show() {} }'
  IpcHandler {
    target: "plugin:example"
    function show(): string {
      function nested(flag: bool) {}
      return "}";
    }
  }
}
'''
        self.assertEqual(self.errors(), [])
        self.action["command"] = "atmosphera ipc plugin:example nested"
        self.has_error("unknown IPC function")
        for target in ("comment-only", "string-only"):
            self.action["command"] = f"atmosphera ipc {target} show"
            self.has_error("unknown IPC target")


class IndexRegression(unittest.TestCase):
    def snapshot(self, root):
        tree = subprocess.check_output(["git", "-C", str(root), "write-tree"], text=True, timeout=30).strip()
        archive = root / "snapshot.tar"
        with archive.open("wb") as output:
            subprocess.run(["git", "-C", str(root), "archive", tree, "--", "example"], stdout=output, check=True, timeout=30)
        snapshot = root / "snapshot"
        snapshot.mkdir(exist_ok=True)
        with tarfile.open(archive) as source:
            source.extractall(snapshot, filter="data")
        return snapshot

    def test_partial_staging_and_sensitive_file_exclusion(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            subprocess.run(["git", "init", "-q", str(root)], check=True, timeout=30)
            plugin = root / "example"
            plugin.mkdir()
            manifest = {"id": "example", "version": "1.0.0"}
            (plugin / "manifest.json").write_text(json.dumps(manifest))
            file = plugin / "file with spaces.qml"
            file.write_text("AtmoIconButton {}\n")
            (root / ".envrc").write_text("PRIVATE_TEST_VALUE=do-not-transfer\n")
            subprocess.run(["git", "-C", str(root), "add", "--", "example", ".envrc"], check=True, timeout=30)
            file.write_text("NIconButton {}\n")
            snapshot = self.snapshot(root)
            self.assertEqual((snapshot / "example/file with spaces.qml").read_bytes(), b"AtmoIconButton {}\n")
            self.assertFalse((snapshot / ".envrc").exists())
            self.assertEqual(lint.changes_from_snapshot(snapshot, root / "empty")["checked_plugins"], ["example"])

    def test_checker_accepts_good_index_and_rejects_retired_widget(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            subprocess.run(["git", "init", "-q", str(root)], check=True, timeout=30)
            plugin = root / "example"
            plugin.mkdir()
            (plugin / "manifest.json").write_text(json.dumps({"id": "example", "version": "1.0.0",
                "minAtmospheraVersion": "0.8.0", "entryPoints": {"barWidget": "Bar.qml"}}))
            for widget, expected in (("AtmoIconButton", 0), ("NIconButton", 1)):
                (plugin / "Bar.qml").write_text(f"import QtQuick\nimport qs.Widgets\n{widget} {{}}\n")
                subprocess.run(["git", "-C", str(root), "add", "--", "example"], check=True, timeout=30)
                snapshot = self.snapshot(root)
                result = subprocess.run([sys.executable, "-B", str(CHECKER), "--root", str(snapshot)],
                                        capture_output=True, timeout=30)
                self.assertEqual(result.returncode, expected, result.stdout.decode() + result.stderr.decode())
                if expected:
                    self.assertIn(b"retired widget NIconButton", result.stdout)

    def test_snapshot_version_bump_and_documentation_only_change(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            current, base = root / "current", root / "base"
            for directory in (current, base):
                (directory / "example").mkdir(parents=True)
                (directory / "example/manifest.json").write_text('{"id":"example","version":"1.0.0"}')
                (directory / "example/file with spaces.qml").write_text("import QtQuick\nItem {}\n")
            (current / "example/README.md").write_text("documentation only")
            self.assertEqual(lint.changes_from_snapshot(current, base)["checked_plugins"], [])
            (current / "example/file with spaces.qml").write_text("import QtQuick\nItem { visible: false }\n")
            self.assertTrue(any("version bump" in e for e in lint.lint(current, changes=lint.changes_from_snapshot(current, base))))


if __name__ == "__main__":
    unittest.main(argv=[__file__, *remaining])
