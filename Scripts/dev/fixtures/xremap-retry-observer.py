"""Observe the real remapper after the existing save-failure Retry, before restore.

The matrix imports the unchanged deployment runner and attaches this observer;
the original causal schedule and assertions execute first.
"""
from pathlib import Path


def attach(module):
    original = module.Runner.save_failure

    def observed(runner):
        original(runner)
        result = module.run(["systemctl", "--user", "show", "xremap-atmosphera.service",
                             "-p", "MainPID", "-p", "ActiveState", "-p", "FragmentPath", "-p", "ExecStart"])
        runner.check(result.returncode == 0, "retry consumer unit observation failed")
        values = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
        pid = int(values.get("MainPID", "0"))
        runner.check(pid > 0 and values.get("ActiveState") == "active", "Retry did not leave the actual xremap consumer active")
        observation = {"unit": values, "pid": pid}
        if pid > 0:
            argv = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
            expected = Path.home() / ".config/xremap/atmosphera-xremap.yml"
            runner.check(str(expected).encode() in argv, "Retry remapper consumed a different settings path")
            runner.check(Path(values["FragmentPath"]).read_bytes() == (runner.source / "Scripts/systemd/xremap-atmosphera.service").read_bytes(), "Retry remapper unit differs from the candidate")
            observation.update(argv=[value.decode() for value in argv if value], configuration=str(expected), configuration_sha256=module.sha(expected))
        module.atomic_json(runner.case / "retry-consumer.json", observation)

    module.Runner.save_failure = observed
