# ==============================================================================
# Dockerfile to build the LATEST STABLE OpenSSH for linux/arm/v7
# This runs inside a QEMU emulated environment on GitHub Actions.
# ==============================================================================

# --- STAGE 1: The Builder ---
FROM debian:bookworm AS builder

# Install all dependencies required for the build process
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        git \
        ca-certificates \
        autoconf \
        automake \
        libpam0g-dev \
        zlib1g-dev \
        libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# --- Source Code Preparation ---
# Define arguments for repository and installation path
ARG OPENSSH_REPO_URL=https://anongit.mindrot.org/openssh.git
ARG INSTALL_PREFIX=/usr/local/openssh-dist

# Clone the source code
WORKDIR /build
RUN git clone ${OPENSSH_REPO_URL} openssh
WORKDIR /build/openssh

# Find the latest stable tag (e.g., V_9_7_P1) and check it out
RUN LATEST_TAG=$(git tag -l "V_*_P*" | grep -v "pre" | grep -v "snap" | sort -V | tail -n 1) && \
    echo "--- Building OpenSSH version: ${LATEST_TAG} ---" && \
    git checkout ${LATEST_TAG}

# --- Build Process ---
# This is a standard, native build process running inside the emulated environment.

# 1. Generate the 'configure' script.
RUN autoreconf -i

# 2. Configure the build.
RUN ./configure \
    --prefix=${INSTALL_PREFIX} \
    --sysconfdir=${INSTALL_PREFIX}/etc \
    --with-pam \
    --with-privsep-path=/var/empty/sshd

# 3. Compile.
RUN make -j$(nproc)

# 4. Install.
RUN make install

# --- Final Stage: Create the package ---
# This stage is just a container for the final compiled files.
FROM scratch
ARG INSTALL_PREFIX=/usr/local/openssh-dist
COPY --from=builder ${INSTALL_PREFIX} /
