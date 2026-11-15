#!/usr/bin/env python3
"""Inspect, never execute, the literal command of a sh -c locker expression.

Shell syntax remains owned by the launcher. Expressions whose executable needs
shell evaluation are unverified, not missing. Arguments are never evaluated.
"""
import os
import re
import shlex
import shutil
import sys


def check(command):
    if not command.strip():
        return "empty"
    # shlex removes quoting but does not implement expansion, shell grammar or
    # assignment semantics. Do not misdiagnose those expressions as missing.
    if any(char in command for char in "$`\n\r"):
        return "unverified"
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        words = list(lexer)
    except ValueError:
        return "unverified"
    if not words or any(re.fullmatch(r"[();<>|&]+", word) for word in words):
        return "unverified"
    executable = words[0]
    if (not executable or executable.startswith("~")
            or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", executable)
            or any(char in executable for char in "*?[")):
        return "unverified"
    # Shell builtins/keywords are not external executables. Avoid claiming that
    # e.g. `exec aerial-lock` or a function definition is a missing program.
    if executable in {"!", ":", ".", "[", "alias", "bg", "break", "case", "cd",
                      "command", "continue", "do", "done", "echo", "elif", "else",
                      "esac", "eval", "exec", "exit", "export", "false", "fc", "fg",
                      "fi", "for", "getopts", "hash", "if", "in", "jobs", "kill",
                      "local", "printf", "pwd", "read", "readonly", "return", "set",
                      "shift", "test", "then", "times", "trap", "true", "type",
                      "ulimit", "umask", "unalias", "unset", "until", "wait", "while",
                      "{", "}"}:
        return "unverified"
    return "available" if shutil.which(executable, path=os.environ.get("PATH", os.defpath)) else "missing"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(2)
    print(check(sys.argv[1]))
