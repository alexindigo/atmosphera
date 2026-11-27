"""Qualify the real AUR metadata and Nix wrapper dependency graph."""
import json
from pathlib import Path
import re


from image_decoding_package_contract import AUR_REMOVED, AUR_REQUIRED, AUR_VARIANTS, NIX_DECODER, NIX_REMOVED


def qualify(run):
    source = run.args.source
    for variant in AUR_VARIANTS:
        generated = run.command(['makepkg', '--printsrcinfo'], cwd=source / 'packaging/aur' / variant)
        (run.out / (variant + '.SRCINFO')).write_text(generated.stdout)
        deps = set(re.findall(r'^\s+depends = ([\w-]+)', generated.stdout, re.M))
        run.check('aur-' + variant + '-imvqml-runtime', generated.returncode == 0 and
                  AUR_REQUIRED <= deps and not (AUR_REMOVED & deps),
                  dict(exit=generated.returncode, dependencies=sorted(deps)))

    # Evaluate the exact dirty source snapshot against the checked-in lock.
    # preFixup is the argument text of the actual wrapped launcher's PATH and
    # imports. Do not ban libav in the transitive decoder/media closure.
    result = run.command(['nix', '--extra-experimental-features', 'nix-command flakes', 'eval',
                          '--json', '--no-update-lock-file', f'path:{source}#default', '--apply',
                          'p: { inputs = map (d: d.outPath) p.buildInputs; inherit (p) preFixup; }'], timeout=600)
    (run.out / 'nix-eval.log').write_text(result.stdout + result.stderr)
    (run.out / 'nix-eval.json').write_text(result.stdout)
    graph = json.loads(result.stdout) if result.returncode == 0 else {}
    decoder = [path for path in graph.get('inputs', []) if Path(path).name.partition('-')[2].startswith(NIX_DECODER + '-')]
    wrapper = graph.get('preFixup', '')
    paths = re.findall(r'/nix/store/[^\s":)]+', wrapper)
    roots = {path.split('/')[3] for path in paths + graph.get('inputs', [])}
    removed = sorted(root for root in roots if any(root.partition('-')[2] == name or
                     root.partition('-')[2].startswith(name + '-') for name in NIX_REMOVED))
    qml_paths = re.findall(r'(?m)^\s*--prefix QML_IMPORT_PATH : (\S+)', wrapper)
    run.check('nix-imvqml-runtime-and-no-converter-cli', result.returncode == 0 and len(decoder) == 1 and
              any(path.startswith(decoder[0] + '/') and path.endswith('/qml') for path in qml_paths) and not removed,
              dict(exit=result.returncode, decoder=decoder, removed=removed, graph=graph))
