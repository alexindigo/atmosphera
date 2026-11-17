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

Per-field versions protect newer payloads from late reads. Membership events
and tombstones protect in-flight inventories, then are retired; they are not an
unbounded event log. Profile settings reads use revision/dirty-again guards.
Record notifications queue publication, avoiding reentrant creation and input
binding loops. Public snapshots do not expose proxies, replies or mutable
registry objects. Native boxed object paths are normalized at the boundary.

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
The same selftest exercises full-scale synthetic smaps analysis, including a known
growing series; synthetic data never substitutes for an actual memory soak.
