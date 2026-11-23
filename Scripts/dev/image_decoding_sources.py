"""Parsed image-boundary discovery shared by inventory and rejection gates.

Use the repository's reviewed QML/JS tree-sitter grammar, including nested
objects, inherited renderers, image-bearing Text, and dynamic QML strings.
The manifest assigns provenance separately; syntax discovery cannot certify it.
"""
import hashlib
from importlib.metadata import version
from pathlib import Path
import re
import warnings

warnings.filterwarnings('ignore', message='int argument support is deprecated', category=DeprecationWarning)
from tree_sitter import Language, Parser
import tree_sitter_qmljs

if version('tree-sitter') != '0.25.2' or version('tree-sitter-qmljs') != '0.3.1':
    raise RuntimeError('Image checks require the reviewed settings-check-requirements parser versions')

SHELL_ROOTS = ('Commons', 'Helpers', 'Modules', 'Services', 'Widgets', 'builtin')
RENDERERS = {'Image', 'AnimatedImage', 'IconImage', 'NImageRounded', 'NImage', 'NImageIcon', 'AtmoAppIcon', 'AtmoIcon', 'NImageText'}
TEXT_TYPES = {'Text', 'TextEdit', 'TextArea', 'NText', 'NHeader'}
TEXT_PROPERTIES = {'textFormat', 'richTextEnabled', 'markdownTextEnabled', 'enableDescriptionRichText'}


def walk(node):
    yield node
    for child in node.named_children:
        yield from walk(child)


def discover(root, repository, shell_types=None):
    root = Path(root).resolve()
    paths = sorted(p for base in (SHELL_ROOTS if repository == 'shell' else ('.',))
                   for p in (root / base).rglob('*') if p.suffix in ('.qml', '.js') and p.is_file()
                    and not any(part.startswith('.') or part in ('tests', 'node_modules') for part in p.relative_to(root).parts))
    types = QmlTypes(root, paths, shell_types)
    rows = []
    for path in paths:
        ordinals = {}
        data, tree = types.parsed[path]
        file_hash = hashlib.sha256(data).hexdigest()
        def text(node):
            return data[node.start_byte:node.end_byte].decode() if node else ''
        for node in walk(tree.root_node):
            kind, bindings, bases = '', {}, set()
            if node.type in ('ui_object_definition', 'ui_object_binding'):
                kind = text(node.child_by_field_name('type_name'))
                init = node.child_by_field_name('initializer')
                if not init:
                    continue
                bindings = {text(b.child_by_field_name('name')): text(b.child_by_field_name('value'))
                            for b in init.named_children if b.type in ('ui_binding', 'ui_property')}
                bases = types.resolve(path, node)
                text_wrapper = bases & {'NText', 'NHeader'}
                if not (bases & (RENDERERS | NATIVE_IMAGES) or
                        not text_wrapper and bases & {'Text', 'TextEdit', 'TextArea'} or
                        bases & TEXT_TYPES and any(p in bindings for p in TEXT_PROPERTIES)):
                    continue
            elif node.type == 'call_expression':
                function = text(node.child_by_field_name('function'))
                if function.split('.')[-1] != 'createQmlObject':
                    continue
                kind = 'dynamic-qml'
            elif node.type in ('string', 'template_string'):
                value = text(node)
                if not any(command in value for command in ('magick', 'ffmpeg', 'ffprobe')):
                    continue
                kind = 'converter-command'
                bindings = {'command': value}
            else:
                continue
            identity = bindings.get('id', '').strip().rstrip(';')
            ordinals[kind] = ordinals.get(kind, 0) + 1
            rows.append(dict(repository=repository, path=str(path.relative_to(root)), line=node.start_point.row + 1,
                             endLine=node.end_point.row + 1,
                             key=f'{repository}:{path.relative_to(root)}:{kind}:{ordinals[kind]}',
                             node=kind, identity=identity, bindings=bindings,
                             nodeSha256=hashlib.sha256(data[node.start_byte:node.end_byte]).hexdigest(),
                              fileSha256=file_hash,
                              **({'inheritedFrom': sorted(bases - {kind})} if bases - {kind} else {})))
    return rows


# ---------------------------------------------------------------------------
# Rejection-gate scan. Every site where Qt (or a process) would decode image
# bytes outside the shared owner: native image nodes (direct or through a
# local wrapper), text that Qt lays out as markup (it loads <img> and
# backgrounds itself), ColorQuantizer, dynamic QML and converter commands.
# Owner renderers (NImage, NImageRounded, NImageIcon, NImageText, AtmoAppIcon,
# AtmoIcon) are not sites: they are the boundary.

PRODUCTION_SHELL = SHELL_ROOTS + ('Quickshell', 'Portals', 'shell.qml', 'ShellSession.qml')
NATIVE_IMAGES = {'Image', 'AnimatedImage', 'IconImage', 'BorderImage', 'AnimatedSprite', 'Sprite'}
AUTO_TEXT = {'Text', 'Label'}  # Qt's default AutoText lays out markup by itself
EXPLICIT_TEXT = {'TextEdit', 'TextArea'}  # PlainText unless textFormat says otherwise
NTEXT_FLAGS = ('richTextEnabled', 'markdownTextEnabled')
COMMAND = re.compile(r'(?<![\w.-])(magick|ffmpeg|ffprobe)(?![\w.-])')


def production_files(root, repository):
    root = Path(root)
    bases = PRODUCTION_SHELL if repository == 'shell' else ('.',)
    found = set()
    for base in bases:
        target = root / base
        candidates = [target] if target.is_file() else target.rglob('*') if target.is_dir() else []
        for path in candidates:
            parts = path.relative_to(root).parts
            if path.suffix in ('.qml', '.js') and path.is_file() and not any(
                    part.startswith('.') or part in ('tests', 'fixtures', 'node_modules') for part in parts):
                found.add(path)
    return sorted(found)


def _decode_literal(body):
    """Decode JS/QML string spelling without executing source. Unknown or
    malformed escapes stay unknown to the gate, never presumed plain text."""
    out, index = [], 0
    escapes = {'b': '\b', 'f': '\f', 'n': '\n', 'r': '\r', 't': '\t', 'v': '\v'}
    while index < len(body):
        char = body[index]
        index += 1
        if char != '\\':
            out.append(char)
            continue
        if index == len(body):
            return None
        char = body[index]
        index += 1
        if char in '\r\n':
            if char == '\r' and body[index:index + 1] == '\n':
                index += 1
        elif char in ('x', 'u'):
            if char == 'u' and body[index:index + 1] == '{':
                end = body.find('}', index + 1)
                digits = body[index + 1:end] if end >= 0 else ''
                index = end + 1
            else:
                length = 2 if char == 'x' else 4
                digits = body[index:index + length]
                if len(digits) != length:
                    return None
                index += length
            if not re.fullmatch(r'[0-9a-fA-F]{1,6}', digits) or int(digits, 16) > 0x10ffff:
                return None
            out.append(chr(int(digits, 16)))
        elif char.isdigit():
            if char != '0' or body[index:index + 1].isdigit():
                return None  # legacy octal is not a proof of a plain literal
            out.append('\0')
        else:
            out.append(escapes.get(char, char))
    try:
        return ''.join(out).encode('utf-16-le', 'surrogatepass').decode('utf-16-le')
    except UnicodeError:
        return None


def _literal_text(node, data, substitutions=False):
    if node.type not in ('string', 'template_string'):
        return None
    expressions = [child for child in node.named_children if child.type == 'template_substitution']
    if expressions and not substitutions:
        return None
    start = node.start_byte + 1
    chunks = []
    for expression in expressions:
        chunks.append(data[start:expression.start_byte])
        start = expression.end_byte
    chunks.append(data[start:node.end_byte - 1])
    return _decode_literal(b''.join(chunks).decode())


def _static_qml(node, data):
    """Fully known generated QML only. A placeholder is not evidence that an
    unresolved expression cannot contribute a node, member or image source."""
    if node.type in ('string', 'template_string'):
        return _literal_text(node, data)
    if node.type == 'parenthesized_expression' and node.named_children:
        return _static_qml(node.named_children[0], data)
    if node.type == 'binary_expression' and data[node.child_by_field_name('operator').start_byte:node.child_by_field_name('operator').end_byte] == b'+':
        left = _static_qml(node.child_by_field_name('left'), data)
        right = _static_qml(node.child_by_field_name('right'), data)
        return left + right if left is not None and right is not None else None
    return None


def _embedded_sites(parser, body):
    """Image-capable node types inside known QML; None when parsing is unsure."""
    data = body.encode()
    found = []
    tree = parser.parse(data)
    if tree.root_node.has_error:
        return None
    for node in walk(tree.root_node):
        if node.type not in ('ui_object_definition', 'ui_object_binding'):
            continue
        name = data[node.child_by_field_name('type_name').start_byte:node.child_by_field_name('type_name').end_byte].decode().split('.')[-1]
        if name in NATIVE_IMAGES | AUTO_TEXT | EXPLICIT_TEXT | {'NText', 'ColorQuantizer'}:
            found.append(name)
    return found


def _static_text(node, data):
    """True when a text binding can only produce literal content without
    markup: literals, literal arrays indexed, numbers, Math.* and + of those."""
    if node is None:
        return True
    kind = node.type
    value = data[node.start_byte:node.end_byte].decode()
    if kind in ('expression_statement', 'parenthesized_expression'):
        return all(_static_text(child, data) for child in node.named_children)
    if kind in ('number', 'true', 'false'):
        return True
    if kind == 'string':
        literal = _literal_text(node, data)
        return literal is not None and '<' not in literal and '![' not in literal
    if kind == 'template_string':
        literal = _literal_text(node, data, substitutions=True)
        return literal is not None and '<' not in literal and '![' not in literal and all(
            _static_text(child.named_children[0] if child.named_children else None, data)
            for child in node.named_children if child.type == 'template_substitution')
    if kind == 'array':
        return all(_static_text(child, data) for child in node.named_children)
    if kind == 'subscript_expression':
        return _static_text(node.child_by_field_name('object'), data)
    if kind == 'binary_expression':
        return _static_text(node.child_by_field_name('left'), data) and _static_text(node.child_by_field_name('right'), data)
    if kind == 'ternary_expression':
        return _static_text(node.child_by_field_name('consequence'), data) and _static_text(node.child_by_field_name('alternative'), data)
    if kind == 'call_expression':
        return data[node.child_by_field_name('function').start_byte:node.child_by_field_name('function').end_byte].decode().startswith('Math.')
    return False


class QmlTypes:
    """Resolve a component in its document, never a repository-wide name table.

    Directory aliases and qs module imports keep their own exports. Each parent
    in an inheritance chain is resolved in the parent's file. Ambiguous imports
    retain all candidates so an image-capable branch cannot disappear by order.
    """
    def __init__(self, root, paths, shell=None):
        self.root = Path(root).resolve()
        self.shell = shell
        self.parser = Parser(Language(tree_sitter_qmljs.language()))
        self.parsed = {}
        self.exports = {}
        for path in paths:
            data = path.read_bytes()
            self.parsed[path.resolve()] = (data, self.parser.parse(data))

    def directory(self, directory, implicit=False):
        directory = directory.resolve()
        key = (directory, implicit)
        if key not in self.exports:
            names = {}
            qmldir = directory / 'qmldir'
            if implicit or not qmldir.is_file():
                names.update({p.stem: p for p in self.parsed if p.parent == directory and p.suffix == '.qml'})
            if qmldir.is_file():
                for line in qmldir.read_text().splitlines():
                    parts = line.split('#', 1)[0].split()
                    if parts[:1] == ['singleton']:
                        parts = parts[1:]
                    if len(parts) >= 2 and parts[0][:1].isupper() and parts[-1].endswith('.qml'):
                        target = (directory / parts[-1]).resolve()
                        if target in self.parsed:
                            names[parts[0]] = target
            self.exports[key] = names
        return self.exports[key]

    def spelling(self, path, node):
        data = self.parsed[path][0]
        return data[node.start_byte:node.end_byte].decode() if node else ''

    def resolve(self, path, node, seen=()):
        path = Path(path).resolve()
        name = self.spelling(path, node.child_by_field_name('type_name'))
        if '.' not in name:
            ancestor = node.parent
            while ancestor is not None:
                if ancestor.type == 'ui_object_initializer':
                    for child in ancestor.named_children:
                        if child.type == 'ui_inline_component' and self.spelling(path, child.child_by_field_name('name')) == name:
                            return self.parent_types(path, child.child_by_field_name('component'), seen)
                ancestor = ancestor.parent
            local = self.directory(path.parent, implicit=True).get(name)
            if local:
                return self.file_types(local, seen)
        alias, short = name.split('.', 1) if '.' in name else ('', name)
        candidates = set()
        data, tree = self.parsed[path]
        for imported in tree.root_node.named_children:
            if imported.type != 'ui_import' or self.spelling(path, imported.child_by_field_name('alias')) != alias:
                continue
            source = imported.child_by_field_name('source')
            value = self.spelling(path, source)
            owner, directory = self, None
            if source.type == 'string':
                literal = _literal_text(source, data)
                if literal is not None:
                    directory = path.parent / literal
            elif value == 'qs' or value.startswith('qs.'):
                owner = self.shell or self
                directory = owner.root.joinpath(*value.split('.')[1:])
            elif alias and short in NATIVE_IMAGES | AUTO_TEXT | EXPLICIT_TEXT | {'ColorQuantizer'}:
                candidates.add(short)
            if directory is not None:
                target = owner.directory(directory).get(short)
                if target:
                    candidates.update(owner.file_types(target, seen))
        return candidates or {name}

    def parent_types(self, path, node, seen):
        identity = (path, node.start_byte)
        if identity in seen:
            return set()
        return self.resolve(path, node, seen + (identity,))

    def file_types(self, path, seen):
        for node in self.parsed[path][1].root_node.named_children:
            if node.type == 'ui_object_definition':
                # Retain renderer identity for inventory without hiding a local
                # lookalike that is actually rooted in a native image type.
                boundary = {path.stem} & (RENDERERS | TEXT_TYPES)
                return self.parent_types(path, node, seen) | boundary
        return set()


def scan(root, repository, shell_types=None):
    """Gated sites plus the import-scoped shell context for plugin scans."""
    root = Path(root).resolve()
    files = production_files(root, repository)
    types = QmlTypes(root, files, shell_types)
    parser = types.parser
    rows = []
    for path, (data, tree) in types.parsed.items():
        relative = path.relative_to(root)
        ordinals = {}
        def text(node):
            return data[node.start_byte:node.end_byte].decode() if node else ''
        for node in walk(tree.root_node):
            rule, kind, bindings, detail = '', '', {}, {}
            if node.type in ('ui_object_definition', 'ui_object_binding'):
                kind = text(node.child_by_field_name('type_name'))
                init = node.child_by_field_name('initializer')
                members = [b for b in (init.named_children if init else []) if b.type in ('ui_binding', 'ui_property')]
                bindings = {text(b.child_by_field_name('name')): text(b.child_by_field_name('value')) for b in members}
                values = {text(b.child_by_field_name('name')): b.child_by_field_name('value') for b in members}
                bases = types.resolve(path, node)
                if bases & NATIVE_IMAGES:
                    rule = 'native-image'
                    if kind not in NATIVE_IMAGES:
                        detail['inheritedFrom'] = sorted(bases & NATIVE_IMAGES)
                elif 'ColorQuantizer' in bases:
                    rule = 'color-quantizer'
                elif 'NText' in bases:
                    if any(bindings.get(flag, 'false').strip().rstrip(';') != 'false' for flag in NTEXT_FLAGS):
                        rule = 'text-markup'
                elif bases & (AUTO_TEXT | EXPLICIT_TEXT):
                    fmt = bindings.get('textFormat')
                    if fmt is not None:
                        markup = fmt.strip().rstrip(';') not in ('Text.PlainText', 'TextEdit.PlainText')
                    elif bases & AUTO_TEXT:
                        markup = not _static_text(values.get('text'), data)
                    else:
                        markup = False
                    if markup:
                        rule = 'text-markup'
            elif node.type == 'call_expression':
                if text(node.child_by_field_name('function')).split('.')[-1] == 'createQmlObject':
                    arguments = node.child_by_field_name('arguments')
                    args = arguments.named_children if arguments else []
                    first = args[0] if args else None
                    static = _static_qml(first, data) if first is not None else None
                    embedded = _embedded_sites(parser, static) if static is not None else None
                    # Literal QML without image-capable nodes is not a site;
                    # QML built from variables needs review.
                    if embedded is None or embedded:
                        rule, kind = 'dynamic-qml', 'createQmlObject'
                        detail['expressionSha256'] = hashlib.sha256(data[first.start_byte:first.end_byte]).hexdigest() if first else ''
                        detail['constructor'] = text(args[2]) if len(args) > 2 else ''
                        if embedded:
                            detail['embedded'] = embedded
            elif node.type in ('string', 'template_string'):
                value = text(node)
                if COMMAND.search(value):
                    rule, kind = 'converter-command', 'command'
            if not rule:
                continue
            ordinals[(rule, kind)] = ordinals.get((rule, kind), 0) + 1
            keep = {key: value for key, value in bindings.items()
                    if key in ('id', 'source', 'icon', 'imagePath', 'text', 'textFormat') + NTEXT_FLAGS}
            if kind == 'command':
                keep = {'command': text(node)}
            rows.append(dict(repository=repository, path=str(relative), line=node.start_point.row + 1, rule=rule, node=kind,
                             key=f'{repository}:{relative}:{rule}:{kind}:{ordinals[(rule, kind)]}', bindings=keep,
                             nodeSha256=hashlib.sha256(data[node.start_byte:node.end_byte]).hexdigest(), **detail))
    return rows, types
