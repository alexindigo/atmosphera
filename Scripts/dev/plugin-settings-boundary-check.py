#!/usr/bin/env python3
"""Parsed generic-page capability gate, separate from detached-write analysis.

Walk manifest entries and their local QML/JS dependency graph. Resolve lexical
declarations, QML object receivers, helper parameters/returns and literal key
sets before checking writer edges. Unresolved field keys and callable writer
escapes are errors, not a regex suppression baseline. This is accidental API
misuse detection, not a sandbox or a substitute for the consumer regressions.
"""
import argparse
from dataclasses import dataclass
from importlib.metadata import version
import importlib.util
import json
from pathlib import Path
import re
import shutil
import tempfile
import warnings

warnings.filterwarnings('ignore', message='int argument support is deprecated', category=DeprecationWarning)
from tree_sitter import Language, Parser
import tree_sitter_qmljs

FUNCTIONS = {'function_declaration', 'function_expression', 'arrow_function', 'method_definition'}
MUTATORS = {'push', 'pop', 'shift', 'unshift', 'splice', 'sort', 'reverse', 'fill', 'copyWithin'}
NATIVE = {'createSettingsEditor', 'openOverlay', 'settingsHandle', 'settingsOwner', 'resetOverrides', 'saveSelected',
          'getPluginAPI', 'createPluginAPI', 'apiFor'}
EMPTY = frozenset()
JS_DIRECTIVE = re.compile(r'^([ \t]*)\.(pragma|import)\b([^\n]*)', re.M)


def js_body(text):
    # Qt's JS file header syntax is not part of the JS grammar. Keep line
    # numbers intact, but inventory local imports before masking the header.
    imports = []

    def mask(match):
        if match[2] == 'import':
            local = re.fullmatch(r'''\s*(["'])(.*?)\1\s+as\s+([A-Za-z_]\w*)\s*;?\s*(?://.*)?''', match[3])
            if local:
                imports.append((local[2], local[3]))
            elif match[3].lstrip().startswith(('"', "'")):
                raise RuntimeError('unresolved local JavaScript directive: ' + match[3].strip())
        return ' ' * len(match[0])

    return JS_DIRECTIVE.sub(mask, text), imports


def walk(node):
    yield node
    for item in node.named_children:
        yield from walk(item)


def child(node, name):
    return node.child_by_field_name(name) if node else None


def union(values):
    return frozenset().union(*values)


@dataclass
class Unit:
    path: Path
    source: bytes
    tree: object
    offset: int

    def text(self, node):
        return self.source[node.start_byte:node.end_byte].decode() if node else ''


class Pages:
    def __init__(self, plugin, fields, fixture_inputs=()):
        self.plugin = plugin.resolve()
        self.fields = fields
        self.units = {}
        self.nodes = {}
        self.byid = {}
        self.declarations = {}
        self.scopes = {}
        self.ids = {}
        self.env = {}
        self.returns = {}
        self.functions = {}
        self.issues = set()
        self.field_calls = set()
        self.intents = set()
        self.instance_roots = {}
        self.js_modules = {}
        self.imports = {}
        self.signal_handlers = {}
        self.edges = {}
        self.record_members = {}
        self.record_sources = {}
        self.string_facts = {}
        self.fixture_inputs = fixture_inputs
        self.frame = {}
        self.active_getters = set()

    def issue(self, node, code):
        unit = self.unit(node)
        self.issues.add((str(unit.path.relative_to(self.plugin)), max(1, node.start_point.row + 1 - unit.offset), code))

    def unit(self, node):
        while node.id not in self.nodes:
            node = node.parent
        return self.nodes[node.id]

    def text(self, node):
        return self.unit(node).text(node) if node else ''

    def unwrap(self, node):
        while node and node.type in ('expression_statement', 'parenthesized_expression', 'required_parameter'):
            node = child(node, 'pattern') or (node.named_children[0] if node.named_children else None)
        return node

    def literal(self, node):
        node = self.unwrap(node)
        if not node or node.type != 'string':
            return None
        # QML strings use JS quoting, but path/key strings here are finite plain
        # literals. Escaped keys are decoded rather than compared by spelling.
        value = self.text(node)
        try:
            return json.loads(value) if value.startswith('"') else bytes(value[1:-1], 'utf8').decode('unicode_escape')
        except (ValueError, UnicodeError):
            return None

    def load(self, path):
        path = path.resolve()
        if not path.is_relative_to(self.plugin):
            raise RuntimeError('local dependency leaves plugin root: ' + str(path))
        if path in self.units:
            return
        original = path.read_text()
        offset = 0
        script_imports = []
        if path.suffix == '.js':
            original, script_imports = js_body(original)
            original = 'import QtQml\nQtObject { function __script() {\n' + original + '\n} }\n'
            offset = 2
        source = original.encode()
        tree = Parser(Language(tree_sitter_qmljs.language())).parse(source)
        unit = Unit(path, source, tree, offset)
        self.units[path] = unit
        for node in walk(tree.root_node):
            self.nodes[node.id] = unit
            self.byid[node.id] = node
        if tree.root_node.has_error:
            self.issue(tree.root_node, 'parse-error')
            return
        directories = {'': [path.parent]}
        dependencies = set()
        for imported, alias in script_imports:
            target = (path.parent / imported).resolve()
            dependencies.add(target)
            self.imports[(path, alias)] = target
        for node in walk(tree.root_node):
            if node.type != 'ui_import':
                continue
            imported = self.literal(child(node, 'source'))
            if imported is None:
                continue
            target = (path.parent / imported).resolve()
            alias = self.text(child(node, 'alias'))
            if target.is_dir():
                directories.setdefault(alias, []).append(target)
            elif target.suffix in ('.js', '.qml'):
                dependencies.add(target)
                if alias:
                    self.imports[(path, alias)] = target
            else:
                self.issue(node, 'unresolved-local-import:' + imported)
        for node in walk(tree.root_node):
            if node.type == 'ui_object_definition':
                name = self.text(child(node, 'type_name')).split('.')
                alias = name[0] if len(name) == 2 else ''
                for directory in directories.get(alias, []):
                    target = directory / (name[-1] + '.qml')
                    if target.is_file():
                        dependencies.add(target)
                        self.instance_roots[node.id] = target.resolve()
                if name[-1] == 'Loader':
                    for binding in child(node, 'initializer').named_children:
                        if binding.type == 'ui_binding' and self.text(child(binding, 'name')) == 'source':
                            value = self.unwrap(child(binding, 'value'))
                            if not any(part.type == 'string' for part in walk(value)):
                                self.issue(binding, 'unresolved-loader-source')
            if node.type == 'string':
                value = self.literal(node)
                if value and value.split('?', 1)[0].endswith(('.qml', '.js')) and not value.startswith(('file:', 'http:', 'https:')):
                    target = path.parent / value.split('?', 1)[0]
                    # A literal QML dependency must exist. Do not silently lose a
                    # newly introduced Loader child from coverage.
                    if not target.is_file():
                        self.issue(node, 'unresolved-local-source:' + value)
                    else:
                        dependencies.add(target)
        for target in sorted(dependencies):
            self.load(target)

    def scope(self, node):
        while node and node.id not in self.scopes:
            node = node.parent
        return node.id if node else 0

    def lookup(self, node, name):
        current = self.scope(node)
        while current:
            found = self.member(current, name)
            if found:
                return found
            current = self.scopes[current]
        return None

    def member(self, owner, name):
        own = self.declarations.get((owner, name))
        if own:
            return own
        inherited = self.instance_roots.get(owner)
        if inherited and inherited in self.units:
            root = child(self.units[inherited].tree.root_node, 'root')
            return self.declarations.get((root.id, name)) if root else None
        return None

    def prepare(self):
        # Declarations, not identifier spelling, own flow facts. A same-named
        # parameter/child method cannot borrow a parent's field capability.
        for unit in self.units.values():
            for node in walk(unit.tree.root_node):
                if node.type in FUNCTIONS | {'ui_object_definition', 'statement_block'}:
                    self.scopes[node.id] = self.scope(node.parent)
                if node.type == 'ui_binding' and self.text(child(node, 'name')) == 'id':
                    self.ids[(unit.path, self.text(self.unwrap(child(node, 'value'))))] = self.scope(node)
                if node.type in ('ui_property', 'variable_declarator'):
                    name = self.text(child(node, 'name'))
                    self.declarations[(self.scope(node), name)] = node
                if node.type == 'ui_signal':
                    self.declarations[(self.scope(node), self.text(child(node, 'name')))] = node
                if node.type in FUNCTIONS:
                    self.functions[node.id] = node
                    name = self.text(child(node, 'name'))
                    if name:
                        self.declarations[(self.scope(node.parent), name)] = node
                    parameters = child(node, 'parameters') or child(node, 'parameter')
                    for parameter in parameters.named_children if parameters and parameters.type == 'formal_parameters' else [parameters] if parameters else []:
                        param = self.unwrap(parameter)
                        self.declarations[(node.id, self.text(param))] = param
        for unit in self.units.values():
            for node in walk(unit.tree.root_node):
                if unit.offset and node.type == 'function_declaration' and self.text(child(node, 'name')) == '__script':
                    self.js_modules[unit.path] = child(node, 'body').id
                if node.type == 'ui_binding':
                    name = self.text(child(node, 'name'))
                    declaration = self.member(self.scope(node), name)
                    if declaration and declaration.type == 'ui_property':
                        # Bind imported component callback properties to the
                        # supplied closure, without guessing by a method name.
                        self.env.setdefault(declaration.id, EMPTY)
                    if name.startswith('on'):
                        signal_name = name[2:3].lower() + name[3:]
                        signal = self.member(self.scope(node), signal_name)
                        if signal and signal.type == 'ui_signal':
                            self.signal_handlers.setdefault(signal.id, []).append(node)

    def name_ref(self, node, name):
        declaration = self.lookup(node, name)
        if declaration:
            if declaration.type in FUNCTIONS:
                return frozenset({('function', declaration.id)})
            if declaration.type == 'ui_signal':
                return frozenset({('signal', declaration.id)})
            # The generic page's injected API is always an editor-page role.
            if name == 'pluginApi' and declaration.type == 'ui_property':
                return frozenset({('api',)})
            if declaration.id in self.frame:
                return self.frame[declaration.id]
            return self.env.get(declaration.id, EMPTY)
        identity = self.ids.get((self.unit(node).path, name))
        if identity:
            return frozenset({('object', identity)})
        module = self.imports.get((self.unit(node).path, name))
        if module in self.js_modules:
            return frozenset({('object', self.js_modules[module])})
        if name == 'pluginApi':
            return frozenset({('api',)})
        return EMPTY

    def property(self, node):
        if node.type == 'member_expression':
            return {self.text(child(node, 'property'))}
        return self.keyset(child(node, 'index')) or set()

    def concatenate(self, node, left, right):
        # The domain must stay finite even for a loop such as key += suffix
        # feeding a computed API lookup. Do not truncate to a guessed key set.
        facts = self.string_facts.setdefault(node.id, set())
        result = set()
        for a in left:
            for b in right:
                value = a + b
                facts.add(value)
                if len(facts) > 128 or len(value) > 1024:
                    raise RuntimeError('unbounded-string-facts')
                result.add(value)
        return result

    def record_value(self, identity, props, seen=frozenset()):
        if identity in seen:
            return EMPTY
        seen = seen | {identity}
        record = self.byid[identity]
        result = set()
        for pair in record.named_children:
            if pair.type == 'pair' and self.text(child(pair, 'key')).strip('"\'') in props:
                result.update(self.value(child(pair, 'value')))
        for prop in props:
            result.update(self.record_members.get(identity, {}).get(prop, EMPTY))
        for source in self.record_sources.get(identity, EMPTY):
            if source[0] == 'record':
                result.update(self.record_value(source[1], props, seen))
            elif source[0] == 'read':
                # Object.assign copies the container, not nested values.
                result.add(source)
        return frozenset(result)

    def explicit_member_copy(self, node):
        # A directly preceding overwrite of this exact computed member by a
        # new local container supersedes the inherited member at this use.
        base, index = child(node, 'object'), child(node, 'index')
        if node.type != 'subscript_expression' or not base or not index or base.type != 'identifier' or index.type != 'identifier':
            return None
        statement = node
        while statement.parent and statement.parent.type not in FUNCTIONS | {'statement_block'}:
            statement = statement.parent
        if not statement.parent or statement.parent.type != 'statement_block' or statement.type != 'expression_statement':
            return None
        prev = statement.prev_named_sibling
        if not prev or prev.type != 'expression_statement':
            return None
        assignment = self.unwrap(prev)
        if assignment.type != 'assignment_expression':
            return None
        left = child(assignment, 'left')
        if left.type != 'subscript_expression' or self.text(left) != self.text(node):
            return None
        for name in ('object', 'index'):
            a, b = child(left, name), child(node, name)
            if not self.lookup(a, self.text(a)) or self.lookup(a, self.text(a)) != self.lookup(b, self.text(b)):
                return None
        # Only the reviewed simple use form: copy immediately before assigning
        # a nested leaf. No intervening callee or rebinding of the index/base.
        outer = child(self.unwrap(statement), 'left')
        if not outer or child(outer, 'object') != node:
            return None
        right = self.value(child(assignment, 'right'))
        return right if right and all(fact[0] == 'record' for fact in right) else None

    def keyset(self, node, seen=frozenset()):
        node = self.unwrap(node)
        if not node or node.id in seen:
            return None
        seen = seen | {node.id}
        if node.type == 'string':
            value = self.literal(node)
            return {value} if value is not None else None
        if node.type == 'ternary_expression':
            left, right = self.keyset(child(node, 'consequence'), seen), self.keyset(child(node, 'alternative'), seen)
            return left | right if left is not None and right is not None else None
        if node.type == 'binary_expression' and self.text(child(node, 'operator')) == '+':
            left, right = self.keyset(child(node, 'left'), seen), self.keyset(child(node, 'right'), seen)
            return self.concatenate(node, left, right) if left is not None and right is not None else None
        if node.type == 'identifier':
            declaration = self.lookup(node, self.text(node))
            if declaration and child(declaration, 'value'):
                if self.keyset(child(declaration, 'value'), seen) is None:
                    return None
        values = self.value(node)
        return {value[1] for value in values} if values and all(value[0] == 'string' for value in values) else None

    def value(self, node):
        node = self.unwrap(node)
        if not node:
            return EMPTY
        if node.type == 'string':
            value = self.literal(node)
            return frozenset({('string', value)}) if value is not None else EMPTY
        if node.type == 'identifier':
            return self.name_ref(node, self.text(node))
        if node.type in FUNCTIONS:
            return frozenset({('function', node.id)})
        if node.type == 'object':
            return frozenset({('record', node.id)})
        if node.type in ('member_expression', 'subscript_expression'):
            local = self.explicit_member_copy(node)
            if local is not None:
                return local
            base = self.value(child(node, 'object'))
            props = self.property(node)
            result = set()
            if props & {'pluginSettings', 'initialSettings', 'settingsView'}:
                result.add(('read',))
            for item in base:
                if item[0] == 'object':
                    for prop in props:
                        declaration = self.member(item[1], prop)
                        if declaration:
                            result.update({('function', declaration.id)} if declaration.type in FUNCTIONS else self.env.get(declaration.id, EMPTY))
                        if prop == 'pluginApi':
                            result.add(('api',))
                elif item[0] == 'record':
                    result.update(self.record_value(item[1], props))
                elif item[0] == 'read':
                    if props & MUTATORS:
                        result.add(('read-mutator',))
                    else:
                        result.add(item)
                elif item[0] == 'read-descriptor' and 'value' in props:
                    result.add(('read',))
                elif item[0] == 'handle' and 'value' in props:
                    result.add(('read',))
                elif item[0] == 'api':
                    if not props:
                        result.add(('unknown-api-method',))
                    for prop in props:
                        if prop in ('field', 'contentField', 'resetFields', 'previewSettings'):
                            result.add(('api-method', prop))
                elif item[0] == 'handle':
                    if not props:
                        result.add(('unknown-api-method',))
                    for prop in props:
                        if prop in ('set', 'reset'):
                            result.add(('intent-method', item[1], item[2], prop))
                elif item[0] in ('intent-method', 'read-mutator') and props & {'call', 'apply', 'bind'}:
                    result.add(item)
            if self.text(node) in ('Object.assign', 'Object.defineProperty', 'Object.defineProperties', 'Reflect.set', 'Reflect.deleteProperty'):
                result.add(('builtin', self.text(node)))
            return frozenset(result)
        if node.type == 'call_expression':
            function = child(node, 'function')
            functions = self.value(function)
            args = child(node, 'arguments')
            arguments = args.named_children if args else []
            values = [self.value(argument) for argument in arguments]
            result = set()
            for item in functions:
                if item[0] == 'function':
                    getter = self.getter(self.functions[item[1]], values)
                    result.update(self.returns.get(item[1], EMPTY) if getter is None else getter)
                if item[0] == 'api-method' and item[1] in ('field', 'contentField'):
                    keys = self.keyset(arguments[0]) if arguments else None
                    # A finite includes guard is a checked domain, not an
                    # invented field schema or a broad computed-key waiver.
                    if keys is None and arguments:
                        keys = self.guarded_keys(node, arguments[0])
                    result.update(('handle', 'content' if item[1] == 'contentField' else 'configuration', key) for key in keys or ())
                if item[0] in ('read-mutator', 'intent-method') and function.type in ('member_expression', 'subscript_expression') and self.property(function) == {'bind'}:
                    result.add(item)
            if ('builtin', 'Object.assign') in functions and values:
                return values[0]
            if self.text(function) == 'JSON.parse':
                return EMPTY
            if self.text(function) == 'Object.getOwnPropertyDescriptor' and values and any(value[0] == 'read' for value in values[0]):
                return frozenset({('read-descriptor',)})
            return frozenset(result)
        if node.type == 'ternary_expression':
            return self.value(child(node, 'consequence')) | self.value(child(node, 'alternative'))
        if node.type == 'binary_expression':
            operator = self.text(child(node, 'operator'))
            if operator in ('||', '&&', '??'):
                return self.value(child(node, 'left')) | self.value(child(node, 'right'))
            if operator == '+':
                left = [fact[1] for fact in self.value(child(node, 'left')) if fact[0] == 'string']
                right = [fact[1] for fact in self.value(child(node, 'right')) if fact[0] == 'string']
                return frozenset(('string', value) for value in self.concatenate(node, left, right))
            return EMPTY
        if node.type == 'array':
            return union(self.value(part) for part in node.named_children)
        return EMPTY

    def getter(self, function, arguments):
        """Call-site return flow for pure helpers, not one global alias union.

        In particular own(ownedCopy,key) must not borrow the readonly provenance
        of an unrelated own(namespace,key) call. Mutation/effectful helpers stay
        in the normal explicit graph; only declarations plus one return qualify.
        """
        if function.id in self.active_getters:
            return None
        body = child(function, 'body')
        if not body or body.type != 'statement_block':
            return None
        statements = [part for part in body.named_children if part.type != 'comment']
        if not statements or statements[-1].type != 'return_statement' or any(part.type not in
                ('lexical_declaration', 'variable_declaration', 'return_statement') for part in statements):
            return None
        if sum(part.type == 'return_statement' for part in statements) != 1:
            return None
        # Resolve only known pure getter calls, without assigning a purity
        # meaning to an arbitrary same-spelled external method.
        for node in walk(body):
            if node.type in ('assignment_expression', 'update_expression', 'augmented_assignment_expression', 'new_expression'):
                return None
            if node.type == 'call_expression':
                fn = child(node, 'function')
                refs = self.value(fn)
                if self.text(fn) != 'Object.getOwnPropertyDescriptor' and not (refs and all(value[0] == 'function' or
                    (value[0] == 'api-method' and value[1] in ('field', 'contentField')) for value in refs)):
                    return None
        previous = self.frame
        self.frame = previous.copy()
        self.active_getters.add(function.id)
        try:
            params = child(function, 'parameters') or child(function, 'parameter')
            params = params.named_children if params and params.type == 'formal_parameters' else [params] if params else []
            for parameter, value in zip(params, arguments):
                self.frame[self.unwrap(parameter).id] = value
            for statement in statements[:-1]:
                for declaration in statement.named_children:
                    if declaration.type == 'variable_declarator':
                        self.frame[declaration.id] = self.value(child(declaration, 'value'))
            return union(self.value(part) for part in statements[-1].named_children)
        finally:
            self.active_getters.remove(function.id)
            self.frame = previous

    def caller(self, node):
        current = node.parent
        while current:
            if current.type in FUNCTIONS | {'ui_binding', 'ui_property'}:
                return current
            current = current.parent
        return None

    def calls(self, node):
        values = self.value(child(node, 'function'))
        expanded = set(values)
        for value in values:
            if value[0] == 'signal':
                for handler in self.signal_handlers.get(value[1], []):
                    expanded.update(self.value(child(handler, 'value')))
        return expanded

    def writer_call(self, node):
        return node.type == 'call_expression' and any(value[0] == 'intent-method' or
            (value[0] == 'api-method' and value[1] in ('previewSettings', 'resetFields'))
            for value in self.value(child(node, 'function')))

    def required_conditions(self, node):
        """Positive predicates implied by containing branches, not descendants of a test."""
        def atoms(expression, positive):
            expression = self.unwrap(expression)
            if not expression:
                return
            operator = self.text(child(expression, 'operator'))
            if expression.type == 'unary_expression' and operator == '!':
                yield from atoms(child(expression, 'argument'), not positive)
            elif expression.type == 'binary_expression' and operator == ('&&' if positive else '||'):
                for side in ('left', 'right'):
                    yield from atoms(child(expression, side), positive)
            elif positive:
                yield expression

        current = node
        while current.parent and current.parent.type not in FUNCTIONS:
            parent = current.parent
            if parent.type in ('if_statement', 'ternary_expression'):
                if current == child(parent, 'consequence'):
                    yield from atoms(child(parent, 'condition'), True)
                elif current == child(parent, 'alternative'):
                    yield from atoms(child(parent, 'condition'), False)
            # tree-sitter wraps the alternative in an else_clause.
            if current.type == 'else_clause' and parent.type == 'if_statement' and current != child(parent, 'alternative'):
                yield from atoms(child(parent, 'condition'), False)
            current = parent

    def guarded_keys(self, node, argument):
        argument = self.unwrap(argument)
        if argument.type != 'identifier':
            return set()
        declaration = self.lookup(argument, self.text(argument))
        if not declaration:
            return set()
        for call in self.required_conditions(node):
            fn = child(call, 'function')
            args = child(call, 'arguments')
            if not fn or fn.type != 'member_expression' or self.text(child(fn, 'property')) != 'includes':
                continue
            items = [self.unwrap(arg) for arg in args.named_children if arg.type != 'comment']
            if len(items) != 1 or items[0].type != 'identifier' or self.lookup(items[0], self.text(items[0])) != declaration:
                continue
            array = child(fn, 'object')
            if array.type == 'array':
                keys = {self.literal(part) for part in array.named_children if part.type != 'comment'}
                if None not in keys:
                    return keys
        return set()

    def add(self, declaration, values):
        if not declaration:
            return False
        old = self.env.get(declaration.id, EMPTY)
        self.env[declaration.id] = old | values
        return self.env[declaration.id] != old

    def solve(self):
        self.prepare()
        nodes = [node for unit in self.units.values() for node in walk(unit.tree.root_node)]
        changed = True
        while changed:
            changed = False
            for node in nodes:
                if node.type in ('ui_property', 'variable_declarator'):
                    values = self.value(child(node, 'value'))
                    if node.type == 'ui_property' and self.text(child(node, 'type')) in ('string', 'bool', 'int', 'real', 'double', 'url', 'color'):
                        # QML scalar storage is not an alias of the read source.
                        values = frozenset(value for value in values if value[0] != 'read')
                    changed |= self.add(node, values)
                if node.type == 'ui_binding':
                    declaration = self.member(self.scope(node), self.text(child(node, 'name')))
                    if declaration and declaration.type == 'ui_property':
                        changed |= self.add(declaration, self.value(child(node, 'value')))
                if node.type == 'assignment_expression':
                    left = child(node, 'left')
                    if left.type == 'identifier':
                        changed |= self.add(self.lookup(left, self.text(left)), self.value(child(node, 'right')))
                    elif left.type in ('member_expression', 'subscript_expression'):
                        for value in self.value(child(left, 'object')):
                            if value[0] != 'record':
                                continue
                            members = self.record_members.setdefault(value[1], {})
                            for key in self.property(left):
                                old = members.get(key, EMPTY)
                                new = old | (self.value(child(node, 'right')) or frozenset({('unknown',)}))
                                members[key] = new
                                changed |= old != new
                if node.type == 'return_statement':
                    owner = node.parent
                    while owner and owner.type not in FUNCTIONS:
                        owner = owner.parent
                    if owner:
                        old = self.returns.get(owner.id, EMPTY)
                        new = old | union(self.value(part) for part in node.named_children)
                        self.returns[owner.id] = new
                        changed |= old != new
                if node.type == 'arrow_function' and child(node, 'body').type != 'statement_block':
                    old = self.returns.get(node.id, EMPTY)
                    new = old | self.value(child(node, 'body'))
                    self.returns[node.id] = new
                    changed |= old != new
                if node.type == 'call_expression':
                    functions = self.calls(node)
                    args = child(node, 'arguments')
                    values = [self.value(argument) for argument in args.named_children] if args else []
                    if ('builtin', 'Object.assign') in functions and values:
                        for target in values[0]:
                            if target[0] == 'record':
                                old = self.record_sources.get(target[1], EMPTY)
                                new = old | union(values[1:])
                                self.record_sources[target[1]] = new
                                changed |= old != new
                    for item in functions:
                        if item[0] != 'function':
                            continue
                        fn = self.functions[item[1]]
                        params = child(fn, 'parameters') or child(fn, 'parameter')
                        params = params.named_children if params and params.type == 'formal_parameters' else [params] if params else []
                        for parameter, value in zip(params, values):
                            changed |= self.add(self.unwrap(parameter), value or frozenset({('unknown',)}))
        for node in nodes:
            if node.type == 'ui_object_definition' and self.text(child(node, 'type_name')).split('.')[-1] in (
                    'ConfigStore', 'PluginPreferenceOwner', 'PluginPreferenceEditor', 'PluginSettingsSession',
                    'PluginSettingsPageApi', 'PluginSettingsFields'):
                self.issue(node, 'page-creates-preference-owner')
            if node.type in ('member_expression', 'subscript_expression'):
                if self.property(node) & NATIVE:
                    self.issue(node, 'page-native-capability')
            if node.type in ('assignment_expression', 'augmented_assignment_expression', 'update_expression'):
                target = child(node, 'left') or child(node, 'argument')
                target_base = child(target, 'object') if target.type in ('member_expression', 'subscript_expression') else None
                if any(item[0] in ('read', 'handle', 'api') for item in self.value(target_base)):
                    self.issue(node, 'page-readonly-write')
            if node.type == 'unary_expression' and self.text(node).startswith('delete ') and any(item[0] == 'read' for item in self.value(child(node, 'argument'))):
                self.issue(node, 'page-readonly-delete')
            if node.type != 'call_expression':
                continue
            fn = child(node, 'function')
            functions = self.value(fn)
            args = child(node, 'arguments')
            arguments = args.named_children if args else []
            caller = self.caller(node)
            for value in self.calls(node):
                if value[0] == 'function' and caller:
                    self.edges.setdefault(caller.id, set()).add(value[1])
            if fn.type in ('member_expression', 'subscript_expression'):
                props = self.property(fn)
                base = self.value(child(fn, 'object'))
                if props & MUTATORS and any(item[0] == 'read' for item in base):
                    self.issue(node, 'page-readonly-mutator')
                if props & {'apply', 'save', 'flush', 'setValue', 'unset'} and any(item[0] in ('read', 'api', 'handle') for item in base):
                    self.issue(node, 'page-publication-bypass')
            if any(value[0] == 'builtin' for value in functions) and arguments and \
               any(item[0] in ('read', 'handle', 'api') for item in self.value(arguments[0])):
                self.issue(node, 'page-readonly-helper-write')
            for item in functions:
                if item[0] == 'api-method' and item[1] in ('field', 'contentField'):
                    handles = [value for value in self.value(node) if value[0] == 'handle']
                    if not handles:
                        self.issue(node, 'unresolved-field-key')
                    for _, usage, key in handles:
                        self.field_calls.add((str(self.unit(node).path.relative_to(self.plugin)), node.start_point.row + 1, usage, key))
                        if key not in self.fields or self.fields[key].get('editorUsage') != usage:
                            self.issue(node, 'undeclared-field-usage:' + str(key))
                if item[0] == 'api-method' and item[1] in ('previewSettings', 'resetFields'):
                    values = self.value(arguments[0]) if arguments else EMPTY
                    keys = set()
                    unknown = not values
                    for value in values:
                        if item[1] == 'resetFields' and value[0] == 'string':
                            keys.add(value[1])
                        elif item[1] == 'previewSettings' and value[0] == 'record':
                            record = self.byid[value[1]]
                            keys.update(self.text(child(pair, 'key')).strip('"\'') for pair in record.named_children if pair.type == 'pair')
                            keys.update(self.record_members.get(value[1], {}))
                            for assignment in nodes:
                                if assignment.type != 'assignment_expression':
                                    continue
                                target = child(assignment, 'left')
                                if target.type in ('member_expression', 'subscript_expression') and value in self.value(child(target, 'object')) and not self.property(target):
                                    unknown = True
                        else:
                            unknown = True
                    if unknown:
                        self.issue(node, 'unresolved-' + item[1] + '-keys')
                    for key in keys:
                        if key not in self.fields or self.fields[key].get('editorUsage') != 'configuration':
                            self.issue(node, 'undeclared-field-usage:' + str(key))
                        self.intents.add((str(self.unit(node).path.relative_to(self.plugin)), node.start_point.row + 1, 'configuration', str(key), item[1]))
                if item[0] == 'intent-method':
                    self.intents.add((str(self.unit(node).path.relative_to(self.plugin)), node.start_point.row + 1, item[1], item[2], item[3]))
                    owner = node.parent
                    while owner and owner.type not in FUNCTIONS | {'ui_binding'}:
                        owner = owner.parent
                    if not owner or (owner.type == 'ui_binding' and not self.text(child(owner, 'name')).split('.')[-1].startswith('on')):
                        self.issue(node, 'construction-time-field-intent')
                if item[0] == 'unknown-api-method':
                    self.issue(node, 'unresolved-computed-api-call')
                if item[0] == 'read-mutator':
                    self.issue(node, 'page-readonly-mutator')
            # A detached writer method must not escape into an unclassified
            # callback; helper declarations are resolved above by identity.
            if not functions:
                for argument in arguments:
                    if any(value[0] == 'intent-method' for value in self.value(argument)):
                        self.issue(node, 'unclassified-writer-callback')
        # Propagate actual declaration call edges from QML event/pending-input
        # entry points. Constructors are a distinct origin, not an event alias.
        origins = {}
        for node in nodes:
            if node.type == 'ui_property':
                origins.setdefault(node.id, set()).add('construction')
            if node.type == 'ui_binding':
                name = self.text(child(node, 'name'))
                origin = 'construction' if name == 'Component.onCompleted' else 'event:' + name if name.startswith('on') else None
                owner = self.byid.get(self.scope(node))
                if name == 'requestValue' and self.text(child(owner, 'type_name')).split('.')[-1] == 'NSpinBox':
                    origins.setdefault(node.id, set()).add('construction')
                    for value in self.value(child(node, 'value')):
                        if value[0] == 'function':
                            origins.setdefault(value[1], set()).add('event:requestValue')
                if origin:
                    origins.setdefault(node.id, set()).add(origin)
                    for value in self.value(child(node, 'value')):
                        if value[0] == 'function':
                            self.edges.setdefault(node.id, set()).add(value[1])
            if node.type == 'function_declaration' and self.text(child(node, 'name')) == 'saveSettings' and not self.unit(node).offset:
                origins.setdefault(node.id, set()).add('pending-input')
            if node.type == 'function_declaration' and self.text(child(node, 'name')) in self.fixture_inputs:
                origins.setdefault(node.id, set()).add('fixture-input')
        changed = True
        while changed:
            changed = False
            for caller, callees in self.edges.items():
                for callee in callees:
                    old = origins.get(callee, set())
                    new = old | origins.get(caller, set())
                    if old != new:
                        origins[callee] = new
                        changed = True

        def buffered_content_guard(call):
            dirty = self.lookup(call, 'settingsDirty')
            expression = self.unwrap(child(dirty, 'value')) if dirty else None
            if not expression:
                return False
            buffers = set()
            for reference in walk(expression):
                if reference.type != 'identifier':
                    continue
                declaration = self.lookup(reference, self.text(reference))
                if declaration and declaration.type == 'ui_property':
                    initial = self.unwrap(child(declaration, 'value'))
                    if not initial or compact(self.unit(initial), initial) not in ('false', '""', "''"):
                        return False
                    buffers.add(declaration.id)
            if not buffers:
                return False
            edited = set()
            for assignment in nodes:
                if assignment.type != 'assignment_expression':
                    continue
                target = child(assignment, 'left')
                declaration = self.lookup(target, self.text(target)) if target.type == 'identifier' else None
                if target.type == 'member_expression':
                    owners = self.value(child(target, 'object'))
                    for owner in owners:
                        if owner[0] == 'object':
                            declaration = self.member(owner[1], self.text(child(target, 'property')))
                caller = self.caller(assignment)
                flow = origins.get(caller.id, set()) if caller else set()
                if declaration and declaration.id in buffers and any(value.startswith('event:') and not value.endswith('Changed') for value in flow) and 'construction' not in flow:
                    edited.add(declaration.id)
            if edited != buffers:
                return False
            expected = compact(self.unit(expression), expression)
            for condition in self.required_conditions(call):
                if compact(self.unit(condition), condition) == expected:
                    return True
                if condition.type == 'identifier' and self.lookup(condition, self.text(condition)) == dirty:
                    return True
            return False

        for node in nodes:
            if not self.writer_call(node):
                continue
            caller = self.caller(node)
            flow = origins.get(caller.id, set()) if caller else set()
            if 'construction' in flow:
                self.issue(node, 'construction-call-reaches-field-intent')
            if not flow:
                self.issue(node, 'unclassified-field-intent-entry')
            if 'pending-input' in flow and any(value[0] == 'intent-method' and value[1] == 'content'
                for value in self.value(child(node, 'function'))) and not buffered_content_guard(node):
                self.issue(node, 'configuration-apply-collects-content')

    def report(self):
        return dict(files=sorted(str(path.relative_to(self.plugin)) for path in self.units),
                    fieldReads=[list(row) for row in sorted(self.field_calls)], intents=[list(row) for row in sorted(self.intents)],
                    issues=[dict(file=file, line=line, code=code) for file, line, code in sorted(self.issues)])


def selftest():
    fields = dict(message=dict(type='String', editorUsage='configuration'),
                  items=dict(type='List', editorUsage='configuration'),
                  todos=dict(type='List', editorUsage='content'), count=dict(type='Integer', editorUsage='operational'))
    prefix = 'import QtQuick\nItem { id: root; property var pluginApi: null; '
    tests = {
        'event': ('readonly property var selected: pluginApi.field("message"); onClicked: selected.set("ok");', None),
        'alias-event': ('readonly property var selected: pluginApi.field("message"); function edit(value) { selected.set(value); } onClicked: root.edit("ok");', None),
        'helper-key': ('function field(key) { return pluginApi.field(key); } onClicked: field("message").set("ok");', None),
        'computed-key': ('onClicked: { const method="fi"+"eld"; const handle=pluginApi[method]("message"); handle.set("ok"); }', None),
        'scalar-buffer': ('property string text: pluginApi.pluginSettings.message; onClicked: { root.text="edit"; pluginApi.field("message").set(root.text); }', None),
        'owned-display': ('onClicked: { const local=Object.assign({}, pluginApi.pluginSettings); local.message="edit"; pluginApi.field("message").set(local.message); }', None),
        'namespace': ('onClicked: pluginApi.pluginSettings.message="bad";', 'page-readonly-write'),
        'alias': ('onClicked: { const ns=pluginApi.pluginSettings; const alias=ns; alias.message="bad"; }', 'page-readonly-write'),
        'helper-argument': ('function edit(target) { target.message="bad"; } onClicked: edit(pluginApi.pluginSettings);', 'page-readonly-write'),
        'helper-return': ('function read() { return pluginApi.pluginSettings; } onClicked: read()["message"]="bad";', 'page-readonly-write'),
        'descriptor-getter': ('function own(value,key) { var p=value ? Object.getOwnPropertyDescriptor(value,key) : null; return p ? p.value : undefined; } onClicked: own(pluginApi.pluginSettings,"items").push({});', 'page-readonly-mutator'),
        'getter-callsite-isolation': ('function own(value,key) { var p=value ? Object.getOwnPropertyDescriptor(value,key) : null; return p ? p.value : undefined; } onClicked: { const shown=own(pluginApi.pluginSettings,"items"); const next=JSON.parse(JSON.stringify(pluginApi.pluginSettings)); const items=own(next,"items"); items.push({}); }', None),
        'nested': ('onClicked: pluginApi.pluginSettings.items[0].value="bad";', 'page-readonly-write'),
        'mutator': ('onClicked: { const rows=pluginApi.pluginSettings.items; rows.push({}); }', 'page-readonly-mutator'),
        'mutator-alias': ('onClicked: { const edit=pluginApi.pluginSettings.items["push"]; edit({}); }', 'page-readonly-mutator'),
        'mutator-bound': ('onClicked: { const edit=pluginApi.pluginSettings.items.push.bind(pluginApi.pluginSettings.items); edit({}); }', 'page-readonly-mutator'),
        'assignment-helper': ('onClicked: Object.assign(pluginApi.pluginSettings, {message:"bad"});', 'page-readonly-helper-write'),
        'assignment-helper-alias': ('onClicked: { const write=Object.assign; write(pluginApi.pluginSettings, {message:"bad"}); }', 'page-readonly-helper-write'),
        'delete': ('onClicked: delete pluginApi.pluginSettings.items[0];', 'page-readonly-delete'),
        'unknown-key': ('onClicked: pluginApi.field(text).set("bad");', 'unresolved-field-key'),
        'membership-required': ('function use(key) { if (["message"].includes(key) && enabled) pluginApi.field(key).set("ok"); } onClicked: use(text);', None),
        'membership-optional': ('function use(key) { if (["message"].includes(key) || enabled) pluginApi.field(key).set("bad"); } onClicked: use(text);', 'unresolved-field-key'),
        'membership-else': ('function use(key) { if (["message"].includes(key)) {} else { pluginApi.field(key).set("bad"); } } onClicked: use(text);', 'unresolved-field-key'),
        'partly-unknown-key': ('onClicked: pluginApi.field(enabled ? "message" : text).set("bad");', 'unresolved-field-key'),
        'undeclared': ('onClicked: pluginApi.field("missing").set("bad");', 'undeclared-field-usage:missing'),
        'content-config': ('onClicked: pluginApi.field("todos").set([]);', 'undeclared-field-usage:todos'),
        'operational-config': ('onClicked: pluginApi.field("count").set(0);', 'undeclared-field-usage:count'),
        'shared-content-command': ('onClicked: pluginApi.contentField("todos").set([]);', None),
        'implicit-content-save': ('function saveSettings() { pluginApi.contentField("todos").set([]); }', 'configuration-apply-collects-content'),
        'buffered-content-input': ('property bool pending:false; readonly property bool settingsDirty:pending; onTextEdited: pending=true; function saveSettings() { if(pending) pluginApi.contentField("todos").set([]); }', None),
        'buffer-bypassed': ('property bool pending:false; readonly property bool settingsDirty:pending; onTextEdited: pending=true; function saveSettings() { if(pending || enabled) pluginApi.contentField("todos").set([]); }', 'configuration-apply-collects-content'),
        'runtime-acquisition': ('onClicked: Service.getPluginAPI("foreign");', 'page-native-capability'),
        'second-owner': ('PluginSettingsSession {}', 'page-creates-preference-owner'),
        'native': ('onClicked: pluginApi.createSettingsEditor(true);', 'page-native-capability'),
        'constructor': ('Component.onCompleted: pluginApi.field("message").set("bad");', 'construction-call-reaches-field-intent'),
        'constructor-helper': ('function edit() { pluginApi.field("message").set("bad"); } Component.onCompleted: edit();', 'construction-call-reaches-field-intent'),
        'property-constructor-helper': ('function edit() { pluginApi.field("message").set("bad"); } property var eager: edit(); onClicked: edit();', 'construction-call-reaches-field-intent'),
        'shallow-copy': ('onClicked: { const local=Object.assign({}, { rows: pluginApi.pluginSettings.items }); local.rows.push({}); }', 'page-readonly-mutator'),
        'shallow-copy-alias': ('onClicked: { const copy=Object.assign; const local=copy({}, pluginApi.pluginSettings); local.items.push({}); }', 'page-readonly-mutator'),
        'reset-content': ('onClicked: pluginApi.resetFields(["todos"]);', 'undeclared-field-usage:todos'),
        'preview-content': ('onClicked: pluginApi.previewSettings({todos: []});', 'undeclared-field-usage:todos'),
        'preview-computed-content': ('onClicked: { const next={}; const key="todos"; next[key]=[]; pluginApi.previewSettings(next); }', 'undeclared-field-usage:todos'),
        'preview-unknown-key': ('onClicked: { const next={}; next[text]=[]; pluginApi.previewSettings(next); }', 'unresolved-previewSettings-keys'),
        'field-value-write': ('onClicked: pluginApi.field("items").value.push({});', 'page-readonly-mutator'),
        'shadow': ('readonly property var handle: pluginApi.field("message"); function edit(handle) { handle.message="local"; } onClicked: edit({});', None),
        'getter-does-not-taint-condition': ('property string text: pluginApi.pluginSettings.message; onClicked: { const local=pluginApi.pluginSettings ? {} : {}; local.message="local"; }', None),
    }
    results = []
    with tempfile.TemporaryDirectory(prefix='plugin-settings-boundary-') as directory:
        root = Path(directory)
        for name, (body, expected) in tests.items():
            path = root / 'Page.qml'
            path.write_text(prefix + body + ' }\n')
            pages = Pages(root, fields)
            pages.load(path)
            pages.solve()
            codes = {row['code'] for row in pages.report()['issues']}
            if (expected is None and codes) or (expected is not None and expected not in codes):
                raise RuntimeError('boundary control ' + name + ': expected ' + str(expected) + ', got ' + repr(codes))
            results.append(dict(id=name, status='PASS', expected=expected))
        # Loaded-child traversal uses the actual local type edge, not a path
        # containing Settings. A same-named unrelated runtime file is not loaded.
        (root / 'Page.qml').write_text(prefix + 'Child { pluginApi: root.pluginApi } }\n')
        (root / 'Child.qml').write_text(prefix + 'onClicked: pluginApi.pluginSettings.items.push({}); }\n')
        pages = Pages(root, fields)
        pages.load(root / 'Page.qml')
        pages.solve()
        if not any(row['file'] == 'Child.qml' and row['code'] == 'page-readonly-mutator' for row in pages.report()['issues']):
            raise RuntimeError('loaded child writer escaped the page graph')
        results.append(dict(id='loaded-child', status='PASS', expected='page-readonly-mutator'))
        (root / 'Page.qml').write_text('import QtQuick\nimport "Bridge.js" as Bridge\nItem { property var pluginApi; onClicked: Bridge.forward(pluginApi) }\n')
        (root / 'Bridge.js').write_text('.pragma library\n.import "Writer.js" as Writer\nfunction forward(api) { Writer.mutate(api); }\n')
        (root / 'Writer.js').write_text('function mutate(api) { api.pluginSettings.items.push({}); }\n')
        pages = Pages(root, fields)
        pages.load(root / 'Page.qml')
        pages.solve()
        if not any(row['file'] == 'Writer.js' and row['code'] == 'page-readonly-mutator' for row in pages.report()['issues']):
            raise RuntimeError('local JS import writer escaped the page graph')
        results.append(dict(id='imported-script-writer', status='PASS', expected='page-readonly-mutator'))
        (root / 'Page.qml').write_text(prefix + 'onClicked: { let key="x"; key=key+"x"; } }\n')
        pages = Pages(root, fields)
        pages.load(root / 'Page.qml')
        try:
            pages.solve()
        except RuntimeError as error:
            if str(error) != 'unbounded-string-facts':
                raise
        else:
            raise RuntimeError('recursive key growth escaped the string budget')
        results.append(dict(id='recursive-string-domain', status='PASS', expected='unbounded-string-facts'))
    return results


def parsed(path, text=None):
    text = path.read_text() if text is None else text
    offset = 0
    if path.suffix == '.js':
        text, _ = js_body(text)
        text = 'import QtQml\nQtObject { function __script() {\n' + text + '\n} }\n'
        offset = 2
    source = text.encode()
    return Unit(path, source, Parser(Language(tree_sitter_qmljs.language())).parse(source), offset)


def compact(unit, node):
    # Tokens from an already parsed node, not whitespace/comment-shaped regex
    # assertions. Strings retain their exact literal identity.
    def tokens(part):
        if part.type == 'comment':
            return []
        if not part.children:
            return [unit.text(part)]
        return [token for nested in part.children for token in tokens(nested)]
    return ''.join(tokens(node))


def shell_boundary(source, overrides=None):
    overrides = overrides or {}
    issues = []
    units = {}
    paths = ('Services/Plugins/PluginLoader.qml', 'Services/Plugins/PluginContract.js',
             'Services/Plugins/PluginView.qml', 'Services/Plugins/PluginSettingsSession.qml',
             'Services/Plugins/PluginSettingsPageApi.qml', 'Services/Plugins/PluginSettingsFields.qml',
             'Widgets/NPluginSettingsPopup.qml')
    for name in paths:
        unit = parsed(source / name, overrides.get(name))
        units[name] = unit
        if unit.tree.root_node.has_error:
            issues.append(dict(file=name, code='shell-parse-error'))

    def require(name, method, predicate, code):
        unit = units[name]
        functions = [node for node in walk(unit.tree.root_node) if node.type == 'function_declaration' and unit.text(child(node, 'name')) == method]
        if len(functions) != 1 or not predicate(unit, functions[0]):
            issues.append(dict(file=name, code=code))

    def contains(unit, method, pattern):
        return any(compact(unit, node) == pattern for node in walk(method))

    def guarded(unit, method):
        body = child(method, 'body')
        first = next((node for node in body.named_children if node.type != 'comment'), None)
        consequence = child(first, 'consequence')
        return first and first.type == 'if_statement' and compact(unit, child(first, 'condition')) == '(!PluginContract.acceptsApi(entryPoint,api))' and \
            exits(consequence, 'throw_statement') and \
            contains(unit, method, 'props={"pluginApi":api}') and \
            [compact(unit, node) for node in walk(method) if node.type == 'return_statement'] == ['returnprops;']

    def statements(block):
        return [node for node in block.named_children if node.type != 'comment'] if block else []

    def exits(body, kind):
        return body and (body.type == kind or body.type == 'statement_block'
                         and any(node.type == kind for node in statements(body)))

    def admitted_construction(unit, fn, target, admission, call_method, construction, same_try):
        # This checker recognizes the two reviewed finite control shapes. A
        # matching call hidden under a branch is not a proof of dominance.
        body = child(fn, 'body')
        attempts = [node for node in statements(body) if node.type == 'try_statement']
        sites = [node for node in walk(fn) if node.type == 'call_expression' and
                 unit.text(child(child(node, 'function'), 'property')) == call_method]
        if len(attempts) != 1 or len(sites) != 1 or compact(unit, sites[0]) != construction:
            return False
        attempt, site = attempts[0], sites[0]
        protected = statements(child(attempt, 'body'))
        if not protected or compact(unit, protected[0]).rstrip(';') != target + '=' + admission:
            return False
        if not exits(child(child(attempt, 'handler'), 'body'), 'return_statement') or child(attempt, 'finalizer'):
            return False
        assignments = [node for node in walk(fn) if node.type == 'assignment_expression' and compact(unit, child(node, 'left')) == target]
        if len(assignments) != 1:
            return False
        if same_try:
            return len(protected) == 2 and compact(unit, protected[1]).rstrip(';') == 'instance=' + construction
        following = statements(body)[statements(body).index(attempt) + 1:]
        return len(protected) == 1 and [compact(unit, part).rstrip(';') for part in following] == ['_initial=' + target, construction]

    require(paths[0], 'initialProperties', guarded, 'generic-role-not-admitted-before-properties')
    require(paths[0], 'createObject', lambda unit, fn: admitted_construction(unit, fn, 'initial',
            'initialProperties(entryPoint,component.url,api,context)', 'createObject', 'component.createObject(parent,initial)', True),
            'direct-construction-bypasses-admission')
    require(paths[2], '_reload', lambda unit, fn: admitted_construction(unit, fn, 'props',
            'PluginLoader.initialProperties(entryPoint,url,api,context)', 'setSource', 'loader.setSource(url,props)', False),
            'view-construction-bypasses-admission')
    require(paths[1], 'apiRole', lambda unit, fn: contains(unit, fn, 'entryPoint==="settings"?"settings-editor":"runtime"'), 'generic-role-declaration')
    require(paths[1], 'acceptsApi', lambda unit, fn: [compact(unit, node) for node in walk(fn) if node.type == 'return_statement'] ==
            ['returnapiRole(entryPoint)!=="settings-editor"||(api!==null&&api!==undefined&&api.apiRole==="settings-editor"&&typeofapi.field==="function"&&typeofapi.contentField==="function");'], 'generic-capability-role-check')
    require(paths[3], '_open', lambda unit, fn: contains(unit, fn, 'currentPluginApi.createSettingsEditor(true)'), 'session-field-capture-required')
    for name in (paths[3], paths[5]):
        for node in walk(units[name].tree.root_node):
            if node.type == 'call_expression' and units[name].text(child(child(node, 'function'), 'property')) == 'apply' and \
               compact(units[name], node) not in ('editor.apply(editor.values,completed)', 'editor.apply(editor.values,callback)'):
                issues.append(dict(file=name, code='generic-apply-values-identity'))
    popup = units[paths[6]]
    if not any(node.type == 'call_expression' and compact(popup, node) ==
               'settingsLoader.setSource(settingsSession.settingsUrl,PluginLoader.initialProperties(settingsSession.settingsEntryPoint,settingsSession.settingsUrl,_pageApi,{}))'
               for node in walk(popup.tree.root_node)):
        issues.append(dict(file=paths[6], code='popup-construction-bypasses-selected-page-api'))
    # A new alternative host cannot instantiate another generic page adapter or
    # field owner. Runtime non-generic editor APIs remain intentionally additive.
    for directory in ('Services', 'Widgets', 'Modules'):
        for path in sorted((source / directory).rglob('*.qml')):
            name = str(path.relative_to(source))
            unit = units.get(name) or parsed(path, overrides.get(name))
            if unit.tree.root_node.has_error:
                issues.append(dict(file=name, code='shell-parse-error'))
            for node in walk(unit.tree.root_node):
                if node.type == 'ui_object_definition' and unit.text(child(node, 'type_name')) in ('PluginSettingsPageApi', 'PluginSettingsFields') and name != paths[3]:
                    issues.append(dict(file=name, code='second-generic-editor-owner'))
                if node.type == 'pair' and unit.text(child(node, 'key')).strip('"\'') == 'pluginApi' and name not in (paths[0], 'Modules/LockScreen/LockScreen.qml'):
                    # Entry property dictionaries belong to PluginLoader. Lock
                    # surfaces use their separate process/protocol contract.
                    issues.append(dict(file=name, code='plugin-api-properties-bypass-loader'))
    # Keep the already proven focused safety replacement contract as a separate
    # gate, not a weaker reimplementation or an alternative publishing path.
    spec = importlib.util.spec_from_file_location('safety_supersession', source / 'Scripts/dev/plugin-settings-safety-supersession-check.py')
    safety = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(safety)
    for issue in safety.inspect(overrides.get(paths[4], (source / paths[4]).read_text()),
                                overrides.get(paths[3], (source / paths[3]).read_text()),
                                'import QtQuick\nItem {}'):
        issues.append(dict(file='generic-selected-owner', code=issue))
    return issues


def shell_controls(source):
    cases = [
        ('role', 'Services/Plugins/PluginLoader.qml', 'if (!PluginContract.acceptsApi(entryPoint, api))', 'if (false)', 'generic-role-not-admitted-before-properties'),
        ('direct', 'Services/Plugins/PluginLoader.qml', 'initialProperties(entryPoint, component.url, api, context)', '({pluginApi: api})', 'direct-construction-bypasses-admission'),
        ('direct-conditional', 'Services/Plugins/PluginLoader.qml', 'initial = initialProperties(entryPoint, component.url, api, context);', 'if (false) initial = initialProperties(entryPoint, component.url, api, context);', 'direct-construction-bypasses-admission'),
        ('view', 'Services/Plugins/PluginView.qml', 'PluginLoader.initialProperties(entryPoint, url, api, context)', '({pluginApi: api})', 'view-construction-bypasses-admission'),
        ('popup', 'Widgets/NPluginSettingsPopup.qml', 'settingsSession.settingsUrl, _pageApi, {}', 'settingsSession.settingsUrl, currentPluginApi, {}', 'popup-construction-bypasses-selected-page-api'),
        ('apply', 'Services/Plugins/PluginSettingsSession.qml', 'editor.apply(editor.values, completed)', 'editor.apply(pageApi.pluginSettings, completed)', 'generic-apply-values-identity'),
        ('capture', 'Services/Plugins/PluginSettingsSession.qml', 'currentPluginApi.createSettingsEditor(true)', 'currentPluginApi.createSettingsEditor()', 'session-field-capture-required'),
        ('contract', 'Services/Plugins/PluginContract.js', 'apiRole(entryPoint) !== "settings-editor" ||', 'true ||', 'generic-capability-role-check'),
    ]
    rows = []
    for identity, name, old, new, expected in cases:
        original = (source / name).read_text()
        if original.count(old) != 1:
            raise RuntimeError('review changed shell control boundary: ' + identity)
        issues = shell_boundary(source, {name: original.replace(old, new)})
        if not any(issue['code'] == expected for issue in issues):
            raise RuntimeError('shell rejecting control escaped: ' + identity)
        rows.append(dict(id='shell-' + identity, status='PASS', expected=expected))
    return rows


def inventory_issues(actual, expected):
    issues = []
    if not isinstance(expected, dict) or expected.get('version') != 1 or not isinstance(expected.get('entries'), dict):
        return [dict(code='boundary-inventory-invalid')]
    for name in sorted(set(actual) | set(expected['entries'])):
        if actual.get(name) != expected['entries'].get(name):
            issues.append(dict(plugin=name, code='unreviewed-entry-or-loaded-dependency'))
    return issues


def scan_catalog(source, plugins):
    schema_path = source / 'Scripts/python/src/settings/plugin-schema.py'
    spec = importlib.util.spec_from_file_location('boundary_plugin_schema', schema_path)
    schema = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(schema)
    overlays = json.loads((source / 'Configs/plugin-settings-overlays.json').read_text())
    manifests = [(path.parent.name, path) for path in sorted(plugins.glob('*/manifest.json'))]
    manifests += [('builtin/' + path.parent.name, path) for path in sorted((source / 'builtin/plugins').glob('*/manifest.json'))]
    manifests += [('fixture/' + str(path.parent.relative_to(source / 'Scripts/dev/fixtures')), path)
                  for path in sorted((source / 'Scripts/dev/fixtures').rglob('manifest.json'))]
    results, issues, inventory = {}, [], {}
    for name, manifest_path in manifests:
        manifest = json.loads(manifest_path.read_text())
        entry = manifest.get('entryPoints', {}).get('settings')
        if not entry:
            continue
        fields = {}
        try:
            metadata = schema.editor_metadata(manifest, overlays)
            _, fields, _ = schema.described(manifest, overlays)
            if metadata['ready'] is not True:
                issues.append(dict(plugin=name, code=metadata['error']))
            else:
                fields = {key: dict(value, editorUsage=metadata['fields'][key]['usage']) for key, value in fields.items()}
        except ValueError as error:
            issues.append(dict(plugin=name, code='invalid-page-descriptor', detail=str(error)))
        pages = Pages(manifest_path.parent, fields)
        try:
            pages.load(manifest_path.parent / entry.split('?', 1)[0])
            pages.solve()
            results[name] = dict(entry=entry, **pages.report())
            inventory[name] = dict(entry=entry, files=results[name]['files'])
            issues.extend(dict(plugin=name, **issue) for issue in results[name]['issues'])
        except (OSError, RuntimeError) as error:
            issues.append(dict(plugin=name, code='page-graph-unresolved', detail=str(error)))
    synthetic = json.loads((source / 'Scripts/dev/fixtures/plugin-settings-boundary-synthetic.json').read_text())
    if synthetic.get('version') != 1 or set(synthetic) != {'version', 'fields', 'pages'}:
        issues.append(dict(code='synthetic-page-contract-invalid'))
    else:
        for entry, inputs in synthetic['pages'].items():
            name = 'synthetic/' + entry
            pages = Pages(source / 'Scripts/dev/fixtures', synthetic['fields'], inputs)
            pages.load(source / 'Scripts/dev/fixtures' / entry)
            pages.solve()
            results[name] = dict(entry=entry, **pages.report())
            inventory[name] = dict(entry=entry, files=results[name]['files'])
            issues.extend(dict(plugin=name, **issue) for issue in results[name]['issues'])
    if not results:
        issues.append(dict(code='empty-generic-catalog'))
    return results, issues, inventory


def catalog_controls(source, plugins):
    # Real manifest/compiler and manifest-entry graph mutations, not a parallel
    # mock of the production descriptor rules. Copies are task scratch only.
    with tempfile.TemporaryDirectory(prefix='plugin-settings-catalog-control-') as directory:
        root = Path(directory)
        target = root / 'mpvpaper'
        shutil.copytree(plugins / 'mpvpaper', target)
        path = target / 'manifest.json'
        original = json.loads(path.read_text())
        manifest = json.loads(json.dumps(original))
        manifest['version'] = 'unregistered-boundary-control'
        del manifest['metadata']['settingsSchema']['fields']['active']['editorUsage']
        path.write_text(json.dumps(manifest))
        _, issues, _ = scan_catalog(source, root)
        if not any(issue.get('plugin') == 'mpvpaper' and issue['code'] == 'settings-editor-usage-missing' for issue in issues):
            raise RuntimeError('missing authored field-usage control escaped')
        path.write_text(json.dumps(original))
        original['entryPoints']['settings'] = 'Unaudited.qml'
        path.write_text(json.dumps(original))
        (target / 'Unaudited.qml').write_text('import QtQuick\nItem { property var pluginApi; readonly property bool settingsDirty: false }\n')
        _, _, actual = scan_catalog(source, root)
        expected = json.loads((source / 'Scripts/dev/fixtures/plugin-settings-boundary-inventory.json').read_text())
        if not any(issue.get('plugin') == 'mpvpaper' for issue in inventory_issues(actual, expected)):
            raise RuntimeError('new manifest entry source escaped inventory admission')
    return [dict(id='missing-authored-usage', status='PASS', expected='settings-editor-usage-missing'),
            dict(id='new-manifest-entry', status='PASS', expected='unreviewed-entry-or-loaded-dependency')]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--plugins', type=Path, required=True)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--selftest', action='store_true')
    parser.add_argument('--discover-inventory', type=Path, help='write discovery for review, never a passing gate')
    args = parser.parse_args()
    if version('tree-sitter') != '0.25.2' or version('tree-sitter-qmljs') != '0.3.1':
        parser.error('use the existing pinned settings-check requirements')
    controls = selftest() + shell_controls(args.source) if args.selftest else []
    results, issues, inventory = scan_catalog(args.source, args.plugins)
    issues.extend(shell_boundary(args.source))
    inventory_path = args.source / 'Scripts/dev/fixtures/plugin-settings-boundary-inventory.json'
    if args.discover_inventory:
        args.discover_inventory.write_text(json.dumps(dict(version=1, entries=inventory), indent=2) + '\n')
        issues.append(dict(code='inventory-discovery-requires-review'))
    elif not inventory_path.is_file():
        issues.append(dict(code='boundary-inventory-missing'))
    else:
        expected = json.loads(inventory_path.read_text())
        issues.extend(inventory_issues(inventory, expected))
        if args.selftest:
            changed = dict(inventory, **{'unreviewed-generic': dict(entry='New.qml', files=['New.qml'])})
            if not inventory_issues(changed, expected):
                raise RuntimeError('new unaudited entry control escaped')
            controls.append(dict(id='new-entry', status='PASS', expected='unreviewed-entry-or-loaded-dependency'))
            controls.extend(catalog_controls(args.source, args.plugins))
    result = dict(status='FAIL' if issues else 'PASS', catalog=results, issues=issues, controls=controls,
                  scope='parsed page/child/descriptor/selected-owner capability contract, not runtime consumer proof')
    if args.report:
        args.report.write_text(json.dumps(result, indent=2) + '\n')
    for issue in issues:
        print(json.dumps(issue))
    print('PLUGIN_SETTINGS_BOUNDARY: ' + result['status'])
    return 1 if issues else 0


if __name__ == '__main__':
    raise SystemExit(main())
