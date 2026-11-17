# Locker lifecycle

## Ownership and authentication

`LockOwnerService` owns one lock generation for the graphical session. Existing
lock IPC, compositor/session actions, idle and logind requests feed that owner.
It snapshots adapter and hook selection, coalesces requests and retains exact
systemd invocation/cgroup identities. `LockerService` observes the independent
Locker1 service and compositor-originated session state; it does not spawn a
second locker. The in-shell lock screen is a presentation-only preview.

Only successful PAM in the actual holder may request protocol unlock. Cancelling
a candidate, retiring an emergency holder for takeover, losing a protocol request
or restarting the main shell must not send `unlock_and_destroy`. No password or
authentication permit is transferred between processes.

| # | Time / event | Behavior |
|---|---|---|
| 1 | Initial bundled request | Prepare settings, auth and UI; report generation-ready; wait for the owner's acquisition grant |
| 2 | Native `locked()` | Report secure, separately from preparation or a requested lock |
| 3 | Original request + 3 seconds | Start the independently authenticating emergency config if the real client is not confirmed secure |
| 4 | Emergency secure, bundled candidate ready | On a compositor with proven dead-holder takeover, retire emergency without protocol unlock, await its exact cgroup exit, then grant the candidate |
| 5 | Original request + 30 seconds | Revoke and stop an unready bundled candidate; retain the secure emergency client |
| 6 | Successful PAM | Fence candidate authority before the holder unlocks; settle only after exact owned cgroups finish |
| 7 | Main-shell restart | Reconcile and adopt the same generation/invocations; retain original deadlines and secure holder |

Neither engaged client has a runtime expiry. The original startup deadline must
not become a timer that kills a legitimate overnight lock.

## Opaque commands and Locker1

External shell syntax and selection precedence are preserved. Per-lock external
commands run in the owned real unit, including pipelines and daemonized children.
The availability checker only inspects command availability; it never runs the
command. A persistent `app.atmosphera.Locker1` service is independently managed:
the owner may call `Lock()` but must not terminate that service.

Neither a running unit, a D-Bus name nor LockedHint identifies a secure candidate.
At the deadline, the emergency connection provides its own protocol outcome:

| # | Emergency outcome | Owner behavior |
|---|---|---|
| 1 | Secure | Retain emergency; stop an owned opaque candidate, but not an independent Locker1 service |
| 2 | Refused before secure | Protect the possibly acquiring external holder; expose `engaged-unconfirmed(external)`, not secure |
| 3 | External candidate crashes while unconfirmed | Probe immediately, using the new probe's actual outcome |
| 4 | Pending suspend while unconfirmed | Probe once at the start of that logind delay window |
| 5 | Legitimate external unlock | Settle without launching a probe or requiring a second password |

Row 3 applies where the compositor allows dead-client takeover (niri), and
there a legitimate unlock arrives first as LockedHint=false. Without takeover
(Hyprland, restore disabled) the compositor keeps a dead holder's lock and
would refuse a probe, so a probe could only relock after the user's own
unlock. There the refused opaque unit's exit is the unlock observation and the
generation settles without a probe or a second password.

There are no periodic emergency retries. A probe already acquiring when external
authentication finishes must be resolved: if it becomes secure, it stays locked
and requires its own PAM authentication. The owner logs that fail-closed race.

The public Locker1 contract, including version 2, is in
[`docs/locker1-contract.md`](../locker1-contract.md). The owner obtains a fresh
per-generation request ID from `locker-unit.py`, reads `Version`, calls
`LockRequest(id)` (or `Lock()` for version 1) and records the accepting unique
bus owner. `LockerService` stamps `Secured`/`Unlocked` with the current owner;
the adapter's `contract-observe` operation persists them only for the matching
request ID and owner. A persisted `Secured` confirms engagement until the
service's name is lost or changes owner. `Unlocked` is the same unlock
observation as LockedHint=false on niri, so no probe or second password follows.
After a shell restart the owner queries `RequestState(id)` of the recorded owner.
Standalone shipped lockers serve version 2 through `LockClient`; managed clients
never claim the name.

## Settings and process lifetime

The main Settings owner publishes a private, generation-correlated effective
settings view. Managed lockers read it through native read-only ConfigQml routes;
standalone lockers also use native read-only sources. Lockers do not materialize
defaults, save settings or execute migration side effects. Live preference
updates remain observable. The generation input is removed at settlement.

`locker-unit.py` fences effects by session, generation, InvocationID and cgroup.
Its startup bound covers ungranted preparation while the main shell is absent;
it never infers successful unlock from process death. Client protocol refusal
or terminal settlement stops local auth/resource work and exits the client.

## Diagnostics

Read the actual main shell's status without granting unlock authority:

```sh
qs ipc -c atmosphera call lockOwner status
```

The status includes generation, original deadlines, role/unit identities and
requested/secure/terminal client state. Keep LockedHint as separate corroboration.
Use the recorded InvocationID and ControlGroup to inspect that invocation, not a
command-substring process search. Collection or a missing unit name alone is not
proof that its previously recorded descendants are gone.

Protocol tracing can contain keyboard events. Redact keyboard-event lines before
retaining or sharing logs, and never collect protected credential/hash files.
An absence-of-unlock claim requires a continuous native/compositor trace, not
only a sampled boolean or the owner's own log. Observe locked output through
the named VM framebuffer, not compositor screencopy that may return black.

## Guest verification entry points

Run workloads only in the authorized task guest. For the retained niri fork,
use `ark-user-vms` strict pinned tester SSH to `atmosphera-locker-orphan` on
`ark.home`, UUID `2ecc7f91-19d9-4588-bda1-6502a623f1ce`, source workspace
`/home/tester/Projects/locker/source`, with
`TMPDIR=/home/tester/Projects/locker/tmp`. Never run these on Ark itself.

`locker-lifecycle-units.py --work <new-artifact-directory>` runs policy, actual
unit/cgroup, managed-client/PAM and actual delay-inhibitor-fd proofs. The fd proof
is not a real suspend/resume proof.

`locker-lifecycle-regression.py` currently provides `fast`, `slow`, `boundary`,
`deadline-race`, `rejected`, `resources`, `external`, `contract`, `restart`, `ingress`, `preview`,
`suspend`, `load`, `packaging`, `cold-load` and `orphan-acceptance`.
Each case requires its own new `--work` directory.
The external suite includes the command variants, cooperative handover and
event-driven opaque probes. Preserve each subproof's result; do not infer a
passing full matrix from a subset. Framebuffer-dependent cases require the
exact fork's local VNC port forwarded to the guest and the matching VM name.

The contract case uses a separately supervised Locker1 service for normal,
method-error, no-engagement and disappearing-name outcomes. It preserves the
independent service after owner settlement and observes actual PAM/native unlock.

The restart case cold-starts the actual main shell again while engaged, starting,
in fallback and after committed emergency retirement. It checks original
deadlines, same locker invocation/cgroup/generation, continuous compositor/native
evidence, framebuffer sentinel absence during handover and authenticated cleanup.

The boundary case delays the actual prepared client's generation publication to
2.9, 3.0, 3.1, 29.9, 30.0 and 30.1 seconds from the original request. It leaves
the real adapter's parent-process identity fence and protocol outcomes intact,
checks late-ready authority revocation, and retains continuous traces plus
framebuffer sequences. It also exercises policy orderings and real emergency
authentication before delayed readiness. A naturally late preparation fails
the controlled barrier instead of silently moving its target.

The packaging and cold-load cases inspect a fresh assembled install and run
actual-main built-in/demo paths, an independently authenticating emergency
config and the read-only settings matrix. No source-only Portals link is added;
the emergency closure contains only its own entry points and shared auth/client
helpers. Startup is followed by real PAM, native teardown and cgroup cleanup.

AUR and Nix assembly both call `Scripts/bash/install-locker-configs`; neither
maintains a separate locker dependency list. Nix registers the main tree and
both named sibling configs under `$out/etc/xdg/quickshell`, adds that XDG search
directory to the wrapper environment and supplies child Quickshell plus the
Python D-Bus/GLib bindings regardless of optional calendar support.
`python3 -B Scripts/dev/locker-nix-assembly-proof.py --work <new-artifact-directory>`
uses the real Nix evaluator and actual package installPhase to inspect the
filtered assembly, manifest, closed emergency tree and native `qs -c` resolution.
Its dependency values are sentinels: this is an assembly check, not a full
Nixpkgs/Qt build, wrapped-runtime proof or NixOS/Home Manager boot. The normal
guest cold-load/PAM suite separately verifies the shared installed closure.

Startup outcomes use native protocol time, not owner receipt time. A real lock
before the original 3-second deadline must have no emergency attempt. If real
secures late but first, the refused emergency exits and the same real holder
stays. If emergency secures first, the ready real client takes over through the
fail-closed handover. Every outcome retains continuous no-unauthenticated-unlock
assertions. `deadline-race` deterministically exercises both late outcomes with
test-only response/exec barriers, actual protocol traffic and real PAM. A secure
holder is never terminated merely to manufacture a different test outcome.
Owner proofs record guest CPU steal and native startup timing. Their launcher
supplies `LOCKER_TEST_ARK_LOAD_FILE`, a disk-backed guest file receiving timestamped
Ark `uptime` observations throughout the run. Strict universal sub-3-second
latency is tracked separately for a quiet environment, not inferred under load.

The rejected case runs both unmodified installed configs against an independent
authenticating holder. Native refusal must make both losing clients self-exit,
without releasing that holder. The resources case adds a retained diagnostic:
the actual bundled LockSession receives a test adapter's delayed terminal reply,
so its normal exit waits while its resource cleanup can be observed. No
production self-exit is disabled. LED/spectrum registrations and event counters
must stay off, no compositor subscription may initialize, and the root must use
less than 0.1 core over at least 10 seconds. Native stacks and exact cgroup/PID
identities are retained. Releasing the reply must exit normally; real PAM unlock
is followed by at least 10 seconds of exact process/cgroup absence. The image
cache's independent 1x1 render traffic is not LED or spectrum activity.

The ingress case drives actual main/public IPC and CLI, native ext-idle,
a real compositor keybind, custom session action, exclusive and nonexclusive
hooks, listener hooks and legacy external selection. It also retains the scoped
overlapping-callback and coalesced-suspend-intent checks. The niri keybind fixture
waits for the shell's startup configuration handoff, validates a private config
copy, uses the exact VM console's emulated keyboard, then restores the session
config. It never edits the original compositor config. Passing subproofs retire
only their reconstructible staged installs, preserving logs/configuration and
results, to avoid exhausting guest inodes.

The preview case uses the actual CLI, observes the rendered guest framebuffer,
presses real Escape and checks the desktop returns. The descriptor is unchanged,
LockedHint stays false, and no protocol lock/unlock request is allowed. This is
presentation-only; normal inset desktop margins are not a secure-output defect.
Escape is scoped to each preview window's live content, not an off-window root.

`suspend --delays 0,5,40 --sleep-signals` exercises actual main lock-and-suspend
and externally initiated sleep through the real logind manager, signals and
delay-inhibitor fd. A guest-only runtime override substitutes a bounded service
barrier for systemd's kernel-sleep command. The proof observes the real inhibitor
held before the request, native secure before its actual release, service entry,
real PrepareForSleep(false), inhibitor reacquisition and the lock intact on the
guest framebuffer. The original service ExecStart is restored in finally.
No kernel sleep is invoked; the kernel journal must contain no suspend entry.
`--real-suspend` is rejected: real S3 is not testable in this VM and must be
checked on the user's machine. This proof is not hardware suspend/resume proof.

Passing subproofs retire only their reconstructible staged installs and icon
copies that match the authoritative source byte-for-byte. Per-file hashes and
exact paths are recorded; settings, caches, state, logs and captures remain.
This avoids inode exhaustion during sequential main-shell matrices.

`load --delay 5` keeps a supervised, RSS/CPU-bounded resident-memory worker
active through real-main slow handover/secure sleep-signal ordering and a
separate actual emergency-PAM-before-ready proof. It records requested and
resident bytes, guest meminfo/PSI, native startup time, Ark uptime and guest
CPU steal; it does not claim universal sub-3-second latency or hardware sleep.
The worker's exact invocation/PID identity is retired independently of locker
authentication, even if a subproof fails.

Separate Hyprland restore-option proofs are not implied by these entry points.

`locker-owner-proof.py --main-shell --case opaque-expiry --sleep-signals
--sleep-route prepare-for-sleep` records the unconfirmed opaque-output finding.
The native test client requests a session lock without surfaces, retains its
connection through the real inhibitor deadline, then maps input surfaces only
for actual PAM recovery. Guest grim capture must show the unlocked sentinel
before locking and after authentication; an uncalibrated black image is never
accepted. This records compositor-rendered output, not physical scanout or
hardware sleep, and never upgrades the owner's unconfirmed state to secure.

On Hyprland the continuous compositor observer builds a read-only native
hyprland-lock-notify-v1 subscriber and records its initial state and lock/unlock
timestamps. It never requests a session lock or substitutes notifications for
a client's generation-correlated secure acknowledgement. Logind hints remain
separate corroboration. The slow proof follows discovered takeover capability:
without it, the real candidate is cancelled and the independently authenticating
emergency stays alive; no dead-holder handover is attempted.

## Durable native client reports

LockClient writes its native outcome synchronously before returning from
secureStateChanged, before Quickshell tears down the lock surfaces. A private
0600 per-client runtime file is atomically committed by FileView with blocking
writes; the installed Qt uses fdatasync before the rename. The adapter validates
the session, generation, invocation, registered PID/start identity, token and
monotone sequence before retaining the report in the generation descriptor.
Late asynchronous status cannot erase the native result. These are operation
reports, not settings writes or an additional authentication path.

A matching finished report means refused, never secure. A matching locked report
followed by unauthenticated process death means a dead-client lock, not unlock.
No report means unknown; an unreported probe exit triggers a new fail-closed
probe rather than pretending the dead process secured the session. Only the
client's successful-PAM path and committed private fence may report authenticated
unlock. Standalone clients prepare the same private report before acquiring
and retire their own file, by exact process identity, when they exit; no owner
reads it. The emergency package includes only the narrow helper it needs.

Guest `locker-owner-proof.py --case report-refusal` reproduces native refusal
while an independently authenticating holder remains secure, verifies that the
owner reads finished after probe death, and traces the client's own successful
sync plus atomic commit before surface destruction. Hyprland's native error
must remain visible. The focused proof authenticates and retires its holder
explicitly; it is not class-3 contract acceptance. `--case report-unknown` kills
only a blocked, not-yet-executed probe, verifies unknown, then requires a fresh
emergency lock and actual PAM. `locker-report-validation.py` exercises stale
identity/sequence, mode, symlink and private-auth-fence rejection; those synthetic
validation inputs are not PAM evidence.
Keep their acceptance status in the task's
outside-repository execution note until those proofs are implemented and run.
