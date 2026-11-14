# Regression guest profiles

Settings/model/bindings runners require an explicit `--guest-profile FILE` for
execution. `--help` and the deployment runner's `--list-cases` remain side-effect-
free discovery commands. A profile is public expected identity, **not permission**
to run a workload or change a VM. Use the task's separately authorized guest route.

The shared `Scripts/dev/guest_profile.py` boundary checks the guest account/home,
SMBIOS UUID, NIC MAC and exact public SSH host key before preparing directories or
launching fixtures. It also checks canonical owned disk roots, disk TMPDIR and the
profile's real niri/Wayland session. Missing/mismatched identity fails closed;
there is no default guest, discovery acceptance, MAC substitution or relaxed SSH
trust. The access connector must independently verify its peer host key.

At run start, the original named console's PID, kernel start time, UID, process
group and argv are captured. Live Settings/deployment execution requires that
console. Ownership/termination and restoration guards protect this captured
identity, not a PID baked into source. An absent console in an inert model or
mechanics run is recorded as absent; those commands cannot acquire an arbitrary
existing console as an owned child.

| # | Profile fields | Meaning |
|---|---|---|
| 1 | version, name, uuid, mac, sshHostKey | Format 1 and explicit guest identity; sshHostKey contains only a public Ed25519 key. |
| 2 | uid, home, workspace | Expected guest account and owned disk-backed task workspace. |
| 3 | workBase, journalBase, runtimeBase | Canonical disjoint roots inside that workspace; fresh work/output children remain mandatory. |
| 4 | sessionRuntime, waylandDisplay, consoleConfig | Existing real compositor/runtime and named original console selector. |
| 5 | qmpCommand | Explicit argument-vector template with one `{event}` element for hardware injection. Null means unavailable and refuses physical-input work; it never substitutes compositor/virtual input. |

`fixtures/guest-profiles/agora-804.json` records the integration's authorized agora
VM 804, `dev-niri-atmosphera-typing-stall`. `ark-gtkfree.json` preserves the old
guest identity/paths as metadata; it is not an executable default or authorization
to access Ark. Revalidate/update a profile explicitly if an operator rotates a
host key or provisions a different guest; never weaken a mismatch in the runner.

## Integration example

Source editing/commits happen in the task worktree. All builds/tests/runtime for
this integration execute **inside agora VM 804**, via agora-niri, guest workspace
`/home/tester/Projects/atcq`; never on the laptop, Ark or the agora host. Library
tests may use VM 806 only as separately authorized by their plan. Stop if the
named guest is unavailable. Deliver the exact candidate into `source/`, provide
the original console, and from the laptop use a bounded guest command such as:

```sh
timeout 90s /home/user/.local/bin/agora-niri ssh 804 -- 'timeout 60s env TMPDIR=/home/tester/Projects/atcq/tmp LANG=C.UTF-8 python3 -B /home/tester/Projects/atcq/source/Scripts/dev/settings-model-regression.py --guest-profile /home/tester/Projects/atcq/source/Scripts/dev/fixtures/guest-profiles/agora-804.json --source /home/tester/Projects/atcq/source --output /home/tester/Projects/atcq/artifacts/runners/settings-model-ownership/fresh-run --case all'
```

Private fixture engines use short disk-backed runtime directories. Wayland
consumers receive the absolute original display socket, while niri and D-Bus
addresses retain their real-session identities. This keeps fixture IPC/logs off
RAM-backed temporary storage without redirecting input to another compositor.
The private root forwards the actual session bus/systemd/pulse endpoints and keeps
PipeWire pointed at the real session: systemctl's direct user-manager socket does
not honor DBUS_SESSION_BUS_ADDRESS alone. Profile selftests query the actual
manager through this environment; no replies or activation are simulated.

## Capacity and evidence retention

Existing two-extracted-copy, byte/inode/runtime/journal reserves, protected desktop,
descendant quiescence, metadata/symlink restoration, and pending/blocked coverage
gates remain in force. Existing outputs and historical trees are never reused.

Settings/deployment runners offer opt-in `--archive-completed-copies` for a long
baseline. After successful restoration and verified quiescence, **this run's exact
disposable workspace** (source tree and generated synthetic config/cache) is
stored in a scratch `.tar.gz`. Every byte, link,
mode, UID/GID, nanosecond mtime and xattr is verified, a checksum/manifest is recorded
in the journal, and only then is the extracted workspace reclaimed. Live, foreign,
changed, corrupt, or existing-archive cases refuse and retain their data. Archives
preserve the disposable instrumentation as well as the original candidate; no
application settings, canonical source, old evidence or failed restoration is
discarded. Older verified source-only capsules are retained inside the complete
workspace capsule. The default keeps extracted copies exactly as before, and the ceiling
still refuses a third unarchived copy. Mechanics selftests exercise both policies.

Use actual case IDs and preserve the deployment registry's pending user-decision
and pending live-prerequisite entries. A baseline with missing hardware transport
or other prerequisites is BLOCKED, not PASS. Retain its result and restoration
facts rather than faking input or loosening an assertion. Restore the console and
shut down assigned guests at the end of the authorized task.
