#!/usr/bin/env python3
"""Guest-only negative controls for finite fixture-source retirement."""
import base64
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

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
    base = source_manifest(source)
    receipt = root / 'source.json'
    receipt.write_text(json.dumps(base))
    work = root / 'work'
    work.mkdir()
    passed = []

    def fixture(name):
        copy = work / name
        shutil.copytree(source, copy)
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
    copy = fixture('changed')
    (copy / 'product.qml').write_text('arbitrary change')
    refuse('changed-product-refused', copy)
    copy = fixture('missing')
    (copy / 'product.qml').unlink()
    refuse('missing-product-refused', copy)
    copy = fixture('extra')
    (copy / 'unsaved.txt').write_text('keep')
    refuse('unexplained-file-refused', copy)
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
    result = dict(passed=True, cases=passed, workspace=str(root))
    (root / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
