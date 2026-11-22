"""Parsed image-boundary discovery shared by inventory and rejection gates.

Use the repository's reviewed QML/JS tree-sitter grammar, including nested
objects, inherited renderers, image-bearing Text, and dynamic QML strings.
The manifest assigns provenance separately; syntax discovery cannot certify it.
"""
import hashlib
from importlib.metadata import version
from pathlib import Path
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
