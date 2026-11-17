# app.atmosphera.Locker1 contract

Atmosphera's lock owner can hand a lock request to a persistent screen locker
that runs as its own session service ("class-3" locker). This page is the
public contract for such lockers. Version 2 adds a request ID and correlated
signals, so the owner can tell when the locker's own session lock is secure
and when the user has unlocked it. Version 1 lockers keep working unchanged.

## Bus identity

| # | Item | Value |
|---|---|---|
| 1 | Bus | Session bus |
| 2 | Well-known name | `app.atmosphera.Locker` |
| 3 | Object path | `/app/atmosphera/Locker` |
| 4 | Interface | `app.atmosphera.Locker1` |

## Interface

```xml
<interface name="app.atmosphera.Locker1">
  <!-- Version 1 -->
  <method name="Lock"/>
  <!-- Version 2 -->
  <property name="Version" type="i" access="read"/>
  <method name="LockRequest">
    <arg name="request_id" type="s" direction="in"/>
  </method>
  <method name="RequestState">
    <arg name="request_id" type="s" direction="in"/>
    <arg name="state" type="s" direction="out"/>
  </method>
  <signal name="Secured">
    <arg name="request_id" type="s"/>
  </signal>
  <signal name="Unlocked">
    <arg name="request_id" type="s"/>
  </signal>
</interface>
```

A service without a readable `Version` property, or with `Version` below 2, is
a version 1 service and receives only `Lock()`.

## Semantics

| # | Member | Meaning |
|---|---|---|
| 1 | `Lock()` | Start a lock, or join the lock already in progress. Return an error if no lock can be started. |
| 2 | `Version` | `2` for this revision. The owner reads it before each request. |
| 3 | `LockRequest(id)` | Same as `Lock()`, and remember `id` for the lock that serves it. Calling it again with a known `id` must not start a second lock. |
| 4 | `Secured(id)` | Emit only after the service's own ext-session-lock object received the compositor's `locked` event, for the lock serving `id`. If that lock is already secure, emit it after replying to `LockRequest`. |
| 5 | `Unlocked(id)` | Emit only after the user authenticated in this service and the service sent its own protocol unlock (`unlock_and_destroy`) for that lock. Always after `Secured(id)`. |
| 6 | `RequestState(id)` | Read-only state of one request: `pending`, `secure`, `unlocked`, `failed` or `unknown`. |

`failed` means the service no longer holds a lock for that request and did not
authenticate the user (for example, the compositor refused or finished it).
`unknown` means the service has never seen the ID or no longer remembers it.

Request IDs are 1 to 128 characters from `[A-Za-z0-9._:-]`. Reject anything
else with the error `app.atmosphera.Locker1.Error.InvalidRequest`. A service
that is ending its lock and cannot take a new request replies with
`app.atmosphera.Locker1.Error.Ended`.

The contract is observational. There is no unlock method, and no message on
this interface may ask a locker to release its lock. A service must not emit
`Secured` because of readiness, a running process, name ownership or the
logind `LockedHint`; only its own protocol `locked` event counts.

## What the owner does

| # | Situation | Owner behavior |
|---|---|---|
| 1 | Version 2, `Secured(id)` from the owner that accepted the request | Lock confirmed secure; no emergency lock is needed |
| 2 | Version 2, `Unlocked(id)` after `Secured(id)` | Lock operation ends; no relock, no second password |
| 3 | Signal with another ID, or from a different bus owner | Ignored as evidence; a changed owner counts as a failed request |
| 4 | Service name disappears or changes owner during the lock | Confirmation is withdrawn; the owner probes with its emergency lock, which can only add a lock |
| 5 | Main shell restarts during the lock | The new owner asks `RequestState(id)` of the same bus owner before trusting any state |
| 6 | Version 1 service | `Lock()` only. Secure state is never confirmed. On niri the compositor's logind `LockedHint` reports the unlock; on Hyprland the owner cannot observe it (see below) |

The owner subscribes to `Secured` and `Unlocked` before it calls
`LockRequest`. It never stops, restarts or kills an independent locker service.

### Version 1 on Hyprland

Hyprland reports session-lock state through its own `hyprland-lock-notify-v1`
protocol, not through logind `LockedHint`. Quickshell has no client for that
protocol, so the owner cannot see when a version 1 service unlocks there. The
owner keeps such a lock as unconfirmed and never kills the service. Lockers that
want correct behavior on Hyprland should implement version 2.

## Atmosphera's own lockers

The bundled lock screen (`qs -c atmosphera-lockscreen`) and the emergency lock
(`qs -c atmosphera-emergency-lock`) serve version 2 when they are started on
their own, outside the owner, and the name is free. They claim the name
without queueing and without allowing or requesting replacement, so they never
take it from an independent service. Lockers started by the owner never claim
the name; the owner observes them through private per-launch reports instead.

## Existing standards checked

| # | Interface | Why it is not enough |
|---|---|---|
| 1 | `org.freedesktop.ScreenSaver`: `Lock()`, `GetActive()`, `ActiveChanged(b)` | A global active flag with no request identity; it cannot say which lock request is secure, or that a particular locker's own lock is secure rather than requested |
| 2 | `org.freedesktop.login1.Session`: `Lock`/`Unlock` signals, `LockedHint` | Session-wide requests and a hint any process may set; no correlation with a specific locker or request. Hyprland does not update `LockedHint` |
| 3 | Wayland `ext-session-lock-v1` | Tells a lock client its own state, but nothing to a third party such as the shell |

`Lock()` keeps the shape of the ScreenSaver method so version 1 lockers stay
simple. Version 2 adds the request ID and correlated signals only.
