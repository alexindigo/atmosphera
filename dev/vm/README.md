# Dev VM loop

## Setup (one-time)

Requires `arch-niri-vm-dev` skill loaded. The VM must be patched for
virtio-fs once (see skill). SSH key `~/.ssh/id_vm-agent` must be deployed.

## Full cycle

From host:

```bash
# Revert, boot, wait-ssh
virsh -c qemu:///system snapshot-revert arch-niri --snapshotname niri-base
virsh -c qemu:///system start arch-niri
# ... wait for SSH ...

# In-VM: mount, build, install
ssh tester@$IP '
  sudo pacman -Syu --noconfirm
  sudo modprobe virtiofs
  sudo mkdir -p /mnt/hostshare
  sudo mount -t virtiofs hostshare /mnt/hostshare
  mkdir -p ~/build
'
scp dev/vm/aur/PKGBUILD tester@$IP:~/build/PKGBUILD
ssh tester@$IP '
  cd ~/build
  makepkg -s --noconfirm
  sudo pacman -U --noconfirm atmosphera-git-*.pkg.tar.zst
'
```

## Quick iterate (no revert)

Skip snapshot revert. Remount if needed. Rebuild, reinstall:

```bash
ssh tester@$IP 'cd ~/build && makepkg -f --noconfirm && sudo pacman -U --noconfirm atmosphera-git-*.pkg.tar.zst'
```

## Drift guard

```bash
diff \
  <(grep -v '^source=\|^sha256sums=\|^_ref=' dev/vm/aur/PKGBUILD) \
  <(grep -v '^source=\|^sha256sums=' ~/Projects/aur-atmosphera-git/PKGBUILD)
# Must produce no output.
```

## Teardown

```bash
virsh -c qemu:///system destroy arch-niri
```
