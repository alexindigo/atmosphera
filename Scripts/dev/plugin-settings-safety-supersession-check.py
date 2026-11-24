#!/usr/bin/env python3
"""Parsed proof that the final field contract replaces the P001 safety path.

This focused gate is not the complete catalog/role boundary checker. Run both.
"""
import argparse
from importlib.metadata import version
import json
from pathlib import Path
import warnings

warnings.filterwarnings('ignore', message='int argument support is deprecated', category=DeprecationWarning)
from tree_sitter import Language, Parser
import tree_sitter_qmljs


def walk(node):
    yield node
    for child in node.named_children:
        yield from walk(child)


def inspect(page_api, session, todo):
    issues = []
    for name, text in (('page-api', page_api), ('session', session), ('todo', todo)):
        source = text.encode()
        tree = Parser(Language(tree_sitter_qmljs.language())).parse(source)
        if tree.root_node.has_error:
            issues.append(name + ': parse error')
            continue
        nodes = list(walk(tree.root_node))

        def spelling(node):
            return source[node.start_byte:node.end_byte].decode() if node else ''

        def field(node, key):
            return node.child_by_field_name(key) if node else None

        if name == 'page-api':
            properties = {spelling(field(node, 'name')): node for node in nodes if node.type == 'ui_property'}
            settings = properties.get('pluginSettings')
            if not settings or not any(child.type == 'ui_property_modifier' and spelling(child) == 'readonly' for child in settings.children):
                issues.append('page-api: mutable namespace remains')
            for forbidden in ('editor', 'base'):
                if forbidden in properties:
                    issues.append('page-api: direct ' + forbidden + ' capability remains')
        elif name == 'session':
            for node in nodes:
                if node.type == 'function_declaration' and spelling(field(node, 'name')) == '_resetReviewedConfiguration':
                    issues.append('session: safety Reset dispatch remains')
                if node.type in ('property_identifier', 'string', 'identifier') and spelling(node).strip('\"\'') == 'resetOverrides':
                    issues.append('session: all-data Reset remains')
                if node.type != 'call_expression':
                    continue
                callee = field(node, 'function')
                if callee and callee.type == 'member_expression' and spelling(field(callee, 'property')) == 'apply':
                    arguments = field(node, 'arguments')
                    first = arguments.named_children[0] if arguments and arguments.named_children else None
                    if not first or first.type != 'member_expression' or spelling(field(first, 'object')) != 'editor' or spelling(field(first, 'property')) != 'values':
                        issues.append('session: Apply does not use selected native values identity')
        else:
            aliases = set()

            def namespace(node):
                return any((part.type == 'member_expression' and spelling(field(part, 'property')) == 'pluginSettings') or
                           (part.type == 'identifier' and spelling(part) in aliases) for part in walk(node)) if node else False

            def aliases_namespace(node):
                if not node:
                    return False
                if node.type in ('expression_statement', 'parenthesized_expression'):
                    return any(aliases_namespace(part) for part in node.named_children)
                if node.type in ('identifier', 'member_expression', 'subscript_expression'):
                    return namespace(node)
                if node.type in ('binary_expression', 'ternary_expression'):
                    return any(aliases_namespace(part) for part in node.named_children)
                # A read passed into a copying/projection call does not make
                # that call's result an alias of its input namespace.
                return False

            # Resolve named aliases in declarations and simple assignments before
            # checking direct, computed-key and nested publication attempts.
            for _ in range(len(nodes) + 1):
                old = set(aliases)
                for node in nodes:
                    if node.type in ('variable_declarator', 'ui_property') and aliases_namespace(field(node, 'value')):
                        aliases.add(spelling(field(node, 'name')))
                    if node.type == 'assignment_expression' and aliases_namespace(field(node, 'right')):
                        left = field(node, 'left')
                        if left and left.type == 'identifier':
                            aliases.add(spelling(left))
                if aliases == old:
                    break
            for node in nodes:
                if node.type in ('assignment_expression', 'augmented_assignment_expression', 'update_expression'):
                    target = field(node, 'left') or field(node, 'argument')
                    if namespace(target):
                        issues.append('todo: mutable namespace content/config writer remains')
                if node.type == 'function_declaration' and spelling(field(node, 'name')) in ('stageConfiguration', 'markContent'):
                    issues.append('todo: interim intent implementation remains')
                if node.type == 'call_expression':
                    callee, arguments = field(node, 'function'), field(node, 'arguments')
                    if callee and callee.type == 'member_expression':
                        prop = spelling(field(callee, 'property'))
                        if prop in ('push', 'pop', 'shift', 'unshift', 'splice', 'sort', 'reverse', 'fill', 'copyWithin') and namespace(field(callee, 'object')):
                            issues.append('todo: compound namespace mutator remains')
                        if spelling(callee) == 'Object.assign' and arguments and arguments.named_children and namespace(arguments.named_children[0]):
                            issues.append('todo: namespace assignment helper remains')
    return sorted(set(issues))


def selftest():
    page = 'import QtQuick\nQtObject { required property var capability; readonly property var pluginSettings: capability.readSettings() }'
    session = 'import QtQuick\nQtObject { function apply() { editor.apply(editor.values, completed); } }'
    todo = 'import QtQuick\nItem { function edit() { pluginApi.field("showCompleted").set(false); } }'
    assert not inspect(page, session, todo)
    copied = todo.replace('pluginApi.field("showCompleted").set(false)', 'let ns = pluginApi.pluginSettings; let local = Object.assign({}, ns); local.showCompleted = false')
    if inspect(page, session, copied):
        raise RuntimeError('owned display copy confused with namespace alias')
    controls = [
        (page.replace('readonly property', 'property'), session, todo),
        (page.replace('required property var capability;', 'required property var capability; property var editor;'), session, todo),
        (page, session.replace('editor.values', 'pageApi.pluginSettings'), todo),
        (page, session.replace('editor.apply(editor.values, completed)', 'editor.resetOverrides(completed)'), todo),
        (page, session.replace('function apply()', 'function _resetReviewedConfiguration()'), todo),
        (page, session, todo.replace('pluginApi.field("showCompleted").set(false)', 'pluginApi.pluginSettings.todos = []')),
        (page, session, todo.replace('pluginApi.field("showCompleted").set(false)', 'let cfg = pluginApi.pluginSettings; let alias = cfg; alias["todos"].push({})')),
        (page, session, todo.replace('pluginApi.field("showCompleted").set(false)', 'Object.assign(pluginApi.pluginSettings, {todos: []})')),
    ]
    for index, values in enumerate(controls):
        if not inspect(*values):
            raise RuntimeError('supersession rejecting control not rejected: ' + str(index))
    return len(controls)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--plugins', type=Path, required=True)
    parser.add_argument('--selftest', action='store_true')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if version('tree-sitter') != '0.25.2' or version('tree-sitter-qmljs') != '0.3.1':
        parser.error('use the existing pinned settings-check requirements')
    controls = selftest() if args.selftest else 0
    issues = inspect((args.source / 'Services/Plugins/PluginSettingsPageApi.qml').read_text(),
                     (args.source / 'Services/Plugins/PluginSettingsSession.qml').read_text(),
                     (args.plugins / 'todo/Settings.qml').read_text())
    if args.report:
        args.report.write_text(json.dumps(dict(status='FAIL' if issues else 'PASS', issues=issues, rejectingControls=controls,
            completeCatalogBoundaryNotCertified=True), indent=2) + '\n')
    for issue in issues:
        print(issue)
    print('P001_SAFETY_SUPERSESSION: ' + ('FAIL' if issues else 'PASS'))
    return 1 if issues else 0


if __name__ == '__main__':
    raise SystemExit(main())
