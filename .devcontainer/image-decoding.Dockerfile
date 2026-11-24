ARG BASE_IMAGE=localhost/atmosphera-image-decoding-dev:present
FROM ${BASE_IMAGE}
USER root
# Sway supplies wlroots layer-shell as well as a true headless backend.
# Use the signed, versioned archive rather than following the mirror's latest.
ARG SWAY_ARCHIVE=sway-1:1.12-4-x86_64.pkg.tar.zst
RUN curl --fail --location --retry 3 --max-time 120 \
      "https://archive.archlinux.org/packages/s/sway/${SWAY_ARCHIVE}" -o "/var/cache/${SWAY_ARCHIVE}" \
    && curl --fail --location --retry 3 --max-time 120 \
      "https://archive.archlinux.org/packages/s/sway/${SWAY_ARCHIVE}.sig" -o "/var/cache/${SWAY_ARCHIVE}.sig" \
    && pacman-key --verify "/var/cache/${SWAY_ARCHIVE}.sig" "/var/cache/${SWAY_ARCHIVE}" \
    && pacman -U --noconfirm "/var/cache/${SWAY_ARCHIVE}" \
    && test "$(pacman -Q sway)" = 'sway 1:1.12-4' \
    && rm "/var/cache/${SWAY_ARCHIVE}" "/var/cache/${SWAY_ARCHIVE}.sig"
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
