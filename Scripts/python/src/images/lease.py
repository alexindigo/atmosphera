"""An stdin-owned cleanup scope that can unwind after Qt destroys QProcess."""
import os
import signal


def run(owned_scope, *args):
    # QProcess destruction kills the directly tracked PID before that process
    # can run finally blocks. Inherit only the protocol/stdio in the cleanup
    # child, then let EOF release its resources even if the supervisor dies.
    shell = os.getppid()
    child = os.fork()
    if child == 0:
        owned_scope(*args, shell_pid=shell)
        return

    def terminate(signum, _frame):
        try:
            os.kill(child, signum)
        except ProcessLookupError:
            pass

    signal.signal(signal.SIGTERM, terminate)
    # Do not keep QProcess's protocol descriptors alive in both processes.
    for fd in (0, 1, 2):
        os.close(fd)
    _, status = os.waitpid(child, 0)
    code = os.waitstatus_to_exitcode(status)
    raise SystemExit(code if code >= 0 else 128 - code)
