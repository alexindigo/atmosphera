"""Disk-backed fixture profile and deterministic image payloads for paste proofs."""
import json
import os
import struct
import zlib


def png(color):
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
    pixels = b''.join(b'\0' + bytes(color) * 2 for _ in range(2))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', 2, 2, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')


def profile_environment(profile, source):
    for name in ('home', 'config/atmosphera', 'cache/atmosphera', 'state/atmosphera', 'data', 'tmp'):
        (profile / name).mkdir(parents=True)
    settings = json.loads((source / 'Configs/defaults.json').read_text())
    settings['settingsVersion'] = 62
    settings['general']['animationDisabled'] = True
    settings['appLauncher']['enableClipboardHistory'] = True
    (profile / 'config/atmosphera/settings.json').write_text(json.dumps(settings))
    env = dict(os.environ, HOME=str(profile / 'home'), XDG_CONFIG_HOME=str(profile / 'config'),
               XDG_CACHE_HOME=str(profile / 'cache'), XDG_STATE_HOME=str(profile / 'state'),
               XDG_DATA_HOME=str(profile / 'data'), TMPDIR=str(profile / 'tmp'),
               ATMOSPHERA_CONFIG_DIR=str(profile / 'config/atmosphera'), ATMOSPHERA_CACHE_DIR=str(profile / 'cache/atmosphera'),
               ATMOSPHERA_STATE_DIR=str(profile / 'state/atmosphera'), ATMOSPHERA_SETTINGS_FILE=str(profile / 'config/atmosphera/settings.json'))
    env.pop('QT_IM_MODULE', None)
    env.pop('GTK_IM_MODULE', None)
    return env
