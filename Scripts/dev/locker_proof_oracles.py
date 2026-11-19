"""Narrow evidence oracles for locker proofs, never product authority."""
import json
import re


def pam_success(message):
    if 'LOCKER_PAM_SUCCESS ' in message:
        return True
    try:
        return json.loads(message).get('event') == 'pam-success'
    except (ValueError, AttributeError):
        return False


def authenticated_unlocks(events, expected):
    """Every native unlock follows real PAM success in the same invocation."""
    unlocks = [(index, row) for index, row in enumerate(events) if row['kind'] == 'journal'
        and re.search(r'ext_session_lock_v1#\d+\.unlock_and_destroy\(', row.get('message', ''))]
    assert len(unlocks) == expected, 'unexpected native unlock count'
    proofs = []
    consumed = {}
    for unlock_index, unlock in unlocks:
        # journald can timestamp consecutive lines from one stream identically.
        # journalctl preserves their source order; require both earlier position
        # and a non-later source time, never merely an auth-attempt timestamp.
        # Each unlock needs its own success after the client's previous unlock.
        client = (unlock.get('invocation'), unlock.get('pid'))
        after = consumed.get(client, -1)
        consumed[client] = unlock_index
        successes = [row for index, row in enumerate(events) if after < index < unlock_index and row['kind'] == 'journal'
            and row.get('invocation') == unlock.get('invocation') and row.get('invocation')
            and row.get('pid') == unlock.get('pid') and row.get('pid')
            and pam_success(row.get('message', ''))
            and row['sourceMonotonic'] <= unlock['sourceMonotonic']]
        assert successes, 'native unlock lacks preceding same-invocation/client PAM success'
        success = max(successes, key=lambda row: row['sourceMonotonic'])
        proofs.append(dict(invocation=unlock['invocation'], pid=unlock['pid'],
            pamSuccessAt=success['sourceMonotonic'], nativeUnlockAt=unlock['sourceMonotonic']))
    return proofs


def process_report_commit(trace, path, received, destroyed):
    """Exact synced file and atomic rename before teardown, not power-loss proof.

    The complete report is atomically visible before teardown and survives the
    writer's death within this boot. Runtime tmpfs is wiped at logout/reboot;
    directory fsync cannot add reboot persistence to this session channel.
    """
    commits = []
    for at, line in trace:
        match = re.search(r'rename\("([^"]+)", "([^"]+)"\)\s*= 0', line)
        if not match or match[2] != str(path) or not received < at < destroyed:
            continue
        def producer(text):
            prefix = re.match(r'\[trace=([^]]+)\]', text)
            return prefix[1] if prefix else ''
        related = [(when, text) for when, text in trace if received < when < at
            and producer(text) == producer(line)]
        synced = [(when, text) for when, text in related
            if re.search(r'(?:fsync|fdatasync)\(\d+<' + re.escape(match[1]) + r'>\)\s*= 0', text)]
        # Qt's QSaveFile can sync an O_TMPFILE inode before materializing it
        # with linkat(/proc/self/fd/N, temporaryName). Bind that successful link
        # to the exact synced fd lifetime and the exact subsequent rename.
        links = []
        for linked_at, text in related:
            link = re.search(r'linkat\(AT_FDCWD(?:<[^>]+>)?, "/proc/self/fd/(\d+)", AT_FDCWD(?:<[^>]+>)?, "'
                + re.escape(match[1]) + r'", AT_SYMLINK_FOLLOW\)\s*= 0', text)
            if not link:
                continue
            fd = link[1]
            for when, sync in related:
                anonymous = re.search(r'(?:fsync|fdatasync)\(' + fd + r'<([^>]+)>\(deleted\)\)\s*= 0', sync)
                if not anonymous or not when < linked_at:
                    continue
                if not re.search(r'/#[0-9]+>\(deleted\)', sync):
                    continue
                if any(when < closed_at < linked_at and re.search(r'close\(' + fd + r'(?:<[^>]+>)?\)\s*= 0', closed)
                        for closed_at, closed in related):
                    continue
                synced.append((when, sync))
                links.append((linked_at, text))
        if synced:
            commits.append(dict(renameAt=at, rename=line, sync=synced[-1], materialization=links, temporaryPath=match[1]))
    assert commits, 'exact report file was not synced and atomically committed before teardown'
    return commits
