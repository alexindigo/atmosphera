"""Reference owner for content-addressed notification originals, not exports."""
import json
import os
from pathlib import Path
import re
import stat
from urllib.parse import unquote, urlsplit

from .storage import atomic_write, directory as open_directory, namespace, read_bytes


NAME = re.compile(r'atmosphera-[0-9a-f]{64}\.[a-z0-9]+')
BOOT = Path('/proc/sys/kernel/random/boot_id')


def identity(pid):
    # PID alone can refer to a different process after reuse or reboot.
    try:
        fields = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
    except (FileNotFoundError, ProcessLookupError):
        return None
    return None if fields[0] == 'Z' else f'{BOOT.read_text().strip()}:{pid}:{fields[19]}'


def read_json(path, default):
    try:
        return json.loads(read_bytes(path))
    except FileNotFoundError:
        return default


def save_json(path, data):
    atomic_write(path, json.dumps(data, ensure_ascii=False).encode() + b'\n', path.parent, private=False)


class NotificationOriginals:
    def __init__(self, directory, history, shell_pid):
        self.directory, self.history = Path(directory), Path(history)
        if (not self.directory.is_absolute() or '..' in self.directory.parts
                or not self.history.is_absolute() or '..' in self.history.parts
                or self.history.is_relative_to(self.directory)):
            raise ValueError('Invalid notification retention store')
        self.journal = self.directory / '.references.json'
        self.session = identity(shell_pid)
        if self.session is None:
            raise OSError('Notification shell has already retired')
        with open_directory(self.directory):
            pass

    def names(self, urls):
        for value in urls:
            url = urlsplit(value)
            if url.scheme == 'file' and not url.netloc:
                path = Path(unquote(url.path))
            elif not url.scheme:
                path = Path(value)
            else:
                continue
            if path.parent == self.directory and NAME.fullmatch(path.name):
                yield path.name

    def history_names(self, rows):
        return set(self.names(row.get('cachedImage') or '' for row in rows))

    def history_rows(self, file):
        rows = read_json(file, {'notifications': []})['notifications']
        if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
            raise ValueError('Invalid notification history')
        return rows

    def update(self, *, wanted=None, live=None, load=False, rows=None, publication=None):
        # A single order for admission, transfer, commit and collection, even
        # across workers. Use the committed JSON as the durable holder, not a
        # copy of what the UI thinks it saved. A failed read vetoes collection.
        with namespace(self.directory, True) as base:
            journal = read_json(self.journal, {'known': [], 'histories': [], 'shells': {}})
            known, histories = set(journal['known']), set(journal['histories'])
            histories.add(str(self.history))
            shells = {key: state for key, state in journal['shells'].items()
                      if identity(int(key.split(':')[1])) == key}
            session = shells.setdefault(self.session, {'live': [], 'pending': {}})
            current = {file: self.history_rows(Path(file)) for file in histories}
            persisted = current[str(self.history)]
            # Adopt historical names even on the first transaction, before a
            # removal can commit. Ignore unrelated files in the directory.
            for existing in current.values():
                known.update(self.history_names(existing))
            if load:
                session['live'] = sorted(self.history_names(persisted))
            if live is not None:
                session['live'] = sorted(self.names(live))
            if wanted is not None:
                session['pending'] = {key: name for key, name in session['pending'].items() if key in wanted}
            if publication is not None:
                key, name, _publish = publication
                session['pending'][key] = name
                known.add(name)
            if rows is not None and not self.history_names(rows) <= set(session['live']) | self.history_names(persisted):
                raise ValueError('Notification history attempted to commit unheld bytes')

            def save():
                save_json(self.journal, dict(known=sorted(known), histories=sorted(histories), shells=shells))

            # Write-ahead: a crash can delay collection but never lose the
            # only claim on a published name or forget an unlinked candidate.
            save()
            if publication is not None:
                _publish()
                os.fsync(base)
            if rows is not None:
                save_json(self.history, {'notifications': rows})
                current[str(self.history)] = rows
            held = set()
            for existing in current.values():
                held.update(self.history_names(existing))
            for state in shells.values():
                held.update(state['live'])
                held.update(state['pending'].values())
            retired = known - held
            for name in retired:
                if not NAME.fullmatch(name):
                    raise ValueError('Invalid notification retention name')
                try:
                    info = os.stat(name, dir_fd=base, follow_symlinks=False)
                    if stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid():
                        os.unlink(name, dir_fd=base)
                except FileNotFoundError:
                    pass
            if retired:
                os.fsync(base)
                known.difference_update(retired)
                save()
            return persisted if load else None

    def publish(self, key, name, writer):
        if not NAME.fullmatch(name):
            raise ValueError('Invalid notification retention name')
        self.update(publication=(key, name, writer))
