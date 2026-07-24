FROM archlinux:base-devel

RUN pacman -Sy --noconfirm --needed \
    qt6-declarative qt6-tools \
    python python-pip \
    shellcheck shfmt \
    tree-sitter \
    rustup \
    sudo

RUN useradd -m -G wheel -s /bin/bash dev \
  && echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/dev

USER dev
WORKDIR /workspaces/atmosphera
