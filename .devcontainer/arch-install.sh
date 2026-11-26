#!/usr/bin/env bash
set -euo pipefail

# Bootstrap trust from the digest-pinned Arch image, then update the keyring
# and fully upgrade against the image's normal Arch mirrors. Keep signature
# checks on. Pass requested packages here so each install layer refreshes
# its own databases instead of relying on a cached parent layer.
pacman-key --init
pacman-key --populate archlinux
pacman -Sy --noconfirm --needed archlinux-keyring
pacman -Su --noconfirm --needed "$@"
