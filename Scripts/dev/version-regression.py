#!/usr/bin/env python3
"""Guest-only VERSION regression: actual QML service/consumers, private copies.

Run with --source TREE --output FRESH_DIRECTORY in the named Qt612 niri VM.
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

DOMAIN = "arch-niri-atmosphera-qt612-color"
ROOT = Path("/home/tester/Projects/qt612-atmocolor/version-identity")
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
    assert "52:54:00:4c:05:2c" in macs, (DOMAIN, macs)
    socks = glob.glob("/run/user/1000/niri.*.sock")
    assert len(socks) == 1 and Path("/run/user/1000/wayland-1").exists()
    env = dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000", WAYLAND_DISPLAY="wayland-1", NIRI_SOCKET=socks[0],
               ATMOSPHERA_CONFIG_DIR=str(case / "config") + "/", ATMOSPHERA_CACHE_DIR=str(case / "cache") + "/",
               ATMOSPHERA_SETTINGS_FILE=str(case / "config/settings.json"), ATMOSPHERA_DEBUG="0",
               TMPDIR="/home/tester/Projects/qt612-atmocolor/tmp", QT_FORCE_STDERR_LOGGING="1",
               ATMOSPHERA_UPGRADELOG_URL="http://127.0.0.1:9")
    return env


def copy_source(source, target):
    shutil.copytree(source, target, symlinks=True,
                    ignore=shutil.ignore_patterns(".git", ".qmlls.ini", "__pycache__"))


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
    (case / "probe.log").write_text(log)
    payloads = [json.loads(line.split("VERSION_PROBE|", 1)[1]) for line in log.splitlines() if "VERSION_PROBE|" in line]
    persisted = [json.loads(line.split("VERSION_PERSISTED|", 1)[1]) for line in log.splitlines() if "VERSION_PERSISTED|" in line]
    assert result.returncode == 0 and len(payloads) == 1 and len(persisted) == 1, log
    assert not ERRORS.search(log), log
    return payloads[0], persisted[0], log


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    source, output = Path(args.source).resolve(), Path(args.output).resolve()
    assert source.is_relative_to(ROOT) and output.is_relative_to(ROOT)
    assert not output.exists(), "Preserve earlier evidence; use a fresh output directory"
    # Identity checked before creating fixtures or running project workloads.
    guest_env(output)
    # Source identity is input, not a fixture to rewrite at each release.
    source_version_text = (source / "VERSION").read_text()
    assert re.fullmatch(r"\d+\.\d+\.\d+\n", source_version_text), source_version_text
    source_version = source_version_text.strip()
    major, minor, patch = map(int, source_version.split("."))
    source_requirements = [source_version, f"{major}.{minor}.{patch + 1}"]
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
    (distribution / "result.json").write_text(json.dumps(distribution_result, indent=2) + "\n")
    dist_failures = []
    if distribution_result["release_VERSION"] != source_version_text or not distribution_result["nix_VERSION_selected"]:
        dist_failures.append("source VERSION absent or changed in distribution inputs")
    results.append({"case": "distribution", "failures": dist_failures, "consumer": distribution_result})
    print(f"[{'FAIL' if dist_failures else 'PASS'}] distribution: {dist_failures}", flush=True)
    # None means preserve the supplied source VERSION. Deliberate build-format
    # and compatibility vectors stay pinned independently of the current release.
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
             ("legacy-unknown", "", None, False, None)]
    for name, version, expected, packaged, base in specs:
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
        settings = json.loads((shell / "Configs/defaults.json").read_text())
        settings["general"]["showChangelogOnStartup"] = False
        (case / "config/settings.json").write_text(json.dumps(settings))
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
                check(data["seen"] == "v" + base and persisted["lastSeenVersion"] == "v" + base, "stored last-seen identity")
                disk_seen = json.loads((case / "cache/shell-state.json").read_text())["changelogState"]["lastSeenVersion"]
                check(disk_seen == "v" + base, "persistent disk last-seen identity")
                check(data["manualTarget"] == "v" + base, "manual changelog target")
                check(not data["prompt"], "same-release changelog reopened")
                raw = re.sub(r"\x1b\[[0-9;]*m", "", log)
                urls = [line.split("Fetching upgrade log: ", 1)[1].strip() for line in raw.splitlines() if "Fetching upgrade log: " in line]
                check(urls == [env["ATMOSPHERA_UPGRADELOG_URL"] + "/v3.0.0/v" + base], "exact changelog URL")
                if name == "next-commit":
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
                cold = command(["dbus-run-session", "--", "qs", "-p", shell / "shell.qml"], env, 20)
                coldlog = cold.stdout + cold.stderr
                (case / "cold-load.log").write_text(coldlog)
                check(cold.returncode == 124 and not ERRORS.search(coldlog), "cold-load parser/import/runtime gate")
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
