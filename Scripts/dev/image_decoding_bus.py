"""Fixture-owned notification bus, without login-session service activation."""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import time
from xml.sax.saxutils import escape

from guest_profile import ProcessIdentity, protect_owned_process


def kernel(identity):
    return identity.pid, identity.start, identity.uid, identity.pgid


def address_for(profile):
    runtime = Path(profile.child_environment('bus-')['XDG_RUNTIME_DIR'])
    # VM profiles forward the real session bus as runtime/bus. Do not replace
    # that link; this synthetic endpoint has its own fresh socket name.
    path = runtime / 'notification-bus'
    if len(os.fsencode(path)) >= 108:
        raise ValueError('Profile runtime root is too long for a private Unix socket')
    return 'unix:path=' + str(path)


@contextmanager
def private_bus(profile, output, address=None):
    """Own one daemon; preserve both consumer and teardown errors on failure.

    This bus carries only fixture-owned notification producers/servers. The
    system session.conf imports desktop portals, accessibility and user-manager
    activation, none of which belongs to this synthetic notification endpoint.
    """
    address = address if address is not None else address_for(profile)
    socket = Path(address.removeprefix('unix:path='))
    if (address != 'unix:path=' + str(socket) or socket != socket.resolve() or socket.exists()
            or not socket.is_relative_to(profile.runtime_base) or socket.parent.stat().st_uid != os.getuid()
            or socket.parent.stat().st_mode & 0o077):
        raise ValueError('Private bus requires an unused socket in its owned private runtime directory')
    config = output / 'bus.conf'
    config.write_text('''<busconfig>
  <type>session</type>
  <auth>EXTERNAL</auth>
  <listen>''' + escape(address) + '''</listen>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
''')
    record = dict(address=address, primaryError='', cleanupError='', escalated=False)
    primary = cleanup = None
    with (output / 'bus.log').open('w') as log:
        bus = subprocess.Popen(['dbus-daemon', '--config-file=' + str(config), '--nofork',
                                '--print-address=1', '--address=' + address],
                               stdout=subprocess.PIPE, stderr=log, text=True, start_new_session=True)
        guard = protect_owned_process(bus)
        record['identity'] = guard.identity.record() if guard.identity else None
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(bus.stdout, selectors.EVENT_READ)
                if not selector.select(10):
                    raise TimeoutError('Private notification bus did not publish its address')
                actual = bus.stdout.readline().strip()
            if not actual.startswith(address + ',guid=') or kernel(ProcessIdentity.read(bus.pid)) != kernel(guard.identity):
                raise AssertionError('Private notification bus address/ownership changed')
            record['readyIdentity'] = ProcessIdentity.read(bus.pid).record()
            yield actual
        except BaseException as error:
            primary = error
            record['primaryError'] = repr(error)
        finally:
            try:
                guard.terminate()
                record['exit'] = bus.wait(timeout=10)
            except BaseException as error:
                cleanup = error
                record['cleanupError'] = repr(error)
                # A failed deadline is still a failure. Reap only the exact
                # captured group; never leave the bus behind or hide the error.
                if bus.poll() is None:
                    if kernel(ProcessIdentity.read(bus.pid)) != kernel(guard.identity):
                        raise AssertionError('Private bus ownership changed before escalation') from error
                    os.killpg(guard.identity.pgid, signal.SIGKILL)
                    record['escalated'] = True
                    record['exit'] = bus.wait(timeout=10)
            finally:
                bus.stdout.close()
                record['elapsedEnd'] = time.monotonic()
                (output / 'bus-process.json').write_text(json.dumps(record, indent=2) + '\n')
    if primary is not None and cleanup is not None:
        raise BaseExceptionGroup('Notification consumer and private bus cleanup failed', [primary, cleanup])
    if primary is not None:
        raise primary.with_traceback(primary.__traceback__)
    if cleanup is not None:
        raise cleanup.with_traceback(cleanup.__traceback__)
