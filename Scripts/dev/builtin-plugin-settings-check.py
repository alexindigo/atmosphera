#!/usr/bin/env python3
"""Every shipped built-in plugin must resolve its settings store.

The shell compiles each loaded plugin's store from its exact manifest version
(authored metadata or the reviewed exact-version overlay). A built-in version
bump without a matching descriptor fails only at runtime, so check the shipped
tree with the same compiler the shell runs. Reads authored files only.
"""
import argparse
import importlib.util
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]


def failures(root):
    spec = importlib.util.spec_from_file_location('plugin_schema', root/'Scripts/python/src/settings/plugin-schema.py')
    compiler = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(compiler)
    overlays = compiler.shared.load(root/'Configs/plugin-settings-overlays.json')
    found = []
    manifests = sorted((root/'builtin/plugins').glob('*/manifest.json'))
    if not manifests:
        return ['no built-in plugin manifests found']
    for path in manifests:
        manifest = None
        try:
            manifest = compiler.shared.load(path)
            # Same construction as PluginPreferenceOwner's --runtime-store call;
            # the placeholder paths are only emitted as declarations.
            compiler.compile_store(manifest, overlays, path.parent, Path('/check/user.json'),
                                   Path('/check/config.json'), Path('/check/evidence'))
        except (ValueError, KeyError, TypeError, OSError) as error:
            version = manifest.get('version') if isinstance(manifest, dict) else None
            found.append(f'{path.relative_to(root)}: version {version}: {error}')
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    args = parser.parse_args()
    found = failures(args.root.resolve())
    if found:
        for line in found:
            print('built-in plugin settings: ' + line, file=sys.stderr)
        return 1
    print('BUILTIN_PLUGIN_SETTINGS: PASS (every shipped built-in version compiles its settings store)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
