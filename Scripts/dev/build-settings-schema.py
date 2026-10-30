#!/usr/bin/env python3
"""Build ConfigQml declarations and immutable reference metadata (never live data).

Defaults are authored in Configs/defaults.json; all ambiguous collections and
real-valued fields require reviewed overlay descriptors. --check never writes.
During preparation, the old adapter is independently parsed for parity; remove
that check with the adapter at the single-owner cutover.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TYPES = {'Boolean', 'Integer', 'Real', 'String', 'List', 'Record', 'Map', 'Group'}
FIELDS = {'type', 'element', 'fields', 'optional', 'nullable', 'sensitive',
          'machineLocal', 'choices', 'minimum', 'maximum', 'idField', 'stringPattern'}
ENV = {('general', 'avatarImage'): 'root.homeDirectory + "/.face"',
       ('wallpaper', 'directory'): 'root.homeDirectory + "/Pictures/Wallpapers"',
       ('ui', 'fontDefault'): 'root.defaultFont', ('ui', 'fontFixed'): 'root.fixedFont',
       ('settingsVersion',): 'root.compatibilityVersion'}
# Qt 6.12 QColor::colorNames(), SVG 1.0 + transparent. Qt removes ASCII
# space/tab in names (up to 255 code units); hex spellings are not trimmed.
# Kept as application metadata; configqml Core has no QtGui dependency.
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


def uncomment(text):
    spec = importlib.util.spec_from_file_location('qml_lex', ROOT/'Scripts/dev/qml-identifiers.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    _, spans = module.lex(text)
    chars = list(text)
    for kind, start, end in spans:
        if kind == 'comment':
            chars[start:end] = ['\n' if c == '\n' else ' ' for c in chars[start:end]]
    return ''.join(chars)


def adapter_contract(root):
    """Restricted declarative parser: unknown syntax is an error, never skipped."""
    text = uncomment((root/'Commons/Settings.qml').read_text())
    marker = re.search(r'JsonAdapter\s*\{\s*id:\s*settingsAdapter\b', text)
    if not marker:
        raise ValueError('old adapter not found (remove parity at the owner cutover)')
    start = marker.end()
    enum_source = uncomment((root/'Modules/OSD/OSD.qml').read_text())
    enum = re.search(r'enum Type\s*\{([^}]+)\}', enum_source)[1]
    names = [name.strip() for name in enum.split(',') if name.strip()]
    if not all(re.fullmatch(r'\w+', name) for name in names):
        raise ValueError('unsupported OSD enum expression')
    for index, name in enumerate(names):
        text = re.sub(r'\bOSD\.Type\.'+name+r'\b', str(index), text)
    pos = start
    paths = {}
    decoder = json.JSONDecoder()
    def space():
        nonlocal pos
        while pos < len(text) and (text[pos].isspace() or text[pos] == ';'):
            pos += 1
    def take(pattern):
        nonlocal pos
        space()
        match = re.match(pattern, text[pos:])
        if not match:
            raise ValueError(f'unsupported adapter syntax near {text[pos:pos+60]!r}')
        pos += match.end()
        return match
    def group(path):
        nonlocal pos
        result = {}
        while True:
            space()
            if text[pos] == '}':
                pos += 1
                return result
            match = take(r'property\s+(JsonObject|list\s*<\s*(?:var|string)\s*>|bool|int|string|real|double|color)\s+(\w+)')
            kind, key = re.sub(r'\s', '', match[1]), match[2]
            child = path + (key,)
            if child in paths:
                raise ValueError(f'duplicate adapter path: {child}')
            paths[child] = kind
            space()
            if kind == 'JsonObject':
                if text[pos] != ':':
                    take(re.escape(key))
                take(r':\s*JsonObject\s*\{')
                value = group(child)
            else:
                take(':')
                space()
                value, count = decoder.raw_decode(text[pos:])
                pos += count
            result[key] = value
    return group(()), paths


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
    for flag in ('optional', 'nullable', 'sensitive', 'machineLocal'):
        if flag in descriptor and type(descriptor[flag]) is not bool:
            raise ValueError(f'{flag} must be Boolean')
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


def schema(root):
    defaults = load(root/'Configs/defaults.json')
    overlay = load(root/'Configs/settings-schema-overlay.json')
    if overlay.keys() != {'version', 'definitions', 'entries'} or overlay['version'] != 1:
        raise ValueError('unsupported overlay format')
    overrides = {}
    for entry in overlay['entries']:
        path = entry.get('path')
        if not isinstance(path, list) or not path or not all(isinstance(p,str) and p for p in path):
            raise ValueError('overlay path must be a nonempty segment array')
        path = tuple(path)
        if path in overrides:
            raise ValueError(f'duplicate overlay path: {path}')
        overrides[path] = {k:v for k,v in entry.items() if k != 'path'}
    used = set()
    paths = {}
    def build(value, path):
        extra = overrides.get(path, {})
        if extra:
            used.add(path)
        if isinstance(value, dict):
            inferred = {'type':'Group', 'fields': {k: build(v,path+(k,)) for k,v in sorted(value.items())}}
        elif isinstance(value, list):
            if not extra:
                raise ValueError(f'list requires overlay even when nonempty: {path}')
            inferred = {}
        elif type(value) is bool:
            inferred = {'type':'Boolean'}
        elif type(value) is str:
            inferred = {'type':'String'}
        elif type(value) is int:
            inferred = {'type':'Integer', 'minimum':-2147483648, 'maximum':2147483647}
        elif type(value) is float:
            inferred = {}  # Real must be explicit, including integral-looking defaults.
        else:
            raise ValueError(f'ambiguous default: {path}')
        if extra.get('type') == 'Real':
            inferred = {'type':'Real'}
        node = resolve({**inferred, **extra}, overlay['definitions'])
        validate(value,node,path)
        paths[path] = node
        return node
    tree = build(defaults, ())
    if set(overrides) != used:
        raise ValueError(f'overlay refers to nonexistent paths: {sorted(set(overrides)-used)}')
    old_defaults, old_types = adapter_contract(root)
    if old_defaults != defaults:
        def flatten(v,p=()):
            if isinstance(v,dict):
                return {k:x for name,item in v.items() for k,x in flatten(item,p+(name,)).items()}
            return {p:v}
        old, new = flatten(old_defaults), flatten(defaults)
        differences = [p for p in old.keys()|new.keys() if old.get(p) != new.get(p)]
        raise ValueError(f'old-adapter/defaults parity mismatch: {sorted(differences)}')
    if set(old_types) != set(paths)-{()}:
        raise ValueError('adapter/schema topology mismatch')
    expected = {'JsonObject':'Group', 'bool':'Boolean', 'string':'String', 'color':'String',
                'int':'Integer', 'real':'Real', 'double':'Real', 'list<string>':'List', 'list<var>':'List'}
    for path, old in old_types.items():
        if paths[path]['type'] != expected[old]:
            raise ValueError(f'old-adapter/schema type mismatch: {path}: {old}')
        if old == 'list<string>' and paths[path]['element']['type'] != 'String':
            raise ValueError(f'string list element mismatch: {path}')
        if old == 'color' and paths[path].get('stringPattern') != COLOR_PATTERN:
            raise ValueError(f'color requires QColor overlay: {path}')
    return defaults, tree, paths


def literal(value):
    return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(', ', ': '))


def declarations(node, key=None, default=None, path=(), depth=1, has_default=True):
    pad = '  '*depth
    lines = [pad+('ConfigGroup {' if node['type']=='Group' else 'ConfigValue {')]
    if key is not None:
        lines.append(pad+'  key: '+literal(key))
    if node['type'] != 'Group':
        lines.append(pad+'  valueType: ConfigValue.'+node['type'])
        if has_default:
            value = ENV.get(path, literal(default))
            # Parenthesize object literals for QML bindings.
            if isinstance(default,dict):
                value = '('+value+')'
            lines.append(pad+'  defaultValue: '+value)
    for flag in ('optional','nullable','sensitive','machineLocal','choices','minimum','maximum','idField','stringPattern'):
        if flag in node:
            lines.append(pad+'  '+flag+': '+literal(node[flag]))
    if node['type'] in ('List','Map'):
        lines.extend(declarations(node['element'],depth=depth+1,has_default=False))
    for name,child in node.get('fields',{}).items():
        lines.extend(declarations(child,name,default.get(name) if isinstance(default,dict) else None,
                                  path+(name,),depth+1,has_default=node['type']=='Group'))
    return lines+[pad+'}']


def outputs(root):
    defaults, tree, paths = schema(root)
    banner = '// Generated by Scripts/dev/build-settings-schema.py. Do not edit.\n'
    qml = banner+'import ConfigQml 1.0\n\nConfigSchema {\n  id: root\n'
    qml += '  property string homeDirectory: ""\n  property string defaultFont: ""\n  property string fixedFont: ""\n  property int compatibilityVersion: 62\n'
    for name,node in tree['fields'].items():
        qml += '\n'+'\n'.join(declarations(node,name,defaults[name],(name,)))+'\n'
    qml += '}\n'
    sections = sorted(k for k in defaults if k != 'settingsVersion')
    sources = banner+'import QtQml\nimport ConfigQml 1.0\n\nQtObject {\n  id: root\n  required property string settingsFile\n  required property string overridesDirectory\n  property list<JsonFileSource> sources: [\n'
    records = [('legacy','legacy',[], 'root.settingsFile', False)]+[
        ('user',section,[section],'root.overridesDirectory + '+literal('/'+section+'.json'),True) for section in sections]
    for i,(layer,source,prefix,file,writable) in enumerate(records):
        sources += '    JsonFileSource {\n'
        for key,value in [('layerId',literal(layer)),('sourceId',literal(source)),('prefix',literal(prefix)),
                          ('path',file),('writable',literal(writable)),('optional','true'),
                          ('watchMode','JsonFileSource.Live'),('conflictPolicy','JsonFileSource.StrictSourcePreimage'),
                          ('startupErrorPolicy','JsonFileSource.SkipProjectionRetainError')]+([('deleteWhenEmpty','true')] if writable else []):
            sources += f'      {key}: {value}\n'
        sources += '    }'+(',' if i<len(records)-1 else '')+'\n'
    sources += '  ]\n}\n'
    metadata = {'format':1, 'sections':sections, 'paths':[
        {'path':list(path), **({'type':'Group'} if node['type']=='Group' else node)} for path,node in sorted(paths.items()) if path],
        'inputs':{name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in
                  ('Configs/defaults.json','Configs/settings-schema-overlay.json')}}
    js = '.pragma library\n\n'+banner+'function freeze(value) {\n  if (value && typeof value === "object") {\n    Object.keys(value).forEach(function(key) { freeze(value[key]); });\n    Object.freeze(value);\n  }\n  return value;\n}\n\n'
    js += 'var defaults = freeze('+literal(defaults)+');\n'
    js += 'function defaultValue(path) {\n  var value = defaults;\n  for (var i = 0; i < path.length; ++i) {\n    if (!value || !Object.prototype.hasOwnProperty.call(value, path[i]))\n      return undefined;\n    value = value[path[i]];\n  }\n  return value;\n}\n'
    # Keep generated declarations byte-identical to the normal project formatter.
    formatter = shutil.which('qmlformat') or next((str(p) for p in
        [Path('/usr/lib/qt6/bin/qmlformat'),Path('/usr/lib64/qt6/bin/qmlformat')] if p.is_file()), None)
    if not formatter:
        raise ValueError('Qt 6.12 qmlformat required for reproducible declarations')
    def formatted(text):
        with tempfile.TemporaryDirectory(prefix='settings-schema-') as directory:
            path = Path(directory)/'Generated.qml'
            path.write_text(text)
            result = subprocess.run([formatter,'-w','2','-W','360','-S','--semicolon-rule','always',str(path)],
                                    capture_output=True,text=True,timeout=20)
            if result.returncode:
                raise ValueError('generated QML formatting failed: '+result.stderr)
            return result.stdout
    return {'Commons/SettingsSchema.qml':formatted(qml), 'Commons/SettingsSources.qml':formatted(sources),
            'Configs/settings-schema.json':json.dumps(metadata,indent=2,sort_keys=True)+'\n',
            'Helpers/SettingsDefaults.js':js}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    parser.add_argument('--root',type=Path,default=ROOT)
    args = parser.parse_args()
    try:
        generated = outputs(args.root)
        for name,text in generated.items():
            path = args.root/name
            if args.check:
                if not path.exists() or path.read_bytes() != text.encode():
                    raise ValueError(f'stale generated schema: {name}; run {Path(__file__).name}')
            else:
                path.write_text(text)
    except (ValueError,KeyError,IndexError,OSError,TypeError) as error:
        parser.exit(1,f'settings schema: {error}\n')
    print('SETTINGS_SCHEMA: PASS (defaults/overlay/adapter parity; four resources current)')


if __name__ == '__main__':
    main()
