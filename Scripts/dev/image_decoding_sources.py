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
RENDERERS = {'Image', 'AnimatedImage', 'IconImage', 'NImageRounded', 'NImage', 'AtmoAppIcon', 'AtmoIcon', 'NImageText'}
TEXT_TYPES = {'Text', 'TextEdit', 'TextArea', 'NText', 'NHeader'}
TEXT_PROPERTIES = {'textFormat', 'richTextEnabled', 'markdownTextEnabled', 'enableDescriptionRichText'}


def walk(node):
    yield node
    for child in node.named_children:
        yield from walk(child)


def discover(root, repository):
    root = Path(root)
    parser = Parser(Language(tree_sitter_qmljs.language()))
    paths = sorted(p for base in (SHELL_ROOTS if repository == 'shell' else ('.',))
                   for p in (root / base).rglob('*') if p.suffix in ('.qml', '.js') and p.is_file()
                   and not any(part.startswith('.') or part in ('tests', 'node_modules') for part in p.relative_to(root).parts))
    rows = []
    for path in paths:
        ordinals = {}
        data = path.read_bytes()
        tree = parser.parse(data)
        def text(node):
            return data[node.start_byte:node.end_byte].decode() if node else ''
        for node in walk(tree.root_node):
            kind, bindings = '', {}
            if node.type in ('ui_object_definition', 'ui_object_binding'):
                kind = text(node.child_by_field_name('type_name')).split('.')[-1]
                init = node.child_by_field_name('initializer')
                if not init:
                    continue
                bindings = {text(b.child_by_field_name('name')): text(b.child_by_field_name('value'))
                            for b in init.named_children if b.type in ('ui_binding', 'ui_property')}
                if kind not in RENDERERS and not (kind in ('Text', 'TextEdit', 'TextArea') or
                                                  kind in TEXT_TYPES and any(p in bindings for p in TEXT_PROPERTIES)):
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
                             fileSha256=hashlib.sha256(data).hexdigest()))
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


def _static_qml(node, data):
    """QML text of a string literal or a + concatenation of literals and
    expressions (expressions become a placeholder); None if nothing is literal."""
    value = data[node.start_byte:node.end_byte].decode()
    if node.type in ('string', 'template_string'):
        body = re.sub(r'\$\{[^}]*\}', '0', value[1:-1])
        return re.sub(r'\\(.)', lambda match: {'n': '\n', 't': '\t'}.get(match[1], match[1]), body)
    if node.type == 'parenthesized_expression' and node.named_children:
        return _static_qml(node.named_children[0], data)
    if node.type == 'binary_expression' and data[node.child_by_field_name('operator').start_byte:node.child_by_field_name('operator').end_byte] == b'+':
        left = _static_qml(node.child_by_field_name('left'), data)
        right = _static_qml(node.child_by_field_name('right'), data)
        if left is None and right is None:
            return None
        return (left if left is not None else '0') + (right if right is not None else '0')
    return None


def _embedded_sites(parser, body):
    """Image-capable node types inside QML text ([] when none)."""
    data = body.encode()
    found = []
    for node in walk(parser.parse(data).root_node):
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
        return '<' not in value and '![' not in value
    if kind == 'template_string':
        return '<' not in value and '![' not in value and all(
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


def _component_scope(relative, repository):
    # Plugin components resolve inside their own plugin directory; shell
    # components resolve across the shell (qs.* imports and same directory).
    return relative.parts[0] if repository == 'plugins' else ''


def scan(root, repository, shell_types=None):
    """Gated sites of one repository. shell_types maps shell component names to
    their root types so plugin usages of shell wrappers resolve too."""
    root = Path(root)
    parser = Parser(Language(tree_sitter_qmljs.language()))
    files = production_files(root, repository)
    parsed, roots = {}, {}
    for path in files:
        data = path.read_bytes()
        tree = parser.parse(data)
        parsed[path] = (data, tree)
        if path.suffix == '.qml':
            for node in tree.root_node.named_children:
                if node.type == 'ui_object_definition':
                    name = data[node.child_by_field_name('type_name').start_byte:node.child_by_field_name('type_name').end_byte].decode()
                    roots[(_component_scope(path.relative_to(root), repository), path.stem)] = name.split('.')[-1]
                    break
    def resolve(scope, name, seen=()):
        if name in NATIVE_IMAGES or name in seen or len(seen) > 12:
            return name
        if (scope, name) in roots:
            return resolve(scope, roots[(scope, name)], seen + (name,))
        if shell_types and name in shell_types:
            return resolve('', shell_types[name], seen + (name,))
        return name
    rows = []
    for path, (data, tree) in parsed.items():
        relative = path.relative_to(root)
        scope = _component_scope(relative, repository)
        ordinals = {}
        def text(node):
            return data[node.start_byte:node.end_byte].decode() if node else ''
        for node in walk(tree.root_node):
            rule, kind, bindings, detail = '', '', {}, {}
            if node.type in ('ui_object_definition', 'ui_object_binding'):
                kind = text(node.child_by_field_name('type_name')).split('.')[-1]
                init = node.child_by_field_name('initializer')
                members = [b for b in (init.named_children if init else []) if b.type in ('ui_binding', 'ui_property')]
                bindings = {text(b.child_by_field_name('name')): text(b.child_by_field_name('value')) for b in members}
                values = {text(b.child_by_field_name('name')): b.child_by_field_name('value') for b in members}
                base = resolve(scope, kind)
                if base in NATIVE_IMAGES:
                    rule = 'native-image'
                    if base != kind:
                        detail['inheritedFrom'] = base
                elif kind == 'ColorQuantizer':
                    rule = 'color-quantizer'
                elif kind == 'NText':
                    if any(bindings.get(flag, 'false').strip().rstrip(';') != 'false' for flag in NTEXT_FLAGS):
                        rule = 'text-markup'
                elif kind in AUTO_TEXT | EXPLICIT_TEXT:
                    fmt = bindings.get('textFormat')
                    if fmt is not None:
                        markup = fmt.strip().rstrip(';') not in ('Text.PlainText', 'TextEdit.PlainText')
                    elif kind in AUTO_TEXT:
                        markup = not _static_text(values.get('text'), data)
                    else:
                        markup = False
                    if markup:
                        rule = 'text-markup'
            elif node.type == 'call_expression':
                if text(node.child_by_field_name('function')).split('.')[-1] == 'createQmlObject':
                    arguments = node.child_by_field_name('arguments')
                    first = arguments.named_children[0] if arguments and arguments.named_children else None
                    static = _static_qml(first, data) if first is not None else None
                    embedded = _embedded_sites(parser, static) if static is not None else None
                    # Literal QML without image-capable nodes is not a site;
                    # QML built from variables needs review.
                    if embedded is None or embedded:
                        rule, kind = 'dynamic-qml', 'createQmlObject'
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
    return rows, {name: base for (scope, name), base in roots.items() if scope == ''}
