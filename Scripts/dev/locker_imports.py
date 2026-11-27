"""Check local imports against the actual assembled locker closure."""
import re


LOCAL_IMPORT = re.compile(r'^\s*\.?import\s+"([^"]+)"(?:\s+as\s+(\w+))?', re.MULTILINE)
QS_IMPORT = re.compile(r'^\s*import\s+qs\.([\w.]+)(?:\s+as\s+(\w+))?', re.MULTILINE)
NON_CODE = re.compile(r'''//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*\' ''', re.DOTALL | re.VERBOSE)
SHARED_TREES = {'Assets', 'Configs', 'Scripts', 'Shaders'}


def unresolved_imports(source, config):
    unresolved = []
    singletons = {}
    for path in config.rglob('*'):
        relative = path.relative_to(config)
        if relative.parts[0] in SHARED_TREES or path.suffix not in ('.qml', '.js'):
            continue
        text = path.read_text()
        modules = [(path.parent, None)]  # QML implicitly imports its own directory.
        for target, alias in LOCAL_IMPORT.findall(text):
            local = path.parent / target
            if not local.exists():
                unresolved.append(f'{relative} -> {target}')
            elif local.is_dir():
                modules.append((local, alias))
        for module, alias in QS_IMPORT.findall(text):
            local = config / module.replace('.', '/')
            if not local.is_dir():
                unresolved.append(f'{relative} -> qs.{module}')
            modules.append((local, alias))
        if path.suffix != '.qml':
            continue
        code = NON_CODE.sub(' ', text)
        for local, alias in modules:
            try:
                directory = local.resolve().relative_to(config.resolve())
            except ValueError:
                continue  # Already checked the path of the explicit import.
            if directory not in singletons:
                singletons[directory] = [p.name for p in (source / directory).glob('*.qml')
                                         if re.search(r'^\s*pragma\s+Singleton\b', p.read_text(), re.MULTILINE)]
            for name in singletons[directory]:
                reference = (alias + '.' if alias else '') + name.removesuffix('.qml')
                if re.search(r'(?<![\w.])' + re.escape(reference) + r'\s*\.', code) and not (local / name).is_file():
                    unresolved.append(f'{relative} -> {directory / name}')
    return sorted(set(unresolved))
