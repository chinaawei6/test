# ==============================================================================
# Dockerfile to build a FULLY STATIC OpenSSH with PAM for OpenWrt (ARMv5, uClibc)
# Version: The Ultimate uClibc Build with PAM support
# ==============================================================================

# --- STAGE 1: The uClibc Cross-Compiler Toolchain Builder ---
FROM debian:bookworm AS toolchain-builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential git wget ca-certificates bison flex texinfo \
        gperf libtool patchutils bc unzip help2man python3-dev

WORKDIR /build
RUN git clone https://github.com/crosstool-ng/crosstool-ng.git
WORKDIR /build/crosstool-ng
RUN ./bootstrap && ./configure --enable-local && make -j$(nproc)

RUN ./ct-ng arm-unknown-linux-uclibcgnueabi
RUN sed -i 's/CT_LINUX_VERSION=".*"/CT_LINUX_VERSION="5.10.158"/' .config && \
    sed -i 's/CT_UCLIBC_VERSION=".*"/CT_UCLIBC_VERSION="1.0.43"/' .config && \
    ./ct-ng build


# --- STAGE 2: The Final Builder ---
FROM debian:bookworm AS final-builder

COPY --from=toolchain-builder /root/x-tools/arm-unknown-linux-uclibcgnueabi /usr/local/uclibc-toolchain
ENV PATH="/usr/local/uclibc-toolchain/bin:${PATH}"

ARG TARGETTRIPLET=arm-unknown-linux-uclibcgnueabi
ARG INSTALL_PREFIX=/usr/local/openssh-static-uclibc-pam

# Versions for dependencies and OpenSSH
ARG ZLIB_VERSION=1.3.1
ARG OPENSSL_VERSION=3.0.12
ARG PAM_VERSION=1.5.3
ARG OPENSSH_VERSION=9.7p1

ARG ZLIB_URL=http://www.zlib.net/zlib-${ZLIB_VERSION}.tar.gz
ARG OPENSSL_URL=https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
ARG PAM_URL=https://github.com/linux-pam/linux-pam/releases/download/v${PAM_VERSION}/Linux-PAM-${PAM_VERSION}.tar.xz
ARG OPENSSH_URL=https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-${OPENSSH_VERSION}.tar.gz

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential wget tar ca-certificates perl autoconf automake libtool \
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
    --prefix=${INSTALL_PREFIX} --openssldir=${INSTALL_PREFIX}/ssl \
    no-asm no-shared no-dso no-engine \
    --with-zlib-include=${INSTALL_PREFIX}/include \
    --with-zlib-lib=${INSTALL_PREFIX}/lib
RUN make -j$(nproc) && make install_sw

# --- 3. (NEW) Compile Linux-PAM (static) ---
WORKDIR /build/pam
RUN wget -O pam.tar.xz ${PAM_URL} && tar -xJf pam.tar.xz
WORKDIR /build/pam/Linux-PAM-${PAM_VERSION}
# We must disable some features that are hard to statically link or not needed.
RUN ./configure \
    --host=${TARGETTRIPLET} \
    --prefix=${INSTALL_PREFIX} \
    --disable-shared \
    --enable-static \
    --disable-db \
    --without-selinux
RUN make -j$(nproc) && make install

# --- 4. Compile OpenSSH (static, with PAM) ---
WORKDIR /build/openssh
RUN wget --no-check-certificate -O openssh.tar.gz ${OPENSSH_URL} && tar -xzf openssh.tar.gz
WORKDIR /build/openssh/openssh-${OPENSSH_VERSION}
RUN autoreconf -i
# LDFLAGS needs to explicitly find the static PAM and crypto libraries
RUN LDFLAGS="-all-static -L${INSTALL_PREFIX}/lib" \
    CPPFLAGS="-I${INSTALL_PREFIX}/include" \
    ./configure \
        --host=${TARGETTRIPLET} \
        --prefix=${INSTALL_PREFIX} \
        --sysconfdir=${INSTALL_PREFIX}/etc \
        --with-zlib=${INSTALL_PREFIX} \
        --with-ssl-dir=${INSTALL_PREFIX} \
        --with-pam \
        --with-privsep-path=/var/empty/sshd
RUN make -j$(nproc)
RUN make install-nokeys


# --- Final Stage: The Artifact ---
FROM scratch
ARG INSTALL_PREFIX=/usr/local/openssh-static-uclibc-pam
COPY --from=final-builder ${INSTALL_PREFIX} /
