#!/usr/bin/env python3
"""terminal-bridge — per-window terminal identity for the niri windows map.

Polls niri for windows, resolves each terminal window's shell cwd and
foreground process purely from /proc, and prints a JSON snapshot (one line)
to stdout whenever the result changes.

Zero dependencies beyond python3 stdlib and the `niri` CLI.

Output: a JSON array per line, e.g.
  [{"winId": 12, "pid": 3625, "cwd": "/home/user/Projects/atmosphera",
    "cwdBase": "atmosphera", "fg": "opencode", "fgCmd": "opencode"}]
`fg`/`fgCmd` are null when the shell sits idle at its prompt.

Attribution: single-instance terminals (e.g. ghostty --gtk-single-instance)
host several windows under one pid. Shells are attributed to windows by
scoring the window title against each shell's cwd basename / "~" home
abbreviation / foreground command name. Best effort; good enough for icon
display.
"""

import json
import os
import subprocess
import sys
import time

POLL_INTERVAL = 2.0
POLL_INTERVAL_DOWN = 5.0  # when niri is unreachable

# appIds we recognize as terminal emulators (niri window app_id)
TERMINAL_APP_IDS = {
    "ghostty",
    "com.mitchellh.ghostty",
    "kitty",
    "foot",
    "footclient",
    "alacritty",
    "wezterm",
    "org.wezfurlong.wezterm",
    "org.kde.konsole",
    "konsole",
    "xterm",
    "uxterm",
    "kgx",
    "gnome-terminal-server",
    "tilix",
    "terminator",
    "contour",
    "rio",
}

SHELLS = {
    "bash", "zsh", "fish", "nu", "nushell", "dash", "sh", "ksh",
    "tcsh", "csh", "xonsh", "elvish", "ion",
}

HOME = os.path.expanduser("~")


class Proc:
    __slots__ = ("pid", "comm", "ppid", "pgrp", "session", "tty", "tpgid")

    def __init__(self, pid, comm, ppid, pgrp, session, tty, tpgid):
        self.pid = pid
        self.comm = comm
        self.ppid = ppid
        self.pgrp = pgrp
        self.session = session
        self.tty = tty
        self.tpgid = tpgid


def read_procs():
    """Snapshot /proc: pid -> Proc, plus children map ppid -> [pid]."""
    procs = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            with open(f"/proc/{pid}/stat", "rb") as f:
                line = f.read().decode("utf-8", "replace")
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        # comm is wrapped in parens and may itself contain spaces/parens
        close = line.rfind(")")
        if close < 0:
            continue
        comm = line[line.find("(") + 1:close]
        fields = line[close + 2:].split()
        if len(fields) < 6:
            continue
        try:
            ppid = int(fields[1])
            pgrp = int(fields[2])
            session = int(fields[3])
            tty = int(fields[4])
            tpgid = int(fields[5])
        except ValueError:
            continue
        procs[pid] = Proc(pid, comm, ppid, pgrp, session, tty, tpgid)

    children = {}
    for p in procs.values():
        children.setdefault(p.ppid, []).append(p.pid)
    return procs, children


def descendants(root_pid, children):
    """All descendant pids of root_pid (not including root itself)."""
    out = []
    stack = list(children.get(root_pid, []))
    while stack:
        pid = stack.pop()
        out.append(pid)
        stack.extend(children.get(pid, []))
    return out


def read_cwd(pid):
    try:
        return os.readlink(f"/proc/{pid}/cwd")
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        return None


def read_cmd0(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            raw = f.read()
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        return None
    if not raw:
        return None
    arg0 = raw.split(b"\0", 1)[0].decode("utf-8", "replace")
    return os.path.basename(arg0) if arg0 else None


def foreground_of(shell, procs, desc_set):
    """Foreground process of a shell's controlling terminal.

    /proc/<pid>/stat tpgid is the fg process group of the shell's tty.
    If it equals the shell's own pgrp, the shell is at its prompt (idle).
    Otherwise the group leader (pid == pgrp) among the shell's descendants
    is the foreground app; fall back to any group member.
    """
    if shell.tpgid <= 0 or shell.tpgid == shell.pgrp:
        return None
    members = [
        procs[p] for p in desc_set
        if p in procs and procs[p].pgrp == shell.tpgid
    ]
    if not members:
        return None
    for m in members:
        if m.pid == m.pgrp:
            return m
    return members[0]


def tilde(cwd):
    if cwd is None:
        return None
    if cwd == HOME:
        return "~"
    if cwd.startswith(HOME + "/"):
        return "~" + cwd[len(HOME):]
    return cwd


def score(window_title, cwd, fg_comm):
    """How well does a shell (cwd/fg) explain this window title?"""
    t = (window_title or "").lower()
    if not t:
        return 0
    s = 0
    if fg_comm:
        # a window titled after a program is not an idle prompt — prefer
        # shells with a live foreground job on ties
        s += 1
        if fg_comm.lower() in t:
            s += 4
    if cwd:
        tcwd = tilde(cwd)
        if tcwd and t == tcwd.lower():
            # title is exactly the cwd — strong signal (shell showing pwd)
            s += 8
            if fg_comm is None:
                # a pwd-titled window most likely sits at a prompt; don't
                # let busy shells claim it over idle ones
                s += 2
        elif tcwd and tcwd != "/" and tcwd.lower() in t:
            s += 3
        base = os.path.basename(cwd)
        if base and base.lower() in t:
            s += 2
    return s


def attribute(windows, shells_info):
    """Assign each window its best-matching shell, globally best-first.

    Greedy in window order lets early windows consume scarce shells that a
    later window explains better (e.g. a pwd-titled window eating the only
    opencode shell while an 'OC | …' window gets nothing). Score every
    window↔shell pair, sort descending, assign greedily — no reuse.
    Zero-score pairs are included so every window still gets *some* shell.
    """
    result = {}
    if not shells_info:
        return result
    by_shell = {sh["shellPid"]: sh for sh in shells_info}
    pairs = []
    for win in windows:
        for sh in shells_info:
            sc = score(win.get("title"), sh["cwd"], sh["fg"])
            pairs.append((-sc, win["id"], sh["shellPid"]))
    pairs.sort()
    used_windows = set()
    used_shells = set()
    for _neg, win_id, shell_pid in pairs:
        if win_id in used_windows or shell_pid in used_shells:
            continue
        used_windows.add(win_id)
        used_shells.add(shell_pid)
        result[win_id] = by_shell[shell_pid]
    return result


def list_terminal_windows():
    out = subprocess.run(
        ["niri", "msg", "-j", "windows"],
        capture_output=True, text=True, timeout=5,
    )
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or "niri msg failed")
    windows = json.loads(out.stdout)
    return [w for w in windows
            if (w.get("app_id") or "") in TERMINAL_APP_IDS and w.get("pid")]


def snapshot():
    windows = list_terminal_windows()
    if not windows:
        return []

    procs, children = read_procs()

    # Group windows by terminal process (single-instance terminals share one)
    by_pid = {}
    for w in windows:
        by_pid.setdefault(w["pid"], []).append(w)

    entries = []
    for pid, wins in by_pid.items():
        desc = descendants(pid, children)
        desc_set = set(desc)
        shells = []
        for p in desc:
            proc = procs.get(p)
            if proc is None or proc.comm not in SHELLS:
                continue
            cwd = read_cwd(p)
            fg = foreground_of(proc, procs, desc_set)
            shells.append({
                "shellPid": p,
                "cwd": cwd,
                "fg": fg.comm if fg else None,
                "fgCmd": read_cmd0(fg.pid) if fg else None,
            })
        assigned = attribute(wins, shells)
        for w in wins:
            sh = assigned.get(w["id"])
            if sh is None:
                continue
            cwd = sh["cwd"]
            entries.append({
                "winId": w["id"],
                "pid": pid,
                "cwd": cwd,
                "cwdBase": os.path.basename(cwd) if cwd else None,
                "fg": sh["fg"],
                "fgCmd": sh["fgCmd"],
            })

    entries.sort(key=lambda e: e["winId"])
    return entries


def main():
    last = None
    interval = POLL_INTERVAL
    while True:
        try:
            snap = snapshot()
            interval = POLL_INTERVAL
        except Exception as exc:  # niri down/restarting — report empty, slow poll
            print(f"terminal-bridge: {exc}", file=sys.stderr)
            snap = []
            interval = POLL_INTERVAL_DOWN
        if snap != last:
            print(json.dumps(snap), flush=True)
            last = snap
        time.sleep(interval)


if __name__ == "__main__":
    main()
