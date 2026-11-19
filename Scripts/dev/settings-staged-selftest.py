#!/usr/bin/env python3
"""Prove final-index ownership independently of working-tree input/tooling."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile

spec=importlib.util.spec_from_file_location('contracts',Path(__file__).with_name('settings-contract-check.py'))
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
with tempfile.TemporaryDirectory(prefix='settings-stage-proof-') as directory:
    root=Path(directory)/'repository'; root.mkdir()
    def git(*args):
        return subprocess.run(['git',*args],cwd=root,check=True,capture_output=True,timeout=15)
    git('init','-q')
    path=root/'input.json'; path.write_text('staged\n'); git('add','input.json')
    path.write_text('unrelated unstaged\n')
    (root/'untracked.json').write_text('untracked\n')
    first=Path(directory)/'first'; first.mkdir()
    tree1=module.staged_snapshot(root,first)
    assert (first/'input.json').read_text()=='staged\n'
    assert not (first/'untracked.json').exists()
    git('add','input.json')
    second=Path(directory)/'second'; second.mkdir()
    tree2=module.staged_snapshot(root,second)
    assert tree1!=tree2 and (second/'input.json').read_text()=='unrelated unstaged\n'
print('SETTINGS_STAGED_SELFTEST: PASS (staged content; unstaged/untracked exclusion; restaged tree)')
