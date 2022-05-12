ARG USER=vscode
ARG UID=1000
ARG GID=${UID}

FROM debian:stable-slim as base

ARG USER
ARG UID
ARG GID
ARG NIX_INSTALLER=https://nixos.org/nix/install

# Install deps required by Nix installer
RUN apt update && apt upgrade -y && apt install -y \
    ca-certificates \
    curl \
    sudo \
    xz-utils

# Create user
RUN groupadd -g ${GID} ${USER} && \
    useradd -u ${UID} -g ${GID} -G sudo -m ${USER} -s /bin/bash

# Install Nix and enable flakes
RUN sed -i 's/%sudo.*ALL/%sudo   ALL=(ALL:ALL) NOPASSWD:ALL/' /etc/sudoers && \
    curl -L ${NIX_INSTALLER} | sudo -u ${USER} NIX_INSTALLER_NO_MODIFY_PROFILE=1 sh && \
    echo "sandbox = false" > /etc/nix.conf && \
    echo "experimental-features = nix-command flakes" >> /etc/nix.conf

# Install home-manager
USER ${USER}
WORKDIR /home/${USER}
ENV USER=${USER}
ENV NIX_PATH=/home/${USER}/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels
RUN . /home/${USER}/.nix-profile/etc/profile.d/nix.sh && \
    nix-env --set-flag priority 10 nix-2.8.0 && \
    nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager && \
    nix-channel --update && \
    nix-shell '<home-manager>' -A install

# Build first generation
COPY config/config.nix /home/${USER}/.config/nixpkgs/home.nix
RUN . /home/${USER}/.nix-profile/etc/profile.d/nix.sh && \
    home-manager build

FROM debian:stable-slim

ARG USER
ARG UID
ARG GID

ENV NIX_CONF_DIR /etc
ENV DIRENV_CONFIG /etc

## Install vscode deps
RUN apt update && apt upgrade -y && apt install -y \
    ca-certificates \
    git \
    gnupg \
    ssh \
    sudo

# Create user
RUN apt update && apt upgrade -y && apt install -y sudo ca-certificates && \
    groupadd -g ${GID} ${USER} && \
    useradd -u ${UID} -g ${GID} -G sudo -m ${USER} -s /bin/bash
COPY --from=base --chown=${USER}:${USER} /home/${USER} /home/${USER}

# Configure en_US.UTF-8 locale
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y locales && \
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    locale-gen

# Configure sudo
RUN apt install -y sudo && \
    sed -i 's/%sudo.*ALL/%sudo   ALL=(ALL:ALL) NOPASSWD:ALL/' /etc/sudoers

# Setup Nix environment
RUN echo "source /home/${USER}/.nix-profile/etc/profile.d/nix.sh" >> /etc/bash.bashrc && \
    echo "source /home/${USER}/.nix-profile/etc/profile.d/nix.sh" >> /etc/zshrc

# Copy direnv config
COPY config/direnv.toml /etc

# Bring in Nix
COPY --from=base /nix /nix
COPY --from=base /etc/nix.conf /etc/nix.conf

USER ${USER}

# Setup vscode
RUN mkdir -p /home/${USER}/.vscode-server/extensions && \
    mkdir -p /home/${USER}/.vscode-server-insiders/extensions

# Switch to home-manager environment
WORKDIR /home/${USER}
ENV USER=${USER}
RUN . /home/${USER}/.nix-profile/etc/profile.d/nix.sh && \
    home-manager switch && \
    rm /home/${USER}/result && \
    nix-collect-garbage -d

# Copy entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh

ENTRYPOINT [ "/docker-entrypoint.sh" ]