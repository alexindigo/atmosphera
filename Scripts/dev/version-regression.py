#!/usr/bin/env python3
"""Guest-only VERSION regression: actual QML service/consumers, private copies.

Run with --source TREE --output FRESH_DIRECTORY in atmosphera-nm-events on ark.
The fixture comes from this runner's tree, allowing an unmodified baseline to
be tested. No installed shell or retained profile is relaunched or modified.
"""
import argparse
import glob
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import time

from qml_probe import inject_probe, probe_owner_path
from workspace_guard import require_disk_backed_paths

DOMAIN = "atmosphera-nm-events"
ROOT = Path("/home/tester/Projects/changelog")
FIXTURE = Path(__file__).with_name("fixtures") / "version-regression.qml"
ERRORS = re.compile(r"ReferenceError|TypeError|Cannot assign to non-existent property|Component is not ready|Failed to load configuration|module .* is not installed")


def command(argv, env=None, seconds=20):
    return subprocess.run(["timeout", "--kill-after=5s", str(seconds), *map(str, argv)],
                          env=env, capture_output=True, text=True, timeout=seconds + 10)


def checked(argv):
    result = command(argv)
    if result.returncode:
        raise RuntimeError(f"{argv}: {result.returncode}: {result.stderr}")
    return result.stdout.strip()


def guest_env(case):
    assert os.getuid() == 1000 and Path.home() == Path("/home/tester")
    macs = [p.read_text().strip().lower() for p in Path("/sys/class/net").glob("*/address")]
    assert "52:54:00:ac:67:e1" in macs, (DOMAIN, macs)
    assert checked(["sudo", "cat", "/sys/class/dmi/id/product_uuid"]) == "18da6e81-e4ac-4039-b497-45e813296ed8"
    socks = glob.glob("/run/user/1000/niri.*.sock")
    assert len(socks) == 1 and Path("/run/user/1000/wayland-1").exists()
    env = dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000", WAYLAND_DISPLAY="wayland-1", NIRI_SOCKET=socks[0],
               ATMOSPHERA_CONFIG_DIR=str(case / "config") + "/", ATMOSPHERA_CACHE_DIR=str(case / "cache") + "/",
               ATMOSPHERA_SETTINGS_FILE=str(case / "config/settings.json"), ATMOSPHERA_DEBUG="0",
               QT_FORCE_STDERR_LOGGING="1")
    return env


def copy_source(source, target):
    shutil.copytree(source, target, symlinks=True,
                    ignore=shutil.ignore_patterns(".git", ".envrc", ".qmlls.ini", "__pycache__"))


def bundled_notes(markdown, target):
    """Independent expected section boundaries for manual/history consumers."""
    sections = []
    for section in re.split(r"(?=^## \[)", markdown, flags=re.M):
        heading = re.match(r"## \[([\d.]+)\][^\n]*\n", section)
        if heading and tuple(map(int, heading[1].split("."))) <= tuple(map(int, target.split("."))):
            if section[heading.end():].strip():
                sections.append(section.strip())
    return "\n\n".join(sections)


def init_git(shell):
    checked(["git", "-C", shell, "init", "-q"])
    checked(["git", "-C", shell, "add", "."])
    commit(shell, "fixture")


def commit(shell, message):
    # Private guest fixture commits, never product history or persistent config.
    checked(["git", "-C", shell, "-c", "user.name=Version fixture", "-c", "user.email=fixture@example.invalid",
             "-c", "commit.gpgsign=false", "commit", "--allow-empty", "-qm", message])


def observe(case, shell, env):
    shutil.copyfile(FIXTURE, shell / "version-regression-probe.qml")
    result = command(["dbus-run-session", "--", "qs", "-p", shell / "version-regression-probe.qml"], env, 25)
    log = result.stdout + result.stderr
    (case / f"probe-{len(list(case.glob('probe-*.log'))) + 1}.log").write_text(log)
    payloads = [json.loads(line.split("VERSION_PROBE|", 1)[1]) for line in log.splitlines() if "VERSION_PROBE|" in line]
    persisted = [json.loads(line.split("VERSION_PERSISTED|", 1)[1]) for line in log.splitlines() if "VERSION_PERSISTED|" in line]
    assert result.returncode == 0 and len(payloads) == 1 and len(persisted) == 1, log
    assert not ERRORS.search(log), log
    return payloads[0], persisted[0], log


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--case", action="append", help="run only the named cases (plus distribution)")
    args = parser.parse_args()
    source, output = Path(args.source).resolve(), Path(args.output).resolve()
    assert source.is_relative_to(ROOT) and output.is_relative_to(ROOT)
    require_disk_backed_paths(source, output, os.environ.get("TMPDIR", ""))
    assert not output.exists(), "Preserve earlier evidence; use a fresh output directory"
    # Identity checked before creating fixtures or running project workloads.
    guest_env(output)
    # Source identity is input, not a fixture to rewrite at each release.
    source_version_text = (source / "VERSION").read_text()
    assert re.fullmatch(r"\d+\.\d+\.\d+\n", source_version_text), source_version_text
    source_version = source_version_text.strip()
    major, minor, patch = map(int, source_version.split("."))
    source_requirements = [source_version, f"{major}.{minor}.{patch + 1}"]
    # None preserves the supplied source VERSION; fixed vectors independently
    # exercise build formats and compatibility. This matrix also owns CLI names.
    specs = [("archive", None, source_version, True, source_version),
             ("checkout", None, None, False, source_version),
             ("next-commit", None, None, False, source_version),
             ("worktree", None, None, False, source_version),
             ("parent-repo", None, source_version, True, source_version),
             ("git-failure", None, source_version, False, source_version),
             ("release", "0.8.0", "0.8.0", True, "0.8.0"),
             ("package", "0.8.0.r12.gabc123456", "0.8.0.r12.gabc123456", True, "0.8.0"),
             ("package-checkout", "0.8.0.r12.gabc123456", "0.8.0.r12.gabc123456", False, "0.8.0"),
             ("pkgrel", "0.8.0.r12.gabc123456-2", "0.8.0.r12.gabc123456", True, "0.8.0"),
             ("hash", "0.8.0-gabc123456", "0.8.0-gabc123456", True, "0.8.0"),
             ("old-release", "0.7.2", "0.7.2", True, "0.7.2"),
             ("legacy-unknown", "", None, False, None),
             ("upgrade", "0.9.3", "0.9.3", True, "0.9.3"),
             ("missing-notes", "0.9.3", "0.9.3", True, "0.9.3"),
             ("empty-notes", "0.9.3", "0.9.3", True, "0.9.3"),
             ("empty-section", "0.9.3", "0.9.3", True, "0.9.3"),
             ("future-only", "0.9.3", "0.9.3", True, "0.9.3"),
             ("downgrade", "0.9.2", "0.9.2", True, "0.9.2"),
             ("disabled", "0.9.3", "0.9.3", True, "0.9.3")]
    unknown = set(args.case or []) - {spec[0] for spec in specs}
    if unknown:
        parser.error("unknown case name(s): " + ", ".join(sorted(unknown)))
    output.mkdir(parents=True)
    results = []
    # Run the actual release archive's rsync selection. Nix evidence is an
    # explicit source/filter trace, not a Nix evaluation or package build.
    distribution = output / "distribution"
    distribution.mkdir()
    workflow = (source / ".github/workflows/release.yml").read_text()
    rsync_block = re.search(r"rsync -av \\\n(.*?)\./ ../atmosphera-release/", workflow, re.S)
    assert rsync_block, "release copy-selection pattern changed; inspect its new contract"
    excludes = shlex.split(rsync_block[1].replace("\\\n", ""))
    release = distribution / "release"
    release.mkdir()
    checked(["rsync", "-a", *excludes, str(source) + "/", str(release) + "/"])
    nix = (source / "nix/package.nix").read_text()
    filter_list = re.search(r"builtins.any.*?\[([^]]*)\]", nix, re.S)
    assert filter_list and "src = ../.;" in nix and "cp -r . $out/share/atmosphera" in nix
    prefixes = re.findall(r"/[^\s]+", filter_list[1])
    distribution_result = {"release_rsync_excludes": excludes, "release_VERSION": (release / "VERSION").read_text() if (release / "VERSION").exists() else None,
                           "nix_filter_prefixes": prefixes, "nix_VERSION_selected": (source / "VERSION").exists() and not any("/VERSION".startswith(p) for p in prefixes),
                           "nix_evaluated": False, "nix_built": False}
    # Exercise the canonical AUR assembly, not a duplicate file-selection model.
    aur = distribution / "aur"
    checked(["bash", "-c", 'set -eu; source "$1/packaging/aur/package.sh"; srcdir="$2"; _gitname=release; pkgdir="$2/aur"; pkgver="$3"; package',
             "aur-assembly", source, distribution, source_version])
    notes = (source / "CHANGELOG.md").read_text()
    distribution_result.update(release_changelog=(release / "CHANGELOG.md").read_text() == notes,
                               aur_changelog=(aur / "etc/xdg/quickshell/atmosphera/CHANGELOG.md").read_text() == notes,
                               nix_changelog_selected=not any("/CHANGELOG.md".startswith(p) for p in prefixes))
    (distribution / "result.json").write_text(json.dumps(distribution_result, indent=2) + "\n")
    dist_failures = []
    if distribution_result["release_VERSION"] != source_version_text or not distribution_result["nix_VERSION_selected"]:
        dist_failures.append("source VERSION absent or changed in distribution inputs")
    if not all(distribution_result[key] for key in ("release_changelog", "aur_changelog", "nix_changelog_selected")):
        dist_failures.append("bundled CHANGELOG missing from distribution inputs")
    results.append({"case": "distribution", "failures": dist_failures, "consumer": distribution_result})
    print(f"[{'FAIL' if dist_failures else 'PASS'}] distribution: {dist_failures}", flush=True)
    for name, version, expected, packaged, base in specs:
        if args.case and name not in args.case:
            continue
        case = output / name
        case.mkdir()
        shell = case / "shell"
        copy_source(source, shell)
        if version is not None:
            if version:
                (shell / "VERSION").write_text(version + "\n")
            elif (shell / "VERSION").exists():
                (shell / "VERSION").unlink()
        for part in ("config", "cache"):
            (case / part).mkdir()
        (case / "cache/github.json").write_text(json.dumps({"timestamp": time.time(), "version": source_version, "contributors": []}))
        settings = json.loads((shell / "Configs/defaults.json").read_text())
        settings["general"]["showChangelogOnStartup"] = name != "disabled"
        settings["general"]["animationDisabled"] = True
        (case / "config/settings.json").write_text(json.dumps(settings))
        if name in ("upgrade", "downgrade"):
            (case / "cache/shell-state.json").write_text(json.dumps({"changelogState": {"lastSeenVersion": "v0.9.2" if name == "upgrade" else "v0.9.3"}}))
        if name == "missing-notes":
            (shell / "CHANGELOG.md").unlink()
        elif name == "empty-notes":
            (shell / "CHANGELOG.md").write_text("")
        elif name == "empty-section":
            (shell / "CHANGELOG.md").write_text("# Changelog\n\n## [0.9.3] - 2026-11-12\n\n")
        elif name == "future-only":
            (shell / "CHANGELOG.md").write_text("# Changelog\n\n## [0.9.4] - future\n\nNot this release.\n")
        env = guest_env(case)
        requirements = source_requirements if version is None else ["0.8.0", "0.8.1"]
        env["ATMOSPHERA_VERSION_PROBE_REQUIREMENTS"] = json.dumps(requirements)
        if name in ("checkout", "next-commit", "worktree", "git-failure", "package-checkout"):
            init_git(shell)
            if name == "next-commit":
                before, _, _ = observe(case, shell, env)
                (case / "before-commit.json").write_text(json.dumps(before, indent=2) + "\n")
                commit(shell, "next fixture commit")
            if name == "worktree":
                linked = case / "linked shell ' argv"
                checked(["git", "-C", shell, "worktree", "add", "--detach", linked, "HEAD"])
                shell = linked
            if name != "package-checkout":
                expected = source_version + "-g" + checked(["git", "-C", shell, "rev-parse", "--short=9", "HEAD"])
            if name == "git-failure":
                (case / "bin").mkdir()
                git = case / "bin/git"
                git.write_text("#!/bin/sh\nexit 1\n")
                git.chmod(0o755)
                env["PATH"] = str(case / "bin") + ":" + env["PATH"]
                expected = source_version
        if name == "parent-repo":
            init_git(case)
        failures = []
        data = persisted = None
        try:
            data, persisted, log = observe(case, shell, env)
            def check(ok, message):
                if not ok:
                    failures.append(message)
            known = name != "legacy-unknown"
            check(data["known"] == known, f"known={data['known']} expected {known}")
            if known:
                check(data["current"] == expected, f"identity={data['current']} expected {expected}")
                check(data["release"] == base, "authoritative release identity")
                check(data["packaged"] == packaged, "checkout/package provenance")
                check(data["parts"] == [int(v) for v in base.split(".")], "release parts include build tokens")
                has_notes = name not in ("missing-notes", "empty-notes", "empty-section", "future-only")
                if has_notes:
                    expected_seen = "v0.9.3" if name == "downgrade" else "v" + base
                    check(data.get("okClicked") and data.get("dialogRendered"), "real dialog rendered and OK clicked")
                    check(data["seen"] == expected_seen and persisted["lastSeenVersion"] == expected_seen, "OK stored last-seen identity")
                    disk_seen = json.loads((case / "cache/shell-state.json").read_text())["changelogState"]["lastSeenVersion"]
                    check(disk_seen == expected_seen, "OK persistent disk last-seen identity")
                    check(data["aboutRendered"] and data["aboutNotes"], "About renders bundled notes")
                    check(data["aboutNotes"] == bundled_notes(notes, base), "About shows exactly bundled history up to the current release")
                    if not data["prompt"]:
                        check(data["manualNotes"] == bundled_notes(notes, base), "manual dialog shows bundled history independent of provenance/setting")
                    restart, _, _ = observe(case, shell, env)
                    check(not restart["prompt"], "cold restart reopened acknowledged release")
                    check(restart["initialSeen"] == expected_seen, "cold restart loaded disk acknowledgment")
                    if name == "package":
                        (shell / "VERSION").write_text("0.8.0.r13.gdef123456\n")
                        next_build, _, _ = observe(case, shell, env)
                        check(next_build["current"] != data["current"] and next_build["release"] == data["release"] and not next_build["prompt"],
                              "new packaged-git commit within the same release prompted")
                else:
                    check(not data.get("okClicked") and not data["aboutNotes"], "missing/empty notes remain empty without acknowledgment")
                check(data["manualTarget"] == "v" + base, "manual changelog target")
                should_prompt = packaged and has_notes and name not in ("disabled", "downgrade")
                check(data["prompt"] == should_prompt, f"automatic eligibility expected {should_prompt}")
                check("Fetching upgrade log:" not in log, "remote upgrade-log path remains")
                if name == "upgrade":
                    expected_notes = notes[notes.index("## [0.9.3]"):notes.index("## [0.9.2]")].strip()
                    check(data["automaticNotes"] == expected_notes, "upgrade must show exactly the 0.9.3 section")
                if name == "next-commit":
                    check(not before["prompt"] and not data["prompt"], "same release new commit prompted")
                    check(before["current"] != data["current"], "another commit did not change display identity")
                    check(before["compatibility"] == data["compatibility"] and before["manualTarget"] == data["manualTarget"] and before["seen"] == data["seen"], "commit changed API/changelog identity")
            expected_compatibility = []
            for required in requirements:
                compatible = not known or tuple(map(int, base.split("."))) >= tuple(map(int, required.split(".")))
                expected_compatibility.append({"required": required, "result": {
                    "compatible": compatible, "track": "" if compatible else "atmosphera",
                    "requiredVersion": "" if compatible else required}})
            check(data["compatibility"] == expected_compatibility, f"exact consumer gate for {requirements}")
            check(("Shell version unknown" in log) == (not known), "unknown-version gate skip")
            for row in data["comparisons"]:
                check(row["equal"] == 0 and row["next"] == -1, f"build comparison {row}")
                if "gabc" in row["version"]:
                    check(row["git"] and row["hash"] == "abc123456", f"build helper {row}")
            check(data["major"] == [4] and data["minor"] == [4, 6], "major/minor input support")
            check(data["noctalia4"]["compatible"] and not data["noctalia5"]["compatible"], "Noctalia ceiling")
            if name == "archive":
                # A real cold shell/import graph with a self-terminating probe,
                # rather than calling a timeout exit successful startup.
                owner = probe_owner_path(shell)
                owner.write_text(inject_probe(owner.read_text(), 'Timer { interval: 8000; running: true; onTriggered: { console.log("VERSION_COLD_LOAD: PASS"); Qt.exit(0); } }'))
                cold = command(["dbus-run-session", "--", "qs", "-p", shell / "shell.qml"], env, 20)
                coldlog = cold.stdout + cold.stderr
                (case / "cold-load.log").write_text(coldlog)
                check(cold.returncode == 0 and "VERSION_COLD_LOAD: PASS" in coldlog and not ERRORS.search(coldlog), "cold-load parser/import/runtime gate")
                check(f"Detected installed version: {source_version} (git: false, packaged: true)" in coldlog, "cold-load VERSION-only detection")
        except Exception as error:
            failures.append(repr(error))
        result = {"case": name, "failures": failures, "consumer": data, "persisted": persisted, "expected": expected,
                  "release": base, "requirements": requirements, "source_version_preserved": version is None}
        (case / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        results.append(result)
        print(f"[{'FAIL' if failures else 'PASS'}] {name}: {failures}", flush=True)
    summary = {"source": str(source), "source_version": source_version, "cases": results,
               "failed": sum(bool(r["failures"]) for r in results), "at": time.time()}
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print("VERSION_REGRESSION: " + ("FAIL" if summary["failed"] else "PASS"), flush=True)
    return int(bool(summary["failed"]))


if __name__ == "__main__":
    raise SystemExit(main())
