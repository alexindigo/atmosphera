"""Independent saved-endpoint review, including frames and package receipts."""
import hashlib
import json
from pathlib import Path

from image_decoding_fixtures import COLORS, pixel, read_png


OWNER_ENDPOINTS = {
    'owner': ('owner', 'owner-locker'),
    'packaging': ('aur-shell', 'aur-locker', 'nix-shell', 'nix-locker'),
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
        require({'formats', 'motion', 'raw', 'workerRunning', 'finalInterests', 'finalRequests'} <= consumer.keys()
                and isinstance(consumer['formats'], list) and consumer['formats'],
                'Incomplete owner endpoint: ' + str(directory))
        require(consumer['raw'] == (1 if lane == 'present' else 3), 'Raw codec control mismatch')
        for index, row in enumerate(consumer['formats']):
            require(row['consumer']['state'] == 'ready', 'Format endpoint unavailable: ' + row['name'])
            center = frames['format-' + str(index) + '.png']['center']
            require(max(abs(a-b) for a, b in zip(center, COLORS[0])) <= 8, 'Format pixels disagree: ' + row['name'])
        motion = consumer['motion']
        require(motion['state'] == 'ready' and motion['frameCount'] == motion['result']['frames'] == 3,
                'Animated endpoint did not retain three frames')
        colors = {tuple(row['center']) for name, row in frames.items() if name.startswith('motion-')}
        require(colors == set(COLORS), 'Presented motion frames do not match independent fixture colors')
        require(motion['result']['origin'] == ('native' if lane == 'present' else 'fallback'), 'Wrong decoder lane')
        require(not consumer['workerRunning'] and consumer['finalInterests'] == consumer['finalRequests'] == 0,
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
    for name in ('aur-candidate-build', 'aur-candidate-normal-install', 'nix-candidate-build', 'devcontainer-candidate-build'):
        record = load(directory / (name + '-command.json'))
        require(record['exit'] == 0 and (directory / (name + '.log')).is_file(), 'Package command failed: ' + name)
    pkginfo = (directory / 'candidate.PKGINFO').read_text()
    srcinfo = (directory / 'stable.SRCINFO').read_text()
    for dep in ('qt6-imageformats', 'imagemagick', 'ffmpeg', 'python', 'libwebp', 'libheif'):
        require('depend = ' + dep + '\n' in pkginfo and 'depends = ' + dep + '\n' in srcinfo, 'Missing AUR dependency: ' + dep)
    closure = (directory / 'nix-closure.txt').read_text().splitlines()
    for dep in ('imagemagick', 'ffmpeg', 'python3', 'qtimageformats', 'libheif'):
        require(any(dep in Path(line).name for line in closure), 'Missing Nix closure: ' + dep)
    tools = (directory / 'devcontainer-tools.txt').read_text()
    for codec in ('WEBP', 'HEIC', 'AVIF', 'PNG', 'GIF'):
        rows = [line.split() for line in tools.splitlines() if line.split() and line.split()[0].rstrip('*') == codec]
        require(rows and ('r' if codec in ('WEBP', 'HEIC', 'AVIF') else 'w') in rows[0][2], 'Missing container delegate: ' + codec)
    require({p.parent.relative_to(directory).as_posix() for p in directory.rglob('consumer.json')} == set(OWNER_ENDPOINTS['packaging']),
             'Incomplete installed consumer matrix')
    return dict(closure=closure, requiredConsumers=list(OWNER_ENDPOINTS['packaging']))


def inspect(directory, contract, expected, lane):
    report = load(directory / 'result.json')
    require(report['inputs'] == expected, 'Mixed/stale input trees: ' + str(directory))
    require(report['state'] == 'complete' and report['qtWebp'] == lane, 'Incomplete/wrong lane: ' + str(directory))
    rows = report['cases']
    require(len(rows) == len({r['id'] for r in rows}) and {r['id'] for r in rows} == set(contract),
            'Missing or unexpected case IDs: ' + str(directory))
    require(all(row['result'] == 'PASS' for row in rows), 'Nonpassing required case: ' + str(directory))
    owner_dirs = {directory / name for name in OWNER_ENDPOINTS.get(report['case'], ())}
    observed_dirs = {path.parent for path in directory.rglob('consumer.json')}
    require(owner_dirs <= observed_dirs, 'Missing required owner endpoint: ' + str(directory))
    endpoints = [endpoint(path, lane, owner=path in owner_dirs) for path in sorted(observed_dirs)]
    require(endpoints, 'No saved consumer endpoints: ' + str(directory))
    result = dict(path=str(directory), case=report['case'], qtWebp=lane, checks=len(rows), endpoints=endpoints)
    if report['case'] == 'packaging':
        result['packages'] = packages(directory)
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
