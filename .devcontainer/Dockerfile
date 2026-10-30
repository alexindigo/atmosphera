FROM docker.io/library/archlinux:base-devel

# Container identity for the dev account. The default matches the Podman
# keep-id target; the Docker tooling path passes the invoking user's IDs
# as build arguments so bind-mount writes stay host-user-owned.
ARG DEV_UID=1000
ARG DEV_GID=1000

RUN pacman -Sy --noconfirm --needed \
    quickshell qt6-declarative qt6-tools qt6-multimedia \
    cmake ninja pkgconf libpipewire \
    python python-pip \
    git shellcheck shfmt \
    tree-sitter \
    rustup \
    sudo

# Build the real QML plugins so their runtime modules and registrar-generated
# type descriptions agree. No hand-written lint substitutes.
COPY install-qml-deps.sh /usr/local/bin/install-qml-deps
RUN bash /usr/local/bin/install-qml-deps

# AST/provenance analysis tooling, not an application/runtime build. The grammar
# archive is pinned and verified; install once per resource-capped tooling image.
COPY settings-check-requirements.txt /opt/settings-check-requirements.txt
RUN pip install --break-system-packages -r /opt/settings-check-requirements.txt

RUN groupadd -g "$DEV_GID" dev \
  && useradd -m -u "$DEV_UID" -g "$DEV_GID" -G wheel -s /bin/bash dev \
  && echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/dev

COPY atmo-dev.sh /usr/local/bin/atmo-dev
RUN chmod +x /usr/local/bin/atmo-dev

USER dev
WORKDIR /workspaces/atmosphera
