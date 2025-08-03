# ==============================================================================
# Dockerfile to build a FULLY STATIC OpenSSH for OpenWrt (using glibc toolchain)
# Version: The Ultimate Static Build (Manual Install)
# ==============================================================================

# We only need a single stage now.
FROM debian:bookworm AS builder

# --- Build Arguments for ARMv-el, glibc) ---
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
# (KEY CHANGE) We only run 'make', not 'make install'.
RUN make -j$(nproc)

# --- 4. (KEY CHANGE) Manually "install" the required files ---
# Create a clean directory for our final package
RUN mkdir -p ${INSTALL_PREFIX}/bin ${INSTALL_PREFIX}/sbin ${INSTALL_PREFIX}/etc ${INSTALL_PREFIX}/libexec
# Copy the server binary
RUN cp sshd ${INSTALL_PREFIX}/sbin/
# Copy the client binaries
RUN cp ssh scp ssh-add ssh-agent ssh-keyscan ${INSTALL_PREFIX}/bin/
# Copy the sftp-server, which is needed by the server
RUN cp sftp-server ${INSTALL_PREFIX}/libexec/
# Copy the default config files
RUN cp sshd_config ${INSTALL_PREFIX}/etc/
RUN cp ssh_config ${INSTALL_PREFIX}/etc/
# (Optional) Use the arm cross-compiler's strip to reduce size
RUN ${TARGETTRIPLET}-strip ${INSTALL_PREFIX}/sbin/sshd
RUN ${TARGETTRIPLET}-strip ${INSTALL_PREFIX}/bin/*
RUN ${TARGETTRIPLET}-strip ${INSTALL_PREFIX}/libexec/*

# --- Final Stage: The Artifact ---
FROM scratch
ARG INSTALL_PREFIX=/usr/local/openssh-static-armel
COPY --from=builder ${INSTALL_PREFIX} /
