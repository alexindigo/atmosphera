ARG BASE_IMAGE=localhost/atmosphera-image-decoding-dev:latest
FROM ${BASE_IMAGE}
USER root
ARG QT_READERS=present
# The base image supplies Sway (built with INSTALL_IMAGE_TOOLS=1).
# The package's scheduling capability cannot be acquired in a rootless
# container. Headless pixman needs no privileged scheduling or device access.
RUN getcap /usr/bin/sway && setcap -r /usr/bin/sway
RUN bash -ec '\
    source /usr/local/share/atmosphera/imvqml-arch-runtime.sh; \
    pacman -Q python-dbus "${imvqml_core[@]}" "${imvqml_readers[@]}"; \
    case "$QT_READERS" in \
      present) ;; \
      absent) pacman -R --noconfirm "${imvqml_readers[@]}" ;; \
      *) echo "QT_READERS must be present or absent" >&2; exit 1 ;; \
    esac'
USER dev
