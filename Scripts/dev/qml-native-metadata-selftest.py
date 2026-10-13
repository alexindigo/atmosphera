#!/usr/bin/env python3
"""Semantic ownership regressions; run in the assigned development VM."""
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('native_metadata', Path(__file__).with_name('qml-native-metadata.py'))
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


class OwnershipTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='native-metadata-selftest-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'Quickshell'
        self.root.mkdir()

    def write(self, name, components):
        path = self.root / name / 'types.qmltypes'
        path.parent.mkdir(parents=True)
        path.write_text('import QtQuick.tooling 1.2\nModule {\n' + components + '\n}\n')
        return path

    def resolve(self, **kwargs):
        return metadata.resolve(self.root, externals={'QObject', 'int'}, **kwargs)

    def test_recursive_native_contract_and_foreign_export_ownership(self):
        self.write('Core', '''
Component { file: "box.hpp"; name: "Box"; accessSemantics: "value";
    exports: ["Quickshell/Box 0.0"]
    Property { name: "width"; type: "int" }
}
Component { file: "anchor.hpp"; name: "Anchor"; prototype: "QObject"
    Property { name: "rect"; type: "Box" }
}''')
        window = self.write('Window', '''
Component { name: "Anchor"; isTypeOpaque: true }
Component { file: "window.hpp"; name: "Window"; prototype: "QObject"
    Property { name: "anchor"; type: "Anchor" }
}''')
        corrected, provenance = self.resolve()
        nodes = metadata.parse(corrected[window.relative_to(self.root)]).children
        box = next(c for c in nodes if c.values['name'] == 'Box')
        self.assertEqual(box.children[0].values['name'], 'width')
        self.assertNotIn('exports', box.values)
        self.assertEqual(set(provenance['Window/types.qmltypes']), {'Anchor', 'Box'})

    def test_unknown_reference_fails_even_without_an_opaque_placeholder(self):
        self.write('Core', 'Component { file: "a.hpp"; name: "A"; Property { name: "child"; type: "Missing" } }')
        with self.assertRaisesRegex(metadata.MetadataError, 'unresolved native reference Missing'):
            self.resolve()

    def test_public_qml_spelling_is_not_a_cpp_owner(self):
        self.write('Core', '''Component { file: "other.hpp"; name: "OtherNativeClass"; exports: ["Quickshell/MissingNativeClass 0.0"] }
Component { name: "MissingNativeClass"; isTypeOpaque: true }''')
        with self.assertRaisesRegex(metadata.MetadataError, 'MissingNativeClass'):
            self.resolve()

    def test_container_element_and_namespace_local_enum_are_closed(self):
        self.write('Core', '''Component { file: "item.hpp"; name: "ns::Item"; prototype: "QObject";
Enum { name: "State"; alias: "States"; values: ["Ready"] }
Property { name: "state"; type: "Item::States" }
}
Component { name: "QList<ns::Item*>"; isTypeOpaque: true }''')
        self.resolve()

    def test_nonexistent_enum_is_not_accepted_as_a_class_reference(self):
        self.write('Core', '''Component { file: "item.hpp"; name: "ns::Item"; Property { name: "bad"; type: "ns::Item::Missing" } }''')
        with self.assertRaisesRegex(metadata.MetadataError, 'unresolved native reference'):
            self.resolve()

    def test_ambiguous_namespace_local_ownership_fails(self):
        self.write('Core', '''Component { file: "one.hpp"; name: "one::Item" }
Component { file: "two.hpp"; name: "two::Item" }
Component { file: "user.hpp"; name: "User"; Property { name: "child"; type: "Item" } }''')
        with self.assertRaisesRegex(metadata.MetadataError, 'ambiguous native owner'):
            self.resolve()

    def test_identical_file_backed_contracts_coalesce(self):
        self.write('Core', 'Component { file: "a.hpp"; name: "A"; isTypeOpaque: true; Property { name: "value"; type: "int" } }')
        self.write('Linked', 'Component { file: "a.hpp"; name: "A"; Property { name: "value"; type: "int" } }')
        self.resolve()

    def test_conflicting_concrete_contracts_fail(self):
        self.write('Core', 'Component { file: "a.hpp"; name: "A"; Property { name: "one"; type: "int" } }')
        self.write('Linked', 'Component { file: "a.hpp"; name: "A"; Property { name: "two"; type: "int" } }')
        with self.assertRaisesRegex(metadata.MetadataError, 'ambiguous native owner'):
            self.resolve()

    def test_external_and_source_declared_terminals_require_ownership(self):
        self.write('Core', 'Component { file: "a.hpp"; name: "A"; prototype: "QObject"; Property { name: "payload"; type: "OpaquePayload" } }')
        self.resolve(terminals={'OpaquePayload': {'header': 'payload.hpp', 'sha256': 'source-proof'}})
        with self.assertRaisesRegex(metadata.MetadataError, 'OpaquePayload'):
            self.resolve()

    def test_family_integrity_and_toolchain_fail_closed(self):
        installed = Path(self.temp.name) / 'sdk/lib/qt6/qml/Quickshell'
        installed.mkdir(parents=True)
        (installed / 'original.qmltypes').write_text('installed contract')
        qt = installed.parent.parent / 'metatypes'
        qt.mkdir()
        (qt / 'qt_metatypes.json').write_text('matching SDK')
        families = Path(self.temp.name) / 'families'
        family = families / 'supported'
        (family / 'Quickshell').mkdir(parents=True)
        (family / 'Quickshell/types.qmltypes').write_text('generated contract')
        (family / 'owners.qmltypes').write_text('owner contract')
        (family / 'terminals.json').write_text('{}')
        digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
        manifest = {'installed_qmltypes': {'original.qmltypes': digest(installed / 'original.qmltypes')},
                    'qt_metatypes': {'qt_metatypes.json': digest(qt / 'qt_metatypes.json')},
                    'required_qt_metatypes': {'qt_metatypes.json': digest(qt / 'qt_metatypes.json')},
                    'artifacts': {p.relative_to(family).as_posix(): digest(p)
                                  for p in family.rglob('*') if p.is_file()}}
        (family / 'manifest.json').write_text(json.dumps(manifest))
        self.assertEqual(metadata.input_family(installed, families), family)
        (qt / 'qt_metatypes.json').write_text('different SDK')
        with self.assertRaisesRegex(metadata.MetadataError, 'Qt toolchain mismatch'):
            metadata.input_family(installed, families)
        (qt / 'qt_metatypes.json').write_text('matching SDK')
        (qt / 'unrelated_metatypes.json').write_text('optional SDK package')
        self.assertEqual(metadata.input_family(installed, families), family)
        (family / 'Quickshell/unbound.qmltypes').write_text('unexpected owner')
        with self.assertRaisesRegex(metadata.MetadataError, 'inventory mismatch'):
            metadata.input_family(installed, families)
        (family / 'Quickshell/unbound.qmltypes').unlink()
        (family / 'owners.qmltypes').write_text('altered contract')
        with self.assertRaisesRegex(metadata.MetadataError, 'integrity mismatch'):
            metadata.input_family(installed, families)

    def test_ordinary_native_lint_preserves_positive_and_negative_contracts(self):
        repo = Path(__file__).resolve().parents[2]
        shutil.copyfile(repo / '.qmllint.ini', Path(self.temp.name) / '.qmllint.ini')
        cases = {
            'valid': ('import QtQuick\nimport Quickshell\nPanelWindow { margins.top: 7; '
                      'Item { id: target } PopupWindow { anchor.item: target; anchor.rect.width: 9 } }',
                      0, 'qmllint: clean'),
            'missing-property': ('import Quickshell\nPanelWindow { margins.notARealEdge: 7 }',
                                 1, 'Could not find property "notARealEdge"'),
            'ineffective-expression': ('import QtQuick\nItem { property int n: 0; function ineffective() { n; } }',
                                      1, '[confusing-expression-statement]'),
        }
        for name, (source, status, diagnostic) in cases.items():
            with self.subTest(name=name):
                fixture = Path(self.temp.name) / (name + '.qml')
                fixture.write_text(source + '\n')
                result = subprocess.run(['timeout', '90s', str(repo / 'Scripts/dev/qmllint.sh'), str(fixture)],
                                        cwd=repo, capture_output=True, text=True, timeout=100,
                                        env=dict(os.environ, TMPDIR=self.temp.name))
                output = result.stdout + result.stderr
                print(f'native lint {name}: exit {result.returncode}; expected {status}', flush=True)
                self.assertEqual(result.returncode, status, output)
                self.assertIn(diagnostic, output)
                self.assertNotIn('[unresolved-type]', output)

    def test_qt_input_ownership_follows_full_generated_contract(self):
        self.write('Core', '''Component { file: "native.hpp"; name: "Native";
Property { name: "items"; type: "QList<QtOwner*>" }
Property { name: "state"; type: "QtOwner::State" } }''')
        supplemental = Path(self.temp.name) / 'owners.qmltypes'
        supplemental.write_text('import QtQuick.tooling 1.2\nModule { Component { name: "Linked"; prototype: "OtherQtOwner" } }')
        qt = Path(self.temp.name) / 'metatypes'
        qt.mkdir()
        for file, owner in [('used', 'QtOwner'), ('linked', 'OtherQtOwner'), ('optional', 'UnrelatedQtOwner')]:
            (qt / (file + '_metatypes.json')).write_text(json.dumps([{'classes': [{'qualifiedClassName': owner}]}]))
        self.assertEqual(set(metadata.qt_contract_inputs(self.root, supplemental, qt)),
                         {'used_metatypes.json', 'linked_metatypes.json'})


if __name__ == '__main__':
    unittest.main()
