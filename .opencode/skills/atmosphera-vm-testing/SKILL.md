---
name: atmosphera-vm-testing
description: Orchestrate Atmosphera testing on the arch-niri and arch-hypr libvirt VMs. Two modes: AUR (test what users get) and dev (local iteration via bind mount + local PKGBUILD). Delegates VM lifecycle to arch-niri-vm / libvirt-vm-snapshot, dev loop to arch-niri-vm-dev, and system ops to talk-to-domovoy.
license: GPL-3.0-or-later
compatibility: opencode
metadata:
  family: infrastructure
  topic: atmosphera-testing
  related: [arch-niri-vm, arch-niri-vm-dev, arch-hypr-vm, talk-to-domovoy, libvirt-vm-snapshot]
attribution: user#arch
---
# atmosphera-vm-testing

Master skill for Atmosphera testing on libvirt VMs. Covers both the AUR
test cycle and the local dev loop.

## Delegation map

```
atmosphera-vm-testing              ← YOU ARE HERE
  ├── arch-niri-vm                 VM lifecycle (rollback, boot, SSH)
  ├── arch-niri-vm-dev             dev loop (bind mount, build, install, iterate)
  ├── arch-hypr-vm                 Hyprland variant (future)
  ├── talk-to-domovoy              sudo operations (bind mount, package installs)
  └── libvirt-vm-snapshot          snapshot management
```

## VM topology

```
arch-base (clean Arch + dev-agent tools)
  ├── baseline
  │
  ├── virt-clone → arch-niri (niri 26.04)
  │     └── niri-base
  │
  └── virt-clone → arch-hypr (hyprland)
        └── hypr-base
```

All VMs have prebaked: `tester` user (passwordless sudo), dev-agent SSH key
(`~/.ssh/id_vm-agent`), `base-devel` + `git`, `virtiofs` module autoload,
`fcitx5` + `fcitx5-mozc` IME stack, `noto-fonts` + `noto-fonts-cjk`,
`/etc/vm-share` virtiofs device (tag `hostshare`).

## Connectors

```
virsh -c qemu:///system ...     # polkit, no sudo needed on this host
ssh -i ~/.ssh/id_vm-agent \
  -o IdentitiesOnly=yes \
  -o IdentityAgent=none \
  tester@<ip> ...
```

## Host prerequisites (one-time)

### 1. vm-share directory

```bash
sudo mkdir -p /home/user/vm-share
```

Must always exist on the host (domain source dir validation). Created by
Domovoy during VM provisioning; validate with `ls -d ~/vm-share`.

### 2. virtiofsd

```bash
pacman -Q virtiofsd
# binary at /usr/lib/virtiofsd — baked into domain XML via <binary path>
```

### 3. Networking

libvirt's nftables rules exist but Docker sets `iptables FORWARD` policy
to DROP. Domovoy has a systemd unit (`libvirt-network-fix.service`) that
persists the forwarding fix across host reboots.

```bash
systemctl status libvirt-network-fix 2>&1
```

## Test modes

### Mode A: AUR (test what users get)

Use `arch-niri-vm` skill directly. Reverts to `niri-base`, installs
`atmosphera-git` from the published PKGBUILD on GitHub. Full user-path
verification.

```bash
# See arch-niri-vm/SKILL.md for the full test flow
```

### Mode B: Dev (local iteration)

Use `arch-niri-vm-dev` skill. Host bind-mounts `~/Projects/atmosphera`
into `~/vm-share`. VM mounts tag `hostshare` at `/mnt/hostshare`.
Builds with `dev/vm/aur/PKGBUILD` — unpushed local commits included,
no push-to-GitHub round-trip.

**Per-cycle host step** (delegate to `talk-to-domovoy` or run manually):

```bash
sudo mount --bind ~/Projects/atmosphera ~/vm-share
```

Then follow `arch-niri-vm-dev` for the full or quick-iterate cycle.

## Verification checklist

After any install cycle, verify (run from host):

```bash
# SSH reachable and key works (no injection needed):
ssh -i ~/.ssh/id_vm-agent -o IdentitiesOnly=yes -o IdentityAgent=none \
  tester@<ip> 'whoami'

# niri installed and version:
ssh tester@<ip> 'niri --version'

# Internet works:
ssh tester@<ip> 'ping -c 1 1.1.1.1'

# virtiofs mount works (dev mode only):
ssh tester@<ip> 'sudo mount -t virtiofs hostshare /mnt/hostshare && ls /mnt/hostshare'
```

## Shell smoke test (headless)

The shell needs a running Wayland compositor (PanelWindow backend). On the
VM, use cage with the wlroots headless backend — no display needed:

```bash
# In-VM:
sudo pacman -S --needed --noconfirm cage
rm -rf ~/.config/atmosphera   # only for fresh-bootstrap testing
WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 \
  timeout 40 cage -- qs -c atmosphera > /tmp/qs-run.log 2>&1
# exit 124 (timeout kill) = shell stayed alive. exit 255/134 = load failure.

# Then inspect:
cat ~/.config/atmosphera/plugins.json          # seeded states/sources
grep -iE "bootstrap|Registered icon set" /tmp/qs-run.log
```

Expected on fresh install: Built-in source + 4 bundled plugin states
`enabled:true`, and log lines `Registered icon set: <hash>:atmosphera-icons`
and `<hash>:noctalia-icons-legacy`.

## Input-device / keybind testing (keyd, xremap)

**Inject keys at the emulated-hardware level with QEMU `send-key`** — this
flows through the guest's evdev → keyd/xremap → virtual keyboard →
compositor, the REAL chain:

```bash
# From host, press+release a key (hold-time ms):
virsh -c qemu:///system qemu-monitor-command arch-niri \
  '{"execute":"send-key","arguments":{"keys":[{"type":"qcode","data":"alt"}],"hold-time":150}}'

# Chord (Alt held + F1):
virsh -c qemu:///system qemu-monitor-command arch-niri \
  '{"execute":"send-key","arguments":{"keys":[{"type":"qcode","data":"alt"},{"type":"qcode","data":"f1"}],"hold-time":200}}'
```

Valid qcodes: `alt`, `ctrl`, `meta_l`/`meta_r` (NOT bare `meta`), `f1`…
Full list: QEMU `QKeyCode` enum.

**Gotcha — injection target moves with hotplug:** `send-key` goes to the
MOST RECENTLY ADDED input device. Hotplugging a `usb-kbd` for scoping tests
(`device_add driver=usb-kbd id=…`) silently reroutes injection from PS/2 to
USB. `device_del id=…` after the scoping check, or your key tests hit the
wrong device.

**Observe results in-guest** on the keyd/xremap virtual keyboard:

```bash
# find it: sudo evtest   (look for "keyd virtual keyboard" / "xremap")
sudo timeout 10 evtest /dev/input/eventN > /tmp/ev.log &
# then inject from host; expect remapped KEY_* in the log:
grep "Event: time" /tmp/ev.log
```

keyd notes (learned the hard way):

- keyd reads ALL files in `/etc/keyd/`, not just `*.conf` — an
  extensionless `atmosphera` include target IS parsed.
- keyd 2.5+ deprecates direct modifier assignment (`leftalt = leftmeta`);
  use `layer()` form (`leftalt = layer(meta)`). Side effect: a bare
  modifier tap emits NOTHING (correct) — verify remaps with chords, not
  taps.
- `[ids]` scoping only works when the including config doesn't wildcard:
  a generated `[ids] *` upstream of an `include` defeats the included
  file's own scoping.

`wtype` (virtual-keyboard protocol) does NOT reach keyd/xremap (it injects
at the compositor, after evdev) and is unreliable in cage→nested-niri
topologies. Use QEMU `send-key` for anything that must pass through
evdev remappers.

More input-testing lessons learned the hard way:

- **User services die with the SSH session.** `systemd --user` exits when
  the last session closes unless lingering is on: `loginctl enable-linger
  tester`. Without it, user units (xremap) stop mid-test with a
  mysterious "Exit the Session" journal block.
- **evtest on a grabbed device shows nothing.** keyd/xremap grab their
  input exclusively — capture the FINAL output device in the chain
  (xremap's device after keyd's), not the grabbed intermediate.
- **New group membership needs a fresh session.** After `usermod -aG
  input tester`, `sudo loginctl terminate-user tester` then reconnect.

## Custom (non-repo) dependencies

Three deps are not in official repos; pre-install on the VM before
`makepkg -s`, else dependency resolution fails:

| Package | Built from |
|---|---|
| `noctalia-qs` | PKGBUILD at `/home/domovoy/aur/noctalia-qs/` |
| `qt6-dbusqml` | `~/Projects/qt6-dbusqml/` |
| `qt6-xdgiconqml-git` | `~/Projects/qt6-xdgiconqml-git/` (AUR-published) |

```bash
scp *.pkg.tar.zst tester@<ip>:/tmp/
ssh tester@<ip> 'sudo pacman -Udd --noconfirm /tmp/*.pkg.tar.zst'
# NOTE: -Udd skips dep resolution — install noctalia-qs's deps separately:
ssh tester@<ip> 'sudo pacman -S --needed --noconfirm jemalloc qt6-base \
  qt6-declarative qt6-svg qt6-wayland libpipewire polkit'
```

Missing `libjemalloc.so.2` at `qs` launch = forgot the second step.

## Drift guard (dev mode)

Ensure `dev/vm/aur/PKGBUILD` hasn't drifted from the AUR PKGBUILD:

```bash
diff \
  <(grep -v '^source=\|^sha256sums=\|^_ref=' ~/Projects/atmosphera/dev/vm/aur/PKGBUILD) \
  <(grep -v '^source=\|^sha256sums=' ~/Projects/aur-atmosphera-git/PKGBUILD)
# Must produce no output.
```

## Companion docs

- `dev/vm/aur/PKGBUILD` — local-source build recipe (in atmosphera repo)
- `dev/vm/README.md` — dev loop quick reference
- `setup/arch/vms/arch-vm-branching.md` — VM build blueprint (Domovoy's docs)
- `~/Documents/Atmosphera/plans/vm-local-dev/plan.md` — original plan doc
