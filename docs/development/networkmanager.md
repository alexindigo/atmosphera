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
