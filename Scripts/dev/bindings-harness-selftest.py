#!/usr/bin/env python3
"""VM-only harness mechanics tests. Synthetic resources never claim product success."""
import argparse
from contextlib import redirect_stdout, redirect_stderr
import errno
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from types import SimpleNamespace


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    a = ap.parse_args()
    if os.getuid() != 1000 or Path.home() != Path("/home/tester") or "52:54:00:cd:ea:a0" not in {
            p.read_text().strip() for p in Path("/sys/class/net").glob("*/address")}:
        raise SystemExit("HARNESS_REPAIR: BLOCKED — owned VM required")
    if a.output.exists():
        raise SystemExit("HARNESS_REPAIR: BLOCKED — refusing existing output")
    if a.source.resolve() == a.output.resolve() or a.source.resolve() in a.output.resolve().parents:
        raise SystemExit("HARNESS_REPAIR: BLOCKED — output overlaps source")
    a.output.mkdir(parents=True)
    spec = importlib.util.spec_from_file_location("deployment_harness", a.source / "Scripts/dev/bindings-deployment-regression.py")
    h = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(h)
    results = []

    def test(name, body):
        root = a.output / name
        root.mkdir()
        log = io.StringIO()
        try:
            with redirect_stdout(log), redirect_stderr(log):
                body(root)
            result = {"id": name, "status": "PASS"}
        except Exception as error:
            result = {"id": name, "status": "FAIL", "error": repr(error)}
        (root / "observations.log").write_text(log.getvalue())
        h.atomic_json(root / "result.json", result)
        results.append(result)
        print(json.dumps(result), flush=True)

    def refused(call):
        try:
            call()
        except h.HarnessBlocked:
            return
        raise AssertionError("required refusal did not occur")

    def registry(root):
        all_cases = h.select_cases("all")
        assert len(all_cases) == len(h.CASE_REGISTRY)
        assert len({c["id"] for c in all_cases}) == len(all_cases)
        overlapping = h.select_cases("fifo,review-errors,fifo")
        assert len(overlapping) == len({c["id"] for c in overlapping})
        assert {c["id"] for c in h.select_cases("fifo")} <= {c["id"] for c in overlapping}
        assert {c["id"] for c in h.select_cases("review-errors")} <= {c["id"] for c in overlapping}
        for case in all_cases:
            assert {"id", "groups", "callable", "prerequisites", "input_needs", "coverage_status", "reason"} <= case.keys()
            if case["coverage_status"] == "RUNNABLE":
                assert callable(getattr(h.Runner, case["callable"]))
        resets = [c for c in all_cases if c["id"].startswith("generic-bindings-reset-")]
        assert len(resets) == 2 and all(c["coverage_status"] == "PENDING_USER_DECISION" and c["callable"] is None for c in resets)
        assert all("supersession" not in c["id"] for c in all_cases)
        h.atomic_json(root / "registry.json", all_cases)

    def discovery(root):
        old = h.Runner
        def forbidden(*args, **kwargs):
            raise AssertionError("discovery constructed a live Runner")
        h.Runner = forbidden
        try:
            output = io.StringIO()
            with redirect_stdout(output):
                assert h.main(["--list-cases"]) == 0
            data = json.loads(output.getvalue())
            assert len(data["cases"]) == len(h.CASE_REGISTRY)
            assert not list(root.iterdir()), "metadata discovery created artifacts"
        finally:
            h.Runner = old

    def aggregation(root):
        selected = h.select_cases("fifo-deployment,generic-bindings-reset-section")
        passing = [{"id": "fifo-deployment", "status": "PASS", "executed": True}]
        blocked = h.aggregate_results(selected, passing)
        assert blocked["exit_code"] == 2 and blocked["pending_ids"] == ["generic-bindings-reset-section"]
        assert blocked["counts"]["executed"] == 1 and blocked["counts"]["selected"] == 2
        failed = h.aggregate_results(selected, [{"id": "fifo-deployment", "status": "FAIL", "executed": True}])
        assert failed["exit_code"] == 1 and failed["status"] == "FAIL"
        partial = h.aggregate_results(selected[:1], passing)
        assert partial["exit_code"] == 0 and partial["status"] == "PASS"
        missing = h.aggregate_results(selected[:1], [])
        assert missing["exit_code"] == 2 and missing["not_run_ids"] == ["fifo-deployment"]
        full = h.aggregate_results(h.select_cases("all"), [
            {"id": c["id"], "status": "PASS", "executed": True}
            for c in h.select_cases("all") if c["coverage_status"] == "RUNNABLE"])
        assert full["exit_code"] == 2, "pending coverage became full matrix PASS"
        h.atomic_json(root / "aggregates.json", {"partial": partial, "full": full, "failed": failed})

    def copies(root):
        source = root / "source"
        (source / "nested/assets").mkdir(parents=True)
        (source / "nested/assets/asset").write_bytes(b"immutable-reference\n")
        (source / "entry.qml").write_text("// synthetic QML bytes, never launched\n")
        source.joinpath("linked").symlink_to("nested/assets/asset")
        w = h.Workspace(source, root / "journal", root / "work", live=False)
        _, _, first = w.case("first")
        assert (first / "nested/assets/asset").read_bytes() == b"immutable-reference\n"
        assert (first / "linked").is_symlink()
        assert (first / "nested/assets/asset").stat().st_ino != (source / "nested/assets/asset").stat().st_ino
        (first / "entry.qml").write_text("// mutate disposable copy only\n")
        assert source.joinpath("entry.qml").read_text() == "// synthetic QML bytes, never launched\n"
        w.case("second")
        refused(lambda: w.case("third"))
        assert first.exists() and not (root / "work/third").exists()
        refused(lambda: h.Workspace(source, root / "journal", root / "new-work", live=False))
        refused(lambda: h.Workspace(source, root / "new-output", root / "work", live=False))
        refused(lambda: h.Workspace(source, source / "nested-result", root / "other-work", live=False))
        root.joinpath("alias").symlink_to(source, target_is_directory=True)
        refused(lambda: h.Workspace(root / "alias", root / "other-output", root / "other-work", live=False))
        h.atomic_json(root / "storage.json", w.peak)

    def reserve(root):
        w = h.Workspace.__new__(h.Workspace)
        w.live, w.copies = True, []
        w.source = root
        w.output, w.work_root = root / "journal", root / "work"
        w.budget = {"copy_bytes": 64 * h.MIB, "entries": 7000}
        w.peak = {}
        state = {"bytes": 639 * h.MIB, "inodes": 100000}
        w.statvfs = lambda path: SimpleNamespace(f_bavail=state["bytes"], f_frsize=1, f_favail=state["inodes"])
        refused(lambda: w.preflight(initial=True))
        state.update(bytes=2048 * h.MIB, inodes=89999)
        refused(lambda: w.preflight(initial=True))
        state.update(inodes=100000)
        w.preflight(initial=True)
        w.statvfs = lambda path: SimpleNamespace(f_bavail=63 * h.MIB if str(path) == "/run/user/1000" else state["bytes"],
                                               f_frsize=1, f_favail=state["inodes"])
        refused(lambda: w.preflight(initial=True))
        w.statvfs = lambda path: SimpleNamespace(f_bavail=state["bytes"], f_frsize=1,
                                               f_favail=4999 if str(path) == "/run/user/1000" else state["inodes"])
        refused(lambda: w.preflight(initial=True))
        w.statvfs = lambda path: SimpleNamespace(f_bavail=state["bytes"], f_frsize=1, f_favail=state["inodes"])
        w.copies = [root / "retained-1", root / "retained-2"]
        for copy in w.copies:
            copy.mkdir()
            (copy / "preserved-synthetic-copy").write_bytes(b"retained")
        refused(w.preflight)

    def enospc(root):
        result = root / "result.json"
        original = b'{"historical":"must survive"}\n'
        result.write_bytes(original)
        summary = h.aggregate_results(h.select_cases("fifo-deployment"), [])
        def exhausted(path, data):
            raise OSError(errno.ENOSPC, "synthetic exhausted result storage")
        output = io.StringIO()
        with redirect_stdout(output), redirect_stderr(output):
            code = h.publish_summary(root, summary, writer=exhausted)
        assert code == 1 and "FAIL" in output.getvalue() and "retained_summary" in output.getvalue()
        assert result.read_bytes() == original, "failed result write truncated existing evidence"
        h.atomic_json(root / "atomic.json", {"status": "BLOCKED"})
        assert json.loads((root / "atomic.json").read_text())["status"] == "BLOCKED"
        (root / "ENOSPC-stdout-stderr.log").write_text(output.getvalue())

    def descendants(root):
        target, release = root / "config", root / "release"
        target.write_bytes(b"baseline")
        snap = h.FileSnapshot([target], root / "backup")
        lifecycle = h.OwnedLifecycle()
        child_code = "from pathlib import Path; import time; target=Path(" + repr(str(target)) + "); target.write_bytes(b'owned-live'); gate=Path(" + repr(str(release)) + ")\nwhile not gate.exists(): time.sleep(.01)\n"
        parent_code = "import subprocess,sys; p=subprocess.Popen([sys.executable,'-c'," + repr(child_code) + "],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); print(p.pid,flush=True); sys.stdin.read()"
        proc = subprocess.Popen([sys.executable, "-c", parent_code], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, start_new_session=True)
        try:
            lifecycle.track(proc)
            child_pid = int(proc.stdout.readline())
            deadline = time.monotonic() + 5
            while target.read_bytes() != b"owned-live" and time.monotonic() < deadline:
                time.sleep(.01)
            lifecycle.sample()
            proc.stdin.close()
            proc.wait(timeout=5)
            assert child_pid in lifecycle.owned, "writer descendant was not owned before parent exit"
            refused(lambda: snap.restore(lifecycle))
            assert target.read_bytes() == b"owned-live", "live-producer refusal still mutated configuration"
            assert any(r["pid"] == child_pid for r in lifecycle.sample()), "refusal was not against the live descendant"
            release.write_text("approved synthetic exit")
            deadline = time.monotonic() + 5
            while lifecycle.sample() and time.monotonic() < deadline:
                time.sleep(.02)
            restored = snap.restore(lifecycle)
            assert target.read_bytes() == b"baseline"
            h.atomic_json(root / "restoration.json", restored)
        finally:
            release.touch(exist_ok=True)
            if proc.poll() is None:
                proc.stdin.close()
                proc.wait(timeout=5)
            lifecycle.close()

    def links(root):
        referent, foreign, link, absent = (root / n for n in ("referent", "foreign", "link", "absent"))
        referent.write_bytes(b"original-referent")
        referent.chmod(0o640)
        foreign.write_bytes(b"foreign-must-survive")
        link.symlink_to("referent")
        snap = h.FileSnapshot([link, absent], root / "backup")
        referent.write_bytes(b"test-change")
        referent.chmod(0o600)
        link.unlink()
        link.symlink_to("foreign")
        absent.write_bytes(b"test-generated")
        lifecycle = h.OwnedLifecycle()
        try:
            restored = snap.restore(lifecycle)
            assert os.readlink(link) == "referent" and referent.read_bytes() == b"original-referent"
            assert referent.stat().st_mode & 0o777 == 0o640
            assert foreign.read_bytes() == b"foreign-must-survive" and not absent.exists()
            assert all(snap.matches(r) for r in snap.records)
            h.atomic_json(root / "restoration.json", restored)
        finally:
            lifecycle.close()

    def both_errors(root):
        calls = []
        class SyntheticRunner:
            failures = []
            bindings = SimpleNamespace(Blocked=h.HarnessBlocked)
            ctx = SimpleNamespace(restore_all=lambda: (_ for _ in ()).throw(RuntimeError("synthetic cleanup failure")))
            def fail(self):
                calls.append("case")
                self.failures.append("original failing oracle")
                raise RuntimeError("synthetic primary failure")
            def stop(self):
                calls.append("stop")
            def restore(self):
                calls.append("unsafe restore")
            def audit_case_end(self):
                pass
        selected = [h.case_record("first", ("synthetic",), "fail"), h.case_record("second", ("synthetic",), "fail")]
        summary = h.execute_selected(selected, SyntheticRunner(), root)
        assert summary["exit_code"] == 1
        first = summary["cases"][0]
        assert first["primary_errors"] and first["cleanup_errors"] and first["failures"]
        assert summary["not_run_ids"] == ["second"] and calls == ["case"], "teardown failure advanced/restored"
        assert json.loads((root / "progress.json").read_text())["status"] == "FAIL"

    def journal_quota(root):
        source = root / "source"
        source.mkdir()
        (source / "fixture").write_bytes(b"synthetic")
        workspace = h.Workspace(source, root / "journal", root / "work", live=False)
        protected = workspace.output / "protected.json"
        protected.write_bytes(b'{"original":true}\n')
        with (workspace.output / "quota-sparse-file").open("wb") as f:
            f.truncate(64 * h.MIB)
        before = protected.read_bytes()
        try:
            h.atomic_json(protected, {"replacement": True})
        except OSError as error:
            assert error.errno == errno.ENOSPC
        else:
            raise AssertionError("journal budget did not refuse additional atomic output")
        assert protected.read_bytes() == before

    def shared_cleanup(root):
        spec = importlib.util.spec_from_file_location("synthetic_consumer_cleanup", a.source / "Scripts/dev/bindings-regression.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.Ctx._discover_session = lambda self: {}  # No live desktop/session operation.
        ctx = module.Ctx(root, root)
        lifecycle = h.OwnedLifecycle()
        ctx.owned_register = lifecycle.track
        proc = subprocess.Popen([sys.executable, "-c", "import sys; sys.stdin.read()"], stdin=subprocess.PIPE,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        called = []
        try:
            ctx.add_process(proc)
            def failed():
                called.append("failed")
                raise RuntimeError("synthetic cleanup exception")
            def quiesce():
                called.append("quiesce")
                proc.stdin.close()
            ctx.add_restore(failed)
            ctx.add_restore(quiesce)
            try:
                ctx.restore_all()
            except module.Blocked:
                pass
            else:
                raise AssertionError("shared cleanup swallowed its error")
            assert called == ["quiesce", "failed"] and proc.poll() == 0
            assert ctx.failures and not lifecycle.sample()
            h.atomic_json(root / "observed.json", {"callbacks": called, "errors": ctx.failures})
        finally:
            if proc.poll() is None:
                proc.stdin.close()
                proc.wait(timeout=5)
            lifecycle.close()

    def settings_refusal(root):
        spec = importlib.util.spec_from_file_location("synthetic_settings_storage", a.source / "Scripts/dev/settings-regression.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        assert len(module.CASES) == 14 and "explicit-section-reset" in module.CASES
        source = root / "source"
        source.mkdir()
        (source / "fixture").write_bytes(b"synthetic complete-copy marker")
        workspace = module.HARNESS.Workspace(source, root / "journal", root / "work", live=False)
        lifecycle = module.HARNESS.OwnedLifecycle()
        # Storage-only receiver: never construct the live Settings/backup Runner.
        receiver = SimpleNamespace(workspace=workspace, journals={},
                                   backup=SimpleNamespace(lifecycle=lifecycle, case=None))
        try:
            directory = module.Runner.prepare_case_dir(receiver, "retained")
            marker = directory / "must-survive"
            marker.write_bytes(b"existing case data")
            try:
                module.Runner.prepare_case_dir(receiver, "retained")
            except module.HARNESS.HarnessBlocked:
                pass
            else:
                raise AssertionError("Settings runner replaced an existing case directory")
            assert marker.read_bytes() == b"existing case data"
            assert (directory / "shell/fixture").read_bytes() == b"synthetic complete-copy marker"
        finally:
            lifecycle.close()

    def timeout_term_only(root):
        # Executable name exercises the qs-client path; the executable is a
        # synthetic Python sleeper, never Quickshell or a desktop fixture.
        executable = root / "qs"
        marker = root / "TERM-observed"
        executable.write_text("#!" + sys.executable + "\nimport signal,sys,time\nfrom pathlib import Path\n"
            + "def terminated(signum, frame):\n    Path(" + repr(str(marker)) + ").write_text('TERM')\n    sys.exit(0)\n"
            + "signal.signal(signal.SIGTERM, terminated)\nprint('READY',flush=True)\ntime.sleep(30)\n")
        executable.chmod(0o700)
        try:
            h.run([str(executable)], timeout=.5)
        except subprocess.TimeoutExpired as error:
            assert "READY" in error.output
        else:
            raise AssertionError("timed-out client was reported successful")
        assert marker.read_text() == "TERM", "timeout used SIGKILL rather than approved TERM"

    def cross_run_copy_limit(root):
        source = root / "sources/candidate"
        source.mkdir(parents=True)
        (source / "fixture").write_text("synthetic complete-copy marker")
        work_base, journals = root / "scratch", root / "journals"
        work_base.mkdir()
        journals.mkdir()
        trees = []
        for name in ("tooling", "fifo"):
            w = h.Workspace(source, journals / name, work_base / name, live=False)
            _, _, tree = w.case(name)
            trees.append(tree)
            owner_file = w.output / "ownership.json"
            owner = json.loads(owner_file.read_text())
            owner["live"] = True  # Synthetic ledger; no native Runner/session operation.
            h.atomic_json(owner_file, owner)
        retained = h.retained_complete_copies(journals, source, work_base)
        assert set(retained) == set(trees) and len(retained) == 2
        h.atomic_json(root / "observed.json", {"retained_complete_copies": [str(p) for p in retained]})

    def json_types(root):
        for left, right in ((False, 0), (True, 1), ([False, 0], [0, False]),
                            ({"nested": [False, 0]}, {"nested": [0, False]}),
                            (None, ""), ({}, []), (0, "0")):
            assert not h.json_equal(left, right), (left, right)
        for value in (None, False, True, 0, "", {}, [], {"nested": [False, 0, None, ""]}):
            assert h.json_equal(value, json.loads(json.dumps(value)))
        assert h.json_equal(1, 1.0) and h.json_equal({"number": 0}, {"number": 0.0})

    def capture_identity(root):
        original = {"captureId": 2, "provenance": "ordinary", "section": "ui", "path": "/private/ui.json",
                    "base": {"exists": True, "identity": "inspected", "data": {"unknown": False}},
                    "json": '{"fontDefaultScale":1.7}', "foreignEpoch": 3, "coveredPaths": {"fontDefaultScale": 1}}
        assert h.json_equal(h.frozen_capture(original), h.frozen_capture(json.loads(json.dumps(original))))
        for key, wrong in (("captureId", 9), ("provenance", "bindings"), ("base", {}),
                           ("json", "{}"), ("foreignEpoch", 0), ("coveredPaths", {})):
            altered = dict(original, **{key: wrong})
            assert not h.json_equal(h.frozen_capture(original), h.frozen_capture(altered))

    def terminal_oracle(root):
        detail = {"requestId": "id", "attemptId": 1, "success": False, "error": "captured error"}
        signal = {"event": "handoff", "detail": dict(detail, selected="none")}
        callback = {"event": "callback", "detail": dict(detail, token="terminal-original", capturedEnvironment="none")}
        observers = [{"event": "startup-observer", "detail": dict(detail, token=token, capturedEnvironment="none")}
                     for token in ("startup-frozen", "startup-frozen-second")]
        stage = {"event": "stage", "detail": {"requestId": "id", "attemptId": 2, "stage": "startup"}}
        valid = [signal, callback, *observers, stage]
        assert not h.terminal_delivery_errors(valid, "id", "none", True)
        assert h.terminal_delivery_errors([signal, callback, stage, *observers], "id", "none", True)
        assert h.terminal_delivery_errors([*valid, observers[0]], "id", "none", True)
        altered = json.loads(json.dumps(valid)); altered[1]["detail"]["capturedEnvironment"] = "macos"
        assert h.terminal_delivery_errors(altered, "id", "none", True)
        altered = json.loads(json.dumps(valid)); altered[1]["detail"]["success"] = 0
        assert h.terminal_delivery_errors(altered, "id", "none", True)

    def retention_oracle(root):
        state = {"exists": True, "identity": "inspected", "sha256": "digest", "raw": '{"unknown":false}',
                 "raw_base64": "eyJ1bmtub3duIjpmYWxzZX0=", "valid": True, "data": {"unknown": False}}
        artifact = {"observed": state, "file_mode": 0o600, "directory_mode": 0o700}
        assert not h.retained_state_errors([state], [artifact])
        for key, wrong in (("identity", "other"), ("sha256", "bad"), ("raw", ""), ("raw_base64", ""),
                           ("exists", False), ("data", {"unknown": 0})):
            bad = dict(artifact, observed=dict(state, **{key: wrong}))
            assert h.retained_state_errors([state], [bad])
        assert h.retained_state_errors([state], [])
        assert h.retained_state_errors([state], [dict(artifact, file_mode=0o644)])

    for name, body in (("registry", registry), ("side-effect-free-discovery", discovery), ("aggregation", aggregation),
                       ("copies-refusal-complete-tree", copies), ("byte-inode-reserves", reserve),
                       ("ENOSPC-terminal-summary", enospc), ("orphan-writer-refusal", descendants),
                       ("link-referent-metadata", links), ("primary-and-cleanup-errors", both_errors),
                       ("reserved-journal-quota", journal_quota), ("shared-consumer-cleanup-errors", shared_cleanup),
                       ("settings-existing-case-refusal", settings_refusal), ("qs-client-timeout-TERM-only", timeout_term_only),
                       ("cross-run-complete-copy-ledger", cross_run_copy_limit),
                       ("corrective-json-type-equality", json_types), ("corrective-capture-tuple", capture_identity),
                       ("corrective-terminal-delivery", terminal_oracle), ("corrective-complete-retention", retention_oracle)):
        test(name, body)
    failures = [r for r in results if r["status"] == "FAIL"]
    summary = {"status": "FAIL" if failures else "PASS", "cases": results,
               "scope": "isolated harness mechanics only; no application functionality proof", "source": str(a.source)}
    h.atomic_json(a.output / "result.json", summary)
    print("HARNESS_REPAIR: " + summary["status"], flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
