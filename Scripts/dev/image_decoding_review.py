"""Independent saved-endpoint review, including frames and package receipts."""
import hashlib
import json
from pathlib import Path
import re

from image_decoding_evidence import displays_retired
from image_decoding_fixtures import COLORS, pixel, read_png
from image_decoding_package_contract import AUR_REMOVED, AUR_REQUIRED, AUR_VARIANTS, NIX_DECODER, NIX_REMOVED


OWNER_ENDPOINTS = {
    'owner': ('owner', 'owner-locker'),
}


def load(path):
    return json.loads(Path(path).read_text())


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def endpoint(directory, lane, *, owner=False):
    """Reconstruct the endpoint from its raw Qt log, not the driver's verdict."""
    consumer = load(directory / 'consumer.json')
    process = load(directory / 'process.json')
    lines = (directory / 'qt.log').read_text().splitlines()
    observations = [json.loads(line.split('IMAGE_BASELINE|', 1)[1]) for line in lines if 'IMAGE_BASELINE|' in line]
    grabs = [json.loads(line.split('IMAGE_GRAB|', 1)[1]) for line in lines if 'IMAGE_GRAB|' in line]
    require(process['exit'] == 0 and observations == [consumer], 'Endpoint/log mismatch: ' + str(directory))
    require(grabs and all(row['saved'] for row in grabs), 'Missing presented grabs: ' + str(directory))
    frames = {}
    saved_files = {p.name: p for p in directory.glob('*.png') if p.is_file() and not p.is_symlink()}
    for row in grabs:
        # Older fixtures record either a capture stem, a filename, or a single
        # unnamed capture. Normalize by unique file identity, never by guessing
        # from a suffix (a stem can itself contain an input filename).
        name = row.get('name')
        if name is None:
            require(len(grabs) == len(saved_files) == 1, 'Ambiguous unnamed capture: ' + str(directory))
            candidates = list(saved_files.values())
        else:
            require(isinstance(name, str) and bool(name), 'Invalid capture label')
            candidates = [saved_files[label] for label in (name, name + '.png') if label in saved_files]
        require(len(candidates) == 1, 'Missing or ambiguous saved capture: ' + str(directory) + '/' + str(name))
        path = candidates[0]
        require(path.parent == directory and not path.is_symlink(), 'Nonlocal endpoint frame')
        width, height, _pixels = read_png(path)
        frames[path.name] = dict(sha256=hashlib.sha256(path.read_bytes()).hexdigest(), width=width, height=height,
                                 center=pixel(path))
    if owner:
        require({'formats', 'motion', 'raw', 'retired'} <= consumer.keys()
                and isinstance(consumer['formats'], list) and consumer['formats'],
                'Incomplete owner endpoint: ' + str(directory))
        require(consumer['raw'] == (1 if lane == 'present' else 3), 'Raw codec control mismatch')
        for index, row in enumerate(consumer['formats']):
            require(row['consumer']['state'] == 'ready', 'Format endpoint unavailable: ' + row['name'])
            center = frames['format-' + str(index) + '.png']['center']
            require(max(abs(a-b) for a, b in zip(center, COLORS[0])) <= 8, 'Format pixels disagree: ' + row['name'])
        motion = consumer['motion']
        require(motion['state'] == 'ready' and motion['result']['format'] == 'webp'
                and motion['frameCount'] == motion['result']['frames'] == 3,
                'Animated endpoint did not retain three frames')
        colors = {tuple(row['center']) for name, row in frames.items() if name.startswith('motion-')}
        require(colors == set(COLORS), 'Presented motion frames do not match independent fixture colors')
        require(displays_retired(consumer['retired'], len(consumer['formats']) + 10),
                'Installed/owner endpoint retained work')
    plugins = process['imagePlugins']
    if lane == 'absent':
        require(not any('qwebp' in p for p in plugins), 'Absent process loaded the WebP plugin')
    if process.get('cleanEnvironment'):
        require(plugins and all(p.startswith('/nix/store/') for p in plugins), 'Nix imported foreign image plugins')
        require(any(p.startswith('/nix/store/') and Path(p).name in ('qs', 'quickshell', '.quickshell-wrapped')
                    for p in process['executables']), 'Installed Nix Qt process missing')
        require(any('/nonexistent' in env.get('PATH', '') and '/nix/store/' in env.get('PATH', '')
                    for env in process['environments']), 'Real wrapper did not supply clean PATH')
    return dict(path=str(directory), process=process, frames=frames, consumerKeys=sorted(consumer))


def packages(directory):
    dependencies = {}
    for variant in AUR_VARIANTS:
        deps = set()
        for line in (directory / (variant + '.SRCINFO')).read_text().splitlines():
            key, _, value = line.partition('=')
            if key.strip() == 'depends':
                deps.add(re.split(r'[<>=]', value.strip(), maxsplit=1)[0])
        require(AUR_REQUIRED <= deps, f'{variant}: missing dependencies {sorted(AUR_REQUIRED - deps)}')
        require(not (AUR_REMOVED & deps), f'{variant}: retired dependencies {sorted(AUR_REMOVED & deps)}')
        dependencies[variant] = sorted(deps)

    # Qualification currently evaluates package metadata and wrapper inputs.
    # It does not build/install packages or enumerate a transitive Nix closure.
    graph = load(directory / 'nix-eval.json')
    inputs = graph['inputs']
    wrapper_paths, qml_paths = set(), set()
    for line in graph['preFixup'].splitlines():
        words = line.split()
        for word in words:
            wrapper_paths.update(path for path in word.strip('"').split(':') if path.startswith('/nix/store/'))
        if words[:3] == ['--prefix', 'QML_IMPORT_PATH', ':'] and len(words) == 4:
            qml_paths.add(words[3].strip('"'))

    def package_name(path):
        parts = Path(path).parts
        require(parts[:3] == ('/', 'nix', 'store') and len(parts) >= 4, 'Invalid Nix store path: ' + path)
        return parts[3].split('-', 1)[-1]

    decoder = [path for path in inputs if package_name(path).startswith(NIX_DECODER + '-')]
    require(len(decoder) == 1, 'Expected one imvqml build input')
    require(any(path.startswith(decoder[0] + '/') and path.endswith('/qml') for path in qml_paths),
            'Wrapper missing imvqml QML import path')
    retired = {package_name(path) for path in set(inputs) | wrapper_paths if any(
        package_name(path) == dep or package_name(path).startswith(dep + '-') for dep in NIX_REMOVED)}
    require(not retired, 'Retired direct Nix dependencies: ' + ', '.join(sorted(retired)))
    return dict(aurDependencies=dependencies, nixDecoder=decoder[0])


def inspect(directory, contract, expected, lane):
    report = load(directory / 'result.json')
    require(report['inputs'] == expected, 'Mixed/stale input trees: ' + str(directory))
    require(report['state'] == 'complete' and report['qtWebp'] == lane, 'Incomplete/wrong lane: ' + str(directory))
    rows = report['cases']
    require(len(rows) == len({r['id'] for r in rows}) and {r['id'] for r in rows} == set(contract),
            'Missing or unexpected case IDs: ' + str(directory))
    require(all(row['result'] == 'PASS' for row in rows), 'Nonpassing required case: ' + str(directory))
    if report['case'] == 'packaging':
        return dict(path=str(directory), case=report['case'], qtWebp=lane, checks=len(rows),
                    endpoints=[], packages=packages(directory))
    owner_dirs = {directory / name for name in OWNER_ENDPOINTS.get(report['case'], ())}
    observed_dirs = {path.parent for path in directory.rglob('consumer.json')}
    require(owner_dirs <= observed_dirs, 'Missing required owner endpoint: ' + str(directory))
    endpoints = [endpoint(path, lane, owner=path in owner_dirs) for path in sorted(observed_dirs)]
    require(endpoints, 'No saved consumer endpoints: ' + str(directory))
    result = dict(path=str(directory), case=report['case'], qtWebp=lane, checks=len(rows), endpoints=endpoints)
    return result


def review(run):
    results = run.args.results
    if results is None or results != results.resolve() or not results.is_dir() or not results.is_relative_to(run.profile.journal_base):
        raise ValueError('--results must name canonical saved guest evidence')
    contract = load(run.args.source / 'Scripts/dev/fixtures/image-decoding/required-cases.json')
    expected = {key: row['sha256'] for key, row in run.inputs.items()}
    candidates = {}
    stale = 0
    for path in sorted(results.rglob('result.json')):
        if path.is_relative_to(run.out):
            continue
        record = load(path)
        if record.get('case') not in contract:
            continue
        if record.get('inputs') != expected:
            stale += 1
            continue
        if record.get('state') == 'complete':
            candidates.setdefault((record['case'], record['qtWebp']), []).append(path.parent)
    reviewed = []
    for case, ids in contract.items():
        for lane in (('present',) if case == 'packaging' else ('present', 'absent')):
            matches = candidates.get((case, lane), [])
            require(matches, 'Missing current-tree cohort: ' + case + '/' + lane)
            # Review every matching success, rather than hide a deficient one
            # behind another passing aggregate or an unrelated historical tree.
            for directory in matches:
                observed = inspect(directory, ids, expected, lane)
                reviewed.append(observed)
                run.check('review-' + case + '-' + lane + '-' + str(len(reviewed)), True,
                          dict(path=str(directory), checks=observed['checks'], endpoints=len(observed['endpoints'])))
    (run.out / 'independent-review.json').write_text(json.dumps(dict(inputs=expected, historicalExcluded=stale, reviewed=reviewed), indent=2) + '\n')
