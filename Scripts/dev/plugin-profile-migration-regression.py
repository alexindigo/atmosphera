#!/usr/bin/env python3
"""Guest-side gate: plugins.json v5 profile migration and built-in refresh (M14).

Run inside the Qt612 niri VM only. For every synthetic fixture the script builds
a profile under ROOT/runtime/<output name>/profiles/<fixture>, cold-starts a copy
of --source twice (15 s each, same launcher and environment as shell-gate.py),
and checks the profile after each start. Fixtures contain synthetic data only.

--output receives small files only: logs, per-start profile inventories, copies
of the small settings and plugins.json files, and result.json (written last).
Exit 0: every check passed. Exit 1: at least one check failed. Exit 2: setup error.
"""
import argparse
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import traceback
from pathlib import Path

ROOT = Path('/home/tester/Projects/qt612-atmocolor/081-integrity')
REGISTRY_URL = 'https://github.com/alexindigo/atmosphera-plugins'
WALLPAPERS_URL = 'https://github.com/atmosphera/atmosphera-wallpapers'
REGISTRY_HASH = '57e8d5'
START_SECONDS = 15
MARKER = 'OLD-COPY'
SHIPPED_IDS = ['atmosphera-icons', 'atmosphera-wallpapers', 'demo-custom-lockscreen']
ERRORS = re.compile(r'ReferenceError|TypeError|Cannot assign to non-existent property|Component is not ready|'
                    r'Failed to load configuration|module .* is not installed|is not a type|QQuickColor')
OLD_NICON_VIEW = ('import QtQuick\n\n// Pre-0.8 lock screen view.\n'
                  'Item {\n    NIcon { icon: "lock" }\n}\n')


class SetupError(Exception):
    pass


def sha(data):
    return hashlib.sha256(data).hexdigest()


def short_hash(url):
    return sha(url.encode())[:6]


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n')


def write_section(cfg, name, value):
    path = cfg / 'settings' / (name + '.json')
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(value, bytes):
        path.write_bytes(value)
    else:
        write_json(path, value)


def write_plugins(cfg, version, sources, states):
    write_json(cfg / 'plugins.json', {'version': version, 'sources': sources, 'states': states})
    return (cfg / 'plugins.json').read_bytes()


def tree_of(root):
    """rel path -> sha256 for files, symlink target for links; top-level settings.json excluded."""
    out = {}
    for f in sorted(root.rglob('*')):
        rel = f.relative_to(root).as_posix()
        if rel == 'settings.json':
            continue
        if f.is_symlink():
            out[rel] = 'link:' + os.readlink(f)
        elif f.is_file():
            out[rel] = sha(f.read_bytes())
    return out


def inventory(root):
    """rel path -> sha256/mtime/size for every file under root (profile inventory)."""
    out = {}
    for f in sorted(root.rglob('*')):
        rel = f.relative_to(root).as_posix()
        if f.is_symlink():
            out[rel] = {'symlink': os.readlink(f)}
        elif f.is_file():
            st = f.stat()
            out[rel] = {'sha256': sha(f.read_bytes()), 'mtime_ns': st.st_mtime_ns, 'size': st.st_size}
    return out


def small_files(profile):
    """Small settings and plugins.json files copied to the output directory."""
    cfg = profile / 'config'
    picked = [cfg / 'plugins.json', cfg / 'settings.json']
    picked += sorted(cfg.glob('settings/*.json'))
    picked += sorted(cfg.glob('settings/plugins/*.json'))
    picked += sorted(cfg.glob('plugins/*/settings.json'))
    return {p.relative_to(cfg).as_posix(): p.read_bytes() for p in picked if p.is_file()}


def qs_pids():
    pids = []
    for d in glob.glob('/proc/[0-9]*'):
        try:
            if Path(d, 'comm').read_text().strip() not in ('qs', 'quickshell'):
                continue
            uid_line = next(x for x in Path(d, 'status').read_text().splitlines() if x.startswith('Uid:'))
            if int(uid_line.split()[1]) == 1000:
                pids.append(int(Path(d).name))
        except (OSError, StopIteration, ValueError):
            continue
    return pids


def shell_env(profile):
    cfg, cache = profile / 'config', profile / 'cache'
    return dict(os.environ, TMPDIR=str(ROOT / 'tmp'), XDG_RUNTIME_DIR='/run/user/1000',
                WAYLAND_DISPLAY='wayland-1', NIRI_SOCKET=glob.glob('/run/user/1000/niri.*.sock')[0],
                QT_FORCE_STDERR_LOGGING='1', ATMOSPHERA_CONFIG_DIR=str(cfg) + '/',
                ATMOSPHERA_CACHE_DIR=str(cache) + '/', ATMOSPHERA_SETTINGS_FILE=str(cfg / 'settings.json'),
                ATMOSPHERA_DEBUG='0', ATMOSPHERA_UPGRADELOG_URL='http://127.0.0.1:9')


def check(res, name, cond, detail=''):
    res.append({'name': name, 'ok': bool(cond), 'detail': '' if cond else str(detail)[:900]})


def diff_dicts(got, want):
    keys = sorted(set(got or {}) | set(want or {}))
    return {k: {'got': (got or {}).get(k), 'want': (want or {}).get(k)}
            for k in keys if (got or {}).get(k) != (want or {}).get(k)}


class Ctx:
    def __init__(self, shell, runtime, out):
        self.shell = shell
        self.runtime = runtime
        self.out = out
        self.shell_dir = str(shell)
        self.B = 'file://' + self.shell_dir + '/builtin/plugins'
        self.O = 'file://' + self.shell_dir + '/Plugins'
        self.H = short_hash(self.B)
        self.HO = short_hash(self.O)
        shipped = sorted(p.parent.name for p in (shell / 'builtin/plugins').glob('*/manifest.json'))
        if sorted(shipped) != sorted(SHIPPED_IDS):
            raise SetupError('shipped built-ins are %s, expected %s' % (shipped, SHIPPED_IDS))
        self.shipped_manifest = {i: (shell / 'builtin/plugins' / i / 'manifest.json').read_bytes() for i in SHIPPED_IDS}
        self.shipped_tree = {i: tree_of(shell / 'builtin/plugins' / i) for i in SHIPPED_IDS}
        self.shipped_enabled = {i: bool(json.loads(self.shipped_manifest[i]).get('defaultEnabled', False))
                                for i in SHIPPED_IDS}
        reg = (shell / 'Services/Plugins/Registry.qml').read_text()
        m = re.search(r'readonly property int currentVersion: (\d+)', reg)
        if not m:
            raise SetupError('currentVersion not found in Registry.qml')
        self.version = int(m.group(1))


def cold_start(ctx, profile, name):
    before = qs_pids()
    if before:
        raise SetupError('quickshell already running before %s: %s' % (name, before))
    cmd = ['timeout', '--kill-after=5s', str(START_SECONDS), 'dbus-run-session', '--',
           'qs', '-p', str(ctx.shell / 'shell.qml')]
    r = subprocess.run(cmd, cwd=str(ctx.shell), env=shell_env(profile), capture_output=True,
                       timeout=START_SECONDS + 60)
    text = (r.stdout + r.stderr).decode('utf-8', 'replace')
    (ctx.out_dir / (name + '.log')).write_text(text)
    deadline = time.monotonic() + 20
    while qs_pids() and time.monotonic() < deadline:
        time.sleep(1)
    return {'rc': r.returncode, 'log': text, 'leftover': qs_pids()}


def snapshot(ctx, profile, name):
    write_json(ctx.out_dir / (name + '-inventory.json'), inventory(profile))
    small = small_files(profile)
    for rel, data in small.items():
        dst = ctx.out_dir / (name + '-small') / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(data)
    backups_dir = profile / 'config' / 'backups'
    backups = sorted(p.name for p in backups_dir.glob('*')) if backups_dir.is_dir() else []
    return {'small': small, 'backups': backups}


def expected_sources(ctx):
    return [('Built-in', ctx.B, True), ('Atmosphera Plugins', REGISTRY_URL, True),
            ('Atmosphera Wallpapers', WALLPAPERS_URL, False)]


def check_first_start(ctx, exp, start, snap, res, tag):
    """Checks after a start that must leave the migrated (or fresh) layout."""
    rc, log = start['rc'], start['log']
    check(res, tag + ' ran the full %d s (exit 124)' % START_SECONDS, rc == 124, 'exit %s' % rc)
    check(res, tag + ' leaves no quickshell running', not start['leftover'], start['leftover'])
    m = ERRORS.search(log)
    check(res, tag + ' log has no error signature', m is None, m.group(0) if m else '')
    check(res, tag + ' log has no "NIcon is not a type"', 'NIcon is not a type' not in log, 'NIcon error')
    raw = snap['small'].get('plugins.json')
    if raw is None:
        check(res, tag + ' plugins.json exists', False, 'missing')
        return
    pj = json.loads(raw)
    check(res, tag + ' plugins.json version is current (%d)' % ctx.version,
          pj.get('version') == ctx.version, pj.get('version'))
    got_sources = [(s.get('name'), s.get('url'), s.get('enabled')) for s in pj.get('sources', [])]
    check(res, tag + ' sources: Built-in, Atmosphera Plugins, Wallpapers (disabled)',
          got_sources == expected_sources(ctx), got_sources)
    check(res, tag + ' states match the expected layout', pj.get('states') == exp['states'],
          diff_dicts(pj.get('states'), exp['states']))
    for key, tree in exp['registry'].items():
        got = tree_of(ctx.runtime_profile / 'config/plugins' / key)
        check(res, tag + ' registry folder %s unchanged' % key, got == tree,
              'files differ: %s' % sorted(set(got) ^ set(tree)))
    for bid in exp['built_in_ids']:
        key = ctx.H + ':' + bid
        got = tree_of(ctx.runtime_profile / 'config/plugins' / key)
        check(res, tag + ' folder %s matches shipped copy' % key, got == ctx.shipped_tree[bid],
              'files differ: %s' % sorted(k for k in set(got) | set(ctx.shipped_tree[bid])
                                          if got.get(k) != ctx.shipped_tree[bid].get(k))[:8])
    plugins_dir = ctx.runtime_profile / 'config/plugins'
    names = sorted(p.name for p in plugins_dir.glob('*')) if plugins_dir.is_dir() else []
    leftovers = [n for n in names if n.startswith('builtin:') or any(n.endswith(':' + r) for r in exp['retired'])]
    check(res, tag + ' no builtin: or retired folders remain', not leftovers, leftovers)
    stale = [k for k in pj.get('states', {}) if k.startswith('builtin:') or any(k.endswith(':' + r) for r in exp['retired'])]
    check(res, tag + ' no builtin: or retired states remain', not stale, stale)
    if exp['lock'] is not None:
        lock = None
        path = ctx.runtime_profile / 'config/settings/general.json'
        if path.is_file():
            lock = json.loads(path.read_text()).get('lockScreenPlugin')
        check(res, tag + ' general.lockScreenPlugin is %s' % exp['lock'], lock == exp['lock'], lock)
    for needle in exp['log_has']:
        check(res, tag + ' log has "%s"' % needle, needle in log, 'not logged')
    if exp['backup']:
        dirs = [b for b in snap['backups'] if b.startswith('plugins-v5-')]
        check(res, tag + ' v5 backup directory exists', len(dirs) == 1, snap['backups'])
        if dirs and exp['input_plugins'] is not None:
            saved = ctx.runtime_profile / 'config/backups' / dirs[0] / 'plugins.json'
            same = saved.is_file() and saved.read_bytes() == exp['input_plugins']
            check(res, tag + ' backup plugins.json is the pre-migration file', same, 'differs or missing')
    else:
        check(res, tag + ' no v5 backup on a fresh profile', not any(b.startswith('plugins-v5-') for b in snap['backups']),
              snap['backups'])
    if exp.get('extra'):
        exp['extra'](ctx, res, tag)


def check_second_start(start1, snap1, start2, snap2, res):
    check(res, 'start 2 ran the full %d s (exit 124)' % START_SECONDS, start2['rc'] == 124, 'exit %s' % start2['rc'])
    check(res, 'start 2 leaves no quickshell running', not start2['leftover'], start2['leftover'])
    m = ERRORS.search(start2['log'])
    check(res, 'start 2 log has no error signature', m is None, m.group(0) if m else '')
    check(res, 'start 2 plugins.json byte-identical to start 1',
          snap2['small'].get('plugins.json') == snap1['small'].get('plugins.json'), 'plugins.json changed')
    same = snap2['small'] == snap1['small']
    changed = sorted(k for k in set(snap1['small']) | set(snap2['small'])
                     if snap1['small'].get(k) != snap2['small'].get(k))
    check(res, 'start 2 settings and plugin settings byte-identical to start 1', same, changed)
    check(res, 'start 2 creates no new backup', snap2['backups'] == snap1['backups'], snap2['backups'])


def run_layout_fixture(ctx, name, build):
    """Build, start twice, check: the layout and the no-change rule."""
    res = []
    prof = ctx.runtime_profile
    exp = build(ctx, prof)
    start1 = cold_start(ctx, prof, 'start1')
    snap1 = snapshot(ctx, prof, 'start1')
    check_first_start(ctx, exp, start1, snap1, res, 'start 1')
    start2 = cold_start(ctx, prof, 'start2')
    snap2 = snapshot(ctx, prof, 'start2')
    check_second_start(start1, snap1, start2, snap2, res)
    return res


def setup_profile(ctx, name):
    ctx.out_dir = ctx.out / name
    ctx.out_dir.mkdir(parents=True)
    ctx.runtime_profile = ctx.runtime / 'profiles' / name
    (ctx.runtime_profile / 'config').mkdir(parents=True)
    (ctx.runtime_profile / 'cache').mkdir(parents=True)
    return ctx.runtime_profile


REG_SOURCE = {'name': 'Atmosphera Plugins', 'url': REGISTRY_URL, 'enabled': True}
REG_FOLDERS = [('57e8d5:pomodoro', 'pomodoro'), ('57e8d5:weather', 'weather'), ('digest-watcher', 'digest-watcher')]


def reg_states():
    return {
        '57e8d5:pomodoro': {'enabled': True, 'sourceUrl': REGISTRY_URL},
        '57e8d5:weather': {'enabled': False, 'sourceUrl': REGISTRY_URL},
        'digest-watcher': {'enabled': True, 'sourceUrl': None},
    }


def manifest_for(mid):
    return {'id': mid, 'name': mid, 'version': '1.0.0', 'author': 'M14 fixture',
            'description': 'Synthetic fixture plugin', 'entryPoints': {}}


def put_builtin_copy(ctx, dst, shipped_id, marker=False):
    shutil.copytree(ctx.shell / 'builtin/plugins' / shipped_id, dst, symlinks=True)
    if marker:
        (dst / MARKER).write_text('pre-migration copy\n')


def put_manifest_dir(dst, mid, marker=False):
    dst.mkdir(parents=True)
    write_json(dst / 'manifest.json', manifest_for(mid))
    if marker:
        (dst / MARKER).write_text('pre-migration copy\n')


def put_registry(plugins):
    trees = {}
    for key, mid in REG_FOLDERS:
        put_manifest_dir(plugins / key, mid)
        trees[key] = tree_of(plugins / key)
    return trees


def expect(ctx, states, lock, built_in_ids, log_has, backup=True, input_plugins=None, retired=(), extra=None):
    return {'states': states, 'registry': reg_trees_cache(ctx), 'built_in_ids': built_in_ids,
            'retired': list(retired), 'lock': lock, 'log_has': log_has, 'backup': backup,
            'input_plugins': input_plugins, 'extra': extra}


def reg_trees_cache(ctx):
    return ctx.reg_trees


def layout_states(ctx, enabled):
    """Expected final states: the built-ins in `enabled` (id -> enabled) under the current key, plus registry."""
    out = {ctx.H + ':' + i: {'enabled': e, 'sourceUrl': ctx.B} for i, e in enabled.items()}
    out.update(reg_states())
    return out


def common_log(ctx, extra=()):
    return ["Parsed 3 plugins manifest from 'Built-in'",
            'Plugin loaded: %s:demo-custom-lockscreen' % ctx.H] + list(extra)


def build_user_shaped(ctx, prof):
    """Fixture 1: a v4 profile with builtin: keys, a retired built-in, an old NIcon view, registry plugins, unsourced plugin."""
    cfg = prof / 'config'
    plugins = cfg / 'plugins'
    B = ctx.B
    states = {
        'builtin:atmosphera-icons': {'enabled': True, 'sourceUrl': B},
        'builtin:atmosphera-wallpapers': {'enabled': False, 'sourceUrl': B},
        'builtin:demo-custom-lockscreen': {'enabled': True, 'sourceUrl': B},
        'builtin:noctalia-icons-legacy': {'enabled': True, 'sourceUrl': B},
    }
    states.update(reg_states())
    put_builtin_copy(ctx, plugins / 'builtin:atmosphera-icons', 'atmosphera-icons', marker=True)
    put_builtin_copy(ctx, plugins / 'builtin:atmosphera-wallpapers', 'atmosphera-wallpapers')
    put_builtin_copy(ctx, plugins / 'builtin:demo-custom-lockscreen', 'demo-custom-lockscreen')
    (plugins / 'builtin:demo-custom-lockscreen' / 'LockScreenView.qml').write_text(OLD_NICON_VIEW)
    put_manifest_dir(plugins / 'builtin:noctalia-icons-legacy', 'noctalia-icons-legacy', marker=True)
    ctx.reg_trees = put_registry(plugins)
    raw = write_plugins(cfg, 4, [REG_SOURCE], states)
    write_section(cfg, 'general', {'lockScreenPlugin': 'builtin:demo-custom-lockscreen',
                                   'showChangelogOnStartup': False})
    write_section(cfg, 'bar', {'widgets': {'left': [{'id': 'plugin:57e8d5:pomodoro'}], 'center': [], 'right': []}})
    want = layout_states(ctx, {'atmosphera-icons': True, 'atmosphera-wallpapers': False,
                               'demo-custom-lockscreen': True})

    def bar_extra(ctx, res, tag):
        bar = json.loads((ctx.runtime_profile / 'config/settings/bar.json').read_text())
        widgets = bar.get('widgets')
        want_widgets = {'left': [{'id': 'plugin:57e8d5:pomodoro'}], 'center': [], 'right': []}
        check(res, tag + ' bar.widgets (left, center, right) equal the fixture input',
              widgets == want_widgets, widgets)
        for label, path in (('rule 4 unsourced digest-watcher folder unchanged', 'digest-watcher'),):
            check(res, tag + ' ' + label, tree_of(plugins / path) == ctx.reg_trees[path],
                  'changed')
    return expect(ctx, want, ctx.H + ':demo-custom-lockscreen', list(SHIPPED_IDS),
                  common_log(ctx, ['rekeyed builtin:demo-custom-lockscreen',
                                   'removed retired built-in plugin builtin:noctalia-icons-legacy',
                                   'digest-watcher is a local plugin without a source']),
                  input_plugins=raw, retired=['noctalia-icons-legacy'], extra=bar_extra)


def build_pre06_hashes(ctx, prof):
    """Fixture 2: built-in keys hashed from file://<shellDir>/Plugins, sourceUrl the old payload path."""
    cfg = prof / 'config'
    plugins = cfg / 'plugins'
    O, HO = ctx.O, ctx.HO
    states = {
        HO + ':atmosphera-icons': {'enabled': True, 'sourceUrl': O},
        HO + ':atmosphera-wallpapers': {'enabled': False, 'sourceUrl': O},
        HO + ':demo-custom-lockscreen': {'enabled': True, 'sourceUrl': O},
    }
    states.update(reg_states())
    put_builtin_copy(ctx, plugins / (HO + ':atmosphera-icons'), 'atmosphera-icons', marker=True)
    put_builtin_copy(ctx, plugins / (HO + ':atmosphera-wallpapers'), 'atmosphera-wallpapers')
    put_builtin_copy(ctx, plugins / (HO + ':demo-custom-lockscreen'), 'demo-custom-lockscreen')
    ctx.reg_trees = put_registry(plugins)
    raw = write_plugins(cfg, 4, [REG_SOURCE], states)
    write_section(cfg, 'general', {'lockScreenPlugin': HO + ':demo-custom-lockscreen',
                                   'showChangelogOnStartup': False})
    want = layout_states(ctx, {'atmosphera-icons': True, 'atmosphera-wallpapers': False,
                               'demo-custom-lockscreen': True})
    return expect(ctx, want, ctx.H + ':demo-custom-lockscreen', list(SHIPPED_IDS),
                  common_log(ctx, ['rekeyed ' + HO + ':demo-custom-lockscreen']), input_plugins=raw)


def build_duplicate(ctx, prof):
    """Fixture 3: builtin: and current keys both exist; the current one is kept, the old one dropped."""
    cfg = prof / 'config'
    plugins = cfg / 'plugins'
    B, H = ctx.B, ctx.H
    states = {
        'builtin:demo-custom-lockscreen': {'enabled': False, 'sourceUrl': B},
        H + ':demo-custom-lockscreen': {'enabled': True, 'sourceUrl': B},
    }
    states.update(reg_states())
    put_builtin_copy(ctx, plugins / 'builtin:demo-custom-lockscreen', 'demo-custom-lockscreen', marker=True)
    put_builtin_copy(ctx, plugins / (H + ':demo-custom-lockscreen'), 'demo-custom-lockscreen')
    ctx.reg_trees = put_registry(plugins)
    raw = write_plugins(cfg, 4, [REG_SOURCE], states)
    write_section(cfg, 'general', {'lockScreenPlugin': 'builtin:demo-custom-lockscreen',
                                   'showChangelogOnStartup': False})
    want = layout_states(ctx, {'demo-custom-lockscreen': True})
    return expect(ctx, want, H + ':demo-custom-lockscreen', ['demo-custom-lockscreen'],
                  common_log(ctx, ['dropped builtin:demo-custom-lockscreen']), input_plugins=raw)


SETTINGS_FILE_BYTES = b'{"showMediaControls": false}\n'
CONFIG_FILE_BYTES = b'{"theme": "kept"}\n'
LEGACY_IN_DIR_BYTES = b'{"showSessionButtons": false, "legacy": true}\n'
DEMO_OLD = 'builtin:demo-custom-lockscreen'


def build_settings_refs(ctx, prof):
    """Fixture 4: old keys in bar, screen overrides, control-centre shortcuts, desktop monitors, lock screen,
    and the per-plugin settings file, its .config sibling and a legacy in-dir settings.json."""
    cfg = prof / 'config'
    plugins = cfg / 'plugins'
    B, H = ctx.B, ctx.H
    states = {
        'builtin:atmosphera-icons': {'enabled': True, 'sourceUrl': B},
        DEMO_OLD: {'enabled': True, 'sourceUrl': B},
    }
    states.update(reg_states())
    put_builtin_copy(ctx, plugins / 'builtin:atmosphera-icons', 'atmosphera-icons', marker=True)
    put_builtin_copy(ctx, plugins / DEMO_OLD, 'demo-custom-lockscreen')
    (plugins / DEMO_OLD / 'settings.json').write_bytes(LEGACY_IN_DIR_BYTES)
    ctx.reg_trees = put_registry(plugins)
    raw = write_plugins(cfg, 4, [REG_SOURCE], states)
    (cfg / 'settings/plugins').mkdir(parents=True)
    write_section(cfg, 'plugins/' + DEMO_OLD, SETTINGS_FILE_BYTES)
    write_section(cfg, 'plugins/' + DEMO_OLD + '.config', CONFIG_FILE_BYTES)
    write_section(cfg, 'general', {'lockScreenPlugin': DEMO_OLD, 'showChangelogOnStartup': False})
    write_section(cfg, 'bar', {
        'widgets': {'left': [{'id': 'plugin:' + DEMO_OLD, 'instanceSettings': {'tint': 'warm'},
                              'customTag': 'keep-me'}, {'id': 'Clock'}],
                    'center': [], 'right': [{'id': 'plugin:57e8d5:pomodoro'}]},
        'screenOverrides': [{'name': 'DP-1', 'widgets': {
            'left': [{'id': 'plugin:builtin:atmosphera-icons'}], 'center': [], 'right': []}}]})
    write_section(cfg, 'controlCenter', {'shortcuts': {
        'left': [{'id': 'plugin:' + DEMO_OLD}, {'id': 'Network'}], 'right': []}})
    write_section(cfg, 'desktopWidgets', {'monitorWidgets': [{'name': 'DP-1', 'widgets': [
        {'id': 'plugin:' + DEMO_OLD, 'instanceSettings': {'x': 1}, 'customTag': 'mon'}]}]})
    want = layout_states(ctx, {'atmosphera-icons': True, 'demo-custom-lockscreen': True})

    def settings_extra(ctx, res, tag):
        def load(section):
            p = ctx.runtime_profile / 'config/settings' / (section + '.json')
            return json.loads(p.read_text()) if p.is_file() else None
        bar = load('bar') or {}
        left = bar.get('widgets', {}).get('left', [])
        check(res, tag + ' bar placement rewritten, instanceSettings and customTag kept',
              left[:1] == [{'id': 'plugin:' + H + ':demo-custom-lockscreen', 'instanceSettings': {'tint': 'warm'},
                            'customTag': 'keep-me'}] and left[1:] == [{'id': 'Clock'}], left)
        check(res, tag + ' bar.widgets.center unchanged', bar.get('widgets', {}).get('center') == [],
              bar.get('widgets', {}).get('center'))
        check(res, tag + ' bar.widgets.right unchanged',
              bar.get('widgets', {}).get('right') == [{'id': 'plugin:57e8d5:pomodoro'}],
              bar.get('widgets', {}).get('right'))
        ov = bar.get('screenOverrides', [])
        check(res, tag + ' screen override placement rewritten', ov and ov[0].get('name') == 'DP-1' and
              ov[0]['widgets']['left'] == [{'id': 'plugin:' + H + ':atmosphera-icons'}], ov)
        cc = (load('controlCenter') or {}).get('shortcuts', {}).get('left')
        check(res, tag + ' control-centre shortcut rewritten, Network kept',
              cc == [{'id': 'plugin:' + H + ':demo-custom-lockscreen'}, {'id': 'Network'}], cc)
        mon = ((load('desktopWidgets') or {}).get('monitorWidgets') or [{}])[0].get('widgets')
        check(res, tag + ' monitor widget rewritten, instanceSettings and customTag kept',
              mon == [{'id': 'plugin:' + H + ':demo-custom-lockscreen', 'instanceSettings': {'x': 1},
                       'customTag': 'mon'}], mon)
        sdir = ctx.runtime_profile / 'config/settings/plugins'
        new_s, new_c = sdir / (H + ':demo-custom-lockscreen.json'), sdir / (H + ':demo-custom-lockscreen.config.json')
        check(res, tag + ' plugin settings file moved, bytes identical',
              new_s.is_file() and new_s.read_bytes() == SETTINGS_FILE_BYTES, 'missing or changed')
        check(res, tag + ' plugin .config file moved, bytes identical',
              new_c.is_file() and new_c.read_bytes() == CONFIG_FILE_BYTES, 'missing or changed')
        check(res, tag + ' old settings file names gone',
              not any(p.name.startswith('builtin:') for p in sdir.glob('*')), sorted(p.name for p in sdir.glob('*')))
        legacy = ctx.runtime_profile / 'config/plugins' / (H + ':demo-custom-lockscreen') / 'settings.json'
        check(res, tag + ' legacy in-dir settings.json byte-identical under the new key',
              legacy.is_file() and legacy.read_bytes() == LEGACY_IN_DIR_BYTES, 'missing or changed')
    return expect(ctx, want, H + ':demo-custom-lockscreen', ['atmosphera-icons', 'demo-custom-lockscreen'],
                  common_log(ctx, ['rekeyed ' + DEMO_OLD, 'rekeyed builtin:atmosphera-icons']),
                  input_plugins=raw, extra=settings_extra)


def build_fresh(ctx, prof):
    """Fixtures 5 and 6: no profile; the seed must match 0.8.0's (Built-in, 3 built-ins, current version)."""
    ctx.reg_trees = {}
    want = {ctx.H + ':' + i: {'enabled': ctx.shipped_enabled[i], 'sourceUrl': ctx.B} for i in SHIPPED_IDS}
    return expect(ctx, want, None, list(SHIPPED_IDS), common_log(ctx), backup=False)


def run_fresh_content_refresh(ctx, prof):
    """Fixture 6: fresh start, then one byte appended to an installed built-in; start 2 must restore it."""
    res = []
    exp = build_fresh(ctx, prof)
    start1 = cold_start(ctx, prof, 'start1')
    snap1 = snapshot(ctx, prof, 'start1')
    check_first_start(ctx, exp, start1, snap1, res, 'start 1')
    icons = prof / 'config/plugins' / (ctx.H + ':atmosphera-icons') / 'manifest.json'
    wall = prof / 'config/plugins' / (ctx.H + ':atmosphera-wallpapers') / 'manifest.json'
    icons.write_bytes(icons.read_bytes() + b' ')
    wall_mtime = wall.stat().st_mtime_ns
    start2 = cold_start(ctx, prof, 'start2')
    snapshot(ctx, prof, 'start2')
    check(res, 'start 2 ran the full %d s (exit 124)' % START_SECONDS, start2['rc'] == 124, 'exit %s' % start2['rc'])
    check(res, 'start 2 leaves no quickshell running', not start2['leftover'], start2['leftover'])
    m = ERRORS.search(start2['log'])
    check(res, 'start 2 log has no error signature', m is None, m.group(0) if m else '')
    check(res, 'start 2 restores the edited icons manifest to the shipped bytes',
          icons.is_file() and icons.read_bytes() == ctx.shipped_manifest['atmosphera-icons'], 'not restored')
    check(res, 'start 2 leaves the wallpapers manifest mtime unchanged',
          wall.is_file() and wall.stat().st_mtime_ns == wall_mtime, 'mtime changed')
    return res


def build_fixtures():
    return [
        ('1-user-shaped-v4', build_user_shaped),
        ('2-pre06-hashes', build_pre06_hashes),
        ('3-duplicate', build_duplicate),
        ('4-settings-references', build_settings_refs),
        ('5-fresh', build_fresh),
        ('6-content-refresh', None),
    ]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--source', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    a = ap.parse_args()
    if os.getuid() != 1000 or Path.home() != Path('/home/tester'):
        raise SetupError('must run as tester in the guest')
    if '52:54:00:4c:05:2c' not in [f.read_text().strip() for f in Path('/sys/class/net').glob('*/address')]:
        raise SetupError('not the guest VM (MAC check)')
    source = a.source.resolve()
    if not source.is_relative_to(ROOT / 'sources') or not (source / 'shell.qml').is_file():
        raise SetupError('source must be a shell tree under %s/sources' % ROOT)
    output = a.output.resolve()
    runtime = ROOT / 'runtime' / output.name
    if output.exists() or runtime.exists():
        raise SetupError('output or runtime for %s already exists' % output.name)
    if short_hash(REGISTRY_URL) != REGISTRY_HASH:
        raise SetupError('hash helper does not reproduce the registry key hash')
    output.mkdir(parents=True)
    runtime.mkdir(parents=True)
    before = tree_of(source)
    shell = runtime / 'shell'
    shutil.copytree(source, shell, symlinks=True)
    ctx = Ctx(shell.resolve(), runtime, output)
    results = {}
    for name, build in build_fixtures():
        res = []
        try:
            if name.startswith('6-'):
                setup_profile(ctx, name)
                res = run_fresh_content_refresh(ctx, ctx.runtime_profile)
            else:
                setup_profile(ctx, name)
                res = run_layout_fixture(ctx, name, build)
        except SetupError:
            raise
        except Exception:
            check(res, 'fixture raised an exception', False, traceback.format_exc()[-800:])
        passed = all(c['ok'] for c in res)
        results[name] = {'pass': passed, 'checks': res}
        print('%s: %s' % (name, 'PASS' if passed else 'FAIL'), flush=True)
        for c in res:
            if not c['ok']:
                print('   FAIL %s: %s' % (c['name'], c['detail']), flush=True)
    source_unchanged = tree_of(source) == before
    everything = source_unchanged and all(r['pass'] for r in results.values())
    receipt = {'source': str(source), 'shell_dir': ctx.shell_dir, 'h': ctx.H, 'ho': ctx.HO,
               'currentVersion': ctx.version, 'source_unchanged': source_unchanged,
               'fixtures': results, 'pass': everything}
    write_json(output / 'result.json', receipt)
    print(json.dumps({k: v['pass'] for k, v in results.items()}), 'source_unchanged', source_unchanged, flush=True)
    return 0 if everything else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except SetupError as e:
        print('SETUP ERROR: %s' % e, file=sys.stderr)
        sys.exit(2)
