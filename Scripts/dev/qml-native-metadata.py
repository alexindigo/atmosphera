#!/usr/bin/env python3
"""Materialize Quickshell's cross-module native type closure for QML tooling.

qmltyperegistrar's opaque foreign declarations shadow their concrete owners,
and circular qmldir dependencies can resolve against a partly populated scope.
Copy authoritative descriptions (without foreign QML exports) into each native
scope, recursively. Runtime imports and installed metadata are never modified.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil


class MetadataError(ValueError):
    pass


# qmltypes is a declarative data format, not arbitrary QML/JavaScript. Reject
# unsupported syntax instead of guessing boundaries with a brace regex.
TOKEN = re.compile(r'\s+|//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|[A-Za-z_][\w.]*|-?\d+(?:\.\d+)?|[{}\[\]:;,]')


class Node:
    def __init__(self, kind, start):
        self.kind, self.start, self.end = kind, start, None
        self.values, self.fields, self.children = {}, {}, []

    def walk(self):
        yield self
        for child in self.children:
            yield from child.walk()


def parse(text):
    tokens = []
    position = 0
    for match in TOKEN.finditer(text):
        if match.start() != position:
            raise MetadataError(f"unsupported metadata syntax at {position}")
        position = match.end()
        value = match.group()
        if not value.isspace() and not value.startswith(('//', '/*')):
            tokens.append((value, match.start(), match.end()))
    if position != len(text):
        raise MetadataError(f"unsupported metadata syntax at {position}")
    index = 0

    def take(expected=None):
        nonlocal index
        if index >= len(tokens):
            raise MetadataError("truncated metadata")
        token = tokens[index]
        index += 1
        if expected is not None and token[0] != expected:
            raise MetadataError(f"expected {expected!r}, got {token[0]!r}")
        return token

    def value():
        token = take()[0]
        if token == '[':
            result = []
            while tokens[index][0] != ']':
                result.append(value())
                if tokens[index][0] == ',':
                    take(',')
                elif tokens[index][0] != ']':
                    raise MetadataError("expected array separator")
            take(']')
            return result
        if token.startswith('"'):
            return json.loads(token)
        if token in ('true', 'false'):
            return token == 'true'
        if re.fullmatch(r'-?\d+(?:\.\d+)?', token):
            return float(token) if '.' in token else int(token)
        raise MetadataError(f"unsupported metadata value {token!r}")

    def node():
        kind, start, _ = take()
        result = Node(kind, start)
        take('{')
        while tokens[index][0] != '}':
            if tokens[index + 1][0] == '{':
                result.children.append(node())
            else:
                key, begin, _ = take()
                take(':')
                if key in result.values:
                    raise MetadataError(f"duplicate field {key}")
                result.values[key] = value()
                end = tokens[index - 1][2]
                if tokens[index][0] == ';':
                    end = take(';')[2]
                result.fields[key] = (begin, end)
        result.end = take('}')[2]
        return result

    take('import')
    take('QtQuick.tooling')
    take()  # format version
    result = node()
    if result.kind != 'Module' or index != len(tokens):
        raise MetadataError("expected one tooling Module")
    return result


def references(component):
    for node in component.walk():
        for field in ('type', 'prototype', 'attachedType', 'extension', 'valueType'):
            if field in node.values:
                yield node.values[field]


def foreign_description(text, component):
    result = text[component.start:component.end]
    for field in sorted(('exports', 'exportMetaObjectRevisions'),
                        key=lambda key: component.fields.get(key, (-1, -1))[0], reverse=True):
        if field in component.fields:
            start, end = component.fields[field]
            result = result[:start-component.start] + result[end-component.start:]
    return result


def imported_modules(paths):
    spec = importlib.util.spec_from_file_location('qml_identifiers', Path(__file__).with_name('qml-identifiers.py'))
    lexer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(lexer)
    modules = set()
    for name in lexer.iter_files(map(str, paths)):
        source = Path(name).read_text()
        _, spans = lexer.lex(source)
        chars = list(source)
        for kind, start, end in spans:
            if kind == 'comment':
                chars[start:end] = ['\n' if c == '\n' else ' ' for c in chars[start:end]]
        modules.update(re.findall(r'^\s*import\s+(Quickshell[\w.]*)\b', ''.join(chars), re.M))
    return modules


def module_closure(root, requested):
    directories = {}
    for path in root.rglob('qmldir'):
        match = re.search(r'^module\s+(\S+)', path.read_text(), re.M)
        if match:
            if match[1] in directories:
                raise MetadataError(f'ambiguous native module {match[1]}: {directories[match[1]]}, {path}')
            directories[match[1]] = path
    selected, pending = set(), list(requested)
    while pending:
        name = pending.pop()
        if name in selected or not name.startswith('Quickshell'):
            continue
        if name not in directories:
            raise MetadataError(f"unresolved native module {name}")
        selected.add(name)
        pending.extend(re.findall(r'^(?:(?:optional|default)\s+)?(?:depends|import)\s+(\S+)',
                                  directories[name].read_text(), re.M))
    return {directories[name].parent for name in selected}


def signature(component):
    """Compare semantic contracts, independent of indentation/public exports."""
    fields = {k: v for k, v in component.values.items()
              if k not in ('exports', 'exportMetaObjectRevisions')}
    # Registrar's file-backed opaque marker means unregistered, not unknown.
    # Compare its actual contract with an anonymous inventory description.
    if 'file' in fields:
        fields.pop('isTypeOpaque', None)
    return component.kind, fields, [signature(c) for c in component.children]


def external_types(qml_dir):
    """Qt/builtin identities come from this toolchain, never a member allowlist."""
    known = set()
    for path in sorted(qml_dir.rglob('*.qmltypes')):
        if path.is_relative_to(qml_dir / 'Quickshell'):
            continue
        for component in parse(path.read_text()).children:
            if component.values.get('isTypeOpaque') and 'file' not in component.values:
                continue
            name = component.values['name']
            known.add(name)
            known.update(component.values.get('aliases', []))
            for child in component.children:
                if child.kind == 'Enum':
                    known.add(name + '::' + child.values['name'])
                    if 'alias' in child.values:
                        known.add(name + '::' + child.values['alias'])
    for path in sorted((qml_dir.parent / 'metatypes').glob('*_metatypes.json')):
        if not path.stat().st_size:
            continue
        for record in json.loads(path.read_text()):
            for component in record.get('classes', []):
                name = component['qualifiedClassName']
                known.add(name)
                for enum in component.get('enums', []):
                    known.add(name + '::' + enum['name'])
                    if enum.get('alias'):
                        known.add(name + '::' + enum['alias'])
    return known


def qt_contract_inputs(root, supplemental, qt_metatypes):
    """Bind Qt owners reached by generated contracts, not optional SDK packages."""
    symbols = set()
    for path in [*sorted(root.rglob('*.qmltypes')), supplemental]:
        for component in parse(path.read_text()).children:
            symbols.add(component.values['name'])
            for reference in references(component):
                symbols.update(re.findall(r'[A-Za-z_]\w*(?:::\w+)*', reference))
    required = {}
    for path in sorted(qt_metatypes.glob('*_metatypes.json')):
        if not path.stat().st_size:
            continue
        owners = [c['qualifiedClassName'] for record in json.loads(path.read_text())
                  for c in record.get('classes', [])]
        if any(symbol == owner or symbol.startswith(owner + '::')
               for symbol in symbols for owner in owners):
            required[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return required


def resolve(root, requested=None, supplemental=None, externals=None, terminals=None):
    """Return corrected native scopes and provenance; no type/member allowlist."""
    files, owners = {}, {}
    inputs = sorted(root.rglob('*.qmltypes'))
    if supplemental is not None:
        inputs.append(supplemental)
    for path in inputs:
        text = path.read_text()
        module = parse(text)
        if path != supplemental:
            files[path] = (text, module)
        for component in module.children:
            if component.kind != 'Component':
                raise MetadataError(f"unexpected {component.kind} in {path}")
            name = component.values['name']
            # Registrar also marks deliberately unexported Qt base classes
            # opaque, but includes their owning header and enum descriptions.
            # These are authoritative records, unlike source-less placeholders.
            if not component.values.get('isTypeOpaque', False) or 'file' in component.values:
                if name in owners and signature(owners[name][2]) != signature(component):
                    raise MetadataError(f"ambiguous native owner for {name}: {owners[name][0]}, {path}")
                owners.setdefault(name, (path, text, component))
    if not owners:
        raise MetadataError(f"no native descriptions under {root}")
    selected = module_closure(root, requested) if requested is not None else None
    if externals is None:
        externals = external_types(Path('/usr/lib/qt6/qml'))
    terminals = terminals or {}

    def owner_name(name, context=None):
        # Qt and builtin identities are supplied by the matching toolchain's
        # import universe. Native closure must not replace that external owner.
        if name in externals:
            return None
        if name in owners:
            return name
        if name in terminals:
            return None
        # Containers and scoped enum/flag names have an owning element/class,
        # not a separate QObject definition. Keep their installed descriptions.
        container = re.fullmatch(r'QList<(.+?)\*?>', name)
        if container:
            return owner_name(container[1].rstrip('*'), context)
        # A declaration can use its own enum/flag or a namespace-local spelling.
        # Resolve lexical scope first, then only a unique fully qualified owner.
        if context:
            for length in range(len(context.split('::')), 0, -1):
                qualified = '::'.join(context.split('::')[:length]) + '::' + name
                if qualified in owners:
                    return qualified
                if qualified in externals or qualified in terminals:
                    return None
                for owner in owners.values():
                    if qualified.startswith(owner[2].values['name'] + '::'):
                        enum_name = qualified[len(owner[2].values['name'])+2:]
                        if any(c.kind == 'Enum' and enum_name in (c.values['name'], c.values.get('alias')) for c in owner[2].children):
                            return owner[2].values['name']
        if '::' in name:
            parent, enum_name = name.rsplit('::', 1)
            matches = [key for key in owners if key == parent or key.endswith('::' + parent)]
            matches = [key for key in matches if any(c.kind == 'Enum' and enum_name in (c.values['name'], c.values.get('alias')) for c in owners[key][2].children)]
            if len(matches) > 1:
                raise MetadataError(f'ambiguous native enum owner for {name}: {matches}')
            if matches:
                return matches[0]
        # Registrar can leave a namespace-local C++ spelling in a container.
        # Resolve only an unambiguous installed owner; never choose the first.
        matches = [key for key in owners if key.endswith('::' + name)]
        if len(matches) > 1:
            raise MetadataError(f"ambiguous native owner for {name}: {matches}")
        if matches:
            return matches[0]
        raise MetadataError(f'unresolved native reference {name} from {context}')

    corrected, provenance = {}, {}
    for path, (text, module) in files.items():
        if selected is not None and path.parent not in selected:
            continue
        present = {c.values['name']: c for c in module.children}
        needed = set()
        queue = list(module.children)
        for component in queue:
            if component.values.get('isTypeOpaque', False) and 'file' not in component.values:
                name = component.values['name']
                owner = owner_name(name, component.values['name'])
                if owner is not None:
                    needed.add(owner)
            for name in references(component):
                owner = owner_name(name, component.values['name'])
                if owner is not None and owner not in needed:
                    needed.add(owner)
                    queue.append(owners[owner][2])
        pending = list(needed)
        while pending:
            owner = pending.pop()
            for name in references(owners[owner][2]):
                dependency = owner_name(name, owner)
                if dependency is not None and dependency not in needed:
                    needed.add(dependency)
                    pending.append(dependency)
        edits, additions, copied = [], [], {}
        for name in sorted(needed):
            local = present.get(name)
            if local is not None and (not local.values.get('isTypeOpaque', False) or 'file' in local.values):
                continue
            owner_path, owner_text, component = owners[name]
            description = foreign_description(owner_text, component)
            copied[name] = ('owners.qmltypes' if owner_path == supplemental
                            else owner_path.relative_to(root).as_posix())
            if local is not None:
                edits.append((local.start, local.end, description))
            else:
                additions.append('    ' + description)
        if additions:
            edits.append((module.end - 1, module.end - 1, '\n'.join(additions) + '\n'))
        for start, end, replacement in sorted(edits, reverse=True):
            text = text[:start] + replacement + text[end:]
        corrected[path.relative_to(root)] = text
        provenance[path.relative_to(root).as_posix()] = copied
    return corrected, provenance


def input_family(installed, families):
    observed = {p.relative_to(installed).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in installed.rglob('*.qmltypes')}
    matches = []
    for manifest_path in sorted(families.glob('*/manifest.json')):
        manifest = json.loads(manifest_path.read_text())
        if manifest['installed_qmltypes'] == observed:
            matches.append((manifest_path.parent, manifest))
    if len(matches) != 1:
        raise MetadataError(f'expected one source-backed input family for installed native metadata, found {len(matches)}; regenerate matching inputs (see native-metadata/README.md)')
    family, manifest = matches[0]
    consumed = {p.relative_to(family).as_posix() for p in family.glob('Quickshell/**/*')
                if p.is_file() and p.name.endswith(('.qmltypes', 'qmldir'))}
    consumed.update(('owners.qmltypes', 'terminals.json'))
    if consumed != set(manifest['artifacts']):
        raise MetadataError(f'native input inventory mismatch: {family}')
    for relative, digest in manifest['artifacts'].items():
        path = family / relative
        if not path.resolve().is_relative_to(family.resolve()) or path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise MetadataError(f'native input integrity mismatch: {path}')
    qt_metatypes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in sorted((installed.parent.parent / 'metatypes').glob('*_metatypes.json'))}
    mismatches = [name for name, digest in manifest['required_qt_metatypes'].items()
                  if qt_metatypes.get(name) != digest]
    if mismatches:
        raise MetadataError(f'native input Qt toolchain mismatch: {mismatches}; regenerate matching inputs')
    return family


def materialize(qml_dir, destination, requested=None, families=None):
    family = input_family(qml_dir / 'Quickshell', families or Path(__file__).with_name('native-metadata'))
    terminals = json.loads((family / 'terminals.json').read_text())
    corrected, provenance = resolve(family / 'Quickshell', requested, family / 'owners.qmltypes', external_types(qml_dir), terminals)
    destination.mkdir(exist_ok=False)
    for entry in qml_dir.iterdir():
        if entry.name != 'Quickshell':
            (destination / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
    shutil.copytree(qml_dir / 'Quickshell', destination / 'Quickshell')
    for relative, text in corrected.items():
        (destination / 'Quickshell' / relative).write_text(text)
    (destination / 'native-metadata-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    return provenance


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--qml-dir', type=Path, default=Path('/usr/lib/qt6/qml'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--sources', type=Path, nargs='+', help='QML/JS inputs whose native module graph is required')
    args = parser.parse_args()
    try:
        requested = imported_modules(args.sources) if args.sources is not None else None
        provenance = materialize(args.qml_dir, args.output, requested)
    except (OSError, ValueError, KeyError, IndexError) as error:
        parser.exit(1, f"native metadata: {error}\n")
    print(f"native metadata: {len(provenance)} scopes, {sum(map(len, provenance.values()))} resolved foreign descriptions")


if __name__ == '__main__':
    main()
