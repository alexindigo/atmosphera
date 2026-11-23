#!/usr/bin/env python3
"""Import-scoped discovery controls. Execute in the assigned VM or CI."""
import tempfile
import unittest
from pathlib import Path
import importlib.util
from unittest import mock

from image_decoding_sources import discover, scan


class ScopeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='image-source-scope-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def write(self, name, body):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body)

    def usages(self, rows, path):
        return [row for row in rows if row['path'] == path]

    def test_directory_collision_does_not_hide_imported_image(self):
        self.write('example/a/Preview.qml', 'import QtQuick\nImage {}')
        self.write('example/z/Preview.qml', 'import QtQuick\nItem {}')
        self.write('example/Main.qml', 'import QtQuick\nimport "a"\nPreview { source: path }')
        rows, _ = scan(self.root, 'plugins')
        self.assertEqual([r['rule'] for r in self.usages(rows, 'example/Main.qml')], ['native-image'])

    def test_alias_selects_its_directory_not_an_unrelated_type(self):
        self.write('example/a/Preview.qml', 'import QtQuick\nImage {}')
        self.write('example/z/Preview.qml', 'import QtQuick\nItem {}')
        self.write('example/Main.qml', 'import QtQuick\nimport "a" as Pixels\nimport "z" as Plain\n'
                   'Item { Pixels.Preview { source: path } Plain.Preview {} }')
        rows, _ = scan(self.root, 'plugins')
        uses = self.usages(rows, 'example/Main.qml')
        self.assertEqual(len(uses), 1, uses)
        self.assertEqual(uses[0]['rule'], 'native-image')
        self.assertEqual(uses[0]['bindings']['source'], 'path')

    def test_unimported_image_does_not_taint_plain_wrapper(self):
        self.write('example/a/Preview.qml', 'import QtQuick\nItem {}')
        self.write('example/z/Preview.qml', 'import QtQuick\nImage {}')
        self.write('example/Main.qml', 'import QtQuick\nimport "a"\nPreview {}')
        rows, _ = scan(self.root, 'plugins')
        self.assertEqual(self.usages(rows, 'example/Main.qml'), [])

    def test_inventory_keeps_inherited_usage_and_source_binding(self):
        self.write('example/Pic.qml', 'import QtQuick\nImage {}')
        self.write('example/Main.qml', 'import QtQuick\nPic { id: supplied; source: externalPath }')
        uses = self.usages(discover(self.root, 'plugins'), 'example/Main.qml')
        self.assertEqual(len(uses), 1, uses)
        self.assertEqual(uses[0]['node'], 'Pic')
        self.assertEqual(uses[0]['bindings']['source'], 'externalPath')

    def test_shell_module_alias_is_resolved_only_through_its_import(self):
        self.write('shell/Widgets/Preview.qml', 'import QtQuick\nImage {}')
        self.write('shell/Commons/Preview.qml', 'import QtQuick\nItem {}')
        _, shell = scan(self.root / 'shell', 'shell')
        self.write('plugins/example/Main.qml', 'import QtQuick\nimport qs.Widgets as W\n'
                   'import qs.Commons as C\nItem { W.Preview { source: path } C.Preview {} }')
        rows, _ = scan(self.root / 'plugins', 'plugins', shell)
        self.assertEqual(len(self.usages(rows, 'example/Main.qml')), 1, rows)

    def test_qmldir_public_name_and_private_implicit_sibling(self):
        self.write('example/a/qmldir', 'PublicPreview 1.0 PrivatePreview.qml\n')
        self.write('example/a/PrivatePreview.qml', 'import QtQuick\nImage {}')
        self.write('example/a/Inside.qml', 'import QtQuick\nPrivatePreview { source: inside }')
        self.write('example/Main.qml', 'import QtQuick\nimport "a"\n'
                   'Item { PublicPreview { source: outside } PrivatePreview {} }')
        rows, _ = scan(self.root, 'plugins')
        self.assertEqual(len(self.usages(rows, 'example/Main.qml')), 1, rows)
        self.assertEqual(len(self.usages(rows, 'example/a/Inside.qml')), 1, rows)

    def test_inheritance_resolves_each_parent_in_its_own_file_scope(self):
        self.write('example/a/Pic.qml', 'import QtQuick\nImage {}')
        self.write('example/b/Preview.qml', 'import "../a" as A\nA.Pic {}')
        self.write('example/Main.qml', 'import "b"\nPreview { source: externalPath }')
        rows, _ = scan(self.root, 'plugins')
        self.assertEqual(len(self.usages(rows, 'example/Main.qml')), 1, rows)

    def test_inline_component_scope(self):
        self.write('example/Main.qml', 'import QtQuick\nItem { component Pic: Image {} Pic { source: path } }')
        rows, _ = scan(self.root, 'plugins')
        self.assertEqual(len(self.usages(rows, 'example/Main.qml')), 2, rows)

    def test_renderer_named_lookalike_cannot_hide_a_native_wrapper(self):
        self.write('example/NImage.qml', 'import QtQuick\nImage {}')
        self.write('example/Main.qml', 'import QtQuick\nNImage { source: path }')
        rows, _ = scan(self.root, 'plugins')
        self.assertEqual(len(self.usages(rows, 'example/Main.qml')), 1, rows)

    def test_plain_text_wrapper_does_not_expand_the_image_inventory(self):
        self.write('Widgets/NText.qml', 'import QtQuick\nText { property bool richTextEnabled: false; textFormat: Text.PlainText }')
        self.write('Modules/Main.qml', 'import qs.Widgets\nNText { text: "plain" }')
        self.assertEqual(self.usages(discover(self.root, 'shell'), 'Modules/Main.qml'), [])

    def test_hidden_wrapper_control_cannot_pass_on_the_definition_alone(self):
        spec = importlib.util.spec_from_file_location('boundary', Path(__file__).with_name('image-decoding-boundary-check.py'))
        boundary = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(boundary)
        shell, plugins = self.root / 'shell', self.root / 'plugins'
        shell.mkdir()
        plugins.mkdir()
        _, shell_types = scan(shell, 'shell')
        def without_usage(*args):
            rows, types = scan(*args)
            return [r for r in rows if not r['path'].endswith('/UsePic.qml')], types
        with mock.patch.object(boundary, 'scan', without_usage):
            results = boundary.selftest([], {'sites': []}, dict(shell=shell, plugins=plugins), shell_types)
        self.assertFalse(next(r['passed'] for r in results if r['control'] == 'hidden-wrapper'))


if __name__ == '__main__':
    unittest.main()
