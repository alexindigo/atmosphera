#!/usr/bin/env python3
"""Real build/commit/push failure and retry contracts, using guest-local bare repos.

Run only in the assigned Arch VM: test-publish.py STABLE_FIXTURE GIT_FIXTURE FRESH_WORKSPACE
No AUR remote is configured or written by these tests.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

RECIPES = Path(__file__).resolve().parent
STABLE, GIT, WORK = (Path(p).resolve() for p in sys.argv[1:])
WORK.mkdir()
for name in ('tmp', 'remotes', 'clones'):
    (WORK / name).mkdir()
os.environ['TMPDIR'] = str(WORK / 'tmp')

def run(*args, cwd=WORK, success=True):
    result = subprocess.run(list(map(str, args)), cwd=cwd, text=True, capture_output=True, timeout=600)
    if success and result.returncode:
        raise AssertionError((args, result.returncode, result.stdout, result.stderr))
    if not success and result.returncode == 0:
        raise AssertionError(('expected failure', args, result.stdout))
    return result.stdout

def identity(directory):
    run('git', 'config', 'user.name', 'Fixture', cwd=directory)
    run('git', 'config', 'user.email', 'fixture@example.invalid', cwd=directory)

def clones(label, remotes):
    result = []
    for name, remote in zip(('atmosphera', 'atmosphera-git'), remotes):
        directory = WORK / 'clones' / (label + '-' + name)
        assert remote.resolve().is_relative_to(WORK)
        run('git', 'clone', remote, directory)
        identity(directory)
        result.append(directory)
    return result

def seed(label):
    remotes = []
    for name, fixture in (('atmosphera', STABLE), ('atmosphera-git', GIT)):
        directory = WORK / (label + '-seed-' + name)
        shutil.copytree(fixture, directory)
        run('git', 'init', '-b', 'master', cwd=directory)
        identity(directory)
        run('git', 'add', '.', cwd=directory)
        run('git', 'commit', '-m', 'fixture', cwd=directory)
        remote = WORK / 'remotes' / (label + '-' + name + '.git')
        run('git', 'clone', '--bare', directory, remote)
        remotes.append(remote)
    return remotes, clones(label, remotes)

def heads(remotes):
    return [run('git', 'rev-parse', 'refs/heads/master', cwd=remote).strip() for remote in remotes]

def publish(recipes, directories, label, success=True):
    summary = WORK / (label + '-summary.md')
    result = subprocess.run([sys.executable, str(recipes / 'sync.py'), 'v0.9.0',
                             *(str(p) for p in directories), '--push', '--summary', str(summary)],
                            text=True, capture_output=True, timeout=600)
    (WORK / (label + '.log')).write_text(result.stdout + result.stderr)
    assert (result.returncode == 0) == success, (label, result.returncode, result.stdout, result.stderr)
    assert summary.exists(), label
    return result.stdout, summary.read_text()

recipes = WORK / 'recipes'
shutil.copytree(RECIPES, recipes)
metadata = recipes / 'metadata.sh'
metadata.write_text(metadata.read_text().replace("  'python'\n", "  'python'\n  'file'\n"))

invalid = WORK / 'invalid-recipes'
shutil.copytree(recipes, invalid)
path = invalid / 'atmosphera-git/PKGBUILD'
path.write_text(path.read_text() + '\n) invalid syntax\n')
remotes, directories = seed('prepare-failure')
before = heads(remotes)
_, summary = publish(invalid, directories, 'prepare-failure', success=False)
assert heads(remotes) == before and 'not attempted' in summary
print('PASS: actual second preparation failure pushes neither repository', flush=True)

# A real makepkg package() error in the second recipe must publish neither repo.
broken = WORK / 'broken-build-recipes'
shutil.copytree(recipes, broken)
path = broken / 'atmosphera-git/PKGBUILD'
path.write_text(path.read_text() + '\npackage() { return 75; }\n')
remotes, directories = seed('build-failure')
before = heads(remotes)
_, summary = publish(broken, directories, 'build-failure', success=False)
assert heads(remotes) == before
assert all(run('git', 'rev-list', '--count', 'HEAD', cwd=p).strip() == '1' for p in directories)
assert 'not attempted' in summary
print('PASS: actual second build failure leaves both remote refs and local commits unchanged', flush=True)

# A real second commit-hook failure must also occur before either push.
remotes, directories = seed('commit-failure')
hook = directories[1] / '.git/hooks/pre-commit'
hook.write_text('#!/bin/sh\nexit 76\n')
hook.chmod(0o755)
before = heads(remotes)
_, summary = publish(recipes, directories, 'commit-failure', success=False)
assert heads(remotes) == before and 'not attempted' in summary
print('PASS: actual second local commit failure pushes neither repository', flush=True)

# Both local HEADs must already contain the changed recipes when the first
# remote's receive hook runs. This observes the external boundary, not a mock.
remotes, directories = seed('push-failure')
before = heads(remotes)
receipt = WORK / 'first-receive.json'
first_hook = remotes[0] / 'hooks/pre-receive'
first_hook.write_text('#!/usr/bin/env python3\n' +
    'import json, os, subprocess\nfrom pathlib import Path\n' +
    f'clones = {list(map(str, directories))!r}\n' +
    'env = {k:v for k,v in os.environ.items() if not k.startswith("GIT_")}\n' +
    'heads = []\nfor directory in clones:\n' +
    '    text = subprocess.check_output(["git", "show", "HEAD:PKGBUILD"], cwd=directory, env=env, text=True)\n' +
    '    assert "  \'file\'\\n" in text\n' +
    '    assert not subprocess.check_output(["git", "status", "--porcelain"], cwd=directory, env=env, text=True)\n' +
    '    heads.append(subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=directory, env=env, text=True).strip())\n' +
    f'Path({str(receipt)!r}).write_text(json.dumps(heads))\n')
first_hook.chmod(0o755)
reject = remotes[1] / 'hooks/pre-receive'
reject.write_text('#!/bin/sh\nexit 77\n')
reject.chmod(0o755)
out, summary = publish(recipes, directories, 'push-failure', success=False)
assert receipt.exists() and len(json.loads(receipt.read_text())) == 2
after = heads(remotes)
assert after[0] != before[0] and after[1] == before[1]
assert '| atmosphera | built and committed | published |' in summary
assert 'remote state unconfirmed' in summary
assert out.index('atmosphera-git: build checked') < out.index('Publishing atmosphera...')
assert 'pkgrel=13\n' in run('git', 'show', 'HEAD:PKGBUILD', cwd=directories[1])
print('PASS: first receive sees both committed recipes; second receive rejects; failure summary names published stable', flush=True)

# A new workflow run uses fresh clones: stable is already current, and -git's
# one missing publication still has pkgrel 13, never 14.
reject.unlink()
retry = clones('retry', remotes)
out, summary = publish(recipes, retry, 'retry')
retried = heads(remotes)
assert retried[0] == after[0] and retried[1] != after[1]
assert 'Publishing atmosphera...' not in out and 'Publishing atmosphera-git...' in out
assert 'already current (no-op)' in summary
assert 'pkgrel=13\n' in run('git', 'show', 'master:PKGBUILD', cwd=remotes[1])
print('PASS: fresh-clone retry publishes only missing -git, with exactly one pkgrel bump', flush=True)

again = clones('again', remotes)
out, summary = publish(recipes, again, 'again')
assert heads(remotes) == retried and 'Publishing ' not in out
assert summary.count('already current (no-op)') == 2
print('PASS: identical subsequent workflow run commits/pushes nothing and bumps no counters', flush=True)
print('ALL PUBLICATION CONTRACT CHECKS PASSED', flush=True)
