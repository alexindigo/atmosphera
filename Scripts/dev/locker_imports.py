"""Check local imports against the actual assembled locker closure."""
import re


LOCAL_IMPORT = re.compile(r'^\s*\.?import\s+"([^"]+)"(?:\s+as\s+(\w+))?', re.MULTILINE)
QS_IMPORT = re.compile(r'^\s*import\s+qs\.([\w.]+)(?:\s+as\s+(\w+))?', re.MULTILINE)
NON_CODE = re.compile(r'''//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*\' ''', re.DOTALL | re.VERBOSE)
SHARED_TREES = {'Assets', 'Configs', 'Scripts', 'Shaders'}
TYPE = r'[A-Z]\w*(?:\.[A-Z]\w*)*'
OBJECT_TYPE = re.compile(r'(?<![\w.])(' + TYPE + r')\s*\{')
PROPERTY_TYPE = re.compile(r'\bproperty\s+(?:list\s*<\s*)?(' + TYPE + r')(?:\s*>)?\s+\w+')


def blank(match):
    return re.sub(r'[^\n]', ' ', match[0])


def unresolved_imports(source, config):
    unresolved = []
    catalog = {}
    for path in config.rglob('*'):
        relative = path.relative_to(config)
        if relative.parts[0] in SHARED_TREES or path.suffix not in ('.qml', '.js'):
            continue
        text = path.read_text()
        imports = NON_CODE.sub(lambda m: blank(m) if m[0].startswith('/') else m[0], text)
        modules = [(path.parent, None)]  # QML implicitly imports its own directory.
        for target, alias in LOCAL_IMPORT.findall(imports):
            local = path.parent / target
            if not local.exists():
                unresolved.append(f'{relative} -> {target}')
            elif local.is_dir():
                modules.append((local, alias))
        for module, alias in QS_IMPORT.findall(imports):
            local = config / module.replace('.', '/')
            if not local.is_dir():
                unresolved.append(f'{relative} -> qs.{module}')
            modules.append((local, alias))
        if path.suffix != '.qml':
            continue
        code = NON_CODE.sub(blank, text)
        types = set(OBJECT_TYPE.findall(code)) | set(PROPERTY_TYPE.findall(code))
        for local, alias in modules:
            try:
                directory = local.resolve().relative_to(config.resolve())
            except ValueError:
                continue  # Already checked the path of the explicit import.
            if directory not in catalog:
                catalog[directory] = {p.stem: bool(re.search(r'^\s*pragma\s+Singleton\b', p.read_text(), re.MULTILINE))
                                      for p in (source / directory).glob('[A-Z]*.qml')}
            for name, singleton in catalog[directory].items():
                reference = (alias + '.' if alias else '') + name
                filename = name + '.qml'
                if (local / filename).is_file():
                    continue
                if reference in types or (singleton and re.search(r'(?<![\w.])' + re.escape(reference) + r'\s*\.', code)):
                    unresolved.append(f'{relative} -> {directory / filename}')
    return sorted(set(unresolved))
