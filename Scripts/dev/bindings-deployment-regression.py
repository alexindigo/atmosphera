#!/usr/bin/env python3
"""Actual UI/deployment/activation regression; run only on an owned niri VM.

Physical QMP injection is supplied through the existing AWAITING/GO protocol.
The runner never manually installs a layer to make first deployment green.
Real guest files/services are backed up and restored, including managed keyd.
"""
import argparse
import hashlib
import importlib.util
import json
import os
import shlex
import signal
import stat
import sys
from pathlib import Path
import shutil
import subprocess
import time
import uuid
import threading
import difflib
import base64
from collections import Counter
import socket
import select
import tarfile
from guest_profile import (ProfileBlocked as HarnessBlocked, activate_profile,
                           current_profile, profile_argument, protect_owned_process)
from native_settings_controls import prepare as prepare_native_controls

HERE = Path(__file__).resolve().parent
FILES = [".config/niri/config.kdl", ".config/niri/atmosphera.kdl",
         ".config/niri/atmosphera-i18n.kdl", ".config/niri/atmosphera-session.kdl",
         ".config/niri/atmosphera-shortcuts-macos.kdl",
         ".config/xremap/atmosphera-xremap.yml", ".config/zed/keymap.json",
          ".config/zed/keymap.json.pre-atmosphera", "/etc/keyd/atmosphera"]

MIB = 1024 * 1024
RESET_CHECKPOINT = "bindings-fifo-recovery-continuation/reset-semantics-checkpoint-20261004.md"


def case_record(identity, groups, method=None, args=(), needs=(), status="RUNNABLE", reason=""):
    return {"id": identity, "groups": list(groups), "callable": method, "args": list(args),
            "prerequisites": ["identity-profile-VM", "scoped-live-permission", *needs],
            "input_needs": "physical-QMP" if "physical-input" in needs else "none",
            "coverage_status": status, "reason": reason}


# Discovery is data only: no Runner, desktop/service queries or case invocation.
CASE_REGISTRY = (
    case_record("fifo-deployment", ("fifo",), "fifo", needs=("current-FIFO-API",)),
    case_record("fifo-generation", ("fifo",), "fifo", (True,), ("current-FIFO-API",)),
    case_record("failure-retention", ("fifo", "review-errors"), "failure_retention"),
    case_record("settings-transitions", ("settings",), "settings", (False,), ("physical-input",)),
    case_record("settings-consumers", ("settings", "consumers"), "settings", needs=("physical-input", "xremap", "visual-review")),
    case_record("wizard-finish", ("wizard",), "wizard", (False,), ("physical-input",)),
    case_record("wizard-consumers", ("wizard", "consumers"), "wizard", (True,), ("physical-input", "xremap", "visual-review")),
    case_record("save-failure", ("review-errors",), "save_failure"),
    case_record("wizard-failure-retry", ("wizard", "review-errors"), "wizard_failure", needs=("physical-input",)),
    case_record("pending-edits", ("persistence",), "pending_edits"),
    case_record("queued-save-failure", ("persistence", "review-errors"), "queued_save_failure"),
    case_record("prepare-failure", ("review-errors",), "io_failure", ("prepare",)),
    case_record("promote-failure", ("review-errors",), "io_failure", ("promote",)),
    case_record("external-publication-conflict", ("persistence", "review-errors"), "conflict"),
    case_record("callback-lifecycle-huge-stdin", ("review-errors",), "callback_lifecycle"),
    case_record("startup-held", ("review-errors",), "startup_gate"),
    case_record("child-failed-to-start", ("review-errors",), "child_fault", ("missing",)),
    case_record("child-crash", ("review-errors",), "child_fault", ("crash",)),
    case_record("generation-failure", ("review-errors",), "generation_fault"),
    case_record("null-typed-handoff", ("review-errors",), "null_handoff"),
    case_record("later-reload-diagnostic", ("review-errors",), "later_reload_diagnostic"),
    case_record("teardown-refusal", ("review-errors",), "teardown_guard"),
    case_record("generic-bindings-reset-section", ("reset",), status="PENDING_USER_DECISION", reason=RESET_CHECKPOINT),
    case_record("generic-bindings-reset-value", ("reset",), status="PENDING_USER_DECISION", reason=RESET_CHECKPOINT),
    case_record("wizard-local-reset-skip-unload", ("wizard",), "wizard_local_lifecycle", needs=("physical-input",)),
    case_record("external-echo-legacy-transitions", ("persistence", "fifo"), "external_transitions"),
    case_record("reconnect-no-replay", ("fifo", "review-errors"), "reconnect_no_replay"),
    case_record("effective-runtime-consumers-failed-save", ("consumers",), "runtime_consumers_failed_save"),
    case_record("xremap-default-XDG-consumer", ("consumers", "xdg"), "xdg_default_consumer"),
    case_record("xremap-custom-XDG-consumer", ("consumers", "xdg"), status="PENDING_LIVE_PREREQUISITE",
                reason="Requires the separately approved private UID0 manager/native-socket procedure (custom-xdg-native-socket-addendum-20261005.md). That procedure has retained native custom-path consumption and independent teardown evidence; its completed/stopped context is not a fresh execution of later selected runs. Existing protected desktop manager is default-XDG; client/set-environment changes alone are not equivalent."),
    case_record("symlink-referent-restoration", ("restoration",), "linked_live_paths"),
    case_record("persistence-audit-capture-held-write", ("persistence-audit",), "capture_operation"),
    case_record("persistence-audit-capture-ABA", ("persistence-audit",), "capture_operation", (True,)),
    case_record("persistence-audit-mixed-section-restart", ("persistence-audit",), "mixed_snapshot"),
    case_record("persistence-audit-mixed-legacy-restart", ("persistence-audit",), "mixed_snapshot", (True,)),
    case_record("persistence-audit-failed-ordinary-intent", ("persistence-audit",), "failed_ordinary"),
    case_record("persistence-audit-failed-ordinary-new-edit", ("persistence-audit",), "failed_ordinary", (True,)),
    case_record("persistence-audit-reversed-inspectors", ("persistence-audit",), "read_ownership"),
    case_record("persistence-audit-read-callback-owner", ("persistence-audit",), "read_ownership", (True,)),
    case_record("persistence-audit-missing-inspection", ("persistence-audit",), "missing_acceptance"),
    case_record("persistence-audit-managed-effective-reentry", ("persistence-audit",), "notification_reentry"),
    case_record("persistence-audit-accepted-choice-reentry", ("persistence-audit",), "notification_reentry", (True,)),
    case_record("persistence-audit-acceptance-reasons", ("persistence-audit",), "acceptance_reasons"),
    case_record("persistence-audit-promotion-success-conflicts", ("persistence-audit",), "promotion_conflicts"),
    case_record("persistence-audit-promotion-error-conflicts", ("persistence-audit",), "promotion_conflicts", (True,)),
    case_record("persistence-audit-retention-failure", ("persistence-audit",), "promotion_conflicts", (False, True)),
    case_record("persistence-audit-setup-failed-bundle", ("persistence-audit", "wizard"), "setup_failed_bundle"),
    case_record("persistence-audit-setup-prior-failed-captures", ("persistence-audit", "wizard"), "setup_failed_bundle", (True,)),
    case_record("persistence-audit-terminal-signal-reentry", ("persistence-audit",), "terminal_reentry"),
    case_record("persistence-audit-terminal-status-reentry", ("persistence-audit",), "terminal_reentry", (True,)),
    case_record("persistence-audit-terminal-startup-observers", ("persistence-audit",), "terminal_reentry", (False, True)),
    case_record("persistence-audit-corrective-external-section-debounce-reentry", ("persistence-audit-corrective",), "corrective_listener"),
    case_record("persistence-audit-corrective-external-legacy-debounce-reentry", ("persistence-audit-corrective",), "corrective_listener", ("debounce", True)),
    case_record("persistence-audit-corrective-external-section-save-reentry", ("persistence-audit-corrective",), "corrective_listener", ("save",)),
    case_record("persistence-audit-corrective-external-record-inplace-reentry", ("persistence-audit-corrective",), "corrective_listener", ("record",)),
    case_record("persistence-audit-corrective-section-pending-parent-add", ("persistence-audit-corrective",), "corrective_pending_parent"),
    case_record("persistence-audit-corrective-initial-accepted-tree-ownership", ("persistence-audit-corrective",), "corrective_initial_ownership"),
    case_record("persistence-audit-corrective-section-pending-parent-remove", ("persistence-audit-corrective",), "corrective_pending_parent", (False, True)),
    case_record("persistence-audit-corrective-legacy-pending-parent-add", ("persistence-audit-corrective",), "corrective_pending_parent", (True,)),
    case_record("persistence-audit-corrective-legacy-pending-parent-remove", ("persistence-audit-corrective",), "corrective_pending_parent", (True, True)),
    case_record("persistence-audit-corrective-own-missing-recreate-delete", ("persistence-audit-corrective",), "corrective_missing_lifetime"),
    case_record("persistence-audit-corrective-legacy-section-add", ("persistence-audit-corrective",), "corrective_ordinary_layers", ("legacy-add",)),
    case_record("persistence-audit-corrective-legacy-section-remove", ("persistence-audit-corrective",), "corrective_ordinary_layers", ("legacy-remove",)),
    case_record("persistence-audit-corrective-ordinary-leaf-remove-fallback", ("persistence-audit-corrective",), "corrective_ordinary_layers", ("leaf-remove",)),
    case_record("persistence-audit-corrective-ordinary-file-delete-fallback", ("persistence-audit-corrective",), "corrective_ordinary_layers", ("file-delete",)),
    case_record("persistence-audit-corrective-forward-inspectors", ("persistence-audit-corrective",), "corrective_forward_reads"),
    case_record("persistence-audit-corrective-readback-foreign-retention", ("persistence-audit-corrective",), "corrective_readback", ("foreign",)),
    case_record("persistence-audit-corrective-readback-identity-retention", ("persistence-audit-corrective",), "corrective_readback", ("identity",)),
    case_record("persistence-audit-corrective-readback-missing-retention", ("persistence-audit-corrective",), "corrective_readback", ("missing",)),
    case_record("persistence-audit-corrective-readback-postjoin-state", ("persistence-audit-corrective",), "corrective_readback_postjoin"),
    case_record("persistence-audit-corrective-retention-arrival-success", ("persistence-audit-corrective",), "corrective_retention_arrival"),
    case_record("persistence-audit-corrective-retention-arrival-error", ("persistence-audit-corrective",), "corrective_retention_arrival", (True,)),
    case_record("persistence-audit-corrective-helper-preimage-retention-failure", ("persistence-audit-corrective",), "corrective_helper_failure", ("preimage",)),
    case_record("persistence-audit-corrective-helper-invalid-retention-failure", ("persistence-audit-corrective",), "corrective_helper_failure", ("invalid",)),
    case_record("persistence-audit-corrective-helper-readback-retention-failure", ("persistence-audit-corrective",), "corrective_helper_failure", ("readback",)),
    case_record("persistence-audit-corrective-publication-error-own-output", ("persistence-audit-corrective",), "corrective_helper_failure", ("publication",)),
    case_record("persistence-audit-corrective-setup-older-failure-newer-success", ("persistence-audit-corrective", "wizard"), "corrective_setup_suffix"),
)


def select_cases(selection, registry=CASE_REGISTRY):
    ids = [c["id"] for c in registry]
    if len(ids) != len(set(ids)):
        raise ValueError("duplicate registry identity")
    selectors = [s.strip() for s in selection.split(",") if s.strip()]
    known = {"all", *ids, *(g for c in registry for g in c["groups"])}
    if not selectors or any(s not in known for s in selectors):
        raise ValueError("unknown/empty case selection: " + selection)
    return [c for c in registry if "all" in selectors or c["id"] in selectors
            or set(c["groups"]).intersection(selectors)]


def aggregate_results(selected, results):
    by_id = {r["id"]: r for r in results}
    if len(by_id) != len(results) or set(by_id) - {c["id"] for c in selected}:
        raise ValueError("duplicate/unselected result identity")
    records = []
    for c in selected:
        records.append(by_id.get(c["id"], {"id": c["id"], "status":
            c["coverage_status"] if c["coverage_status"] != "RUNNABLE" else "NOT_RUN",
            "reason": c["reason"], "executed": False}))
    failed = [r["id"] for r in records if r["status"] == "FAIL"]
    pending = [r["id"] for r in records if r["status"].startswith("PENDING")]
    blocked = [r["id"] for r in records if r["status"] == "BLOCKED"]
    not_run = [r["id"] for r in records if r["status"] == "NOT_RUN"]
    unknown = [r for r in records if r["status"] not in ("PASS", "FAIL", "BLOCKED", "NOT_RUN")
               and not r["status"].startswith("PENDING")]
    if unknown:
        raise ValueError("unknown terminal result status")
    incomplete = pending or blocked or not_run or not records
    state, code = ("FAIL", 1) if failed else (("BLOCKED", 2) if incomplete else ("PASS", 0))
    return {"status": state, "exit_code": code, "selected_ids": [c["id"] for c in selected],
            "executed_ids": [r["id"] for r in records if r.get("executed")],
            "pending_ids": pending, "blocked_ids": blocked, "not_run_ids": not_run,
            "failed_ids": failed, "counts": {"selected": len(records),
                "executed": sum(bool(r.get("executed")) for r in records), "pending": len(pending),
                "blocked": len(blocked), "not_run": len(not_run), "failed": len(failed)},
            "cases": records, "scope": "selected cases only; not full production repair acceptance"}


def atomic_json(path, data):
    """Retain any incomplete temp as evidence; never truncate the terminal result."""
    path = Path(path)
    encoded = json.dumps(data, indent=2) + "\n"
    for parent in path.parents:
        if (parent / "ownership.json").is_file():
            files = [p for p in parent.rglob("*") if p.is_file()]
            if sum(p.stat().st_size for p in files) + len(encoded.encode()) > 64 * MIB or len(files) + 1 > 5000:
                raise OSError(28, "reserved journal budget exhausted", str(path))
            break
    temporary = path.with_name(path.name + ".incomplete-" + uuid.uuid4().hex)
    with temporary.open("x", encoding="utf-8") as f:
        os.chmod(temporary, 0o600)
        f.write(encoded)
        f.flush()
    temporary.replace(path)


def publish_summary(output, summary, label="BINDINGS_DEPLOYMENT_REGRESSION", writer=atomic_json):
    code = summary["exit_code"]
    try:
        writer(Path(output) / "result.json", summary)
    except Exception as error:
        print(f"{label}: FAIL — terminal journal write failed: {type(error).__name__}: {error}", file=sys.stderr, flush=True)
        print(json.dumps({"retained_summary": summary, "output_error": repr(error)}), flush=True)
        return 1
    print(label + ": " + summary["status"], flush=True)
    return code


def source_budget(source):
    entries, blocks = 0, 0
    for base, dirs, files in os.walk(source, followlinks=False):
        dirs[:] = [d for d in dirs if d not in (".git", "__pycache__")]
        entries += 1
        blocks += 4096
        for name in files:
            if name.endswith(".bak"):
                continue
            size = (Path(base) / name).lstat().st_size
            entries += 1
            blocks += max(4096, ((size + 4095) // 4096) * 4096)
    return {"entries": entries, "copy_bytes": blocks}


def overlap(a, b):
    return a == b or a in b.parents or b in a.parents


def validate_layout(source, output, work_root, live=True):
    paths = [Path(p).absolute() for p in (source, output, work_root)]
    resolved = [p.resolve() for p in paths]
    if any(p != r for p, r in zip(paths, resolved)):
        raise HarnessBlocked("symlinked source/work/output ancestor is not an owned layout")
    if any(overlap(a, b) for i, a in enumerate(resolved) for b in resolved[i + 1:]):
        raise HarnessBlocked("source, work and output must be disjoint non-nested paths")
    if not paths[0].is_dir():
        raise HarnessBlocked("source directory missing")
    if paths[1].exists() or paths[2].exists():
        raise HarnessBlocked("refusing existing output/work root; retain the old run")
    if live and (current_profile().work_base not in paths[2].parents
                 or current_profile().journal_base not in paths[1].parents):
        raise HarnessBlocked("work must be a fresh scratch child and output a fresh recovery-journals child")
    return paths


def require_guest_identity():
    current_profile().verify(require_console=True)


def retained_complete_copies(journal_base, source, work_base):
    """The two-copy ceiling spans runs, including retained tooling fixtures."""
    copies = []
    for marker in Path(journal_base).rglob("ownership.json"):
        owner = json.loads(marker.read_text())
        if not owner.get("live"):
            continue
        peer_source = Path(owner["source"]).resolve()
        if peer_source.parent != Path(source).resolve().parent:
            continue  # Distinct task/source family, never reclaim or assume ownership.
        work = Path(owner["work_root"])
        if Path(work_base).resolve() not in work.resolve().parents or owner["uid"] != os.getuid():
            raise HarnessBlocked("ambiguous peer workspace ownership")
        for record in marker.parent.glob("*/paths.json"):
            paths = json.loads(record.read_text())
            tree = Path(paths["tree"])
            if tree.exists():
                if tree.is_symlink() or tree.parent.parent != work or tree.resolve() != tree:
                    raise HarnessBlocked("unsafe peer complete-copy record")
                copies.append(tree)
    return list(dict.fromkeys(copies))


class Workspace:
    """Measured two-copy ceiling. Never reclaim a historical/new case tree."""
    def __init__(self, source, output, work_root, live=True, disk_usage=shutil.disk_usage, statvfs=os.statvfs,
                 archive_completed=False):
        self.archive_completed = archive_completed
        self.profile = current_profile() if live else None
        if live:
            require_guest_identity()
        self.source, self.output, self.work_root = validate_layout(source, output, work_root, live)
        self.live, self.disk_usage, self.statvfs = live, disk_usage, statvfs
        self.budget = source_budget(self.source)
        self.copies = retained_complete_copies(self.profile.journal_base, self.source, self.profile.work_base) if live else []
        self.peak = {"copy_count": 0, "candidate": self.budget}
        if live:
            self.profile.prepare_roots()
            self.preflight(initial=True)
        self.output.mkdir(mode=0o700, parents=True)
        self.work_root.mkdir(mode=0o700, parents=True)
        atomic_json(self.output / "ownership.json", {"source": str(self.source), "work_root": str(self.work_root),
                    "output": str(self.output), "uid": os.getuid(), "pid": os.getpid(), "live": live,
                    "guest_profile": self.profile.record() if live else None})

    def preflight(self, initial=False):
        if self.live:
            self.profile.verify(require_console=True)
            self.copies = list(dict.fromkeys([p for p in self.copies if p.exists()]
                + retained_complete_copies(self.profile.journal_base, self.source, self.profile.work_base)))
        if len(self.copies) >= 2:
            raise HarnessBlocked("two retained complete case copies reached; new exact-path reclamation approval required")
        if not self.live:
            return
        work = self.work_root if self.work_root.exists() else self.profile.work_base
        journal = self.output if self.output.exists() else self.profile.journal_base
        wf, jf = self.statvfs(work), self.statvfs(journal)
        runtime = self.statvfs(self.profile.session_runtime)
        if runtime.f_bavail * runtime.f_frsize < 64 * MIB or runtime.f_favail < 5000:
            raise HarnessBlocked("guest runtime byte/inode reserve unavailable; preserve stopped task logs before reclaim")
        required = max(640 * MIB if initial else 0, self.budget["copy_bytes"] + 128 * MIB + 256 * MIB)
        if wf.f_bavail * wf.f_frsize < required or wf.f_favail < max(90000 if initial else 0, self.budget["entries"] + 50000):
            raise HarnessBlocked("scratch byte/inode preflight cannot retain recovery reserve")
        if jf.f_bavail * jf.f_frsize < 1024 * MIB + 64 * MIB or jf.f_favail < 55000:
            raise HarnessBlocked("root journal byte/inode reserve unavailable")
        if self.output.exists():
            files = [p for p in self.output.rglob("*") if p.is_file()]
            if sum(p.stat().st_size for p in files) >= 64 * MIB or len(files) >= 5000:
                raise HarnessBlocked("reserved root journal budget exhausted")
        self.peak.update(scratch_available_bytes=wf.f_bavail * wf.f_frsize,
                         scratch_available_inodes=wf.f_favail, root_available_bytes=jf.f_bavail * jf.f_frsize,
                         runtime_available_bytes=runtime.f_bavail * runtime.f_frsize,
                         runtime_available_inodes=runtime.f_favail)

    def case(self, identity, tree_name="tree"):
        self.preflight()
        work, journal = self.work_root / identity, self.output / identity
        if work.exists() or journal.exists():
            raise HarnessBlocked("refusing existing case paths")
        work.mkdir(mode=0o700)
        journal.mkdir(mode=0o700)
        tree = work / tree_name
        self.copies.append(tree)  # Reserve before copying, including a failed partial copy.
        self.peak["copy_count"] = max(self.peak["copy_count"], len(self.copies))
        shutil.copytree(self.source, tree, symlinks=True,
                        ignore=shutil.ignore_patterns(".git", "*.bak", "__pycache__"))
        atomic_json(journal / "paths.json", {"work": str(work), "tree": str(tree), "journal": str(journal)})
        return work, journal, tree

    def archive_case_tree(self, case_dir, lifecycle):
        """Opt-in lossless retention of this run's quiesced disposable copy.

        Unverified/live/foreign/older trees are never reclaimed. The two-copy
        ceiling still applies before every allocation, including failed archives.
        """
        lifecycle.assert_quiet()
        case_dir = Path(case_dir)
        journal = self.output / case_dir.name
        record = json.loads((journal / "paths.json").read_text())
        tree = Path(record["tree"])
        if (case_dir.parent != self.work_root or case_dir != case_dir.resolve() or tree.parent != case_dir
                or tree.is_symlink() or tree != tree.resolve() or not case_dir.is_dir()):
            raise HarnessBlocked("archive is not this run's exact owned disposable tree")
        if tree.exists():
            if tree not in self.copies or not tree.is_dir():
                raise HarnessBlocked("source tree is not a registered disposable copy")
        else:
            # Older completed runs may already have packed the source tree but
            # still retain their generated config/cache replicas. Preserve that
            # verified capsule inside the complete workspace capsule as well.
            earlier = json.loads((journal / "archived-tree.json").read_text())
            earlier_path = Path(earlier["archive"])
            if (earlier.get("tree") != str(tree) or not earlier.get("verified_before_reclamation")
                    or earlier_path.parent != case_dir or earlier_path.is_symlink()
                    or earlier_path != earlier_path.resolve() or sha(earlier_path) != earlier["sha256"]):
                raise HarnessBlocked("earlier disposable source archive is not verified")
        archive = case_dir.with_name(case_dir.name + ".tar.gz")
        temporary = archive.with_suffix(archive.suffix + ".incomplete")
        if archive.exists() or temporary.exists():
            raise HarnessBlocked("refusing an existing disposable-tree archive")

        def inventory():
            result = {}
            for path in [case_dir, *sorted(case_dir.rglob("*"))]:
                st = path.lstat()
                kind = "link" if path.is_symlink() else "file" if path.is_file() else "directory" if path.is_dir() else None
                if kind is None:
                    raise HarnessBlocked("unsupported disposable-tree archive entry")
                result[str(path.relative_to(case_dir.parent))] = {
                    "kind": kind, "uid": st.st_uid, "gid": st.st_gid, "mode": stat.S_IMODE(st.st_mode),
                    "mtime_ns": st.st_mtime_ns,
                    "xattrs": {key: base64.b64encode(os.getxattr(path, key, follow_symlinks=False)).decode()
                               for key in os.listxattr(path, follow_symlinks=False)},
                    "content": os.readlink(path) if kind == "link" else sha(path) if kind == "file" else None}
            return result

        captured = inventory()
        with temporary.open("xb") as raw:
            with tarfile.open(fileobj=raw, mode="w:gz", format=tarfile.PAX_FORMAT) as tar:
                for name, meta in captured.items():
                    path = case_dir.parent / name
                    info = tar.gettarinfo(str(path), arcname=name)
                    ns = meta["mtime_ns"]
                    info.pax_headers["mtime"] = f"{ns // 1000000000}.{ns % 1000000000:09d}"
                    info.pax_headers["atmosphera.xattrs"] = json.dumps(meta["xattrs"], sort_keys=True)
                    if meta["kind"] == "file":
                        with path.open("rb") as content:
                            tar.addfile(info, content)
                    else:
                        tar.addfile(info)
            raw.flush()
            os.fsync(raw.fileno())
        with tarfile.open(temporary, "r:gz") as tar:
            members = tar.getmembers()
            if len(members) != len(captured) or {m.name for m in members} != set(captured):
                raise HarnessBlocked("disposable archive membership verification failed")
            for member in members:
                meta = captured[member.name]
                ns = meta["mtime_ns"]
                if ((member.uid, member.gid, member.mode) != (meta["uid"], meta["gid"], meta["mode"])
                        or member.pax_headers["mtime"] != f"{ns // 1000000000}.{ns % 1000000000:09d}"
                        or json.loads(member.pax_headers["atmosphera.xattrs"]) != meta["xattrs"]):
                    raise HarnessBlocked("disposable archive metadata verification failed")
                if meta["kind"] == "file":
                    if not member.isfile() or hashlib.sha256(tar.extractfile(member).read()).hexdigest() != meta["content"]:
                        raise HarnessBlocked("disposable archive byte verification failed")
                elif meta["kind"] == "link":
                    if not member.issym() or member.linkname != meta["content"]:
                        raise HarnessBlocked("disposable archive link verification failed")
                elif not member.isdir():
                    raise HarnessBlocked("disposable archive type verification failed")
        lifecycle.assert_quiet()
        if inventory() != captured:
            raise HarnessBlocked("disposable tree changed during archive; retaining both")
        temporary.replace(archive)
        atomic_json(journal / "archived-workspace.json", {"archive": str(archive), "sha256": sha(archive),
                    "workspace": str(case_dir), "tree": str(tree), "entries": captured, "verified_before_reclamation": True})
        shutil.rmtree(case_dir)  # Only after full byte/metadata verification and quiescence.
        self.copies = [p for p in self.copies if p.exists()]


def process_table():
    rows = {}
    for p in Path("/proc").glob("[0-9]*"):
        try:
            fields = (p / "stat").read_text().rsplit(")", 1)[1].split()
            rows[int(p.name)] = {"pid": int(p.name), "state": fields[0], "ppid": int(fields[1]),
                                 "pgid": int(fields[2]), "start": fields[19]}
        except (FileNotFoundError, ProcessLookupError):
            continue
    return rows


class OwnedLifecycle:
    """Track stable process identities/descendants, without any termination policy."""
    def __init__(self):
        self.profile = current_profile()
        self.console = self.profile.console
        self.owned = {}
        self.groups = set()
        self.roots = set()
        self.done = threading.Event()
        self.lock = threading.Lock()
        self.thread = threading.Thread(target=self._watch, daemon=True)
        self.thread.start()

    def track(self, proc):
        rows = process_table()
        item = rows.get(proc.pid)
        if item:
            if proc.pid in self.console.pids or item["pgid"] in self.console.groups or item["pgid"] == os.getpgrp():
                raise HarnessBlocked("refusing desktop/runner process-group ownership")
            with self.lock:
                self.owned[proc.pid] = item
                self.groups.add(item["pgid"])

    def sample(self):
        rows = process_table()
        with self.lock:
            # Detached children can change session/PPID before the next poll.
            # A fresh case's exact path is also an ownership boundary; the
            # original named desktop never has that path in its command.
            for pid, row in rows.items():
                if pid in self.console.pids or not self.roots:
                    continue
                try:
                    command = Path(f"/proc/{pid}/cmdline").read_bytes().decode(errors="replace")
                except (FileNotFoundError, ProcessLookupError, PermissionError):
                    continue
                if any(root in command for root in self.roots):
                    self.owned[pid] = row
            ancestors = {pid for pid, old in self.owned.items()
                         if pid in rows and rows[pid]["start"] == old["start"]}
            while True:
                found = {pid for pid, row in rows.items() if row["ppid"] in ancestors or row["pgid"] in self.groups}
                found -= ancestors
                if not found:
                    break
                for pid in found:
                    if pid in self.console.pids or rows[pid]["pgid"] in self.console.groups:
                        raise HarnessBlocked("desktop unexpectedly intersects owned descendants")
                    self.owned[pid] = rows[pid]
                ancestors.update(found)
            return [rows[pid] for pid, old in self.owned.items() if pid in rows
                    and rows[pid]["start"] == old["start"] and rows[pid]["state"] != "Z"]

    def add_root(self, path):
        with self.lock:
            self.roots.add(str(Path(path).resolve()) + "/")

    def _watch(self):
        while not self.done.wait(.03):
            try:
                self.sample()
            except Exception as error:
                self.watch_error = repr(error)
                return

    def assert_quiet(self):
        self.profile.verify()
        if getattr(self, "watch_error", None):
            raise HarnessBlocked("owned process observation failed: " + self.watch_error)
        live = self.sample()
        if live:
            raise HarnessBlocked("refusing restoration with live owned producer identities: " + repr(live))
        return list(self.owned.values())

    def close(self):
        self.done.set()
        self.thread.join(timeout=2)


class JournalCapture:
    """Keep the reserved journal bounded; spill excess and stop the case honestly."""
    def __init__(self, proc, journal_root, logpath, work_root):
        self.proc, self.root, self.path = proc, journal_root, logpath
        self.spill = work_root / (logpath.name + ".overflow")
        self.error = None
        self.thread = threading.Thread(target=self._read, daemon=True)
        self.thread.start()

    def _read(self):
        try:
            with self.path.open("xb") as log:
                overflow = None
                try:
                    while True:
                        chunk = self.proc.stdout.read1(65536)
                        if not chunk:
                            break
                        if overflow is None:
                            files = [p for p in self.root.rglob("*") if p.is_file()]
                            # Leave result/error space on the separate journal filesystem.
                            if sum(p.stat().st_size for p in files) + len(chunk) > 64 * MIB - 256 * 1024 or len(files) >= 4990:
                                self.error = "root journal log budget reached; overflow retained on scratch"
                                overflow = self.spill.open("xb")
                        destination = overflow if overflow else log
                        destination.write(chunk)
                        destination.flush()
                finally:
                    if overflow:
                        overflow.close()
        except Exception as error:
            self.error = "log capture failed: " + repr(error)

    def join(self, check_error=True):
        self.thread.join(timeout=5)
        if self.thread.is_alive():
            raise HarnessBlocked("owned stdout pipe still has a live producer")
        if check_error and self.error:
            raise HarnessBlocked(self.error)


class OwnedSocketRelay:
    """Test-only real-byte transport fault boundary; no action/reply fabrication."""
    def __init__(self, path, upstream):
        self.path, self.upstream = path, upstream
        self.online = True
        self.done = threading.Event()
        self.connections = []
        self.workers = []
        self.listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.listener.bind(str(path)); self.listener.listen(); self.listener.settimeout(.1)
        self.thread = threading.Thread(target=self._accept, daemon=True); self.thread.start()

    def _accept(self):
        while not self.done.is_set():
            try: client, _ = self.listener.accept()
            except socket.timeout: continue
            except OSError: return
            if not self.online:
                client.close(); continue
            target = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try: target.connect(self.upstream)
            except OSError:
                client.close(); target.close(); continue
            self.connections.append((client, target))
            thread = threading.Thread(target=self._forward, args=(client, target), daemon=True)
            self.workers.append(thread); thread.start()

    def _forward(self, client, target):
        try:
            while self.online and not self.done.is_set():
                readable, _, _ = select.select([client, target], [], [], .1)
                for peer in readable:
                    data = peer.recv(65536)
                    if not data: return
                    (target if peer is client else client).sendall(data)
        except OSError:
            pass  # Deliberate transport close, never a synthesized action result.
        finally:
            client.close(); target.close()

    def disconnect(self):
        self.online = False
        for pair in self.connections:
            for peer in pair:
                try: peer.shutdown(socket.SHUT_RDWR)
                except OSError: pass
        for thread in self.workers: thread.join(timeout=2)

    def close(self):
        self.disconnect(); self.done.set(); self.listener.close(); self.thread.join(timeout=2)
        if self.thread.is_alive() or any(t.is_alive() for t in self.workers):
            raise HarnessBlocked("owned transport relay did not quiesce")
        self.path.unlink()  # Owned ephemeral socket, not source/data evidence.


class FileSnapshot:
    """Explicit paths only; preserve link and referent plus captured metadata."""
    def __init__(self, paths, backup):
        self.records = []
        backup.mkdir()
        for path in dict.fromkeys(Path(p) for p in paths):
            self._capture(path, backup)
            if path.is_symlink():
                self._capture(path.resolve(strict=False), backup)
        atomic_json(backup.parent / "manifest.json", self.records)

    def _capture(self, path, backup):
        if any(r["path"] == str(path) for r in self.records):
            return
        r = {"path": str(path), "exists": os.path.lexists(path)}
        if r["exists"]:
            s = path.lstat()
            r.update(uid=s.st_uid, gid=s.st_gid, mode=stat.S_IMODE(s.st_mode), mtime_ns=s.st_mtime_ns,
                     xattrs={k: base64.b64encode(os.getxattr(path, k, follow_symlinks=False)).decode()
                             for k in os.listxattr(path, follow_symlinks=False)})
            if path.is_symlink():
                r["symlink"] = os.readlink(path)
            elif path.is_file():
                b = backup / str(len(self.records))
                shutil.copy2(path, b)
                r.update(backup=str(b), sha256=sha(path))
            else:
                raise HarnessBlocked("unsupported backup type: " + str(path))
        self.records.append(r)

    def matches(self, r):
        p = Path(r["path"])
        if os.path.lexists(p) != r["exists"]:
            return False
        if not r["exists"]:
            return True
        s = p.lstat()
        if (s.st_uid, s.st_gid, stat.S_IMODE(s.st_mode), s.st_mtime_ns) != (r["uid"], r["gid"], r["mode"], r["mtime_ns"]):
            return False
        attrs = {k: base64.b64encode(os.getxattr(p, k, follow_symlinks=False)).decode()
                 for k in os.listxattr(p, follow_symlinks=False)}
        if attrs != r["xattrs"]:
            return False
        return os.readlink(p) == r["symlink"] if "symlink" in r else (not p.is_symlink() and p.is_file() and sha(p) == r["sha256"])

    def restore(self, lifecycle):
        identities = lifecycle.assert_quiet()  # First: never mutate before quiescence.
        for r in self.records:
            if self.matches(r):
                continue
            p = Path(r["path"])
            if not r["exists"]:
                p.unlink(missing_ok=True)
                continue
            if "symlink" in r:
                if os.path.lexists(p):
                    p.unlink()
                p.symlink_to(r["symlink"])
            else:
                if p.is_symlink():
                    p.unlink()
                p.write_bytes(Path(r["backup"]).read_bytes())
                os.chmod(p, r["mode"])
            s = p.lstat()
            if (s.st_uid, s.st_gid) != (r["uid"], r["gid"]):
                os.chown(p, r["uid"], r["gid"], follow_symlinks=False)
            current_attrs = os.listxattr(p, follow_symlinks=False)
            for key in current_attrs:
                if key not in r["xattrs"]:
                    os.removexattr(p, key, follow_symlinks=False)
            for key, value in r["xattrs"].items():
                os.setxattr(p, key, base64.b64decode(value), follow_symlinks=False)
            os.utime(p, ns=(p.lstat().st_atime_ns, r["mtime_ns"]), follow_symlinks=False)
        if not all(self.matches(r) for r in self.records):
            raise RuntimeError("captured link/referent bytes or metadata did not restore")
        return {"files": [r["path"] for r in self.records], "owned_observed_identities": identities,
                "live_owned_at_restore": lifecycle.sample(),
                "checked_metadata": ["uid", "gid", "mode", "mtime_ns", "recorded xattrs", "symlink target", "referent bytes"]}


def run(args, **kwargs):
    if Path(args[0]).name in ("qs", "quickshell"):
        # subprocess.run automatically SIGKILLs on timeout. Our permission is
        # scoped TERM only; retain/refuse an unquiesced client instead of escalating.
        timeout = kwargs.pop("timeout", None)
        check = kwargs.pop("check", False)
        proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, start_new_session=True, **kwargs)
        try:
            out, err = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired as error:
            if proc.poll() is None:
                protect_owned_process(proc)
                os.killpg(proc.pid, signal.SIGTERM)
            try:
                out, err = proc.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                raise HarnessBlocked("owned qs client did not quiesce after approved TERM: pid=" + str(proc.pid))
            raise subprocess.TimeoutExpired(args, timeout, output=out, stderr=err) from error
        if check and proc.returncode:
            raise subprocess.CalledProcessError(proc.returncode, args, output=out, stderr=err)
        return subprocess.CompletedProcess(args, proc.returncode, out, err)
    return subprocess.run(args, capture_output=True, text=True, **kwargs)


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def json_equal(a, b):
    """JSON equality, including types: Python's False == 0 is not JSON equality."""
    if isinstance(a, bool) or isinstance(b, bool):
        return type(a) is type(b) and a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return a == b
    if type(a) is not type(b):
        return False
    if isinstance(a, dict):
        return a.keys() == b.keys() and all(json_equal(a[k], b[k]) for k in a)
    if isinstance(a, list):
        return len(a) == len(b) and all(json_equal(x, y) for x, y in zip(a, b))
    return a == b


def json_ipc_text(value):
    # qs's CLI11 positional vector treats a first-byte '[' as argument-vector
    # notation. JSON whitespace preserves a single argument and its JSON type.
    return " " + json.dumps(value, separators=(",", ":"))


def frozen_capture(intent):
    return {key: intent[key] for key in ("captureId", "provenance", "section", "path",
            "base", "json", "foreignEpoch", "coveredPaths")}


def terminal_delivery_errors(events, identity, environment, startup=False):
    errors = []
    tokens = ["terminal-original"] + (["startup-frozen", "startup-frozen-second"] if startup else [])
    signals = [e for e in events if e["event"] == "handoff" and
               e["detail"].get("requestId") == identity and e["detail"].get("attemptId") == 1]
    if len(signals) != 1:
        return ["original signal missing or duplicated"]
    original = signals[0]
    expected = {key: original["detail"][key] for key in ("requestId", "attemptId", "success", "error")}
    if original["detail"]["selected"] != environment:
        errors.append("signal captured environment changed")
    old_deliveries = [original]
    for token in tokens:
        matches = [e for e in events if e["event"] in ("callback", "startup-observer") and
                   e["detail"].get("token") == token]
        if len(matches) != 1:
            errors.append(token + ": old delivery missing or duplicated")
            continue
        observed = matches[0]
        old_deliveries.append(observed)
        actual = {key: observed["detail"].get(key) for key in expected}
        if not json_equal(expected, actual) or observed["detail"].get("capturedEnvironment") != environment:
            errors.append(token + ": frozen tuple changed")
    last_old = max(events.index(e) for e in old_deliveries)
    if any(i <= last_old and e["event"] in ("stage", "handoff", "callback") and
           e["detail"].get("requestId") == identity and e["detail"].get("attemptId", 0) > 1
           for i, e in enumerate(events)):
        errors.append("new attempt stage/completion preceded old delivery")
    return errors


def retained_state_errors(expected, artifacts):
    errors = []
    for number, state in enumerate(expected, 1):
        matched = [a for a in artifacts if json_equal(a.get("observed"), state)]
        if not matched:
            errors.append("complete inspected version F" + str(number) + " not privately retained")
        elif not any(a.get("file_mode") == 0o600 and a.get("directory_mode") == 0o700 for a in matched):
            errors.append("version F" + str(number) + " artifact permissions are not private")
    return errors


class Runner:
    def __init__(self, workspace):
        self.workspace = workspace
        self.source, self.output = source, output = workspace.source, workspace.output
        spec = importlib.util.spec_from_file_location("bindings", HERE / "bindings-regression.py")
        self.bindings = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.bindings)
        self.ctx = self.bindings.Ctx(str(source), output)
        self.failures = []
        self.process = None
        self.manifest = []
        self.referents = []
        self.desktop = {}
        self.lifecycle = OwnedLifecycle()
        self.ctx.owned_register = self.lifecycle.track
        self.gates = []
        self.stop_failed = False
        self.case = None
        self.finished_cases = []
        workspace.profile.console.verify(required=True)
        for identity in workspace.profile.console.records:
            path = Path("/proc") / str(identity.pid) / "cmdline"
            self.desktop[str(path)] = path.read_bytes().hex()
        if not self.desktop:
            raise RuntimeError("original named Atmosphera desktop instance missing")
        (output / "desktop.json").write_text(json.dumps(self.desktop, indent=2))
        hashes = {str(p.relative_to(source)): sha(p) for p in sorted(source.rglob("*"))
                  if p.is_file() and ".git" not in p.parts and not p.name.endswith(".bak")
                  and "__pycache__" not in p.parts}
        (output / "source-hashes.json").write_text(json.dumps(hashes, indent=2))
        backup = output / "legacy-backup"
        backup.mkdir()
        for i, name in enumerate(FILES):
            p = Path(name) if name.startswith("/") else Path.home() / name
            r = {"path": str(p), "exists": p.exists() or p.is_symlink()}
            if r["exists"]:
                st = p.lstat()
                r.update(uid=st.st_uid, gid=st.st_gid, mode=st.st_mode)
                if p.is_symlink():
                    r["symlink"] = os.readlink(p)
                    target = p.resolve(strict=False)
                    referent = {"path": str(target), "exists": target.exists()}
                    if referent["exists"]:
                        target_stat = target.stat()
                        copied = backup / (str(i) + "-referent")
                        shutil.copy2(target, copied)
                        referent.update(uid=target_stat.st_uid, gid=target_stat.st_gid, mode=target_stat.st_mode,
                                        backup=str(copied), sha256=sha(target))
                    self.referents.append(referent)
                else:
                    b = backup / str(i)
                    shutil.copy2(p, b)
                    r.update(backup=str(b), sha256=sha(p))
            self.manifest.append(r)
        (output / "manifest.json").write_text(json.dumps(self.manifest, indent=2))
        (output / "referents.json").write_text(json.dumps(self.referents, indent=2))
        self.states = {"xremap": run(["systemctl", "--user", "is-active", "xremap-atmosphera.service"]).stdout.strip(),
                       "keyd": run(["systemctl", "is-active", "keyd.service"]).stdout.strip()}
        (output / "services.json").write_text(json.dumps(self.states, indent=2))
        config_root = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
        paths = [Path(r["path"]) for r in self.manifest]
        paths += [config_root / name.removeprefix(".config/") for name in FILES if name.startswith(".config/")]
        paths.append(Path.home() / ".config/systemd/user/xremap-atmosphera.service")
        properties = run(["systemctl", "--user", "show", "xremap-atmosphera.service", "-p", "FragmentPath", "-p", "DropInPaths"])
        if properties.returncode:
            raise HarnessBlocked("cannot record consumer unit/drop-ins: " + properties.stderr)
        for line in properties.stdout.splitlines():
            paths.extend(Path(v) for v in line.partition("=")[2].split() if v)
        self.snapshot = FileSnapshot(paths, output / "backup")
        self.manager_environment = run(["systemctl", "--user", "show-environment"])
        if self.manager_environment.returncode:
            raise HarnessBlocked("cannot capture original user-manager environment")
        atomic_json(output / "consumer-baseline.json", {"config_root": str(config_root), "unit_properties": properties.stdout,
                    "manager_environment": self.manager_environment.stdout, "services": self.states})

    def check(self, condition, description):
        if not condition:
            self.failures.append(description)

    def start(self, name, mode="settings", before_launch=None, wait_startup=True):
        self.lifecycle.assert_quiet()
        if self.stop_failed:
            raise HarnessBlocked("previous teardown failed; refusing another live case")
        self.mode = mode
        self.work_case, self.case, self.tree = self.workspace.case(getattr(self, "current_id", name))
        self.lifecycle.add_root(self.work_case)
        self.lifecycle.add_root(self.case)
        self.live_started = False
        self.gates = []
        shutil.copy2(HERE / "fixtures/bindings-deployment.qml", self.tree / "deployment-probe.qml")
        native_build, native_record = prepare_native_controls(self.source)
        atomic_json(self.case / "native-controls.json", native_record)
        self.native_schedule = self.case / "native-schedule.json"
        self.native_rules = []
        atomic_json(self.native_schedule, {"rules": self.native_rules})
        self.config = self.work_case / "config"
        (self.config / "settings").mkdir(parents=True)
        (self.work_case / "cache").mkdir()
        (self.config / "settings/bindings.json").write_text('{"environment":"none"}\n')
        (self.config / "settings/general.json").write_text('{"animationDisabled":true}\n')
        self.entry = self.tree / "deployment-probe.qml"
        self.env = self.ctx.env({
            "ATMOSPHERA_CONFIG_DIR": str(self.config), "ATMOSPHERA_SETTINGS_FILE": str(self.config / "settings.json"),
            "ATMOSPHERA_CACHE_DIR": str(self.work_case / "cache"), "ATMOSPHERA_SHELL_DIR": str(self.tree),
            "ATMOSPHERA_DEBUG": "0", "DEPLOYMENT_CASE": mode, "QT_FORCE_STDERR_LOGGING": "1",
            "PATH": str(self.tree / "Scripts/bash") + ":" + os.environ["PATH"],
        })
        self.env.update(self.workspace.profile.child_environment("bd-"))
        self.env.update(QML_IMPORT_PATH=str(native_build),
                        LD_PRELOAD=str(native_build / "libatmosphera_native_io.so"),
                        ATCQ_NATIVE_SCHEDULE=str(self.native_schedule))
        self.logpath = self.case / "qs.log"
        self.event_log_paths = [self.logpath]
        if before_launch:
            before_launch()
        self.record_copy_changes(name)
        command = ["qs", "-p", str(self.entry)]
        launch_env = self.env
        if mode == "runtime-consumers":
            # Preload only qs, not the private-bus launcher. Otherwise the
            # launcher's inherited PID fence correctly excludes its qs child.
            command = ["dbus-run-session", "--", "env", "LD_PRELOAD=" + self.env["LD_PRELOAD"], *command]
            launch_env = {key: value for key, value in self.env.items() if key != "LD_PRELOAD"}
        self.process = subprocess.Popen(command, env=launch_env, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, start_new_session=True)
        self.lifecycle.track(self.process)
        self.live_started = True
        self.capture = JournalCapture(self.process, self.output, self.logpath, self.work_case)
        self.wait(lambda: any(e["event"] == "ready" for e in self.events()), "actual UI readiness")
        if wait_startup:
            self.wait(lambda: any(e["event"] == "startup" and e["detail"]["success"] for e in self.events()), "startup completion")
            self.wait(lambda: any(e["event"] == "saved" or (e["event"] == "startup" and e["detail"]["success"])
                                 for e in self.events()), "initial save/startup completion")
        self.bindings.focus_launched(self.ctx, self.process, "bindings-deployment-regression")

    def record_copy_changes(self, scenario):
        changes = {}
        for p in self.tree.rglob("*"):
            if not p.is_file() or p.is_symlink():
                continue
            name = p.relative_to(self.tree).as_posix()
            original = self.source / name
            if not original.exists() or sha(p) != sha(original):
                old = original.read_text(errors="replace").splitlines(True) if original.exists() else []
                new = p.read_text(errors="replace").splitlines(True)
                changes[name] = "".join(difflib.unified_diff(old, new, fromfile="candidate/" + name, tofile="disposable/" + name))
        atomic_json(self.case / "disposable-copy-diff.json", {"scenario": scenario, "tree": str(self.tree), "changes": changes,
                    "claim": "test-only copy instrumentation; production candidate is unchanged"})

    def events(self):
        events = []
        marker = "DEPLOYMENT_PROBE|"
        if not hasattr(self, "logpath") or not self.logpath.exists():
            return events
        content = "".join(p.read_text() for p in getattr(self, "event_log_paths", [self.logpath]))
        for line in content.splitlines(keepends=True):
            if not line.endswith("\n"):
                continue  # The capture can be between writes; never parse a partial record.
            pos = line.find(marker)
            if pos >= 0:
                events.append(json.loads(line[pos + len(marker):]))
        return events

    def wait(self, condition, description, timeout=30):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if getattr(self, "capture", None) and self.capture.error:
                raise HarnessBlocked(self.capture.error)
            if condition():
                return True
            if self.process and self.process.poll() is not None:
                break
            time.sleep(.1)
        raise RuntimeError(f"timed out awaiting {description}; see {self.logpath}")

    def ipc_wire(self, method, *args):
        p = run(["qs", "-p", str(self.entry), "ipc", "call", "deploymentprobe", method, *args], env=self.env, timeout=15)
        if p.returncode:
            raise RuntimeError(f"fixture IPC failed: {p.stdout}{p.stderr}")
        return p.stdout

    def ipc(self, method, *args):
        response = self.ipc_wire(method, *args)
        if method != "auditPrivateBegin":
            try:
                header = json.loads(response)
            except json.JSONDecodeError:
                header = None
            if isinstance(header, dict) and header.get("protocol") == "deployment-private-v1":
                if set(header) != {"protocol", "id", "length"}:
                    raise HarnessBlocked("invalid private snapshot transfer header")
                self.private_json_serial = getattr(self, "private_json_serial", 0) + 1
                return self.private_transfer(header, f"ipc-{method}-{self.private_json_serial}")
        return response

    def begin_private_transfer(self, method, *args):
        # Capture once on the producer step; drain the immutable evidence only
        # after the causal schedule is queued. Observation must not become a
        # wait that lets autosave overtake an intended pending-input stimulus.
        header = json.loads(self.ipc_wire(method, *args))
        if not isinstance(header, dict) or set(header) != {"protocol", "id", "length"} or header["protocol"] != "deployment-private-v1":
            raise HarnessBlocked("invalid deferred private snapshot transfer header")
        return header

    def private_transfer(self, transfer, label):
        if type(transfer.get("id")) is not int or type(transfer.get("length")) is not int or not 0 < transfer["length"] < 16 * MIB:
            raise HarnessBlocked("invalid private snapshot transfer identity/length")
        pieces = []
        for offset in range(0, transfer["length"], 4096):
            frame = json.loads(self.ipc("auditPrivateChunk", str(transfer["id"]), str(offset), "4096"))
            if type(frame.get("id")) is not int or frame["id"] != transfer["id"] or frame.get("offset") != offset or not isinstance(frame.get("body"), str):
                raise HarnessBlocked("private snapshot frame identity/order changed")
            if len(frame["body"]) != min(4096, transfer["length"] - offset) or not frame["body"].isascii():
                raise HarnessBlocked("private snapshot frame truncated/encoding changed")
            pieces.append(frame["body"])
        response = "".join(pieces)
        atomic_json(self.case / (label + "-transfer.json"), dict(transfer, frames=len(pieces),
                    sha256=hashlib.sha256(response.encode("ascii")).hexdigest()))
        return response

    def private_state(self, label):
        response = self.private_transfer(json.loads(self.ipc("auditPrivateBegin")), label)
        try:
            state = json.loads(response)
        except json.JSONDecodeError:
            atomic_json(self.case / (label + "-invalid-ipc-private.json"), {"response": response})
            raise
        atomic_json(self.case / (label + "-private.json"), state)
        return state

    def inspected_state(self, target):
        result = run([sys.executable, str(self.tree / "Scripts/python/src/settings/section-io.py"),
                      "inspect", str(target)], check=True)
        payload = json.loads(result.stdout)
        if payload.get("ok") is not True:
            raise HarnessBlocked("real inspected-state witness unavailable")
        return payload["state"]

    def retained_artifacts(self, directory):
        return [dict(json.loads(p.read_text()), file_mode=stat.S_IMODE(p.stat().st_mode),
                     directory_mode=stat.S_IMODE(p.parent.stat().st_mode))
                 for p in sorted(directory.glob("*.json"))]

    def native_evidence(self, directory):
        artifacts = []
        for path in sorted(directory.rglob("metadata.json")):
            metadata = json.loads(path.read_text())
            body = path.parent / "bytes"
            self.check(stat.S_IMODE(path.stat().st_mode) == 0o600 and
                       stat.S_IMODE(path.parent.stat().st_mode) == 0o700, "native evidence permissions are not private")
            if metadata["bytesState"] == "available":
                self.check(body.is_file() and stat.S_IMODE(body.stat().st_mode) == 0o600,
                           "native complete evidence is missing its private byte artifact")
            artifacts.append(dict(metadata=metadata, directory=str(path.parent),
                bytesBase64=base64.b64encode(body.read_bytes()).decode() if body.is_file() else None))
        return artifacts

    def stop(self):
        try:
            for marker, fifo in self.gates:
                if marker.exists():
                    try:
                        self.release(fifo)
                    except OSError as error:
                        if error.errno != 6:  # ENXIO: no reader remains; do not hang.
                            raise
            if self.process and self.process.poll() is None:
                self.ipc("finish")
                self.process.wait(timeout=15)
            deadline = time.monotonic() + 5
            while self.lifecycle.sample() and time.monotonic() < deadline:
                time.sleep(.05)
            self.lifecycle.assert_quiet()
            if getattr(self, "capture", None):
                self.capture.join(check_error=False)
        except Exception:
            self.stop_failed = True
            raise
        self.process = None
        self.stop_failed = False

    def audit_case_end(self):
        if getattr(self, "capture", None) and self.capture.error:
            raise HarnessBlocked(self.capture.error)
        callbacks = {}
        for e in self.events():
            if e["event"] in ("callback", "save-callback", "audit-read", "startup-observer"):
                key = (e["event"], e["detail"]["token"])
                callbacks[key] = callbacks.get(key, 0) + 1
        self.check(all(n == 1 for n in callbacks.values()), "callback delivery changed/duplicated by case end: " + repr(callbacks))
        if getattr(self, "terminal_oracle", None):
            self.failures.extend(terminal_delivery_errors(self.events(), *self.terminal_oracle))
        if self.case:
            atomic_json(self.case / "final-events.json", {"events": self.events(), "callbacks": [
                {"event": k[0], "token": k[1], "count": n} for k, n in callbacks.items()]})
            self.record_copy_changes(getattr(self, "current_id", "case-end"))

    def settled_frame(self, name):
        # Focus acknowledgement and window destruction precede the compositor's
        # centering animation. Observe the rendered frame, not an assumed delay.
        previous, stable = None, 0
        end = time.monotonic() + 15
        while time.monotonic() < end:
            image = self.bindings._grim(self.ctx, name + "-before.png")
            pixels = subprocess.run(["magick", str(image), "-depth", "8", "rgb:-"],
                                    capture_output=True, check=True).stdout
            if len(pixels) != 1280 * 800 * 3:
                raise RuntimeError("physical-input fixture requires the recorded 1280x800 output")
            # The VM recipe's blue focus ring identifies the actual focused
            # window; wallpaper/closing-window pixels outside it are irrelevant.
            row = pixels[100 * 1280 * 3:101 * 1280 * 3]
            blue = [x for x in range(1280)
                    if all(abs(row[x * 3 + channel] - value) <= 8
                           for channel, value in enumerate((127, 200, 255)))]
            if len(blue) >= 8:
                left, right = min(blue), max(blue)
                # The welcome logo deliberately pulses forever. The wizard's
                # navigation lane, not that decoration, is the click target.
                lines = range(650, 720) if self.mode == "wizard" else range(100, 760)
                content = b"".join(pixels[(line * 1280 + left + 8) * 3:(line * 1280 + right - 8) * 3]
                                   for line in lines)
                state = (left, right, hashlib.sha256(content).hexdigest())
                stable = stable + 1 if state == previous else 0
                previous = state
                if stable >= 3:
                    return left, right
            else:
                previous, stable = None, 0
            time.sleep(.1)
        raise RuntimeError("fixture render did not settle before physical click")

    def mouse(self, name, x, y):
        self.bindings.focus_launched(self.ctx, self.process, "bindings-deployment-regression")
        left, right = self.settled_frame(name)
        if self.mode == "settings":
            x = (left + right) / 2
            image = self.output / (name + "-before.png")
            pixels = subprocess.check_output(["magick", str(image), "-depth", "8", "rgb:-"])
            rows = self.settings_card_geometry(pixels, left, right)
            choice = "none" if name.endswith("-none") else "macos"
            y = rows[choice]
            atomic_json(self.output / (name + "-geometry.json"), {"cards": rows, "requested_choice": choice,
                        "observed_focus_bounds": [left, right], "image": str(image), "target": [x, y]})
        elif name.startswith("wizard-next-") or name in ("wizard-dock", "wizard-finish", "wizard-failed-finish", "wizard-retry-finish"):
            image = self.output / (name + "-before.png")
            pixels = subprocess.check_output(["magick", str(image), "-depth", "8", "rgb:-"])
            x, y = self.wizard_primary_geometry(pixels, left, right)
            atomic_json(self.output / (name + "-geometry.json"), {"observed_focus_bounds": [left, right],
                        "image": str(image), "target": [x, y], "selector": "rendered lower-right primary button"})
        elif name in ("wizard-local-reset", "wizard-local-skip"):
            image = self.output / (name + "-before.png")
            pixels = subprocess.check_output(["magick", str(image), "-depth", "8", "rgb:-"])
            _, y = self.wizard_primary_geometry(pixels, left, right)
            # Positions are the two observed left footer controls in this
            # recorded/maximized VM recipe; the row center comes from its
            # rendered primary sibling, including changing status-lane height.
            x = left + (185 if name == "wizard-local-reset" else 100)
            atomic_json(self.output / (name + "-geometry.json"), {"image": str(image), "target": [x, y],
                        "observed_focus_bounds": [left, right], "selector": "left footer Reset/Skip; shared rendered row"})
        if not left < x < right:
            raise RuntimeError(f"requested click is outside the observed window: {x}, {left}, {right}")
        (self.output / (name + "-target.json")).write_text(
            json.dumps({"x": x, "y": y, "focused_left": left, "focused_right": right}, indent=2))
        self.action_at = time.time_ns() // 1_000_000
        event = {"execute": "input-send-event", "arguments": {"events": [
            {"type": "abs", "data": {"axis": "x", "value": round(x * 32767 / 1280)}},
            {"type": "abs", "data": {"axis": "y", "value": round(y * 32767 / 800)}},
            {"type": "btn", "data": {"button": "left", "down": True}},
        ]}}
        up = {"execute": "input-send-event", "arguments": {"events": [
            {"type": "btn", "data": {"button": "left", "down": False}}]}}
        cmds = [current_profile().qmp_command(e) for e in (event, up)]
        self.ctx.await_injection(name, cmds)

    @staticmethod
    def settings_card_geometry(pixels, left, right):
        """Observe the two rendered card shapes, never query component internals."""
        if len(pixels) != 1280 * 800 * 3:
            raise HarnessBlocked("settings card observation requires the recorded VM output")
        def rgb(x, y):
            start = (y * 1280 + x) * 3
            return tuple(pixels[start:start + 3])
        def runs(values):
            result = []
            for y in values:
                if result and y == result[-1][-1] + 1:
                    result[-1].append(y)
                else:
                    result.append([y])
            return result
        band = range(left + 24, right - 24)
        blue = runs([y for y in range(100, 740) if sum(
            r < 80 and g > 60 and b > 120 for r, g, b in (rgb(x, y) for x in band)) > len(band) * .7])
        selected = [(sum(a) / len(a) + sum(b) / len(b)) / 2 for a, b in zip(blue, blue[1:])
                    if 40 <= b[0] - a[-1] <= 110]
        # A clear vertical strip between the card's left edge and its radio
        # control identifies the other card independently of text wrapping.
        x = left + 40
        grey_values = [rgb(x, y)[0] for y in range(100, 740)
                       if max(rgb(x, y)) - min(rgb(x, y)) <= 3 and rgb(x, y)[0] < 100]
        if not grey_values:
            raise HarnessBlocked("no observed settings surface background")
        background = Counter(grey_values).most_common(1)[0][0]
        grey = runs([y for y in range(100, 740) if max(rgb(x, y)) - min(rgb(x, y)) <= 3
                     and background + 4 < rgb(x, y)[0] < background + 40])
        unselected = [(a[0] + a[-1]) / 2 for a in grey if 30 <= len(a) <= 120]
        centers = []
        for center in sorted(selected + unselected):
            # A selected card can have both a blue outline and the same grey
            # fill as the other card. Coincident shape observations are one
            # geometric target, never two separate controls.
            if not centers or abs(center - centers[-1]) > 3:
                centers.append(center)
        if len(centers) != 2 or not 40 < centers[1] - centers[0] < 160:
            raise HarnessBlocked("ambiguous rendered card geometry: " + repr({"selected": selected, "unselected": unselected}))
        return {"none": centers[0], "macos": centers[1]}

    @staticmethod
    def wizard_primary_geometry(pixels, left, right):
        if len(pixels) != 1280 * 800 * 3:
            raise HarnessBlocked("wizard geometry requires recorded VM output")
        observed = []
        for y in range(500, 750):
            xs = []
            for x in range((left + right) // 2, right - 24):
                start = (y * 1280 + x) * 3
                r, g, b = pixels[start:start + 3]
                if r < 80 and g > 60 and b > 120:
                    xs.append(x)
            if len(xs) > 50:
                observed.append((y, min(xs), max(xs)))
        groups = []
        for row in observed:
            if groups and row[0] == groups[-1][-1][0] + 1:
                groups[-1].append(row)
            else:
                groups.append([row])
        # Customize controls can also contain blue fills. The primary button
        # is the last separate lower-right shape, not their combined bounds.
        candidates = [g for g in groups if 25 <= g[-1][0] - g[0][0] <= 70]
        if not candidates:
            raise HarnessBlocked("ambiguous wizard primary-button geometry")
        observed = candidates[-1]
        x0 = min(r[1] for r in observed)
        x1 = max(r[2] for r in observed)
        if not 70 <= x1 - x0 <= 350:
            raise HarnessBlocked("wizard primary shape width is not a button")
        return (x0 + x1) / 2, (observed[0][0] + observed[-1][0]) / 2

    def observation(self, label):
        p = self.config / "settings/bindings.json"
        session = Path.home() / ".config/niri/atmosphera-session.kdl"
        layer = Path.home() / ".config/niri/atmosphera-shortcuts-macos.kdl"
        data = {"persisted": json.loads(p.read_text()) if p.exists() else None,
                "layer": layer.exists(), "include": "atmosphera-shortcuts-macos.kdl" in session.read_text(),
                 "session": session.read_text(), "xremap": run(["systemctl", "--user", "is-active", "xremap-atmosphera.service"]).stdout.strip()}
        data["base_sha256"] = sha(Path.home() / ".config/niri/config.kdl")
        original_base = next(r for r in self.manifest if r["path"].endswith("/niri/config.kdl"))
        self.check(data["base_sha256"] == original_base["sha256"], label + ": original base config changed")
        if layer.exists():
            data["layer_sha256"] = sha(layer)
            template = self.tree / "Bindings/environments/macos/niri/atmosphera-shortcuts-macos.kdl"
            if template.exists():
                self.check(data["layer_sha256"] == sha(template), label + ": installed layer differs from source")
        (self.case / f"{label}.json").write_text(json.dumps(data, indent=2))
        return data

    def settle(self, environment):
        p = self.config / "settings/bindings.json"
        self.wait(lambda: p.exists() and json.loads(p.read_text()).get("environment") == environment,
                  "persisted selected environment")
        self.wait(lambda: any(e["event"] == "handoff" and e["at"] >= self.action_at
                             and e["detail"]["selected"] == environment and e["detail"]["success"]
                             for e in self.events()), "accepted request handoff completion")
        state = self.status("completion-" + str(self.action_at))
        self.check(state["detail"]["owner"]["state"] == "Idle", "handoff returned without an idle selected queue")

    def endpoints(self, label):
        # Observe the device the real UI/helper created, never install another
        # template or call the old suite's manual session-layer loader.
        class Capture:
            def __init__(self, ctx, node, name):
                self.log_path = ctx.output / name
                self.log = self.log_path.open("w")
                self.proc = subprocess.Popen(["sudo", "-n", "timeout", "30", "stdbuf", "-oL", "evtest", node],
                                             stdout=self.log, stderr=subprocess.STDOUT, text=True, start_new_session=True)
                ctx.add_process(self.proc)
            def stop(self):
                self.proc.wait(timeout=35)
                self.log.close()
        self.bindings.EvtestCapture = Capture
        ctx = self.bindings.Ctx(str(self.tree), self.case / label)
        ctx.output.mkdir()
        ctx.owned_register = self.lifecycle.track
        node = self.bindings._xremap_device_node(ctx)
        self.check(node is not None, label + ": deployed remapper device missing")
        primary = None
        launcher_chord_sent = False
        try:
            if node is not None:
                self.bindings.leg_k1_terminal(ctx, node)
            self.check(not self.bindings.launcher_open_probe(ctx), label + ": launcher already open before chord")
            ctx.await_injection(label + "-open", [self.bindings._qmp(["alt", "spc"], 200)])
            launcher_chord_sent = True
            opened = self.bindings.launcher_open_probe(ctx)
            ctx.check(opened, "native launcher did not open after actual deployment")
            if opened:
                self.bindings._grim(ctx, "launcher.png", region=self.bindings.L1_PANEL_REGION)
                ctx.await_injection(label + "-close", [self.bindings._qmp(["alt", "spc"], 200)])
                launcher_chord_sent = False
                ctx.check(not self.bindings.launcher_open_probe(ctx), "native launcher did not close")
        except Exception as error:
            primary = error
        finally:
            cleanup = []
            if launcher_chord_sent:
                try:
                    ctx.await_injection(label + "-close-after-observation", [self.bindings._qmp(["alt", "spc"], 200)])
                    if self.bindings.launcher_open_probe(ctx):
                        raise HarnessBlocked("native launcher did not release scoped grab after paired close chord")
                except Exception as error:
                    cleanup.append("paired launcher close: " + repr(error))
            try:
                ctx.restore_all()
            except Exception as error:
                cleanup.append(repr(error))
            self.failures.extend(label + ": " + error for error in ctx.failures)
            atomic_json(ctx.output / "result.json", {"failures": ctx.failures, "notes": ctx.notes,
                        "primary_error": repr(primary) if primary else None, "cleanup_errors": cleanup})
            if cleanup:
                raise HarnessBlocked("consumer cleanup failed; " + repr(primary) + "; " + repr(cleanup))
        if primary:
            raise primary

    def restore(self):
        self.lifecycle.assert_quiet()
        if self.stop_failed:
            raise HarnessBlocked("refusing restoration after failed stop/IPC")
        if not (getattr(self, "live_started", False) or getattr(self, "global_mutation", False)):
            return {"live_mutation": False}
        stopped = run(["systemctl", "--user", "stop", "xremap-atmosphera.service"])
        if stopped.returncode:
            raise RuntimeError(stopped.stderr)
        unit_changed = any(r["path"].endswith("/xremap-atmosphera.service") and not self.snapshot.matches(r)
                           for r in self.snapshot.records)
        restored = self.snapshot.restore(self.lifecycle)
        # Only the consumer test's explicitly touched XDG key may be restored;
        # unexpected manager changes are a conflict, not an automatic overwrite.
        old = dict(l.split("=", 1) for l in self.manager_environment.stdout.splitlines() if "=" in l)
        current_result = run(["systemctl", "--user", "show-environment"])
        if current_result.returncode:
            raise RuntimeError(current_result.stderr)
        current = dict(l.split("=", 1) for l in current_result.stdout.splitlines() if "=" in l)
        if {k:v for k,v in current.items() if k != "XDG_CONFIG_HOME"} != {k:v for k,v in old.items() if k != "XDG_CONFIG_HOME"}:
            raise HarnessBlocked("foreign user-manager environment change; no implicit restoration winner")
        if current.get("XDG_CONFIG_HOME") != old.get("XDG_CONFIG_HOME"):
            args = ["set-environment", "XDG_CONFIG_HOME=" + old["XDG_CONFIG_HOME"]] if "XDG_CONFIG_HOME" in old else ["unset-environment", "XDG_CONFIG_HOME"]
            p = run(["systemctl", "--user", *args])
            if p.returncode:
                raise RuntimeError(p.stderr)
            unit_changed = True
        if unit_changed:
            reload = run(["systemctl", "--user", "daemon-reload"])
            if reload.returncode:
                raise RuntimeError("original unit manager reload failed: " + reload.stderr)
        config_root = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
        env = self.ctx.env({"NIRI_LOAD_CONFIG": str(config_root / "niri/atmosphera-session.kdl")})
        p = run(["qs", "-p", str(HERE / "fixtures/niri-load-config.qml")], env=env, timeout=30)
        if p.returncode or "NIRI_LOAD|OK|" not in p.stdout + p.stderr:
            raise RuntimeError("original typed niri handoff not accepted: " + p.stdout + p.stderr)
        if self.states["xremap"] == "active":
            subprocess.run(["systemctl", "--user", "start", "xremap-atmosphera.service"], check=True)
        if self.states["keyd"] == "active":
            subprocess.run(["busctl", "call", "--system", "org.freedesktop.systemd1", "/org/freedesktop/systemd1",
                            "org.freedesktop.systemd1.Manager", "StartUnit", "ss",
                            "atmosphera-keyd-reload.service", "replace"], check=True,
                           stdout=subprocess.DEVNULL)
        assert run(["systemctl", "--user", "is-active", "xremap-atmosphera.service"]).stdout.strip() == self.states["xremap"]
        assert run(["systemctl", "is-active", "keyd.service"]).stdout.strip() == self.states["keyd"]
        assert all(self.snapshot.matches(r) for r in self.snapshot.records), "post-handoff baseline drift"
        for path, command in self.desktop.items():
            assert Path(path).read_bytes().hex() == command, "original desktop process changed"
        self.workspace.profile.console.verify(required=True)
        restored.update(services=self.states, desktop=self.desktop, typed_original_config_handoff="Accepted",
                        limits="No whole-desktop/clipboard/independent activation claim")
        atomic_json(self.case / "restoration.json", restored)
        self.live_started = False
        self.global_mutation = False
        return restored

    def settings(self, consumers=True):
        self.start("settings")
        self.mouse("settings-first", 300, 637)
        self.settle("macos")
        data = self.observation("first-deployment")
        self.check(data["layer"] and data["include"] and data["xremap"] == "active", "first deployment omitted layer/activation/remapper")
        if consumers:
            self.endpoints("first-endpoints")
        # Existing-layer and reverse-transition legs use the same running UI.
        self.mouse("settings-none", 300, 400)
        self.settle("none")
        data = self.observation("none")
        self.check(not data["include"] and data["xremap"] == "inactive", "none transition left active macOS state")
        self.mouse("settings-redeploy", 300, 637)
        self.settle("macos")
        data = self.observation("redeploy")
        self.check(data["include"] and data["xremap"] == "active", "existing-layer redeployment failed")
        if consumers:
            self.endpoints("redeploy-endpoints")

    def wizard_selection(self, advance=True):
        binding_file = self.config / "settings/bindings.json"
        before = binding_file.read_bytes()
        wrapper = Path.home() / ".config/niri/atmosphera-session.kdl"
        wrapper_before = wrapper.read_bytes()
        handoffs = sum(e["event"] == "handoff" for e in self.events())
        # Real compositor viewport adjustment, not a layout/source repair.
        run(["niri", "msg", "action", "maximize-column"], env=self.env, check=True)
        for i in range(4):
            self.mouse(f"wizard-next-{i}", 1010, 690)
        self.mouse("wizard-select", 400, 380)
        state = self.status("staged-wizard-choice")
        self.check(state["detail"]["wizardChoice"] == "macos", "physical selection did not reach the wizard's staged choice")
        self.check(binding_file.read_bytes() == before, "wizard persisted bindings before Finish")
        self.check(wrapper.read_bytes() == wrapper_before, "wizard deployed/generated before Finish")
        self.check(sum(e["event"] == "handoff" for e in self.events()) == handoffs, "wizard sent a typed handoff before Finish")
        if advance:
            self.mouse("wizard-dock", 1025, 690)

    def wizard_local_lifecycle(self):
        self.start("wizard-local-lifecycle", "wizard")
        self.wizard_selection(advance=False)
        binding = self.config / "settings/bindings.json"
        before = binding.read_bytes()
        handoffs = sum(e["event"] == "handoff" for e in self.events())
        self.mouse("wizard-local-reset", 205, 690)
        reset = self.status("local-reset")
        self.check(reset["detail"]["wizardChoice"] == "none", "wizard-local Reset did not reset staged selection")
        self.check(binding.read_bytes() == before and sum(e["event"] == "handoff" for e in self.events()) == handoffs,
                   "wizard-local Reset persisted/deployed before submission")
        self.mouse("wizard-select", 400, 380)
        selected = self.status("local-reselected")
        self.check(selected["detail"]["wizardChoice"] == "macos", "staged re-selection was lost")
        marker, fifo = self.gate("wizard-submission-held", "atmosphera-bindings-apply", "true")
        try:
            self.mouse("wizard-local-skip", 120, 690)
            self.wait(marker.exists, "Skip's captured submission at deployment")
            submitted = self.status("submitted-skip")["detail"]["wizardSubmitted"]
            self.check(submitted is not None and submitted["environment"] == "macos", "Skip did not capture the staged work")
            identity = submitted["id"] if submitted else ""
            self.ipc("wizardClose")
            self.check(not self.status("unloaded-skip")["detail"]["wizardOpen"], "wizard did not unload after explicit close")
            self.ipc("wizardOpen")
            reopened = self.status("reopened-skip")["detail"]
            self.check(reopened["wizardOpen"] and reopened["wizardOutstanding"] and reopened["wizardSubmitted"]
                       and reopened["wizardSubmitted"]["id"] == identity and reopened["wizardChoice"] == "macos",
                       "close/reopen discarded or duplicated captured submitted work")
            self.check(not any(e["event"] == "wizard-closed" and e["queue"]["state"] == "Idle"
                               and e["queue"]["queueCount"] == 0 for e in self.events()), "submission completed while its helper was held")
        finally:
            if marker.exists(): self.release(fifo)
        self.wait(lambda: any(e["event"] == "handoff" and e["detail"]["requestId"] == identity and e["detail"]["success"]
                             for e in self.events()), "captured Skip handoff after reopen")
        self.wait(lambda: not self.status("skip-final")["detail"]["wizardOpen"], "own result closes reattached wizard")
        self.check(sum(e["event"] == "handoff" and e["detail"]["requestId"] == identity for e in self.events()) == 1,
                   "reattachment duplicated the submission completion")

    def wizard(self, consumers=True):
        self.start("wizard", "wizard")
        self.wizard_selection()
        self.mouse("wizard-finish", 1025, 690)
        self.settle("macos")
        data = self.observation("finished")
        self.check(data["layer"] and data["include"] and data["xremap"] == "active", "wizard completion omitted the deployed layer")
        if consumers:
            self.endpoints("wizard-endpoints")

    def callback(self, token, event="callback"):
        matching = [e["detail"] for e in self.events()
                    if e["event"] == event and e["detail"]["token"] == token]
        return matching[-1] if matching else None

    def wait_callback(self, token, event="callback"):
        self.wait(lambda: self.callback(token, event) is not None, token + " completion")
        self.check(sum(e["event"] == event and e["detail"].get("token") == token
                       for e in self.events()) == 1, token + ": callback was delivered more than once")
        return self.callback(token, event)

    def native_gate(self, name, phase, section, *, file=None, **facts):
        marker = self.case / (name + "-entered")
        fifo = self.case / (name + "-release")
        os.mkfifo(fifo, 0o600)
        self.native_rules.append(dict(phase=phase, file=str(file or self.config / "settings" / (section + ".json")),
                                      marker=str(marker), gate=str(fifo), **facts))
        atomic_json(self.native_schedule, {"rules": self.native_rules})
        self.gates.append((marker, fifo))
        return marker, fifo

    def native_fault(self, name, phase, sections):
        enabled = self.case / (name + "-enabled")
        enabled.touch(mode=0o600)
        markers = []
        for section in sections:
            marker = self.case / (name + "-" + section + "-entered")
            self.native_rules.append(dict(phase=phase, file=str(self.config / "settings" / (section + ".json")),
                marker=str(marker), enabled=str(enabled), repeat=True, error="controlled-native-" + name))
            markers.append(marker)
        atomic_json(self.native_schedule, {"rules": self.native_rules})
        return enabled, markers

    def gate(self, name, executable, condition, after=False):
        # Fault injection stays in this case's disposable tree. The real
        # executable runs after an explicit FIFO release, never after a sleep.
        marker, fifo = self.case / (name + "-entered"), self.case / (name + "-release")
        os.mkfifo(fifo)
        wrapper = self.tree / "Scripts/bash" / executable
        if wrapper.exists():
            real = wrapper.with_name(wrapper.name + ".real")
            wrapper.rename(real)
        else:
            real = Path(shutil.which(executable))
        quote = shlex.quote
        wrapper.write_text("#!/usr/bin/env bash\nset -eu\n"
                           f"if {condition} && [ ! -e {quote(str(marker))} ]; then\n"
                           f"  : > {quote(str(marker))}\n"
                           + (f"  umask 077\n  {quote(str(real))} \"$@\" > {quote(str(marker))}.payload\n" if after else "") +
                           f"  IFS= read -r release < {quote(str(fifo))}\nfi\n"
                           f"exec {quote(str(real))} \"$@\"\n")
        if after:
            text = wrapper.read_text()
            text = text.replace("\nfi\nexec", f"\n  cat {quote(str(marker))}.payload\n  exit 0\nfi\nexec")
            wrapper.write_text(text)
        wrapper.chmod(0o755)
        self.gates.append((marker, fifo))
        return marker, fifo

    def release(self, fifo, failure=False):
        # The reader's marker proves it has reached the gate. Nonblocking open
        # keeps a broken test from hanging without a restoration checkpoint.
        fd = os.open(fifo, os.O_WRONLY | os.O_NONBLOCK)
        try:
            os.write(fd, b"1\n" if failure else b"0\n")
        finally:
            os.close(fd)

    def save_failure(self):
        self.start("save-failure")
        directory = self.config / "settings"
        before = sha(Path.home() / ".config/niri/atmosphera-session.kdl")
        mode = directory.stat().st_mode & 0o7777
        try:
            directory.chmod(0o555)
            self.ipc("request", "macos", "failed-save")
            result = self.wait_callback("failed-save")
            self.check(not result["success"] and result["error"] == "lock-failed"
                       and result["state"] == "Stopped", "specific unwritable-directory I/O failure was not propagated before callback")
            self.check(not any(e["event"] == "stage" and e["detail"]["requestId"] == result["requestId"]
                       and e["detail"]["attemptId"] == result["attemptId"]
                       and e["detail"]["stage"] in ("deploy", "generate-handoff") for e in self.events()),
                       "failed persistence advanced into deployment/handoff")
            self.check(sha(Path.home() / ".config/niri/atmosphera-session.kdl") == before,
                       "save failure activated a session")
            self.check(not (Path.home() / ".config/niri/atmosphera-shortcuts-macos.kdl").exists(),
                       "save failure launched deployment")
            retained = self.status("retained-save")
            self.check(retained["environment"] == "macos", "failed save discarded the selected state")
        finally:
            directory.chmod(mode)
        self.ipc("retry", "save-retry")
        retry = self.wait_callback("save-retry")
        self.check(retry["success"] and retry["requestId"] == result["requestId"]
                   and retry["attemptId"] == result["attemptId"] + 1, "failed persistence did not retry the same captured head/new attempt")
        self.check(self.observation("retry")["include"], "save retry did not reach activation")

    def wizard_failure(self):
        self.start("wizard-failure", "wizard")
        self.wizard_selection()
        template = self.tree / "Bindings/environments/macos/niri/atmosphera-shortcuts-macos.kdl"
        hidden = template.with_suffix(".held")
        template.rename(hidden)
        try:
            self.mouse("wizard-failed-finish", 1025, 690)
            self.wait(lambda: any(e["event"] == "handoff" and not e["detail"]["success"]
                                 for e in self.events()), "actual deployment failure")
            self.ipc("status", "failed-wizard")
            self.wait(lambda: any(e["event"] == "status" and e["detail"]["token"] == "failed-wizard"
                                 for e in self.events()), "wizard failure state")
            state = next(e for e in self.events() if e["event"] == "status"
                         and e["detail"]["token"] == "failed-wizard")
            self.check(state["detail"]["wizardOpen"] and state["detail"]["wizardChoice"] == "macos",
                       "deployment failure closed the wizard or discarded its selection")
            self.check(not any(e["event"] == "wizard-closed" for e in self.events()),
                       "wizard closed before successful deployment")
            self.check(not self.observation("failed")["include"], "failed deployment activated the macOS layer")
        finally:
            hidden.rename(template)
        self.mouse("wizard-retry-finish", 1025, 690)
        self.settle("macos")
        self.wait(lambda: any(e["event"] == "wizard-closed" for e in self.events()), "wizard retry closure")
        self.check(self.observation("retried")["include"], "wizard retry omitted activation")

    def pending_edits(self):
        self.start("pending-edits")
        marker, fifo = self.native_gate("persist", "rename", "ui")
        try:
            self.ipc("editScale", "1.2")
            self.wait(marker.exists, "in-flight settings write")
            self.ipc("save", "first-barrier")
            self.ipc("editScale", "1.7")
            self.ipc("save", "latest-barrier")
            self.ipc("save", "empty-barrier")
            self.check(all(self.callback(token, "save-callback") is None
                           for token in ("first-barrier", "latest-barrier", "empty-barrier")),
                       "save completed while an earlier write was still pending")
        finally:
            if marker.exists():
                self.release(fifo)
        for token in ("first-barrier", "latest-barrier", "empty-barrier"):
            self.check(self.wait_callback(token, "save-callback")["success"], token + " failed")
        value = json.loads((self.config / "settings/ui.json").read_text())["fontDefaultScale"]
        self.check(value == 1.7, "later in-flight edit was lost from disk")
        self.ipc("status", "pending-consumer")
        self.wait(lambda: any(e["event"] == "status" and e["detail"]["token"] == "pending-consumer"
                             for e in self.events()), "pending edit consumer")
        self.check(next(e["detail"]["scale"] for e in self.events() if e["event"] == "status"
                        and e["detail"]["token"] == "pending-consumer") == 1.7,
                   "later in-flight edit was lost from the consumer")

    def queued_save_failure(self):
        self.start("queued-save-failure")
        marker, fifo = self.native_gate("failed-persist", "rename", "ui")
        try:
            self.ipc("editScale", "1.2")
            self.wait(marker.exists, "failing in-flight write")
            self.ipc("save", "failed-revision")
            self.ipc("editScale", "1.7")
            self.ipc("save", "later-revision")
            before_release = self.private_state("queued-save-before-failure")
            self.check(all(self.callback(token, "save-callback") is None for token in ("failed-revision", "later-revision")),
                       "queued saves were not pending behind the original held publication")
        finally:
            if marker.exists():
                self.release(fifo, failure=True)
        receipts = {}
        for token in ("failed-revision", "later-revision"):
            receipts[token] = self.wait_callback(token, "save-callback")
            self.check(receipts[token]["success"], token + ": native later save did not retry/cover the requested work")
        first, later = (receipts[token]["receipt"] for token in ("failed-revision", "later-revision"))
        after = self.private_state("queued-save-after-replies")
        ui_inputs = [row for row in before_release["native"]["inputs"] if row["path"] == ["ui", "fontDefaultScale"]]
        self.check(len(ui_inputs) == 2, "queued original/later UI inputs were not captured separately")
        old_input, new_input = (int(row["sequence"]) for row in ui_inputs)
        # Integration decision20: later ordinary requests own their attempts;
        # they do not inherit the earlier publication's terminal failure.
        self.check(first["status"] == "saved" and old_input <= int(first["inputPrefix"]) < new_input and
                   any(p["sourceId"] == "ui" and p["success"] for p in first["publications"]) and
                   later["status"] in ("saved", "nothing_to_save") and int(later["inputPrefix"]) >= new_input and
                   int(later["requestId"]) > int(first["requestId"]), "queued native receipts lost their actual attempts/prefixes")
        self.check(any(f["status"] == "failed" and old_input <= int(f["inputPrefix"]) < new_input and f["code"] == "controlled-native-rename"
                       for f in after["native"]["failures"]), "later native retry erased the original failed publication")
        atomic_json(self.case / "queued-save-failure-assertion.json", {"before_release": before_release,
            "decision": 20, "receipts": receipts, "after": after,
            "disk": json.loads((self.config / "settings/ui.json").read_text())})
        self.check(json.loads((self.config / "settings/ui.json").read_text())["fontDefaultScale"] == 1.7,
                   "a failed earlier write discarded the later revision")
        self.ipc("save", "after-failure")
        self.check(self.wait_callback("after-failure", "save-callback")["success"],
                    "failure from a completed batch poisoned a later save")
        self.restart_fixture()
        self.check(self.status("queued-save-cold-consumer")["detail"]["scale"] == 1.7,
                   "latest queued choice did not reach the cold consumer")

    def fifo(self, generation=False):
        self.start("fifo-generation" if generation else "fifo-deployment")
        if generation:
            marker, fifo = self.gate("fifo-generation", "sh", '[[ "${2:-}" == *"Base config detected at niri boot"* ]]')
        else:
            marker, fifo = self.gate("fifo-deploy", "atmosphera-bindings-apply", "true")
        wrapper = self.tree / "Scripts/bash/atmosphera-bindings-apply"
        real = wrapper.with_name(wrapper.name + ".real")
        if generation:
            wrapper.rename(real)
            wrapper.write_text("#!/usr/bin/env bash\nset -eu\nexec " + shlex.quote(str(real)) + ' "$@"\n')
            wrapper.chmod(0o755)
        ledger = self.case / "helper-ledger.log"
        wrapper.write_text(wrapper.read_text().replace(
            "exec " + shlex.quote(str(real)) + ' "$@"',
            "printf '%s\\n' \"${2:-missing-captured-environment}\" >> " + shlex.quote(str(ledger))
            + '\nexec ' + shlex.quote(str(real)) + ' "$@"'))
        tokens = ("fifo-first", "fifo-none", "fifo-last", "fifo-repeat")
        try:
            self.ipc("request", "macos", tokens[0])
            self.wait(marker.exists, "held head deployment")
            self.ipc("request", "none", tokens[1])
            self.ipc("status", "tail-held")
            self.wait(lambda: any(e["event"] == "status" and e["detail"]["token"] == "tail-held" for e in self.events()), "held tail status")
            state = next(e for e in reversed(self.events()) if e["event"] == "status"
                         and e["detail"]["token"] == "tail-held")
            self.check(state["environment"] == "macos", "later choice mutated the running head's shared adapter")
            self.check(json.loads((self.config / "settings/bindings.json").read_text())["environment"] == "macos",
                       "later choice reached persistence while the head was held")
            self.ipc("request", "macos", tokens[2])
            self.ipc("request", "macos", tokens[3])
            self.check(not any(self.callback(token) for token in tokens), "a request completed while the head was held")
        finally:
            if marker.exists():
                self.release(fifo)
        attempts = []
        for token, choice in zip(tokens, ("macos", "none", "macos", "macos")):
            result = self.wait_callback(token)
            self.check(result["success"], token + ": captured request was skipped or superseded")
            attempts.append((result["requestId"], result["attemptId"]))
            handoffs = [e for e in self.events() if e["event"] == "handoff"
                        and e["detail"]["requestId"] == result["requestId"] and e["detail"]["attemptId"] == result["attemptId"]]
            self.check(len(handoffs) == 1 and handoffs[0]["detail"]["selected"] == choice,
                       token + ": typed accepted-handoff identity/value mismatch")
            stages = [e["detail"]["stage"] for e in self.events() if e["event"] == "stage"
                      and (e["detail"]["requestId"], e["detail"]["attemptId"]) == attempts[-1]]
            self.check(stages == ["save", "deploy", "generate-handoff"], token + ": incomplete/out-of-order stages " + repr(stages))
        self.check(len({i for i, a in attempts}) == 4, "repeated choices were deduplicated into one identity")
        completed = [e["detail"]["token"] for e in self.events() if e["event"] == "callback"
                     and e["detail"]["token"] in tokens]
        self.check(completed == list(tokens), "callbacks were not delivered once in FIFO order")
        deployed = ledger.read_text().splitlines()
        self.check(deployed == ["macos", "none", "macos", "macos"], "helper choices were combined/replaced: " + repr(deployed))
        (self.case / "fifo-observation.json").write_text(json.dumps(
            {"callbacks": completed, "deployed": deployed, "events": self.events()}, indent=2))

    def failure_retention(self):
        self.start("review-errors")
        marker, fifo = self.gate("failed-head", "atmosphera-bindings-apply", "true")
        wrapper = self.tree / "Scripts/bash/atmosphera-bindings-apply"
        wrapper.write_text(wrapper.read_text().replace("fi\nexec", "  exit 17\nfi\nexec"))
        try:
            self.ipc("request", "macos", "failed-head")
            self.wait(marker.exists, "held failing head")
            self.ipc("request", "none", "waiting-tail")
        finally:
            if marker.exists():
                self.release(fifo)
        result = self.wait_callback("failed-head")
        self.check(not result["success"] and result["state"] == "Stopped", "failure did not install Stopped before callback")
        self.ipc("status", "stopped-head")
        self.wait(lambda: any(e["event"] == "status" and e["detail"]["token"] == "stopped-head" for e in self.events()), "stopped head status")
        state = next(e for e in reversed(self.events()) if e["event"] == "status"
                     and e["detail"]["token"] == "stopped-head")
        self.check(state["detail"]["owner"].get("queueCount") == 2, "failed head/tail were not retained")
        self.check(self.callback("waiting-tail") is None, "failure advanced into the waiting tail")
        failed_id, failed_attempt = result["requestId"], result["attemptId"]
        self.check(state["detail"]["owner"].get("headRequestId") == failed_id, "failure replaced retained head identity")
        self.ipc("request", "macos", "appended-while-stopped")
        self.ipc("status", "still-stopped")
        self.wait(lambda: any(e["event"] == "status" and e["detail"]["token"] == "still-stopped" for e in self.events()), "stopped enqueue status")
        state = next(e for e in reversed(self.events()) if e["event"] == "status"
                     and e["detail"]["token"] == "still-stopped")
        self.check(state["detail"]["owner"].get("state") == "Stopped", "new enqueue implicitly resumed a stopped queue")
        self.ipc("retry", "head-retry")
        retry = self.wait_callback("head-retry")
        self.check(retry["success"] and retry["requestId"] == failed_id and retry["attemptId"] == failed_attempt + 1,
                   "explicit Retry did not retain the same head with a new attempt")
        self.check(self.wait_callback("waiting-tail")["success"], "retained tail did not run after head retry")
        self.check(self.wait_callback("appended-while-stopped")["success"], "appended work was lost")
        self.check(sum(e["event"] == "callback" and e["detail"]["token"] == "failed-head"
                       for e in self.events()) == 1, "Retry repeated the failed attempt's callback")

    def status(self, token):
        before = sum(e["event"] == "status" and e["detail"]["token"] == token for e in self.events())
        self.ipc("status", token)
        self.wait(lambda: sum(e["event"] == "status" and e["detail"]["token"] == token for e in self.events()) > before, token)
        return next(e for e in reversed(self.events()) if e["event"] == "status" and e["detail"]["token"] == token)

    def io_failure(self, stage):
        self.start("io-failure-" + stage)
        marker, fifo = self.native_gate("failed-" + stage, "write" if stage == "prepare" else "rename", "bindings")
        try:
            self.ipc("request", "macos", "io-head")
            self.wait(marker.exists, "held I/O " + stage)
            self.ipc("request", "none", "io-tail")
        finally:
            if marker.exists(): self.release(fifo, failure=True)
        result = self.wait_callback("io-head")
        self.check(not result["success"] and result["state"] == "Stopped", stage + " did not stop before callback")
        self.ipc("editScale", "1.45")
        self.ipc("save", "held-full-save")
        self.check(not self.wait_callback("held-full-save", "save-callback")["success"], "full save hid stopped bindings")
        self.check(self.callback("io-tail") is None, "I/O failure advanced the tail")
        self.check(json.loads((self.config / "settings/ui.json").read_text())["fontDefaultScale"] == 1.45,
                   "unrelated ordinary save was lost")
        self.ipc("retry", "io-retry")
        self.check(self.wait_callback("io-retry")["success"], stage + " retry failed")
        self.check(self.wait_callback("io-tail")["success"], stage + " retained tail was lost")

    def conflict(self):
        self.start("prepared-conflict")
        marker, fifo = self.native_gate("prepared-held", "rename", "bindings")
        original = (self.config / "settings/bindings.json").read_bytes()
        try:
            self.ipc("request", "macos", "conflict-head")
            self.wait(marker.exists, "prepared content before promotion")
            self.ipc("request", "none", "conflict-tail")
            external = {"environment": "none", "futureRaw": {"retain": [1, 2, 3]}}
            target = self.config / "settings/bindings.json"
            temporary = target.with_suffix(".external")
            temporary.write_text(json.dumps(external) + "\n")
            temporary.replace(target)
        finally:
            if marker.exists(): self.release(fifo)
        self.check(not self.wait_callback("conflict-head")["success"], "prepared stale content overwrote external data")
        self.check(json_equal(json.loads(target.read_text()), external), "accepted unknown/raw data was discarded")
        self.ipc("retry", "unresolved-conflict")
        self.check(not self.wait_callback("unresolved-conflict")["success"], "Retry silently authorized overwrite/merge")
        self.check(json_equal(json.loads(target.read_text()), external), "Retry discarded foreign data")
        target.write_bytes(original)  # explicit user resolution, not owner rollback
        self.ipc("retry", "resolved-conflict")
        self.check(self.wait_callback("resolved-conflict")["success"], "explicitly resolved head could not retry")
        self.check(self.wait_callback("conflict-tail")["success"], "conflict tail was not retained")

    def audit_state(self, token):
        before = sum(e["event"] == "audit-state" and e["detail"]["token"] == token for e in self.events())
        self.ipc("auditState", token)
        self.wait(lambda: sum(e["event"] == "audit-state" and e["detail"]["token"] == token
                             for e in self.events()) > before, token)
        return next(e["detail"] for e in reversed(self.events())
                    if e["event"] == "audit-state" and e["detail"]["token"] == token)

    def capture_operation(self, aba=False):
        def gate_debounce():
            settings = self.tree / "Commons/SettingsStore.qml"
            text = settings.read_text()
            original = '  autoSave: true'
            if text.count(original) != 1:
                raise HarnessBlocked("ordinary debounce seam is not uniquely characterized")
            settings.write_text(text.replace(original,
                '  autoSave: false // HARNESS_CAPTURE_CLOCK_GATE: explicit saves remain real.'))
        self.start("capture-operation-ABA" if aba else "capture-operation-held", before_launch=gate_debounce)
        marker, fifo = self.native_gate("capture-old-publication", "rename", "ui")
        target = self.config / "settings/ui.json"
        latest = 1.25 if aba else 1.75
        try:
            self.ipc("auditSaveScale", "1.25", "old-write")
            self.wait(marker.exists, "old captured ordinary write held before publication")
            original = self.private_state("old-native-capture-held")
            frozen = original["frozenCapture"]
            self.check(frozen["requestId"] in original["native"]["pendingRequests"],
                       "held original save is not pending in the actual owner")
            if aba:
                self.ipc("auditCaptureABA", "1.75", "1.25")
            else:
                self.ipc("auditCaptureScale", "1.75")
            captured = self.private_state("newer-capture-before-old-completion")
            self.check(captured["frozenCapture"] == frozen and
                       int(captured["native"]["inputPrefix"]) == int(frozen["inputPrefix"]) + (2 if aba else 1),
                       "newer local inputs were not captured independently of the held save")
            self.check(captured["current"]["consumer"]["uiScale"] == latest,
                       "newer local input did not reach the held-write consumer")
        finally:
            if marker.exists(): self.release(fifo)
        old = self.wait_callback("old-write", "save-callback")
        self.check(old["success"], "held original ordinary save failed")
        old_identity = target.stat().st_ino
        completed = self.private_state("newer-capture-after-old-completion")
        self.check(old["receipt"]["requestId"] == frozen["requestId"] and
                   old["receipt"]["inputPrefix"] == frozen["inputPrefix"] and
                   completed["native"]["inputPrefix"] == captured["native"]["inputPrefix"] and
                   json.loads(target.read_text())["fontDefaultScale"] == 1.25,
                   "held save changed capture or automatic enqueue masked its completion boundary")
        self.check(completed["native"]["inputs"] == captured["native"]["inputs"] and
                   completed["current"]["consumer"]["uiScale"] == latest,
                   "old write completion erased a newer captured operation")
        self.ipc("save", "later-capture-save")
        later = self.wait_callback("later-capture-save", "save-callback")
        actual_raw = target.read_text()
        actual = json.loads(actual_raw)
        consumer = self.private_state("capture-final-consumer")
        atomic_json(self.case / "capture-operation-outcome.json", {
            "aba": aba, "captured": captured, "after_old": completed, "old_callback": old,
            "later_callback": later, "expected": {"fontDefaultScale": latest},
            "actual": actual, "actual_raw": actual_raw, "consumer": consumer,
            "old_inode": old_identity, "final_inode": target.stat().st_ino})
        self.check(later["success"], "later save of retained capture failed")
        self.check(json_equal(actual, {"fontDefaultScale": latest}), "newer captured operation did not reach disk")
        self.check(consumer["current"]["consumer"]["uiScale"] == latest and
                   later["receipt"]["inputPrefix"] == captured["native"]["inputPrefix"],
                   "newer capture did not reach the Settings consumer/save prefix")
        if aba:
            self.check(target.stat().st_ino != old_identity, "same-path ABA capture was silently erased without its later publication")

    def failed_ordinary(self, new_edit=False):
        original = {"fontDefaultScale": 1.0, "futureRaw": {"original": [False, 0, ""]}}
        def seed():
            (self.config / "settings/ui.json").write_text(json.dumps(original) + "\n")
        self.start("failed-ordinary-new-edit" if new_edit else "failed-ordinary", before_launch=seed)
        target = self.config / "settings/ui.json"
        original_bytes = target.read_bytes()
        directory = target.parent
        try:
            directory.chmod(0o555)
            self.ipc("auditSaveScale", "1.3", "ordinary-first-failure")
            first = self.wait_callback("ordinary-first-failure", "save-callback")
            self.check(not first["success"], "ordinary permission failure was not established")
        finally:
            directory.chmod(0o755)
        captured = self.private_state("ordinary-original-capture")
        frozen = captured["frozenCapture"]
        self.check(frozen["requestId"] == first["receipt"]["requestId"] and
                   frozen["inputPrefix"] == first["receipt"]["inputPrefix"],
                   "ordinary capture identity/prefix observation was not established")
        external = {"fontDefaultScale": 1.0, "futureRaw": {"foreign": [None, False, 0, ""]}}
        count = sum(e["event"] == "settings-reloaded" for e in self.events())
        temp = target.with_suffix(".external")
        temp.write_text(json.dumps(external) + "\n"); temp.replace(target)
        self.wait(lambda: sum(e["event"] == "settings-reloaded" for e in self.events()) > count,
                  "foreign observation after ordinary failure")
        terminal = len(self.events())
        # Arm a real, fresh unrelated edit's debounce after foreign acceptance;
        # the original edit's timer may have already fired during the first fault.
        self.ipc("auditEdit", "general.scaleRatio", "1.25")
        self.wait(lambda: any(e["event"] == "native-save-completed" and e["detail"]["status"] == "saved" and
                              any(c["path"] == ["general", "scaleRatio"] for c in e["detail"]["coverage"])
                              for e in self.events()[terminal:]), "actual general input's saved debounce coverage")
        after_debounce = json.loads(target.read_text())
        if new_edit:
            self.ipc("auditCaptureScale", "1.7")
        self.ipc("auditEdit", "general.scaleRatio", "1.25")
        self.ipc("save", "ordinary-unrelated-save")
        unrelated = self.wait_callback("ordinary-unrelated-save", "save-callback")
        actual = json.loads(target.read_text())
        observed = self.audit_state("ordinary-after-foreign-save")
        expected_local = dict(external, fontDefaultScale=1.7 if new_edit else 1.3)
        atomic_json(self.case / "ordinary-foreign-assertion.json", {"new_edit": new_edit, "decision": 20,
            "first_callback": first, "captured": captured, "expected": expected_local, "foreign": external,
            "after_debounce": after_debounce, "actual": actual, "callback": unrelated, "observed": observed})
        self.check(json_equal(after_debounce, dict(external, fontDefaultScale=1.3)),
                   "native debounce retry lost the pending local choice or foreign unknown data")
        self.check(json_equal(actual, expected_local), "native full save lost the latest local choice or foreign other-path data")
        self.check(unrelated["success"] and unrelated["receipt"]["status"] in ("saved", "nothing_to_save"),
                   "successful native retry/rebase was not acknowledged truthfully")
        owned = self.private_state("ordinary-retained-owner")
        self.check(owned["frozenCapture"] == frozen and owned["native"]["inputs"][:len(frozen["inputs"])] == frozen["inputs"] and
                   any(failure["requestId"] == frozen["requestId"] for failure in owned["native"]["failures"]),
                   "failed ordinary input identity/fingerprint tuple changed or lost its failure record")
        self.check(json.loads((self.config / "settings/general.json").read_text())["scaleRatio"] == 1.25,
                   "unrelated ordinary section did not persist")
        target.write_bytes(original_bytes)  # After acknowledgement this is a newer external choice, not Retry.
        self.ipc("save", "ordinary-explicit-resolution")
        resolved = self.wait_callback("ordinary-explicit-resolution", "save-callback")
        self.ipc("auditRead", "ui", "ordinary-post-ack-external-read", "normal")
        self.check(self.wait_callback("ordinary-post-ack-external-read", "audit-read")["success"], "post-ack external choice was not admitted")
        expected = original
        final = json.loads(target.read_text())
        atomic_json(self.case / "ordinary-resolution-assertion.json", {
            "expected": expected, "actual": final, "callback": resolved,
            "consumer": self.audit_state("ordinary-resolved-consumer")})
        self.check(resolved["success"] and json_equal(final, expected), "clean save resurrected acknowledged work over the newer external choice")
        self.check(self.audit_state("ordinary-resolution-live-consumer")["uiScale"] == expected["fontDefaultScale"],
                   "post-ack external choice did not reach the live consumer")
        self.ipc("auditEdit", "general.scaleRatio", "1.35")
        self.ipc("save", "ordinary-later-clean-save")
        self.check(self.wait_callback("ordinary-later-clean-save", "save-callback")["success"],
                   "completed ordinary failure poisoned a genuinely later save")
        self.check(json_equal(json.loads(target.read_text()), expected), "later save replayed stale ordinary bytes")
        self.restart_fixture()
        self.check(self.audit_state("ordinary-post-ack-cold-consumer")["uiScale"] == 1.0 and
                   json_equal(json.loads(target.read_text()), expected), "post-ack external choice did not survive cold restart")

    def read_ownership(self, throwing=False):
        def seed():
            (self.config / "settings/ui.json").write_text('{"fontDefaultScale":1.0}\n')
        self.start("read-callback-owner" if throwing else "reversed-inspectors", before_launch=seed)
        target = self.config / "settings/ui.json"
        held = None
        route_active = True
        self.ipc("nativePacketsBegin")
        def packets():
            return json.loads(self.ipc("nativePackets"))
        def reads(value):
            return [row for row in packets() if row["operation"] == "reload" and row["status"] == "reloaded"
                    and row["values"].get("ui.fontDefaultScale") == value]
        try:
            self.ipc("auditRead", "ui", "old-read", "throw" if throwing else "normal")
            self.wait(lambda: bool(reads(1.0)), "actual old native inspection packet held before delivery")
            old_payload = reads(1.0)[0]
            self.check(self.callback("old-read", "audit-read") is None, "old read escaped its native delivery hold")
            if throwing:
                held = self.native_gate("new-general-publication", "rename", "general")
                self.ipc("auditEdit", "general.scaleRatio", "1.25")
                self.ipc("save", "new-job")
                self.wait(held[0].exists, "different ordinary job held at real publication")
            else:
                temporary = target.with_suffix(".external")
                temporary.write_text('{"fontDefaultScale":1.4}\n'); temporary.replace(target)
                self.ipc("auditRead", "ui", "new-read", "normal")
                self.wait(lambda: bool(reads(1.4)), "real newer native read packet held")
                newer = reads(1.4)[-1]
                self.check(int(newer["generation"]) > int(old_payload["generation"]), "new read is not a later real publication")
                # Native result-only packets contain deltas, not complete value
                # publications. Deliver every actual newer observation through
                # that receipt, while keeping the older read itself held.
                for packet in packets():
                    if packet["index"] <= newer["index"] and int(packet["generation"]) > int(old_payload["generation"]):
                        self.ipc("nativePacketRelease", str(packet["index"]))
                self.check(self.private_state("new-native-read-before-old")["current"]["consumer"]["uiScale"] == 1.4,
                           "newer native snapshot was not accepted before releasing the old inspection")
            self.ipc("nativePacketRelease", str(old_payload["index"]))
            old_callback = self.wait_callback("old-read", "audit-read")
            self.ipc("nativePacketsEnd")
            route_active = False
            if held:
                self.release(held[1])
                new_callback = self.wait_callback("new-job", "save-callback")
                self.check(new_callback["success"], "old read callback exception failed a different active job")
                self.check(json.loads((self.config / "settings/general.json").read_text()).get("scaleRatio") == 1.25,
                           "new ordinary owner did not publish after old read callback")
            else:
                self.check(self.wait_callback("new-read", "audit-read")["success"], "newer native read callback was lost")
                observed = self.audit_state("read-order-final-consumer")
                atomic_json(self.case / "read-order-assertion.json", {"old_payload": old_payload,
                    "old_callback": old_callback, "consumer": observed, "actual": json.loads(target.read_text())})
                self.check(observed["uiScale"] == 1.4, "late inspection rolled back the newer Settings consumer")
                self.check(json.loads(target.read_text()) == {"fontDefaultScale": 1.4}, "late inspection replaced newer disk state")
        finally:
            if route_active:
                self.ipc("nativePacketsEnd")
            if held and held[0].exists():
                try: self.release(held[1])
                except OSError as error:
                    if error.errno != 6: raise

    def missing_acceptance(self):
        self.start("missing-acceptance")
        self.ipc("request", "macos", "missing-prior-choice")
        self.check(self.wait_callback("missing-prior-choice")["success"], "missing-file prior choice failed")
        self.ipc("auditWatchMissing")
        (self.config / "settings/bindings.json").unlink()
        self.wait(lambda: any(e["event"] == "audit-missing-acceptance" for e in self.events()),
                  "actual missing-file acceptance notification")
        observed = next(e["detail"] for e in self.events() if e["event"] == "audit-missing-acceptance")
        atomic_json(self.case / "missing-acceptance-assertion.json", observed)
        self.check(observed["exists"] is False and bool(observed["identity"]),
                   "missing existence/full identity was not settled before notification")
        self.wait(lambda: self.status("missing-settled")["detail"]["owner"]["state"] == "Idle",
                  "missing-file captured fallback handoff")

    def notification_reentry(self, accepted=False):
        initial = {"environment": "none", "futureRaw": {"original": [False, 0, ""]}}
        def seed():
            (self.config / "settings/bindings.json").write_text(json.dumps(initial) + "\n")
        self.start("accepted-choice-reentry" if accepted else "managed-effective-reentry", before_launch=seed)
        target = self.config / "settings/bindings.json"
        if accepted:
            self.ipc("auditWatchAcceptedChoice")
            expected = {"environment": "macos", "futureRaw": {"foreign": [None, False, 0, ""]}}
            temporary = target.with_suffix(".external")
            temporary.write_text(json.dumps(expected) + "\n"); temporary.replace(target)
            self.wait(lambda: any(e["event"] == "audit-accepted-choice" for e in self.events()), "acceptance listener reentry")
            observed = next(e["detail"] for e in self.events() if e["event"] == "audit-accepted-choice")
            self.check(observed["coherentRaw"] and observed["identitySettled"],
                       "acceptance listener saw unsettled raw body or file identity")
            self.check(self.wait_callback("accepted-tail")["success"], "acceptance listener's queued tail failed")
            expected["environment"] = "none"
        else:
            self.ipc("auditWatchManagedEffective")
            self.ipc("request", "macos", "effective-head")
            self.check(self.wait_callback("effective-head")["success"], "managed effective head failed")
            self.check(self.wait_callback("effective-tail")["success"], "managed effective listener's queued tail failed")
            self.check(not self.wait_callback("effective-save", "save-callback")["success"],
                       "effective listener's full save hid unresolved binding work")
            observed = next(e["detail"] for e in self.events() if e["event"] == "audit-managed-effective")
            self.check(observed["intentInstalled"] and observed["snapshotSettled"],
                       "managed effective notification exposed an uninstalled capture or stale snapshot")
            self.check(json.loads((self.config / "settings/ui.json").read_text())["fontDefaultScale"] == 1.6,
                       "effective listener's ordinary edit was lost")
            expected = initial
        actual = json.loads(target.read_text())
        atomic_json(self.case / "notification-reentry-assertion.json", {"accepted": accepted,
            "observed": observed, "expected": expected, "actual": actual})
        self.check(json_equal(actual, expected), "reentrant notification lost immutable request raw data")

    def acceptance_reasons(self):
        self.start("acceptance-reasons")
        target = self.config / "settings/bindings.json"
        outcomes = []
        for variant in ("byte-different-same-tree", "identity-only", "unknown-only"):
            before = sum(e["event"] == "handoff" for e in self.events())
            expected = json.loads(target.read_text())
            if variant == "unknown-only":
                expected["futureRaw"] = {"array": [None, False, 0, ""], "null": None,
                                         "false": False, "zero": 0, "empty": ""}
            authored = target.read_bytes() if variant == "identity-only" else (json.dumps(expected, separators=(",", ":")) + "\n\n").encode()
            temporary = target.with_suffix(".external")
            temporary.write_bytes(authored); temporary.replace(target)
            self.wait(lambda: sum(e["event"] == "handoff" for e in self.events()) > before,
                      variant + " captured request decision")
            self.wait(lambda: self.status("acceptance-reason-settled")["detail"]["owner"]["state"] == "Idle",
                      variant + " accepted handoff")
            for turn in range(4): self.status(variant + "-echo-" + str(turn))
            delivered = [e["detail"] for e in self.events() if e["event"] == "handoff"][before:]
            actual = json.loads(target.read_text())
            outcomes.append({"variant": variant, "expected": expected, "actual": actual, "handoffs": delivered})
            atomic_json(self.case / (variant + "-assertion.json"), outcomes[-1])
            self.check(len(delivered) == 1 and delivered[0]["success"] and delivered[0]["selected"] == "none",
                       variant + " legitimate repeated decision was omitted or replayed")
            self.check(json_equal(actual, expected), variant + " accepted raw tree was lost")
        atomic_json(self.case / "acceptance-reasons.json", outcomes)

    def promotion_conflicts(self, publication_error=False, retention_fault=False):
        return self.native_promotion_observations(publication_error, retention_fault)

    def native_promotion_observations(self, publication_error=False, retention_fault=False, arrival=False):
        self.start("native-retention-arrival" if arrival else "native-promotion-conflicts")
        target = self.config / "settings/bindings.json"
        original = target.read_bytes()
        holder = self.work_case / "original-binding-preimage"
        evidence = self.work_case / "cache/settings-conflicts"
        before = self.native_gate("disputed-preflight", "parent-preflight", "bindings")
        gates = [before]
        packets_active = False
        versions = []
        def author(number):
            value = {"environment": "none", "futureRaw": {
                "arrival" if arrival else "version": number, "values": [None, False, 0, ""]}}
            body = (json.dumps(value) + "\n").encode()
            gate = self.native_gate("foreign-" + str(number), "read-after", "bindings", sha256=hashlib.sha256(body).hexdigest())
            gates.append(gate)
            temp = target.with_suffix(".external"); temp.write_bytes(body); temp.replace(target)
            return value, body, gate
        def acquired(number, body, gate):
            self.wait(gate[0].exists, "actual native acquired foreign F" + str(number))
            row = json.loads(gate[0].read_text())["observation"]
            self.check(base64.b64decode(row["bytesBase64"]) == body and row["presence"] == "present",
                       "native foreign acquisition changed authored complete F" + str(number))
            versions.append(row)
            return row
        try:
            self.ipc("request", "macos", "arrival-head" if arrival else "disputed-head")
            self.wait(before[0].exists, "actual retained native writer before locked preflight")
            self.ipc("request", "none", "arrival-tail" if arrival else "disputed-tail")
            self.ipc("nativePacketsBegin"); packets_active = True
            if not publication_error: target.rename(holder)
            first, body, gate = author(1)
            self.release(before[1])
            acquired(1, body, gate)
            if retention_fault: evidence.chmod(0o555)
            self.release(gate[1])
            self.wait(lambda: any(p["operation"] == "saveGroup" for p in json.loads(self.ipc("nativePackets"))),
                      "actual native disputed attempt completion held before delivery")
            second, body, gate = author(2)
            retaining = None
            if arrival:
                retaining = self.native_gate("arrival-retention", "retain-before", "bindings", file=evidence,
                    sourceId="bindings", sha256=hashlib.sha256(body).hexdigest())
                gates.append(retaining)
            self.ipc("auditRead", "bindings", "observed-F2", "normal")
            acquired(2, body, gate)
            self.release(gate[1])
            if arrival:
                self.wait(retaining[0].exists, "actual native F2 retention while application head remains pending")
                self.check(self.callback("arrival-head") is None, "native head completed before required retention")
                third, body, gate = author(3)
                self.ipc("auditRead", "bindings", "observed-F3", "normal")
                self.check(self.status("arrival-during-retention")["detail"]["owner"]["state"] == "Running",
                           "F3 arrived after actual application job disposal")
                self.release(retaining[1])
                acquired(3, body, gate)
                self.release(gate[1])
            elif not publication_error:
                target.unlink(); holder.rename(target)
            expected_reloads = 2 if arrival else 1
            self.wait(lambda: sum(p["operation"] == "reload" for p in json.loads(self.ipc("nativePackets"))) >= expected_reloads,
                      "all actually acquired later native observations settled before application callback")
            held = json.loads(self.ipc("nativePackets"))
            self.ipc("nativePacketsEnd"); packets_active = False
            head = "arrival-head" if arrival else "disputed-head"
            tail = "arrival-tail" if arrival else "disputed-tail"
            result = self.wait_callback(head)
            self.check(not result["success"] and result["state"] == "Stopped", "actual disputed native head did not stop")
            self.check(result["error"] == ("evidence-retention" if retention_fault else "source-preimage-conflict"),
                       "actual native dispute/retention cause was lost")
            self.check(self.callback(tail) is None, "disputed native attempt advanced original waiting tail")
            first_boundary = self.private_state("native-disputed-first-terminal")
            retry = None
            resolved = None
            if not arrival:
                if retention_fault: evidence.chmod(0o700)
                self.ipc("retry", "disputed-unresolved-retry")
                retry = self.wait_callback("disputed-unresolved-retry")
                if publication_error:
                    self.check(not retry["success"] and self.callback(tail) is None,
                               "foreign unresolved native preimage authorized overwrite or advanced tail")
                else:
                    self.check(retry["success"] and retry["requestId"] == result["requestId"] and
                               retry["attemptId"] == result["attemptId"] + 1,
                               "native content-equal restoration did not resolve same head/new attempt")
                    self.check(self.wait_callback(tail)["success"], "native resolved dispute lost original waiting tail")
                target.write_bytes(original)
                self.ipc("retry", "disputed-resolved-retry")
                resolved = self.wait_callback("disputed-resolved-retry")
                if publication_error:
                    self.check(resolved["success"] and self.wait_callback(tail)["success"],
                               "explicit native preimage restoration failed original head/tail")
                else:
                    self.check(not resolved["success"] and resolved["error"] == "No stopped head is available for Retry",
                               "already settled native head was replayed after external restoration")
            artifacts = self.native_evidence(evidence)
            for number, version in enumerate(versions, 1):
                self.check(any(a["bytesBase64"] == version["bytesBase64"] and
                               a["metadata"]["revision"] == version["revision"] for a in artifacts),
                           "complete acquired native foreign F" + str(number) + " was not durably retained")
            atomic_json(self.case / ("retention-arrival-assertion.json" if arrival else "foreign-retention-assertion.json"),
                dict(nativeSerialIO=True, publication_error=publication_error, retention_fault=retention_fault,
                     expected=versions, held=held, result=result, first=first_boundary, retry=retry,
                     resolved=resolved, artifacts=artifacts, actual=json.loads(target.read_text())))
        finally:
            if evidence.exists(): evidence.chmod(0o700)
            if holder.exists():
                if target.exists(): target.unlink()
                holder.rename(target)
            for marker, fifo in gates:
                if marker.exists():
                    try: self.release(fifo)
                    except OSError as error:
                        if error.errno != 6: raise
            if packets_active: self.ipc("nativePacketsEnd")

    def setup_failed_bundle(self, preexisting=False):
        self.start("setup-failed-bundle", "wizard")
        enabled, markers = self.native_fault("setup-preparation", "write", ("general", "bar"))
        def native():
            return json.loads(self.ipc("auditNativeState"))
        def group(state, identity):
            matches = [row for row in state["groups"] if row["requestKey"] == identity + ":setup"]
            self.check(len(matches) == 1, "actual setup retained group missing or duplicated")
            return matches[0]
        self.ipc("auditWizardSelection")
        if preexisting:
            self.ipc("auditWizardApplySelection")
            self.wait(lambda: any(e["event"] == "save-failed" for e in self.events()) and
                      not native()["pendingRequests"],
                      "actual setup step's prior failed ordinary captures")
        prior = native()
        self.ipc("auditWizardFinish")
        self.wait(lambda: self.status("setup-first-failed")["detail"]["wizardSubmitted"] and
                  self.status("setup-first-terminal")["detail"]["wizardSubmitted"]["status"] in ("Stopped", "Succeeded"),
                  "first actual setup submission terminal result")
        first = self.status("setup-first-result")["detail"]
        self.check(first["wizardOpen"] and first["owner"]["stage"] == "setup-save",
                    "first ordinary setup failure did not retain the open wizard")
        identity = first["wizardSubmitted"]["id"]
        first_native = native()
        first_group = group(first_native, identity)
        self.check(first_group["state"] == "stopped" and any(marker.exists() for marker in markers),
                   "setup failure did not reach the real native publication boundary")
        before = len(self.events())
        self.check(first["owner"]["state"] == "Stopped", "failed native setup advanced the queue")
        self.ipc("auditWizardFinish")
        self.wait(lambda: any(e["event"] == "handoff" and e["detail"]["requestId"] == identity
                             and e["detail"]["attemptId"] == 2 for e in self.events()), "unchanged setup Retry result")
        second = self.status("setup-unchanged-retry")["detail"]
        second_native = native()
        second_group = group(second_native, identity)
        advanced = [e for e in self.events()[before:] if e["event"] == "stage"
                    and e["detail"]["stage"] in ("save", "deploy", "generate-handoff")]
        atomic_json(self.case / "setup-barrier-assertion.json", {"prior": prior, "first": first, "second": second,
            "first_native": first_native, "second_native": second_native, "advanced_stages": advanced,
            "general": json.loads((self.config / "settings/general.json").read_text())})
        self.check(second["wizardOpen"] and second["owner"]["state"] == "Stopped"
                   and second["owner"]["stage"] == "setup-save" and not advanced,
                    "unchanged setup Retry bypassed failed ordinary captures")
        self.check(first_group["token"] == second_group["token"] and
                   first_group["capturePrefix"] == second_group["capturePrefix"] and
                   len(second_group["attempts"]) == 2 and
                   all(attempt["status"] == "failed" for attempt in second_group["attempts"]),
                   "unchanged Retry replaced or bypassed the failed native capture")
        enabled.unlink()  # Resolve only the task-owned native preparation fault.
        if second["owner"]["state"] == "Stopped":
            self.ipc("auditWizardFinish")
            self.wait(lambda: not self.status("setup-resolved")["detail"]["wizardOpen"], "resolved actual wizard closes")
        general = json.loads((self.config / "settings/general.json").read_text())
        bar_path = self.config / "settings/bar.json"
        bar = json.loads(bar_path.read_text()) if bar_path.exists() else {}
        self.check(general.get("scaleRatio") == 1.2 and bar.get("position") == "bottom",
                   "setup completion omitted its actual ordinary writes")
        self.check(self.status("setup-complete")["detail"]["wizardSubmitted"]["id"] == identity,
                    "setup Retry replaced the submitted request identity")
        self.restart_fixture()
        cold = self.private_state("setup-restarted-consumer")
        self.check(cold["current"]["consumer"]["generalScale"] == 1.2,
                   "acknowledged setup choice did not reach the restarted consumer")
        atomic_json(self.case / "setup-cold-consumer.json", cold)

    def terminal_reentry(self, status=False, startup=False):
        self.start("terminal-startup-observers" if startup else ("terminal-status-reentry" if status else "terminal-signal-reentry"),
                   "terminal-startup" if startup else "settings", wait_startup=not startup)
        if not startup:
            self.ipc("auditTerminalRetry", "status" if status else "signal")
            self.ipc("request", "unsupported-captured-environment", "terminal-original")
        original = self.wait_callback("terminal-original")
        retry = self.wait_callback("terminal-retry")
        environment = "none" if startup else "unsupported-captured-environment"
        self.terminal_oracle = (original["requestId"], environment, startup)
        self.failures.extend(terminal_delivery_errors(self.events(), *self.terminal_oracle))
        signals = [e["detail"] for e in self.events() if e["event"] == "handoff"
                   and e["detail"]["requestId"] == original["requestId"]]
        first = next(s for s in signals if s["attemptId"] == 1)
        same = (first["success"], first["error"], first["requestId"], first["attemptId"]) == (
            original["success"], original["error"], original["requestId"], original["attemptId"])
        atomic_json(self.case / "terminal-tuple-assertion.json", {
            "status_trigger": status, "signals": signals, "original_callback": original, "retry_callback": retry})
        self.check(same, "reentrant settlement mutated the original callback result tuple")
        if startup:
            observer = self.wait_callback("startup-frozen", "startup-observer")
            self.check((observer["success"], observer["error"], observer["requestId"], observer["attemptId"]) ==
                       (first["success"], first["error"], first["requestId"], first["attemptId"]),
                        "startup observer received a mutated terminal tuple")
            self.wait_callback("startup-frozen-second", "startup-observer")
        self.check([s["attemptId"] for s in signals] == [1, 2], "new Retry attempt delivered before old terminal notification")
        ordered = [e["detail"]["token"] for e in self.events() if e["event"] == "callback"
                   and e["detail"]["token"] in ("terminal-original", "terminal-retry")]
        self.check(ordered == ["terminal-original", "terminal-retry"], "new Retry callback preceded original callback delivery")
        self.check(not retry["success"] and retry["requestId"] == original["requestId"] and retry["attemptId"] == 2,
                   "explicit reentrant Retry did not retain immutable head/new attempt")
        self.check(self.callback("terminal-enqueued") is None, "failed reentrant Retry advanced enqueued tail")
        state = self.status("terminal-final-retained")["detail"]["owner"]
        self.check(state["state"] == "Stopped" and state["queueCount"] == 2, "terminal reentry lost stopped head or tail")

    def restart_fixture(self):
        self.stop()
        ready = sum(e["event"] == "ready" for e in self.events())
        startup = sum(e["event"] == "startup" for e in self.events())
        self.logpath = self.case / "restart.log"
        self.event_log_paths.append(self.logpath)
        self.process = subprocess.Popen(["qs", "-p", str(self.entry)], env=self.env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
        self.lifecycle.track(self.process)
        self.live_started = True
        self.capture = JournalCapture(self.process, self.output, self.logpath, self.work_case)
        self.wait(lambda: sum(e["event"] == "ready" for e in self.events()) > ready, "same-config restart readiness")
        self.wait(lambda: sum(e["event"] == "startup" for e in self.events()) > startup, "same-config restart startup")

    def mixed_snapshot(self, legacy=False):
        raw = {"object": {"zero": 0}, "array": [None, False, 0, ""],
               "null": None, "empty": "", "false": False, "zero": 0}
        initial = {"animationDisabled": True, "futureRaw": raw}
        def seed():
            (self.config / "settings/general.json").write_text(json.dumps(initial) + "\n")
            if legacy:
                (self.config / "settings.json").write_text(json.dumps({"settingsVersion": 60,
                    "general": {"dimmerOpacity": 0.2, "futureRaw": {"foreign": False}}}) + "\n")
        self.start("mixed-legacy" if legacy else "mixed-section", before_launch=seed)
        target = self.config / "settings/general.json"
        count = sum(e["event"] == "settings-reloaded" for e in self.events())
        if legacy:
            publication = self.config / "settings.json"
            external = {"settingsVersion": 60, "general": {"dimmerOpacity": 0.65, "futureRaw": {"foreign": True}}}
            expected = dict(initial, scaleRatio=1.17)
        else:
            publication = target
            external = dict(initial, dimmerOpacity=0.65, futureRaw=dict(raw, foreign={"new": False}))
            expected = dict(external, scaleRatio=1.17)
        authored = (json.dumps(external) + "\n").encode()
        temporary = publication.with_suffix(".external")
        temporary.write_bytes(authored); temporary.replace(publication)
        self.wait(lambda: sum(e["event"] == "settings-reloaded" for e in self.events()) > count,
                  "mixed known/unknown observation")
        observed = self.audit_state("mixed-observed")
        self.check(observed["dimmer"] == 0.65, "mixed known setting did not reach consumer")
        self.check(not observed["hasSnapshotFutureRaw"], "rejected raw paths leaked into capture baseline")
        # Existing legacy acceptance may capture bindings work. A full save
        # correctly reports that unresolved work; this case tests raw snapshots
        # after its actual handoff, rather than weakening the full-save barrier.
        self.wait(lambda: self.status("mixed-owner-settled")["detail"]["owner"]["state"] == "Idle",
                  "mixed observation's existing captured binding work")
        self.ipc("auditEdit", "general.scaleRatio", "1.17")
        self.ipc("save", "mixed-save")
        saved = self.wait_callback("mixed-save", "save-callback")
        actual_raw = target.read_text()
        actual = json.loads(actual_raw)
        atomic_json(self.case / "mixed-raw-assertion.json", {"legacy": legacy, "expected": expected,
            "actual": actual, "actual_raw": actual_raw, "observed": observed, "callback": saved})
        self.check(saved["success"], "mixed raw save failed")
        self.check(json_equal(actual, expected), "mixed known/unknown save lost raw siblings or types")
        if legacy:
            self.check(publication.read_bytes() == authored, "mixed save rewrote read-only legacy bytes")
        self.restart_fixture()
        consumer = self.audit_state("mixed-restarted-consumer")
        atomic_json(self.case / "mixed-restart-consumer.json", consumer)
        self.check(consumer["generalScale"] == 1.17 and consumer["dimmer"] == 0.65,
                   "saved mixed setting did not reach restarted consumer")
        self.check(json_equal(json.loads(target.read_text()), expected), "restart did not retain complete mixed raw tree")

    def corrective_listener(self, kind="debounce", legacy=False):
        record = kind == "record"
        original = {"widgets": {"left": [{"id": "Tray", "futureRaw": [False, 0, None, ""]}]}} if record else {
            "fontDefaultScale": 1.0, "futureRaw": [False, 0, None, ""]}
        section = "bar" if record else "ui"
        def seed():
            if legacy:
                (self.config / "settings.json").write_text(json.dumps({"settingsVersion": 60, section: original}) + "\n")
            else:
                (self.config / ("settings/" + section + ".json")).write_text(json.dumps(original) + "\n")
        self.start("corrective-listener-" + kind, before_launch=seed)
        publication = self.config / "settings.json" if legacy else self.config / ("settings/" + section + ".json")
        target = self.config / ("settings/" + section + ".json")
        self.ipc("correctiveListen", kind, "bar.widgets.left" if record else "ui.fontDefaultScale")
        external = json.loads(json.dumps(original))
        if record:
            external["widgets"]["left"][0]["externalValue"] = 1.4
        else:
            external["fontDefaultScale"] = 1.4
        authored = (json.dumps({"settingsVersion": 60, section: external} if legacy else external) + "\n").encode()
        temporary = publication.with_suffix(".external")
        temporary.write_bytes(authored); temporary.replace(publication)
        self.wait(lambda: any(e["event"] == "corrective-listener" for e in self.events()), "one-shot real property listener")
        listener_serial = next(e["serial"] for e in self.events() if e["event"] == "corrective-listener")
        def covered_listener_save():
            return any(e["event"] == "native-save-completed" and e["serial"] > listener_serial and
                       e["detail"]["status"] == "saved" and any(
                           coverage["path"] == (["bar", "widgets", "left"] if record else ["ui", "fontDefaultScale"])
                           and int(coverage["inputThrough"]) >= 1 for coverage in e["detail"]["coverage"])
                       for e in self.events())
        self.wait(covered_listener_save, "actual native saved coverage for the listener's local input")
        if kind == "save":
            self.check(self.wait_callback("corrective-listener-save", "save-callback")["success"], "reentrant save was swallowed or failed")
        expected = json.loads(json.dumps(external))
        if record:
            expected["widgets"]["left"][0]["correctiveLocal"] = {"values": [False, 0, None, ""]}
        else:
            expected["fontDefaultScale"] = 1.7
            if legacy:
                expected = {"fontDefaultScale": 1.7}
        actual = json.loads(target.read_text()) if target.exists() else None
        private = self.private_state("listener-settled")
        self.check(json_equal(actual, expected), "external assignment absorbed the listener's local edit into its baseline")
        if kind == "save":
            at_call = private["terminals"]["listener-after-save-call"]
            before = private["terminals"]["listener-before-edit"]["native"]["owner"]
            after = at_call["native"]["owner"]
            self.check(int(after["inputPrefix"]) > int(before["inputPrefix"]) and bool(after["pendingRequests"]) and
                       after["paths"]["ui.fontDefaultScale"]["admittedFingerprint"] ==
                       before["paths"]["ui.fontDefaultScale"]["admittedFingerprint"],
                       "nested save lost its local input/detached callback before external notification settled")
        if legacy:
            self.check(publication.read_bytes() == authored, "listener edit rewrote legacy bytes")
        atomic_json(self.case / "corrective-listener-assertion.json", {"kind": kind, "legacy": legacy,
            "expected": expected, "actual": actual, "authored_base64": base64.b64encode(authored).decode()})
        self.restart_fixture()
        expected_consumer = json.loads(json.dumps(expected["widgets"]["left"])) if record else None
        if record:
            # The undeclared numeric member is an opaque ConfigNumber after
            # disk admission, not a declared Real. Keep its exact token contract
            # separate from the unchanged raw-JSON assertions above and below.
            expected_consumer[0]["externalValue"] = {"decimal": "1.4"}
        self.check(self.audit_state("listener-restarted")["uiScale"] == 1.7 if not record else
                   json_equal(self.private_state("record-restarted")["current"]["consumer"]["widgetsLeft"], expected_consumer),
                    "listener local edit did not reach the restarted consumer")
        self.check(json_equal(json.loads(target.read_text()) if target.exists() else None, expected),
                   "listener local raw intent did not survive same-tree restart")

    def corrective_pending_parent(self, legacy=False, removed=False):
        initial = {"animationDisabled": True, "futureRoot": [False, 0, None, ""]}
        parent = {"keyUp": ["F1"], "keyDown": ["F2"], "keyLeft": ["F2"], "futureSibling": [False, 0, None, ""]}
        if legacy:
            initial["keybinds"] = {"keyDown": ["F8"]}
        elif removed:
            initial["keybinds"] = parent
        legacy_initial = {"settingsVersion": 60, "general": {}}
        if removed:
            legacy_initial["general"]["keybinds"] = parent if legacy else {"keyUp": ["F3"], "keyDown": ["F4"]}
        def seed():
            (self.config / "settings/general.json").write_text(json.dumps(initial) + "\n")
            if legacy or removed:
                (self.config / "settings.json").write_text(json.dumps(legacy_initial) + "\n")
        self.start("corrective-pending-parent", before_launch=seed)
        target = self.config / "settings/general.json"
        # Genuine initial inspection separates accepted disk state from initial
        # overlay aliasing on BASELINE; it also establishes the actual preimage.
        self.ipc("auditRead", "general", "parent-initial-inspection", "normal")
        self.check(self.wait_callback("parent-initial-inspection", "audit-read")["success"], "initial parent inspection failed")
        if legacy:
            self.ipc("auditRead", "legacy", "parent-initial-legacy", "normal")
            self.check(self.wait_callback("parent-initial-legacy", "audit-read")["success"], "initial legacy inspection failed")
        # Startup no longer materializes defaults as a spurious user write.
        # Preserve the before-capture settlement barrier using an actual native
        # flush receipt; a clean no-op must not pretend to emit settingsSaved.
        self.ipc("settle", "pending-parent-startup-settled")
        self.check(self.wait_callback("pending-parent-startup-settled", "save-callback")["success"],
                   "initial native settlement failed")
        accepted_bytes = target.read_bytes()
        accepted = json.loads((self.config / "settings.json").read_bytes()) if legacy else json.loads(accepted_bytes)
        prior_parent = accepted.get("general", {}).get("keybinds") if legacy else accepted.get("keybinds")
        self.check((prior_parent is not None) == removed, "authored parent add/remove precondition was not established")
        external = dict(legacy_initial if legacy else initial)
        if legacy:
            external["general"] = {} if removed else {"keybinds": parent}
        elif removed:
            external.pop("keybinds")
        else:
            external["keybinds"] = parent
        publication = self.config / "settings.json" if legacy else target
        authored = (json.dumps(external) + "\n").encode()
        transfer = self.begin_private_transfer("correctiveCapture", "general.keybinds.keyUp", json_ipc_text(["F9"]))
        # Check the actual file before authoring the foreign parent, not after
        # draining a large diagnostic body across multiple IPC round trips.
        unpublished = target.read_bytes() == accepted_bytes
        temporary = publication.with_suffix(".external")
        temporary.write_bytes(authored); temporary.replace(publication)
        self.ipc("auditRead", "legacy" if legacy else "general", "pending-parent-read", "normal")
        captured = json.loads(self.private_transfer(transfer, "pending-parent-captured"))
        atomic_json(self.case / "pending-parent-captured-private.json", captured)
        self.check(captured["decodedNativeArray"] and captured["decoded"] == ["F9"] and
                   captured["current"]["consumer"]["keyUp"] == ["F9"], "pending parent stimulus is not the authored array")
        self.check(unpublished and captured["before"]["revision"] == captured["after"]["revision"],
                   "pending descendant was enqueued before the parent-add schedule")
        self.check(captured["current"]["native"]["paths"]["general.keybinds.keyUp"]["latestInput"] != captured["beforeInput"]["latestInput"],
                   "pending descendant was not captured")
        self.wait_callback("pending-parent-read", "audit-read")
        consumer = self.private_state("pending-parent-applied")["current"]["consumer"]
        self.check(consumer["keyUp"] == ["F9"], "external parent addition clobbered the protected descendant")
        sibling = "keyLeft" if legacy else "keyDown"
        expected_sibling = ["Left"] if legacy and removed else (["F4"] if removed else ["F2"])
        self.check(consumer[sibling] == expected_sibling, "external parent skipped an unprotected sibling/lower-layer fallback")
        if legacy:
            self.check(consumer["keyDown"] == ["F8"], "external legacy parent bypassed a section-masked sibling")
            self.wait(lambda: self.status("parent-legacy-owner-settled")["detail"]["owner"]["state"] == "Idle",
                      "legacy observation's captured binding handoff")
        # The case tests retained pending work, not a timer count. A real explicit
        # save joins any earlier automatic write and proves its owned terminal.
        self.ipc("save", "pending-parent-save")
        self.check(self.wait_callback("pending-parent-save", "save-callback")["success"], "pending parent owned save failed")
        expected = dict(initial if legacy else external)
        expected["keybinds"] = dict(expected.get("keybinds", {}), keyUp=["F9"])
        actual = json.loads(target.read_text())
        atomic_json(self.case / "corrective-parent-assertion.json", {"legacy": legacy, "removed": removed,
            "expected": expected, "actual": actual, "consumer": consumer})
        self.check(json_equal(actual, expected), "pending path or raw unknown sibling was lost from parent-add publication")
        if legacy:
            self.check(publication.read_bytes() == authored, "pending parent capture rewrote legacy bytes")
        self.restart_fixture()
        restarted = self.private_state("pending-parent-restarted")["current"]["consumer"]
        self.check(restarted["keyUp"] == ["F9"] and restarted[sibling] == expected_sibling,
                   "protected descendant did not reach restarted consumer")

    def corrective_ordinary_layers(self, variant):
        legacy_change = variant.startswith("legacy-")
        legacy_initial = {"settingsVersion": 60, "futureLegacy": [False, 0, None, ""]}
        if variant != "legacy-add":
            legacy_initial["general"] = {"dimmerOpacity": 0.65, "scaleRatio": 1.2, "futureLegacyLeaf": [False, 0]}
        initial = {"animationDisabled": True, "dimmerOpacity": 0.9, "futureRoot": [False, 0, None, ""]}
        def seed():
            (self.config / "settings.json").write_text(json.dumps(legacy_initial) + "\n")
            (self.config / "settings/general.json").write_text(json.dumps(initial) + "\n")
        self.start("corrective-ordinary-layers", before_launch=seed)
        legacy = self.config / "settings.json"
        target = self.config / "settings/general.json"
        if legacy_change:
            external = dict(legacy_initial)
            if variant == "legacy-add":
                external["general"] = {"scaleRatio": 1.2, "dimmerOpacity": 0.65, "futureLegacyLeaf": [False, 0]}
            else:
                external.pop("general")
            authored = (json.dumps(external) + "\n").encode()
            temporary = legacy.with_suffix(".external"); temporary.write_bytes(authored); temporary.replace(legacy)
        else:
            authored = legacy.read_bytes()
            if variant == "file-delete":
                target.unlink()
            else:
                external = dict(initial); external.pop("dimmerOpacity")
                temporary = target.with_suffix(".external"); temporary.write_text(json.dumps(external) + "\n"); temporary.replace(target)
        self.ipc("auditRead", "legacy" if legacy_change else "general", "ordinary-layer-read", "normal")
        self.wait_callback("ordinary-layer-read", "audit-read")
        consumer = self.private_state("ordinary-layer-live")["current"]["consumer"]
        expected_scale = 1.2 if variant == "legacy-add" or not legacy_change else 1.0
        expected_dimmer = 0.9 if legacy_change else 0.65
        self.check(consumer["generalScale"] == expected_scale and consumer["dimmer"] == expected_dimmer,
                   "ordinary layer add/remove did not reach the correct live section/legacy/default value")
        self.wait(lambda: self.status("ordinary-layer-owner-settled")["detail"]["owner"]["state"] == "Idle",
                  "ordinary layer observation's captured binding handoff")
        self.ipc("auditEdit", "ui.fontDefaultScale", json_ipc_text(1.17))
        self.ipc("save", "ordinary-layer-save")
        self.check(self.wait_callback("ordinary-layer-save", "save-callback")["success"], "unrelated layer-control save failed")
        expected = initial if legacy_change else (None if variant == "file-delete" else external)
        actual = json.loads(target.read_text()) if target.exists() else None
        atomic_json(self.case / "ordinary-layer-assertion.json", {"variant": variant, "expected": expected,
            "actual": actual, "consumer": consumer})
        self.check(json_equal(actual, expected), "ordinary layer control serialized merged defaults/legacy or lost unknown raw")
        self.check(legacy.read_bytes() == authored, "ordinary layer control rewrote legacy bytes")
        self.restart_fixture()
        restarted = self.private_state("ordinary-layer-restarted")["current"]["consumer"]
        self.check(restarted["generalScale"] == expected_scale and restarted["dimmer"] == expected_dimmer,
                   "ordinary layer live/restarted consumers disagree")

    def corrective_missing_lifetime(self):
        def seed():
            (self.config / "settings/ui.json").write_text('{"fontDefaultScale":1.3}\n')
        self.start("corrective-missing-lifetime", before_launch=seed)
        target = self.config / "settings/ui.json"
        self.ipc("correctiveReset", "ui.fontDefaultScale")
        self.wait(lambda: not target.exists() and not self.audit_state("ordinary-delete-complete")["native"]["pendingRequests"],
                  "actual owned ordinary UI deletion")
        self.ipc("auditRead", "ui", "own-missing-echo", "normal")
        self.wait_callback("own-missing-echo", "audit-read")
        own = self.private_state("ordinary-owned-missing")["current"]
        self.check(any(state["sourceId"] == "ui" and state["presence"] == "absent" for state in own["native"]["sources"]),
                   "owned ordinary deletion was not confirmed")
        temp = target.with_suffix(".external"); temp.write_text('{"fontDefaultScale":2.0}\n'); temp.replace(target)
        self.ipc("auditRead", "ui", "foreign-recreation", "normal")
        self.wait_callback("foreign-recreation", "audit-read")
        self.check(self.audit_state("foreign-recreated-consumer")["uiScale"] == 2.0, "foreign recreation did not reach live consumer")
        target.unlink()
        self.ipc("auditRead", "ui", "foreign-second-delete", "normal")
        self.wait_callback("foreign-second-delete", "audit-read")
        self.check(self.audit_state("foreign-delete-fallback")["uiScale"] == 1.0, "stale owned missing confirmation suppressed foreign deletion fallback")
        captured = json.loads(self.ipc("correctiveCapture", "ui.fontFixedScale", json_ipc_text(1.25)))
        atomic_json(self.case / "ordinary-missing-after-capture-private.json", captured)
        self.ipc("save", "ordinary-missing-save")
        self.check(self.wait_callback("ordinary-missing-save", "save-callback")["success"], "ordinary missing-lifetime control save failed")
        self.check(json_equal(json.loads(target.read_text()), {"fontFixedScale": 1.25}), "later ordinary save resurrected stale raw overrides")
        self.restart_fixture()
        self.check(self.audit_state("missing-lifetime-restarted")["uiScale"] == 1.0, "foreign deletion fallback did not survive restart")

    def corrective_initial_ownership(self):
        initial = {"animationDisabled": True, "futureRoot": [False, 0, None, ""]}
        def seed():
            (self.config / "settings/general.json").write_text(json.dumps(initial) + "\n")
        self.start("corrective-initial-ownership", before_launch=seed)
        target = self.config / "settings/general.json"
        authored = target.read_bytes()
        transfer = self.begin_private_transfer("correctiveCapture", "general.scaleRatio", json_ipc_text(1.17))
        unpublished = target.read_bytes() == authored
        self.ipc("save", "initial-ownership-save")
        captured = json.loads(self.private_transfer(transfer, "initial-ownership-captured"))
        atomic_json(self.case / "initial-ownership-capture-private.json", captured)
        self.check(unpublished and captured["before"]["presence"] == "present",
                   "initial accepted source differs from the authored file")
        self.check(json_equal(captured["after"], captured["before"]), "local capture mutated the initial accepted version")
        before_input = captured["beforeInput"]
        after_input = captured["current"]["native"]["paths"]["general.scaleRatio"]
        self.check(before_input["contentRevision"] == after_input["contentRevision"] and
                   before_input["latestInput"] != after_input["latestInput"],
                   "local ingress mutated the worker-admitted initial version or lost the new input")
        expected = dict(initial, scaleRatio=1.17)
        self.check(captured["current"]["consumer"]["generalScale"] == 1.17,
                   "local capture lost its separate overlay/live consumer")
        self.check(unpublished, "initial ownership boundary unexpectedly published")
        saved = self.wait_callback("initial-ownership-save", "save-callback")
        self.check(saved["success"], "initial ownership local save failed")
        self.check(json_equal(json.loads(target.read_text()), expected), "initial ownership save lost complete raw tree")
        self.restart_fixture()
        self.check(self.private_state("initial-ownership-restarted")["current"]["consumer"]["generalScale"] == 1.17,
                   "initial ownership edit did not reach restarted consumer")
        self.check(json_equal(json.loads(target.read_text()), expected), "initial ownership raw types did not survive restart")

    def corrective_forward_reads(self):
        first = {"fontDefaultScale": 1.4, "futureRaw": {"version": 1, "values": [False, 0, None, ""]}}
        second = {"fontDefaultScale": 1.7, "futureRaw": {"version": 2, "values": [False, 0, None, ""]}}
        authored = {label: (json.dumps(value) + "\n").encode() for label, value in (("F1", first), ("F2", second))}
        def seed():
            (self.config / "settings/ui.json").write_text('{"fontDefaultScale":1.0}\n')
        self.start("corrective-forward-inspectors", before_launch=seed)
        target = self.config / "settings/ui.json"
        self.ipc("auditRead", "ui", "forward-initial-read", "normal")
        self.wait_callback("forward-initial-read", "audit-read")
        self.ipc("nativePacketsBegin")
        held = {}
        def reads(value):
            return [row for row in json.loads(self.ipc("nativePackets")) if row["operation"] == "reload"
                    and row["status"] == "reloaded" and row["values"].get("ui.fontDefaultScale") == value]
        try:
            for label, scale in (("F1", 1.4), ("F2", 1.7)):
                temp = target.with_suffix(".external"); temp.write_bytes(authored[label]); temp.replace(target)
                self.ipc("auditRead", "ui", "forward-" + label, "normal")
                self.wait(lambda: bool(reads(scale)), "actual " + label + " native read held before delivery")
                held[label] = reads(scale)[-1]
            before = self.private_state("forward-before-delivery")["current"]
            self.check(before["consumer"]["uiScale"] == 1.0 and not any(row["released"] for row in json.loads(self.ipc("nativePackets"))),
                       "a relevant native read delivery escaped before the forward schedule")
            for packet in json.loads(self.ipc("nativePackets")):
                if packet["index"] <= held["F1"]["index"]:
                    self.ipc("nativePacketRelease", str(packet["index"]))
            first_consumer = self.private_state("forward-first-accepted")["current"]
            self.check(first_consumer["consumer"]["uiScale"] == 1.4, "first forward watcher state was not accepted")
            for packet in json.loads(self.ipc("nativePackets")):
                if not packet["released"] and packet["index"] <= held["F2"]["index"]:
                    self.ipc("nativePacketRelease", str(packet["index"]))
            self.check(held["F1"]["inputPrefix"] == held["F2"]["inputPrefix"] and
                       int(held["F2"]["generation"]) > int(held["F1"]["generation"]),
                       "forward reads did not share the same input fence with ordered actual publications")
            consumer = self.private_state("forward-read-final")["current"]
            atomic_json(self.case / "forward-read-assertion.json", {"held": held, "packets": json.loads(self.ipc("nativePackets")),
                "first_consumer": first_consumer, "consumer": consumer, "disk": json.loads(target.read_text())})
            self.check(consumer["consumer"]["uiScale"] == 1.7, "higher forward inspector was falsely rejected after earlier acceptance")
            self.check(json_equal(json.loads(target.read_text()), second), "forward inspectors replaced authored newer disk data")
        finally:
            self.ipc("nativePacketsEnd")
        for label in ("F1", "F2"):
            self.check(self.wait_callback("forward-" + label, "audit-read")["success"], "forward native read callback was lost")

    def corrective_readback(self, variant):
        return self.native_readback(variant)

    def native_readback(self, variant):
        self.start("corrective-readback-" + variant)
        target = self.config / "settings/bindings.json"
        entered, fifo = self.native_gate("readback-inspection", "readback", "bindings")
        acquired = None
        try:
            self.ipc("request", "macos", "readback-head")
            self.wait(entered.exists, "actual native writer reached post-publication readback")
            self.ipc("request", "none", "readback-tail")
            before = self.private_state("readback-owner-before-foreign")
            self.check(any(g["state"] == "saving" for g in before["native"]["groups"]),
                       "native readback gate has no actual saving retained group")
            if variant == "missing":
                target.unlink()
                authored = b""
            else:
                authored = target.read_bytes() if variant == "identity" else (json.dumps({"environment": "macos",
                    "futureRaw": {"foreignReadback": [False, 0, None, ""]}}) + "\n").encode()
                temporary = target.with_suffix(".external"); temporary.write_bytes(authored); temporary.replace(target)
            expected = self.inspected_state(target)
            acquired = self.native_gate("readback-acquired", "read-after", "bindings", sha256=hashlib.sha256(authored).hexdigest())
            self.release(fifo)
            self.wait(acquired[0].exists, "native backend acquired actual readback disagreement")
            read = json.loads(acquired[0].read_text())["observation"]
            self.check(base64.b64decode(read["bytesBase64"]) == authored and
                       read["presence"] == ("absent" if variant == "missing" else "present"),
                       "native readback result does not match authored bytes/presence")
            self.release(acquired[1])
            result = self.wait_callback("readback-head")
            boundary = self.private_state("readback-before-retry")
            artifacts = self.native_evidence(self.work_case / "cache/settings-conflicts")
            matching = [a for a in artifacts if a["metadata"]["sourceId"] == "bindings" and
                        a["metadata"]["revision"] == read["revision"] and a["metadata"]["phase"] == "readback"]
            self.check(not result["success"] and result["state"] == "Stopped" and result["error"] == "readback-mismatch",
                       "actual native readback disagreement did not stop head with truthful cause")
            self.check(any(g["state"] == "stopped" and any(a["status"] == "failed" for a in g["attempts"])
                           for g in boundary["native"]["groups"]), "native failed readback group/attempt was not retained")
            self.check(any(a["metadata"]["presence"] == read["presence"] and
                           (a["bytesBase64"] == read["bytesBase64"] if variant != "missing" else a["metadata"]["bytesState"] == "absent")
                           for a in matching), "actual complete readback witness was omitted from durable native evidence")
            self.check(self.callback("readback-tail") is None, "readback dispute advanced retained tail")
            atomic_json(self.case / "readback-retention-assertion.json", dict(variant=variant, expected=expected,
                before=before, acquired=read, result=result, boundary=boundary, artifacts=artifacts))
        finally:
            for gate in ((entered, fifo), acquired):
                if gate and gate[0].exists():
                    try: self.release(gate[1])
                    except OSError as error:
                        if error.errno != 6: raise

    def corrective_readback_postjoin(self):
        return self.native_readback_postjoin()

    def native_readback_postjoin(self):
        self.start("corrective-readback-postjoin")
        target = self.config / "settings/bindings.json"
        before = self.native_gate("postjoin-readback", "readback", "bindings")
        own, later = None, None
        packets_active = False
        foreign = {"environment": "macos", "futureRaw": {"postJoin": [False, 0, None, ""]}}
        foreign_bytes = (json.dumps(foreign) + "\n").encode()
        try:
            self.ipc("request", "macos", "postjoin-head")
            self.wait(before[0].exists, "native writer reached actual readback boundary")
            own_bytes = target.read_bytes()
            own = self.native_gate("postjoin-own-acquired", "read-after", "bindings", sha256=hashlib.sha256(own_bytes).hexdigest())
            later = self.native_gate("postjoin-foreign-acquired", "read-after", "bindings", sha256=hashlib.sha256(foreign_bytes).hexdigest())
            self.ipc("nativePacketsBegin"); packets_active = True
            self.release(before[1])
            self.wait(own[0].exists, "actual owned A readback held before return")
            own_read = json.loads(own[0].read_text())["observation"]
            self.ipc("request", "none", "postjoin-tail")
            temporary = target.with_suffix(".external"); temporary.write_bytes(foreign_bytes); temporary.replace(target)
            expected = self.inspected_state(target)
            self.ipc("auditRead", "bindings", "postjoin-F", "normal")
            self.release(own[1])
            # The native worker serializes IO, unlike the retired parallel
            # helpers. Hold its unchanged completion at delivery while the
            # genuinely queued later F read is acquired; never fabricate a join.
            self.wait(later[0].exists, "native later F read acquired before application completion")
            foreign_read = json.loads(later[0].read_text())["observation"]
            self.check(base64.b64decode(own_read["bytesBase64"]) == own_bytes and
                       base64.b64decode(foreign_read["bytesBase64"]) == foreign_bytes and
                       own_read["revision"] != foreign_read["revision"], "native postjoin reads lost their actual distinct versions")
            self.check(self.callback("postjoin-head") is None and self.callback("postjoin-tail") is None,
                       "native postjoin delivery gate did not retain the actual head/tail")
            self.release(later[1])
            self.wait(lambda: any(p["operation"] == "reload" and p["status"] == "reloaded"
                                 for p in json.loads(self.ipc("nativePackets"))), "native later F completion held")
            held = json.loads(self.ipc("nativePackets"))
            own_packet = next(p for p in held if p["operation"] == "saveGroup")
            foreign_packet = next(p for p in held if p["operation"] == "reload" and p["status"] == "reloaded")
            self.check(own_packet["index"] < foreign_packet["index"] and
                       int(own_packet["generation"]) < int(foreign_packet["generation"]),
                       "native postjoin did not retain actual ordered own/later generations")
            for packet in held:
                if packet["index"] <= own_packet["index"]:
                    self.ipc("nativePacketRelease", str(packet["index"]))
            self.check(self.callback("postjoin-tail") is None, "original waiting tail overtook actual head completion")
            self.ipc("nativePacketsEnd"); packets_active = False
            result = self.wait_callback("postjoin-head")
            self.check(result["success"], "native verified A publication lost its truthful successful completion")
            self.check(self.wait_callback("postjoin-tail")["success"], "native postjoin lost original waiting tail")
            self.check(self.wait_callback("postjoin-F", "audit-read")["success"], "actual later F read callback was lost")
            self.wait(lambda: self.status("postjoin-settled")["detail"]["owner"]["state"] == "Idle",
                      "postjoin later accepted choice and original tail settle")
            actual = json.loads(target.read_text())
            artifacts = self.native_evidence(self.work_case / "cache/settings-conflicts")
            self.check(json_equal(actual, foreign), "native postjoin lost the later external choice or its raw unknown data")
            self.check(any(a["bytesBase64"] == foreign_read["bytesBase64"] and
                           a["metadata"]["revision"] == foreign_read["revision"] for a in artifacts),
                       "native postjoin lost the exact acquired later foreign witness")
            atomic_json(self.case / "postjoin-assertion.json", dict(nativeSerialIO=True, expected=expected,
                own=own_read, foreign=foreign_read, held=held, result=result, actual=actual, artifacts=artifacts))
        finally:
            for gate in (before, own, later):
                if gate and gate[0].exists():
                    try: self.release(gate[1])
                    except OSError as error:
                        if error.errno != 6: raise
            if packets_active: self.ipc("nativePacketsEnd")

    def corrective_setup_suffix(self):
        self.start("corrective-setup-suffix", "wizard")
        marker, fifo = self.native_gate("setup-A", "write", "general")
        target = self.config / "settings/general.json"
        try:
            self.ipc("auditWizardScale", "1.1")
            self.ipc("save", "setup-capture-A")
            self.wait(marker.exists, "actual A preparation held before controlled failure")
            self.ipc("auditWizardScale", "1.2")
            self.ipc("save", "setup-capture-B")
            self.ipc("auditWizardFinish")
            captured = self.private_state("setup-ordered-bundle-captured")
            identity = self.status("setup-ordered-submission")["detail"]["wizardSubmitted"]["id"]
            self.release(fifo, failure=True)
            a = self.wait_callback("setup-capture-A", "save-callback")
            b = self.wait_callback("setup-capture-B", "save-callback")
            self.wait(lambda: self.status("setup-ordered-terminal")["detail"]["wizardSubmitted"]["status"] in ("Stopped", "Succeeded"),
                      "actual submitted wizard terminal result")
            terminal = self.status("setup-ordered-first-status")["detail"]
            final = self.private_state("setup-ordered-terminal-native")
            self.check(not a["success"] and b["success"] and a["receipt"]["status"] == "failed" and
                       b["receipt"]["status"] == "saved", "original A-failed/B-success schedule was not established")
            self.check(any(failure["requestId"] == a["receipt"]["requestId"] and failure["status"] == "failed"
                           for failure in final["native"]["failures"]), "B success erased the recorded A failure")
            # Integration decision19: latest choice already saved; Finish may
            # succeed. The two setup-failure cases retain failed-group Retry.
            submitted = terminal["wizardSubmitted"]
            self.check(submitted["id"] == identity and submitted["status"] == "Succeeded" and
                       submitted["attemptId"] == 1 and submitted["handoff"] == "Accepted" and not terminal["wizardOpen"],
                       "already saved latest setup choice did not finish/close on its original attempt")
            self.check(json.loads(target.read_text())["scaleRatio"] == 1.2 and
                       final["current"]["consumer"]["generalScale"] == 1.2, "latest saved choice did not reach file/consumer")
            self.restart_fixture()
            cold = self.private_state("setup-ordered-cold-consumer")
            self.check(cold["current"]["consumer"]["generalScale"] == 1.2,
                       "latest setup choice did not survive a cold consumer restart")
            atomic_json(self.case / "setup-suffix-assertion.json", {"decision": 19, "identity": identity,
                "captured": captured, "a": a, "b": b, "terminal": terminal, "final": final,
                "cold": cold, "disk": json.loads(target.read_text())})
        finally:
            if marker.exists():
                try: self.release(fifo)
                except OSError as error:
                    if error.errno != 6: raise

    def corrective_helper_failure(self, variant):
        if variant == "preimage":
            return self.native_helper_preimage()
        return self.native_helper_boundary(variant)

    def native_helper_boundary(self, variant):
        self.check(variant in ("invalid", "readback", "publication"), "unknown native helper boundary")
        binding = variant == "publication"
        def seed():
            if not binding:
                (self.config / "settings/ui.json").write_text('{"fontDefaultScale":1.0}\n')
        self.start("corrective-helper-" + variant, before_launch=seed)
        section = "bindings" if binding else "ui"
        target = self.config / ("settings/" + section + ".json")
        if variant == "invalid":
            target.write_bytes(b'{"privateInvalid":\xff NOT_JSON\n')
            self.ipc("auditRead", "ui", "helper-accept-invalid", "normal")
            self.wait_callback("helper-accept-invalid", "audit-read")
        original = target.read_bytes()
        evidence = self.work_case / "cache/settings-conflicts"
        holder = self.work_case / "helper-original-version"
        before = self.native_gate("helper-before", "read-before" if variant == "invalid" else "readback", section)
        acquired = None
        retaining = None
        try:
            if binding: self.ipc("request", "macos", "helper-head")
            else: self.ipc("auditSaveScale", "1.7", "helper-head")
            self.wait(before[0].exists, "actual native helper " + variant + " boundary")
            captured = self.private_state("native-helper-captured")
            if binding: self.ipc("request", "none", "helper-tail")
            if variant == "readback":
                target.rename(holder)
                target.write_text(json.dumps({"fontDefaultScale": 1.0, "futureRaw": {
                    "helper": variant, "values": [False, 0, None, ""]}}) + "\n")
            expected_bytes = target.read_bytes()
            expected = self.inspected_state(target)
            digest = hashlib.sha256(expected_bytes).hexdigest()
            acquired = self.native_gate("helper-acquired", "read-after", section, sha256=digest)
            if not binding:
                # A failed earlier observation in the same transaction queues
                # subsequent witnesses under decision23, rather than calling the
                # destination again. The final exact-byte check covers both.
                if variant == "invalid":
                    retaining = self.native_gate("helper-retaining", "retain-before", section,
                        file=evidence, sourceId=section, sha256=digest)
                evidence.chmod(0o555)
            # A post-replacement error uses the installed backend's fault hook;
            # its subsequent read still obtains the exact real own-output bytes.
            self.release(before[1], failure=binding)
            self.wait(acquired[0].exists, "native backend genuinely acquired the helper witness")
            read = json.loads(acquired[0].read_text())["observation"]
            self.check(base64.b64decode(read["bytesBase64"]) == expected_bytes,
                       "native helper did not acquire the complete authored witness")
            if holder.exists():
                target.unlink(); holder.rename(target)
            self.release(acquired[1])
            observation = None
            if retaining:
                self.wait(retaining[0].exists, "native helper attempts actual evidence retention")
                observation = json.loads(retaining[0].read_text())["observation"]
                self.check(observation["revision"] == read["revision"] and
                           base64.b64decode(observation["bytesBase64"]) == expected_bytes,
                           "retention request changed the actual acquired bytes/revision")
                self.release(retaining[1])
            result = self.wait_callback("helper-head", "callback" if binding else "save-callback")
            first = self.private_state("helper-first-terminal")
            self.check(not result["success"], "native helper fault reported save success")
            if binding:
                self.check(result["error"] == "controlled-native-readback" and result["state"] == "Stopped",
                           "post-replacement native failure was not preserved")
                self.check(self.callback("helper-tail") is None, "publication uncertainty advanced retained tail")
            else:
                self.check(result["receipt"]["error"]["code"] == "evidence-retention",
                           "real native evidence permission failure was not reported")
                evidence.chmod(0o700)
            retried = None
            tail_settled = None
            if variant in ("readback", "publication"):
                self.ipc("retry" if binding else "save", "helper-own-output-retry")
                retried = self.wait_callback("helper-own-output-retry", "callback" if binding else "save-callback")
                if binding:
                    # The native backend has an exact published revision and a
                    # successful own-output read, despite the injected terminal
                    # error. Same-head Retry can verify that witness (#19).
                    self.check(retried["success"] and retried["requestId"] == result["requestId"] and
                               retried["attemptId"] == result["attemptId"] + 1,
                               "native verified own-output Retry did not preserve same head/new attempt")
                    self.check(self.wait_callback("helper-tail")["success"], "verified native Retry lost original tail")
                    self.wait(lambda: self.status("helper-tail-settling")["detail"]["owner"]["state"] == "Idle",
                              "actual native requests settle after the original waiting tail")
                    tail_settled = self.status("helper-tail-final-choice")
                    self.check(tail_settled["environment"] == "none" and json.loads(target.read_text())["environment"] == "none",
                               "own uncertain-publication echo replayed macos over the user's later None choice")
                else:
                    self.check(not retried["success"], "unconfirmed own output falsely resolved on Retry")
            target.write_bytes(original if variant != "invalid" else b'{"fontDefaultScale":1.7}\n')
            self.ipc("retry" if binding else "save", "helper-external-resolution")
            recovered = self.wait_callback("helper-external-resolution", "callback" if binding else "save-callback")
            external_resolution = recovered
            if binding:
                self.check(not recovered["success"] and recovered["error"] == "No stopped head is available for Retry",
                           "settled native head was unexpectedly replayed after newer external restoration")
                self.ipc("auditRead", "bindings", "helper-post-ack-external", "normal")
                self.wait_callback("helper-post-ack-external", "audit-read")
                self.check(target.read_bytes() == original, "acknowledged native output overwrote newer external choice")
            else:
                if variant == "invalid":
                    # Preserve the original external1.7 stimulus and its truthful
                    # frozen-base refusal, then resolve against the actual native
                    # accepted preimage rather than the retired helper's JSON.
                    self.check(not recovered["success"] and recovered["receipt"]["error"]["code"] == "source-preimage-conflict" and
                               json.loads(target.read_text())["fontDefaultScale"] == 1.7,
                               "invalid-source frozen retry lost latest external choice or hid its conflict")
                    target.write_bytes(b'{"fontDefaultScale":1.0}\n')
                    self.ipc("save", "helper-native-base-resolution")
                    recovered = self.wait_callback("helper-native-base-resolution", "save-callback")
                self.check(recovered["success"], "native helper fault failed after genuine accepted-base resolution")
                self.check(json.loads(target.read_text())["fontDefaultScale"] == 1.7 and
                           self.private_state("helper-recovered-consumer")["current"]["consumer"]["uiScale"] == 1.7,
                           "resolved native helper capture missed disk/live consumer")
            artifacts = self.native_evidence(evidence)
            self.check(any(a["bytesBase64"] == read["bytesBase64"] and a["metadata"]["revision"] == read["revision"]
                           for a in artifacts), "complete native helper witness was lost across failure/retry")
            atomic_json(self.case / "helper-failure-assertion.json", dict(variant=variant, expected=expected,
                acquired=read, observation=observation, captured=captured, result=result, first=first,
                ownOutputRetry=retried, tailSettled=tail_settled, externalResolution=external_resolution, recovered=recovered,
                artifacts=artifacts, final=json.loads(target.read_text())))
        finally:
            if evidence.exists(): evidence.chmod(0o700)
            if holder.exists():
                if target.exists(): target.unlink()
                holder.rename(target)
            for gate in (before, acquired, retaining):
                if gate and gate[0].exists():
                    try: self.release(gate[1])
                    except OSError as error:
                        if error.errno != 6: raise

    def native_helper_preimage(self):
        initial = {"fontDefaultScale": 1.0}
        def seed():
            (self.config / "settings/ui.json").write_text(json.dumps(initial) + "\n")
        self.start("corrective-helper-preimage", before_launch=seed)
        target = self.config / "settings/ui.json"
        original = target.read_bytes()
        foreign = (json.dumps({"fontDefaultScale": 1.0, "futureRaw": {
            "helper": "preimage", "values": [False, 0, None, ""]}}) + "\n").encode()
        digest = hashlib.sha256(foreign).hexdigest()
        evidence = self.work_case / "cache/settings-conflicts"
        before = self.native_gate("helper-before", "read-before", "ui")
        acquired = self.native_gate("helper-acquired", "read-after", "ui", sha256=digest)
        retaining = self.native_gate("helper-retaining", "retain-before", "ui", file=evidence, sourceId="ui", sha256=digest)
        holder = self.work_case / "helper-original-version"
        try:
            self.ipc("auditSaveScale", "1.7", "helper-head")
            self.wait(before[0].exists, "real native helper preflight read held")
            captured = self.private_state("native-helper-captured")
            target.rename(holder); target.write_bytes(foreign)
            expected = self.inspected_state(target)
            self.release(before[1])
            self.wait(acquired[0].exists, "native helper acquired the actual foreign preimage")
            read = json.loads(acquired[0].read_text())["observation"]
            self.check(base64.b64decode(read["bytesBase64"]) == foreign and read["presence"] == "present",
                       "native helper did not acquire the complete authored foreign bytes")
            # The worker already retained its original preflight before read().
            # Obstruct only the now-acquired foreign evidence, then restore the
            # physical original while the genuine read result remains held.
            evidence.chmod(0o555)
            target.unlink(); holder.rename(target)
            self.release(acquired[1])
            self.wait(retaining[0].exists, "actual native foreign evidence retention")
            observation = json.loads(retaining[0].read_text())["observation"]
            self.check(observation["requestId"] == captured["frozenCapture"]["requestId"] and
                       observation["revision"] == read["revision"] and base64.b64decode(observation["bytesBase64"]) == foreign,
                       "native retained observation is not the actual writer's complete acquired version")
            self.release(retaining[1])
            failed = self.wait_callback("helper-head", "save-callback")
            self.check(not failed["success"] and failed["receipt"]["error"]["code"] == "evidence-retention",
                       "real native evidence destination failure was not reported")
            self.check(target.read_bytes() == original, "failed evidence retention published over the restored preimage")
            first = self.private_state("native-helper-first-failure")
            evidence.chmod(0o700)
            self.ipc("save", "helper-external-resolution")
            recovered = self.wait_callback("helper-external-resolution", "save-callback")
            self.check(recovered["success"] and json.loads(target.read_text())["fontDefaultScale"] == 1.7 and
                       self.private_state("native-helper-recovered")["current"]["consumer"]["uiScale"] == 1.7,
                       "native failed capture did not recover to the user's latest choice")
            artifacts = self.native_evidence(evidence)
            self.check(any(artifact["bytesBase64"] == observation["bytesBase64"] and
                           artifact["metadata"]["revision"] == observation["revision"] for artifact in artifacts),
                       "only complete acquired foreign observation was lost across retention failure/retry")
            atomic_json(self.case / "helper-failure-assertion.json", dict(variant="preimage", expected=expected,
                acquired=read, observation=observation, failed=failed, first=first, recovered=recovered,
                artifacts=artifacts, final=json.loads(target.read_text())))
        finally:
            if evidence.exists(): evidence.chmod(0o700)
            if holder.exists():
                if target.exists(): target.unlink()
                holder.rename(target)
            for marker, fifo in (before, acquired, retaining):
                if marker.exists():
                    try: self.release(fifo)
                    except OSError as error:
                        if error.errno != 6: raise

    def corrective_retention_arrival(self, publication_error=False):
        return self.native_promotion_observations(publication_error, arrival=True)

    def external_transitions(self):
        legacy_data = {"settingsVersion": 60, "bindings": {"environment": "macos"},
                       "futureLegacy": {"nested": ["retained", {"unknown": 9}]}}
        def prepare():
            (self.config / "settings.json").write_text(json.dumps(legacy_data) + "\n")
        self.start("external-transitions", before_launch=prepare)
        legacy = self.config / "settings.json"
        self.check(self.status("initial-section-over-legacy")["environment"] == "none",
                   "initial section None did not override legacy macOS")
        phases = []
        target = self.config / "settings/bindings.json"
        baseline = sum(e["event"] == "handoff" for e in self.events())
        expected_raw = {"environment": "macos", "futureRaw": {"nested": ["retained", {"unknown": 7}]}}
        temp = target.with_suffix(".external")
        temp.write_text(json.dumps(expected_raw) + "\n")
        temp.replace(target)
        self.wait(lambda: sum(e["event"] == "handoff" for e in self.events()) > baseline, "external accepted transition outcome")
        first = [e for e in self.events() if e["event"] == "handoff"][baseline:]
        self.check(len(first) == 1 and first[0]["detail"]["success"] and first[0]["detail"]["selected"] == "macos",
                   "external transition did not complete exactly one captured macOS request")
        actual_raw = target.read_text()
        actual_tree = json.loads(actual_raw)
        atomic_json(self.case / "raw-preservation-assertion-1.json", {
            "transition": 1, "path": str(target), "expected": expected_raw,
            "actual": actual_tree, "actual_raw": actual_raw})
        self.check(json_equal(actual_tree, expected_raw), "external captured request discarded nested unknown raw data")
        # Repeated inspect/status messages join the live process's watcher
        # turns; own publication echoes must not become new application choices.
        for i in range(8):
            self.status("own-echo-check-" + str(i))
        self.check(sum(e["event"] == "handoff" for e in self.events()) == baseline + 1, "own write echo enqueued another request")
        for index, choice in enumerate(("none", "macos"), 2):
            expected_raw["environment"] = choice
            temp.write_text(json.dumps(expected_raw) + "\n"); temp.replace(target)
            self.wait(lambda: sum(e["event"] == "handoff" for e in self.events()) >= baseline + index,
                      "distinct external captured transition")
            actual_raw = target.read_text()
            actual_tree = json.loads(actual_raw)
            atomic_json(self.case / ("raw-preservation-assertion-" + str(index) + ".json"), {
                "transition": index, "path": str(target), "expected": expected_raw,
                "actual": actual_tree, "actual_raw": actual_raw})
            self.check(json_equal(actual_tree, expected_raw), "subsequent external transition lost raw data")
        values = [e["detail"]["selected"] for e in self.events() if e["event"] == "handoff"][baseline:]
        self.check(values == ["macos", "none", "macos"], "external transitions were omitted/coalesced/replayed: " + repr(values))

        def handoffs():
            return [e["detail"] for e in self.events() if e["event"] == "handoff"]
        def publish_legacy(choice, section_choice):
            if choice is None:
                legacy_data.pop("bindings", None)
            else:
                legacy_data["bindings"] = {"environment": choice}
            authored = (json.dumps(legacy_data) + "\n").encode()
            count = sum(e["event"] == "settings-reloaded" for e in self.events())
            before = len(handoffs())
            temporary = legacy.with_suffix(".external")
            temporary.write_bytes(authored); temporary.replace(legacy)
            self.wait(lambda: sum(e["event"] == "settings-reloaded" for e in self.events()) > count,
                      "public legacy reload completion")
            self.wait(lambda: self.status("legacy-precedence-settled")["detail"]["owner"]["state"] == "Idle",
                      "legacy precedence application settles")
            for turn in range(8):
                observed = self.status("legacy-precedence-" + str(turn))
                self.check(observed["environment"] == section_choice, "legacy edit bypassed section precedence")
            after = handoffs()[before:]
            self.check(all(r["success"] and r["selected"] == section_choice for r in after),
                       "legacy edit captured a choice outside effective section precedence")
            self.check(legacy.read_bytes() == authored, "legacy bytes/unknown entries changed during managed application")
            phases.append({"phase": "legacy-publication", "legacy_choice": choice, "section_choice": section_choice,
                           "legacy_sha256": sha(legacy), "handoffs": after})
            return authored
        def delete_section(expected, authored):
            before = len(handoffs())
            target.unlink()
            self.wait(lambda: len(handoffs()) > before, "external section deletion fallback handoff")
            self.wait(lambda: self.status("section-deletion-settled")["detail"]["owner"]["state"] == "Idle",
                      "section deletion application settles")
            after = handoffs()[before:]
            self.check(len(after) == 1 and after[0]["success"] and after[0]["selected"] == expected,
                       "section deletion did not capture exactly one effective fallback choice")
            self.check(self.status("fallback-choice")["environment"] == expected,
                       "external deletion fallback did not reach actual Settings consumer")
            self.check(legacy.read_bytes() == authored, "section deletion rewrote read-only legacy bytes")
            phases.append({"phase": "external-section-deletion", "expected": expected,
                           "legacy_sha256": sha(legacy), "handoffs": after})
        authored = publish_legacy("none", "macos")
        delete_section("none", authored)
        authored = publish_legacy("macos", "none")
        delete_section("macos", authored)
        authored = publish_legacy(None, "macos")
        delete_section("none", authored)
        atomic_json(self.case / "legacy-precedence-outcomes.json", {"phases": phases,
                    "scope": "actual section/legacy/schema precedence and external deletion; generic Reset not invoked"})

    def linked_live_paths(self):
        holder = {}
        def prepare():
            self.lifecycle.assert_quiet()
            managed = Path.home() / ".config/niri/atmosphera-session.kdl"
            referent = self.work_case / "original-session-referent.kdl"
            shutil.copy2(managed, referent)
            self.global_mutation = True  # Own the pre-launch mutation even if Popen fails.
            managed.unlink(); managed.symlink_to(referent)
            holder["snapshot"] = FileSnapshot([managed], self.case / "linked-baseline-backup")
        self.start("linked-live-paths", before_launch=prepare)
        self.ipc("request", "macos", "linked-request")
        self.check(self.wait_callback("linked-request")["success"], "actual request failed on linked managed baseline")
        self.stop()
        linked = holder["snapshot"].restore(self.lifecycle)
        self.check(all(holder["snapshot"].matches(r) for r in holder["snapshot"].records),
                   "linked baseline identity/referent bytes/metadata did not restore after actual producer")
        atomic_json(self.case / "linked-restoration.json", linked)

    def reconnect_no_replay(self):
        relay = None
        def prepare():
            nonlocal relay
            path = current_profile().session_runtime / ("bindings-harness-" + uuid.uuid4().hex[:12] + ".sock")
            relay = OwnedSocketRelay(path, self.ctx.session["NIRI_SOCKET"])
            self.env["NIRI_SOCKET"] = str(relay.path)
        try:
            self.start("reconnect-no-replay", before_launch=prepare)
            relay.disconnect()
            self.wait(lambda: not self.status("transport-disconnected")["detail"]["niriConnected"], "real connection loss")
            self.ipc("request", "macos", "disconnected-head")
            failed = self.wait_callback("disconnected-head")
            self.check(not failed["success"] and failed["state"] == "Stopped", "unavailable transport did not stop head once")
            self.ipc("request", "none", "disconnected-tail")
            relay.online = True
            self.wait(lambda: self.status("transport-reconnected")["detail"]["niriConnected"], "real niri transport reconnect")
            for index in range(8):
                state = self.status("reconnect-no-replay-" + str(index))["detail"]["owner"]
                self.check(state["state"] == "Stopped" and state["headRequestId"] == failed["requestId"]
                           and state["queueCount"] == 2, "reconnect silently resumed/replaced/advanced retained head")
            self.check(self.callback("disconnected-tail") is None, "reconnect completed tail without explicit Retry")
            self.ipc("retry", "reconnected-retry")
            retry = self.wait_callback("reconnected-retry")
            self.check(retry["success"] and retry["requestId"] == failed["requestId"]
                       and retry["attemptId"] == failed["attemptId"] + 1, "Retry after reconnect did not use same head/new attempt")
            self.check(self.wait_callback("disconnected-tail")["success"], "retained tail lost after explicit retry")
        finally:
            if relay:
                # Stop the fixture before the relay disappears; original-config
                # restoration later uses the untouched real session socket.
                self.stop()
                relay.close()

    def xdg_default_consumer(self):
        def prepare():
            original_environment = dict(l.split("=", 1) for l in self.manager_environment.stdout.splitlines() if "=" in l)
            if original_environment.get("XDG_CONFIG_HOME") not in (None, "", str(Path.home() / ".config")):
                raise HarnessBlocked("default consumer requires a matching default-XDG user-manager session")
            override = Path.home() / ".config/systemd/user/xremap-atmosphera.service"
            captured = next(r for r in self.snapshot.records if r["path"] == str(override))
            if captured["exists"]:
                raise HarnessBlocked("existing user unit override is not this test's disposable consumer definition")
            self.global_mutation = True
            override.parent.mkdir(parents=True, exist_ok=True)
            override.write_bytes((self.source / "Scripts/systemd/xremap-atmosphera.service").read_bytes())
            result = run(["systemctl", "--user", "daemon-reload"])
            if result.returncode: raise HarnessBlocked("candidate unit manager reload failed: " + result.stderr)
        self.start("xdg-default-consumer", before_launch=prepare)
        self.ipc("request", "macos", "default-consumer")
        self.check(self.wait_callback("default-consumer")["success"], "default-XDG application did not complete")
        result = run(["systemctl", "--user", "show", "xremap-atmosphera.service", "-p", "MainPID", "-p", "FragmentPath", "-p", "ExecStart"])
        if result.returncode: raise HarnessBlocked("cannot observe actual xremap consumer")
        props = dict(l.split("=", 1) for l in result.stdout.splitlines() if "=" in l)
        pid = int(props.get("MainPID", "0"))
        self.check(pid > 0, "candidate unit did not start the actual default-XDG consumer")
        if pid > 0:
            argv = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
            expected = str(Path.home() / ".config/xremap/atmosphera-xremap.yml")
            self.check(expected.encode() in argv, "xremap process consumed a different configuration path")
            self.check(Path(props["FragmentPath"]).read_bytes() == (self.source / "Scripts/systemd/xremap-atmosphera.service").read_bytes(),
                       "actual consumer unit bytes differ from the frozen approved candidate")
            atomic_json(self.case / "consumer.json", {"pid": pid, "argv": [v.decode() for v in argv if v], "unit": props,
                        "configuration": expected, "configuration_sha256": sha(Path(expected))})

    def runtime_consumers_failed_save(self):
        def prepare():
            (self.config / "settings/bar.json").write_text(json.dumps({"widgets": {"left": [
                {"id": "Tray", "pinned": [], "blacklist": [], "hidePassive": False},
                {"id": "MediaMini", "compactMode": False, "panelShowAlbumArt": True, "showVisualizer": False}],
                "center": [], "right": []}}) + "\n")
            (self.config / "settings/notifications.json").write_text('{"enabled":true}\n')
        self.start("runtime-consumers", "runtime-consumers", before_launch=prepare, wait_startup=False)
        def values(token):
            self.ipc("runtimeConsumerValues", token)
            self.wait(lambda: any(e["event"] == "runtime-consumers" and e["detail"]["token"] == token for e in self.events()), token)
            return next(e["detail"] for e in reversed(self.events()) if e["event"] == "runtime-consumers" and e["detail"]["token"] == token)
        initial = values("runtime-initial")
        bus = initial["privateBus"]
        if bus == self.ctx.session["DBUS_SESSION_BUS_ADDRESS"]:
            raise HarnessBlocked("runtime consumer sender must be isolated from original desktop bus")
        register = run(["gdbus", "call", "--address", bus, "--dest", "org.kde.StatusNotifierWatcher", "--object-path", "/StatusNotifierWatcher",
                        "--method", "org.kde.StatusNotifierWatcher.RegisterStatusNotifierItem", "org.kde.StatusNotifierItem.AtmospheraHarness"])
        if register.returncode: raise HarnessBlocked("controlled actual tray D-Bus sender registration failed: " + register.stderr)
        self.ipc("runtimeOpenDrawer")
        self.wait(lambda: values("runtime-baseline")["drawerItems"] == 1, "actual tray item reaches drawer consumer")
        def notification_owned():
            p = run(["gdbus", "call", "--address", bus, "--dest", "org.freedesktop.DBus", "--object-path", "/org/freedesktop/DBus",
                     "--method", "org.freedesktop.DBus.NameHasOwner", "org.freedesktop.Notifications"])
            if p.returncode: raise HarnessBlocked("private notification endpoint read failed: " + p.stderr)
            return "true" in p.stdout
        self.wait(notification_owned, "actual private notification server owner")
        def notify(summary):
            p = run(["gdbus", "call", "--address", bus, "--dest", "org.freedesktop.Notifications",
                     "--object-path", "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify",
                     "Atmosphera Harness", "0", "", summary, "private consumer probe", "[]", "{}", "1000"])
            if p.returncode:
                raise RuntimeError("native notification call failed: " + p.stderr)
            return p.stdout.strip()
        delivered = "harness-enabled-" + uuid.uuid4().hex
        suppressed = "harness-disabled-" + uuid.uuid4().hex
        before_notify = notify(delivered)
        self.wait(lambda: delivered in values("runtime-notification-before")["notificationSummaries"],
                  "enabled native notification reaches actual history consumer")
        baseline = values("runtime-before-edit")
        directory = self.config / "settings"
        mode = directory.stat().st_mode & 0o7777
        before_bar = (directory / "bar.json").read_bytes()
        before_notifications = (directory / "notifications.json").read_bytes()
        try:
            directory.chmod(0o555)
            self.ipc("runtimeConsumerEdit", "runtime-save-failed")
            saved = self.wait_callback("runtime-save-failed", "save-callback")
            self.check(not saved["success"], "runtime consumer test did not observe the intended real save failure")
            self.check(saved["receipt"]["error"]["code"] == "lock-failed",
                       "runtime save failed for an unrelated native IO reason")
            self.check({"bar", "notifications"}.issubset({e["detail"] for e in self.events() if e["event"] == "effective-change"}),
                       "failed persistence did not emit both public effective section changes")
            after_notify = notify(suppressed)
            for turn in range(8):
                observed = values("runtime-disabled-notification-" + str(turn))
                self.check(suppressed not in observed["notificationSummaries"]
                           and observed["notificationHistoryCount"] == baseline["notificationHistoryCount"],
                           "disabled notification still reached history after failed persistence")
            self.wait(lambda: values("runtime-updated")["trayFiltered"] == 1 and values("runtime-updated-2")["drawerItems"] == 0,
                      "real tray/drawer filtering changes from in-place settings despite failed save")
            final = values("runtime-final")
            self.check(final["trayPinned"] == ["Atmosphera Harness Tray"] and final["mediaCompact"] and not final["mediaAlbumArt"],
                       "media/tray runtime consumers did not receive effective settings on failed save")
            self.check((directory / "bar.json").read_bytes() == before_bar and (directory / "notifications.json").read_bytes() == before_notifications,
                       "consumer scenario unexpectedly persisted supposedly failed data")
            atomic_json(self.case / "runtime-consumer-outcomes.json", {"initial": initial, "baseline": baseline, "final": final,
                         "save_callback": saved, "notification_before_reply": before_notify, "notification_after_reply": after_notify,
                         "delivered_summary": delivered, "suppressed_summary": suppressed,
                         "scope": "actual components/native private bus delivery and consumer history"})
        finally:
            directory.chmod(mode)

    def callback_lifecycle(self):
        self.start("callback-lifecycle")
        def facade():
            return json.loads(self.ipc("modelFacadeState"))
        default_file = self.tree / "Configs/defaults.json"
        original_default_bytes = default_file.read_bytes()
        expected_default = json.loads(original_default_bytes)["ui"]["fontDefaultScale"]
        loaded = facade()
        self.check(loaded["defaultDefined"] and loaded["boundDefault"] == expected_default,
                   "actual bound generated default is not available after native readiness")
        # Defaults are immutable build metadata after the owner cutover, not a
        # runtime FileView. Preserve the source-corruption/restoration schedule
        # and observe that neither transition mutates runtime defaults or intent.
        try:
            default_file.write_text('{"controlledInvalidDefault":')
            failed = facade()
            self.check(failed["defaultDefined"] and failed["boundDefault"] == expected_default and
                       failed["native"]["inputPrefix"] == loaded["native"]["inputPrefix"],
                       "runtime authored-default corruption changed immutable metadata or created input")
        finally:
            default_file.write_bytes(original_default_bytes)
        restored = facade()
        self.check(restored["defaultDefined"] and restored["boundDefault"] == expected_default and
                   restored["native"]["inputPrefix"] == loaded["native"]["inputPrefix"],
                   "authored-default restoration changed the generated bound getter or created input")
        atomic_json(self.case / "supplemental-production-default-binding.json", {
            "loaded": loaded, "source_corruption": failed, "restored": restored,
            "source_default_sha256": hashlib.sha256(original_default_bytes).hexdigest(),
            "scope": "actual Settings generated default binding; runtime source edits are not metadata reloads"})
        self.ipc("requestThrow", "none", "throwing-request")
        self.ipc("request", "macos", "after-throw")
        self.check(self.wait_callback("throwing-request")["success"], "throwing callback request failed")
        self.check(self.wait_callback("after-throw")["success"], "throwing callback left the owner busy")
        self.ipc("reentrant", "none", "reentrant", "macos")
        self.check(self.wait_callback("reentrant")["success"], "reentrant original request failed")
        self.check(self.wait_callback("reentrant-nested")["success"], "reentrant enqueue was erased")
        self.ipc("saveThrow", "throwing-save")
        self.ipc("save", "after-save-throw")
        self.check(self.wait_callback("throwing-save", "save-callback")["success"], "throwing save did not persist")
        self.check(self.wait_callback("after-save-throw", "save-callback")["success"], "save exception stranded later caller")
        self.ipc("modelCallbackReentry")
        self.wait(lambda: any(e["event"] == "model-facade-contract" for e in self.events()),
                   "actual asynchronous empty-save callback registry/reentry")
        contract = next(e["detail"] for e in self.events() if e["event"] == "model-facade-contract")
        self.check(int(contract["nested"]) > int(contract["outer"]) and
                   contract["outer"] not in contract["atSignal"]["pendingRequests"] and
                   not contract["after"]["pendingRequests"],
                   "actual native callback registration/detachment crossed the wrong invocation boundary")
        self.check([e["event"] for e in contract["events"]] == ["signal", "outer-callback", "signal", "nested-callback"] and
                   [e["requestId"] for e in contract["events"]] == [contract["outer"], contract["outer"], contract["nested"], contract["nested"]] and
                   all(e["status"] == "nothing_to_save" and e["requestId"] not in e["pending"] for e in contract["events"]) and
                   all(e.get("returned") is True for e in contract["events"] if e["event"].endswith("callback")) and
                   contract["savedSignals"] == 0,
                   "empty saves violated async signal-before-callback order, no-op truthfulness or reentry")
        atomic_json(self.case / "supplemental-production-callback-registry.json", contract)
        self.ipc("hugeSave", "huge-stdin")
        self.check(self.wait_callback("huge-stdin", "save-callback")["success"], "huge stdin JSON failed")
        value = json.loads((self.config / "settings/bar.json").read_text())["middleClickCommand"]
        self.check(len(value) > 131072 and value.startswith("private-stdin-fixture-"), "huge JSON did not reach disk")
        self.check("private-stdin-fixture-" not in self.logpath.read_text(), "private JSON leaked into command logs")

    def child_fault(self, fault):
        def prepare():
            owner = self.tree / "Services/Keyboard/BindingsService.qml"
            text = owner.read_text()
            if fault == "missing":
                text = text.replace('OwnedProcess.run(root, ["env",', 'OwnedProcess.run(root, ["/nonexistent/fifo-child",')
            else:
                dispatcher = self.tree / "Scripts/bash/atmosphera"
                dispatcher.write_text("#!/usr/bin/env bash\nulimit -c 0\nkill -ABRT $$\n")
            owner.write_text(text)
        self.start("child-fault-" + fault, before_launch=prepare)
        self.ipc("request", "macos", "child-head")
        self.ipc("request", "none", "child-tail")
        result = self.wait_callback("child-head")
        self.check(not result["success"] and result["state"] == "Stopped", "child lifecycle did not terminate once")
        self.check(self.callback("child-tail") is None, "child failure advanced tail")
        state = self.status("child-stopped")
        self.check(state["detail"]["owner"]["queueCount"] == 2, "child failure lost retained work")

    def generation_fault(self):
        self.start("generation-fault")
        marker, fifo = self.gate("generation-failed", "sh", '[[ "${2:-}" == *"Base config detected at niri boot"* ]]')
        wrapper = self.tree / "Scripts/bash/sh"
        wrapper.write_text(wrapper.read_text().replace("fi\nexec", "  exit 17\nfi\nexec"))
        try:
            self.ipc("request", "macos", "generation-head")
            self.wait(marker.exists, "failed generation gate")
            self.ipc("request", "none", "generation-tail")
        finally:
            if marker.exists(): self.release(fifo)
        result = self.wait_callback("generation-head")
        self.check(not result["success"] and result["state"] == "Stopped", "generation failure did not stop")
        self.check(self.callback("generation-tail") is None, "generation failure advanced tail")
        self.ipc("retry", "generation-retry")
        self.check(self.wait_callback("generation-retry")["success"], "generation same-head retry failed")
        self.check(self.wait_callback("generation-tail")["success"], "generation retained tail was lost")

    def null_handoff(self):
        def prepare():
            ipc = self.tree / "Services/Compositor/NiriSessionIpc.qml"
            text = ipc.read_text().replace("  property int peerPid: -1", "  property int peerPid: -1\n  property int faultCalls: 0")
            text = text.replace("  function activate(path, onComplete) {", "  function activate(path, onComplete) {\n    root.faultCalls++;")
            text = text.replace("var reply = NiriActions.sendAction(", "var reply = root.faultCalls > 1 ? null : NiriActions.sendAction(")
            ipc.write_text(text)
        self.start("null-handoff", before_launch=prepare)
        self.ipc("request", "macos", "null-head")
        self.ipc("request", "none", "null-tail")
        result = self.wait_callback("null-head")
        self.check(not result["success"] and result["state"] == "Stopped", "null typed reply left owner busy")
        self.check(self.callback("null-tail") is None, "null reply advanced the tail")

    def later_reload_diagnostic(self):
        self.start("later-reload")
        self.ipc("request", "macos", "accepted-handoff")
        self.check(self.wait_callback("accepted-handoff")["success"], "handoff acknowledgement failed")
        base_layer = Path.home() / ".config/niri/atmosphera.kdl"
        original = base_layer.read_bytes()
        try:
            base_layer.write_bytes(original + b"\nTHIS_IS_NOT_VALID_KDL {\n")
            # Accepted handoff is intentionally earlier than config parsing.
            # Trigger a separate actual reload after corruption, rather than
            # racing the previous request's asynchronous watcher installation.
            diagnostic_env = self.ctx.env({"NIRI_LOAD_CONFIG": str(Path.home() / ".config/niri/atmosphera-session.kdl")})
            diagnostic = run(["qs", "-p", str(HERE / "fixtures/niri-load-config.qml")], env=diagnostic_env, timeout=30)
            atomic_json(self.case / "separate-reload-trigger.json", {"exit": diagnostic.returncode})
            self.wait(lambda: "generic configuration reload failure" in self.logpath.read_text(), "separate generic reload diagnostic")
            self.check(sum(e["event"] == "callback" and e["detail"]["token"] == "accepted-handoff" for e in self.events()) == 1,
                       "later reload fabricated/revoked a request completion")
            self.check(self.callback("accepted-handoff")["success"], "generic reload failure revoked handoff acceptance")
        finally:
            base_layer.write_bytes(original)

    def startup_gate(self):
        holder = {}
        def prepare():
            holder["gate"] = self.gate("startup-keyd", "sh", '[[ "${2:-}" == *"awk"* && "${2:-}" == *"ids"* ]]')
        self.start("startup-held", before_launch=prepare, wait_startup=False)
        marker, fifo = holder["gate"]
        try:
            self.wait(marker.exists, "held startup keyd writer")
            self.ipc("request", "macos", "after-startup")
            state = self.status("startup-waiting")
            self.check(state["environment"] == "none", "request bypassed startup and changed shared adapter")
            self.check(self.callback("after-startup") is None, "request completed before startup")
        finally:
            if marker.exists(): self.release(fifo)
        self.check(self.wait_callback("after-startup")["success"], "startup waiting request failed")
        self.ipc("repeatInit", "duplicate-init")
        self.wait(lambda: any(e["event"] == "startup-observer" for e in self.events()), "completed startup observer")
        self.check(sum(e["event"] == "stage" and e["detail"]["stage"] == "startup" for e in self.events()) == 1,
                   "duplicate init reran startup side effects")

    def teardown_guard(self):
        self.start("teardown-guard")
        before = sha(Path.home() / ".config/niri/atmosphera-session.kdl")
        self.ipc("teardownFault")
        refused = False
        try: self.stop()
        except (RuntimeError, subprocess.TimeoutExpired): refused = True
        self.check(refused and self.process is not None and self.process.poll() is None, "teardown fault was swallowed")
        try:
            self.restore()
            self.check(False, "live producer restoration was allowed")
        except RuntimeError as error:
            self.check("live" in str(error), "restoration failed for an unrelated reason")
        self.check(sha(Path.home() / ".config/niri/atmosphera-session.kdl") == before, "teardown refusal still rewrote configuration")
        self.stop()

def execute_selected(selected, runner, output):
    results, halted = [], False
    for record in selected:
        identity = record["id"]
        if record["coverage_status"] != "RUNNABLE":
            results.append({"id": identity, "status": record["coverage_status"], "reason": record["reason"], "executed": False})
            continue
        if halted:
            results.append({"id": identity, "status": "NOT_RUN", "reason": "unsafe/capacity-blocked predecessor; no automatic continuation", "executed": False})
            continue
        runner.current_id = identity
        runner.case = None
        runner.live_started = False
        start_failures = len(runner.failures)
        result = {"id": identity, "status": "PASS", "executed": True, "primary_errors": [], "cleanup_errors": []}
        try:
            if "physical-input" in record["prerequisites"] and not current_profile().qmp_prefix:
                result["executed"] = False
                raise HarnessBlocked("profile has no verified hardware QMP injection command")
            getattr(runner, record["callable"])(*record["args"])
        except (HarnessBlocked, runner.bindings.Blocked) as error:
            result["status"] = "BLOCKED"
            result["primary_errors"].append(repr(error))
        except Exception as error:
            result["status"] = "FAIL"
            result["primary_errors"].append(repr(error))
        finally:
            try:
                runner.ctx.restore_all()
                runner.stop()
            except Exception as error:
                result["cleanup_errors"].append("quiescence/stop: " + repr(error))
                halted = True
            if not result["cleanup_errors"]:
                try:
                    runner.audit_case_end()
                except HarnessBlocked as error:
                    result["status"] = "BLOCKED"
                    result["primary_errors"].append("end observation: " + repr(error))
                    halted = True
                except Exception as error:
                    result["status"] = "FAIL"
                    result["primary_errors"].append("end observation: " + repr(error))
                try:
                    result["restoration"] = runner.restore()
                    if getattr(getattr(runner, "workspace", None), "archive_completed", False) and runner.case:
                        runner.workspace.archive_case_tree(runner.work_case, runner.lifecycle)
                except Exception as error:
                    result["cleanup_errors"].append("restoration: " + repr(error))
                    halted = True
        result["failures"] = runner.failures[start_failures:]
        if result["failures"]:
            result["status"] = "FAIL"
        elif result["cleanup_errors"] and result["status"] != "FAIL":
            result["status"] = "BLOCKED"
        if result["status"] == "BLOCKED":
            halted = True
        results.append(result)
        try:
            atomic_json(output / (identity + ".result.json"), result)
            atomic_json(output / "progress.json", aggregate_results(selected, results))
        except Exception as error:
            result["status"] = "FAIL"
            result["cleanup_errors"].append("journal: " + repr(error))
            print(json.dumps(result), file=sys.stderr, flush=True)
            halted = True
    return aggregate_results(selected, results)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--list-cases", action="store_true")
    ap.add_argument("--source", type=Path)
    ap.add_argument("--output", type=Path)
    ap.add_argument("--work-root", type=Path)
    ap.add_argument("--case", default="all", help="stable case ID or group(s); all includes deferred required coverage")
    profile_argument(ap, required=False)
    ap.add_argument("--archive-completed-copies", action="store_true",
                    help="retain verified quiesced disposable trees as lossless archives on scratch")
    a = ap.parse_args(argv)
    if a.list_cases:
        print(json.dumps({"cases": CASE_REGISTRY, "all_ids": [c["id"] for c in select_cases("all")]}, indent=2))
        return 0
    if not all((a.source, a.output, a.work_root)):
        ap.error("--source, --output and --work-root are required for execution")
    if a.guest_profile is None:
        ap.error("--guest-profile is required for execution")
    try:
        selected = select_cases(a.case)
    except ValueError as error:
        ap.error(str(error))
    workspace, runner = None, None
    try:
        activate_profile(a.guest_profile, require_console=True)
        workspace = Workspace(a.source, a.output, a.work_root, archive_completed=a.archive_completed_copies)
        if any(c["coverage_status"] == "RUNNABLE" for c in selected):
            runner = Runner(workspace)
            summary = execute_selected(selected, runner, workspace.output)
        else:
            summary = aggregate_results(selected, [])
        summary["storage"] = workspace.peak
    except Exception as error:
        # Never construct a second Runner or run a blind finally on failed init.
        summary = aggregate_results(selected, [{"id": selected[0]["id"], "status": "BLOCKED",
            "executed": False, "primary_errors": [repr(error)], "cleanup_errors": []}])
        print(json.dumps(summary), file=sys.stderr, flush=True)
        if workspace is None:
            # An existing/unsafe output must not be touched, even to report failure.
            print("BINDINGS_DEPLOYMENT_REGRESSION: BLOCKED — preflight/refusal", flush=True)
            return 2
    finally:
        if runner is not None:
            runner.lifecycle.close()
    return publish_summary(workspace.output, summary)


if __name__ == "__main__":
    raise SystemExit(main())
