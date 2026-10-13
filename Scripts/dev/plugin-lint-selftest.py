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
