#!/usr/bin/env python3
"""Shell-profiles raw publication witnesses. Assigned project guest only."""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('plugins', 'work-root', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    args.work_root.mkdir(parents=True, exist_ok=False)
    args.output.mkdir(parents=True, exist_ok=False)
    scripts = args.plugins/'shell-profiles/assets/scripts'
    spec = importlib.util.spec_from_file_location('profile_files', scripts/'profile-files.py')
    io = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(io)
    cases = []

    def raw(root, name, data):
        path = root/name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def seed(name):
        base = args.work_root/name
        config = base/'c'
        raw(config, 'settings.json', b'{"settingsVersion":62,"opaque":18446744073709551615}')
        raw(config, 'colors.json', b'{"mPrimary":"#123456"}')
        raw(config, 'plugins.json', b'{"plugins":{}}')
        raw(config, 'settings/bar.json', b'{"position":"bottom","opaque":18446744073709551615}')
        raw(config, 'settings/plugins/example.json', b'{"custom":18446744073709551615}')
        raw(config, 'settings/plugins/example.config.json', b'{"opaque":{"__proto__":true}}')
        return base, config

    def byteset(config):
        return {name: io.file_state(config/name)[1] for name in io.inventory(config)}

    def passed(name):
        cases.append(dict(id=name, status='PASS'))
        print(name+': PASS', flush=True)

    base, config = seed('snapshot-apply')
    expected = byteset(config)
    for operation in ('save-profile.sh', 'backup-configs.sh'):
        target = base/operation
        done = subprocess.run(['sh', str(scripts/operation), str(config), str(target),
                               '{"screens":[]}', '{"savedAt":"fixture"}'],
                              capture_output=True, text=True, timeout=15)
        assert done.returncode == 0, done.stderr
        manifest = json.loads((target/io.MANIFEST).read_bytes())
        assert manifest['format'] == 2 and set(manifest['entries']) == set(expected)
        assert byteset(target) == expected
        assert json.loads((target/'wallpapers.json').read_bytes()) == dict(screens=[])
    passed('profile-and-auto-backup-exact-family')
    raw(config, 'settings/bar.json', b'{"position":"top"}')
    raw(config, 'settings/ui.json', b'{"fontDefaultScale":1.6}')
    io.apply(base/'save-profile.sh', config, None, base/'evidence')
    assert byteset(config) == expected and not (config/'settings/ui.json').exists()
    passed('apply-restores-raw-unknown-and-sparse-absence')

    baseline = base/'baseline'
    io.snapshot(config, baseline, {})
    raw(config, 'settings/bar.json', b'{"position":"left","foreign":true}')
    competing = byteset(config)
    try:
        io.apply(base/'save-profile.sh', config, baseline, base/'evidence')
        raise AssertionError('competing writer accepted')
    except io.Refused as error:
        assert str(error) == 'profile-preimage-conflict'
    assert byteset(config) == competing
    passed('competing-writer-refused-with-preimages-retained')

    base, config = seed('copy-failure')
    profile = base/'profile'
    io.snapshot(config, profile, {})
    raw(config, 'colors.json', b'{"mPrimary":"#abcdef"}')
    raw(config, 'settings/bar.json', b'{"position":"top"}')
    before = byteset(config)
    original = io.os.replace
    calls = []
    def fail_second(source, target):
        calls.append(str(target))
        if len(calls) == 2:
            raise OSError('injected second-copy failure')
        return original(source, target)
    io.os.replace = fail_second
    try:
        try:
            io.apply(profile, config, None, base/'evidence')
            raise AssertionError('copy fault accepted')
        except OSError:
            pass
    finally:
        io.os.replace = original
    assert byteset(config) == before
    assert list((base/'evidence').glob('*/before/'+io.MANIFEST))
    passed('second-copy-failure-restores-prior-publications')

    base, config = seed('post-rename-failure')
    profile = base/'profile'
    io.snapshot(config, profile, {})
    raw(config, 'colors.json', b'{"mPrimary":"#abcdef"}')
    before = byteset(config)
    original = io.os.fsync
    injected = []
    def fail_directory(fd):
        if stat.S_ISDIR(os.fstat(fd).st_mode) and not injected:
            injected.append(True)
            raise OSError('injected directory-fsync failure after rename')
        return original(fd)
    io.os.fsync = fail_directory
    try:
        try:
            io.apply(profile, config, None, base/'evidence')
            raise AssertionError('post-rename fault accepted')
        except OSError:
            pass
    finally:
        io.os.fsync = original
    assert injected and byteset(config) == before, 'post-rename failure lost original publication bookkeeping'
    passed('post-rename-failure-restores-committed-preimage')

    base, config = seed('rollback-foreign')
    profile = base/'profile'
    io.snapshot(config, profile, {})
    raw(config, 'colors.json', b'{"mPrimary":"#abcdef"}')
    raw(config, 'settings/bar.json', b'{"position":"top"}')
    original = io.os.replace
    calls = []
    def conflict_then_fail(source, target):
        calls.append(str(target))
        if len(calls) == 2:
            Path(calls[0]).write_bytes(b'{"foreign":"after-publication"}')
            raise OSError('second-copy fault with foreign first target')
        return original(source, target)
    io.os.replace = conflict_then_fail
    try:
        try:
            io.apply(profile, config, None, base/'evidence')
            raise AssertionError('foreign rollback fault accepted')
        except OSError:
            pass
    finally:
        io.os.replace = original
    assert (config/'colors.json').read_bytes() == b'{"foreign":"after-publication"}'
    result = json.loads(next((base/'evidence').glob('*/result.json')).read_bytes())
    assert result['status'] == 'failed' and result['rollbackConflicts'] == ['colors.json']
    assert next((base/'evidence').glob('*/observed/colors.json')).read_bytes() == b'{"foreign":"after-publication"}'
    passed('rollback-never-overwrites-competing-writer')

    base, config = seed('symlink')
    linked = config/'settings/bar.json'
    referent = base/'actual-bar.json'
    linked.rename(referent)
    linked.symlink_to(referent)
    profile = base/'profile'
    io.snapshot(config, profile, {})
    referent.write_bytes(b'{"position":"top"}')
    io.apply(profile, config, None, base/'evidence')
    assert linked.is_symlink() and linked.resolve() == referent
    assert referent.read_bytes() == b'{"position":"bottom","opaque":18446744073709551615}'
    passed('resolved-symlink-publish-preserves-configured-link')

    base, config = seed('legacy')
    profile = base/'legacy-profile'
    raw(profile, 'settings.json', b'{"settingsVersion":62,"bar":{"position":"right"}}')
    plugin_before = (config/'settings/plugins/example.json').read_bytes()
    io.apply(profile, config, None, base/'evidence')
    assert not (config/'settings/bar.json').exists()
    assert (config/'settings/plugins/example.json').read_bytes() == plugin_before
    assert (config/'settings.json').read_bytes() == (profile/'settings.json').read_bytes()
    passed('legacy-profile-removes-shadowing-main-shards-only')

    base, config = seed('lock')
    lock_path = config/'settings/bar.json.lock'
    with lock_path.open('wb') as stream:
        fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        result = subprocess.run(['sh', str(scripts/'backup-configs.sh'), str(config), str(base/'blocked')],
                                capture_output=True, text=True, timeout=10)
        assert result.returncode != 0 and not (base/'blocked').exists()
    passed('cooperative-lock-failure-is-not-backup-success')

    (args.output/'result.json').write_text(json.dumps(dict(status='PASS', cases=cases), indent=2)+'\n')
    print('SETTINGS_PROFILE_FILES: PASS')


if __name__ == '__main__':
    main()
