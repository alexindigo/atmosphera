#!/usr/bin/env bash
set -euo pipefail

install -m 644 "$(dirname "$0")/arch-snapshot.mirrorlist" /etc/pacman.d/mirrorlist

# The Archive can stall longer than pacman's 10-second low-speed limit.
# Give each transfer more time, with bounded retries for network errors.
# Pacman still owns package selection and signature verification.
sed -i '0,/^\[options\]$/s|^\[options\]$|&\nXferCommand = /usr/bin/curl --disable --fail --location --proto =https --proto-redir =https --connect-timeout 20 --speed-limit 1 --speed-time 40 --max-time 90 --retry 2 --retry-connrefused --retry-max-time 120 --output %o %u|' /etc/pacman.conf

# Bootstrap trust from the digest-pinned Arch image, then update the keyring
# from the same archive as the rest of the system. Keep signature checks on.
pacman-key --init
pacman-key --populate archlinux
pacman -Syy --noconfirm --needed archlinux-keyring
pacman -Suu --noconfirm --needed "$@"
