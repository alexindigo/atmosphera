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


def described(manifest, overlays):
    if not isinstance(manifest, dict) or not isinstance(manifest.get('id'), str) or not manifest['id']:
        raise ValueError('plugin manifest requires a nonempty id')
    version = manifest.get('version')
    if not isinstance(version, str) or not version:
        raise ValueError('plugin manifest requires an exact version')
    metadata = manifest.get('metadata', {})
    if not isinstance(metadata, dict):
        raise ValueError('plugin metadata must be an object')
    if not isinstance(overlays, dict) or set(overlays) != {'version', 'plugins'} or type(overlays['version']) is not int or overlays['version'] != 1 or not isinstance(overlays['plugins'], dict):
        raise ValueError('unsupported plugin overlay catalog')
    if 'settingsSchema' in metadata:
        descriptor = metadata['settingsSchema']
        origin = 'manifest'
    else:
        versions = overlays['plugins'].get(manifest['id'], {})
        if not isinstance(versions, dict) or version not in versions:
            raise ValueError('plugin settings schema missing for exact version')
        descriptor = versions[version]
        origin = 'compatibility'
    if not isinstance(descriptor, dict) or set(descriptor) - {'version', 'definitions', 'fields'} or type(descriptor.get('version')) is not int or descriptor['version'] != 1 or not isinstance(descriptor.get('fields'), dict):
        raise ValueError('unsupported plugin settings descriptor')
    definitions = descriptor.get('definitions', {})
    if not isinstance(definitions, dict):
        raise ValueError('plugin schema definitions must be an object')
    defaults = metadata.get('defaultSettings', {})
    if not isinstance(defaults, dict):
        raise ValueError('plugin settings defaults must be an object')
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
        atomic(node)
        if key in defaults:
            shared.validate(defaults[key], node, ('settings', key))
        elif not node.get('optional'):
            raise ValueError('plugin field without a default must be optional')
        fields[key] = node
    if set(defaults) - set(fields):
        raise ValueError('plugin defaults contain an undeclared setting')
    return defaults, fields, origin


def compile_schema(manifest, overlays):
    defaults, fields, origin = described(manifest, overlays)
    text = ('// Generated from an explicit plugin settings descriptor. Do not edit.\n'
            'import ConfigQml 1.0\n\nConfigSchema {\n  ConfigGroup {\n    key: "settings"\n')
    for key, node in fields.items():
        text += '\n'+'\n'.join(shared.declarations(node, key, defaults.get(key),
            path=('settings', key), depth=2, has_default=key in defaults))+'\n'
    return text+'  }\n}\n', origin


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--overlays', type=Path, default=ROOT/'Configs/plugin-settings-overlays.json')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        text, origin = compile_schema(shared.load(args.manifest), shared.load(args.overlays))
        args.output.write_text(text)
    except (ValueError, KeyError, TypeError, OSError) as error:
        parser.exit(1, 'plugin settings schema: '+str(error)+'\n')
    print('PLUGIN_SETTINGS_SCHEMA: PASS ('+origin+'; explicit descriptors, no user-file inference)')


if __name__ == '__main__':
    main()
