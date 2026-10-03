FROM docker.io/library/archlinux:base-devel

# Container identity for the dev account. The default matches the Podman
# keep-id target; the Docker tooling path passes the invoking user's IDs
# as build arguments so bind-mount writes stay host-user-owned.
ARG DEV_UID=1000
ARG DEV_GID=1000

RUN pacman -Sy --noconfirm --needed \
    quickshell qt6-declarative qt6-tools \
    python python-pip \
    shellcheck shfmt \
    tree-sitter \
    rustup \
    sudo

RUN groupadd -g "$DEV_GID" dev \
  && useradd -m -u "$DEV_UID" -g "$DEV_GID" -G wheel -s /bin/bash dev \
  && echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/dev

COPY atmo-dev.sh /usr/local/bin/atmo-dev
RUN chmod +x /usr/local/bin/atmo-dev

USER dev
WORKDIR /workspaces/atmosphera
