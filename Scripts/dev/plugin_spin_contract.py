"""Inspect numeric spin editors without confusing JS blocks with QML objects."""

from dataclasses import dataclass

from tree_sitter import Language, Parser
import tree_sitter_qmljs


SPIN_TYPES = {"NSpinBox", "SpinBox"}


def walk(node):
    pending = [node]
    while pending:
        current = pending.pop()
        yield current
        pending.extend(reversed(current.named_children))


def text(node):
    return node.text.decode() if node is not None else ""


@dataclass(frozen=True)
class Spin:
    line: int
    kind: str
    value: str
    submit: tuple[str, ...]
    field_bound: bool
    has_request: bool


def inventory(source):
    tree = Parser(Language(tree_sitter_qmljs.language())).parse(source.encode())
    objects = {}
    by_id = {}
    for obj in walk(tree.root_node):
        if obj.type not in {"ui_object_definition", "ui_object_definition_binding"}:
            continue
        initializer = obj.child_by_field_name("initializer")
        if initializer is None:
            continue
        members = {
            text(member.child_by_field_name("name")): member.child_by_field_name("value")
            for member in initializer.named_children if member.type in {"ui_binding", "ui_property"}
        }
        kind = text(obj.child_by_field_name("type_name")).rsplit(".", 1)[-1]
        objects[obj] = kind, members
        if members.get("id") is not None:
            by_id[text(members["id"])] = obj

    def ancestors(obj):
        while obj is not None:
            if obj in objects:
                yield obj
            obj = obj.parent

    def depends_on_field(expression, owner, seen):
        if expression is None or (expression, owner) in seen:
            return False
        seen.add((expression, owner))
        for node in walk(expression):
            if node.type == "call_expression":
                function = node.child_by_field_name("function")
                if function is not None and text(function.child_by_field_name("property")) == "field":
                    return True
            elif node.type == "member_expression":
                receiver = by_id.get(text(node.child_by_field_name("object")))
                name = text(node.child_by_field_name("property"))
                if receiver is not None and depends_on_field(objects[receiver][1].get(name), receiver, seen):
                    return True
            elif node.type == "identifier":
                for scope in ancestors(owner):
                    members = objects[scope][1]
                    if text(node) in members:
                        if depends_on_field(members[text(node)], scope, seen):
                            return True
                        break
        return False

    for obj, (kind, members) in objects.items():
        if kind not in SPIN_TYPES:
            continue
        field_bound = any(objects[scope][0] == "NPluginSettingsField" and objects[scope][1].get("field") is not None
                          for scope in ancestors(obj.parent))
        field_bound |= depends_on_field(members.get("value"), obj, set())
        submit = tuple(name for name in ("requestValue", "onValueModified", "onValueChanged") if name in members)
        request = members.get("requestValue")
        yield Spin(obj.start_point.row + 1, kind, text(members.get("value")), submit, field_bound,
                   request is not None and text(request) not in {"null", "undefined"})


def lint(source):
    for spin in inventory(source):
        if spin.field_bound and (spin.kind != "NSpinBox" or not spin.has_request or spin.submit != ("requestValue",)):
            yield spin.line, "field-bound spin must use NSpinBox.requestValue, not onValueModified or onValueChanged"
