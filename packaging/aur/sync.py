#!/usr/bin/env python3
"""Prepare standalone AUR recipes; commit/push only with explicit --push."""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parent


def run(*args, cwd, env=None):
    result = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE, env=env)
    if result.returncode:
        print(result.stdout, file=sys.stderr)
        result.check_returncode()
    return result.stdout


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
        sources = destination.parent / "sources"
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
    sources = directory.parent / "sources"
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


def publish(args, destinations, states):
    states["atmosphera"][0] = "checking version"
    validate_version(args.tag[1:], destinations[0][1], args.push)
    changed = []
    for name, directory in destinations:
        states[name][0] = "preparing"
        if prepare(name, directory, args.tag[1:], args.recipes):
            changed.append((name, directory))
        states[name][0] = "prepared"
    if not args.push:
        print("Preparation only: no commits or pushes.")
        return
    # BOTH actual builds and BOTH local commits must succeed before any push.
    for name, directory in destinations:
        states[name][0] = "building"
        build_check(name, directory)
        states[name][0] = "build checked"
    for name, directory in changed:
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
        run("git", "push", "origin", "HEAD", cwd=directory)
        states[name][1] = "published"
        print(f"Published {name}.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", help="release tag, e.g. v0.9.0")
    parser.add_argument("stable", type=Path, help="clean stable AUR clone")
    parser.add_argument("git", type=Path, help="clean -git AUR clone")
    parser.add_argument("--push", action="store_true", help="commit and publish both prepared clones")
    parser.add_argument("--summary", type=Path, help="write per-repository progress even on failure")
    parser.add_argument("--recipes", type=Path, default=ROOT,
                        help="selected release recipes; publisher policy remains in this script")
    args = parser.parse_args()
    args.recipes = args.recipes.resolve()
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", args.tag):
        parser.error("expected a release tag vMAJOR.MINOR.PATCH")
    destinations = [("atmosphera", args.stable.resolve()),
                    ("atmosphera-git", args.git.resolve())]
    if destinations[0][1] == destinations[1][1]:
        parser.error("AUR clones must be different directories")
    for name, directory in destinations:
        if run("git", "rev-parse", "--show-toplevel", cwd=directory).strip() != str(directory):
            raise ValueError(f"{name}: expected a repository root")
        if run("git", "status", "--porcelain", cwd=directory):
            raise ValueError(f"{name}: clone must be clean")
    states = {name: ["not started", "not attempted"] for name, _ in destinations}
    try:
        if args.push:
            for name, directory in destinations:
                run("git", "fetch", "origin", cwd=directory)
        publish(args, destinations, states)
    finally:
        summary = f"## AUR recipe sync — {args.tag}\n\n| Package | Local gate | Publication |\n|---|---|---|\n"
        summary += "".join(f"| {name} | {local} | {remote} |\n" for name, (local, remote) in states.items())
        print(summary, flush=True)
        if args.summary:
            args.summary.write_text(summary)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"AUR sync FAILED: {error}. Check the log for any packages already published.")
