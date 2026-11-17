# NetworkManager state ownership

`NmState` owns the NetworkManager owner epoch, root subscriptions, inventories and
commands. `NetworkService` and `VPNService` only project replacement fact snapshots
and present errors/toasts. Widgets and panels retain their existing APIs.

| # | Record | Ownership and lifetime |
|---|---|---|
| 1 | NmState | Watches actual NameOwnerChanged before resolving the current owner. One session per unique owner; no command replay. |
| 2 | NmProfile | One retained Settings.Connection interface per saved path, for every profile type. Updated rereads that profile only, coalescing bursts. Only a compact summary is retained. |
| 3 | NmActiveConnection | One record per active path, not per UUID. Properties and real StateChanged determine outcomes, including WireGuard. |
| 4 | NmDevice | Owns base and applicable wired/wireless interfaces. Linked active/AP/IP facts are injected inputs, never child-object reads. |
| 5 | NmAccessPoint, NmIpConfig | Shared path/interface records, retained while referenced. Same-path changes reach both device details and facade projections. |

The reusable `NmDevice.Interface` inline type is explicitly Unbound: it captures
only its own IDs and must be constructible by sibling record files. It retains
one dbusqml proxy plus explicit interface/Properties watchers. Automatic proxy
property/signal handling is disabled. The adapter attaches watchers before one
GetAll and owns revisions and invalidation Gets itself. This avoids dbusqml
1.1.2's signal-before-cache ordering and duplicate invalidation reads when both
layers try to handle the same invalidation. Children that reject introspection
still have explicit watchers and finite, signature-declared reads/commands.

Failed interface reads arm one owner-scoped, one-shot reconciliation retry with
exponential backoff from 250 ms to 30 seconds. A successful GetAll resets the
backoff and leaves no timer running. Retirement cancels recovery, and late
replies cannot publish into retired records. This shared contract covers the
manager and retained device, wireless, active, AP and IP interfaces, including
failed invalidation reads; it is not periodic freshness polling.

Per-field versions protect newer payloads from late reads. Membership events
and tombstones protect in-flight inventories, then are retired; they are not an
unbounded event log. Profile settings reads use revision/dirty-again guards.
Record notifications queue publication, avoiding reentrant creation and input
binding loops. Public snapshots do not expose proxies, replies or mutable
registry objects. Native boxed object paths are normalized at the boundary.

Sessions, records and retained interfaces use non-visual `Scope` roots. Device
subinterfaces use `Instantiator`, never graphical `Loader` objects. The ownership
gate rejects graphical backend objects as well as duplicate transport owners.

`NmSsid.js` is the shared AP/profile byte-decoding boundary. dbusqml 1.1.2 delivers
NM `ay` values as `ArrayBuffer`, including inside `a{sv}`. Empty native byte
buffers must be recognized before `textFromBytes` constructs a typed-array view;
Qt can reject a view of the null backing store of an empty `QByteArray`. Absent
and empty values yield an empty SSID. Non-empty bytes retain the library's UTF-8
decoding, with replacement characters for invalid sequences. Profile display
names are NM strings and never pass through a byte decoder.
SSID-keyed facade maps have null prototypes from initialization through
projection, so names such as `toString`, `constructor` and `__proto__` are data,
not inherited members. Controlled tests require their actual rendered rows.

Enterprise certificate settings use NM's byte-array path scheme: an absolute
CA certificate path becomes `file://` plus its UTF-8 path and a NUL terminator.
Already-qualified URI/token values are preserved. Both facade call shapes share
this owner-side encoding; the controlled peer checks the complete wire value.

## Commands and recovery

Operations have an identity and compact `accepted`, `completed` or `error` results.
Acceptance is not success. Activation waits for the returned active path's
observed activated state; deactivation waits for all selected instances to end.
Removal, owner loss, request errors and finite failure-only deadlines settle
busy state once. Delete is confirmed by removal, even if removal beats its reply.
Wireless LastScan advancement completes a scan, including a signal before the
RequestScan reply. A scan never enumerates profiles.

Owner replacement retires the entire old graph, publishes empty/unavailable
facts, cancels operations without replay, then performs one new-owner seed.
System-bus disconnection is different: dbusqml reports it but does not reconnect.
The degraded error requests a shell reload after bus restoration; NM owner
watching cannot repair a disconnected bus.

Explicit refresh methods remain available for targeted reconciliation. There
are no periodic refresh, profile reload, detail-TTL or scan timers. Facade
one-shot startup/radio scans and toast debounce remain separate from state
freshness. Neither method acceptance nor a compatibility setter fabricates
active/connected daemon state. Secret failures never delete saved profiles.

## Guest verification

All commands below run inside `atmosphera-nm-events` on `ark.home`, never on the
physical host. The profile is generated outside the repository from that fork's
verified receipt. Source is `/home/tester/Projects/nm-events/source`; TMPDIR is
`/home/tester/Projects/nm-events/tmp`. Each runtime output directory must be new.

```sh
export TMPDIR=/home/tester/Projects/nm-events/tmp
cd /home/tester/Projects/nm-events/source
python3 -B Scripts/dev/nm-ownership-regression.py --root .
python3 -B Scripts/dev/nm-protocol-characterization.py --guest-profile ../guest-profile.json --work ../artifacts/protocol-1
python3 -B Scripts/dev/nm-event-regression.py --guest-profile ../guest-profile.json --work ../artifacts/events-1
```

The protocol runner includes a negative canary for mixed invalidation ownership,
then proves one read with a single explicit owner and signals from a child that
rejects introspection. Event tests execute production records over a separate
guest-private bus. Controlled AP/security/scan results are not physical-radio
proof. Runtime runners retain result.json, logs and cleanup status and join all
owned processes before returning. Full consumer, wire, restart and memory
acceptance is specified by the external event-driven implementation plan.

## Real consumer and wire runners

Inside the same identity-pinned guest, with a fresh output directory for each run:

```sh
python3 -B Scripts/dev/nm-widget-e2e.py --guest-profile /home/tester/Projects/nm-events/guest-profile.json --work /home/tester/Projects/nm-events/artifacts/lifecycle-1 --case lifecycle
python3 -B Scripts/dev/nm-widget-e2e.py --guest-profile /home/tester/Projects/nm-events/guest-profile.json --work /home/tester/Projects/nm-events/artifacts/actions-1 --case actions
python3 -B Scripts/dev/nm-widget-e2e.py --guest-profile /home/tester/Projects/nm-events/guest-profile.json --work /home/tester/Projects/nm-events/artifacts/restart-1 --case restart
python3 -B Scripts/dev/nm-widget-e2e.py --guest-profile /home/tester/Projects/nm-events/guest-profile.json --work /home/tester/Projects/nm-events/artifacts/network-1 --case network
python3 -B Scripts/dev/nm-widget-e2e.py --guest-profile /home/tester/Projects/nm-events/guest-profile.json --work /home/tester/Projects/nm-events/artifacts/wifi-1 --case wifi
python3 -B Scripts/dev/nm-idle-wire.py --guest-profile /home/tester/Projects/nm-events/guest-profile.json --work /home/tester/Projects/nm-events/artifacts/idle-1 --seconds 600
python3 -B Scripts/dev/nm-runner-selftest.py --guest-profile /home/tester/Projects/nm-events/guest-profile.json --work /home/tester/Projects/nm-events/artifacts/runner-selftest-1
```

The consumer runner copies the candidate tree and inserts read-only observers in
that disposable copy. Production VPN/NetworkPanel components, facades and dbusqml
remain in the path. Native Wayland pointer events open the widget/menu and select
actions. A requested FrameAnimation observes settled Text/icon/menu delegates;
the Python receipt time is a conservative upper bound after that frame. The signal
observer uses the same guest monotonic clock. Test observation never provides
state to the product.

The VPN widget is placed at the bar center in the test configuration so transient
top-right notification surfaces cannot intercept the next menu action. Icon-plugin
readiness is part of fixture startup. Raw logs retain the unchanged HostService
icon binding warning separately from new runtime exceptions.

Live fixtures install a temporary tester-only guest polkit rule, own every profile
by UUID before mutation, and remove only those profiles and that rule at teardown.
WG fixtures have no peer, default route or DNS change. No private key enters results.
The network case additionally requires a task-owned disposable virtio Ethernet NIC,
with autoconnect prevented before hotplug. Its external guest-workspace
`ethernet-fixture.json` contains `guestUuid` and `mac`; the runner rejects the
management MAC, resolves exactly one matching guest interface and checks its NM
type before creating a no-default-route/no-DNS static profile. The management
connection, default routes and resolver contents must remain unchanged.

Controlled-daemon legs run on a separate guest-private bus with real dbusqml and
real consumer components. These cover accepted-then-failed activation and
Wi-Fi/AP/IP/security/scan contracts, not a physical Wi-Fi radio or remote VPN peer.
Every result distinguishes controlled and live cases.
The `wifi` case runs the controlled network leg alone, including rendered saved
UTF-8 SSIDs behind an empty hidden AP, invalid UTF-8 SSIDs and profile names.

The wire runner retains both broad raw traffic and the measured interval, resolves
all shell system-bus names by PID, records dynamic name membership, and proves the
monitor saw the actual shell seed before measuring zero idle calls. Parser canaries
inject both NM destination forms, multiple shell names, setup churn, unrelated
senders and malformed headers. Any external NM transition makes the interval
non-idle; preserve it and repeat a new full interval rather than filtering it away.

The runner selftest includes a real SIGTERM during shell construction and requires
an explicit failed receipt, joined children, restored niri configuration and no
remaining guest polkit fixture. Its cancellation exception is not an OSError:
Python's subprocess/select machinery can retry and swallow InterruptedError.
It also injects signal-worker construction interruption, authorization install/
ledger failures and owned-child teardown failure. Constructors clean up before
returning failure, and CLI completion rejects unsuccessful teardown without
replacing an in-flight body exception.
The same selftest exercises full-scale synthetic smaps analysis, including a known
growing series; synthetic data never substitutes for an actual memory soak.

## Memory observation

Run inside the same pinned guest and disk workspace. Preserve the original tester
lingering and user-manager TMPDIR first; enable lingering and give D-Bus-activated
guest services the disk TMPDIR too. Restore both after joining the job and any
task-activated service. Never import a signing agent or host credentials.

```sh
export WORK=/home/tester/Projects/nm-events
export TMPDIR="$WORK/tmp"
sudo loginctl enable-linger tester
systemctl --user set-environment TMPDIR="$TMPDIR"
systemd-run --user --unit=atmosphera-nm-memory --property=KillMode=mixed --property=WorkingDirectory="$WORK/source" --setenv=TMPDIR="$TMPDIR" python3 -B "$WORK/source/Scripts/dev/nm-memory-soak.py" --guest-profile "$WORK/guest-profile.json" --work "$WORK/artifacts/memory-1" --idle-seconds 3600 --cycles 30 --interval 30
```

Use a new output directory. A workspace lock and the named unit prevent duplicate
collectors; inspect the existing PID, start time, cgroup and status rather than
relaunching after an SSH timeout. The runner warms one real shell for 60 seconds,
samples Pss_Anon and SwapPss for at least 3600 uninterrupted idle seconds, then
performs 30 safe WireGuard add/up/down/delete cycles and settles for 30 seconds.
Every cycle must retire all records to baseline. Shell PID/start time and NM owner
must remain unchanged. State-changing NM transitions, observer failure, residual
operations and new runtime exceptions fail the observation; failed data is retained.

The memory harness classifies real DHCP4Config.Options signals separately only
when lease expiry advances and every other option stays identical. Changed address,
router, DNS, lease duration, invalidations, another sender/path/interface or extra
properties fail its negative canaries and remain disallowed transitions. Each
renewal is timestamped beside its surrounding memory samples and retained in
`dhcp-renewals.jsonl`, with unchanged published network facts, record counts and
management routes/resolver required. This is external signal handling, not polling.
The harness never initiates a product refresh. A full-interval raw wire capture
checks every shell system-bus name and observes its startup seed; no shell NM
method or subscription-setup churn is allowed during idle or these renewals because
expiry bookkeeping invalidates none of the backend's watched facts. Raw NM signals
must exactly match the separately retained renewal count. Other transitions are
not filtered away, and the separate stable ten-minute wire gate is unchanged.
The broad capture relay and its privileged child are joined before creating any
cycle profile: raw capture must never include private-key marshalling. A teardown
gate enforces that boundary. KillMode=mixed lets the runner restore its own children
on cancellation instead of terminating the shell concurrently with its cleanup.

Inspect `status.json`, `memory.jsonl` and the ten-minute `interim-report.md` with
bounded guest checks, normally every ten minutes. The interim and final JSON/Markdown
reports contain idle duration/count, Pss_Anon/SwapPss ranges and idle slopes, analysis
cost, completed cycles and all-phase memory deltas. Samples include record and
operation counts. `result.json` must report all assertions and cleanup green;
unit liveness alone is not success. Preserve raw evidence with verified checksums.

The historical +/-20 MiB comparison is distinct from the measured trend: a positive
slope within that envelope is not proof of flat memory. Report it as observed,
including an inconclusive trend when appropriate. This one-hour supported-library
whole-shell observation proves neither 24-hour stability nor NM-only attribution,
physical-radio behavior, a remote tunnel handshake or an older-library comparison.
