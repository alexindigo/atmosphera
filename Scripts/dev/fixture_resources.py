"""Lexical ownership for regression-driver resources and teardown evidence."""
from functools import partial
import subprocess
import threading
import time
import uuid
from pathlib import Path

from guest_profile import protect_owned_process


class FixtureResources:
    def __init__(self):
        self._cleanup = []

    def __enter__(self):
        return self

    def __exit__(self, _type, primary, _traceback):
        failures = []
        while self._cleanup:
            try:
                self._cleanup.pop()()
            except BaseException as error:
                failures.append(error)
        if failures:
            if primary is None and len(failures) == 1:
                raise failures[0]
            raise BaseExceptionGroup('fixture execution and cleanup failed',
                                     ([primary] if primary is not None else []) + failures) from None
        return False

    def close(self):
        self.__exit__(None, None, None)

    def defer(self, callback, *args, **kwargs):
        self._cleanup.append(partial(callback, *args, **kwargs))

    def open(self, path, *args, **kwargs):
        stream = path.open(*args, **kwargs)
        self.defer(stream.close)
        return stream

    def spawn(self, argv, *, timeout=5, guard_factory=protect_owned_process, **kwargs):
        return self._spawn(argv, timeout, guard_factory, **kwargs)

    def spawn_direct(self, argv, *, timeout=5, **kwargs):
        """Own only the direct child, e.g. when observing a descendant's fate."""
        return self._spawn(argv, timeout, None, **kwargs)

    def _spawn(self, argv, timeout, guard_factory, **kwargs):
        proc = subprocess.Popen(argv, start_new_session=guard_factory is not None, **kwargs)
        self.defer(proc.wait, timeout=timeout)
        guard = None

        def stop():
            if guard is None:
                # Identity capture itself failed. Only the direct Popen child
                # is owned; never signal an unverified process group.
                proc.terminate()
            else:
                guard.terminate()

        self.defer(stop)
        if guard_factory is not None:
            guard = guard_factory(proc)
        return proc

    def thread(self, target, *, stop=None, daemon=None, timeout=5):
        worker = threading.Thread(target=target, daemon=daemon)
        worker.start()

        def join():
            worker.join(timeout=timeout)
            if worker.is_alive():
                raise RuntimeError('fixture worker did not exit')

        self.defer(join)
        if stop is not None:
            self.defer(stop)
        return worker

    def serve(self, server, *, daemon=None, interrupt=None, release=None):
        # Binding owns a socket even if the worker cannot be constructed or started.
        self.defer(server.server_close)
        self.thread(server.serve_forever, stop=interrupt or server.shutdown, daemon=daemon)
        if release is not None:
            self.defer(release)
        return server


def start_private_bus(resources, socket_root, log_path, *, publish=None, **details):
    """Start the private bus, owning process and log before readiness or receipts."""
    # AF_UNIX addresses must not inherit the nested case-directory length.
    socket = socket_root / ('psh-bus-' + uuid.uuid4().hex[:12])
    address = 'unix:path=' + str(socket)
    receipt = None

    def mark_joined():
        if receipt is not None and process.returncode is not None:
            publish(dict(receipt, joined=True, returncode=process.returncode))

    if publish is not None:
        resources.defer(mark_joined)
    log = resources.open(log_path, 'w')
    process = resources.spawn(['/usr/bin/dbus-daemon', '--session', '--nofork', '--address=' + address],
                              stdout=log, stderr=subprocess.STDOUT)
    for _ in range(200):
        if socket.exists():
            break
        time.sleep(.01)
    else:
        raise RuntimeError('private bus unavailable')
    if publish is not None:
        stat = (Path('/proc') / str(process.pid) / 'stat').read_text()
        receipt = dict(details, pid=process.pid, start=stat.split(') ', 1)[1].split()[19], address=address, joined=False)
        publish(receipt)
    return address
