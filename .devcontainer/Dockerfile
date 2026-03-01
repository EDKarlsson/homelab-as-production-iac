FROM python:3.13
ARG USERNAME=odin
ARG UID=1000
ARG GID=1000
ARG WORKSPACE=workspace

WORKDIR /${WORKSPACE}


RUN apt update && apt install --no-install-recommends -y \
    aggregate \
    build-essential \
    ca-certificates \
    curl \
    dnsutils \
    fzf \
    gh \
    git \
    gnupg2 \
    iproute2 \
    ipset \
    iptables \
    iputils-ping \
    jq \
    less \
    man-db \
    nano \
    procps \
    sudo \
    unzip \
    vim \
    wget \ 
    && rm -rf /var/lib/apt/lists/*

# COPY requirements.txt /${WORKSPACE}/requirements.txt

RUN useradd -m $USERNAME -s /usr/bin/zsh && chown -R $USERNAME /${WORKSPACE} && usermod -aG sudo $USERNAME \
    && echo $USERNAME ALL=\(ALL\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

USER $USERNAME

RUN  npm install -g @google/gemini-cli @doist/todoist-ai \
     && url -fsSL https://claude.ai/install.sh | bash

RUN echo 'export PATH=$PATH:${HOME}/.local/bin' >> /home/$USERNAME/.zshrc