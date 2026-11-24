#!/usr/bin/env python3
"""Page-usage admission is finite and separate from native value admission.

Run inside the assigned project VM, with its disk-backed TMPDIR.
"""
import copy
import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('plugin_schema', ROOT / 'Scripts/python/src/settings/plugin-schema.py')
schema = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(schema)


class PageMetadata(unittest.TestCase):
    def setUp(self):
        self.manifest = dict(id='fixture', version='1.2.3', metadata=dict(
            defaultSettings=dict(enabled=False, token='', tasks=[], result=0),
            settingsSchema=dict(version=1, fields=dict(
                enabled=dict(type='Boolean', editorUsage='configuration'),
                token=dict(type='String', sensitive=True, machineLocal=True, editorUsage='configuration'),
                tasks=dict(type='List', element=dict(type='String'), machineLocal=True, editorUsage='content'),
                result=dict(type='Real', editorUsage='operational')))))
        self.overlays = dict(version=1, plugins={})

    def test_explicit_usage_including_machine_local_credentials(self):
        metadata = schema.editor_metadata(self.manifest, self.overlays)
        self.assertTrue(metadata['ready'])
        self.assertEqual(metadata['fields']['token'], dict(usage='configuration', sensitive=True))
        self.assertEqual(metadata['fields']['tasks']['usage'], 'content')
        self.assertEqual(metadata['fields']['result']['usage'], 'operational')

    def test_annotation_does_not_change_native_schema(self):
        annotated, _ = schema.compile_schema(self.manifest, self.overlays)
        plain = copy.deepcopy(self.manifest)
        for field in plain['metadata']['settingsSchema']['fields'].values():
            del field['editorUsage']
        native, _ = schema.compile_schema(plain, self.overlays)
        self.assertEqual(annotated, native)
        self.assertNotIn('editorUsage', native)

    def test_incomplete_or_invalid_metadata_does_not_disable_runtime(self):
        for value, code in ((None, 'settings-editor-usage-missing'), ('preference', 'settings-editor-usage-invalid')):
            candidate = copy.deepcopy(self.manifest)
            if value is None:
                del candidate['metadata']['settingsSchema']['fields']['token']['editorUsage']
            else:
                candidate['metadata']['settingsSchema']['fields']['token']['editorUsage'] = value
            schema.compile_schema(candidate, self.overlays)
            metadata = schema.editor_metadata(candidate, self.overlays)
            self.assertFalse(metadata['ready'])
            self.assertEqual(metadata['error'], code)
            self.assertEqual(metadata['fields'], {})

    def test_reviewed_exact_version_adds_only_missing_annotations(self):
        authored = self.manifest['metadata']['settingsSchema']['fields']
        del authored['enabled']['editorUsage']
        compatibility = dict(version=1, fields=dict(
            enabled=dict(type='String', editorUsage='configuration'),
            token=dict(type='Real', editorUsage='content'),
            invented=dict(type='String', editorUsage='configuration')))
        self.overlays['plugins'] = {'fixture': {'1.2.3': compatibility}}
        metadata = schema.editor_metadata(self.manifest, self.overlays)
        self.assertTrue(metadata['ready'])
        self.assertNotIn('invented', metadata['fields'])
        self.assertEqual(metadata['fields']['token']['usage'], 'configuration')
        defaults, fields, origin = schema.described(self.manifest, self.overlays)
        self.assertIs(defaults['enabled'], False)
        self.assertEqual(fields['enabled']['type'], 'Boolean')
        self.assertTrue(fields['token']['sensitive'])
        self.assertEqual(origin, 'manifest')
        self.manifest['version'] = '1.2.4'
        self.assertFalse(schema.editor_metadata(self.manifest, self.overlays)['ready'])

    def test_authored_invalid_annotation_cannot_fall_back(self):
        self.manifest['metadata']['settingsSchema']['fields']['enabled']['editorUsage'] = 'bad'
        self.overlays['plugins'] = {'fixture': {'1.2.3': dict(version=1, fields=dict(
            enabled=dict(type='Boolean', editorUsage='configuration')))}}
        self.assertEqual(schema.editor_metadata(self.manifest, self.overlays)['error'], 'settings-editor-usage-invalid')

    def test_sensitive_atomic_record_descendant_is_not_exposed_in_summary(self):
        self.manifest['metadata']['defaultSettings']['connection'] = dict(secret='')
        self.manifest['metadata']['settingsSchema']['fields']['connection'] = dict(
            type='Record', editorUsage='configuration', fields=dict(secret=dict(type='String', sensitive=True)))
        self.assertTrue(schema.editor_metadata(self.manifest, self.overlays)['fields']['connection']['sensitive'])

    def test_empty_informational_page_is_ready_without_invented_fields(self):
        self.manifest['metadata'] = dict(defaultSettings={}, settingsSchema=dict(version=1, fields={}))
        self.assertEqual(schema.editor_metadata(self.manifest, self.overlays), dict(ready=True, error='', fields={}))


if __name__ == '__main__':
    unittest.main()
