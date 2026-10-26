#!/usr/bin/env python3
"""Prepare standalone AUR recipes; commit/push only with explicit --push."""

import argparse
import base64
import contextlib
import hashlib
import json
import math
import os
from pathlib import Path
import pwd
import re
import shutil
import signal
import stat
import subprocess
import sys
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parent
TIMEOUTS = {"local": 30.0, "network": 180.0, "build": 600.0}


class CommandError(RuntimeError):
    """A bounded diagnostic, deliberately containing no command argv."""

    def __init__(self, step, *, status=None, timeout=None, tail=""):
        reason = f"timed out after {timeout} seconds" if timeout is not None else f"exited with status {status}"
        super().__init__(f"{step} {reason}\nstderr tail:\n{tail or '(no stderr output)'}")


def command_step(args):
    command = Path(args[0]).name
    if command == "git" and len(args) > 1 and args[1] in (
            "init", "add", "commit", "fetch", "push", "show", "status", "rev-parse", "merge-base"):
        return f"git {args[1]}"
    if command == "makepkg":
        return "makepkg metadata" if "--printsrcinfo" in args else "makepkg package list" if "--packagelist" in args else "makepkg build"
    return command


def stderr_tail(log, lines=12, size=1024):
    log.seek(0, os.SEEK_END)
    log.seek(max(0, log.tell() - 8192))
    text = log.read().decode("utf-8", errors="replace")
    text = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", text)
    return "\n".join(text.splitlines()[-lines:])[-size:]


def run(*args, cwd, env=None, timeout=None, input=None, step=None, tail_lines=12, tail_bytes=1024):
    step = step or command_step(args)
    if timeout is None:
        category = "local"
        if args[0] == "updpkgsums" or (args[0] == "git" and args[1] in ("clone", "fetch", "push")):
            category = "network"
        elif args[0] == "makepkg" and "--printsrcinfo" not in args and "--packagelist" not in args:
            category = "build"
        timeout = TIMEOUTS[category]
    # Stderr remains disk-backed. Failures expose only its bounded tail, never
    # stdout protocol data or Python's raw argv-bearing subprocess exceptions.
    with tempfile.TemporaryFile(mode="w+b") as errors:
        try:
            process = subprocess.Popen(args, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=errors,
                                       stdin=subprocess.PIPE if input is not None else subprocess.DEVNULL,
                                       env=env, start_new_session=True)
        except OSError as error:
            raise CommandError(step, status="not started", tail=error.strerror) from None
        try:
            output, _ = process.communicate(input=input, timeout=timeout)
        except subprocess.TimeoutExpired:
            # Only the invocation's own group, including Git's SSH/receive children.
            for sig in (signal.SIGTERM, signal.SIGKILL):
                try:
                    os.killpg(process.pid, sig)
                except ProcessLookupError:
                    pass
                try:
                    process.communicate(timeout=3)
                    break
                except subprocess.TimeoutExpired:
                    continue
            else:
                process.stdout.close()
                if process.stdin:
                    process.stdin.close()
            raise CommandError(step, timeout=timeout, tail=stderr_tail(errors, tail_lines, tail_bytes)) from None
        if process.returncode:
            raise CommandError(step, status=process.returncode, tail=stderr_tail(errors, tail_lines, tail_bytes))
        errors.seek(0)
        # Preserve successful progress logs without buffering them in memory.
        with contextlib.redirect_stdout(sys.stderr):
            for line in errors:
                print(line.decode("utf-8", errors="replace"), end="")
        return output


def host_key(path):
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), "rb") as source:
        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
            raise ValueError("AUR known_hosts must be a regular file")
        text = source.read(8193).decode("utf-8")
    entries = [line.split() for line in text.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    if len(text) > 8192 or len(entries) != 1 or len(entries[0]) != 3 or entries[0][:2] != ["aur.archlinux.org", "ssh-ed25519"]:
        raise ValueError("AUR known_hosts must contain exactly the pinned aur.archlinux.org Ed25519 entry")
    return base64.b64decode(entries[0][2], validate=True)


def verify_host_keys(path, account):
    pinned = ROOT / "aur-known-hosts"
    protected_path(pinned, account)
    protected_path(path.absolute(), account)
    expected, observed = host_key(pinned), host_key(path)
    fingerprint = lambda key: "SHA256:" + base64.b64encode(hashlib.sha256(key).digest()).decode().rstrip("=")
    if observed != expected:
        raise ValueError(f"AUR host key mismatch: expected {fingerprint(expected)}; got {fingerprint(observed)}; publication not attempted")
    print(f"AUR host key verified: {fingerprint(expected)}", flush=True)


def field(text, name):
    matches = re.findall(rf"^{name}=(.+)$", text, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError(f"expected one {name} assignment")
    return matches[0]


def replace(text, name, value):
    field(text, name)
    return re.sub(rf"^{name}=.*$", lambda _: f"{name}={value}", text,
                  flags=re.MULTILINE)


def render(name, recipes=ROOT):
    text = (recipes / name / "PKGBUILD").read_text()
    for fragment in ("metadata.sh", "package.sh"):
        include = 'source "$(dirname "${BASH_SOURCE[0]}")/../' + fragment + '"\n'
        if text.count(include) != 1:
            raise ValueError(f"{name}: expected one include for {fragment}")
        text = text.replace(include, (recipes / fragment).read_text())
    return text


def stable_identity(metadata):
    """Read pacman's full package identity without executing the old recipe."""
    values = {}
    for name in ("epoch", "pkgver", "pkgrel"):
        matches = re.findall(rf"^\s*{name} = (\S+)$", metadata, re.MULTILINE)
        if not matches and name == "epoch":
            values[name] = "0"
        elif len(matches) != 1:
            raise ValueError(f"published stable .SRCINFO: expected one {name} field")
        else:
            values[name] = matches[0]
    return f"{values['epoch']}:{values['pkgver']}-{values['pkgrel']}"


def validate_version(version, destination, published):
    """Reject a stable downgrade before either package's preparation can write."""
    candidate = f"0:{version}-1"
    refs = ["HEAD"]
    if published:
        refs.append("@{upstream}")
    for ref in refs:
        current = stable_identity(run("git", "show", f"{ref}:.SRCINFO", cwd=destination))
        if int(run("vercmp", candidate, current, cwd=destination).strip()) < 0:
            raise ValueError(f"refusing downgrade: atmosphera {candidate} < {current} ({ref}); neither recipe prepared")
    print(f"atmosphera: version {candidate} is not older than local/published metadata", flush=True)


def prepare(name, destination, version, recipes=ROOT):
    hook = f"{name}.install"
    text = render(name, recipes)
    if name == "atmosphera":
        text = replace(replace(text, "pkgver", version), "pkgrel", "1")
    else:
        old = (destination / "PKGBUILD").read_text()
        # AUR owns these generated counters, not the template's seed values.
        text = replace(text, "pkgver", field(old, "pkgver"))
        text = replace(text, "pkgrel", field(old, "pkgrel"))
        if text == old and (destination / hook).read_bytes() == (recipes / name / hook).read_bytes():
            print(f"{name}: no change", flush=True)
            return False
        release = field(old, "pkgrel")
        if not re.fullmatch(r"[0-9]+", release):
            raise ValueError(f"{name}: expected integer pkgrel, got {release}")
        text = replace(text, "pkgrel", str(int(release) + 1))

    (destination / "PKGBUILD").write_text(text)
    (destination / hook).write_bytes((recipes / name / hook).read_bytes())
    if name == "atmosphera":
        # Keep fetched archives outside the clone so reruns see only recipe
        # changes, not untracked build/cache files.
        sources = Path(os.environ.get("SRCDEST", destination.parent / "sources"))
        sources.mkdir(exist_ok=True)
        run("updpkgsums", cwd=destination, env={**os.environ, "SRCDEST": str(sources)})
        # updpkgsums leaves SKIP untouched; releases must carry a real checksum.
        checksum = field((destination / "PKGBUILD").read_text(), "sha256sums")
        if not re.fullmatch(r"\('[0-9a-f]{64}'\)", checksum):
            raise ValueError(f"{name}: missing release archive checksum")
    metadata = run("makepkg", "--printsrcinfo", cwd=destination)
    (destination / ".SRCINFO").write_text(metadata)
    changed = bool(run("git", "status", "--porcelain", cwd=destination))
    print(f"{name}: {'prepared' if changed else 'no change'}", flush=True)
    return changed


def build_check(name, directory):
    # VCS makepkg rewrites pkgver/pkgrel. Build a private copy so generated build
    # identities never alter the AUR publication counters or retry comparison.
    sources = Path(os.environ.get("SRCDEST", directory.parent / "sources"))
    sources.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f"aur-check-{name}-") as temporary:
        build = Path(temporary)
        for filename in ("PKGBUILD", ".SRCINFO", f"{name}.install"):
            shutil.copy2(directory / filename, build / filename)
        # This is a QML/data packaging check, not an AUR dependency bootstrap.
        env = {**os.environ, "SRCDEST": str(sources), "PKGDEST": str(build), "BUILDDIR": str(build)}
        run("makepkg", "--nodeps", "--cleanbuild", "--noconfirm", cwd=build, env=env)
        archives = [Path(path) for path in run("makepkg", "--packagelist", cwd=build, env=env).splitlines()
                    if Path(path).is_file()]
        if not archives:
            raise ValueError(f"{name}: build produced no package archive")
        for archive in archives:
            with tarfile.open(archive) as package:
                names = package.getnames()
                if "etc/xdg/quickshell/atmosphera/shell.qml" not in names:
                    raise ValueError(f"{name}: shell missing from package")
                if any("/atmosphera/Scripts/dev/" in path or "/atmosphera/dev/" in path or
                       "/atmosphera/tmp/" in path for path in names):
                    raise ValueError(f"{name}: development files in package")
        print(f"{name}: build checked", flush=True)


def pending_push(directory):
    upstream = run("git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}", cwd=directory).strip()
    # Refuse a conflicting remote before pushing either repository.
    run("git", "merge-base", "--is-ancestor", upstream, "HEAD", cwd=directory)
    return run("git", "rev-parse", "HEAD", cwd=directory) != run("git", "rev-parse", upstream, cwd=directory)


def filenames(name):
    return ("PKGBUILD", ".SRCINFO", f"{name}.install")


def file_data(name, directory):
    result = {}
    for filename in filenames(name):
        # Never follow a recipe symlink while holding credentials.
        with os.fdopen(os.open(directory / filename, os.O_RDONLY | os.O_NOFOLLOW), "rb") as source:
            if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
                raise ValueError(f"{filename}: expected a regular recipe file")
            content = source.read(1024 * 1024 + 1)
        if len(content) > 1024 * 1024:
            raise ValueError(f"{filename}: recipe exceeds 1 MiB")
        result[filename] = base64.b64encode(content).decode("ascii")
    return result


def decoded_data(name, data):
    if not isinstance(data, dict) or set(data) != set(filenames(name)):
        raise ValueError("worker returned unexpected recipe files")
    result = {}
    for filename in filenames(name):
        if not isinstance(data[filename], str) or len(data[filename]) > 2 * 1024 * 1024:
            raise ValueError("invalid recipe data")
        result[filename] = base64.b64decode(data[filename], validate=True)
        if len(result[filename]) > 1024 * 1024:
            raise ValueError("recipe exceeds 1 MiB")
    return result


def write_data(name, directory, data):
    for filename, content in decoded_data(name, data).items():
        (directory / filename).write_bytes(content)


def protected_path(path, account):
    for item in (path, *path.parents):
        info = item.stat()
        if (info.st_mode & stat.S_IWOTH or
            (info.st_uid == account.pw_uid and info.st_mode & stat.S_IWUSR) or
            (info.st_gid == account.pw_gid and info.st_mode & stat.S_IWGRP)):
            raise ValueError(f"publisher path is writable by build account: {item}")


def build_account(args, destinations):
    if os.geteuid() != 0 or not args.build_user or not args.worker_root:
        raise ValueError("publication requires root, --build-user and --worker-root; recipes never run as the key holder")
    account = pwd.getpwnam(args.build_user)
    if account.pw_uid == 0:
        raise ValueError("build account must not be root")
    if not args.worker_root.is_dir() or args.worker_root.stat().st_uid != account.pw_uid:
        raise ValueError("worker root must be a disk-backed directory owned by the build account")
    protected_path(Path(__file__).resolve(), account)
    for _, directory in destinations:
        protected_path(directory, account)
        git = directory / ".git"
        if not git.is_dir() or directory.stat().st_uid != os.geteuid():
            raise ValueError("publication requires publisher-owned clones with private Git directories")
        for item in (git, *git.rglob("*")):
            if item.is_symlink():
                raise ValueError(f"unexpected Git metadata symlink: {item}")
            protected_path(item, account)
    if args.summary:
        protected_path(args.summary.parent.resolve(), account)
        if args.summary.is_symlink():
            raise ValueError("publisher summary must not be a symlink")
        if args.summary.exists():
            protected_path(args.summary, account)
    return account


def worker(action, name, data, args, account):
    # Code is maintained publisher policy, not a worker-selected script/path.
    program = f"__file__ = {str(Path(__file__).resolve())!r}\n" + Path(__file__).read_text()
    env = {"PATH": "/usr/bin:/bin", "HOME": account.pw_dir, "USER": account.pw_name,
           "LOGNAME": account.pw_name, "LANG": "C.UTF-8", "TMPDIR": str(args.worker_root),
           "SRCDEST": str(args.worker_root / "sources")}
    request = dict(action=action, name=name, files=data, version=args.tag[1:],
                   recipes=str(args.recipes), timeouts=TIMEOUTS)
    output = run("setpriv", "--reuid", str(account.pw_uid), "--regid", str(account.pw_gid),
                 "--clear-groups", "--no-new-privs", "--inh-caps=-all", "--ambient-caps=-all",
                 "--bounding-set=-all", sys.executable, "-I", "-c", program, "--worker",
                 cwd=Path("/"), env=env, input=json.dumps(request),
                 step=f"{name}: {action} worker",
                 tail_lines=16, tail_bytes=2048,
                 timeout=TIMEOUTS["build"] + 2 * TIMEOUTS["network"] + 10 * TIMEOUTS["local"])
    return json.loads(output)


def worker_main():
    if os.geteuid() == 0:
        raise ValueError("recipe worker must be unprivileged")
    request = json.load(sys.stdin)
    TIMEOUTS.update(request["timeouts"])
    if any(not math.isfinite(v) or v <= 0 for v in TIMEOUTS.values()):
        raise ValueError("worker timeouts must be finite positive seconds")
    name = request["name"]
    if name not in ("atmosphera", "atmosphera-git"):
        raise ValueError("unknown package")
    Path(os.environ["SRCDEST"]).mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="aur-worker-") as temporary:
        directory = Path(temporary) / name
        directory.mkdir()
        write_data(name, directory, request["files"])
        with contextlib.redirect_stdout(sys.stderr):
            if request["action"] == "prepare":
                run("git", "init", "-b", "master", cwd=directory)
                run("git", "add", ".", cwd=directory)
                run("git", "-c", "user.name=Recipe Snapshot", "-c", "user.email=snapshot@example.invalid",
                    "commit", "-m", "snapshot", cwd=directory)
                prepare(name, directory, request["version"], Path(request["recipes"]))
            elif request["action"] == "build":
                build_check(name, directory)
            else:
                raise ValueError("unknown worker action")
        result = file_data(name, directory) if request["action"] == "prepare" else {}
        print(json.dumps(result), flush=True)


def publish(args, destinations, states):
    states["atmosphera"][0] = "checking version"
    validate_version(args.tag[1:], destinations[0][1], args.push)
    changed = []
    prepared = {}
    for name, directory in destinations:
        states[name][0] = "preparing"
        if args.push:
            original = file_data(name, directory)
            prepared[name] = worker("prepare", name, original, args, args.account)
            # Credential-holder policy validates the data boundary too: a
            # recipe cannot use metadata output to bypass the version guard.
            candidate = prepared[name]
            content = decoded_data(name, candidate)
            if name == "atmosphera":
                recipe = content["PKGBUILD"].decode()
                if field(recipe, "pkgver") != args.tag[1:] or field(recipe, "pkgrel") != "1":
                    raise ValueError("worker changed requested stable counters")
                identity = stable_identity(content[".SRCINFO"].decode())
                if int(run("vercmp", identity, f"0:{args.tag[1:]}-1", cwd=directory).strip()) != 0:
                    raise ValueError("prepared stable identity differs from requested release")
            else:
                old = base64.b64decode(original["PKGBUILD"]).decode()
                new = content["PKGBUILD"].decode()
                expected_release = field(old, "pkgrel")
                if candidate != original:
                    expected_release = str(int(expected_release) + 1)
                if field(new, "pkgver") != field(old, "pkgver") or field(new, "pkgrel") != expected_release:
                    raise ValueError("worker changed publication-owned VCS counters")
            if prepared[name] != original:
                changed.append((name, directory))
            print(f"{name}: {'prepared' if prepared[name] != original else 'no change'}", flush=True)
        elif prepare(name, directory, args.tag[1:], args.recipes):
            changed.append((name, directory))
        states[name][0] = "prepared"
    if not args.push:
        print("Preparation only: no commits or pushes.")
        return
    # BOTH actual builds and BOTH local commits must succeed before any push.
    for name, directory in destinations:
        states[name][0] = "building"
        worker("build", name, prepared[name], args, args.account)
        print(f"{name}: build checked", flush=True)
        states[name][0] = "build checked"
    for name, directory in changed:
        write_data(name, directory, prepared[name])
        states[name][0] = "committing"
        run("git", "add", "PKGBUILD", ".SRCINFO", f"{name}.install", cwd=directory)
        run("git", "commit", "-m", f"chore(package): sync {name} for {args.tag}", cwd=directory)
        states[name][0] = "built and committed"
    pending = []
    for name, directory in destinations:
        if pending_push(directory):
            pending.append((name, directory))
        else:
            states[name][1] = "already current (no-op)"
    for name, directory in pending:
        states[name][1] = "push failed or interrupted; remote state unconfirmed"
        print(f"Publishing {name}...", flush=True)
        run("git", "push", "origin", "HEAD", cwd=directory, timeout=args.push_timeout)
        states[name][1] = "published"
        print(f"Published {name}.", flush=True)


def main():
    if sys.argv[1:] == ["--worker"]:
        worker_main()
        return
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", help="release tag, e.g. v0.9.0")
    parser.add_argument("stable", type=Path, help="clean stable AUR clone")
    parser.add_argument("git", type=Path, help="clean -git AUR clone")
    parser.add_argument("--push", action="store_true", help="commit and publish both prepared clones")
    parser.add_argument("--summary", type=Path, help="write per-repository progress even on failure")
    parser.add_argument("--recipes", type=Path, default=ROOT,
                        help="selected release recipes; publisher policy remains in this script")
    parser.add_argument("--build-user", help="keyless account used for all tag-derived commands")
    parser.add_argument("--worker-root", type=Path, help="disk-backed scratch owned by the keyless account")
    parser.add_argument("--known-hosts", type=Path, default=ROOT / "aur-known-hosts",
                        help="publisher SSH trust file, checked against maintained AUR pins before publication")
    parser.add_argument("--local-timeout", type=float, default=30)
    parser.add_argument("--network-timeout", type=float, default=180)
    parser.add_argument("--build-timeout", type=float, default=600)
    parser.add_argument("--push-timeout", type=float, default=180)
    args = parser.parse_args()
    args.recipes = args.recipes.resolve()
    if args.worker_root:
        args.worker_root = args.worker_root.resolve()
    for name in ("local", "network", "build", "push"):
        value = getattr(args, name + "_timeout")
        if not math.isfinite(value) or value <= 0:
            parser.error("timeouts must be finite positive seconds")
        if name != "push":
            TIMEOUTS[name] = value
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", args.tag):
        parser.error("expected a release tag vMAJOR.MINOR.PATCH")
    destinations = [("atmosphera", args.stable.resolve()),
                    ("atmosphera-git", args.git.resolve())]
    if destinations[0][1] == destinations[1][1]:
        parser.error("AUR clones must be different directories")
    states = {name: ["not started", "not attempted"] for name, _ in destinations}
    summary_safe = not args.push and os.geteuid() != 0
    failure = None
    try:
        if args.push:
            args.account = build_account(args, destinations)
            summary_safe = True
            verify_host_keys(args.known_hosts, args.account)
        elif os.geteuid() == 0:
            raise ValueError("recipe preparation must run as an unprivileged account")
        for name, directory in destinations:
            if run("git", "rev-parse", "--show-toplevel", cwd=directory).strip() != str(directory):
                raise ValueError(f"{name}: expected a repository root")
            if run("git", "status", "--porcelain", cwd=directory):
                raise ValueError(f"{name}: clone must be clean")
        if args.push:
            for name, directory in destinations:
                run("git", "fetch", "origin", cwd=directory)
        publish(args, destinations, states)
    except (OSError, ValueError, KeyError, CommandError) as error:
        failure = str(error)
        raise
    finally:
        summary = f"## AUR recipe sync — {args.tag}\n\n| Package | Local gate | Publication |\n|---|---|---|\n"
        summary += "".join(f"| {name} | {local} | {remote} |\n" for name, (local, remote) in states.items())
        if failure:
            summary += f"\nFailure:\n\n````text\n{failure}\n````\n"
        print(summary, flush=True)
        if args.summary and summary_safe:
            args.summary.write_text(summary)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, CommandError) as error:
        sys.exit(f"AUR sync FAILED: {error}. Check the log for any packages already published.")
