#!/usr/bin/env python3
"""Check direct singleton calls against source declarations and installed types.

No singleton is instantiated and no method is invoked. Dynamic/computed access
is left to runtime tests; literal direct calls must name a declared member.
"""
import argparse
import importlib.util
from pathlib import Path
import re


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


IDENTIFIERS = load("identifiers", "qml-identifiers.py")
METADATA = load("metadata", "qml-native-metadata.py")


def code(text):
    _, spans = IDENTIFIERS.lex(text)
    result = list(text)
    for _, start, end in spans:
        result[start:end] = ['\n' if char == '\n' else ' ' for char in text[start:end]]
    return ''.join(result)


def source_members(text):
    """Only declarations on the singleton's root object, not its children."""
    clean = code(text)
    depth, depths = 0, []
    for char in clean:
        depths.append(depth)
        depth += (char == '{') - (char == '}')
    patterns = (r'\bfunction\s+(\w+)\s*\(', r'\bsignal\s+(\w+)\b',
                r'\bproperty\s+(?:list\s*<[^>]+>|\w+)\s+(\w+)\b')
    declared = [{match[1] for match in re.finditer(pattern, clean)
                 if depths[match.start()] == 1} for pattern in patterns]
    members = set.union(*declared)
    # QML-generated property change signals can themselves be called.
    members.update(name + 'Changed' for name in declared[2])
    return members | {'destroy', 'toString'}


def native_singletons(qml_dir):
    descriptions = {}
    components = []
    for path in (qml_dir / 'Quickshell').rglob('*.qmltypes'):
        for component in METADATA.parse(path.read_text()).children:
            components.append(component)
            if not component.values.get('isTypeOpaque'):
                descriptions[component.values['name']] = component
    exports = {}
    for component in components:
        if not component.values.get('isSingleton'):
            continue
        members, owner, seen = {'destroy', 'toString'}, component, set()
        while owner is not None and owner.values['name'] not in seen:
            seen.add(owner.values['name'])
            members.update(child.values['name'] for child in owner.children
                           if child.kind in {'Method', 'Signal', 'Property'})
            owner = descriptions.get(owner.values.get('prototype'))
        for export in component.values.get('exports', []):
            module, name = export.split(' ')[0].rsplit('/', 1)
            exports.setdefault(module, {})[name] = members
    if 'Quickshell' not in exports or 'Quickshell' not in exports['Quickshell']:
        raise ValueError('expected installed Quickshell singleton type metadata')
    return exports


def quickshell_members(qml_dir):
    return native_singletons(qml_dir)['Quickshell']['Quickshell']


def check(root, paths, qml_dir):
    native = native_singletons(qml_dir)
    singletons = {}
    for path in root.rglob('*.qml'):
        if '.git' in path.parts:
            continue
        text = path.read_text()
        if re.search(r'^\s*pragma\s+Singleton\b', code(text), re.M):
            singletons[path.resolve()] = source_members(text)
    failures, checked = [], 0
    for path in paths:
        text = path.read_text()
        clean = code(text)
        names = {}
        for match in re.finditer(r'^\s*\.?import\s+(Quickshell(?:\.\w+)*)(?:\s+\d+\.\d+)?(?:\s+as\s+(\w+))?\s*$', clean, re.M):
            prefix = match[2] + '.' if match[2] else ''
            names.update({prefix + name: members for name, members in native.get(match[1], {}).items()})
        directories = [(path.parent, '')]
        for match in re.finditer(r'^\s*\.?import\s+(qs(?:\.\w+)+)(?:\s+\d+\.\d+)?(?:\s+as\s+(\w+))?', clean, re.M):
            directories.append((root.joinpath(*match[1].split('.')[1:]), (match[2] + '.') if match[2] else ''))
        for directory, prefix in directories:
            for source, members in singletons.items():
                if source.parent == directory.resolve():
                    names[prefix + source.stem] = members
        for name, members in names.items():
            pattern = r'(?<![\w$.])' + re.escape(name) + r'\s*\.\s*(\w+)\s*\('
            for match in re.finditer(pattern, clean):
                checked += 1
                if match[1] not in members:
                    failures.append(f'{path}:{clean.count(chr(10), 0, match.start()) + 1}: '
                                    f'unknown singleton call {name}.{match[1]}')
    return failures, checked


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--qml-dir', type=Path, default=Path('/usr/lib/qt6/qml'))
    parser.add_argument('paths', nargs='*', type=Path)
    args = parser.parse_args()
    paths = args.paths or [args.root]
    inputs = sorted({file.resolve() for path in paths for file in
                     (path.rglob('*') if path.is_dir() else [path])
                     if file.suffix in {'.qml', '.js'} and '.git' not in file.parts})
    if not inputs:
        parser.error('no QML/JS inputs')
    failures, checked = check(args.root.resolve(), inputs, args.qml_dir)
    for failure in failures:
        print(failure)
    print(f'Singleton calls: {checked} checked, {len(failures)} unknown')
    return bool(failures)


if __name__ == '__main__':
    raise SystemExit(main())
