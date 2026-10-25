#!/usr/bin/env python3
"""Real build/commit/push failure and retry contracts, using guest-local bare repos.

Run only in the assigned Arch VM: test-publish.py STABLE_FIXTURE GIT_FIXTURE FRESH_WORKSPACE
No AUR remote is configured or written by these tests.
"""
import json
import os
from pathlib import Path
import pwd
import re
import shlex
import shutil
import subprocess
import sys
import time

RECIPES = Path(__file__).resolve().parent
STABLE, GIT, WORK = (Path(p).resolve() for p in sys.argv[1:])
WORK.mkdir()
PRIVATE = Path(os.environ['AUR_TEST_PUBLISH_ROOT']).resolve()
PRIVATE.mkdir()
BUILD_USER = os.environ['AUR_TEST_BUILD_USER']
WORKER_ROOT = Path(os.environ['AUR_TEST_WORKER_ROOT']).resolve()
assert os.geteuid() == 0 and PRIVATE.stat().st_uid == 0
PRIVATE.chmod(0o700)
(PRIVATE / 'summaries').mkdir()
(PRIVATE / 'tmp').mkdir()
for name in ('tmp', 'remotes', 'clones'):
    (WORK / name).mkdir()
os.environ['TMPDIR'] = str(PRIVATE / 'tmp')

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
        directory = PRIVATE / (label + '-' + name)
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

def publish(recipes, directories, label, success=True, tag='v0.9.0', extra=()):
    summary = PRIVATE / 'summaries' / (label + '-summary.md')
    # Match the workflow: maintained publisher, separately selected recipe data.
    result = subprocess.run([sys.executable, str(RECIPES / 'sync.py'), tag,
                             *(str(p) for p in directories), '--push', '--summary', str(summary),
                             '--recipes', str(recipes), '--build-user', BUILD_USER,
                             '--worker-root', str(WORKER_ROOT), *extra],
                             text=True, capture_output=True, timeout=600)
    (WORK / (label + '.log')).write_text(result.stdout + result.stderr)
    assert (result.returncode == 0) == success, (label, result.returncode, result.stdout, result.stderr)
    assert summary.exists(), label
    (WORK / (label + '-summary.md')).write_text(summary.read_text())
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

# A stable release's full pacman identity gates both destinations before any
# preparation, including when a fetched remote is newer than stale local HEAD.
def published_stable(directory, version, release='1', epoch=None):
    recipe = directory / 'PKGBUILD'
    text, count = re.subn(r'^pkgver=.*$', f'pkgver={version}', recipe.read_text(), flags=re.MULTILINE)
    assert count == 1
    text, count = re.subn(r'^pkgrel=.*$', f'pkgrel={release}', text, flags=re.MULTILINE)
    assert count == 1
    if epoch:
        text += f'\nepoch={epoch}\n'
    recipe.write_text(text)
    metadata = directory / '.SRCINFO'
    text, count = re.subn(r'^\s*pkgver = .*$', f'\tpkgver = {version}', metadata.read_text(), flags=re.MULTILINE)
    assert count == 1
    text, count = re.subn(r'^\s*pkgrel = .*$', f'\tpkgrel = {release}', text, flags=re.MULTILINE)
    assert count == 1
    if epoch:
        text = text.replace(f'\tpkgver = {version}\n', f'\tpkgver = {version}\n\tepoch = {epoch}\n')
    metadata.write_text(text)
    run('git', 'add', '.', cwd=directory)
    run('git', 'commit', '-m', 'published version fixture', cwd=directory)
    run('git', 'push', 'origin', 'HEAD', cwd=directory)


def refused(recipes, remotes, directories, label, tag):
    before = heads(remotes)
    local = [run('git', 'rev-parse', 'HEAD', cwd=d) for d in directories]
    trees = [run('git', 'diff', 'HEAD', cwd=d) for d in directories]
    out, summary = publish(recipes, directories, label, success=False, tag=tag)
    assert 'refusing downgrade' in (WORK / (label + '.log')).read_text()
    assert heads(remotes) == before
    assert [run('git', 'rev-parse', 'HEAD', cwd=d) for d in directories] == local
    assert [run('git', 'diff', 'HEAD', cwd=d) for d in directories] == trees == ['', '']
    assert all(not run('git', 'status', '--porcelain', cwd=d) for d in directories)
    assert 'prepared' not in summary and 'not attempted' in summary
    print(f'PASS: {label} refuses before either recipe changes; both remotes unchanged', flush=True)


for label, version, release, epoch in (('older-tag', '0.9.0', '1', None),
                                        ('higher-pkgrel', '0.9.0', '2', None),
                                        ('numeric-version', '0.10.0', '1', None),
                                        ('published-epoch', '0.9.0', '1', '1')):
    remotes, directories = seed(label)
    if label != 'older-tag':
        published_stable(directories[0], version, release, epoch)
    refused(recipes, remotes, directories, label, 'v0.8.0' if label == 'older-tag' else 'v0.9.0')

remotes, directories = seed('serialized-versions')
published_stable(directories[0], '0.8.0')
stale = clones('stale-before-newer', remotes)
before = heads(remotes)
# A tag-owned sync.py must not override the maintained publisher's policy.
(recipes / 'sync.py').write_text('raise RuntimeError("tag publisher must never execute")\n')
publish(recipes, directories, 'newer-tag', tag='v0.9.0')
after = heads(remotes)
assert all(a != b for a, b in zip(before, after))
assert '\tpkgver = 0.9.0\n' in run('git', 'show', 'master:.SRCINFO', cwd=remotes[0])
assert 'pkgrel=13\n' in run('git', 'show', 'master:PKGBUILD', cwd=remotes[1])
print('PASS: newer release publishes serially through maintained publisher, not tag-owned code', flush=True)
refused(recipes, remotes, stale, 'stale-clone-after-newer', 'v0.8.0')
equal = clones('equal-after-newer', remotes)
publish(recipes, equal, 'equal-tag')
assert heads(remotes) == after
assert 'pkgrel=13\n' in run('git', 'show', 'master:PKGBUILD', cwd=remotes[1])
print('PASS: equal release after newer publication is a no-op; no second pkgrel bump', flush=True)

# Recipe evaluation and package() both try the publisher's dummy credential and
# Git config. They record only access booleans, never credential contents.
key = PRIVATE / 'id_aur'
key.write_text('non-secret credential-boundary canary\n')
key.chmod(0o600)
assert key.stat().st_uid == 0 and key.stat().st_mode & 0o777 == 0o600
marker = WORKER_ROOT / (WORK.name + '-key-probe.jsonl')
assert not marker.exists()
remotes, directories = seed('key-isolation')
probe_recipes = WORK / 'key-probe-recipes'
shutil.copytree(recipes, probe_recipes)

def probe(stage):
    program = ('import json,os\nfrom pathlib import Path\n' +
        f'key=Path({str(key)!r}); config=Path({str(directories[0] / ".git/config")!r})\n' +
        'try:\n key.read_bytes(); readable=True\nexcept PermissionError:\n readable=False\n' +
        'try:\n with config.open("a") as f: f.write("\\n# keyless write probe\\n")\n writable=True\nexcept PermissionError:\n writable=False\n' +
        'status=Path("/proc/self/status").read_text()\n' +
        'uid=int(next(line for line in status.splitlines() if line.startswith("Uid:")).split()[2])\n' +
        f'row=dict(stage={stage!r},uid=uid,reported_uid=os.geteuid(),key_readable=readable,git_config_writable=writable,' +
        'no_new_privs="NoNewPrivs:\\t1" in status,' +
        'cap_eff=next(line.split()[1] for line in status.splitlines() if line.startswith("CapEff:")),' +
        'credential_environment=any(k in os.environ for k in ["GIT_SSH_COMMAND","SSH_AUTH_SOCK","AUR_SSH_PRIVATE_KEY","GITHUB_ENV"]))\n' +
        f'with Path({str(marker)!r}).open("a") as f: f.write(json.dumps(row)+"\\n")\n')
    return 'python -c ' + shlex.quote(program) + '\n'

for name in ('atmosphera', 'atmosphera-git'):
    path = probe_recipes / name / 'PKGBUILD'
    path.write_text(path.read_text() + '\n' + probe('metadata'))
path = probe_recipes / 'package.sh'
text = path.read_text()
assert text.count('package() {') == 1
path.write_text(text.replace('package() {', '_package_payload() {') +
                '\npackage() {\n' + probe('package') + '  _package_payload\n}\n')
saved = {k: os.environ.get(k) for k in ('GIT_SSH_COMMAND', 'AUR_SSH_PRIVATE_KEY', 'GITHUB_ENV')}
os.environ.update(GIT_SSH_COMMAND='false', AUR_SSH_PRIVATE_KEY='environment sentinel', GITHUB_ENV='file-command sentinel')
try:
    publish(probe_recipes, directories, 'key-isolation')
finally:
    for k, value in saved.items():
        if value is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = value
rows = [json.loads(line) for line in marker.read_text().splitlines()]
assert {r['stage'] for r in rows} == {'metadata', 'package'}
assert all(r['uid'] == pwd.getpwnam(BUILD_USER).pw_uid and not r['key_readable'] and
           not r['git_config_writable'] and not r['credential_environment'] and r['no_new_privs'] and
           int(r['cap_eff'], 16) == 0 for r in rows)
(WORK / 'key-isolation.json').write_text(json.dumps(dict(passed=True, key_uid=key.stat().st_uid,
    key_mode=oct(key.stat().st_mode & 0o777), observations=rows), indent=2))
print('PASS: actual metadata/build code cannot read publisher key/config or credential environment; normal publication succeeds', flush=True)

# A real receive hook stalls after both preparations/builds/commits. The owned
# Git process group must time out while publication status remains unconfirmed.
remotes, directories = seed('push-timeout')
before = heads(remotes)
pidfile = PRIVATE / 'stalled-receive.pid'
hook = remotes[0] / 'hooks/pre-receive'
hook.write_text('#!/bin/sh\nprintf "%s\\n" "$$" > ' + shlex.quote(str(pidfile)) + '\nexec sleep 30\n')
hook.chmod(0o755)
started = time.monotonic()
_, summary = publish(recipes, directories, 'push-timeout', success=False, extra=('--push-timeout', '2'))
elapsed = time.monotonic() - started
assert pidfile.exists() and time.time() - pidfile.stat().st_mtime < 8
assert 'remote state unconfirmed' in summary and heads(remotes) == before
assert 'timed out after 2.0 seconds' in (WORK / 'push-timeout.log').read_text()
pid = pidfile.read_text().strip()
cmdline = Path('/proc') / pid / 'cmdline'
assert not cmdline.exists() or not cmdline.read_bytes()
(WORK / 'push-timeout.json').write_text(json.dumps(dict(passed=True, total_seconds=elapsed,
    push_timeout_seconds=2, failure_after_receive_seconds=time.time()-pidfile.stat().st_mtime,
    remote_heads_unchanged=True, summary=summary), indent=2))
print('PASS: stalled scratch receive fails within push deadline; unconfirmed summary and no surviving hook', flush=True)
print('ALL PUBLICATION CONTRACT CHECKS PASSED', flush=True)
