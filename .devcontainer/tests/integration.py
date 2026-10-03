#!/usr/bin/env python3
"""Real-engine integration matrix for the Atmosphera dev container tooling.

Runs the actual selected engine (Podman or Docker) against disposable
standalone Git clones of the source tree. Never counts mocks as proof —
that is engine-regression.py's job. Fixture QML files are generated into
the disposable clones at runtime (a committed syntax-error fixture would
be uncommittable through the project's own hook).

Usage:
  integration.py --source PATH --engine podman|docker --case all --output DIR

Prints CONTAINER_INTEGRATION: PASS engine=<e>|FAIL|BLOCKED as the final line.
Exit 0 on PASS, 1 on FAIL, 2 on BLOCKED.

Expects the VM provisioning described in DEVELOPMENT.md / the plan:
  - the selected engine installed and usable by the invoking user
  - a second guest account `dev2` (non-1000 UID, sub-ID ranges, linger,
    docker group when testing docker) for the ownership legs
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

VALID_QML = """import QtQuick

Item {
        width: 100
        height: 50
}
"""

INVALID_QML = """import QtQuick

Item {
    width:
}
"""

# Sorts after valid.qml in `git diff --cached --name-only` order, so the
# staged-argument array is [valid.qml, zz-invalid.qml] (valid first).
INVALID_NAME = "zz-invalid.qml"

EXPECTED_MEMORY_MAX = "12884901888"  # 12 GiB
EXPECTED_SWAP_MAX = "0"
EXPECTED_PIDS_MAX = "2048"
EXPECTED_CPU_RATIO = 12

results = []


def record(name, status, detail=""):
    results.append((name, status, detail))
    print(f"[{status}] {name}" + (f" — {detail}" if detail else ""), flush=True)


def sh(args, env=None, cwd=None, input_bytes=None):
    return subprocess.run(args, env=env, cwd=cwd, input=input_bytes,
                          capture_output=True)


class Ctx:
    def __init__(self, source, engine, output):
        self.source = Path(source).resolve()
        self.engine = engine
        self.output = Path(output).resolve()
        self.output.mkdir(parents=True, exist_ok=True)
        self.work = Path(tempfile.mkdtemp(prefix="atmo-integration-",
                                          dir=self.output))
        self.invoker_uid = os.getuid()
        self.invoker_gid = os.getgid()
        self.container_ids = []
        self.versions = {}

    def engine_env(self, extra=None):
        env = dict(os.environ)
        env["ATMOSPHERA_CONTAINER_ENGINE"] = self.engine
        if extra:
            env.update(extra)
        return env

    def log_file(self, name, text):
        (self.output / name).write_text(text)


def apply_delta(source, dest):
    """Overlay the source's uncommitted delta (tracked diff + untracked
    files) onto the dest checkout."""
    diff = sh(["git", "-C", str(source), "diff", "HEAD", "--binary"]).stdout
    if diff.strip():
        patch = Path(dest) / ".delta.patch"
        patch.write_bytes(diff)
        p = sh(["git", "-C", str(dest), "apply", "--whitespace=nowarn",
                str(patch)])
        patch.unlink()
        if p.returncode != 0:
            raise RuntimeError(f"delta apply failed: {p.stderr.decode()}")
    untracked = sh(["git", "-C", str(source), "ls-files", "--others",
                    "--exclude-standard", "-z"]).stdout.decode()
    for rel in filter(None, untracked.split("\0")):
        src = Path(source) / rel
        dst = Path(dest) / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)


def materialize_clone(source, dest):
    """Standalone git clone + the source's uncommitted delta applied."""
    p = sh(["git", "clone", "--no-hardlinks", "-q", str(source), str(dest)])
    if p.returncode != 0:
        raise RuntimeError(f"clone failed: {p.stderr.decode()}")
    apply_delta(source, dest)


def write_fixtures(repo):
    fx = Path(repo) / ".devcontainer" / "tests" / "fixtures"
    fx.mkdir(parents=True, exist_ok=True)
    (fx / "valid.qml").write_text(VALID_QML)
    (fx / INVALID_NAME).write_text(INVALID_QML)


def reset_clone(ctx):
    """Clean fixture state between legs. `reset --hard` + `clean` return the
    clone to committed HEAD, which also removes the infra delta — so the
    delta from the source tree is re-applied afterwards."""
    repo = ctx.repo
    sh(["git", "-C", str(repo), "reset", "--hard", "-q", "HEAD"])
    sh(["git", "-C", str(repo), "clean", "-fdq"])
    apply_delta(ctx.source, repo)


# ------------------------------------------------------------------ legs


def leg_preflight(ctx):
    missing = []
    for tool in ("git", "devcontainer", ctx.engine):
        if not shutil.which(tool):
            missing.append(tool)
    if missing:
        record("preflight", "BLOCKED", f"missing tools: {missing}")
        return False

    ver = sh([ctx.engine, "--version"]).stdout.decode().strip()
    ctx.versions["engine"] = ver
    if ctx.engine == "podman" and not ver.startswith("podman version"):
        record("preflight", "FAIL", f"unexpected podman version output: {ver}")
        return False
    if ctx.engine == "docker" and not ver.startswith("Docker version"):
        record("preflight", "FAIL",
               f"docker must be real Docker, got: {ver}")
        return False

    info = sh([ctx.engine, "info"])
    if info.returncode != 0:
        record("preflight", "BLOCKED", f"{ctx.engine} info failed")
        return False
    ctx.log_file("engine-info.txt", info.stdout.decode(errors="replace"))

    ctx.versions["devcontainer"] = sh(
        ["devcontainer", "--version"]).stdout.decode().strip()
    ctx.versions["kernel"] = sh(["uname", "-r"]).stdout.decode().strip()
    ctx.versions["git"] = sh(["git", "--version"]).stdout.decode().strip()

    if ctx.engine == "podman":
        rootless = sh([ctx.engine, "info", "--format",
                       "{{.Host.Security.Rootless}}"]).stdout.decode().strip()
        if rootless != "true":
            record("preflight", "BLOCKED",
                   f"podman not rootless (rootless={rootless})")
            return False
        major_minor = ctx.versions["kernel"].split("-")[0].split(".")[:2]
        if tuple(map(int, major_minor)) < (6, 6):
            record("preflight", "BLOCKED",
                   f"kernel {ctx.versions['kernel']} < 6.6 (tmpfs userxattr)")
            return False
        driver = sh([ctx.engine, "info", "--format",
                     "{{.Store.GraphDriverName}}"]).stdout.decode().strip()
        ctx.versions["graphdriver"] = driver

    if not Path("/sys/fs/cgroup/cgroup.controllers").exists():
        record("preflight", "BLOCKED", "cgroup v2 not present")
        return False

    dev2 = sh(["id", "dev2"])
    if dev2.returncode != 0:
        record("preflight", "BLOCKED", "guest account dev2 not provisioned")
        return False
    ctx.versions["home_fs"] = sh(
        ["stat", "-f", "-c", "%T", str(Path.home())]).stdout.decode().strip()
    ctx.log_file("versions.txt",
                 "\n".join(f"{k}={v}" for k, v in ctx.versions.items()) + "\n")
    record("preflight", "PASS",
           f"{ver}; devcontainer {ctx.versions['devcontainer']}; "
           f"kernel {ctx.versions['kernel']}")
    return True


def leg_clone(ctx):
    ctx.repo = ctx.work / "repo"
    try:
        materialize_clone(ctx.source, ctx.repo)
    except RuntimeError as exc:
        record("clone", "FAIL", str(exc))
        return False
    head = sh(["git", "-C", str(ctx.repo), "rev-parse", "HEAD"]
              ).stdout.decode().strip()
    src_head = sh(["git", "-C", str(ctx.source), "rev-parse", "HEAD"]
                  ).stdout.decode().strip()
    launcher = ctx.repo / ".devcontainer" / "container-run.sh"
    ok = head == src_head and launcher.exists()
    record("clone", "PASS" if ok else "FAIL",
           f"clone at {ctx.repo} head={head[:12]}")
    return ok


def leg_identity(ctx, label, run_as=None):
    """dev identity, sudo, uid/gid maps, workspace-write ownership."""
    tag = f"{ctx.engine}-{label}"
    probe_name = f".integration-probe-{tag}"
    repo = ctx.repo if run_as is None else ctx.repo_dev2
    probe = (
        f"echo uid=$(id -u) gid=$(id -g) user=$(id -un); "
        f"sudo -n true && echo SUDO_OK; "
        f"echo '--uid_map--'; cat /proc/self/uid_map; "
        f"echo '--gid_map--'; cat /proc/self/gid_map; "
        f"touch /workspaces/atmosphera/{probe_name} && echo PROBE_OK"
    )
    launcher = str(repo / ".devcontainer" / "container-run.sh")
    cmd = [launcher, "bash", "-c", probe]
    if run_as is None:
        p = sh(cmd, env=ctx.engine_env(), cwd=repo)
    else:
        # cwd must be readable by the invoking user (the runner), not the
        # target account — /home/tester is not traversable by dev2. The
        # launcher derives its own repo root, so "/" is fine.
        p = sh(["sudo", "-n", "-u", run_as, "env",
                f"HOME=/home/{run_as}",
                f"XDG_RUNTIME_DIR=/run/user/{ctx.dev2_uid}",
                f"ATMOSPHERA_CONTAINER_ENGINE={ctx.engine}",
                *cmd], cwd="/")
    ctx.log_file(f"identity-{tag}.log",
                 p.stdout.decode() + "\n-- stderr --\n" + p.stderr.decode())
    out = p.stdout.decode()

    host_probe = repo / probe_name
    expected_host_uid = ctx.invoker_uid if run_as is None else ctx.dev2_uid
    expected_host_gid = ctx.invoker_gid if run_as is None else ctx.dev2_gid
    # Podman keep-id always targets the image's dev account (1000:1000);
    # Docker builds dev with the invoking user's IDs.
    expected_ct_uid = 1000 if ctx.engine == "podman" else expected_host_uid
    expected_ct_gid = 1000 if ctx.engine == "podman" else expected_host_gid
    if run_as is None:
        owner_ok = host_probe.exists() and host_probe.stat().st_uid == expected_host_uid
    else:
        # The dev2 clone lives under /home/dev2 (not traversable by the
        # runner) — verify ownership through sudo instead of a direct stat.
        st = sh(["sudo", "-n", "stat", "-c", "%u", str(host_probe)])
        owner_ok = (st.returncode == 0
                    and st.stdout.decode().strip() == str(expected_host_uid))
        sh(["sudo", "-n", "rm", "-f", str(host_probe)])

    ok = (p.returncode == 0 and "SUDO_OK" in out and "PROBE_OK" in out
          and f"uid={expected_ct_uid}" in out and f"gid={expected_ct_gid}" in out
          and "user=dev" in out and owner_ok)
    if ok and ctx.engine == "podman":
        # keep-id maps the invoking user to container UID 1000. In the
        # container's map this shows as "1000 0 1" (parent-NS id 0 is the
        # invoking user in podman's rootless parent mapping); the actual
        # host UID is proven by the file-ownership stat above.
        uid_map = out.split("--uid_map--")[1].split("--gid_map--")[0]
        ok = any(line.split()[:2] == ["1000", "0"]
                 for line in uid_map.strip().splitlines() if line.split())
        if not ok:
            record(f"identity-{tag}", "FAIL",
                   "no keep-id '1000 0 1' entry in uid_map")
            return False
    if host_probe.exists():
        host_probe.unlink()
    record(f"identity-{tag}", "PASS" if ok else "FAIL",
           f"container uid={expected_ct_uid}, host owner={expected_host_uid}")
    return ok


def leg_overlay_vfs(ctx):
    probe = (
        "set -e; "
        "mountpoint -q /home/dev/atmosphera-shell && echo OVERLAY_MOUNTED; "
        "grep ' /home/dev/atmosphera-shell overlay ' /proc/mounts; "
        "[ -n \"$QS_VFS\" ] && [ -d \"$QS_VFS\" ] && echo VFS_OK"
    )
    p = sh([str(ctx.repo / ".devcontainer" / "container-run.sh"),
            "atmo-dev", "bash", "-c", probe],
           env=ctx.engine_env(), cwd=ctx.repo)
    ctx.log_file(f"overlay-vfs-{ctx.engine}.log",
                 p.stdout.decode() + "\n-- stderr --\n" + p.stderr.decode())
    out = p.stdout.decode()
    mounts_line = next((l for l in out.splitlines()
                        if " /home/dev/atmosphera-shell overlay " in l), "")
    ok = (p.returncode == 0 and "OVERLAY_MOUNTED" in out and "VFS_OK" in out
          and mounts_line)
    if ok:
        if ctx.engine == "podman":
            ok = "userxattr" in mounts_line
        else:
            ok = "userxattr" not in mounts_line
    record("overlay_vfs", "PASS" if ok else "FAIL",
           mounts_line[:200] if mounts_line else "no overlay mount line")
    return bool(ok)


def leg_hook(ctx, name, files_to_stage, expect_rc0, expect_in_output=None,
             check_format_delta=False):
    reset_clone(ctx)
    write_fixtures(ctx.repo)
    git = ["git", "-C", str(ctx.repo)]
    for f in files_to_stage:
        sh(git + ["add", f])
    before = None
    target = ctx.repo / ".devcontainer" / "tests" / "fixtures" / "valid.qml"
    if check_format_delta:
        before = target.read_bytes()
    p = sh([str(ctx.repo / ".githooks" / "pre-commit")],
           env=ctx.engine_env(), cwd=ctx.repo)
    combined = p.stdout.decode() + p.stderr.decode()
    ctx.log_file(f"hook-{name}-{ctx.engine}.log", combined)
    ok = (p.returncode == 0) if expect_rc0 else (p.returncode != 0)
    detail = f"rc={p.returncode}"
    if ok and expect_in_output:
        ok = expect_in_output in combined
        detail += f" wanted {expect_in_output!r}"
    if ok and expect_rc0:
        # The clone deliberately carries the infra delta, so global status is
        # never empty. The hook contract is about the staged fixture: after
        # update-index --again it must show no unstaged delta (formatter
        # output re-staged) — e.g. exactly "A  <path>".
        rel = files_to_stage[0]
        status = sh(git + ["status", "--porcelain", "--", rel]
                    ).stdout.decode().strip()
        ok = status == f"A  {rel}"
        detail += f" fixture-status={status!r}"
    if ok and check_format_delta:
        after = target.read_bytes()
        ok = before != after and b"  width: 100" in after
        detail += " format-delta" if ok else " NO-DELTA"
        if ok:
            owner = target.stat().st_uid
            ok = owner == ctx.invoker_uid
            detail += f" owner={owner}"
    record(f"hook_{name}", "PASS" if ok else "FAIL", detail)
    return ok


def profile_config(ctx):
    if ctx.engine == "podman":
        return ctx.repo / ".devcontainer" / "podman" / "devcontainer.json"
    return ctx.repo / ".devcontainer" / "devcontainer.json"


def leg_profile(ctx):
    cfg = profile_config(ctx)
    repo = str(ctx.repo)
    common = ["--docker-path", ctx.engine, "--workspace-folder", repo,
              "--config", str(cfg)]
    build_cmd = ["devcontainer", "build"] + common
    up_cmd = ["devcontainer", "up"] + common
    if ctx.engine == "podman":
        build_cmd += ["--buildkit", "never"]
        up_cmd += ["--buildkit", "never",
                   "--include-configuration", "--include-merged-configuration"]

    p = sh(build_cmd)
    ctx.log_file(f"profile-build-{ctx.engine}.log",
                 p.stdout.decode() + p.stderr.decode())
    try:
        build_outcome = json.loads(p.stdout.decode()).get("outcome")
    except json.JSONDecodeError:
        build_outcome = None
    if p.returncode != 0 or build_outcome != "success":
        record("profile_build", "FAIL",
               f"build rc={p.returncode} outcome={build_outcome}")
        return False

    reset_clone(ctx)  # clean slate; hooks legs left fixtures staged
    write_fixtures(ctx.repo)  # exec leg needs fixtures/valid.qml present

    p = sh(up_cmd)
    ctx.log_file(f"profile-up-{ctx.engine}.log",
                 p.stdout.decode() + p.stderr.decode())
    try:
        up = json.loads(p.stdout.decode())
    except json.JSONDecodeError:
        record("profile_up", "FAIL", "up did not return JSON")
        return False
    if up.get("outcome") != "success":
        record("profile_up", "FAIL", f"outcome={up.get('outcome')}")
        return False
    cid = up.get("containerId", "")
    ctx.container_ids.append(cid)
    ok = (up.get("remoteWorkspaceFolder") == "/workspaces/atmosphera"
          and up.get("remoteUser") == "dev")
    record("profile_up", "PASS" if ok else "FAIL",
           f"ws={up.get('remoteWorkspaceFolder')} user={up.get('remoteUser')}")
    if not ok:
        return False

    # Effective container configuration (never trust configured flags).
    insp = sh([ctx.engine, "container", "inspect", cid])
    ctx.log_file(f"profile-inspect-{ctx.engine}.json", insp.stdout.decode())
    try:
        info = json.loads(insp.stdout.decode())[0]
    except (json.JSONDecodeError, IndexError):
        record("profile_inspect", "FAIL", "inspect not JSON")
        return False
    host = info.get("HostConfig", {})
    create_cmd = " ".join(info.get("Config", {}).get("CreateCommand", [])
                          if isinstance(info.get("Config", {}).get("CreateCommand"), list)
                          else [])
    problems = []
    if host.get("Privileged"):
        problems.append("privileged!")
    userns = str(host.get("UsernsMode", ""))
    if ctx.engine == "podman" and "keep-id" not in userns + create_cmd:
        problems.append(f"no keep-id (userns={userns!r})")
    for bad in (":U", "unconfined", "--privileged"):
        if bad in create_cmd:
            problems.append(f"prohibited {bad!r} in CreateCommand")
    ctx.log_file(f"profile-createcmd-{ctx.engine}.txt",
                 create_cmd + f"\nUsernsMode={userns}\n"
                 f"CapAdd={host.get('CapAdd')}\nUser={info.get('Config', {}).get('User')}\n")
    ok = not problems
    record("profile_inspect", "PASS" if ok else "FAIL", "; ".join(problems))
    return ok


def leg_profile_exec(ctx):
    cfg = profile_config(ctx)
    cmd = ["devcontainer", "exec", "--docker-path", ctx.engine,
           "--workspace-folder", str(ctx.repo), "--config", str(cfg),
           ".devcontainer/precommit-check.sh",
           ".devcontainer/tests/fixtures/valid.qml"]
    p = sh(cmd)
    combined = p.stdout.decode() + p.stderr.decode()
    ctx.log_file(f"profile-exec-{ctx.engine}.log", combined)
    ok = p.returncode == 0 and "qmllint: clean" in combined
    record("profile_exec", "PASS" if ok else "FAIL", f"rc={p.returncode}")
    return ok


def leg_cgroups(ctx):
    cfg = profile_config(ctx)
    code = ("from pathlib import Path; "
            "names=('memory.max','memory.swap.max','pids.max','cpu.max'); "
            "print('\\n'.join(n+'='+(Path('/sys/fs/cgroup')/n).read_text().strip() for n in names))")
    cmd = ["devcontainer", "exec", "--docker-path", ctx.engine,
           "--workspace-folder", str(ctx.repo), "--config", str(cfg),
           "python3", "-c", code]
    p = sh(cmd)
    out = p.stdout.decode()
    ctx.log_file(f"cgroups-{ctx.engine}.log", out + p.stderr.decode())
    values = {}
    for line in out.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            values[k.strip()] = v.strip()
    problems = []
    if values.get("memory.max") != EXPECTED_MEMORY_MAX:
        problems.append(f"memory.max={values.get('memory.max')}")
    if values.get("memory.swap.max") != EXPECTED_SWAP_MAX:
        problems.append(f"memory.swap.max={values.get('memory.swap.max')}")
    if values.get("pids.max") != EXPECTED_PIDS_MAX:
        problems.append(f"pids.max={values.get('pids.max')}")
    cpu = values.get("cpu.max", "").split()
    cpu_ok = False
    if len(cpu) == 2 and cpu[0] != "max":
        try:
            cpu_ok = int(cpu[0]) / int(cpu[1]) == EXPECTED_CPU_RATIO
        except (ValueError, ZeroDivisionError):
            cpu_ok = False
    if not cpu_ok:
        problems.append(f"cpu.max={values.get('cpu.max')}")
    # Record ancestor caps for the report (observed separately, per plan).
    # The v2 root has no such files; walk the container's own cgroup chain.
    chain_lines = []
    cid = ctx.container_ids[-1] if ctx.container_ids else ""
    cg_dir = None
    if cid:
        matches = [d for d in Path("/sys/fs/cgroup").rglob(f"*{cid[:12]}*")
                   if d.is_dir()]
        cg_dir = matches[0] if matches else None
    d = cg_dir
    while d is not None and d != d.parent:
        vals = {}
        for n in ("memory.max", "memory.swap.max", "pids.max", "cpu.max"):
            f = d / n
            if f.exists():
                try:
                    vals[n] = f.read_text().strip()
                except OSError:
                    pass
        if vals:
            chain_lines.append(f"{d}: " + " ".join(f"{k}={v}" for k, v in vals.items()))
        if d == Path("/sys/fs/cgroup"):
            break
        d = d.parent
    ctx.log_file(f"cgroups-ancestors-{ctx.engine}.txt",
                 "\n".join(chain_lines) or "no container cgroup path found")
    ok = not problems
    record("cgroups", "PASS" if ok else "FAIL", "; ".join(problems))
    return ok


def leg_cleanup(ctx):
    ok = True
    for cid in ctx.container_ids:
        p = sh([ctx.engine, "rm", "-f", cid])
        if p.returncode != 0:
            ok = False
    record("cleanup", "PASS" if ok else "FAIL",
           f"removed {len(ctx.container_ids)} container(s)")
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True)
    ap.add_argument("--engine", required=True, choices=("podman", "docker"))
    ap.add_argument("--case", default="all")
    ap.add_argument("--output", required=True)
    args = ap.parse_args()
    if args.case != "all":
        print(f"unknown case {args.case!r} (only 'all' implemented)",
              file=sys.stderr)
        sys.exit(2)

    ctx = Ctx(args.source, args.engine, args.output)

    dev2 = sh(["id", "-u", "dev2"])
    ctx.dev2_uid = int(dev2.stdout.decode().strip()) if dev2.returncode == 0 else None
    dev2g = sh(["id", "-g", "dev2"])
    ctx.dev2_gid = int(dev2g.stdout.decode().strip()) if dev2g.returncode == 0 else None

    if not leg_preflight(ctx):
        return finish(ctx)
    if not leg_clone(ctx):
        return finish(ctx)

    # Disposable clone owned by dev2 (standalone, real .git).
    if ctx.dev2_uid is not None:
        tmp = ctx.work / "repo-dev2-stage"
        try:
            materialize_clone(ctx.source, tmp)
            dest = Path(f"/home/dev2/repo-{ctx.engine}")
            sh(["sudo", "-n", "rm", "-rf", str(dest)])
            p = sh(["sudo", "-n", "cp", "-a", str(tmp), str(dest)])
            p2 = sh(["sudo", "-n", "chown", "-R",
                     f"dev2:dev2", str(dest)])
            if p.returncode != 0 or p2.returncode != 0:
                record("clone_dev2", "BLOCKED", "sudo copy to dev2 failed")
                return finish(ctx)
            ctx.repo_dev2 = dest
            record("clone_dev2", "PASS", str(dest))
        except RuntimeError as exc:
            record("clone_dev2", "FAIL", str(exc))
            return finish(ctx)

    ok = True

    def leg(fn, *a, **kw):
        nonlocal ok
        try:
            rc = bool(fn(ctx, *a, **kw))
        except Exception as exc:
            record(fn.__name__.removeprefix("leg_"), "FAIL",
                   f"exception: {exc}")
            rc = False
        ok &= rc
        return rc

    leg(leg_identity, "uid1000")
    if ctx.dev2_uid is not None:
        leg(leg_identity, "dev2", run_as="dev2")
    leg(leg_overlay_vfs)
    leg(leg_hook, "valid",
        [".devcontainer/tests/fixtures/valid.qml"],
        expect_rc0=True, check_format_delta=True)
    leg(leg_hook, "invalid_late",
        [".devcontainer/tests/fixtures/valid.qml",
         f".devcontainer/tests/fixtures/{INVALID_NAME}"],
        expect_rc0=False, expect_in_output=INVALID_NAME)
    leg(leg_hook, "invalid_first",
        [f".devcontainer/tests/fixtures/{INVALID_NAME}"],
        expect_rc0=False)
    if leg(leg_profile):
        leg(leg_profile_exec)
        leg(leg_cgroups)
    leg(leg_cleanup)
    return finish(ctx)


def finish(ctx):
    statuses = {s for _, s, _ in results}
    (ctx.output / "summary.txt").write_text(
        "\n".join(f"{s} {n} {d}" for n, s, d in results) + "\n")
    if "FAIL" in statuses:
        print(f"CONTAINER_INTEGRATION: FAIL engine={ctx.engine}")
        return 1
    if "BLOCKED" in statuses:
        print(f"CONTAINER_INTEGRATION: BLOCKED engine={ctx.engine}")
        return 2
    print(f"CONTAINER_INTEGRATION: PASS engine={ctx.engine}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
