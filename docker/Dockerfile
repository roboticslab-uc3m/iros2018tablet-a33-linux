# Dockerfile
FROM ubuntu:22.04

# Prevent interactive prompts during apt installations
ENV DEBIAN_FRONTEND=noninteractive

# Install essential build tools, ARM cross-compilers, and dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    crossbuild-essential-armhf \
    gcc-arm-linux-gnueabihf \
    g++-arm-linux-gnueabihf \
    git \
    make \
    bc \
    bison \
    flex \
    libssl-dev \
    ncurses-dev \
    u-boot-tools \
    device-tree-compiler \
    swig \
    python3-dev \
    python3-setuptools \
    wget \
    cpio \
    lzop \
    kmod \
    dosfstools \
    && rm -rf /var/lib/apt/lists/*

# Setup a non-root user to match your host UID/GID
# We use build args so you can pass your host's ID
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USER_NAME=builder

RUN groupadd -g ${GROUP_ID} ${USER_NAME} && \
    useradd -m -u ${USER_ID} -g ${GROUP_ID} -s /bin/bash ${USER_NAME}

# Switch to the new user
USER ${USER_NAME}
WORKDIR /home/${USER_NAME}/workspace