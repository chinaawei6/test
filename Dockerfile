# ==============================================================================
# Dockerfile to build a FULLY STATIC OpenSSH for OpenWrt (using glibc toolchain)
# Version: The Ultimate Static Build (produces a single tarball)
# ==============================================================================

FROM debian:bookworm AS builder

# --- Build Arguments for ARMv5 (armel, glibc) ---
ARG TARGETTRIPLET=arm-linux-gnueabi
ARG INSTALL_PREFIX=/usr/local/openssh-static-armel

# Versions for dependencies and OpenSSH
ARG ZLIB_VERSION=1.3.1
ARG OPENSSL_VERSION=3.0.12
ARG OPENSSH_VERSION=9.7p1

# URLs for the source code
ARG ZLIB_URL=http://www.zlib.net/zlib-${ZLIB_VERSION}.tar.gz
ARG OPENSSL_URL=https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
ARG OPENSSH_URL=https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-${OPENSSH_VERSION}.tar.gz

# --- Install Build Dependencies for armel (glibc based) ---
RUN apt-get update && \
    dpkg --add-architecture armel && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        crossbuild-essential-armel \
        wget \
        tar \
        ca-certificates \
        perl \
        autoconf \
        automake \
        zlib1g-dev:armel \
    && rm -rf /var/lib/apt/lists/*

# --- Set up Cross-Compilation Environment for STATIC linking ---
ENV CC=${TARGETTRIPLET}-gcc
ENV CFLAGS="-static -Os"
ENV LDFLAGS="-static"
ENV PKG_CONFIG_PATH=/usr/${TARGETTRIPLET}/lib/pkgconfig

# --- 1. Compile zlib (static) ---
WORKDIR /build/zlib
RUN wget -O zlib.tar.gz ${ZLIB_URL} && tar -xzf zlib.tar.gz
WORKDIR /build/zlib/zlib-${ZLIB_VERSION}
RUN ./configure --prefix=/usr/${TARGETTRIPLET} --static
RUN make -j$(nproc) && make install

# --- 2. Compile OpenSSL (static) ---
WORKDIR /build/openssl
RUN wget -O openssl.tar.gz ${OPENSSL_URL} && tar -xzf openssl.tar.gz
WORKDIR /build/openssl/openssl-${OPENSSL_VERSION}
RUN ./Configure linux-armv4 \
    --prefix=/usr/${TARGETTRIPLET} \
    --openssldir=/etc/ssl \
    no-asm no-shared no-dso no-engine
RUN make -j$(nproc) && make install_sw

# --- 3. Compile OpenSSH (static) ---
WORKDIR /build/openssh
RUN wget --no-check-certificate -O openssh.tar.gz ${OPENSSH_URL} && tar -xzf openssh.tar.gz
WORKDIR /build/openssh/openssh-${OPENSSH_VERSION}
RUN autoreconf -i
RUN ./configure \
    --host=${TARGETTRIPLET} \
    --with-zlib=/usr/${TARGETTRIPLET} \
    --with-ssl-dir=/usr/${TARGETTRIPLET} \
    --without-pam
RUN make -j$(nproc)

# --- 4. Manually "install" and package the required files ---
RUN mkdir -p ${INSTALL_PREFIX}/bin ${INSTALL_PREFIX}/sbin ${INSTALL_PREFIX}/etc ${INSTALL_PREFIX}/libexec
RUN cp sshd ${INSTALL_PREFIX}/sbin/
RUN cp ssh scp ssh-add ssh-agent ssh-keyscan ${INSTALL_PREFIX}/bin/
RUN cp sftp-server ${INSTALL_PREFIX}/libexec/
RUN cp sshd_config ${INSTALL_PREFIX}/etc/
RUN cp ssh_config ${INSTALL_PREFIX}/etc/
RUN ${TARGETTRIPLET}-strip ${INSTALL_PREFIX}/sbin/sshd
RUN ${TARGETTRIPLET}-strip ${INSTALL_PREFIX}/bin/*
RUN ${TARGETTRIPLET}-strip ${INSTALL_PREFIX}/libexec/*
# (KEY CHANGE) Create a final tarball
WORKDIR ${INSTALL_PREFIX}
RUN tar -czf /openssh-static-armel.tar.gz .


# --- Final Stage: The Artifact ---
# This stage contains ONLY the final compressed package.
FROM scratch
COPY --from=builder /openssh-static-armel.tar.gz /```

### **最终的、修正后的 GitHub Actions Workflow**

```yaml
# ==============================================================================
# GitHub Actions Workflow to build a STATIC OpenSSH package for OpenWrt
# Version: Final fix for artifact extraction.
# ==============================================================================

name: Build Static OpenSSH Package for OpenWrt (ARMv5)

on:
  push:
    branches: [ "main", "master" ]
  workflow_dispatch:

jobs:
  build-static-package:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build the static OpenSSH package using Dockerfile
        run: |
          docker buildx build \
            --platform linux/amd64 \
            -t openssh-static-package \
            --output type=docker \
            .

      # (KEY FIX) A much simpler and more reliable extraction method.
      - name: Extract final tarball from the image
        run: |
          mkdir -p ./openssh-dist
          # Create a temporary container from the final image
          id=$(docker create openssh-static-package)
          # Copy the single tar.gz file from the container's root
          docker cp "$id:/openssh-static-armel.tar.gz" ./openssh-dist/
          # Clean up the container
          docker rm -v "$id"

      - name: Upload Artifact
        uses: actions/upload-artifact@v4
        with:
          name: openssh-static-armel-package
          path: ./openssh-dist/
