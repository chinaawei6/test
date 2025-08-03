# ==============================================================================
# Dockerfile to build a FULLY STATIC OpenSSH for OpenWrt (linux/arm/v5, armel, musl)
# Version: The Ultimate Static Build (PAM removed)
# ==============================================================================

# --- STAGE 1: The Musl Cross-Compiler Toolchain Builder ---
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
        file \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone https://github.com/richfelker/musl-cross-make.git
WORKDIR /build/musl-cross-make

ENV OUTPUT=/usr/local/musl-toolchain
RUN echo "TARGET = arm-linux-musleabi" > config.mak && \
    echo "OUTPUT = ${OUTPUT}" >> config.mak

RUN make -j$(nproc) && make install


# --- STAGE 2: The Final Builder ---
FROM debian:bookworm AS final-builder

COPY --from=toolchain-builder /usr/local/musl-toolchain /usr/local/musl-toolchain
ENV PATH="/usr/local/musl-toolchain/bin:${PATH}"

ARG TARGETTRIPLET=arm-linux-musleabi
ARG INSTALL_PREFIX=/usr/local/openssh-static-armel

ARG ZLIB_VERSION=1.3.1
ARG OPENSSL_VERSION=3.0.12
ARG OPENSSH_VERSION=9.7p1

ARG ZLIB_URL=http://www.zlib.net/zlib-${ZLIB_VERSION}.tar.gz
ARG OPENSSL_URL=https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
ARG OPENSSH_URL=https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-${OPENSSH_VERSION}.tar.gz

# (KEY FIX) We no longer need any PAM development libraries.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        wget \
        tar \
        ca-certificates \
        perl \
        autoconf \
        automake \
    && rm -rf /var/lib/apt/lists/*

ENV CC=${TARGETTRIPLET}-gcc
ENV CFLAGS="-static -Os"
ENV LDFLAGS="-static"
ENV PKG_CONFIG_PATH=${INSTALL_PREFIX}/lib/pkgconfig

# --- 1. Compile zlib (static) ---
WORKDIR /build/zlib
RUN wget -O zlib.tar.gz ${ZLIB_URL} && tar -xzf zlib.tar.gz
WORKDIR /build/zlib/zlib-${ZLIB_VERSION}
RUN ./configure --prefix=${INSTALL_PREFIX} --static
RUN make -j$(nproc) && make install

# --- 2. Compile OpenSSL (static) ---
WORKDIR /build/openssl
RUN wget -O openssl.tar.gz ${OPENSSL_URL} && tar -xzf openssl.tar.gz
WORKDIR /build/openssl/openssl-${OPENSSL_VERSION}
RUN ./Configure linux-armv4 \
    --prefix=${INSTALL_PREFIX} \
    --openssldir=${INSTALL_PREFIX}/ssl \
    no-asm no-shared no-dso no-engine \
    --with-zlib-include=${INSTALL_PREFIX}/include \
    --with-zlib-lib=${INSTALL_PREFIX}/lib
RUN make -j$(nproc) && make install_sw

# --- 3. Compile OpenSSH (static) ---
WORKDIR /build/openssh
RUN wget --no-check-certificate -O openssh.tar.gz ${OPENSSH_URL} && tar -xzf openssh.tar.gz
WORKDIR /build/openssh/openssh-${OPENSSH_VERSION}
RUN autoreconf -i
# (KEY FIX) Removed '--with-pam' from the configure options.
RUN LDFLAGS="-all-static" ./configure \
    --host=${TARGETTRIPLET} \
    --prefix=${INSTALL_PREFIX} \
    --sysconfdir=${INSTALL_PREFIX}/etc \
    --with-zlib=${INSTALL_PREFIX} \
    --with-ssl-dir=${INSTALL_PREFIX} \
    --without-pam \
    --with-privsep-path=/var/empty/sshd
RUN make -j$(nproc)
RUN make install-nokeys


# --- Final Stage: The Artifact ---
FROM scratch
ARG INSTALL_PREFIX=/usr/local/openssh-static-armel
COPY --from=final-builder ${INSTALL_PREFIX} /
