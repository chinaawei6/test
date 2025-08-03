# ==============================================================================
# Dockerfile to build a FULLY STATIC OpenSSH for OpenWrt (using glibc toolchain)
# Version: The Ultimate Static Build (glibc version for max compatibility)
# ==============================================================================

# We only need a single stage now, as we don't build a toolchain anymore.
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
# KEY: We use -static to tell the linker to not use shared libraries.
ENV CFLAGS="-static -Os"
ENV LDFLAGS="-static"
# Add the cross-compiler's library path for pkg-config
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
    no-asm \
    no-shared \
    no-dso \
    no-engine
RUN make -j$(nproc) && make install_sw

# --- 3. Compile OpenSSH (static) ---
WORKDIR /build/openssh
RUN wget --no-check-certificate -O openssh.tar.gz ${OPENSSH_URL} && tar -xzf openssh.tar.gz
WORKDIR /build/openssh/openssh-${OPENSSH_VERSION}
RUN autoreconf -i
RUN ./configure \
    --host=${TARGETTRIPLET} \
    --prefix=${INSTALL_PREFIX} \
    --sysconfdir=${INSTALL_PREFIX}/etc \
    --with-zlib=/usr/${TARGETTRIPLET} \
    --with-ssl-dir=/usr/${TARGETTRIPLET} \
    --without-pam \
    --with-privsep-path=/var/empty/sshd
RUN make -j$(nproc)
RUN make install-nokeys

# --- Final Stage: The Artifact ---
FROM scratch
ARG INSTALL_PREFIX=/usr/local/openssh-static-armel
COPY --from=builder ${INSTALL_PREFIX} /
