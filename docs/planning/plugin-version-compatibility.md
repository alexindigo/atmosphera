# Plugin Version Compatibility Model

**Date:** 2026-08-16
**Status:** Model sound; enforcement incomplete until the `plugin-compat-gate-fix`
plan ran (see below).

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

**What was initially reported:** `installPlugin` compared
`minNoctaliaVersion` against `UpdateService.baseVersion` ("0.1.0", the
*display fallback* for version detection), rejecting every registry plugin as
"incompatible."

**What the compatibility-gate investigation actually found:**

1. **The stated mechanism cannot have occurred against the default source.**
   `installPlugin` gates on the **registry index entry**, not the downloaded
   `manifest.json` — and the index at `alexindigo/atmosphera-plugins` carried
   `minNoctaliaVersion` on **0 of 158 entries** (the manifests carried it on
   156). `if (pluginMetadata.minNoctaliaVersion)` was always falsy, so the
   gate **never executed**. The comparison that was blamed for blocking
   installs never ran.

2. **The rejection would have printed.** `Logger.w` is ungated
   (`Commons/Logger.qml:43` — visible without debug mode), and the pre-fix
   code called it on rejection. The absence of any "incompatible" warning in
   the journal is further evidence the gate was not the cause of the observed
   failure.

3. **The observed GUI install failure therefore remains unexplained** — it
   reproduced the symptom ("button fired, nothing installed") but the gate was
   not the mechanism. It is investigated in the gate-fix plan's phase 4b and
   closed on the strength of phase 5's installs, not of the gate fix.

(The `baseVersion` misuse was still a real latent defect — it would fire the
moment any manifest version reached the gate — but it is not the cause of the
observed failure. Fixing it without claiming it caused the failure is what
makes phase 1 of the gate-fix plan shippable-but-invisible.)

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
  converted mirror). **Correction to an earlier claim:** the gate-fix
  investigation established that on the default source the gate had never
  executed — the known gaps below are what the missing `min*` check would have
  hit, closed by phase 3.
- `minAtmospheraVersion` becomes the contract for Atmosphera-native plugins.
- The version-detection display fallback (`baseVersion: "0.1.0"`) remains for
  source builds — but **it is still consulted**: `currentVersion` initialises
  to `fallbackVersion` built from `baseVersion`, and the native gate compares
  against `currentVersion`. Phase 3 of the gate-fix plan added a
  `versionKnown` property so the native gate is skipped (with a log) when the
  real version is undetectable — instead of comparing against the invented
  `0.1.0`, which is exactly the original bug returning through the new field.
- The lesson that produced this doc: the bug shipped in v0.5.1 because the GUI
  install path was never exercised pre-release. The AUR E2E rule now requires
  a full user-path install test after every `-git` change and every versioned
  release.

## Known gaps (closed by the gate-fix plan's phase 3)

All four defects would have woken at the same moment — the first plugin
declaring `minAtmospheraVersion` or a major ≥ 5:

| # | Defect | Closed by |
|---|---|---|
| 1 | Update path lost its early exit, so an incompatible plugin was filed in both *pending* and *available* sets | phase 1 (`continue` restored) |
| 2 | The native check used the naive comparator on `currentVersion`, mishandling `v`-prefixed / git-style versions | phase 1 (version-aware helpers) |
| 3 | The banner check failed open on `v`-prefixed values (`parseInt("v5") \|\| 0 → 0`) | phase 1 (version-aware helpers) |
| 4 | Native gate compared against the fallback `0.1.0` when the shell version is undetectable — the original bug returning | phase 3 (`versionKnown` guard) |
| 5 | The rejection message said "requires **Atmosphera**" for Noctalia plugins (misbranded for v5) | phase 3 (two-track messaging) |
| 6 | The gate was written twice (install + update paths), so `a81823058` fixed one copy and broke the other | phase 3 (single `checkPluginCompatibility`) |
| 7 | Two comparators with an unstated domain split | phase 3 (documented comparator domain) |
