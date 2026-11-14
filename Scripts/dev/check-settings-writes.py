#!/usr/bin/env python3
"""Conservative, path-sensitive QML/JS detached-settings ownership analysis.

Expressions and statements share proof states. Only the declaration selected by
lexical/QML lookup and its actual receiver can supply a publishing summary.
Unmodeled effects retain obligations and emit owner-review advisories.
"""
import argparse
from dataclasses import dataclass, field
from functools import lru_cache
from importlib.metadata import version
import json
from pathlib import Path
import re
import sys
import warnings

warnings.filterwarnings('ignore', message='int argument support is deprecated', category=DeprecationWarning)
try:
    from tree_sitter import Language, Parser
    import tree_sitter_qmljs
except ImportError:
    raise SystemExit('settings writes: install .devcontainer/settings-check-requirements.txt in the check environment')
if version('tree-sitter') != '0.25.2' or version('tree-sitter-qmljs') != '0.3.1':
    raise SystemExit('settings writes: parser versions differ from the reviewed check requirements')

ROOT = Path(__file__).resolve().parents[2]
MUTATORS = {'push', 'pop', 'shift', 'unshift', 'splice', 'sort', 'reverse', 'fill', 'copyWithin'}
COPIERS = {'slice', 'concat', 'filter', 'map', 'toSorted', 'toReversed', 'toSpliced', 'with'}
CALLBACKS = {'forEach', 'map', 'filter', 'some', 'every', 'find'}
FUNCTIONS = {'function_declaration', 'function_expression', 'arrow_function', 'generator_function_declaration'}
DATA = {'attached', 'detached', 'owned', 'unknown', 'undeclared', 'handle', 'outside-store'}


def walk(node):
    yield node
    for nested in node.named_children:
        yield from walk(nested)


def child(node, name):
    return node.child_by_field_name(name) if node else None


class OwnerKey(str):
    """A captured local key identity, never equal to a literal schema segment."""
    def __eq__(self, other):
        return isinstance(other, OwnerKey) and str.__eq__(self, other)

    def __ne__(self, other):
        return not self == other

    def __hash__(self):
        return hash((OwnerKey, str(self)))


class SchemaKey(str):
    """An owner namespace, distinct from every literal settings segment."""
    def __eq__(self, other):
        return isinstance(other, SchemaKey) and str.__eq__(self, other)

    def __ne__(self, other):
        return not self == other

    def __hash__(self):
        return hash((SchemaKey, str(self)))


@dataclass(frozen=True)
class Ref:
    path: tuple
    mode: str
    token: int = 0
    lineage: tuple = ()


@dataclass
class State:
    env: dict = field(default_factory=dict)
    dirty: dict = field(default_factory=dict)
    control: str = ''
    escaped: set = field(default_factory=set)
    scopes: list = field(default_factory=list)
    locals: set = field(default_factory=set)
    contained: dict = field(default_factory=dict)
    scalars: dict = field(default_factory=dict)
    owner: int = 0
    this_owner: int = 0

    def fork(self):
        return State(env=self.env.copy(), dirty=self.dirty.copy(), control=self.control,
                     escaped=self.escaped.copy(), scopes=self.scopes.copy(), locals=self.locals.copy(),
                     contained={token: {path: values.copy() for path, values in slots.items()}
                                for token, slots in self.contained.items()},
                     scalars=self.scalars.copy(), owner=self.owner, this_owner=self.this_owner)


@dataclass
class Evaluation:
    state: State
    value: object = None
    truth: object = None
    nullish: object = None
    members: frozenset = frozenset()


@dataclass
class Scope:
    node: object
    parent: int
    component: int
    identity: str
    kind: str
    properties: dict
    methods: dict = field(default_factory=dict)


@dataclass
class Definition:
    node: object
    owner: int
    lexical: int
    bound: bool = False


class Checker:
    def __init__(self, metadata):
        self.main_kinds = {tuple(p['path']): p['type'] for p in metadata['paths']}
        self.kinds = self.main_kinds.copy()
        self.issues = []
        self.serial = 0
        self.counts = {'attached': 0, 'detached': 0, 'assignedBack': 0}
        self.effects = []

    def text(self, node):
        return self.source[node.start_byte:node.end_byte].decode() if node else ''

    def report(self, node, code, level='error'):
        self.issues.append({'file': self.file, 'line': max(1, node.start_point.row + 1 - self.offset),
                            'code': code, 'level': level})

    def unwrap(self, node):
        while node and node.type in ('expression_statement', 'parenthesized_expression', 'required_parameter'):
            node = child(node, 'pattern') or (node.named_children[0] if node.named_children else None)
        return node

    def literal(self, node):
        node = self.unwrap(node)
        if node and node.type == 'string':
            try:
                return json.loads(self.text(node)) if self.text(node).startswith('"') else self.text(node)[1:-1]
            except ValueError:
                return None
        return self.text(node) if node and node.type == 'number' else None

    @lru_cache(maxsize=None)
    def kind(self, path):
        path = tuple('*' if isinstance(key, OwnerKey) else key for key in path)
        for size in range(len(path), 0, -1):
            candidates = {self.kinds[path[:size]]} if path[:size] in self.kinds else set()
            if '*' in path[:size]:
                candidates = {kind for key, kind in self.kinds.items() if len(key) == size
                              and all(a == b or a == '*' for a, b in zip(path[:size], key))}
            if len(candidates) == 1:
                kind = next(iter(candidates))
                return kind if size == len(path) else ('Record' if kind in ('List', 'Map', 'Record') else None)
        return 'Group' if not path else None

    def compound(self, path):
        return self.kind(path) in ('List', 'Map', 'Record')

    def binding(self, scope, name):
        for member in child(scope.node, 'initializer').named_children:
            if member.type in ('ui_binding', 'ui_property') and self.text(child(member, 'name')) == name:
                return self.unwrap(child(member, 'value'))
        return None

    def schema_paths(self, node, active=()):
        """Resolve declared local shapes, never infer a schema from a store ID."""
        if not node or node.id in active:
            return None
        if node.type == 'identifier':
            scope = self.schema_context
            identity = self.ids.get((scope.component, self.text(node)))
            return self.schema_paths(self.scopes[identity].node, active + (node.id,)) if identity else None
        if node.type != 'ui_object_definition':
            return None
        scope = self.scopes[node.id]
        kind = scope.kind.split('.')[-1]
        if kind == 'SettingsSchema':
            return self.main_kinds.copy()
        if kind not in ('ConfigSchema', 'ConfigGroup'):
            return None
        paths = {(): 'Group'}
        for descriptor in child(node, 'initializer').named_children:
            if descriptor.type == 'ui_binding' and self.text(child(descriptor, 'name')) == 'children':
                return None  # A computed declaration list is not a known empty schema.
            if descriptor.type != 'ui_object_definition':
                continue
            declaration = self.scopes[descriptor.id]
            key = self.literal(self.binding(declaration, 'key'))
            if not isinstance(key, str) or not key:
                return None
            type_name = declaration.kind.split('.')[-1]
            if type_name == 'ConfigGroup':
                nested = self.schema_paths(descriptor, active + (node.id,))
                if nested is None:
                    return None
                paths.update({(key,) + path: value for path, value in nested.items()})
            elif type_name == 'ConfigValue':
                value = self.text(self.binding(declaration, 'valueType')).split('.')[-1] or 'String'
                if value not in ('Boolean', 'Integer', 'Int64', 'UInt64', 'Real', 'String', 'Url', 'List', 'StringList', 'Map', 'Record', 'SecretRef'):
                    return None
                paths[(key,)] = 'List' if value == 'StringList' else value
            else:
                return None
        return paths

    def store_schema_roots(self):
        self.store_roots = {}
        self.unknown_schemas = set()
        for owner, scope in self.scopes.items():
            kind = scope.kind.split('.')[-1]
            if kind not in ('ConfigStore', 'SettingsStore'):
                continue
            root = (SchemaKey(self.file + ':' + str(owner)),)
            self.schema_context = scope
            paths = self.main_kinds.copy() if kind == 'SettingsStore' else self.schema_paths(self.binding(scope, 'schema'))
            self.store_roots[owner] = root
            if paths is None:
                self.unknown_schemas.add(root[0])
            else:
                self.kinds[root] = 'Group'
                self.kinds.update({root + path: value for path, value in paths.items()})

    def store_value(self, path):
        return Ref(path, 'outside-store' if path and path[0] in self.unknown_schemas else 'attached')

    def new(self, ref, mode='detached'):
        if not ref or ref.mode not in DATA:
            return ref
        if ref.mode == 'outside-store':
            return Ref(ref.path, 'outside-store')
        if ref.mode == 'unknown':
            return Ref(ref.path, 'unknown')
        if not self.compound(ref.path):
            return ref if self.kind(ref.path) == 'Group' else None
        self.serial += 1
        return Ref(ref.path, mode, self.serial, ref.lineage + ((ref.token,) if ref.token else ()))

    def copy_value(self, node, ref, mode='detached'):
        if not self.binding_pass:
            return self.new(ref, mode)
        key = (node.id, ref, mode)
        if key not in self.binding_copies:
            self.binding_copies[key] = self.new(ref, mode)
        return self.binding_copies[key]

    def tokens(self, ref):
        return ({ref.token, *ref.lineage} - {0}) if ref and ref.mode in DATA else set()

    def evaluation(self, state, value=None, truth=None, nullish=None, members=()):
        if value and value.mode in ('object', 'callable', 'settings'):
            truth, nullish = True, False
        elif value and value.mode == 'owned':
            truth, nullish = True, False  # Normal copy construction returned an object.
        return Evaluation(state, value, truth, nullish, frozenset(members) | self.tokens(value))

    def parameters(self, node):
        params = child(node, 'parameters') or child(node, 'parameter')
        if not params: return []
        if params.type == 'identifier': return [self.text(params)]
        result = []
        for index, parameter in enumerate(params.named_children):
            if parameter.type == 'comment': continue
            pattern = child(parameter, 'pattern') or parameter
            result.append(self.text(pattern) if pattern.type == 'identifier' else '@argument' + str(index))
        return result

    def property_key(self, owner, name):
        return '@' + str(owner) + '.' + name

    def identifier(self, name, state):
        if name in state.env:
            return state.env[name]  # Includes unknown/shadowing declarations.
        if name == 'Settings':
            return Ref((), 'settings')
        owner = state.owner
        while owner:
            scope = self.scopes[owner]
            if name in scope.methods:
                return Ref((), 'callable', scope.methods[name])
            if name in scope.properties:
                return self.environments.get(owner, {}).get(name)
            if scope.parent and self.scopes[scope.parent].component != scope.component:
                break  # Cross-component context injection is not a proven receiver.
            owner = scope.parent
        scope = self.scopes.get(state.owner)
        identity = self.ids.get((scope.component, name)) if scope else None
        return Ref((), 'object', identity) if identity else None

    def member(self, base, key, state, node):
        if not base:
            return None
        if base.mode == 'settings':
            return Ref((), 'attached') if key == 'data' else Ref((), 'store') if key == 'store' else None
        if base.mode == 'store':
            return Ref((), 'attached') if key == 'values' else None
        if base.mode == 'object':
            if key is None:
                return None  # A computed receiver member is not a resolved declaration.
            scope = self.scopes[base.token]
            if base.token in self.store_roots and key == 'values':
                return self.store_value(self.store_roots[base.token])
            if key in scope.methods:
                return Ref((), 'callable', scope.methods[key])
            return state.env.get(self.property_key(base.token, key),
                                 self.environments.get(base.token, {}).get(key))
        if base.mode == 'handle' and key == 'values':
            return self.store_value(base.path)
        if base.mode == 'outside-store':
            return Ref(base.path + (key if key is not None else '*',), 'outside-store')
        if base.mode not in DATA or key == 'length' or key in MUTATORS | COPIERS | CALLBACKS:
            return None
        path = base.path + (key if isinstance(key, str) else str(key) if key is not None else '*',)
        if key is None and self.kind(base.path) == 'Group' and self.kind(path) is None:
            return Ref(path, 'unknown', base.token, base.lineage)
        if (base.mode == 'attached' and self.kind(base.path) == 'Group' and key is not None
                and path not in self.kinds and
                (not any(k == '*' or isinstance(k, OwnerKey) for k in path) or self.kind(path) is None)):
            self.report(node, 'unknown-setting-read', 'advisory')
            return Ref(path, 'undeclared')
        return Ref(path, base.mode, base.token, base.lineage)

    def array_path(self, node):
        if node and node.type == 'array':
            values = [self.literal(n) for n in node.named_children]
            if all(isinstance(value, str) for value in values):
                return tuple(values)
        return None

    def owner_key(self, node, state):
        literal = self.literal(node)
        if literal is not None:
            return literal
        node = self.unwrap(node)
        if node and node.type == 'identifier':
            ref = self.identifier(self.text(node), state)
            if ref and ref.mode == 'key':
                return ref.path[0]
        return None

    def parameter_key(self, node, name):
        return Ref((OwnerKey(str(node.id) + ':' + name),), 'key')

    def ref(self, node, state):
        """Side-effect-free provenance for declarations/summaries, never publication."""
        node = self.unwrap(node)
        if not node:
            return None
        if node.type == 'identifier':
            return self.identifier(self.text(node), state)
        if node.type == 'this':
            return Ref((), 'object', state.this_owner) if state.this_owner else None
        if node.type in ('function_expression', 'arrow_function'):
            return Ref((), 'callable', node.id)
        if node.type in ('member_expression', 'subscript_expression'):
            key = self.text(child(node, 'property')) if node.type == 'member_expression' else self.owner_key(child(node, 'index'), state)
            return self.member(self.ref(child(node, 'object'), state), key, state, node)
        if node.type in ('ternary_expression', 'binary_expression'):
            if node.type == 'binary_expression' and self.text(child(node, 'operator')) not in ('||', '??'):
                return None
            nodes = ([child(node, 'consequence'), child(node, 'alternative')] if node.type == 'ternary_expression'
                     else [child(node, 'left'), child(node, 'right')])
            refs = [self.ref(n, state) for n in nodes]
            present = [ref for ref in refs if ref and ref.mode in DATA]
            if present:
                if any(ref.path != present[0].path or ref.mode != present[0].mode for ref in present):
                    return Ref(present[0].path, 'unknown')
                if not all(ref for ref in refs):
                    if any(ref is None and (self.unwrap(n).type not in ('array', 'object') or self.unwrap(n).named_children)
                           for n, ref in zip(nodes, refs)):
                        return Ref(present[0].path, 'unknown')
                return present[0]
        if node.type == 'call_expression':
            fn = child(node, 'function'); args = child(node, 'arguments').named_children
            method = self.method_name(fn)
            receiver = self.ref(child(fn, 'object'), state) if method is not None else None
            values = [self.evaluation(state, self.ref(arg, state)) for arg in args]
            return self.call_value(node, state, self.ref(fn, state), receiver, method, values)
        if node.type in ('array', 'object'):
            refs = [self.ref(n.named_children[0], state) for n in node.named_children if n.type == 'spread_element']
            refs = [ref for ref in refs if ref and ref.mode in DATA]
            return self.new(refs[0], 'owned') if len(refs) == 1 else None
        return None

    def method_name(self, fn):
        if fn and fn.type == 'member_expression':
            return self.text(child(fn, 'property'))
        if fn and fn.type == 'subscript_expression':
            return self.literal(child(fn, 'index'))
        return None

    def builtin(self, fn, state, name):
        root = name.split('.')[0]
        return self.text(fn) == name and root not in state.env and root not in state.locals

    def summary(self, callable_, state, args=()):
        if not callable_ or callable_.mode != 'callable' or callable_.token not in self.definitions:
            return None
        definition = self.definitions[callable_.token]
        if callable_.token in self.summary_stack:
            return None
        self.summary_stack.add(callable_.token)
        try:
            env = state.env.copy() if definition.lexical else self.environments.get(definition.owner, {}).copy()
            context = State(env=env, owner=definition.owner,
                            this_owner=definition.owner if definition.bound else 0)
            params = self.parameters(definition.node)
            if any(name.startswith('@argument') for name in params):
                return None  # Destructured/default binding semantics are not a setter proof.
            for index, name in enumerate(params):
                context.env[name] = args[index].value if index < len(args) else self.parameter_key(definition.node, name)
                context.locals.add(name)
            body = child(definition.node, 'body')
            statements = [n for n in body.named_children if n.type != 'comment'] if body else []
            if not statements:
                return None
            # Only side-effect-free local aliases/copies before a final return
            # qualify. No branch, nested effect or mutation can become a getter.
            for statement in statements[:-1]:
                if statement.type not in ('lexical_declaration', 'variable_declaration'):
                    return None
                for declaration in statement.named_children:
                    name, value = child(declaration, 'name'), child(declaration, 'value')
                    if not name or name.type != 'identifier' or not value or not self.pure_getter(value, context):
                        return None
                    context.env[self.text(name)] = self.ref(value, context)
                    context.locals.add(self.text(name))
            statement = statements[-1]
            expression = self.unwrap(statement)
            if len(statements) == 1 and expression.type == 'assignment_expression':
                destination = self.ref(child(expression, 'left'), context)
                value = child(expression, 'right')
                if destination and destination.mode == 'attached' and value.type == 'identifier' and self.text(value) in params:
                    return ('setter', (params.index(self.text(value)), destination))
            if len(statements) == 1 and expression.type == 'call_expression':
                fn = child(expression, 'function'); arguments = child(expression, 'arguments').named_children
                receiver = self.ref(child(fn, 'object'), context)
                destination = self.screen_destination(receiver, self.method_name(fn), arguments, context)
                value = arguments[2] if len(arguments) == 3 else None
                if destination and value.type == 'identifier' and self.text(value) in params:
                    return ('setter', (params.index(self.text(value)), destination))
            if statement.type == 'return_statement' and statement.named_children:
                value = statement.named_children[0]
                if not self.pure_getter(value, context):
                    return None
                if value.type == 'identifier' and self.text(value) in params:
                    return ('argument', params.index(self.text(value)))
                return ('getter', self.ref(value, context))
            return None
        finally:
            self.summary_stack.remove(callable_.token)

    def pure_getter(self, node, state):
        for nested in walk(node):
            if nested.type in ('assignment_expression', 'augmented_assignment_expression', 'update_expression'):
                return False
            if nested.type == 'unary_expression' and self.text(child(nested, 'operator')) == 'delete':
                return False
            if nested.type == 'call_expression':
                fn = child(nested, 'function'); method = self.method_name(fn)
                receiver = self.ref(child(fn, 'object'), state)
                copy = receiver and receiver.mode in DATA and method in {'slice', 'concat', 'toSorted', 'toReversed', 'toSpliced', 'with'}
                screen = receiver and receiver.mode == 'settings' and method == 'getScreenOverrideEntry'
                if not (copy or screen):
                    return False
                if any(n.type in FUNCTIONS for n in walk(child(nested, 'arguments'))):
                    return False
        return True

    def screen_destination(self, receiver, method, arguments, state, values=None):
        if not (receiver and receiver.mode == 'settings' and method == 'setScreenOverride' and len(arguments) == 3):
            return None
        screen = self.owner_key(arguments[0], state)
        if values is not None and self.literal(arguments[0]) is None:
            captured = values[0].value
            screen = captured.path[0] if captured and captured.mode == 'key' else None
        field = self.literal(arguments[1])
        if screen is None or field is None:
            return None
        return Ref(('bar', 'screenOverrides', screen, field), 'attached')

    def call_value(self, node, state, callable_, receiver, method, args):
        fn = child(node, 'function')
        if receiver and (receiver.mode == 'store' or receiver.mode == 'object' and receiver.token in self.store_roots) and method == 'scope' and args:
            path = self.array_path(child(node, 'arguments').named_children[0])
            root = () if receiver.mode == 'store' else self.store_roots[receiver.token]
            if path is None and root and root[0] in self.unknown_schemas:
                self.report(node, 'store-schema-out-of-scope', 'advisory')
            return Ref(root + path, 'handle') if path is not None else None
        if receiver and receiver.mode in DATA and method in COPIERS:
            return self.copy_value(node, receiver, 'owned')
        if receiver and receiver.mode == 'settings':
            if method in ('getScreenOverrideEntry', 'getScreenOverridesForScreen'):
                arguments = child(node, 'arguments').named_children
                if method == 'getScreenOverrideEntry' and len(arguments) == 1:
                    screen = self.owner_key(arguments[0], state)
                    if screen is not None:
                        return self.copy_value(node, Ref(('bar', 'screenOverrides', screen), 'attached'))
                return self.copy_value(node, Ref(('bar', 'screenOverrides'), 'attached'))
            if method == 'getBarWidgetsForScreen':
                return Ref(('bar', 'widgets'), 'unknown')
        if self.builtin(fn, state, 'Object.assign') and len(args) >= 2:
            refs = [arg.value for arg in args[1:] if arg.value and arg.value.mode in DATA]
            return self.copy_value(node, refs[0], 'owned') if len(refs) == 1 else None
        if self.builtin(fn, state, 'structuredClone') and args:
            return self.copy_value(node, args[0].value, 'owned')
        if self.builtin(fn, state, 'JSON.parse') and args:
            return self.copy_value(node, args[0].value, 'owned')
        if self.builtin(fn, state, 'JSON.stringify') and args:
            return args[0].value  # Provenance only; parse() can reconstruct this copy.
        summary = self.summary(callable_, state, args)
        if summary and summary[0] == 'getter':
            return self.copy_value(node, summary[1])
        if summary and summary[0] == 'argument' and summary[1] < len(args):
            return self.copy_value(node, args[summary[1]].value)
        return None

    def publish(self, destination, value, state):
        if not (destination and value and destination.mode == 'attached' and value.mode in ('attached', 'detached', 'owned')
                and destination.path == value.path and '*' not in destination.path):
            return False
        tokens = self.tokens(value); pending = list(tokens)
        while pending:
            token = pending.pop()
            for children in state.contained.get(token, {}).values():
                for nested in children - tokens:
                    tokens.add(nested); pending.append(nested)
        for token in tokens:
            if token in state.dirty:
                self.counts['assignedBack'] += 1
                del state.dirty[token]
        self.effects.append(('publish', destination, None))
        return True

    def mutate(self, node, ref, state):
        if not ref:
            return
        if ref.mode == 'attached':
            self.counts['attached'] += 1
        elif ref.mode in ('detached', 'owned') and ref.token:
            self.counts['detached'] += 1
            state.dirty[ref.token] = node
            self.effects.append(('mutate', ref, node))
        elif ref.mode == 'unknown':
            self.report(node, 'unknown-copy-flow', 'advisory')
        elif ref.mode == 'undeclared':
            self.report(node, 'unknown-setting-path')
        elif ref.mode == 'outside-store':
            self.report(node, 'store-schema-out-of-scope', 'advisory')

    def review_transfer(self, node, state, tokens, code):
        relevant = set(tokens) & set(state.dirty)
        if relevant:
            state.escaped.update(relevant)
            self.report(node, code, 'advisory')

    def sequence(self, nodes, states):
        rows = [(state, []) for state in states]
        for node in nodes:
            groups = {}; overflow = None
            for state, values in rows:
                for value in self.expression(node, [state]):
                    # Previous argument values need no references to old states.
                    arguments = values + [Evaluation(None, value.value, value.truth, value.nullish, value.members)]
                    key = (self.signature(value.state), tuple((arg.value, arg.members) for arg in arguments))
                    if overflow is not None:
                        overflow = self.join_sequence(overflow, (value.state, arguments))
                    elif key in groups:
                        previous = groups[key]
                        groups[key] = (previous[0], [self.join_value(a, b) for a, b in zip(previous[1], arguments)])
                    else:
                        groups[key] = (value.state, arguments)
                    if len(groups) > 64:
                        self.report(node, 'sequence-flow-limit', 'advisory')
                        for row in groups.values():
                            overflow = row if overflow is None else self.join_sequence(overflow, row)
                        overflow[0].escaped.update(overflow[0].dirty)
                        groups.clear()
            rows = [overflow] if overflow is not None else list(groups.values())
        return rows

    def join_value(self, left, right):
        value = left.value if left.value == right.value else None
        if value is None and left.value != right.value:
            candidates = [ref for ref in (left.value, right.value) if ref and ref.mode in DATA]
            if candidates: value = Ref(candidates[0].path, 'unknown')
        return Evaluation(None, value, left.truth if left.truth == right.truth else None,
                          left.nullish if left.nullish == right.nullish else None,
                          left.members | right.members)

    def join_sequence(self, left, right):
        # Only a complexity-limit join loses ownership alternatives. It must be
        # explicit/advisory and must never choose one branch's publishing method.
        state = left[0].fork(); other = right[0]
        for name in state.env.keys() | other.env.keys():
            if state.env.get(name) != other.env.get(name):
                a, b = state.env.get(name), other.env.get(name)
                state.env[name] = self.join_value(Evaluation(None, a), Evaluation(None, b)).value
        for name in state.scalars.keys() | other.scalars.keys():
            if state.scalars.get(name) != other.scalars.get(name): state.scalars[name] = (None, None)
        state.dirty.update(other.dirty); state.escaped.update(other.escaped); state.escaped.update(state.dirty)
        state.locals.update(other.locals)
        state.contained = {token: {path: children & other.contained[token].get(path, set())
                                  for path, children in slots.items() if path in other.contained[token]}
                           for token, slots in state.contained.items() if token in other.contained}
        if state.this_owner != other.this_owner: state.this_owner = 0
        if state.owner != other.owner: state.owner = 0
        if state.control != other.control: state.control = ''
        frames = []
        for index in range(max(len(state.scopes), len(other.scopes))):
            a, a_locals = state.scopes[index] if index < len(state.scopes) else ({}, set())
            b, b_locals = other.scopes[index] if index < len(other.scopes) else ({}, set())
            saved = {}
            for name in a.keys() | b.keys():
                av = a.get(name, (False, None, False, None)); bv = b.get(name, (False, None, False, None))
                value = self.join_value(Evaluation(None, av[1]), Evaluation(None, bv[1])).value
                saved[name] = (av[0] or bv[0], value, av[2] or bv[2], av[3] if av[3] == bv[3] else (None, None))
            frames.append((saved, a_locals | b_locals))
        state.scopes = frames
        return state, [self.join_value(a, b) for a, b in zip(left[1], right[1])]

    def branch(self, evaluation, nullish=False):
        known = evaluation.nullish if nullish else evaluation.truth
        yes = [] if known is False else [evaluation.state.fork()]
        no = [] if known is True else [evaluation.state.fork()]
        return yes, no

    def expression(self, node, states):
        node = self.unwrap(node)
        if not node:
            return [self.evaluation(state) for state in states]
        rows = []
        for state in states:
            if state.control:
                rows.append(self.evaluation(state)); continue
            rows.extend(self.evaluate(node, state))
        return self.bound_values(rows, node)

    def evaluate(self, node, state):
        kind = node.type
        if kind in ('identifier', 'this'):
            scalar = state.scalars.get(self.text(node), (None, None))
            return [self.evaluation(state, self.ref(node, state), *scalar)]
        if kind in ('true', 'false', 'null', 'undefined', 'number', 'string', 'regex'):
            if kind in ('null', 'undefined'):
                return [self.evaluation(state, truth=False, nullish=True)]
            truth = kind != 'false'
            if kind == 'number':
                try: truth = float(self.text(node)) != 0
                except ValueError: truth = None
            if kind == 'string': truth = bool(self.literal(node))
            return [self.evaluation(state, truth=truth, nullish=False)]
        if kind in FUNCTIONS:
            return [self.evaluation(state, Ref((), 'callable', node.id))]
        if kind == 'ternary_expression':
            rows = []
            for condition in self.expression(child(node, 'condition'), [state]):
                yes, no = self.branch(condition)
                rows += self.expression(child(node, 'consequence'), yes)
                rows += self.expression(child(node, 'alternative'), no)
            return rows
        if kind == 'binary_expression' and self.text(child(node, 'operator')) in ('&&', '||', '??'):
            operator = self.text(child(node, 'operator')); rows = []
            for left in self.expression(child(node, 'left'), [state]):
                yes, no = self.branch(left, nullish=operator == '??')
                execute, skipped = (yes, no) if operator in ('&&', '??') else (no, yes)
                rows += [self.evaluation(s, left.value, left.truth, left.nullish, left.members) for s in skipped]
                rows += self.expression(child(node, 'right'), execute)
            return rows
        if kind in ('member_expression', 'subscript_expression'):
            rows = []
            for base in self.expression(child(node, 'object'), [state]):
                indices = self.expression(child(node, 'index'), [base.state]) if kind == 'subscript_expression' else [self.evaluation(base.state)]
                for index in indices:
                    key = self.text(child(node, 'property')) if kind == 'member_expression' else self.owner_key(child(node, 'index'), index.state)
                    rows.append(self.evaluation(index.state, self.member(base.value, key, index.state, node)))
            return rows
        if kind in ('assignment_expression', 'augmented_assignment_expression'):
            left, right = child(node, 'left'), child(node, 'right'); rows = []
            # Logical assignment is conditional too, not an unconditional setter.
            operator = self.text(child(node, 'operator'))
            if kind == 'augmented_assignment_expression' and operator in ('&&=', '||=', '??='):
                for old in self.expression(left, [state]):
                    yes, no = self.branch(old, nullish=operator == '??=')
                    execute, skipped = (yes, no) if operator != '||=' else (no, yes)
                    rows += [self.evaluation(s, old.value, old.truth, old.nullish, old.members) for s in skipped]
                    for value in self.expression(right, execute):
                        rows.append(self.assign(node, left, value))
                return rows
            for destination in self.expression(left, [state]):
                for value in self.expression(right, [destination.state]):
                    if kind == 'augmented_assignment_expression':
                        self.mutate(node, destination.value, value.state)
                        if left.type == 'identifier':
                            value.state.env[self.text(left)] = None
                        self.review_transfer(node, value.state, value.state.dirty, 'unsupported-assignment-effect')
                        rows.append(self.evaluation(value.state))
                    else:
                        rows.append(self.assign(node, left, value, destination.value))
            return rows
        if kind in ('update_expression', 'unary_expression'):
            rows = []
            for value in self.expression(child(node, 'argument'), [state]):
                operator = self.text(child(node, 'operator'))
                if kind == 'update_expression' or operator == 'delete':
                    self.mutate(node, value.value, value.state)
                    argument = self.unwrap(child(node, 'argument'))
                    if argument.type == 'identifier':
                        value.state.env[self.text(argument)] = None
                rows.append(self.evaluation(value.state,
                    truth=(not value.truth) if operator == '!' and value.truth is not None else None,
                    nullish=False))
            return rows
        if kind == 'call_expression':
            return self.call(node, state)
        if kind in ('array', 'object'):
            rows = []
            for current, values in self.sequence([n for n in node.named_children if n.type != 'comment'], [state]):
                members = set().union(*(value.members for value in values)) if values else set()
                ref = self.ref(node, current)
                if ref and ref.token:
                    current.contained.setdefault(ref.token, {})[ref.path] = members - {ref.token}
                rows.append(self.evaluation(current, ref, True, False, members))
            return rows
        if kind in ('pair', 'spread_element', 'template_substitution'):
            value = child(node, 'value') if kind == 'pair' else (node.named_children[0] if node.named_children else None)
            return self.expression(value, [state])
        if kind in ('sequence_expression', 'binary_expression', 'template_string'):
            rows = []
            for current, values in self.sequence(node.named_children, [state]):
                if kind == 'sequence_expression' and values:
                    last = values[-1]; rows.append(self.evaluation(current, last.value, last.truth, last.nullish, last.members))
                else:
                    rows.append(self.evaluation(current, nullish=False))
            return rows
        if kind in ('property_identifier', 'string_fragment', 'escape_sequence', 'comment', 'empty_statement'):
            return [self.evaluation(state)]
        return [self.evaluation(s, Ref((), 'unknown') if s.dirty else None)
                for s in self.opaque(node, [state], 'unsupported-expression-flow')]

    def assign(self, node, left, value, destination=None):
        state = value.state
        destination = destination or self.ref(left, state)
        published = self.publish(destination, value.value, state)
        if destination and destination.mode == 'attached' and not published:
            self.review_transfer(node, state, value.members, 'copy-assigned-to-different-owner')
        name = self.text(left)
        property_owner = 0
        if left.type == 'identifier' and name not in state.locals:
            owner = state.owner
            while owner:
                if name in self.scopes[owner].properties: property_owner = owner; break
                owner = self.scopes[owner].parent
        elif left.type in ('member_expression', 'subscript_expression'):
            receiver = self.ref(child(left, 'object'), state)
            key = self.method_name(left)
            if receiver and receiver.mode == 'object' and key in self.scopes[receiver.token].properties:
                property_owner, name = receiver.token, key
        if left.type == 'identifier' or property_owner:
            ref = value.value
            literal = self.literal(child(node, 'right'))
            if ref is None and literal is not None and not property_owner:
                ref = Ref((literal,), 'key')
            if property_owner:
                ref = self.new(ref) if ref and ref.mode in DATA and self.compound(ref.path) else ref
                state.env[self.property_key(property_owner, name)] = ref
            if left.type == 'identifier' or property_owner == state.owner:
                state.env[name] = ref; state.scalars[name] = (value.truth, value.nullish)
        else:
            length = left.type == 'member_expression' and self.text(child(left, 'property')) == 'length'
            target = self.ref(child(left, 'object'), state) if length else destination
            self.mutate(node, target, state)
            if destination and destination.mode in DATA and destination.token:
                if '*' in destination.path:
                    old = state.contained.get(destination.token, {}).get(destination.path, set())
                    self.review_transfer(node, state, old, 'computed-container-replacement-owner-review')
                state.contained.setdefault(destination.token, {})[destination.path] = set(value.members) - {destination.token}
        return self.evaluation(state, value.value, value.truth, value.nullish, value.members)

    def property_names(self, owner):
        names = set()
        while owner:
            scope = self.scopes[owner]; names.update(scope.properties)
            names.update(self.property_key(owner, name) for name in scope.properties)
            owner = scope.parent
        return names

    def capture_tokens(self, callable_, state):
        if not callable_ or callable_.mode != 'callable' or callable_.token not in self.definitions:
            return set()
        definition = self.definitions[callable_.token]
        context = State(env=state.env.copy() if definition.lexical else self.environments[definition.owner].copy(),
                        owner=definition.owner, this_owner=definition.owner if definition.bound else 0)
        for name in self.parameters(definition.node): context.env[name] = None
        return set().union(*(self.tokens(self.ref(n, context)) for n in walk(child(definition.node, 'body'))
                             if n.type in ('identifier', 'member_expression', 'subscript_expression')))

    def call(self, node, state):
        fn = child(node, 'function'); method = self.method_name(fn); rows = []
        # Evaluate receiver/computed name before arguments, then the call effect.
        if method is not None or fn.type in ('member_expression', 'subscript_expression'):
            receivers = self.expression(child(fn, 'object'), [state])
        else:
            receivers = [self.evaluation(state)]
        for receiver in receivers:
            callee_states = (self.expression(child(fn, 'index'), [receiver.state]) if fn.type == 'subscript_expression'
                             else [self.evaluation(receiver.state)])
            for callee_state in callee_states:
                callable_ = (self.member(receiver.value, method, callee_state.state, fn)
                             if fn.type in ('member_expression', 'subscript_expression') else self.ref(fn, callee_state.state))
                for current, args in self.sequence(child(node, 'arguments').named_children, [callee_state.state]):
                    base = receiver.value
                    collection = base and base.mode in DATA and (base.mode in ('unknown', 'outside-store') or self.compound(base.path))
                    summary = self.summary(callable_, current, args)
                    published = set()
                    destination = self.screen_destination(base, method, child(node, 'arguments').named_children, current, args)
                    if destination and self.publish(destination, args[2].value, current):
                        published.add(2)
                    if summary and summary[0] == 'setter':
                        index, destination = summary[1]
                        if index < len(args) and self.publish(destination, args[index].value, current):
                            published.add(index)
                    if collection and method in MUTATORS:
                        self.mutate(node, base, current)
                    if collection and method in CALLBACKS:
                        current_rows = self.array_callback(node, current, base)
                    else:
                        current_rows = [current]
                    for result in current_rows:
                        known_value = (collection and method in MUTATORS | COPIERS | CALLBACKS) or bool(summary)
                        known_value |= any(self.builtin(fn, result, name) for name in
                                           ('JSON.parse', 'JSON.stringify', 'Object.assign', 'structuredClone'))
                        for index, argument in enumerate(args):
                            if index not in published and not (known_value and not (summary and summary[0] == 'setter')):
                                self.review_transfer(node, result, argument.members, 'copy-transferred-to-unproven-owner')
                        if not summary:
                            self.review_transfer(node, result, self.capture_tokens(callable_, result), 'captured-copy-owner-review')
                        value = self.call_value(node, result, callable_, base, method, args)
                        if value and value.token:
                            members = set().union(*(arg.members for arg in args)) if args else set()
                            result.contained.setdefault(value.token, {})[value.path] = members - {value.token}
                        rows.append(self.evaluation(result, value,
                            truth=False if summary and summary[0] == 'setter' else None,
                            nullish=True if summary and summary[0] == 'setter' else None))
        return rows

    def array_callback(self, node, state, base):
        results = [state.fork()]  # A value list can be empty.
        for callback in child(node, 'arguments').named_children:
            if callback.type not in FUNCTIONS:
                continue
            nested = state.fork(); before_env = nested.env.copy(); before_scalars = nested.scalars.copy()
            local = self.local_names(child(callback, 'body')) | set(self.parameters(callback))
            for name in local: nested.env[name] = None; nested.locals.add(name)
            params = self.parameters(callback)
            if params: nested.env[params[0]] = Ref(base.path + ('*',), base.mode, base.token, base.lineage)
            nested.this_owner = state.this_owner if callback.type == 'arrow_function' else 0
            for result in self.statement(child(callback, 'body'), [nested]):
                if result.control == 'return': result.control = ''
                for name in local:
                    if name in before_env: result.env[name] = before_env[name]
                    else: result.env.pop(name, None)
                    if name in before_scalars: result.scalars[name] = before_scalars[name]
                    else: result.scalars.pop(name, None)
                result.locals = state.locals.copy(); result.this_owner = state.this_owner
                results.append(result)
        return self.bound(results, node)

    def opaque(self, node, states, code):
        """Inspect uncertain flow without crediting any nested publication."""
        results = []
        for state in states:
            before = state.dirty.copy(); start = len(self.effects)
            rows = [state]
            for nested in node.named_children:
                if nested.type in FUNCTIONS: continue
                rows = self.statement(nested, rows) if nested.type.endswith('_statement') or nested.type in ('statement_block', 'switch_body', 'switch_case', 'switch_default') else [e.state for e in self.expression(nested, rows)]
            mutations = {ref.token: source for kind, ref, source in self.effects[start:] if kind == 'mutate'}
            for result in rows:
                result.dirty = {**before, **result.dirty, **mutations}
                result.escaped.update(result.dirty)
                if result.dirty or self.effects[start:]: self.report(node, code, 'advisory')
                results.append(result)
        return self.bound(results, node)

    def local_names(self, node):
        names = set()
        if not node: return names
        for nested in node.named_children:
            if nested.type in FUNCTIONS: continue
            if nested.type == 'variable_declaration':
                names.update(self.text(child(d, 'name')) for d in nested.named_children if d.type == 'variable_declarator')
            names.update(self.local_names(nested))
        return names

    def block(self, node, states):
        names = set(); functions = {}
        for statement in node.named_children:
            if statement.type == 'lexical_declaration':
                names.update(self.text(child(d, 'name')) for d in statement.named_children if d.type == 'variable_declarator')
            elif statement.type == 'function_declaration':
                name = self.text(child(statement, 'name')); names.add(name); functions[name] = statement.id
        for state in states:
            saved = {name: (name in state.env, state.env.get(name), name in state.scalars, state.scalars.get(name)) for name in names}
            state.scopes.append((saved, state.locals.copy()))
            for name in names:
                state.env[name] = Ref((), 'callable', functions[name]) if name in functions else None
                state.scalars.pop(name, None); state.locals.add(name)
        results = states
        for statement in node.named_children: results = self.statement(statement, results)
        for state in results:
            saved, state.locals = state.scopes.pop()
            for name, (present, value, scalar_present, scalar) in saved.items():
                if present: state.env[name] = value
                else: state.env.pop(name, None)
                if scalar_present: state.scalars[name] = scalar
                else: state.scalars.pop(name, None)
        return results

    def statement(self, node, states):
        if not node: return states
        active = [s for s in states if not s.control]; ended = [s for s in states if s.control]
        if not active: return states
        kind = node.type
        if kind in ('statement_block', 'program', 'else_clause', 'switch_body', 'switch_case', 'switch_default'):
            return ended + self.block(node, active)
        if kind == 'if_statement':
            rows = []
            for value in self.expression(child(node, 'condition'), active):
                yes, no = self.branch(value)
                rows += self.statement(child(node, 'consequence'), yes)
                rows += self.statement(child(node, 'alternative'), no)
            return ended + self.bound(rows, node)
        if kind in ('while_statement', 'for_statement', 'for_in_statement', 'do_statement', 'switch_statement'):
            return ended + self.opaque(node, active, 'loop-flow-not-proven' if kind != 'switch_statement' else 'switch-flow-not-proven')
        if kind == 'try_statement':
            rows = self.statement(child(node, 'body'), active); handler = child(node, 'handler')
            if handler:
                caught = []
                for state in rows:
                    if state.control != 'throw': caught.append(state); continue
                    state.control = ''; name = self.text(child(handler, 'parameter'))
                    present, old = name in state.env, state.env.get(name); old_locals = state.locals.copy()
                    state.env[name] = None; state.locals.add(name)
                    for result in self.statement(child(handler, 'body'), [state]):
                        if present: result.env[name] = old
                        else: result.env.pop(name, None)
                        result.locals = old_locals.copy(); caught.append(result)
                rows = caught
            finalizer = child(node, 'finalizer')
            if finalizer:
                finalized = []
                for state in rows:
                    control = state.control; state.control = ''
                    for result in self.statement(child(finalizer, 'body'), [state]):
                        result.control = result.control or control; finalized.append(result)
                rows = finalized
            return ended + self.bound(rows, node)
        if kind in ('variable_declaration', 'lexical_declaration'):
            rows = active
            for declaration in node.named_children:
                if declaration.type != 'variable_declarator': continue
                name = child(declaration, 'name'); value = child(declaration, 'value')
                if name.type != 'identifier':
                    rows = self.opaque(declaration, rows, 'destructuring-owner-review'); continue
                updated = []
                for result in self.expression(value, rows):
                    key = self.text(name)
                    if value is not None or key not in result.state.env:
                        literal = self.literal(value)
                        result.state.env[key] = result.value or (Ref((literal,), 'key') if literal is not None else None)
                        result.state.scalars[key] = (result.truth, result.nullish)
                    result.state.locals.add(key); updated.append(result.state)
                rows = updated
            return ended + rows
        if kind in ('return_statement', 'throw_statement', 'break_statement', 'continue_statement'):
            rows = []
            for result in self.expression(node.named_children[0] if node.named_children else None, active):
                if kind == 'return_statement': result.state.escaped.update(result.members)
                result.state.control = kind.removesuffix('_statement'); rows.append(result.state)
            return ended + rows
        if kind in FUNCTIONS: return states
        return ended + [value.state for value in self.expression(node, active)]

    def signature(self, state):
        return (tuple(sorted(state.env.items())), tuple(sorted((key, node.id) for key, node in state.dirty.items())),
                state.control, frozenset(state.escaped), frozenset(state.locals), tuple(sorted(state.scalars.items())),
                state.owner, state.this_owner,
                tuple((token, tuple(sorted((path, frozenset(values)) for path, values in slots.items())))
                      for token, slots in sorted(state.contained.items())),
                tuple((tuple(sorted(values.items())), frozenset(locals_)) for values, locals_ in state.scopes))

    def bound(self, states, node):
        states = list({self.signature(state): state for state in states}.values())
        if len(states) <= 64: return states
        self.report(node, 'control-flow-limit', 'advisory'); merged = states[0].fork()
        for state in states[1:]: merged = self.join_sequence((merged, []), (state, []))[0]
        merged.escaped.update(merged.dirty)
        return [merged]

    def bound_values(self, values, node):
        values = list({(self.signature(e.state), e.value, e.truth, e.nullish, e.members): e for e in values}.values())
        if len(values) <= 64: return values
        self.report(node, 'expression-flow-limit', 'advisory')
        states = self.bound([e.state for e in values], node)
        for state in states: state.escaped.update(state.dirty)
        return [self.evaluation(state, Ref((), 'unknown')) for state in states]

    def analyze_function(self, definition):
        node = definition.node; state = State(env=self.environments[definition.owner].copy(), owner=definition.owner,
                                             this_owner=definition.owner if definition.bound else 0)
        parent = self.definitions.get(definition.lexical)
        if self.offset and parent and self.text(child(parent.node, 'name')) == '__script':
            for member in child(parent.node, 'body').named_children:
                if member.type == 'function_declaration':
                    state.env[self.text(child(member, 'name'))] = Ref((), 'callable', member.id)
            for name in self.local_names(child(parent.node, 'body')):
                state.env.setdefault(name, None)
        for name in self.local_names(child(node, 'body')) | set(self.parameters(node)):
            state.env[name] = None; state.locals.add(name)
        for name in self.parameters(node):
            state.env[name] = self.parameter_key(node, name)
        self.finish(self.statement(child(node, 'body'), [state]))

    def finish(self, results):
        for result in results:
            if result.control == 'throw': continue
            for token, mutation in result.dirty.items():
                line = mutation.start_point.row + 1 - self.offset
                previous = self.original.splitlines()[line - 2] if line >= 2 else ''
                suppression = re.fullmatch(r'\s*// settings-write: intentional-copy -- (\S.*)', previous)
                if suppression: self.report(mutation, 'intentional-copy: ' + suppression[1], 'advisory')
                elif token in result.escaped: self.report(mutation, 'copy-transfer-requires-owner-review', 'advisory')
                else: self.report(mutation, 'detached-write-without-assignment-back')

    def check(self, path, text):
        self.file = str(path); self.original = text; self.offset = 0
        self.kinds = self.main_kinds.copy()
        self.kind.cache_clear()
        self.effects = []
        if str(path).endswith('.js'):
            text = re.sub(r'^\s*\.(?:pragma|import)\b[^\n]*', lambda m: ' ' * len(m[0]), text, flags=re.M)
            text = 'import QtQml\nQtObject { function __script() {\n' + text + '\n} }\n'; self.offset = 2
        self.source = text.encode(); tree = Parser(Language(tree_sitter_qmljs.language())).parse(self.source)
        if tree.root_node.has_error:
            before = len(self.issues)
            for node in walk(tree.root_node):
                if node.type == 'ERROR' or node.is_missing: self.report(node, 'parse-error')
            if len(self.issues) == before: self.report(tree.root_node, 'parse-error')
            return
        self.scopes = {}; self.ids = {}; self.definitions = {}; self.environments = {}; self.summary_stack = set()
        self.ql_copies = {}; self.binding_copies = {}; self.binding_pass = True
        for node in walk(tree.root_node):
            if node.type != 'ui_object_definition': continue
            parent = node.parent; boundary = False
            while parent and parent.id not in self.scopes:
                if parent.type == 'ui_inline_component': boundary = True
                if parent.type == 'ui_binding' and self.text(child(parent, 'name')) == 'delegate': boundary = True
                parent = parent.parent
            parent_id = parent.id if parent else 0
            if parent_id and self.scopes[parent_id].kind == 'Component': boundary = True
            component = node.id if not parent_id or boundary else self.scopes[parent_id].component
            initializer = child(node, 'initializer'); identity = ''; properties = {}
            for member in initializer.named_children:
                if member.type == 'ui_property': properties[self.text(child(member, 'name'))] = member
                if member.type == 'ui_binding' and self.text(child(member, 'name')) == 'id':
                    identity = self.text(self.unwrap(child(member, 'value')))
            self.scopes[node.id] = Scope(node, parent_id, component, identity, self.text(child(node, 'type_name')), properties)
            if identity:
                key = (component, identity)
                self.ids[key] = node.id if key not in self.ids else None
        self.store_schema_roots()
        for node in walk(tree.root_node):
            if node.type not in FUNCTIONS: continue
            parent = node.parent; lexical = 0
            while parent and parent.id not in self.scopes:
                if parent.type in FUNCTIONS and not lexical: lexical = parent.id
                parent = parent.parent
            if not parent: continue
            bound = not lexical and not self.offset and (node.type == 'function_declaration' or
                    (node.parent.type == 'ui_binding' and child(node.parent, 'value') == node))
            definition = Definition(node, parent.id, lexical, bound); self.definitions[node.id] = definition
            if not lexical and node.type == 'function_declaration':
                self.scopes[parent.id].methods[self.text(child(node, 'name'))] = node.id
        for _ in range(8):
            changed = False
            for owner, scope in self.scopes.items():
                inherited = self.environments.get(scope.parent, {}).copy()
                if scope.parent and self.scopes[scope.parent].component != scope.component:
                    inherited = {key: value for key, value in inherited.items() if key == 'modelData'}
                env = inherited.copy()
                for name in scope.methods: env.pop(name, None)
                for name in scope.properties: env[name] = None
                context = State(env=env, owner=owner, this_owner=owner)
                for name, prop in scope.properties.items():
                    value = self.ref(child(prop, 'value'), context)
                    if name == 'modelData' and child(prop, 'value') is None: value = inherited.get(name)
                    if value and value.mode in DATA and value.mode != 'handle' and self.compound(value.path):
                        key = (owner, name, value)
                        if key not in self.ql_copies: self.ql_copies[key] = self.new(value)
                        value = self.ql_copies[key]
                    env[name] = value; env[self.property_key(owner, name)] = value
                for member in child(scope.node, 'initializer').named_children:
                    if member.type == 'ui_binding' and self.text(child(member, 'name')) == 'model':
                        ref = self.ref(child(member, 'value'), context)
                        if ref and ref.mode in DATA and self.compound(ref.path):
                            key = (owner, 'modelData', ref)
                            if key not in self.ql_copies: self.ql_copies[key] = self.new(Ref(ref.path + ('*',), 'attached'))
                            env['modelData'] = self.ql_copies[key]
                if self.environments.get(owner) != env: changed = True
                self.environments[owner] = env
            if not changed: break
        self.binding_pass = False
        for definition in self.definitions.values():
            parent = self.definitions.get(definition.lexical)
            if definition.lexical and not (self.offset and parent and self.text(child(parent.node, 'name')) == '__script'):
                continue
            self.analyze_function(definition)
        for node in walk(tree.root_node):
            if node.type != 'ui_binding': continue
            value = self.unwrap(child(node, 'value'))
            if not value or value.type in FUNCTIONS | {'ui_object_definition'}: continue
            if value.type == 'statement_block' or self.text(child(node, 'name')).split('.')[-1].startswith('on'):
                parent = node.parent
                while parent and parent.id not in self.scopes: parent = parent.parent
                if parent:
                    state = State(env=self.environments[parent.id].copy(), owner=parent.id, this_owner=parent.id)
                    self.finish(self.statement(value, [state]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--report', type=Path)
    parser.add_argument('paths', nargs='*', type=Path)
    args = parser.parse_args(); checker = Checker(json.loads((args.root / 'Configs/settings-schema.json').read_text()))
    files = set()
    for path in args.paths or [args.root]:
        path = path if path.is_absolute() else args.root / path
        files.update(p for p in (path.rglob('*') if path.is_dir() else [path]) if p.suffix in ('.qml', '.js')
                     and '.git' not in p.parts and 'node_modules' not in p.parts
                     and not p.is_relative_to(args.root / 'Scripts/dev/fixtures/settings-writes'))
    for file in sorted(files): checker.check(file.relative_to(args.root), file.read_text())
    issues = list({(i['file'], i['line'], i['code'], i['level']): i for i in checker.issues}.values())
    result = {'files': len(files), 'counts': checker.counts, 'issues': issues}
    if args.report: args.report.write_text(json.dumps(result, indent=2) + '\n')
    for issue in issues: print('{file}:{line}: {level}: {code}'.format(**issue))
    errors = sum(i['level'] == 'error' for i in issues)
    print(f'SETTINGS_WRITES: {"FAIL" if errors else "PASS"} ({len(files)} files; {errors} errors; {len(issues)-errors} advisory)')
    return int(bool(errors))


if __name__ == '__main__':
    sys.exit(main())
