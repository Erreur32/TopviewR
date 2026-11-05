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
# keeps the password out of ttyd's command line (see ttyd-cred.c)
COPY ttyd-cred.c /src/
RUN mkdir -p /out/usr/local/lib && gcc -shared -fPIC -O2 -Wall -Werror -o /out/usr/local/lib/ttyd-cred.so /src/ttyd-cred.c

# ---------- build: nvtop compiled from source (not in Alpine stable) ----------
FROM alpine:${ALPINE_VERSION} AS nvtop
ARG NVTOP_VERSION=3.3.2
ARG NVTOP_SHA256=48a295f3b3a917cc851d1aa8b185c09fde3a1b1e741fc57d7fa96b3671271630
RUN apk add --no-cache build-base cmake ncurses-dev libdrm-dev eudev-dev curl
WORKDIR /src
RUN curl -fsSL -o nvtop.tar.gz "https://github.com/Syllo/nvtop/archive/refs/tags/${NVTOP_VERSION}.tar.gz" \
 && echo "${NVTOP_SHA256}  nvtop.tar.gz" | sha256sum -c - \
 && tar xzf nvtop.tar.gz --strip-components=1 \
 && cmake -S . -B b -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DNVIDIA_SUPPORT=ON -DAMDGPU_SUPPORT=ON -DINTEL_SUPPORT=ON \
 && cmake --build b -j"$(nproc)" \
 && install -Dm755 b/src/nvtop /out/usr/local/bin/nvtop

# ---------- final image ----------
FROM alpine:${ALPINE_VERSION}
ARG BTOP_VERSION=1.4.8
ARG NVTOP_VERSION=3.3.2
ARG VERSION=dev
ARG REVISION=unknown
ARG CREATED=unknown
LABEL org.opencontainers.image.title="TopviewR" \
      org.opencontainers.image.description="btop, htop or nvtop in the browser via ttyd, hardened for LAN use" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}" \
      org.opencontainers.image.source="https://github.com/Erreur32/TopviewR" \
      org.opencontainers.image.licenses="Apache-2.0 AND GPL-2.0-or-later AND GPL-3.0-or-later AND MIT AND ISC" \
      io.btop.version="${BTOP_VERSION}" \
      io.nvtop.version="${NVTOP_VERSION}"

RUN apk add --no-cache ttyd tini su-exec curl openssl libstdc++ libgcc htop tmux ncurses-libs eudev-libs libdrm \
 # the monitor runs as a non-root UID: it must be able to traverse /root to read its config
 && chmod 0755 /root && mkdir -p /root/.config/btop /certs && chmod 0755 /root/.config \
 # htop default theme: Black Night, until a theme is picked in htop (F2, saved in the config volume)
 && echo 'color_scheme=5' > /etc/htoprc

COPY --from=build /out/usr/local/ /usr/local/
COPY --from=nvtop /out/usr/local/ /usr/local/
COPY --from=build /out/btop.conf.default /usr/local/share/btop/btop.conf.default
COPY --chmod=0755 entrypoint.sh healthcheck.sh menu.sh session.sh /usr/local/bin/
COPY tmux.conf /usr/local/share/topviewr/tmux.conf
COPY assets/logo.svg /tmp/logo.svg
# ttyd's own page with the TopviewR favicon and title, taken from the installed ttyd so it always matches its version
RUN (ttyd -p 7999 -i lo true >/dev/null 2>&1 & pid=$!; \
     for i in 1 2 3 4 5 6 7 8 9 10; do curl -fsS -o /tmp/index.html http://127.0.0.1:7999/ && break; sleep 0.5; done; \
     kill "$pid") \
 && sed -i -e "s|<link rel=\"icon\"[^>]*>|<link rel=\"icon\" type=\"image/svg+xml\" href=\"data:image/svg+xml;base64,$(base64 -w0 /tmp/logo.svg)\">|" \
           -e 's|<title>[^<]*</title>|<title>TopviewR</title>|' /tmp/index.html \
 # fail the build if a future ttyd page no longer matches
 && grep -q 'image/svg+xml;base64' /tmp/index.html && grep -q '<title>TopviewR</title>' /tmp/index.html \
 && mv /tmp/index.html /usr/local/share/topviewr/index.html && rm /tmp/logo.svg
# license texts of the bundled tools (btop Apache-2.0, htop GPL-2.0+, nvtop GPL-3.0+, ttyd MIT, tmux ISC); sources: see README
COPY licenses/ /usr/local/share/licenses/

# with pid: host tini is not PID 1: register it as child subreaper so it still reaps zombies
ENV TINI_SUBREAPER=1 \
    LANG=C.UTF-8 \
    XDG_CONFIG_HOME=/root/.config \
    XDG_STATE_HOME=/tmp \
    BTOP_PORT=7681

EXPOSE 7681
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["/usr/local/bin/healthcheck.sh"]
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
