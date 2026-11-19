"""ConfigQml declaration metadata. Never reads or infers schema from user files."""
import copy
import json
import math

TYPES = {'Boolean', 'Integer', 'Real', 'String', 'List', 'Record', 'Map', 'Group'}
FIELDS = {'type', 'element', 'fields', 'optional', 'nullable', 'sensitive',
          'machineLocal', 'choices', 'minimum', 'maximum', 'idField', 'stringPattern', 'open'}
COLOR_NAMES = '''aliceblue antiquewhite aqua aquamarine azure beige bisque black
blanchedalmond blue blueviolet brown burlywood cadetblue chartreuse chocolate
coral cornflowerblue cornsilk crimson cyan darkblue darkcyan darkgoldenrod
darkgray darkgreen darkgrey darkkhaki darkmagenta darkolivegreen darkorange
darkorchid darkred darksalmon darkseagreen darkslateblue darkslategray
darkslategrey darkturquoise darkviolet deeppink deepskyblue dimgray dimgrey
dodgerblue firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite gold
goldenrod gray green greenyellow grey honeydew hotpink indianred indigo ivory
khaki lavender lavenderblush lawngreen lemonchiffon lightblue lightcoral lightcyan
lightgoldenrodyellow lightgray lightgreen lightgrey lightpink lightsalmon
lightseagreen lightskyblue lightslategray lightslategrey lightsteelblue lightyellow
lime limegreen linen magenta maroon mediumaquamarine mediumblue mediumorchid
mediumpurple mediumseagreen mediumslateblue mediumspringgreen mediumturquoise
mediumvioletred midnightblue mintcream mistyrose moccasin navajowhite navy oldlace
olive olivedrab orange orangered orchid palegoldenrod palegreen paleturquoise
palevioletred papayawhip peachpuff peru pink plum powderblue purple red rosybrown
royalblue saddlebrown salmon sandybrown seagreen seashell sienna silver skyblue
slateblue slategray slategrey snow springgreen steelblue tan teal thistle tomato
transparent turquoise violet wheat white whitesmoke yellow yellowgreen'''.split()
COLOR_PATTERN = (r'(?:#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3}(?:[0-9a-fA-F]{2}|[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?)?)?'
                 + r'|(?=[\s\S]{1,255}\z)[ \t]*(?:'
                 + '|'.join(r'[ \t]*'.join('['+c+c.upper()+']' for c in name) for name in COLOR_NAMES)
                 + r')[ \t]*)')


def load(path):
    def pairs(items):
        out = {}
        for key, value in items:
            if key in out:
                raise ValueError(f'duplicate JSON key: {key}')
            out[key] = value
        return out
    return json.loads(path.read_text(), object_pairs_hook=pairs,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))


def resolve(descriptor, definitions, seen=()):
    descriptor = copy.deepcopy(descriptor)
    if 'ref' in descriptor:
        name = descriptor.pop('ref')
        if name in seen or name not in definitions:
            raise ValueError(f'unknown/cyclic descriptor reference: {name}')
        descriptor = {**resolve(definitions[name], definitions, seen+(name,)), **descriptor}
    if 'format' in descriptor:
        if descriptor.pop('format') != 'QColor' or descriptor.get('type') != 'String':
            raise ValueError('unsupported domain format')
        descriptor['stringPattern'] = COLOR_PATTERN
    unknown = set(descriptor) - FIELDS
    if unknown or descriptor.get('type') not in TYPES:
        raise ValueError(f'invalid descriptor: {unknown or descriptor.get("type")}')
    kind = descriptor['type']
    if kind in ('List', 'Map'):
        if 'element' not in descriptor:
            raise ValueError('collection requires explicit element')
        descriptor['element'] = resolve(descriptor['element'], definitions, seen)
    elif 'element' in descriptor:
        raise ValueError('element on non-collection')
    if kind in ('Group', 'Record'):
        descriptor['fields'] = {k: resolve(v, definitions, seen) for k, v in sorted(descriptor.get('fields', {}).items())}
    elif 'fields' in descriptor:
        raise ValueError('fields on non-record')
    if descriptor.get('idField'):
        raise ValueError('initial schema lists deliberately have no unique row identity')
    for flag in ('optional', 'nullable', 'sensitive', 'machineLocal', 'open'):
        if flag in descriptor and type(descriptor[flag]) is not bool:
            raise ValueError(f'{flag} must be Boolean')
    if 'open' in descriptor and kind != 'Record':
        raise ValueError('open is valid only on Record descriptors')
    return descriptor


def validate(value, node, path):
    kind = node['type']
    if value is None and node.get('nullable'):
        return
    valid = {'Boolean': type(value) is bool, 'String': type(value) is str,
             'Integer': type(value) is int and -2147483648 <= value <= 2147483647,
             'Real': type(value) in (int, float) and math.isfinite(value),
             'List': type(value) is list, 'Map': type(value) is dict,
             'Record': type(value) is dict, 'Group': type(value) is dict}[kind]
    if not valid:
        raise ValueError(f'default type mismatch at {path}: {kind}')
    if 'choices' in node and value not in node['choices']:
        raise ValueError(f'default outside choices: {path}')
    for name, comparison in [('minimum', lambda a,b: a < b), ('maximum', lambda a,b: a > b)]:
        if name in node and comparison(value, node[name]):
            raise ValueError(f'default outside range: {path}')
    if kind == 'List':
        for i, item in enumerate(value):
            validate(item, node['element'], path+(str(i),))
    if kind == 'Map':
        for key, item in value.items():
            validate(item, node['element'], path+(key,))
    if kind in ('Record', 'Group'):
        for key, field in node['fields'].items():
            if key in value:
                validate(value[key], field, path+(key,))
            elif not field.get('optional'):
                raise ValueError(f'missing required default field: {path+(key,)}')


def literal(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(', ', ': '))


def declarations(node, key=None, default=None, path=(), depth=1, has_default=True, expressions=None):
    pad = '  '*depth
    lines = [pad+('ConfigGroup {' if node['type']=='Group' else 'ConfigValue {')]
    if key is not None:
        lines.append(pad+'  key: '+literal(key))
    if node['type'] != 'Group':
        lines.append(pad+'  valueType: ConfigValue.'+node['type'])
        if has_default:
            value = (expressions or {}).get(path, literal(default))
            if isinstance(default, dict):
                value = '('+value+')'
            lines.append(pad+'  defaultValue: '+value)
    for flag in ('optional','nullable','sensitive','machineLocal','choices','minimum','maximum','idField','stringPattern','open'):
        if flag in node:
            lines.append(pad+'  '+flag+': '+literal(node[flag]))
    if node['type'] in ('List','Map'):
        lines.extend(declarations(node['element'],depth=depth+1,has_default=False,expressions=expressions))
    for name, child in node.get('fields', {}).items():
        lines.extend(declarations(child,name,default.get(name) if isinstance(default,dict) else None,
                                  path+(name,),depth+1,has_default=node['type']=='Group',expressions=expressions))
    return lines+[pad+'}']
