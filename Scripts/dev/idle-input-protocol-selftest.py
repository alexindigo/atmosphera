#!/usr/bin/env python3
"""Guest-only registry wire fixture for the production capability boundary."""
import argparse
import os
from pathlib import Path
import socket
import struct
import subprocess
import threading


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    assert subprocess.check_output(['systemd-detect-virt', '--vm'], text=True).strip() in ('qemu', 'kvm')
    args.work.mkdir(parents=True, exist_ok=False)
    helper = Path(__file__).resolve().parents[1] / 'python/idle-input-protocol.py'
    for version, expected in ((0, 1), (1, 1), (2, 0), (3, 0)):
        path = args.work / ('wayland-' + str(version))
        server = socket.socket(socket.AF_UNIX)
        server.bind(str(path))
        server.listen(1)
        server.settimeout(10)
        errors = []
        def serve():
            try:
                with server.accept()[0] as peer:
                    peer.settimeout(10)
                    data = b''
                    registry = None
                    while True:
                        chunk = peer.recv(4096)
                        if not chunk:
                            raise RuntimeError('registry client disconnected before sync')
                        data += chunk
                        while len(data) >= 8:
                            obj, header = struct.unpack_from('=II', data)
                            size, opcode = header >> 16, header & 0xffff
                            if len(data) < size:
                                break
                            message, data = data[:size], data[size:]
                            assert obj == 1 and size == 12
                            new_id = struct.unpack_from('=I', message, 8)[0]
                            if opcode == 1:
                                registry = new_id
                            else:
                                assert opcode == 0 and registry
                                if version:
                                    name = b'ext_idle_notifier_v1\0'
                                    payload = struct.pack('=II', 1, len(name)) + name
                                    payload += b'\0' * (-len(name) % 4) + struct.pack('=I', version)
                                    peer.sendall(struct.pack('=II', registry, (len(payload) + 8) << 16) + payload)
                                peer.sendall(struct.pack('=III', new_id, 12 << 16, 1))
                                return
            except Exception as error:
                errors.append(error)
        thread = threading.Thread(target=serve)
        thread.start()
        try:
            result = subprocess.run(['python3', '-B', str(helper)], env=dict(os.environ,
                XDG_RUNTIME_DIR=str(args.work), WAYLAND_DISPLAY=path.name),
                capture_output=True, text=True, timeout=10)
            thread.join(11)
            assert not thread.is_alive() and not errors, errors
            assert result.returncode == expected, (version, result)
            print('IDLE_INPUT_PROTOCOL: PASS version=' + str(version), flush=True)
        finally:
            server.close()
            path.unlink()


if __name__ == '__main__':
    main()
