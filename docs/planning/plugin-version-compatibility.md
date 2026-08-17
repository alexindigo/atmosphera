# Plugin Version Compatibility Model

**Date:** 2026-08-16
**Status:** Implemented (landed in `a81823058`)

---

## Context

Atmosphera is a fork of Noctalia. Its plugin system consumes two kinds of
plugins:

1. **Noctalia/upstream plugins** — the ecosystem from
   `noctalia-dev/legacy-v4-plugins` (and our converted mirror at
   `alexindigo/atmosphera-plugins`). Their manifests declare
   `minNoctaliaVersion` in **Noctalia's own versioning** (3.6.0, 4.1.2,
   4.5.0, 4.6.6, …).
2. **Atmosphera-native plugins** — plugins authored for this fork.

The fork has **two version identities** that must not be conflated:

| Identity | What it is | Who uses it |
|---|---|---|
| Product version | Atmosphera 0.5.x | About panel, releases, update checks |
| Noctalia API base | what `minNoctaliaVersion` refers to | plugin compatibility checks |

Upstream Noctalia never needs (2) as a separate value — its product version
*is* the compatibility level. The fork's version divergence created the gap.

---

## The bug

`PluginService.installPlugin()` (and the update check) compared
`minNoctaliaVersion` against `UpdateService.baseVersion`, which is **"0.1.0"**
— the *display fallback* for version detection on source builds, not a
compatibility level.

Every registry plugin declares `minNoctaliaVersion ≥ 3.6.0`, and
`compareVersions("3.6.0", "0.1.0") > 0`, so **every plugin install through the
GUI was rejected as "incompatible"** — silently for the user (a toast that
expires) and without any log line on the default path.

This was found by the GUI install-click test on the VM: the Available tab
rendered the registry, the install button fired, and nothing installed.

Note the trap: the check is inside `installPlugin`, which is only reachable
from the GUI. Installs done file-side (directory copy + `plugins.json` edit)
bypass it entirely — which is why the full plugin sweep loaded 162 plugins
fine while no GUI install could ever succeed.

---

## Goal

A compatibility model that:

1. Lets **all Noctalia v4 plugins** install, regardless of minor/patch version.
2. Introduces **no version constant that can go stale** (no "bump me on every
   upstream release" maintenance tax).
3. Gives **Atmosphera-native plugins a proper native version gate** against
   the fork's real version.
4. Treats old (3.x) plugins as **assumed working**; actual breakage is cleaned
   up case-by-case in the registry, not by the gate.

---

## Design

### Two tracks

| Track | Gate |
|---|---|
| Noctalia/upstream plugins | `major(minNoctaliaVersion) ≤ noctaliaCompatMajor` |
| Atmosphera-native plugins | `minAtmospheraVersion` vs `UpdateService.currentVersion` (proper semver compare) |

### The v4 banner

`UpdateService.noctaliaCompatMajor: 4` — a **major-version ceiling**, not a
version number. Any plugin whose declared `minNoctaliaVersion` has major ≤ 4
is compatible: the whole Noctalia v4 line **and older**, any minor/patch.

Why this is the right shape:

- The Noctalia v4 line is **closed** (upstream moved to v5). "≤ 4" is a fixed
  historical fact, not a moving target — it never needs bumping.
- It matches the user's intent: the fork *carries the v4 banner* for the
  legacy-v4 plugin ecosystem.
- It incidentally keeps the registry's 3.x plugins (e.g. catwalk @ 3.6.0)
  working, since 3 ≤ 4.
- v5 plugins are correctly excluded — the fork is a v4 shell.

### The native track

New manifest field `minAtmospheraVersion`, compared against the fork's real
detected version (`UpdateService.currentVersion`). This is the contract for
plugins authored for Atmosphera itself — e.g. a plugin requiring 0.5.1-era
features declares `minAtmospheraVersion: "0.5.1"`.

Checked **before** the Noctalia gate in both the install and update paths.

### Old plugins policy

3.x plugins pass under the banner by default. If one actually breaks in
practice (uses a removed/changed API), it gets fixed or dropped from the
registry individually — the gate does not try to predict API drift.

---

## Alternatives considered

| Option | Why rejected |
|---|---|
| `noctaliaCompatVersion: "5.0.0"` (first patch) | Another hand-maintained magic constant that goes stale on the next upstream sync — same bug class as the `0.1.0` it replaced |
| `noctaliaCompatVersion: "4.7.7"` (last v4 tag) | A max-version gate: any plugin declaring 4.8.0 would fail despite being a v4 plugin. Violates "any v4, regardless of minor/patch" |
| Build-time derivation from upstream tags (`git describe --match "v4*"`) | Elegant but unnecessary machinery — the v4 line is closed, so a rule (major ≤ 4) already says everything a derived value would |
| Capability-based compat (check which APIs a plugin uses vs. what the shell provides) | The honest long-term model, but a real redesign: manifests don't declare API usage, and it can't capture the NIcon→AtmoIcon rename gap mechanically. Deferred |

---

## Consequences

- GUI plugin installs work for the entire legacy-v4 registry (and our
  converted mirror).
- `minAtmospheraVersion` becomes the contract for Atmosphera-native plugins.
- The version-detection display fallback (`baseVersion: "0.1.0"`) is left
  untouched — it was never meant to be a compatibility level, and nothing else
  uses it as one anymore.
- The lesson that produced this doc: the bug shipped in v0.5.1 because the GUI
  install path was never exercised pre-release. The AUR E2E rule now requires
  a full user-path install test after every `-git` change and every versioned
  release.
