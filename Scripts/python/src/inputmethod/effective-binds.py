#!/usr/bin/env python3
"""Read-only effective binding inventory for InputMethodBinds.

Never executes configuration. Static scanners preserve include order and source
locations; incomplete coverage is data, not an empty list. Hyprland's live list
is authoritative, with generated records subtracted as a multiset, not by label.
"""
import argparse
from collections import Counter
import glob
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

MODS = {'super': 'Super', 'mod4': 'Super', 'win': 'Super', 'logo': 'Super',
        'mod': 'Super', 'ctrl': 'Ctrl', 'control': 'Ctrl', 'ctl': 'Ctrl',
        'alt': 'Alt', 'mod1': 'Alt', 'shift': 'Shift', 'mod5': 'Mod5'}
ORDER = ['Super', 'Ctrl', 'Alt', 'Shift', 'Mod5']
MASKS = {64: 'Super', 4: 'Ctrl', 8: 'Alt', 1: 'Shift', 128: 'Mod5'}
KEYS = {'space': 'space', 'spacebar': 'space', 'esc': 'escape', 'return': 'return',
        'enter': 'return', 'pgup': 'prior', 'page_up': 'prior', 'pageup': 'prior',
        'pgdown': 'next', 'pgdn': 'next', 'page_down': 'next', 'pagedown': 'next',
        'backtab': 'iso_left_tab', 'del': 'delete', 'plus': 'plus'}


def chord(mods, key):
    names = {MODS.get(m.lower(), m) for m in mods if m and m.lower() != 'none'}
    return '+'.join(sorted(names, key=lambda m: (ORDER.index(m) if m in ORDER else 99, m))
                    + [KEYS.get(key.strip().lower(), key.strip().lower())])


def combo(value):
    parts = value.split('+')
    return chord(parts[:-1], parts[-1])


def command(argv):
    return subprocess.run(list(map(str, argv)), capture_output=True, text=True, timeout=6)


def process_config(name, variable, default):
    """The actual compositor's CLI/env, not the shell process's guessed root."""
    p = command(['pgrep', '-u', str(os.getuid()), '-x', name])
    pids = p.stdout.split()
    if len(pids) != 1:
        return Path(os.environ.get(variable) or default), None
    proc = Path('/proc') / pids[0]
    args = proc.joinpath('cmdline').read_bytes().decode().split('\0')
    env = dict(s.split('=', 1) for s in proc.joinpath('environ').read_bytes().decode().split('\0') if '=' in s)
    for i, arg in enumerate(args):
        if arg in ('-c', '--config') and i + 1 < len(args):
            path = Path(args[i + 1])
            return (path if path.is_absolute() else proc.joinpath('cwd').resolve() / path), proc
        if arg.startswith('--config='):
            path = Path(arg.split('=', 1)[1])
            return (path if path.is_absolute() else proc.joinpath('cwd').resolve() / path), proc
    return Path(env.get(variable) or os.environ.get(variable) or default), proc


class Inventory:
    def __init__(self, generated=()):
        self.generated = {Path(p).resolve() for p in generated}
        self.entries = []
        self.unknown = []
        self.files = {}
        self.stack = []
        self.mode = ''
        self.variables = dict(os.environ)
        self.generated_modes = set()
        self.niri_mod = 'Super'

    def problem(self, text):
        if text not in self.unknown:
            self.unknown.append(text)

    def read(self, path):
        path = Path(path).expanduser().resolve()
        if path in self.generated and not path.exists():
            return path, ''
        if path in self.stack or len(self.stack) >= 64:
            self.problem(f'recursive include: {path}')
            return path, None
        try:
            text = path.read_text()
            self.files[str(path)] = text
            return path, text
        except (OSError, UnicodeError) as error:
            self.files[str(path)] = None
            self.problem(f'cannot read {path}: {error.strerror if isinstance(error, OSError) else error}')
            return path, None

    def add(self, path, line, mods, key, action, dispatcher='', arg='', flags=''):
        if key.lower().startswith(('code:', 'code_')):
            # A physical key cannot safely be equated to a keysym without the
            # compositor's active keymap. Do not silently call it unoccupied.
            self.problem(f'physical key identity unavailable at {path}:{line}')
        self.entries.append(dict(combo=chord(mods, key), mode=self.mode, file=str(path),
                                 line=line, action=action, dispatcher=dispatcher, arg=arg, flags=flags,
                                 own=path in self.generated))

    def expand(self, value, path, line, strict=True):
        for _ in range(32):
            expanded = re.sub(r'\$\{(\w+)\}|\$(\w+)',
                              lambda m: self.variables.get(m[1] or m[2], m[0]), value)
            if expanded == value:
                break
            value = expanded
        if strict and '$' in value:
            self.problem(f'unresolved variable at {path}:{line}')
        return os.path.expanduser(value)

    def conf(self, path, dialect, source_dir=None):
        path, text = self.read(path)
        if text is None:
            return
        self.stack.append(path)
        if path in self.generated:
            self.generated_modes.add(self.mode)
        try:
            for number, raw in enumerate(text.splitlines(), 1):
                # Both parsers have line comments. Hyprlang escapes a literal # as ##.
                line = raw.replace('##', '\x00').split('#', 1)[0].replace('\x00', '#').strip() if dialect == 'hypr' else raw.split('#', 1)[0].strip()
                if '=' not in line:
                    continue
                name, value = (s.strip() for s in line.split('=', 1))
                if name.startswith('$') and dialect == 'hypr':
                    self.variables[name[1:]] = self.expand(value, path, number)
                    continue
                value = self.expand(value, path, number, name in ('source', 'source-optional'))
                if name in ('source', 'source-optional'):
                    target = Path(value)
                    if not target.is_absolute():
                        # Mango 0.17.5 ./ is CLI-root-relative, never include-relative.
                        target = (source_dir if dialect == 'mango' else path.parent) / target
                    matches = sorted(glob.glob(str(target))) if dialect == 'hypr' else [str(target)]
                    if not matches:
                        self.problem(f'missing include {target} at {path}:{number}')
                    for included in matches:
                        self.conf(included, dialect, source_dir)
                elif name == ('keymode' if dialect == 'mango' else 'submap'):
                    self.mode = '' if value in ('default', 'reset') else value
                elif name == 'unbind' and dialect == 'hypr':
                    fields = [s.strip() for s in value.split(',', 1)]
                    if len(fields) == 2:
                        identity = chord(re.split(r'[ +_]+', fields[0]), fields[1])
                        self.entries = [e for e in self.entries if (e['combo'], e['mode']) != (identity, self.mode)]
                elif re.fullmatch(r'bind[a-z]*', name):
                    flags = name[4:]
                    limit = 4 if dialect == 'hypr' and 'd' in flags else 3
                    fields = [s.strip() for s in value.split(',', limit)]
                    if len(fields) <= limit - 1:
                        self.problem(f'unparsed binding at {path}:{number}')
                        continue
                    mods, key = fields[:2]
                    if '$' in mods or '$' in key:
                        self.problem(f'unresolved chord at {path}:{number}')
                    dispatcher = fields[3] if limit == 4 else fields[2]
                    arg = fields[limit] if len(fields) > limit else ''
                    self.add(path, number, re.split(r'[ +_]+', mods), key,
                             (dispatcher + ' ' + arg).strip(), dispatcher, arg, flags)
                    if path in self.generated:
                        self.generated_modes.add(self.mode)
                if path in self.generated:
                    self.generated_modes.add(self.mode)
        finally:
            self.stack.pop()

    def niri(self, path):
        path, text = self.read(path)
        if text is None:
            return
        self.stack.append(path)
        try:
            nodes = kdl_nodes(text)
            if sum(name == 'binds' for name, _, _, _ in nodes) > 1:
                self.problem(f'duplicate binds block at {path}')
            for name, args, children, line in nodes:
                if name == 'include':
                    filenames = [t for t in args if t.startswith('"')]
                    if len(filenames) != 1:
                        self.problem(f'unparsed include at {path}:{line}')
                        continue
                    target = Path(json.loads(filenames[0])).expanduser()
                    self.niri(target if target.is_absolute() else path.parent / target)
                elif name == 'binds':
                    for key, props, actions, bind_line in children:
                        if path in self.generated:
                            continue
                        parts = key.split('+')
                        action = '; '.join(' '.join([n] + a) for n, a, _, _ in actions)
                        self.add(path, bind_line, parts[:-1], parts[-1], action)
                        self.entries[-1]['niri_parts'] = parts
                elif name == 'input':
                    for option, values, _, _ in children:
                        if option == 'mod-key' and len(values) == 1:
                            self.niri_mod = json.loads(values[0]) if values[0].startswith('"') else values[0]
        except (ValueError, IndexError) as error:
            self.problem(f'unparsed KDL at {path}: {error}')
        finally:
            self.stack.pop()


def kdl_nodes(text):
    """Tokenize KDL structure, preserving strings, comments, /- and line numbers.

    Only node structure is interpreted, not arbitrary config values. Unsupported
    string syntax fails closed rather than hiding includes/binds behind regexes.
    """
    tokens = []
    i, line = 0, 1
    while i < len(text):
        start = i
        c = text[i]
        if text.startswith('//', i):
            i = text.find('\n', i)
            if i < 0:
                break
        elif text.startswith('/*', i):
            depth = 1
            i += 2
            while depth:
                if i >= len(text):
                    raise ValueError('unterminated comment')
                if text.startswith('/*', i):
                    depth += 1
                    i += 2
                elif text.startswith('*/', i):
                    depth -= 1
                    i += 2
                else:
                    line += text[i] == '\n'
                    i += 1
        elif text.startswith('/-', i):
            tokens.append(('/-', line))
            i += 2
        elif c == '\\' and re.match(r'\\[ \t]*(?://[^\n]*)?\n', text[i:]):
            m = re.match(r'\\[ \t]*(?://[^\n]*)?\n', text[i:])
            i += len(m[0])
            line += 1
        elif re.match(r'(?:r\#*|\#+)"', text[i:]):
            opening = re.match(r'(?:r\#*|\#+)"', text[i:])[0]
            ending = '"' + opening.count('#') * '#'
            content = i + len(opening)
            end = text.find(ending, content)
            if end < 0:
                raise ValueError('unterminated raw string')
            token = text[content:end]
            tokens.append((json.dumps(token), line))
            i = end + len(ending)
            line += token.count('\n')
        elif c == '"':
            i += 1
            while i < len(text):
                if text[i] == '\\':
                    i += 2
                elif text[i] == '"':
                    i += 1
                    break
                else:
                    i += 1
            token = text[start:i]
            decoded = json.loads(re.sub(r'\\u\{([0-9a-fA-F]+)\}', lambda m: chr(int(m[1], 16)), token))
            tokens.append((json.dumps(decoded), line))
            line += token.count('\n')
        elif c in '{};=\n':
            tokens.append((c, line))
            line += c == '\n'
            i += 1
        elif c.isspace():
            i += 1
        else:
            while i < len(text) and not text[i].isspace() and text[i] not in '{};="':
                i += 1
            tokens.append((text[start:i], line))
        if i == start:
            raise ValueError('unsupported token')

    def parse(index, nested=False):
        nodes = []
        while index < len(tokens):
            name, number = tokens[index]
            index += 1
            if name in (';', '\n'):
                continue
            if name == '}':
                if not nested:
                    raise ValueError('unexpected closing brace')
                return nodes, index
            disabled = name == '/-'
            if disabled:
                name, number = tokens[index]
                index += 1
            if name.startswith(('r#', '#', '"""')):
                raise ValueError('unsupported raw string')
            if name.startswith('"'):
                name = json.loads(name)
            args, children = [], []
            while index < len(tokens):
                t, _ = tokens[index]
                if t in (';', '\n', '}'):
                    break
                index += 1
                if t == '{':
                    children, index = parse(index, True)
                    break
                args.append(t)
            if not disabled:
                nodes.append((name, args, children, number))
        if nested:
            raise ValueError('unclosed node')
        return nodes, index
    return parse(0)[0]


def live_identity(record):
    return (record['combo'], record['mode'])


def hypr_live(scan, rows, lua_file):
    """Subtract only expected generated occurrences. Surplus is always external."""
    expected = Counter((e['combo'], e['mode'], e['dispatcher'], e['arg'])
                       for e in scan.entries if e['own'])
    lua = Counter()
    try:
        text = lua_file.read_text()
    except FileNotFoundError:
        text = ''
    except OSError as error:
        scan.problem(f'cannot read generated Lua ownership: {error}')
        text = ''
    for line in text.splitlines():
        # This is exclusively our generated file, not a scan of user Lua.
        m = re.match(r'hl\.bind\(("(?:[^"\\]|\\.)*")\s*,', line)
        if m:
            lua[(combo(json.loads(m[1]).replace(' ', '')), '')] += 1
    sources = {}
    for entry in scan.entries:
        if not entry['own']:
            sources.setdefault((entry['combo'], entry['mode'], entry['dispatcher'], entry['arg']), []).append(entry)
    external = []
    for row in rows:
        mask = int(row['modmask'])
        key = row['key']
        if not key and row.get('keycode'):
            scan.problem('physical key identity unavailable in live Hyprland binding')
            continue
        mods = [name for bit, name in MASKS.items() if mask & bit]
        if mask & ~sum(MASKS):
            mods.append(f'mask:{mask & ~sum(MASKS)}')
        identity = chord(mods, key)
        mode = row.get('submap') or ''
        dispatcher, arg = row['dispatcher'], row.get('arg', '')
        if dispatcher == '__lua' and lua[(identity, mode)] > 0:
            lua[(identity, mode)] -= 1
            continue
        full = (identity, mode, dispatcher, arg)
        if dispatcher != '__lua' and expected[full] > 0:
            expected[full] -= 1
            continue
        attributed = sources.get(full, [])
        entry = dict(attributed.pop(0)) if attributed and dispatcher != '__lua' else dict(
            combo=identity, mode=mode, file='', line=0, own=False,
            action='a Lua function' if dispatcher == '__lua' else (dispatcher + ' ' + arg).strip())
        # Registry refs and callback bodies never enter diagnostics/public data.
        entry.pop('arg', None)
        entry.pop('dispatcher', None)
        external.append(entry)
    return external


def diagnostic(entry):
    identity = entry['combo'].split('+')
    identity[-1] = identity[-1].capitalize() if len(identity[-1]) > 1 else identity[-1].upper()
    text = '+'.join(identity) + ' is bound by ' + entry['action']
    if entry['file']:
        text += f' in {entry["file"]}:{entry["line"]}'
    else:
        text += ' (source unavailable — live Hyprland binding)'
    return text + (' [mode: ' + entry['mode'] + ']' if entry['mode'] else ' [mode: default]')


def inventory(dialect, directory, environment='none'):
    directory = Path(directory)
    route = False
    if dialect == 'hypr':
        helper = Path(__file__).resolve().parents[3] / 'bash/hypr-config-resolve.sh'
        resolved = command(['bash', helper])
        if resolved.returncode:
            raise ValueError(resolved.stderr.strip() or 'Hyprland target unavailable')
        language, root, parent = resolved.stdout.splitlines()
        directory = Path(parent)
        route = language == 'lua'
    suffix = 'kdl' if dialect == 'niri' else 'conf'
    generated = directory / ('atmosphera-input.' + suffix)
    scan = Inventory([generated])
    if dialect == 'mango':
        default = Path.home() / '.config/mango/config.conf'
        if not default.exists():
            default = Path('/etc/mango/config.conf')
        root, proc = process_config('mango', '_ATMOSPHERA_NO_MANGO_ENV', default)
        cli_root = proc is not None and any(a in ('-c', '--config') or a.startswith('--config=')
                                           for a in proc.joinpath('cmdline').read_bytes().decode().split('\0'))
        source_dir = root.parent if cli_root else Path.home() / '.config/mango'
        scan.conf(root, 'mango', source_dir)
        modes = scan.generated_modes or {''}
        entries = [e for e in scan.entries if not e['own'] and (e['mode'] in modes or e['mode'] == 'common')]
    elif dialect == 'niri':
        session = directory / 'atmosphera-session.kdl'
        if session.exists():
            scan.niri(session)
        else:
            root, _ = process_config('niri', 'NIRI_CONFIG', directory / 'config.kdl')
            scan.niri(root)
            for name in ['atmosphera.kdl', 'atmosphera-i18n.kdl'] + (['atmosphera-shortcuts-macos.kdl'] if environment == 'macos' else []):
                if (directory / name).exists():
                    scan.niri(directory / name)
        effective = {}
        for entry in scan.entries:
            if entry['own']:
                continue
            parts = entry.pop('niri_parts')
            entry['combo'] = chord([scan.niri_mod if m.lower() == 'mod' else m for m in parts[:-1]], parts[-1])
            effective[entry['combo']] = entry
        entries = list(effective.values())
    else:
        if language == 'hyprlang':
            active_root, _ = process_config('Hyprland', 'HYPRLAND_CONFIG', root)
            if active_root.suffix == '.conf':
                scan.conf(active_root, 'hypr')
            if str(generated.resolve()) not in scan.files:
                # The generated file is the ownership expectation even while a
                # reload is in flight; never infer ownership from descriptions.
                scan.conf(generated, 'hypr')
        rows = command(['hyprctl', 'binds', '-j'])
        if rows.returncode == 0:
            # Static coverage is only attribution when live occupancy is complete.
            scan.unknown = []
            entries = hypr_live(scan, json.loads(rows.stdout), directory / 'atmosphera-input.lua' if route else directory / '.no-generated-lua')
        else:
            if language == 'lua':
                scan.problem('Lua coverage unknown without a running Hyprland compositor')
            entries = [e for e in scan.entries if not e['own']]
    owners = {}
    for entry in entries:
        owners.setdefault(entry['combo'], diagnostic(entry))
    return dict(owners=owners, unknown='; '.join(scan.unknown), entries=entries, writable=True,
                directory=str(directory), route=route, fcitx5=shutil.which('fcitx5') is not None)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--dialect', choices=['mango', 'niri', 'hypr'], required=True)
    ap.add_argument('--directory', type=Path, required=True)
    ap.add_argument('--environment', default='none')
    args = ap.parse_args()
    try:
        result = inventory(args.dialect, args.directory, args.environment)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        result = dict(owners={}, entries=[], unknown=str(error), writable=False, directory=str(args.directory),
                      route=False, fcitx5=shutil.which('fcitx5') is not None)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))


if __name__ == '__main__':
    main()
