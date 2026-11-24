"""Isolate private Quickshell fixtures from inherited Atmosphera profiles."""
import os


def isolated_profile(profile):
    env = {key: value for key, value in os.environ.items() if not key.startswith('ATMOSPHERA_')}
    for key in ('CONFIG', 'DATA', 'CACHE', 'STATE'):
        directory = profile / key.lower()
        directory.mkdir(parents=True)
        env[f'XDG_{key}_HOME'] = str(directory)
    return env
