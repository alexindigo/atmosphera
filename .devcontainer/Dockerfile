# Immutable Arch bootstrap; the mirrorlist selects the package versions.
FROM docker.io/library/archlinux:base-devel@sha256:949ecb1661609ab7e8f6854ba03efd62792e7a796313738e94b040c095c20d91 AS arch-snapshot
COPY arch-snapshot.mirrorlist arch-snapshot-install.sh /usr/local/share/atmosphera/
RUN bash /usr/local/share/atmosphera/arch-snapshot-install.sh

FROM arch-snapshot AS settings-check

# The settings gates use the Qt formatter and the pinned parser, not the
# shell runtime or any of the compiled QML plugins.
RUN pacman -S --noconfirm --needed git python python-pip qt6-declarative \
    && pacman -Scc --noconfirm
COPY settings-check-requirements.txt /opt/settings-check-requirements.txt
RUN pip install --break-system-packages --no-cache-dir -r /opt/settings-check-requirements.txt
WORKDIR /workspaces/atmosphera

FROM arch-snapshot AS devcontainer

# Container identity for the dev account. The default matches the Podman
# keep-id target; the Docker tooling path passes the invoking user's IDs
# as build arguments so bind-mount writes stay host-user-owned.
ARG DEV_UID=1000
ARG DEV_GID=1000

RUN pacman -S --noconfirm --needed \
    quickshell qt6-declarative qt6-tools qt6-multimedia qt6-imageformats \
    imagemagick ffmpeg libwebp libheif \
    cmake ninja pkgconf libpipewire mpv \
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
