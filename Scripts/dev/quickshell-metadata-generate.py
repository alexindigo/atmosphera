#!/usr/bin/env python3
"""Generate private, source-backed Quickshell lint inputs; never install runtime code.

Use the pinned source/toolchain recorded in the input family's manifest. The
source must be an untouched extracted archive. Source, build and output paths
must be separate, and are retained for independent replay.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess


def hashes(root, pattern='**/*'):
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.glob(pattern)) if p.is_file()}


def generate(args):
    original = hashes(args.source)
    installed = hashes(args.installed, '**/*.qmltypes')
    if hashlib.sha256(args.source_archive.read_bytes()).hexdigest() != args.source_archive_sha256:
        raise ValueError('source archive integrity mismatch')
    if args.output.exists() or (not args.reuse_build and (args.candidate.exists() or args.build.exists())):
        raise ValueError('candidate, build and output must be fresh paths')
    if not args.reuse_build:
        shutil.copytree(args.source, args.candidate)
    args.output.mkdir()
    commands = []

    def run(name, argv, seconds=120, cwd=None):
        argv = ['timeout', '--kill-after=10s', str(seconds), *map(str, argv)]
        commands.append(argv)
        result = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=seconds+15)
        (args.output / (name + '.log')).write_text(result.stdout + result.stderr)
        print(name, result.returncode, flush=True)
        if result.returncode:
            raise ValueError(f'{name} failed; see {args.output / (name + ".log")}')

    patches = [Path(__file__).with_name(name) for name in
               ('quickshell-metadata-producer.patch', 'quickshell-metadata-registration.patch')]
    if not args.reuse_build:
        for patch in patches:
            run(patch.stem + '-check', ['git', 'apply', '--unidiff-zero', '--check', patch], 20, args.candidate)
            run(patch.stem + '-apply', ['git', 'apply', '--unidiff-zero', patch], 20, args.candidate)
        run('configure', ['cmake', '-S', args.candidate, '-B', args.build, '-G', 'Ninja',
                          '-DCMAKE_BUILD_TYPE=Release', '-DDISTRIBUTOR=Arch Linux', '-DNO_PCH=ON',
                          *(['-DCMAKE_PREFIX_PATH=' + str(args.qt_prefix)] if args.qt_prefix else [])])
        targets = sorted(set(re.findall(r'^build [^\n]*?\b(qml_modules/[^\s]+\.qmltypes) \|',
                                       (args.build / 'build.ninja').read_text(), re.M)))
        if not targets:
            raise ValueError('no native metadata generation targets')
        run('generate', ['cmake', '--build', args.build, '--parallel', '2', '--target', *targets], 700)
    # Retain each module's public exports exactly. A separate all-source owner
    # inventory also describes registered classes from linked non-QML libraries.
    # Its exports are never exposed to consumers by the closure materializer.
    native = sorted(p for p in args.build.glob('src/**/meta_types/*_metatypes.json') if p.stat().st_size)
    qt = sorted(args.qt_metatypes.glob('*_metatypes.json'))
    for path in args.installed.rglob('qmldir'):
        destination = args.output / 'Quickshell' / path.relative_to(args.installed)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, destination)
    # Re-run the actual per-module registrar with the full source metatype
    # universe. This supplies inherited/default contracts omitted by lightweight
    # CMake dependencies, while each module keeps only its own public exports.
    for line in (args.build / 'build.ninja').read_text().splitlines():
        command = re.search(r'\S+/qmltyperegistrar --generate-qmltypes=', line)
        if not line.startswith('  COMMAND = ') or command is None:
            continue
        words = shlex.split(line[command.start():].split(' && ')[0])
        own = Path(words[-1])
        uri = next(w.split('=', 1)[1] for w in words if w.startswith('--import-name='))
        relative = Path(next(w.split('=', 1)[1] for w in words if w.startswith('--generate-qmltypes='))).relative_to(args.build / 'qml_modules/Quickshell')
        if relative.as_posix() not in installed:
            continue
        output = args.output / 'Quickshell' / relative
        output.parent.mkdir(parents=True, exist_ok=True)
        run(uri, [args.registrar, '--generate-qmltypes=' + str(output), '--import-name=' + uri,
                  '--major-version=0', '--minor-version=1',
                  '--foreign-types=' + ','.join(map(str, [p for p in native + qt if p != own])),
                  '-o', output.with_suffix('.cpp'), own], 30)
    # Inventory every source-owned metaobject, including unregistered internal
    # QObjects used in reflected slots/signals. Anonymous generation annotations
    # select descriptions, never add public exports or runtime registrations.
    owner_records = []
    compdb_run = subprocess.run(['timeout', '20s', 'ninja', '-C', str(args.build), '-t', 'compdb'], capture_output=True, text=True, timeout=25)
    if compdb_run.returncode:
        raise ValueError('cannot inspect native compilation inputs')
    compdb = json.loads(compdb_run.stdout)
    base_proofs = []
    for path in native:
        for record in json.loads(path.read_text()):
            record = dict(record)
            classes = []
            for component in record.get('classes', []):
                component = dict(component)
                infos = list(component.get('classInfos', []))
                if not any(info['name'] == 'QML.Element' for info in infos):
                    infos.append({'name': 'QML.Element', 'value': 'anonymous'})
                component['classInfos'] = infos
                # moc records the textual C++ template base, which may have no
                # own metaobject. Use its actual inherited metaobject identity,
                # proved by the native compiler, rather than inventing an alias.
                # QObject inheritance is first in moc's superclass list. Later
                # C++ mixins are not reflected prototypes (PwRegistry's second
                # base, for example, is the non-QObject PwObject template).
                for base in component.get('superClasses', [])[:1]:
                    if '<' not in base['name']:
                        continue
                    context = component['qualifiedClassName'].rpartition('::')[0]
                    namespace_open = 'namespace ' + context + ' {\n' if context else ''
                    namespace_close = '}\n' if context else ''
                    module_source = args.candidate / path.parent.parent.relative_to(args.build)
                    leaf_header = module_source / record['inputFile']
                    if not leaf_header.is_file():
                        raise ValueError(f'cannot locate owning native header: {leaf_header}')
                    compile_inputs = [entry for entry in compdb if Path(entry['file']).parent == module_source and entry['file'].endswith('.cpp')]
                    if not compile_inputs:
                        raise ValueError(f'no compilation contract for {leaf_header}')
                    entry = compile_inputs[0]
                    words = shlex.split(entry['command'])
                    argv = []
                    i = 0
                    while i < len(words):
                        if words[i] in ('-o', '-MT', '-MF'):
                            i += 2
                        elif words[i] in ('-c', '-MD', entry['file']):
                            i += 1
                        else:
                            argv.append(words[i]); i += 1
                    probe = args.output / ('base-proof-' + str(len(base_proofs)) + '.cpp')
                    code = '#include <type_traits>\n#include ' + json.dumps(str(leaf_header)) + '\n'
                    code += namespace_open
                    code += 'extern "C" const QMetaObject* atmosphera_inherited_metaobject() { return &' + base['name'] + '::staticMetaObject; }\n' + namespace_close
                    probe.write_text(code)
                    obj = probe.with_suffix('.o')
                    run('base-object-' + str(len(base_proofs)), [*argv, '-ffunction-sections', '-fdata-sections', '-c', probe, '-o', obj], 120, Path(entry['directory']))
                    reloc = subprocess.run(['timeout', '20s', 'objdump', '-r', '--section=.text.atmosphera_inherited_metaobject', str(obj)], capture_output=True, text=True, timeout=25)
                    (args.output / ('base-relocations-' + str(len(base_proofs)) + '.log')).write_text(reloc.stdout + reloc.stderr)
                    symbols = re.findall(r'^\S+\s+R_\S+\s+([^\s+]+)', reloc.stdout, re.M)
                    symbols = [s.split('-0x', 1)[0] for s in symbols]
                    if reloc.returncode or len(symbols) != 1:
                        raise ValueError(f'no unique compiler-derived metaobject relocation for {base["name"]}')
                    demangle = subprocess.run(['timeout', '10s', 'c++filt', symbols[0]], capture_output=True, text=True, timeout=15)
                    symbol = demangle.stdout.strip()
                    if demangle.returncode or not symbol.endswith('::staticMetaObject'):
                        raise ValueError(f'invalid metaobject identity: {symbol}')
                    owning_base = symbol.removesuffix('::staticMetaObject')
                    proof = '#include ' + json.dumps(str(leaf_header)) + '\n' + namespace_open
                    proof += 'static_assert(&' + owning_base + '::staticMetaObject == &' + base['name'] + '::staticMetaObject);\n' + namespace_close
                    probe = probe.with_name(probe.stem + '-assert.cpp')
                    probe.write_text(proof)
                    run('base-proof-' + str(len(base_proofs)), [*argv, '-fsyntax-only', probe], 120, Path(entry['directory']))
                    base_proofs.append({'class': component['qualifiedClassName'], 'textual_base': base['name'], 'reflected_base': owning_base, 'compiler_symbol': symbols[0], 'header': str(leaf_header), 'probe_sha256': hashlib.sha256(probe.read_bytes()).hexdigest(), 'object_sha256': hashlib.sha256(obj.read_bytes()).hexdigest()})
                    base['name'] = owning_base
                classes.append(component)
            record['classes'] = classes
            owner_records.append(record)
    owner_input = args.output / 'owner-metatypes.json'
    owner_input.write_text(json.dumps(owner_records, indent=2) + '\n')
    (args.output / 'compiler-base-proofs.json').write_text(json.dumps(base_proofs, indent=2) + '\n')
    run('owners', [args.registrar, '--generate-qmltypes=' + str(args.output / 'owners.qmltypes'),
                   '--import-name=Quickshell', '--major-version=0', '--minor-version=1',
                   '--foreign-types=' + ','.join(map(str, qt)),
                   '-o', args.output / 'owners-registrations.cpp', owner_input], 60)
    # Qt explicitly declared, non-reflected metatypes (for example opaque D-Bus
    # payload structs) have an owner but no QObject/gadget property contract.
    # Record declarations generically from source; unknown names still fail.
    terminals = {}
    for header in sorted(args.candidate.glob('src/**/*.hpp')):
        text = re.sub(r'//[^\n]*|/\*[\s\S]*?\*/', '', header.read_text())
        for declaration in re.findall(r'\bQ_DECLARE_METATYPE\s*\(\s*([\w:]+)\s*\)', text):
            provenance = {'header': header.relative_to(args.candidate).as_posix(),
                          'sha256': hashlib.sha256(header.read_bytes()).hexdigest()}
            if declaration in terminals and terminals[declaration] != provenance:
                raise ValueError(f'ambiguous native metatype declaration: {declaration}')
            terminals[declaration] = provenance
    (args.output / 'terminals.json').write_text(json.dumps(terminals, indent=2) + '\n')
    # Older Qt SDKs can expose C++ enum parameters without Q_ENUM registration.
    # They are real terminal types, not reflected QML enums. Discover only gaps
    # reached by the strict graph, locate the actual SDK owner, and ask the
    # matching compiler to prove the type is an enum. Never invent enum members
    # or accept a name just because its enclosing Qt class exists.
    spec = importlib.util.spec_from_file_location('native_metadata', Path(__file__).with_name('qml-native-metadata.py'))
    metadata = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(metadata)
    qt_prefix = args.qt_prefix or Path('/usr')
    qt_include = qt_prefix / 'include/qt6'
    qt_owners = {}
    for path in qt:
        for record in json.loads(path.read_text()):
            for component in record.get('classes', []):
                qt_owners.setdefault(component['qualifiedClassName'], set()).add(record['inputFile'])
    externals = metadata.external_types(qt_prefix / 'lib/qt6/qml')
    while True:
        try:
            metadata.resolve(args.output / 'Quickshell', None, args.output / 'owners.qmltypes', externals, terminals)
            break
        except metadata.MetadataError as error:
            match = re.fullmatch(r'unresolved native reference ([\w:]+) from .+', str(error))
            if match is None or '::' not in match[1]:
                raise
            identity = match[1]
            owner, _ = identity.rsplit('::', 1)
            headers = sorted({p for name in qt_owners.get(owner, set())
                              for p in qt_include.glob('*/' + name) if p.is_file()})
            if len(headers) != 1:
                raise ValueError(f'no unique SDK header for unresolved enum {identity}: {headers}') from error
            header = headers[0]
            number = len([v for v in terminals.values() if v.get('kind') == 'unreflected-sdk-enum'])
            probe = args.output / f'sdk-enum-{number}.cpp'
            probe.write_text('#include <type_traits>\n#include ' + json.dumps(str(header)) + '\n'
                             + 'static_assert(std::is_enum_v<' + identity + '>);\n')
            include_args = ['-I' + str(p) for p in [qt_include, *sorted(p for p in qt_include.iterdir() if p.is_dir())]]
            run(f'sdk-enum-{number}', ['c++', '-std=c++20', '-fPIC', *include_args, '-fsyntax-only', probe], 60)
            terminals[identity] = {'kind': 'unreflected-sdk-enum',
                                   'header': header.relative_to(qt_prefix).as_posix(),
                                   'sha256': hashlib.sha256(header.read_bytes()).hexdigest(),
                                   'probe_sha256': hashlib.sha256(probe.read_bytes()).hexdigest()}
            (args.output / 'terminals.json').write_text(json.dumps(terminals, indent=2) + '\n')
    if original != hashes(args.source) or installed != hashes(args.installed, '**/*.qmltypes'):
        raise ValueError('original source or installed metadata changed')
    manifest = {'source_sha256': original, 'patches': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in patches},
                'installed_qmltypes': installed, 'generated_qmltypes': hashes(args.output / 'Quickshell', '**/*.qmltypes'),
                'owners_sha256': hashlib.sha256((args.output / 'owners.qmltypes').read_bytes()).hexdigest(),
                'native_metatypes': hashes(args.build, 'src/**/meta_types/*_metatypes.json'),
                'qt_metatypes': hashes(args.qt_metatypes, '*_metatypes.json'),
                'candidate_source_sha256': hashes(args.candidate),
                'generator_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                'reused_build': args.reuse_build,
                'commands': commands, 'originals_unchanged': True}
    (args.output / 'generation.json').write_text(json.dumps(manifest, indent=2) + '\n')
    family = {'source_commit': args.source_commit, 'source_archive_sha256': args.source_archive_sha256,
              'installed_qmltypes': installed, 'patches': manifest['patches'],
              'generator_sha256': manifest['generator_sha256'],
               'qt_metatypes': manifest['qt_metatypes'], 'native_metatypes': manifest['native_metatypes'],
               'required_qt_metatypes': metadata.qt_contract_inputs(args.output / 'Quickshell', args.output / 'owners.qmltypes', args.qt_metatypes),
              'artifacts': {p.relative_to(args.output).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in [*args.output.glob('Quickshell/**/*.qmltypes'), *args.output.glob('Quickshell/**/qmldir'),
                                      args.output / 'owners.qmltypes', args.output / 'terminals.json']}}
    (args.output / 'manifest.json').write_text(json.dumps(family, indent=2) + '\n')
    print(f'generated {len(installed)} module descriptions and source owner inventory')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'candidate', 'build', 'output', 'installed'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--source-archive', type=Path, required=True)
    parser.add_argument('--source-archive-sha256', required=True)
    parser.add_argument('--qt-metatypes', type=Path, default=Path('/usr/lib/qt6/metatypes'))
    parser.add_argument('--registrar', type=Path, default=Path('/usr/lib/qt6/qmltyperegistrar'))
    parser.add_argument('--qt-prefix', type=Path, help='private version-matched Qt prefix; set its library path when invoking')
    parser.add_argument('--reuse-build', action='store_true', help='export retained, verified candidate/build without rebuilding')
    args = parser.parse_args()
    try:
        generate(args)
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        parser.exit(1, f'native generation: {error}\n')


if __name__ == '__main__':
    main()
