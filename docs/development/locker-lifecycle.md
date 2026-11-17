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

There are no periodic emergency retries. A probe already acquiring when external
authentication finishes must be resolved: if it becomes secure, it stays locked
and requires its own PAM authentication. The owner logs that fail-closed race.

The Locker1 D-Bus contract is unchanged. `acceptContractAck()` is an internal
plug-in point for a future correlated acknowledgement, not a public IPC method
or permission to treat an unconfirmed lock as secure.

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

`locker-lifecycle-regression.py` currently provides `fast`, `slow`, `external`,
`contract`, `restart` and `orphan-acceptance`. Each case requires its own new `--work` directory.
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

The broader boundary/resource/ingress/suspend/load/packaging matrix and
the separate Hyprland restore-option proofs are not implied by these entry
points. Keep their acceptance status in the task's outside-repository execution
note until those proofs are implemented and run.
