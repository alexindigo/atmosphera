"""Qualify the real AUR metadata and Nix wrapper dependency graph."""
import json
from pathlib import Path
import re


REMOVED_TOOLS = {'imagemagick', 'ffmpeg', 'qt6-imageformats', 'qtimageformats'}


def qualify(run):
    source = run.args.source
    for variant in ('atmosphera', 'atmosphera-git'):
        generated = run.command(['makepkg', '--printsrcinfo'], cwd=source / 'packaging/aur' / variant)
        (run.out / (variant + '.SRCINFO')).write_text(generated.stdout)
        deps = set(re.findall(r'^\s+depends = ([\w-]+)', generated.stdout, re.M))
        run.check('aur-' + variant + '-imvqml-runtime', generated.returncode == 0 and
                  {'qt6-imvqml', 'qt6-mpvqml', 'quickshell'} <= deps and not (REMOVED_TOOLS & deps),
                  dict(exit=generated.returncode, dependencies=sorted(deps)))

    # Evaluate the exact dirty source snapshot against the checked-in lock.
    # preFixup is the argument text of the actual wrapped launcher's PATH and
    # imports. Do not ban libav in the transitive decoder/media closure.
    result = run.command(['nix', '--extra-experimental-features', 'nix-command flakes', 'eval',
                          '--json', '--no-update-lock-file', f'path:{source}#default', '--apply',
                          'p: { inputs = map (d: d.outPath) p.buildInputs; inherit (p) preFixup; }'], timeout=600)
    (run.out / 'nix-eval.log').write_text(result.stdout + result.stderr)
    graph = json.loads(result.stdout) if result.returncode == 0 else {}
    decoder = [path for path in graph.get('inputs', []) if '-qt6-imvqml-' in Path(path).name]
    wrapper = graph.get('preFixup', '')
    paths = re.findall(r'/nix/store/[^\s"\)]+', wrapper)
    removed = [path for path in paths + graph.get('inputs', []) if
               re.match(r'^[^-]+-(?:imagemagick|ffmpeg|qtimageformats)(?:-|$)', Path(path).name)]
    run.check('nix-imvqml-runtime-and-no-converter-cli', result.returncode == 0 and len(decoder) == 1 and
              any(path.startswith(decoder[0] + '/') and path.endswith('/qml') for path in paths) and not removed,
              dict(exit=result.returncode, decoder=decoder, removed=removed, graph=graph))
