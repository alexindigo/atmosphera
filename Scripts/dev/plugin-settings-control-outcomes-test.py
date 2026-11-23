#!/usr/bin/env python3
"""Exercise complete driver result boundaries, without starting an engine."""
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


def load(name):
    path = Path(__file__).with_name('plugin-settings-' + name + '-regression.py')
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


AUTOMATIC = load('automatic-lifecycle')
DEVICE = load('device-lifecycle')
RESOURCE = load('resource-native')


class OutcomeTests(unittest.TestCase):
    def exercise(self, driver, control, outcome):
        with tempfile.TemporaryDirectory(prefix='control-outcomes-') as temporary:
            root = Path(temporary)
            source, plugins = root/'source', root/'plugins'
            source.mkdir(); plugins.mkdir()
            (source/'unrelated.txt').write_text('immutable source input')
            for member in ('2-in-1-tools', 'usb-drive-manager', 'agent-session-status', 'clamshell'):
                product = plugins/member
                product.mkdir()
                (product/'Main.qml').write_text(
                    'root._requestHyprTouchTransformSync(outputName, root._applyTarget, policy)\n'
                    'if (admitted.showNotifications)\n')
                (product/'BarWidget.qml').write_text('toggle(pluginApi)\n')
                (product/'manifest.json').write_text(json.dumps(dict(metadata=dict(defaultSettings={}))))
            args = SimpleNamespace(source=source, plugins=plugins, work_root=root/'work',
                                   output=root/'output', control=control, original_plugins=None,
                                   plugin='clamshell', omit_origin=False, wrong_writer=bool(control))
            args.work_root.mkdir(); args.output.mkdir()
            resource = driver is RESOURCE
            scenario = 'instance' if resource else 'apply' if driver is AUTOMATIC else 'usb-mount'
            wanted = ('complete resource native documents' if resource else
                      'captured apply keeps touch and notification policy' if driver is AUTOMATIC else
                      'captured USB completion notification policy')

            def fixture(profile, install, case, output, fixture, **kwargs):
                if resource:
                    expected = json.loads((case/'expectations.json').read_text())
                    persisted = args.output/scenario/'persisted'
                    for boundary, values in expected.items():
                        driver.runner.write_json(persisted/(boundary+'.json'), dict(status='PASS', values=values))
                    if outcome == 'rejected':
                        wrong = deepcopy(expected['runtime-disabled'])
                        wrong['shared']['enabled'] = False
                        wrong['bar']['widgets']['left'][0]['instanceSettings'].pop('enabled', None)
                        driver.runner.write_json(case/'config/settings/plugins/clamshell.json', wrong['shared'])
                        driver.runner.write_json(case/'config/settings/bar.json', wrong['bar'])
                    mode = kwargs['extra_env']['PHA_RESOURCE_MODE']
                    boundary = kwargs['extra_env']['PHA_RESOURCE_BOUNDARY']
                    effect = boundary or {'edit': 'edited', 'reset': 'reset', 'follow': 'following'}[mode]
                    values = dict(expected[effect]['shared'])
                    values.update(expected[effect]['bar']['widgets']['left'][0]['instanceSettings'])
                    who = values.get('inhibitorWho', 'default-who')
                    (case/'requests.jsonl').write_text(json.dumps(dict(
                        endpoint='systemd-inhibit', kind='start', argv=['--who='+who],
                        pid=2147483647, start='0'))+'\n')
                    text = ('RESOURCE_NATIVE: PASS instance '+mode+' '+boundary+'\n'
                            'RESOURCE_NATIVE_CONSUMER '+json.dumps(dict(who=who, active=True)))
                else:
                    text = ('AUTOMATIC_LIFETIME' if driver is AUTOMATIC else 'DEVICE_LIFETIME') + ': PASS '+scenario
                if outcome in ('rejected', 'unrelated', 'wrong-exit'):
                    (output/'runtime.log').write_text(wanted if outcome != 'unrelated' else 'unrelated setup failure')
                    (output/'runtime.exit').write_text('1' if outcome == 'wrong-exit' else '2')
                    raise RuntimeError('controlled fixture failure')
                return text

            with patch.object(driver.runner, 'run_fixture', side_effect=fixture), \
                    patch.object(driver.runner, 'remove_completed_installs'):
                driver.run(args, None, scenario)
            return json.loads((args.output/scenario/'result.json').read_text())

    def test_automatic_control_cannot_escape(self):
        with self.assertRaisesRegex(RuntimeError, 'control escaped'):
            self.exercise(AUTOMATIC, 'apply-policy', 'passed')

    def test_device_control_cannot_escape(self):
        with self.assertRaisesRegex(RuntimeError, 'control escaped'):
            self.exercise(DEVICE, 'usb-completion', 'passed')

    def test_resource_control_cannot_escape(self):
        with self.assertRaisesRegex(RuntimeError, 'control escaped'):
            self.exercise(RESOURCE, True, 'passed')

    def test_positive_completion(self):
        for driver in (AUTOMATIC, DEVICE, RESOURCE):
            with self.subTest(driver=driver.__name__):
                self.assertEqual(self.exercise(driver, None, 'passed')['status'], 'PASS')

    def test_named_rejection(self):
        for driver, control in ((AUTOMATIC, 'apply-policy'), (DEVICE, 'usb-completion'), (RESOURCE, True)):
            with self.subTest(driver=driver.__name__):
                self.assertEqual(self.exercise(driver, control, 'rejected')['status'], 'PASS')

    def test_unrelated_failures_are_not_rejections(self):
        for driver, control in ((AUTOMATIC, 'apply-policy'), (DEVICE, 'usb-completion'), (RESOURCE, True)):
            for outcome in ('unrelated', 'wrong-exit'):
                with self.subTest(driver=driver.__name__, outcome=outcome):
                    with self.assertRaises((RuntimeError, AssertionError)):
                        self.exercise(driver, control, outcome)


if __name__ == '__main__':
    unittest.main()
