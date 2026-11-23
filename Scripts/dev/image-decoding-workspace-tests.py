#!/usr/bin/env python3
"""Guest-only negative controls for finite fixture-source retirement."""
import base64
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import traceback
from unittest.mock import patch

from guest_profile import activate_profile, profile_argument, protect_owned_process
from image_decoding_evidence import source_manifest
from image_decoding_workspace import retire_fixture_copy


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    root = Path(tempfile.mkdtemp(prefix='image-workspace-', dir=profile.work_base))
    source = root / 'source'
    source.mkdir()
    (source / 'product.qml').write_text('import QtQuick\nItem {}\n')
    (source / 'empty').mkdir()
    (source / 'empty').chmod(0o750)
    (source / 'product-link').symlink_to('product.qml')
    base = source_manifest(source)
    receipt = root / 'source.json'
    receipt.write_text(json.dumps(base))
    work = root / 'work'
    work.mkdir()
    passed = []
    failures = []

    def control(name, function):
        try:
            function()
        except Exception:
            failures.append(dict(case=name, error=traceback.format_exc()))

    def fixture(name):
        copy = work / name
        shutil.copytree(source, copy, symlinks=True)
        (copy / 'image-decoding-fixture.qml').write_text('import QtQuick\nItem { width: 64 }\n')
        return copy

    def refuse(name, copy):
        try:
            retire_fixture_copy(source, copy, receipt, root / (name + '.json'), work)
        except ValueError:
            assert copy.exists()
            passed.append(name)
        else:
            raise AssertionError('Unsafe retirement admitted: ' + name)

    copy = fixture('complete')
    actual = source_manifest(copy)
    record = retire_fixture_copy(source, copy, receipt, root / 'complete.json', work)
    rebuilt = dict(base['files'])
    for name, row in record['deltas'].items():
        raw = base64.b64decode(row['bytesBase64'], validate=True)
        assert hashlib.sha256(raw).hexdigest() == row['record']['sha256']
        rebuilt[name] = row['record']
    assert rebuilt == actual['files'] and record['retired'] and not copy.exists()
    passed.append('complete-finite-reconstruction')
    # Preserve bytes, not a mutable canonical-source promise. Mutation after
    # the first check must leave a complete independently rebuildable receipt.
    def source_race():
        copy = fixture('source-race')
        before = (copy / 'product.qml').read_bytes()
        actual_manifest = source_manifest
        def mutate_after_check(path):
            value = actual_manifest(path)
            if Path(path) == source:
                (source / 'product.qml').write_text('concurrent canonical edit')
            return value
        try:
            with patch('image_decoding_workspace.source_manifest', mutate_after_check):
                record = retire_fixture_copy(source, copy, receipt, root / 'race.json', work)
            objects = record.get('objects', {})
            digest = hashlib.sha256(before).hexdigest()
            assert digest in objects and Path(objects[digest]).read_bytes() == before
            assert record['copyManifest'] == actual_manifest_from_bytes(record['copyManifest'])
            rebuilt = root / 'race-rebuilt'
            rebuild(record, rebuilt)
            assert source_manifest(rebuilt) == record['copyManifest']
            assert all(not Path(path).stat().st_mode & 0o222 for path in objects.values())
            passed.append('source-mutation-keeps-immutable-base')
        finally:
            (source / 'product.qml').write_bytes(before)
    control('source-mutation-keeps-immutable-base', source_race)

    # A failed final publication must keep the prior complete receipt, even
    # when the failure would have truncated a direct in-place write.
    def write_failure():
        copy = fixture('receipt-failure')
        output = root / 'write-failure.json'
        write_text, replace = Path.write_text, __import__('os').replace
        def fail_direct(path, data, *args, **kwargs):
            if path == output and json.loads(data)['retired']:
                write_text(path, '{')
                raise OSError('injected receipt write failure')
            return write_text(path, data, *args, **kwargs)
        def fail_atomic(src, dst, *args, **kwargs):
            if Path(dst) == output and json.loads(Path(src).read_text())['retired']:
                raise OSError('injected receipt write failure')
            return replace(src, dst, *args, **kwargs)
        with patch.object(Path, 'write_text', fail_direct), patch('os.replace', fail_atomic):
            try:
                retire_fixture_copy(source, copy, receipt, output, work)
            except OSError:
                pass
            else:
                raise AssertionError('Expected final receipt publication failure')
        preserved = json.loads(output.read_text())
        assert not preserved['retired'] and preserved['copySha256']
        assert preserved['copyManifest'] == actual_manifest_from_bytes(preserved['copyManifest'])
        rebuilt = root / 'failure-rebuilt'
        rebuild(preserved, rebuilt)
        assert source_manifest(rebuilt) == preserved['copyManifest']
        passed.append('write-failure-keeps-complete-receipt')
    control('write-failure-keeps-complete-receipt', write_failure)
    copy = fixture('changed')
    (copy / 'product.qml').write_text('arbitrary change')
    refuse('changed-product-refused', copy)
    copy = fixture('missing')
    (copy / 'product.qml').unlink()
    refuse('missing-product-refused', copy)
    copy = fixture('extra')
    (copy / 'unsaved.txt').write_text('keep')
    refuse('unexplained-file-refused', copy)
    copy = fixture('extra-directory')
    (copy / 'unsaved-empty-directory').mkdir()
    control('unexplained-directory-refused', lambda: refuse('unexplained-directory-refused', copy))
    refuse('canonical-source-refused', source)
    copy = fixture('active')
    process = subprocess.Popen(['python3', '-c', 'import time; time.sleep(30)', str(copy)], start_new_session=True)
    guard = protect_owned_process(process)
    try:
        refuse('live-consumer-refused', copy)
    finally:
        guard.terminate()
        process.wait(timeout=10)
    copy = fixture('source-changed')
    (source / 'product.qml').write_text('new input')
    refuse('changed-canonical-source-refused', copy)
    result = dict(passed=not failures, cases=passed, failures=failures, workspace=str(root))
    (root / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return 0 if result['passed'] else 1


def actual_manifest_from_bytes(manifest):
    """The receipt itself contains every file/link/directory mode identity."""
    rows = manifest['files']
    digest = hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()
    return dict(sha256=digest, files=rows)


def rebuild(record, destination):
    destination.mkdir()
    for name, row in record['copyManifest']['files'].items():
        path = destination / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if row['type'] == 'directory':
            path.mkdir(exist_ok=True)
            path.chmod(row['mode'])
        elif row['type'] == 'link':
            path.symlink_to(row['target'])
        else:
            raw = Path(record['objects'][row['sha256']]).read_bytes()
            assert hashlib.sha256(raw).hexdigest() == row['sha256']
            path.write_bytes(raw)
            path.chmod(row['mode'])


if __name__ == '__main__':
    raise SystemExit(main())
