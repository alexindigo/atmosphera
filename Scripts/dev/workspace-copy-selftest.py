#!/usr/bin/env python3
"""Reject recursive source copies at every presentation-runner entry point."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from workspace_guard import require_disk_backed_paths


ENTRIES = (
    'anchor-identity-regression.py', 'edge-scroll-e2e.py',
    'edge-scroll-settings-regression.py', 'external-command-regression.py',
    'panel-cold-load.py', 'plugin-panel-lifecycle.py', 'popup-owner-regression.py',
    'presentation-sequence-regression.py', 'presentation-state-regression.py',
)
PROBE = '''
import runpy, sys
from unittest.mock import patch
entry, source, workspace = sys.argv[1:]
sys.path.insert(0, str(__import__('pathlib').Path(entry).parent))
sys.argv = [entry, '--source', source, '--workspace', workspace]
with patch('shutil.copytree', side_effect=RuntimeError('COPY_REACHED')):
    runpy.run_path(entry, run_name='__main__')
'''


def main():
    require_disk_backed_paths(os.environ.get('TMPDIR', ''))
    with tempfile.TemporaryDirectory(prefix='workspace-copy-') as temporary:
        root = Path(temporary)
        source = root / 'source'
        source.mkdir()
        alias = root / 'alias'
        alias.symlink_to(source, target_is_directory=True)
        cases = [('equal', source, False), ('nested', source / 'nested', False),
                 ('symlink', alias / 'nested', False), ('outside', root / 'outside', True)]
        for entry in ENTRIES:
            for label, workspace, allowed in cases:
                result = subprocess.run([sys.executable, '-B', '-c', PROBE,
                                         str(Path(__file__).with_name(entry)), str(source), str(workspace)],
                                        text=True, capture_output=True, timeout=15)
                if allowed:
                    assert result.returncode == 1 and 'COPY_REACHED' in result.stderr, (entry, label, result.stderr)
                    workspace.rmdir()
                else:
                    assert result.returncode == 2 and 'outside the source' in result.stderr, (entry, label, result.stderr)
                    if label != 'equal':
                        assert not workspace.exists(), (entry, label, 'created rejected workspace')
                print(entry, label, 'PASS', flush=True)
    print('Workspace copy boundaries: 36/36 PASS', flush=True)


if __name__ == '__main__':
    main()
