ARG BASE_IMAGE=localhost/atmosphera-image-decoding-dev:latest
FROM ${BASE_IMAGE}
USER root
# The base image supplies Sway (built with INSTALL_SWAY=1).
# The package's scheduling capability cannot be acquired in a rootless
# container. Headless pixman needs no privileged scheduling or device access.
RUN getcap /usr/bin/sway && setcap -r /usr/bin/sway
# Independent fixture encoders, not shell runtime dependencies.
RUN bash /usr/local/share/atmosphera/arch-install.sh imagemagick ffmpeg \
    && ! pacman -Q qt6-imageformats
USER dev
