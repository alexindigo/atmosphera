#!/usr/bin/env python3
"""Import-scoped discovery controls. Execute in the assigned VM or CI."""
import tempfile
import unittest
from pathlib import Path
import importlib.util
from unittest import mock

from image_decoding_sources import discover, scan


def boundary_module():
    spec = importlib.util.spec_from_file_location('boundary', Path(__file__).with_name('image-decoding-boundary-check.py'))
    boundary = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(boundary)
    return boundary


def inventory_module():
    spec = importlib.util.spec_from_file_location('inventory', Path(__file__).with_name('image-decoding-inventory.py'))
    inventory = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(inventory)
    return inventory


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

    def test_inventory_resolves_plugin_usages_of_shell_wrappers(self):
        self.write('shell/Widgets/Preview.qml', 'import QtQuick\nNImageRounded {}')
        _, shell_types = scan(self.root / 'shell', 'shell')
        self.write('plugins/example/Main.qml', 'import qs.Widgets as W\nW.Preview { source: path }')
        rows = discover(self.root / 'plugins', 'plugins', shell_types)
        uses = self.usages(rows, 'example/Main.qml')
        self.assertEqual(len(uses), 1, uses)
        self.assertEqual(uses[0]['node'], 'W.Preview')
        self.assertIn('NImageRounded', uses[0]['inheritedFrom'])

    def test_hidden_wrapper_control_cannot_pass_on_the_definition_alone(self):
        boundary = boundary_module()
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

    def test_shell_only_control_requires_the_shell_only_check(self):
        boundary = boundary_module()
        shell, plugins = self.root / 'shell', self.root / 'plugins'
        shell.mkdir()
        plugins.mkdir()
        _, shell_types = scan(shell, 'shell')
        with mock.patch.object(boundary, 'SHELL_ONLY', set()):
            results = boundary.selftest([], {'sites': []}, dict(shell=shell, plugins=plugins), shell_types)
        self.assertFalse(next(r['passed'] for r in results if r['control'] == 'plugin-claims-shell-disposition'))

    def test_fixed_asset_needs_its_source_selection_code(self):
        boundary = boundary_module()
        self.write('example/Logo.qml', 'import QtQuick\nImage { source: "assets/logo.png" }')
        (self.root / 'example/assets').mkdir()
        (self.root / 'example/assets/logo.png').write_bytes(boundary.PNG)
        sites, _ = scan(self.root, 'plugins')
        entry = {key: sites[0][key] for key in boundary.IDENTITY}
        entry.update(disposition='fixed-asset', reason='control logo', assets=[dict(
            path='example/assets/logo.png', sha256=boundary.hashlib.sha256(boundary.PNG).hexdigest())])
        failures = boundary.check(sites, {'sites': [entry]}, dict(plugins=self.root))
        self.assertTrue(any(f['problem'] == 'asset exemption without pinned source-selection file' for f in failures), failures)

    def test_deleted_baseline_owner_does_not_count_as_current_adoption(self):
        boundary = boundary_module()
        row = dict(repository='plugins', path='example/Main.qml', node='NImageRounded',
                   nodeSha256='old-node', key='old-key', disposition='inherited-owner-pending')
        result = boundary.reconcile([], dict(sites=[], baseline={'sites': [row]}, researchRows=[]))
        self.assertEqual(result['baseline'], {'replaced-or-removed': 1})

    def test_reconciliation_requires_exact_current_owner_evidence(self):
        boundary = boundary_module()
        row = dict(repository='plugins', path='example/Main.qml', node='NImageRounded',
                   nodeSha256='old-node', key='old-key', disposition='inherited-owner-pending')
        manifest = dict(sites=[], baseline={'sites': [row]}, researchRows=[])
        self.assertEqual(boundary.reconcile([], manifest, [row])['baseline'], {'owner-renderer': 1})
        native_lookalike = dict(row, inheritedFrom=['Image'])
        self.assertEqual(boundary.reconcile([], manifest, [native_lookalike])['baseline'], {'replaced-or-removed': 1})

    def test_audited_history_is_identified_independently_of_row_order(self):
        inventory = inventory_module()
        pdf = dict(repository='shell', revision='old', file='Pdf.qml', context='PdfPageImage {}')
        text = dict(repository='shell', revision='old', file='History.qml', context='property int format: Text.RichText')
        other = dict(repository='shell', revision='old', file='Other.qml', context='Image {}')
        audits = {inventory.research_identity(pdf): 'pdf', inventory.research_identity(text): 'notification-format'}
        with mock.patch.object(inventory, 'AUDITED_RESEARCH', audits):
            self.assertEqual(inventory.audited_positions([pdf, text, other]), {0: 'pdf', 1: 'notification-format'})
            self.assertEqual(inventory.audited_positions([other, pdf, text]), {1: 'pdf', 2: 'notification-format'})
            for bad in ([pdf, other], [pdf, pdf, text], [dict(pdf, context='changed'), text]):
                with self.assertRaisesRegex(ValueError, 'exactly once'):
                    inventory.audited_positions(bad)

    def test_inventory_source_identity_follows_actual_bytes(self):
        inventory = inventory_module()
        self.write('Main.qml', 'import QtQuick\nImage { source: "one.png" }')
        first = inventory.source_identity(self.root)
        self.assertIsNone(first['revision'])
        self.write('Main.qml', 'import QtQuick\nImage { source: "two.png" }')
        second = inventory.source_identity(self.root)
        self.assertNotEqual(first['contentSha256'], second['contentSha256'])
        self.assertEqual(first['entries'], second['entries'])


if __name__ == '__main__':
    unittest.main()
