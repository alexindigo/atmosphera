#!/usr/bin/env python3
"""Generate tooling-only ConfigQml descriptions with a private matching Qt SDK.

No library is compiled or installed. In particular, generating descriptions for
an older SDK does not claim runtime support for ConfigQml's private Qt ABI.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def generate(source, qt, output, reference):
    source, qt = source.resolve(), qt.resolve()
    output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, LD_LIBRARY_PATH=str(qt.parent))
    commands = []

    def run(argv):
        commands.append(list(map(str, argv)))
        return subprocess.check_output(list(map(str, argv)), cwd=source, env=env, stderr=subprocess.PIPE).decode()

    version = run([qt / 'moc', '-v']).strip().removeprefix('moc ')
    include = qt.parents[1] / 'include/qt6'
    includes = [include, *sorted(p for p in include.glob('Qt*') if p.is_dir()), source]
    flags = [f'-I{p}' for p in includes]
    groups = {'core': [], 'qml': []}
    for header in sorted(source.glob('*.h')):
        group = 'qml' if header.name.startswith('configqml') or header.stem in ('configfacade', 'confignamespace') else 'core'
        moc = output / ('moc_' + header.stem + '.cpp')
        run([qt / 'moc', '--output-json', '-DQT_CORE_LIB', '-DQT_QML_LIB', *flags, '-o', moc, header])
        if moc.with_suffix('.cpp.json').exists():
            groups[group].append(moc.with_suffix('.cpp.json'))
    for group, paths in groups.items():
        if not paths:
            raise ValueError(f'no {group} metaobjects generated')
        run([qt / 'moc', '--collect-json', '-o', output / (group + '.json'), *paths])
    foreign = [qt / 'metatypes' / ('qt6' + name + '_metatypes.json') for name in ('core', 'qml', 'network')]
    run([qt / 'qmltyperegistrar', '--generate-qmltypes=' + str(output / 'configqml.qmltypes'),
         '--import-name=ConfigQml', '--major-version=1', '--minor-version=0',
         '--foreign-types=' + ','.join(map(str, [*foreign, output / 'core.json'])),
         '-o', output / 'registrations.cpp', output / 'qml.json'])
    # Module identity/plugin layout is unchanged; copy the real CMake output.
    (output / 'qmldir').write_bytes((reference / 'qmldir').read_bytes())
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    manifest = json.loads((reference / 'manifest.json').read_text())
    manifest.pop('package', None)
    manifest.update(qtVersion=version, qtMetatypes={p.name: digest(p) for p in foreign},
                    artifacts={name: digest(output / name) for name in ('configqml.qmltypes', 'qmldir')},
                    producer='configqml-metadata-generate.py (moc and qmltyperegistrar; tooling only)')
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (output / 'generation.json').write_text(json.dumps(dict(commands=commands,
        sourceHeaders={p.name: digest(p) for p in source.glob('*.h')},
        tools={str(qt / name): digest(qt / name) for name in ('moc', 'qmltyperegistrar')},
        source=str(source), qt=str(qt)), indent=2) + '\n')
    print(json.dumps(manifest), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'qt', 'output', 'reference'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    generate(args.source, args.qt, args.output.resolve(), args.reference)
