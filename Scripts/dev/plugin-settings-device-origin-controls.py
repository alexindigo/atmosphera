#!/usr/bin/env python3
"""Omitted-origin controls through actual device Settings/native consumers."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
import fcntl
import hashlib
import importlib.util
from pathlib import Path
import shutil
from types import SimpleNamespace

from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('device_native', Path(__file__).with_name('plugin-settings-device-native-regression.py'))
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'): parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve()/'Scripts/dev/plugin-settings-device-origin-controls.py': parser.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        native.runner.write_json(args.output/'inputs.json', {str(path.relative_to(args.source)): hashlib.sha256(path.read_bytes()).hexdigest() for path in (Path(__file__), args.source/'Scripts/dev/plugin-settings-device-native-regression.py', args.source/'Scripts/dev/fixtures/plugin-settings-device-native.qml', args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py')})
        mutant = args.work_root/'omitted'
        mutant.mkdir()
        mutations = (
            ('usb-drive-manager', 'Panel.qml', 'openInFileBrowser(mountpoint, root.pluginApi?.settingsContext)', 'openInFileBrowser(mountpoint)'),
            ('noctalia-supergfxctl', 'src/Main.qml', 'requestRefresh: function () { root.refresh(context); }', 'requestRefresh: function () { root.refresh(); }'),
        )
        controls = []
        for member, relative, old, new in mutations:
            shutil.copytree(args.plugins/member, mutant/member)
            path = mutant/member/relative; text = path.read_text()
            if text.count(old) != 1: raise RuntimeError('stale omitted-origin control')
            path.write_text(text.replace(old, new))
            native.run(SimpleNamespace(source=args.source, plugins=args.plugins, original_plugins=mutant, work_root=args.work_root, output=args.output), profile, member, 'instance')
            controls.append(dict(plugin=member, path=relative, before=old, after=new, rejected=True))
        stage_receipt(args.output/'result.json', dict(status='PASS', kind='omitted-origin-native-controls', controls=controls, completeGroupAcceptance=False))


if __name__ == '__main__': main()
