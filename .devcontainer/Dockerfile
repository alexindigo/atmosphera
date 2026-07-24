FROM archlinux:base-devel

RUN pacman -Sy --noconfirm --needed \
    quickshell qt6-declarative qt6-tools \
    python python-pip \
    shellcheck shfmt \
    tree-sitter \
    rustup \
    sudo

RUN useradd -m -G wheel -s /bin/bash dev \
  && echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/dev

COPY atmo-dev.sh /usr/local/bin/atmo-dev
RUN chmod +x /usr/local/bin/atmo-dev

USER dev
WORKDIR /workspaces/atmosphera
