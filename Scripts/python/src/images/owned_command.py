"""Own one decoder process group even if the requesting worker dies.

The worker retains the only write end of stdin. EOF, SIGTERM and timeout all
retire the group and reap delegates. The decoder never inherits this pipe.
Output is streamed to operation-private files, not buffered in communicate().
"""
import ctypes
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import time


def identity(pid):
    path = Path('/proc') / str(pid)
    fields = (path / 'stat').read_text().rsplit(')', 1)[1].split()
    return dict(pid=pid, start=fields[19], uid=path.stat().st_uid, group=int(fields[2]))


def main():
    # The dedicated watcher becomes the orphan reaper for the decoder subtree.
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(36, 1, 0, 0, 0) != 0:  # PR_SET_CHILD_SUBREAPER
        raise OSError(ctypes.get_errno(), 'Could not own decoder descendants')
    spec = json.loads(sys.argv[1])
    stopping = False
    def retire(_number, _frame):
        nonlocal stopping
        stopping = True
    signal.signal(signal.SIGTERM, retire)
    signal.signal(signal.SIGINT, retire)
    started = time.monotonic()
    timed_out, lost_owner = False, False
    with open(spec['stdout'], 'wb') as out, open(spec['stderr'], 'wb') as err:
        process = subprocess.Popen(spec['argv'], stdin=subprocess.DEVNULL, stdout=out, stderr=err,
                                   start_new_session=True, close_fds=True)
        try:
            child = identity(process.pid)
            Path(spec['identity']).write_text(json.dumps(child) + '\n')
            while process.poll() is None:
                if time.monotonic() - started >= spec['timeout']:
                    timed_out = True
                    break
                ready, _, _ = select.select([0], [], [], .05)
                if ready and not os.read(0, 1):
                    lost_owner = True
                    break
                if stopping:
                    break
        finally:
            # The group belongs exclusively to the exact child we created. It
            # can contain a delegate after the direct process has already exited.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            # A delegate can create a session of its own. Subreaper adoption
            # keeps that process our child after its parent exits; retire only
            # these exact captured child identities, not a system-wide name.
            deadline = time.monotonic() + 5
            while True:
                try:
                    joined, _ = os.waitpid(-1, os.WNOHANG)
                except ChildProcessError:
                    break
                if joined:
                    continue
                children = Path(f'/proc/self/task/{os.getpid()}/children').read_text().split()
                for pid in children:
                    try:
                        owned = identity(int(pid))
                        if identity(owned['pid']) == owned:
                            os.kill(owned['pid'], signal.SIGKILL)
                    except (FileNotFoundError, ProcessLookupError):
                        pass
                if time.monotonic() >= deadline:
                    raise RuntimeError('Decoder descendants did not retire')
                time.sleep(.01)
    Path(spec['result']).write_text(json.dumps(dict(exit=process.returncode, timeout=timed_out,
                                                   cancelled=stopping or lost_owner, child=child)) + '\n')


if __name__ == '__main__':
    main()
