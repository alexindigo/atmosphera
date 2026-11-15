#!/usr/bin/env python3
"""Positive and failing canaries for the direct singleton-call gate (guest only)."""
import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location('calls', Path(__file__).with_name('qml-singleton-calls.py'))
calls = importlib.util.module_from_spec(spec)
spec.loader.exec_module(calls)


class CallsTest(unittest.TestCase):
    def test_native_metadata(self):
        members = calls.quickshell_members(Path('/usr/lib/qt6/qml'))
        self.assertIn('execDetached', members)
        self.assertNotIn('exec', members)

    def test_canaries(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            service = root / 'Services'
            service.mkdir()
            (service / 'Example.qml').write_text('pragma Singleton\nimport QtQml\nQtObject {\n'
                'function valid() {}\nproperty var callback: null\nsignal happened()\n'
                'property QtObject child: QtObject { function hidden() {} }\n}\n')
            cases = [
                ('import Quickshell\nQtObject { function f() { Quickshell.execDetached(["true"]); } }', []),
                ('import Quickshell\nQtObject { function f() { Quickshell.exec("sh"); } }', ['Quickshell.exec']),
                ('import Quickshell\nQtObject { function f() { DesktopEntries.missing(); } }', ['DesktopEntries.missing']),
                ('import Quickshell as Q\nQtObject { function f() { Q.Quickshell.exceDetached([]); } }', ['Q.Quickshell.exceDetached']),
                ('import qs.Services\nQtObject { function f() { Example.valid(); Example.callback(); Example.happened(); } }', []),
                ('import qs.Services\nQtObject { function f() { Example.missing(); Example.hidden(); } }', ['Example.missing', 'Example.hidden']),
                ('import qs.Services\nQtObject { function f() { Example.validChanged(); Example.happenedChanged(); } }', ['Example.validChanged', 'Example.happenedChanged']),
                ('import qs.Services as S\nQtObject { function f() { S.Example.missing(); } }', ['S.Example.missing']),
                ('import qs.Services\nQtObject { property string s: "Example.missing()" // Example.bad()\n }', []),
                ('import qs.Services\nQtObject { property string s: `ignore Example.bad() ${Example.missing()}` }', ['Example.missing']),
            ]
            for text, expected in cases:
                with self.subTest(text=text):
                    path = root / 'Test.qml'
                    path.write_text(text)
                    failures, _ = calls.check(root, [path], Path('/usr/lib/qt6/qml'))
                    self.assertEqual([failure.split('unknown singleton call ')[1] for failure in failures], expected)

            javascript = root / 'Test.js'
            javascript.write_text('.import Quickshell 0.1 as Q\nfunction f() { Q.Quickshell.exec("sh"); }\n')
            failures, _ = calls.check(root, [javascript], Path('/usr/lib/qt6/qml'))
            self.assertEqual([failure.split('unknown singleton call ')[1] for failure in failures], ['Q.Quickshell.exec'])
            javascript.write_text('.import qs.Services 1.0 as S\nfunction f() { S.Example.missing(); }\n')
            failures, _ = calls.check(root, [javascript], Path('/usr/lib/qt6/qml'))
            self.assertEqual([failure.split('unknown singleton call ')[1] for failure in failures], ['S.Example.missing'])


if __name__ == '__main__':
    unittest.main()
