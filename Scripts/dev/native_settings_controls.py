"""Build exact-installed-library test instrumentation inside the named guest."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(source):
    workspace = Path(os.environ['TMPDIR']).parent
    assert workspace == Path('/home/tester/Projects/atcq')
    assert subprocess.check_output(['sudo', '-n', 'cat', '/sys/class/dmi/id/product_uuid'], text=True).strip() == '12f17a02-25e9-474c-9dae-fea092c2d2be'
    metadata = json.loads((source/'Scripts/dev/native-metadata/dependencies/configqml-050/manifest.json').read_text())
    pin = metadata['sourceCommit']
    version = metadata['version']
    for name, expected in metadata['artifacts'].items():
        assert digest(Path('/usr/lib/qt6/qml/ConfigQml')/name) == expected, 'installed native metadata mismatch'
    candidates = []
    for candidate in workspace.glob('*/configqml-'+version):
        archive = candidate.parent/'source.tar'
        if not archive.is_file():
            continue
        with tarfile.open(archive) as contents:
            if contents.pax_headers.get('comment') != pin:
                continue
            for header in candidate.glob('*.h'):
                member = contents.extractfile('configqml-'+version+'/'+header.name)
                assert member is not None and member.read() == header.read_bytes(), 'exact native header mismatch'
        candidates.append(candidate)
    assert len(candidates) == 1, 'exact native test archive missing or ambiguous'
    fixtures = source/'Scripts/dev/fixtures/native-settings-model'
    inputs = {p.name: digest(p) for p in sorted(fixtures.iterdir()) if p.is_file()}
    contract = dict(pin=pin, inputs=inputs, artifacts=metadata['artifacts'])
    key = hashlib.sha256(json.dumps(contract, sort_keys=True).encode()).hexdigest()
    cache = workspace/'native-controls'/key
    ready = cache/'ready.json'
    if ready.is_file():
        record = json.loads(ready.read_text())
        assert record['contract'] == contract
        assert all(digest(cache/name) == expected for name, expected in record['outputs'].items()), 'native test cache changed'
        return cache/'build', record
    cache.mkdir(parents=True, exist_ok=False)
    shutil.copytree(fixtures, cache/'src')
    with (cache/'build.log').open('x') as log:
        subprocess.run(['timeout', '30', 'cmake', '-S', str(cache/'src'), '-B', str(cache/'build'), '-G', 'Ninja',
                        '-DCONFIGQML_TEST_SOURCE='+str(candidates[0])], check=True, stdout=log, stderr=subprocess.STDOUT, timeout=35)
        subprocess.run(['timeout', '70', 'cmake', '--build', str(cache/'build'), '--parallel', '4'],
                       check=True, stdout=log, stderr=subprocess.STDOUT, timeout=75)
    outputs = {str(path.relative_to(cache)): digest(path) for path in (cache/'build').rglob('*')
               if path.is_file() and not path.is_symlink() and (path.suffix == '.so' or path.name in ('qmldir', 'atmosphera_settings_test.qmltypes'))}
    record = dict(contract=contract, outputs=outputs)
    ready.write_text(json.dumps(record, indent=2)+'\n')
    return cache/'build', record
