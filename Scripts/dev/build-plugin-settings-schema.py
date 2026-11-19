#!/usr/bin/env python3
"""Compile an explicitly described plugin settings namespace (I4 preparation).

Never infer public fields from user files or defaults. Old finite versions may
use the host's exact-version overlay; their original files remain user-owned.
"""
import argparse
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('settings_schema', ROOT/'Scripts/dev/build-settings-schema.py')
shared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shared)


def catalog(overlays):
    if (not isinstance(overlays, dict) or set(overlays) - {'version', 'plugins', 'configSchemas', 'sourceProjections', 'incompatible'}
            or type(overlays.get('version')) is not int or overlays['version'] != 1
            or not isinstance(overlays.get('plugins'), dict)):
        raise ValueError('unsupported plugin overlay catalog')
    for name in ('plugins', 'configSchemas', 'sourceProjections', 'incompatible'):
        entries = overlays.get(name, {})
        if not isinstance(entries, dict) or any(not isinstance(k, str) or not k or not isinstance(v, dict) for k, v in entries.items()):
            raise ValueError('plugin overlay entries require exact id/version dictionaries')
        if any(not isinstance(k, str) or not k for versions in entries.values() for k in versions):
            raise ValueError('plugin overlay requires exact nonempty versions')


def metadata_for(manifest, overlays):
    if not isinstance(manifest, dict) or not isinstance(manifest.get('id'), str) or not manifest['id']:
        raise ValueError('plugin manifest requires a nonempty id')
    version = manifest.get('version')
    if not isinstance(version, str) or not version:
        raise ValueError('plugin manifest requires an exact version')
    metadata = manifest.get('metadata', {})
    if not isinstance(metadata, dict):
        raise ValueError('plugin metadata must be an object')
    catalog(overlays)
    return metadata


def selected(manifest, overlays, name, section):
    metadata = metadata_for(manifest, overlays)
    if name in metadata:
        descriptor = metadata[name]
        origin = 'manifest'
    else:
        versions = overlays.get(section, {}).get(manifest['id'], {})
        if manifest['version'] not in versions:
            return None, None
        descriptor = versions[manifest['version']]
        origin = 'compatibility'
    return descriptor, origin


def runtime_compatibility(manifest, overlays):
    """Inert I5 admission gate; descriptor presence cannot port dynamic code."""
    metadata_for(manifest, overlays)
    reason = overlays.get('incompatible', {}).get(manifest['id'], {}).get(manifest['version'])
    if reason is not None and (not isinstance(reason, str) or not reason):
        raise ValueError('plugin incompatibility requires a value-free reason')
    return {'compatible': reason is None, 'reason': reason}


def described(manifest, overlays, namespace='settings', config_defaults=None):
    if namespace not in ('settings', 'config'):
        raise ValueError('unsupported plugin namespace')
    descriptor, origin = selected(manifest, overlays,
        'settingsSchema' if namespace == 'settings' else 'configSchema',
        'plugins' if namespace == 'settings' else 'configSchemas')
    if descriptor is None:
        raise ValueError('plugin '+namespace+' schema missing for exact version')
    if not isinstance(descriptor, dict) or set(descriptor) - {'version', 'definitions', 'fields'} or type(descriptor.get('version')) is not int or descriptor['version'] != 1 or not isinstance(descriptor.get('fields'), dict):
        raise ValueError('unsupported plugin settings descriptor')
    definitions = descriptor.get('definitions', {})
    if not isinstance(definitions, dict):
        raise ValueError('plugin schema definitions must be an object')
    defaults = manifest.get('metadata', {}).get('defaultSettings', {}) if namespace == 'settings' else config_defaults
    if not isinstance(defaults, dict):
        raise ValueError('plugin namespace defaults must be an explicit object')
    fields = {}
    def atomic(node):
        if node['type'] == 'Group':
            raise ValueError('plugin settings are shallow atomic leaves, not groups')
        if 'element' in node:
            atomic(node['element'])
        for child in node.get('fields', {}).values():
            atomic(child)
    for key, declaration in sorted(descriptor['fields'].items()):
        if not isinstance(key, str) or not key or not isinstance(declaration, dict):
            raise ValueError('plugin settings fields require nonempty keys and descriptors')
        node = shared.resolve(declaration, definitions)
        def groups(field):
            if field['type'] == 'Group' and set(field) - {'type', 'fields', 'sensitive', 'machineLocal'}:
                raise ValueError('config groups support namespace metadata, not leaf constraints')
            if 'element' in field:
                groups(field['element'])
            for child in field.get('fields', {}).values():
                groups(child)
        groups(node)
        if namespace == 'settings':
            atomic(node)
        def group_defaults(value, field):
            if field['type'] != 'Group':
                shared.validate(value, field, (namespace, key))
                return
            if not isinstance(value, dict) or set(value) - set(field['fields']):
                raise ValueError('config defaults contain an undeclared group field')
            for child_key, child in field['fields'].items():
                if child_key in value:
                    group_defaults(value[child_key], child)
                elif child['type'] == 'Group':
                    group_defaults({}, child)
                elif not child.get('optional'):
                    raise ValueError('config field without a default must be optional')
        if key in defaults:
            group_defaults(defaults[key], node)
        elif node['type'] == 'Group':
            group_defaults({}, node)
        elif not node.get('optional'):
            raise ValueError('plugin field without a default must be optional')
        fields[key] = node
    if set(defaults) - set(fields):
        raise ValueError('plugin defaults contain an undeclared setting')
    return defaults, fields, origin


def compile_schema(manifest, overlays, namespace='settings', config_defaults=None):
    defaults, fields, origin = described(manifest, overlays, namespace, config_defaults)
    text = ('// Generated from an explicit plugin settings descriptor. Do not edit.\n'
            'import ConfigQml 1.0\n\nConfigSchema {\n  ConfigGroup {\n    key: '+shared.literal(namespace)+'\n')
    def emit(node, key, value, path, depth, present):
        if node['type'] != 'Group':
            return shared.declarations(node, key, value, path, depth, present)
        pad = '  '*depth
        lines = [pad+'ConfigGroup {', pad+'  key: '+shared.literal(key)]
        for flag in ('sensitive', 'machineLocal'):
            if flag in node:
                lines.append(pad+'  '+flag+': '+shared.literal(node[flag]))
        values = value if present else {}
        for name, child in node['fields'].items():
            lines.extend(emit(child, name, values.get(name), path+(name,), depth+1, name in values))
        return lines+[pad+'}']
    for key, node in fields.items():
        text += '\n'+'\n'.join(emit(node, key, defaults.get(key), (namespace, key), 2, key in defaults))+'\n'
    return text+'  }\n}\n', origin


def compile_projection(manifest, overlays, source_ids):
    descriptor, origin = selected(manifest, overlays, 'settingsSourceProjection', 'sourceProjections')
    if origin is None:
        if source_ids:
            raise ValueError('source IDs supplied without a projection descriptor')
        return None, None
    if (not isinstance(descriptor, dict) or set(descriptor) != {'version', 'projectionId', 'transform'}
            or type(descriptor['version']) is not int or descriptor['version'] != 1
            or not isinstance(descriptor['projectionId'], str) or not descriptor['projectionId']
            or not isinstance(descriptor['transform'], str) or not descriptor['transform'].strip()):
        raise ValueError('unsupported plugin Source projection descriptor')
    if (not isinstance(source_ids, list) or not source_ids
            or any(not isinstance(s, str) or not s for s in source_ids) or len(set(source_ids)) != len(source_ids)):
        raise ValueError('projection requires explicit distinct declared source IDs')
    text = '// Generated Source-only projection; construct before the plugin store.\nimport ConfigQml 1.0\n\nConfigProjection {\n'
    for key, value in [('projectionId', descriptor['projectionId']), ('sourceIds', source_ids), ('transform', descriptor['transform'])]:
        text += '  '+key+': '+shared.literal(value)+'\n'
    return text+'}\n', origin


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--overlays', type=Path, default=ROOT/'Configs/plugin-settings-overlays.json')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--namespace', choices=('settings', 'config'), default='settings')
    parser.add_argument('--config-defaults', type=Path, help='authored config.default.json, never user overrides')
    parser.add_argument('--projection-output', type=Path)
    parser.add_argument('--source-id', action='append', default=[])
    parser.add_argument('--require-runtime-compatible', action='store_true')
    args = parser.parse_args()
    try:
        manifest, overlays = shared.load(args.manifest), shared.load(args.overlays)
        if args.require_runtime_compatible and not runtime_compatibility(manifest, overlays)['compatible']:
            raise ValueError('plugin runtime requires its coupled owner port; files retained')
        if (args.namespace == 'config') != (args.config_defaults is not None):
            raise ValueError('config namespace requires its own explicit authored defaults')
        text, origin = compile_schema(manifest, overlays, args.namespace,
            shared.load(args.config_defaults) if args.config_defaults else None)
        if args.projection_output or args.source_id:
            if args.namespace != 'settings' or not args.projection_output:
                raise ValueError('settings projection requires an output and declared source IDs')
            projection, _ = compile_projection(manifest, overlays, args.source_id)
            if projection is None:
                raise ValueError('plugin has no Source projection')
            args.projection_output.write_text(projection)
        args.output.write_text(text)
    except (ValueError, KeyError, TypeError, OSError) as error:
        parser.exit(1, 'plugin settings schema: '+str(error)+'\n')
    print('PLUGIN_SETTINGS_SCHEMA: PASS ('+origin+'; explicit descriptors, no user-file inference)')


if __name__ == '__main__':
    main()
