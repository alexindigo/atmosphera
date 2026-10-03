#!/usr/bin/env python3
"""Deterministic engine-selection and argument regressions for container-run.sh.

Uses mock `podman`/`docker` executables on a hermetic PATH. NEVER launches
containers — the mocks log their argv and emulate version/info/inspect/build/
run responses. Real-engine proof lives in integration.py.

Usage:
  engine-regression.py --source PATH --output DIR

Prints ENGINE_REGRESSION: PASS|FAIL|BLOCKED as the final line.
Exit 0 on PASS, 1 on FAIL, 2 on BLOCKED.
"""

import json
import os
import re
import shutil
import stat
import subprocess
import sys
from pathlib import Path

ESSENTIAL_TOOLS = [
    "bash", "dirname", "sha256sum", "cut", "id", "mkdir", "touch", "cat",
    "grep", "git", "chmod", "cp", "mv", "rm", "ln", "sort", "head", "tr",
]

MOCK_TEMPLATE = """#!/usr/bin/env bash
# Mock container engine for engine-regression tests. Logs every invocation,
# emulates version/info/inspect/build/run. Never executes a real engine.
set -u
: "${MOCK_LOG:?}" "${MOCK_STATE:?}"
{
  echo "== invocation =="
  echo "argv0=$0"
  i=0
  for a in "$@"; do printf 'arg[%s]=%s\\n' "$i" "$a"; i=$((i+1)); done
} >> "$MOCK_LOG"

cmd="${1:-}"
case "$cmd" in
  --version)
    case "@KIND@" in
      podman) echo "podman version ${MOCK_VERSION:-6.1.3}" ;;
      docker) echo "Docker version ${MOCK_VERSION:-28.3.3}, build deadbeef" ;;
      *) echo "${MOCK_VERSION_OUT:-mystery implementation 1.0}" ;;
    esac
    ;;
  info)
    if [ "${MOCK_INFO_RC:-0}" != "0" ]; then exit "$MOCK_INFO_RC"; fi
    if [ "${2:-}" = "--format" ]; then
      case "${3:-}" in
        *Rootless*) echo "${MOCK_ROOTLESS:-true}" ;;
        *SecurityOptions*) echo "${MOCK_SECURITY_OPTIONS:-[name=seccomp,profile=builtin]}" ;;
      esac
    fi
    ;;
  image)
    if [ "${2:-}" = "inspect" ]; then
      [ -f "$MOCK_STATE/built/${3##*/}" ]
      exit $?
    fi
    ;;
  build)
    prev=""
    for a in "$@"; do
      if [ "$prev" = "tag" ]; then
        mkdir -p "$MOCK_STATE/built"
        : > "$MOCK_STATE/built/${a##*/}"
      fi
      case "$a" in -t|--tag) prev="tag" ;; *) prev="" ;; esac
    done
    ;;
  run)
    exit "${MOCK_RUN_RC:-0}"
    ;;
esac
exit 0
"""

IMAGE_RE = re.compile(r"^localhost/atmosphera-dev:[0-9a-f]{16}$")

results = []  # (name, status, detail)


def record(name, status, detail=""):
    results.append((name, status, detail))
    print(f"[{status}] {name}" + (f" — {detail}" if detail else ""))


def write_mock(path, kind):
    path.write_text(MOCK_TEMPLATE.replace("@KIND@", kind))
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def make_essentials(dest):
    dest.mkdir(parents=True, exist_ok=True)
    for tool in ESSENTIAL_TOOLS:
        src = shutil.which(tool)
        if src:
            (dest / tool).symlink_to(src)


class Sandbox:
    """One hermetic case: mock bin dir, essentials dir, state, log."""

    def __init__(self, case_dir, engines):
        self.dir = case_dir
        if self.dir.exists():
            shutil.rmtree(self.dir)  # idempotent re-runs into the same output
        self.bin = case_dir / "bin"
        self.ess = case_dir / "ess"
        self.state = case_dir / "state"
        self.log = case_dir / "engine.log"
        self.bin.mkdir(parents=True)
        self.ess.mkdir()
        self.state.mkdir()
        make_essentials(self.ess)
        for name, kind in engines.items():
            write_mock(self.bin / name, kind)

    def env(self, override=None, extra=None):
        env = {
            "PATH": f"{self.bin}:{self.ess}",
            "MOCK_LOG": str(self.log),
            "MOCK_STATE": str(self.state),
            "HOME": str(self.dir),
        }
        if override is not None:
            env["ATMOSPHERA_CONTAINER_ENGINE"] = override
        if extra:
            env.update(extra)
        return env

    def invocations(self):
        """Parse the mock log into [{'argv0': str, 'args': [str]}]."""
        if not self.log.exists():
            return []
        out = []
        cur = None
        for line in self.log.read_text().splitlines():
            if line == "== invocation ==":
                cur = {"argv0": "", "args": []}
                out.append(cur)
            elif cur is not None and line.startswith("argv0="):
                cur["argv0"] = line[len("argv0="):]
            elif cur is not None and line.startswith("arg["):
                cur["args"].append(line.split("=", 1)[1])
        return out

    def run_invocations(self):
        return [i for i in self.invocations() if i["args"] and i["args"][0] == "run"]

    def build_invocations(self):
        return [i for i in self.invocations() if i["args"] and i["args"][0] == "build"]


def run_launcher(source, sandbox, args=(".devcontainer/precommit-check.sh", "a.qml"),
                 override=None, extra_env=None, launcher=None):
    exe = launcher or (Path(source) / ".devcontainer" / "container-run.sh")
    proc = subprocess.run(
        [str(exe), *args],
        env=sandbox.env(override=override, extra=extra_env),
        capture_output=True, text=True,
    )
    return proc


def copy_devcontainer(source, dest_root):
    dc = Path(source) / ".devcontainer"
    target = Path(dest_root) / ".devcontainer"
    shutil.copytree(dc, target)
    return target


def expect(name, cond, detail=""):
    record(name, "PASS" if cond else "FAIL", detail)
    return cond


# ---------------------------------------------------------------- cases


def case_override_precedence(source, out):
    sb = Sandbox(out / "override_precedence", {"podman": "podman", "docker": "docker"})
    p = run_launcher(source, sb, override="docker")
    ok = p.returncode == 0 and sb.run_invocations() and \
        all("docker" in i["argv0"] for i in sb.invocations())
    expect("override_precedence", bool(ok), p.stderr.strip().splitlines()[:1])


def case_override_invalid(source, out):
    sb = Sandbox(out / "override_invalid", {"podman": "podman"})
    p = run_launcher(source, sb, override="nerdctl")
    expect("override_invalid",
           p.returncode != 0 and "podman" in p.stderr and "docker" in p.stderr
           and not sb.invocations(),
           p.stderr.strip())


def case_override_missing_exe(source, out):
    sb = Sandbox(out / "override_missing_exe", {"docker": "docker"})
    p = run_launcher(source, sb, override="podman")
    expect("override_missing_exe",
           p.returncode != 0 and "not found" in p.stderr and not sb.invocations(),
           p.stderr.strip())


def case_auto_prefers_podman(source, out):
    sb = Sandbox(out / "auto_prefers_podman", {"podman": "podman", "docker": "docker"})
    p = run_launcher(source, sb)
    ok = p.returncode == 0 and sb.run_invocations() and \
        all("podman" in i["argv0"] for i in sb.invocations())
    expect("auto_prefers_podman", bool(ok))


def case_auto_docker_when_no_podman(source, out):
    sb = Sandbox(out / "auto_docker_when_no_podman", {"docker": "docker"})
    p = run_launcher(source, sb)
    ok = p.returncode == 0 and sb.run_invocations() and \
        all("docker" in i["argv0"] for i in sb.invocations())
    expect("auto_docker_when_no_podman", bool(ok))


def case_no_engines(source, out):
    sb = Sandbox(out / "no_engines", {})
    p = run_launcher(source, sb)
    expect("no_engines",
           p.returncode != 0 and "podman" in p.stderr and "docker" in p.stderr,
           p.stderr.strip())


def case_podman_masquerading_as_docker(source, out):
    sb = Sandbox(out / "podman_masquerading", {"docker": "podman"})
    p = run_launcher(source, sb, override="docker")
    runs = sb.run_invocations()
    has_keep_id = any("--userns=keep-id:uid=1000,gid=1000" in i["args"] for i in runs)
    expect("podman_masquerading_as_docker",
           p.returncode == 0 and has_keep_id
           and "backend=podman" in p.stderr and "docker" in p.stderr,
           p.stderr.strip())


def case_broken_preferred_no_retry(source, out):
    sb = Sandbox(out / "broken_preferred", {"podman": "podman", "docker": "docker"})
    p = run_launcher(source, sb, extra_env={"MOCK_INFO_RC": "1"})
    docker_used = any("docker" in i["argv0"] for i in sb.invocations())
    expect("broken_preferred_no_retry",
           p.returncode != 0 and not docker_used and "not usable" in p.stderr,
           p.stderr.strip())


def case_unsupported_implementation(source, out):
    sb = Sandbox(out / "unsupported_impl", {"podman": "weird"})
    p = run_launcher(source, sb)
    expect("unsupported_implementation",
           p.returncode != 0 and "unsupported engine implementation" in p.stderr,
           p.stderr.strip())


def case_podman_requires_rootless(source, out):
    sb = Sandbox(out / "podman_rootless_req", {"podman": "podman"})
    p = run_launcher(source, sb, extra_env={"MOCK_ROOTLESS": "false"})
    expect("podman_requires_rootless",
           p.returncode != 0 and "rootless" in p.stderr and not sb.run_invocations(),
           p.stderr.strip())


def case_docker_rootless_unsupported(source, out):
    sb = Sandbox(out / "docker_rootless", {"docker": "docker"})
    p = run_launcher(source, sb,
                     extra_env={"MOCK_SECURITY_OPTIONS": "[name=rootless]"})
    expect("docker_rootless_unsupported",
           p.returncode != 0 and "rootless Docker" in p.stderr
           and not sb.run_invocations(),
           p.stderr.strip())


def case_image_invalidation(source, out):
    case_dir = out / "image_invalidation"
    sb = Sandbox(case_dir, {"podman": "podman"})
    ws = case_dir / "ws"
    copy_devcontainer(source, ws)
    launcher = ws / ".devcontainer" / "container-run.sh"

    p1 = run_launcher(source, sb, launcher=launcher)
    builds1 = sb.build_invocations()
    tag1 = tag2 = tag3 = None
    if p1.returncode == 0 and builds1:
        tag1 = builds1[0]["args"][builds1[0]["args"].index("--tag") + 1]

    p2 = run_launcher(source, sb, launcher=launcher)
    builds2 = sb.build_invocations()

    # Change a fingerprint input -> new tag -> new build.
    atmo = ws / ".devcontainer" / "atmo-dev.sh"
    atmo.write_text(atmo.read_text() + "\n# fingerprint perturbation\n")
    p3 = run_launcher(source, sb, launcher=launcher)
    builds3 = sb.build_invocations()
    if len(builds3) > len(builds2):
        tag3 = builds3[-1]["args"][builds3[-1]["args"].index("--tag") + 1]
    if builds1:
        tag2 = builds1[0]["args"][builds1[0]["args"].index("--tag") + 1]

    ok = (p1.returncode == 0 and p2.returncode == 0 and p3.returncode == 0
          and len(builds1) == 1 and len(builds2) == 1  # second run: cache hit
          and len(builds3) == 2
          and tag1 and IMAGE_RE.match(tag1) and tag3 and tag3 != tag1
          and IMAGE_RE.match(tag3))
    expect("image_invalidation", ok,
           f"tag1={tag1} tag3={tag3} builds={len(builds3)}")


def case_spaces_in_workspace(source, out):
    case_dir = out / "spaces_in_workspace"
    sb = Sandbox(case_dir, {"podman": "podman"})
    ws = case_dir / "work space with blanks"
    copy_devcontainer(source, ws)
    p = run_launcher(source, sb, launcher=ws / ".devcontainer" / "container-run.sh")
    runs = sb.run_invocations()
    mount_ok = False
    if runs:
        args = runs[0]["args"]
        if "-v" in args:
            mount_ok = args[args.index("-v") + 1] == f"{ws}:/workspaces/atmosphera"
    expect("spaces_in_workspace", p.returncode == 0 and mount_ok,
           f"ws={ws}")


def case_spaces_in_qml_args(source, out):
    sb = Sandbox(out / "spaces_in_qml_args", {"podman": "podman"})
    weird = "Scripts/dev/format me.qml"
    p = run_launcher(source, sb, args=(".devcontainer/precommit-check.sh", weird))
    runs = sb.run_invocations()
    ok = p.returncode == 0 and runs and runs[0]["args"][-1] == weird
    expect("spaces_in_qml_args", ok)


def _expected_run_prefix(root, kind):
    common = [
        "--rm", "--cap-add", "SYS_ADMIN",
        "--tmpfs", "/tmp/overlay:size=256m,mode=1777",
        "--memory=12g", "--memory-swap=12g", "--pids-limit=2048", "--cpus=12",
        "-v", f"{root}:/workspaces/atmosphera",
        "-w", "/workspaces/atmosphera",
    ]
    if kind == "podman":
        return common + ["--userns=keep-id:uid=1000,gid=1000", "--user", "dev",
                         "--env", "ATMOSPHERA_DEV_USERXATTR=1"]
    return common + ["--user", "dev", "--env", "ATMOSPHERA_DEV_USERXATTR=0"]


def case_exact_run_args(source, out):
    for kind in ("podman", "docker"):
        sb = Sandbox(out / f"exact_run_args_{kind}", {kind: kind})
        cmd = (".devcontainer/precommit-check.sh", "a.qml", "b.qml")
        p = run_launcher(source, sb, args=cmd)
        runs = sb.run_invocations()
        ok = p.returncode == 0 and len(runs) == 1
        detail = ""
        if ok:
            args = runs[0]["args"]
            image_idx = next((i for i, a in enumerate(args)
                              if IMAGE_RE.match(a)), None)
            expected = ["run"] + _expected_run_prefix(Path(source).resolve(), kind)
            ok = image_idx is not None and args[1:image_idx] == expected[1:] \
                and args[image_idx + 1:] == list(cmd)
            detail = f"args={args}"
        expect(f"exact_run_args_{kind}", ok, detail[:400])


def case_engine_consistency(source, out):
    sb = Sandbox(out / "engine_consistency", {"podman": "podman", "docker": "docker"})
    p = run_launcher(source, sb, override="podman")
    inv = sb.invocations()
    argv0s = {i["argv0"] for i in inv}
    expect("engine_consistency",
           p.returncode == 0 and len(argv0s) == 1 and "podman" in argv0s.pop(),
           f"argv0s={sorted({i['argv0'] for i in inv})}")


def case_error_propagation(source, out):
    sb = Sandbox(out / "error_propagation", {"podman": "podman"})
    p = run_launcher(source, sb, extra_env={"MOCK_RUN_RC": "42"})
    expect("error_propagation", p.returncode == 42, f"rc={p.returncode}")


PROHIBITED = ("--privileged", ":U", "unconfined", "--security-opt")


def case_no_prohibited_flags(source, out):
    bad = []
    for kind in ("podman", "docker"):
        sb = Sandbox(out / f"prohibited_{kind}", {kind: kind})
        p = run_launcher(source, sb)
        if p.returncode != 0:
            bad.append(f"{kind}: rc={p.returncode}")
            continue
        for inv in sb.invocations():
            joined = "\n".join(inv["args"])
            for token in PROHIBITED:
                if token in joined:
                    bad.append(f"{kind}: found {token!r}")
            if inv["args"] and inv["args"][0] == "run":
                if "--user" not in inv["args"] or \
                        inv["args"][inv["args"].index("--user") + 1] != "dev":
                    bad.append(f"{kind}: missing named '--user dev'")
                if "--user" in inv["args"] and \
                        inv["args"][inv["args"].index("--user") + 1] in ("root", "0"):
                    bad.append(f"{kind}: root user")
    expect("no_prohibited_flags", not bad, "; ".join(bad))


def case_profile_parity(source, out):
    base = json.loads((Path(source) / ".devcontainer" / "devcontainer.json").read_text())
    pod = json.loads((Path(source) / ".devcontainer" / "podman" / "devcontainer.json").read_text())
    problems = []

    common_runargs = {"--cap-add=SYS_ADMIN", "--tmpfs=/tmp/overlay:size=256m,mode=1777",
                      "--memory=12g", "--memory-swap=12g", "--pids-limit=2048", "--cpus=12"}
    for label, cfg in (("docker", base), ("podman", pod)):
        ra = set(cfg.get("runArgs", []))
        missing = common_runargs - ra
        if missing:
            problems.append(f"{label}: missing runArgs {sorted(missing)}")
        for key in ("workspaceMount", "workspaceFolder", "containerUser", "remoteUser"):
            if key not in cfg:
                problems.append(f"{label}: missing {key}")
        if cfg.get("workspaceFolder") != "/workspaces/atmosphera":
            problems.append(f"{label}: workspaceFolder drift")
        if cfg.get("containerUser") != "dev" or cfg.get("remoteUser") != "dev":
            problems.append(f"{label}: user drift")

    if base.get("customizations") != pod.get("customizations"):
        problems.append("customizations drift")
    if "updateRemoteUserUID" in base:
        problems.append("docker profile must keep default remote-user UID updating")
    if pod.get("updateRemoteUserUID") is not False:
        problems.append("podman profile must set updateRemoteUserUID=false")
    if pod.get("containerEnv", {}).get("ATMOSPHERA_DEV_USERXATTR") != "1":
        problems.append("podman profile must set ATMOSPHERA_DEV_USERXATTR=1")
    if "ATMOSPHERA_DEV_USERXATTR" in base.get("containerEnv", {}):
        problems.append("docker profile must not set ATMOSPHERA_DEV_USERXATTR")
    pod_only = set(pod.get("runArgs", [])) - set(base.get("runArgs", []))
    if pod_only != {"--userns=keep-id:uid=1000,gid=1000"}:
        problems.append(f"podman-only runArgs drift: {sorted(pod_only)}")
    base_only = set(base.get("runArgs", [])) - set(pod.get("runArgs", []))
    if base_only:
        problems.append(f"docker-only runArgs drift: {sorted(base_only)}")

    expect("profile_parity", not problems, "; ".join(problems))


def _make_scratch_repo(path, source, hook_source):
    """Scratch git repo with the given pre-commit hook and a staged QML file."""
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True)
    subprocess.run(["git", "init", "-q"], cwd=path, check=True,
                   capture_output=True)
    (path / ".githooks").mkdir()
    shutil.copy(hook_source, path / ".githooks" / "pre-commit")
    (path / "a.qml").write_text("import QtQuick\n\nItem {}\n")
    subprocess.run(["git", "add", "a.qml"], cwd=path, check=True,
                   capture_output=True)


def case_baseline_hook_gap(source, out):
    case_dir = out / "baseline_hook_gap"
    baseline = Path(source).resolve().parent / "baseline"
    hook = baseline / ".githooks" / "pre-commit"
    if not hook.exists():
        record("baseline_hook_gap", "BLOCKED",
               f"no baseline tree at {baseline}")
        return

    # Baseline: only podman available -> old hook fails 'docker not found'.
    repo = case_dir / "repo-baseline"
    _make_scratch_repo(repo, source, hook)
    sb = Sandbox(case_dir / "sb-baseline", {"podman": "podman"})
    env = sb.env()
    p = subprocess.run([str(repo / ".githooks" / "pre-commit")],
                       cwd=repo, env=env, capture_output=True, text=True)
    baseline_ok = p.returncode == 1 and "docker not found" in p.stderr \
        and not sb.run_invocations()

    # Corrected: new hook selects podman through the launcher.
    repo2 = case_dir / "repo-new"
    _make_scratch_repo(repo2, source, Path(source) / ".githooks" / "pre-commit")
    shutil.copytree(Path(source) / ".devcontainer", repo2 / ".devcontainer")
    sb2 = Sandbox(case_dir / "sb-new", {"podman": "podman"})
    p2 = subprocess.run([str(repo2 / ".githooks" / "pre-commit")],
                        cwd=repo2, env=sb2.env(), capture_output=True, text=True)
    runs = sb2.run_invocations()
    new_ok = p2.returncode == 0 and runs and \
        ".devcontainer/precommit-check.sh" in runs[0]["args"] and \
        "a.qml" in runs[0]["args"]

    expect("baseline_hook_gap", baseline_ok and new_ok,
           f"baseline_rc={p.returncode} new_rc={p2.returncode} "
           f"baseline_err={p.stderr.strip()[:120]}")


CASES = [
    case_override_precedence,
    case_override_invalid,
    case_override_missing_exe,
    case_auto_prefers_podman,
    case_auto_docker_when_no_podman,
    case_no_engines,
    case_podman_masquerading_as_docker,
    case_broken_preferred_no_retry,
    case_unsupported_implementation,
    case_podman_requires_rootless,
    case_docker_rootless_unsupported,
    case_image_invalidation,
    case_spaces_in_workspace,
    case_spaces_in_qml_args,
    case_exact_run_args,
    case_engine_consistency,
    case_error_propagation,
    case_no_prohibited_flags,
    case_profile_parity,
    case_baseline_hook_gap,
]


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    source = Path(args.source).resolve()
    output = Path(args.output).resolve()
    if not (source / ".devcontainer" / "container-run.sh").exists():
        print(f"no container-run.sh under {source}", file=sys.stderr)
        sys.exit(2)
    output.mkdir(parents=True, exist_ok=True)
    cases_dir = output / "cases"
    cases_dir.mkdir(exist_ok=True)

    for case in CASES:
        try:
            case(source, cases_dir)
        except Exception as exc:  # a broken case is a FAIL, not a crash
            record(case.__name__.removeprefix("case_"), "FAIL", f"exception: {exc}")

    (output / "summary.txt").write_text(
        "\n".join(f"{s} {n} {d}" for n, s, d in results) + "\n")

    statuses = {s for _, s, _ in results}
    if "FAIL" in statuses:
        print("ENGINE_REGRESSION: FAIL")
        sys.exit(1)
    if "BLOCKED" in statuses:
        print("ENGINE_REGRESSION: BLOCKED")
        sys.exit(2)
    print("ENGINE_REGRESSION: PASS")


if __name__ == "__main__":
    main()
