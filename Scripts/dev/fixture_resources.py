"""Lexical ownership for regression-driver resources and teardown evidence."""
from functools import partial
import subprocess
import threading

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
        proc = subprocess.Popen(argv, start_new_session=True, **kwargs)
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
