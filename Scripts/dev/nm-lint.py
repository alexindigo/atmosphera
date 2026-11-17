#!/usr/bin/env python3
"""Guest-only NM lint with Quickshell-generated composite imports.

Uses the existing checker/metadata boundary unchanged. The disposable source
copy enables scanner tooling; it never starts the desktop shell.
"""
import argparse
import importlib.util
from pathlib import Path
import re
import shutil

from nm_test_support import GuestRun, SOURCE, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--guest-profile", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    owner = GuestRun(args.guest_profile, args.work)
    try:
        shell = owner.work / "source"
        shutil.copytree(SOURCE, shell, ignore=shutil.ignore_patterns(".git", ".envrc", ".qmlls.ini"))
        spec = importlib.util.spec_from_file_location("lint_ci", SOURCE / "Scripts/dev/qml-lint-ci.py")
        tooling = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(tooling)
        modules = tooling.qs_imports(shell.rglob("*.qml"))
        (shell / "LintImports.qml").write_text("import QtQuick\n" + "".join(
            f"import {module} as LintModule{i}\n" for i, module in enumerate(modules)) + "QtObject {}\n")
        probe = shell / "lint-tooling.qml"
        probe.write_text("import QtQuick\nimport Quickshell\nShellRoot { Timer { interval: 0; running: true; onTriggered: Qt.quit() } }\n")
        (shell / ".qmlls.ini").touch()
        env = dict(owner.env, QT_QPA_PLATFORM="offscreen")
        process = owner.launch(["qs", "-p", probe, "--no-color"], "tooling", env)
        owner.check("scanner-exit", process.wait(timeout=90) == 0)
        vfs = (shell / ".qmlls.ini").resolve(strict=True).parent
        owner.check("scanner-vfs-in-private-runtime", vfs.is_relative_to(owner.profile.runtime_base))
        for module in modules:
            assert vfs.joinpath(*module.split("."), "qmldir").is_file(), module
        env["QS_VFS"] = str(vfs)
        qml = [Path("Services/Networking"), *[p.relative_to(SOURCE) for p in sorted((SOURCE / "Scripts/dev/fixtures").glob("nm-*.qml"))]]
        result = run(["bash", shell / "Scripts/dev/qmllint.sh", *[shell / p for p in qml]], env=env, seconds=120, check=False)
        (owner.work / "qmllint.log").write_text(result.stdout + result.stderr)
        owner.check("project-qmllint", result.returncode == 0, exitCode=result.returncode)
        changed = {"NmState.qml", "NmDevice.qml", "NmProfile.qml", "NmActiveConnection.qml", "NmAccessPoint.qml", "NmIpConfig.qml",
                   "NetworkService.qml", "VPNService.qml", "nm-backend.qml", "nm-protocol.qml"}
        diagnostics = [line for line in (result.stdout + result.stderr).splitlines()
                       if re.search(r"\[(?:missing-property|unresolved-type|import)\]", line)
                       and any("/" + name + ":" in line for name in changed)]
        owner.check("changed-qml-types-and-properties-resolved", not diagnostics, diagnostics=diagnostics)
        print(result.stdout, end="")
    except BaseException as error:
        owner.receipt["error"] = repr(error)
        raise
    finally:
        owner.close()


if __name__ == "__main__":
    main()
