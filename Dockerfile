# syntax=docker/dockerfile:1
ARG ALPINE_VERSION=3.24

# ---------- build: btop compiled from source (GPU support) ----------
FROM alpine:${ALPINE_VERSION} AS build
ARG BTOP_VERSION=1.4.8
ARG BTOP_SHA256=67e07c21b770a6d884c5e50ba1d2cfc90732ea57459367d8732ec7ecbeb3be5f
RUN apk add --no-cache build-base linux-headers curl
WORKDIR /src
RUN curl -fsSL -o btop.tar.gz "https://github.com/aristocratos/btop/archive/refs/tags/v${BTOP_VERSION}.tar.gz" \
 && echo "${BTOP_SHA256}  btop.tar.gz" | sha256sum -c - \
    # btop only enables the Intel GPU sources on x86_64; forcing GPU_SUPPORT elsewhere needs them too
 && tar xzf btop.tar.gz --strip-components=1 \
 && make -j"$(nproc)" GPU_SUPPORT=true INTEL_GPU_SUPPORT=true \
 && make install DESTDIR=/out PREFIX=/usr/local \
 && rm -rf /out/usr/local/share/applications /out/usr/local/share/icons /out/usr/local/share/doc \
 && /out/usr/local/bin/btop --default-config \
    # the container fstab does not list host disks: btop reads the real mounts
    | sed -e "s/^use_fstab = true/use_fstab = false/" \
          -e "s|^disks_filter = \"\"|disks_filter = \"exclude=/etc/hostname /etc/hosts /etc/resolv.conf /etc/localtime\"|" \
    > /out/btop.conf.default

# ---------- final image ----------
FROM alpine:${ALPINE_VERSION}
ARG BTOP_VERSION=1.4.8
ARG VERSION=dev
ARG REVISION=unknown
ARG CREATED=unknown
LABEL org.opencontainers.image.title="btop-web" \
      org.opencontainers.image.description="btop in the browser via ttyd, hardened for LAN use" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}" \
      org.opencontainers.image.source="https://github.com/Erreur32/btop-web" \
      org.opencontainers.image.licenses="Apache-2.0" \
      io.btop.version="${BTOP_VERSION}"

RUN apk add --no-cache ttyd tini su-exec curl openssl libstdc++ libgcc \
 # btop runs as a non-root UID: it must be able to traverse /root to read its config
 && chmod 0755 /root && mkdir -p /root/.config/btop /certs && chmod 0755 /root/.config

COPY --from=build /out/usr/local/ /usr/local/
COPY --from=build /out/btop.conf.default /usr/local/share/btop/btop.conf.default
COPY --chmod=0755 entrypoint.sh healthcheck.sh /usr/local/bin/

# with pid: host tini is not PID 1: register it as child subreaper so it still reaps zombies
ENV TINI_SUBREAPER=1 \
    LANG=C.UTF-8 \
    XDG_CONFIG_HOME=/root/.config \
    XDG_STATE_HOME=/tmp \
    BTOP_PORT=7681

EXPOSE 7681
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["/usr/local/bin/healthcheck.sh"]
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
