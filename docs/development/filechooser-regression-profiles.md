# File chooser regression profiles

File chooser runners follow the settings runners' explicit guest-profile design
(commit `4b6a1c1`). No guest identity or workspace defaults to a historical VM.
Pass `--guest-profile FILE` to every top-level invocation. Owned private children
inherit that exact profile path and captured SHA256 through their scrubbed
environment. A profile identifies a separately authorized target, not permission.

The public JSON profile specifies version 1, name, UUID, MAC, Ed25519 host public
key, UID, real account home, disk-backed workspace, and disjoint canonical source,
evidence and runtime paths beneath that workspace. The outer controller verifies
DMI UUID, MAC, account/home, host key, ownership and disk TMPDIR before creating
roots or starting a workload. Private PID-namespace children retain the existing
account/MAC checks, additionally validate the captured profile digest and roots,
and retain all private bus/compositor/keyboard, cgroup, resource, serialization,
process-audit and namespace checks. Privileged DMI inspection stays outside the
unprivileged user namespace, before workload launch.

For the assigned `atmosphera-mov-filter` VM on `ark.home`, run only inside the
guest, from `/home/tester/Projects/filechooser-usability/source`:

```sh
export TMPDIR=/home/tester/Projects/filechooser-usability/tmp
profile=$PWD/Scripts/dev/fixtures/guest-profiles/atmosphera-mov-filter.json
timeout 900 python3 -B Scripts/dev/filechooser-units.py --guest-profile "$profile" --source "$PWD" --output "$PWD/../evidence/units-LABEL"
timeout 900 python3 -B Scripts/dev/filechooser-portal-regression.py --guest-profile "$profile" --source "$PWD" --label portal-LABEL
timeout 900 python3 -B Scripts/dev/filechooser-ui-regression.py --guest-profile "$profile" --source "$PWD" --label ui-LABEL
```

Each label must be fresh. `filechooser_regression.py` is their shared library,
not a CLI. These commands preserve complete extracted working trees and evidence;
they create no workspace capsules. The profile must be explicitly updated when
the authorized guest changes. Do not spoof a MAC or weaken a failing check.

The UI runner also accepts `--path-only` for a short path-entry partition during
iteration. It retains its runtime-error and isolation gates. Omit that flag for
the full pre-commit proof; it does not replace the complete UI walk. Unit output
paths must be absolute because the private supervisor changes working directory.

The private supervisor also owns a PipeWire server and policy-only WirePlumber
with one null sink. It loads no hardware monitors and cannot connect to a login
or host audio endpoint. The initial graph is recorded as `audio-graph.json`;
all audio processes retain the same namespace, cgroup and process audit as the
compositor and keyboard. Install `pipewire` and `wireplumber` inside the assigned
guest alongside the existing Sway, media/image/PDF and compiler prerequisites.

The unit suite's real EROFS case uses an explicitly provisioned read-only bind
mount inside the assigned guest workspace. It changes no host or shared mount.
Before units, run inside `atmosphera-mov-filter` on `ark.home`:

```sh
export TMPDIR=/home/tester/Projects/filechooser-usability/tmp
timeout 10 mkdir -p /home/tester/Projects/filechooser-usability/fixtures/read-only-source /home/tester/Projects/filechooser-usability/fixtures/read-only
timeout 10 sudo mount --bind /home/tester/Projects/filechooser-usability/fixtures/read-only-source /home/tester/Projects/filechooser-usability/fixtures/read-only
timeout 10 sudo mount -o remount,bind,ro /home/tester/Projects/filechooser-usability/fixtures/read-only
```

The private unprivileged test namespace inherits this mount read-only. The suite
checks ST_RDONLY, rather than substituting chmod for a filesystem error. Guest
shutdown removes the temporary mount; provision it again after a reboot.

Real-browser runs additionally seal the exact waiting private supervisor's OOM
minimum at 1000 before admitting any workload children. The outer controller
uses a fixed, short-lived guest-root helper, validating DMI UUID, UID, process
start time, command, namespace and cgroup through a pinned proc directory. The
helper only writes 1000 and launches no child workload. A fresh unprivileged
child must observe 1000 and a denied attempt to lower it; receipts are retained.
No capability is granted to the browser. Caps, sandboxing and all original audit
checks are unchanged; there is no score-repair loop or browser exception.
Only browser walks set LP_NUM_THREADS=1 and RAYON_NUM_THREADS=1 for their private
session's renderer pools, matching the existing one-CPU quota and task cap.
Other runners, especially the matched-idle scroll measurement, retain their
original environment. Firefox's disposable profile disables unused new-tab
preloading to avoid an extra privileged-content process within that same cap.
The disposable browser also inherits one allowed CPU through `taskset`, so its
CPU-derived startup pools match the session's one-CPU quota. The selected CPU is
recorded in its browser profile receipt. All sandbox and task/memory/OOM checks
remain; the shell, other runners and scroll measurements are not affinity-pinned.
Browser and full-UI subjects reuse `filechooser-no-thp.py` and the existing media
resource-test allocator profile (`dirty_decay_ms:0,muzzy_decay_ms:0`), avoiding
huge-page/free-page retention under MemoryHigh. Both are process-only; no kernel
policy or accounting limit changes. Browser profile receipts record these inputs;
the UI uses the same profile to avoid retained software-renderer pages across
its many dialog/media cycles. Scroll benchmarks keep their original profile.

```sh
timeout 900 python3 -B Scripts/dev/filechooser-browser-regression.py --guest-profile "$profile" --source "$PWD" --label browser-LABEL --browser chromium
timeout 900 python3 -B Scripts/dev/filechooser-browser-regression.py --guest-profile "$profile" --source "$PWD" --label browser-LABEL2 --browser firefox
```

## Assistive technology

Install `python-atspi`, `orca`, `espeak-ng` and `speech-dispatcher` inside the
assigned guest. Run from the same guest source/workspace with the same profile:

```sh
timeout 900 python3 -B Scripts/dev/filechooser-a11y-regression.py --guest-profile "$profile" --source "$PWD" --label a11y-LABEL
```

This runner preserves native AT-SPI trees, focus and announcement events, a
reversible keyboard focus walk and Orca's generated speech. It launches the
native accessibility bus/registry and speech dispatcher inside the existing
private compositor's audited/capped PID namespace. The a11y launcher uses
`ATSPI_DBUS_IMPLEMENTATION=dbus-daemon` so service activation does not address
an external user manager; the explicit registry is a private child. Its socket
path is checked against the launcher's path-length limit, avoiding its temporary
directory fallback. Orca's enablement uses the private bus with an in-memory
GSettings backend. espeak-ng outputs only to the existing private PipeWire null
sink. No login-session settings, accessibility stack or audio endpoints change.

The sibling runtime directory `<label>-a11y` holds stack logs and the result;
the normal evidence directory holds tree dumps and the harness log. `--inspect`
captures only the initial tree for diagnosis and is not a full verification.

## File operations

The guest needs `wl-clipboard` and GLib's `gio` command, matching the runtime
package dependencies. The unit runner also exercises the JSON mutation worker
against real files, Trash metadata/collisions, permission errors, no-clobber
rename, identity-checked permanent deletion and symlink-safe recursive deletion.
The UI runner includes native keyboard/mouse file operations. For iteration only,
`--operations-only` runs that partition with the same isolation/runtime gates;
omit it for the full pre-commit proof. Native AT-SPI coverage includes action
menus/submenus, inline rename, error announcements and safe delete confirmation.
