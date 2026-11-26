ARG BASE_IMAGE=localhost/atmosphera-image-decoding-dev:present
FROM ${BASE_IMAGE}
USER root
# Sway supplies wlroots layer-shell as well as a true headless backend.
# Use the package databases inherited from the upgraded dev image.
RUN pacman -S --noconfirm --needed sway
# The package's scheduling capability cannot be acquired in a rootless
# container. Headless pixman needs no privileged scheduling or device access.
RUN getcap /usr/bin/sway && setcap -r /usr/bin/sway
ARG QT_WEBP=present
RUN case "$QT_WEBP" in \
      present) pacman -Q qt6-imageformats ;; \
      absent) pacman -R --noconfirm qt6-imageformats && ! pacman -Q qt6-imageformats ;; \
      *) echo 'QT_WEBP must be present or absent' >&2; exit 1 ;; \
    esac
USER dev
