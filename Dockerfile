# ==============================================================================
# Dockerfile to build a FULLY STATIC OpenSSH for OpenWrt (linux/arm/v5, armel, musl)
# Version: The Ultimate Static Build for Embedded Systems
# ==============================================================================

# --- STAGE 1: The Musl Cross-Compiler Toolchain Builder ---
# This stage builds the cross-compiler for arm-linux-musleabi.
FROM debian:bookworm AS toolchain-builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        git \
        wget \
        bzip2 \
        unzip \
        help2man \
        texinfo \
        file

# Use musl-cross-make to build a cross-compiler targeting armel (soft-float).
WORKDIR /build
RUN git clone https://github.com/richfelker/musl-cross-make.git
WORKDIR /build/musl-cross-make
# Create a config file for our target.
# TARGET = arm-linux-musleabi specifies the soft-float ARM toolchain with musl libc.
RUN echo "TARGET = arm-linux-musleabi" > config.mak
# Download sources and build the toolchain.
RUN make -j$(nproc) && make install

# The toolchain will be installed in /usr/local/arm-linux-musleabi.


# --- STAGE 2: The Final Builder ---
# This stage uses the toolchain we just built to compile everything statically.
FROM debian:bookworm AS final-builder

# Copy the cross-compiler toolchain from the previous stage.
COPY --from=toolchain-builder /usr/local/arm-linux-musleabi /usr/local/arm-linux-musleabi

# Add our new toolchain to the PATH.
ENV PATH="/usr/local/arm-linux-musleabi/bin:${PATH}"

# --- Build Arguments ---
ARG TARGETTRIPLET=arm-linux-musleabi
ARG INSTALL_PREFIX=/usr/local/openssh-static-armel

# Versions for dependencies and OpenSSH
ARG ZLIB_VERSION=1.3.1
ARG OPENSSL_VERSION=3.0.12
ARG OPENSSH_VERSION=9.7p1 # Using a well-tested version for static linking compatibility

# URLs for the source code
ARG ZLIB_URL=http://www.zlib.net/zlib-${ZLIB_VERSION}.tar.gz
ARG OPENSSL_URL=https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
ARG OPENSSH_URL=https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-${OPENSSH_VERSION}.tar.gz

# --- Install base dependencies for the build host ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends wget tar ca-certificates perl autoconf automake \
    && rm -rf /var/lib/apt/lists/*

# --- Set up Cross-Compilation Environment for STATIC linking ---
ENV CC=${TARGETTRIPLET}-gcc
# KEY: CFLAGS ensures everything is built for static linking and optimized for size.
ENV CFLAGS="-static -Os"
ENV LDFLAGS="-static"
ENV PKG_CONFIG_PATH=${INSTALL_PREFIX}/lib/pkgconfig

# --- 1. Compile zlib (static) for ARMv5/musl ---
WORKDIR /build/zlib
RUN wget -O zlib.tar.gz ${ZLIB_URL} && tar -xzf zlib.tar.gz
WORKDIR /build/zlib/zlib-${ZLIB_VERSION}
RUN ./configure --prefix=${INSTALL_PREFIX} --static
RUN make -j$(nproc) && make install

# --- 2. Compile OpenSSL (static) for ARMv5/musl ---
WORKDIR /build/openssl
RUN wget -O openssl.tar.gz ${OPENSSL_URL} && tar -xzf openssl.tar.gz
WORKDIR /build/openssl/openssl-${OPENSSL_VERSION}
# Use 'no-shared' and other flags to ensure a fully static library.
RUN ./Configure linux-armv4 \
    --prefix=${INSTALL_PREFIX} \
    --openssldir=${INSTALL_PREFIX}/ssl \
    no-asm \
    no-shared \
    no-dso \
    no-engine \
    --with-zlib-include=${INSTALL_PREFIX}/include \
    --with-zlib-lib=${INSTALL_PREFIX}/lib
RUN make -j$(nproc) && make install_sw

# --- 3. Compile OpenSSH (static) for ARMv5/musl ---
WORKDIR /build/openssh
RUN wget --no-check-certificate -O openssh.tar.gz ${OPENSSH_URL} && tar -xzf openssh.tar.gz
WORKDIR /build/openssh/openssh-${OPENSSH_VERSION}
RUN autoreconf -i
# LDFLAGS="-all-static" is another way to enforce static linking for OpenSSH.
RUN LDFLAGS="-all-static" ./configure \
    --host=${TARGETTRIPLET} \
    --prefix=${INSTALL_PREFIX} \
    --sysconfdir=${INSTALL_PREFIX}/etc \
    --with-zlib=${INSTALL_PREFIX} \
    --with-ssl-dir=${INSTALL_PREFIX} \
    --without-pam \
    --with-privsep-path=/var/empty/sshd
RUN make -j$(nproc)
# Use install-nokeys to prevent running armv5 ssh-keygen on the x86_64 host.
RUN make install-nokeys


# --- Final Stage: The Artifact ---
# This stage just holds the final compiled distribution.
FROM scratch
ARG INSTALL_PREFIX=/usr/local/openssh-static-armel
COPY --from=final-builder ${INSTALL_PREFIX} /
