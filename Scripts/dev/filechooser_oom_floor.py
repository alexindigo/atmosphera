"""Seal an owned, still-waiting guest supervisor's inherited OOM minimum.

Only the outer guest controller uses sudo. The fixed helper cannot launch code,
change a score to any other value, or target an unvalidated process identity.
"""
import json
import os
from pathlib import Path
import subprocess


# Run isolated from Python's environment/import paths with no source imports.
# Linux fs/proc/base.c updates oom_score_adj_min when a CAP_SYS_RESOURCE writer
# writes oom_score_adj, even when the score was already 1000. Fork inherits it.
_SEAL = r'''
import json, os, sys
from pathlib import Path
spec = json.load(sys.stdin)
assert os.geteuid() == 0
assert Path('/sys/class/dmi/id/product_uuid').read_text().strip().lower() == spec['uuid']
assert spec['uid'] > 0
proc = '/proc/' + str(int(spec['pid']))
fd = os.open(proc, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
def read(name):
    with open(os.open(name, os.O_RDONLY, dir_fd=fd), 'rb', closefd=True) as stream:
        return stream.read()
def identity():
    stat = read('stat').decode().rsplit(')', 1)[1].split()
    return int(stat[19]), stat[0]
before = identity()
assert before[0] == spec['start_time'] and before[1] not in ('Z', 'X', 'x')
status = dict(line.split(':', 1) for line in read('status').decode().splitlines() if ':' in line)
assert set(map(int, status['Uid'].split())) == {spec['uid']}
assert read('cmdline').decode().split('\0')[:-1] == spec['argv']
assert read('cgroup').decode().strip() == spec['cgroup']
assert os.readlink('ns/pid', dir_fd=fd) == spec['namespace']
assert spec['namespace'] != os.readlink('/proc/self/ns/pid')
assert read('oom_score_adj').strip() == b'1000'
assert not read('task/' + str(spec['pid']) + '/children').strip()
score = os.open('oom_score_adj', os.O_WRONLY | os.O_NOFOLLOW, dir_fd=fd)
try:
    assert os.write(score, b'1000\n') == 5
finally:
    os.close(score)
assert identity()[0] == before[0]
assert read('oom_score_adj').strip() == b'1000'
os.close(fd)
print(json.dumps({'pid': spec['pid'], 'start_time': before[0], 'score': 1000, 'sealed': True}))
'''


def seal_supervisor(properties, base, output, profile, admin_env):
    main = int(properties['MainPID'])
    children = Path(f'/proc/{main}/task/{main}/children').read_text().split()
    targets = []
    for pid in children:
        proc = Path('/proc') / pid
        argv = (proc / 'cmdline').read_bytes().decode().split('\0')[:-1]
        if '--session' in argv and str(base) in argv:
            targets.append((int(pid), proc, argv))
    assert len(targets) == 1, targets
    pid, proc, argv = targets[0]
    group = '0::' + properties['ControlGroup']
    assert (proc / 'cgroup').read_text().strip() == group
    spec = dict(pid=pid, start_time=int((proc / 'stat').read_text().rsplit(')', 1)[1].split()[19]),
                argv=argv, cgroup=group, namespace=os.readlink(proc / 'ns/pid'),
                uid=profile.uid, uuid=profile.uuid)
    result = subprocess.run(['timeout', '10', 'sudo', '-n', '/usr/bin/python3', '-I', '-c', _SEAL],
                            input=json.dumps(spec), env=admin_env, capture_output=True, text=True, timeout=15)
    (output / 'oom-floor-helper.log').write_text(result.stdout + result.stderr)
    result.check_returncode()
    receipt = json.loads(result.stdout)
    assert receipt['sealed'] and receipt['pid'] == pid and receipt['start_time'] == spec['start_time']
    (output / 'oom-floor-seal.json').write_text(json.dumps(dict(spec=spec, receipt=receipt), indent=2))


def verify_inherited_floor(output):
    # A separate child proves inheritance and the kernel's refusal, not a
    # background repair loop. No extra privilege reaches the private workload.
    code = """
import json
from pathlib import Path
score = Path('/proc/self/oom_score_adj')
before = score.read_text().strip()
denied = False
try:
    score.write_text('200\\n')
except PermissionError:
    denied = True
after = score.read_text().strip()
print(json.dumps({'before': before, 'after': after, 'loweringDenied': denied}))
assert before == after == '1000' and denied
"""
    result = subprocess.run(['timeout', '5', '/usr/bin/python3', '-I', '-c', code],
                            capture_output=True, text=True, timeout=8)
    (output / 'oom-floor-child.log').write_text(result.stdout + result.stderr)
    result.check_returncode()
