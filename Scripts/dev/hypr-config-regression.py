#!/usr/bin/env python3
"""Guest-only Hyprland config regression, including real tty1 starts and IPC.

Run only in arch-hypr-atmosphera-cc-hypr on ark.home, with TMPDIR under
/home/tester/Projects/atmosphera-cc. --source is read-only; --output must be
fresh. Scratch HOME/XDG trees and all evidence remain inside --output.
Uses C2's explicit-config tty1 session selector; restores it in finally.
Setup's systemctl probe is isolated (no service enabling); real sessions load
the complete generated systemd-route fragment with the existing, unwired target.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

WORKSPACE = Path('/home/tester/Projects/atmosphera-cc')
SELECTOR = WORKSPACE / 'runtime/c2-session-config-path'


def sh(argv, env=None, check=True):
    p = subprocess.run([str(a) for a in argv], env=env, capture_output=True, text=True, timeout=45)
    if check and p.returncode:
        raise RuntimeError(f'{argv}: {p.returncode}: {p.stdout}{p.stderr}')
    return p


def digest(path):
    return {str(p.relative_to(path)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(path.rglob('*')) if p.is_file()}


def session(config):
    sh(['sudo', '-n', 'systemctl', 'stop', 'getty@tty1.service'])
    SELECTOR.write_text(str(config) + '\n')
    sh(['sudo', '-n', 'systemctl', 'start', 'getty@tty1.service'])
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        p = sh(['hyprctl', 'instances', '-j'], check=False)
        try:
            instances = json.loads(p.stdout)
            if len(instances) == 1:
                env = dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE=instances[0]['instance'],
                           WAYLAND_DISPLAY=instances[0]['wl_socket'])
                version = sh(['hyprctl', 'version'], env, check=False)
                if version.returncode == 0:
                    # Let initial parsing finish before observing the consumer.
                    time.sleep(2)
                    errors = sh(['hyprctl', 'configerrors'], env)
                    return {'ipc': True, 'configerrors': errors.stdout.strip(),
                            'instance': instances[0], 'version': version.stdout}
        except (ValueError, KeyError):
            pass
        time.sleep(0.5)
    raise RuntimeError(f'Hyprland IPC did not respond for {config}')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source', required=True, type=Path)
    ap.add_argument('--output', required=True, type=Path)
    args = ap.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if not output.is_relative_to(WORKSPACE) or output.exists():
        ap.error('--output must be fresh and inside the guest disk workspace')
    if not Path(os.environ.get('TMPDIR', '/')).resolve().is_relative_to(WORKSPACE):
        ap.error('set disk-backed TMPDIR inside the guest workspace')
    if Path('/sys/class/net').exists():
        macs = [p.read_text().strip() for p in Path('/sys/class/net').glob('*/address')]
        if '52:54:00:5f:98:a7' not in macs:
            ap.error('wrong guest: expected arch-hypr-atmosphera-cc-hypr')
    os.environ.update(XDG_RUNTIME_DIR='/run/user/1000',
                      DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/1000/bus')
    # The generated startup may start this target, but must not launch an installed shell.
    wants = Path('/home/tester/.config/systemd/user/hyprland-session.target.wants/atmosphera.service')
    if wants.exists() or wants.is_symlink() or sh(['pgrep', '-x', 'qs'], check=False).returncode == 0:
        ap.error('requires C2 baseline: no shell or Atmosphera target wants link')
    sh(['Hyprland', '--version'])
    output.mkdir(parents=True)
    before_selector = SELECTOR.read_bytes()
    before_config = digest(Path('/home/tester/.config/hypr'))
    target_active = sh(['systemctl', '--user', 'is-active', 'hyprland-session.target'], check=False).returncode == 0
    result = {'source': str(source), 'output': str(output), 'cases': [], 'restoration': {}, 'passed': False}
    setups = {}

    def record(number, title, fn):
        rec = {'case': number, 'title': title, 'passed': False}
        try:
            rec['observed'] = fn()
            rec['passed'] = True
        except Exception as e:
            rec['error'] = f'{type(e).__name__}: {e}'
        result['cases'].append(rec)
        print(f'case {number}: {"PASS" if rec["passed"] else "FAIL"} {title}', flush=True)

    def fixture(name, language=None, both=False, custom=False):
        base = output / name
        home = base / 'home'
        xdg = base / ('custom-config' if custom else 'home/.config')
        cfg = xdg / 'hypr'
        cfg.mkdir(parents=True)
        home.mkdir(exist_ok=True)
        bin_dir = base / 'bin'
        bin_dir.mkdir()
        # Exercise the complete systemd config grammar without changing user-manager wiring.
        (bin_dir / 'systemctl').write_text('#!/bin/sh\ncase "$*" in *LoadState*) echo loaded;; esac\nexit 0\n')
        (bin_dir / 'systemctl').chmod(0o755)
        (bin_dir / 'hyprctl').write_text('#!/bin/sh\nexit 0\n')
        (bin_dir / 'hyprctl').chmod(0o755)
        env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(xdg),
                   PATH=f'{bin_dir}:' + os.environ['PATH'])
        env.pop('HYPRLAND_CONFIG', None)
        env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
        if language == 'hyprlang' or both:
            (cfg / 'hyprland.conf').write_text('# user sentinel conf\nmonitor = , preferred, auto, 1\n')
        if language == 'lua' or both:
            (cfg / 'hyprland.lua').write_text('-- user sentinel lua\n')
        f = {'env': env, 'cfg': cfg, 'base': base}
        setups[name] = f
        return f

    def setup(f):
        p = sh(['bash', source / 'Scripts/bash/atmosphera-hypr-setup'], f['env'])
        with (f['base'] / 'setup.log').open('a') as log:
            log.write(p.stdout + p.stderr)

    def check_setup(name, language, both=False, custom=False):
        f = fixture(name, None if name == 'fresh' else language, both, custom)
        setup(f)
        cfg = f['cfg']
        suffix = 'lua' if language == 'lua' else 'conf'
        root = cfg / f'hyprland.{suffix}'
        assert root.exists(), f'missing {root}'
        text = root.read_text()
        assert text.count('require("atmosphera")' if suffix == 'lua' else f'source = {cfg}/atmosphera.conf') == 1, text
        assert (cfg / f'atmosphera.{suffix}').exists()
        assert (cfg / f'atmosphera-input.{suffix}').exists()
        if not both:
            assert not (cfg / ('hyprland.conf' if suffix == 'lua' else 'hyprland.lua')).exists()
        if suffix == 'conf':
            fragment = (cfg / 'atmosphera.conf').read_text()
            assert 'layerrule = blur on, match:namespace ^atmosphera-.*$' in fragment
            assert f'source = {cfg}/atmosphera-input.conf' in fragment
        if name != 'fresh':
            assert f'user sentinel {suffix}' in text
        return {'root': str(root), 'files': digest(cfg)}

    def idempotent():
        observed = {}
        for name in ('fresh', 'conf', 'lua'):
            f = setups[name]
            before = digest(f['cfg'])
            setup(f)
            after = digest(f['cfg'])
            assert before == after, name
            observed[name] = after
        return observed

    def path_and_version_contract():
        observed = {'xdg': check_setup('xdg', 'hyprlang', custom=True)}
        # Characterize the decision boundary without installing another compositor.
        # Real grammar/IPC proof above still runs on the installed 0.56.2 binary.
        for version, language in (('0.53.0', 'hyprlang'), ('0.54.0', 'hyprlang'),
                                  ('0.55.0', 'lua'), ('0.52.0', None), ('unknown', None)):
            f = fixture('version-' + version)
            binary = f['base'] / 'bin/Hyprland'
            binary.write_text(f'#!/bin/sh\nprintf "Hyprland {version}\\n"\n')
            binary.chmod(0o755)
            p = sh(['bash', source / 'Scripts/bash/atmosphera-hypr-setup'], f['env'], check=False)
            (f['base'] / 'setup.log').write_text(p.stdout + p.stderr)
            if language is None:
                assert p.returncode != 0 and not list(f['cfg'].iterdir()), (version, p.stdout, p.stderr)
            else:
                assert p.returncode == 0, p.stderr
                suffix = 'lua' if language == 'lua' else 'conf'
                assert (f['cfg'] / f'hyprland.{suffix}').is_file()
                assert not (f['cfg'] / ('hyprland.conf' if suffix == 'lua' else 'hyprland.lua')).exists()
            observed[version] = {'rc': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr}
        for language in ('lua', 'hyprlang'):
            f = fixture('explicit-' + language, both=True)
            default_before = digest(f['cfg'])
            directory = f['base'] / 'explicit directory'
            directory.mkdir()
            suffix = 'lua' if language == 'lua' else 'conf'
            root = directory / f'custom.{suffix}'
            root.write_text('-- explicit sentinel\n' if suffix == 'lua' else '# explicit sentinel\n')
            f['env']['HYPRLAND_CONFIG'] = str(root)
            setup(f)
            assert digest(f['cfg']) == default_before, 'explicit root must override both default roots'
            assert (directory / f'atmosphera-input.{suffix}').exists()
            live = session(root)
            assert not live['configerrors'], live
            observed['explicit-' + language] = live
        return observed

    def starts():
        observed = {}
        for name in ('fresh', 'conf', 'lua'):
            cfg = setups[name]['cfg']
            root = cfg / ('hyprland.lua' if (cfg / 'hyprland.lua').exists() else 'hyprland.conf')
            observed[name] = session(root)
            (output / f'start-{name}.json').write_text(json.dumps(observed[name], indent=2))
        assert all(v['ipc'] and not v['configerrors'] for v in observed.values()), observed
        return observed

    def negative():
        f = setups['conf']
        frag = f['cfg'] / 'atmosphera.conf'
        original = frag.read_text()
        frag.write_text(re.sub(r'^layerrule = .*$', 'layerrule = blur, namespace:^atmosphera-.*$', original, flags=re.M))
        try:
            observed = session(f['cfg'] / 'hyprland.conf')
            assert observed['configerrors'], observed
            return observed
        finally:
            frag.write_text(original)

    def templates():
        observed = {}
        for name in ('fresh', 'conf'):
            f = setups[name]
            cfg = f['cfg']
            suffix = 'lua' if name == 'fresh' else 'conf'
            theme = cfg / 'noctalia' / f'noctalia-colors.{suffix}'
            theme.parent.mkdir()
            # Render shipped templates, so actual syntax rather than empty includes is loaded.
            template = (source / f'Assets/Templates/hyprland.{suffix}').read_text()
            rendered = re.sub(r'\{\{.*?\}\}', '123456', template)
            theme.write_text(rendered)
            for _ in range(2):
                sh(['bash', source / 'Scripts/bash/template-apply.sh', 'hyprland'], f['env'])
            root = cfg / f'hyprland.{suffix}'
            assert root.read_text().count(f'noctalia-colors.{suffix}') == 1
            assert not (cfg / ('hyprland.conf' if suffix == 'lua' else 'hyprland.lua')).exists()
            observed[name] = session(root)
            assert not observed[name]['configerrors'], observed[name]
        return observed

    try:
        record(1, 'fresh 0.56 selects Lua, no hyprland.conf', lambda: check_setup('fresh', 'lua'))
        record(2, 'existing hyprlang preserves content, modern grammar', lambda: check_setup('conf', 'hyprlang'))
        record(3, 'existing Lua preserves content, one require', lambda: check_setup('lua', 'lua'))
        record(4, 'both roots prefer Lua', lambda: check_setup('both', 'lua', both=True))
        record(5, 'custom XDG, explicit roots and version/refusal boundaries', path_and_version_contract)
        record(6, 'setup twice byte-idempotent in cases 1–3', idempotent)
        record(7, 'real starts cases 1–3, responsive IPC and empty configerrors', starts)
        record(8, 'original rule negative control yields configerrors', negative)
        record(9, 'templates follow resolved language and parse after real starts', templates)
    finally:
        try:
            restored = session(Path(before_selector.decode().strip()))
            SELECTOR.write_bytes(before_selector)
            if not target_active:
                sh(['systemctl', '--user', 'stop', 'hyprland-session.target'])
            after_config = digest(Path('/home/tester/.config/hypr'))
            result['restoration'] = {'selector_sha256': hashlib.sha256(SELECTOR.read_bytes()).hexdigest(),
                                     'config_before': before_config, 'config_after': after_config,
                                     'ipc': restored['ipc'], 'configerrors': restored['configerrors'],
                                     'passed': before_config == after_config and not restored['configerrors']}
        except Exception as e:
            result['restoration'] = {'passed': False, 'error': str(e)}
        result['passed'] = (len(result['cases']) == 9 and all(c['passed'] for c in result['cases'])
                            and result['restoration'].get('passed') is True)
        (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
