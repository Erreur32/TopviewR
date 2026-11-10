# TopviewR, btop, htop and nvtop in your browser

<div align="center">

<img src="assets/logo.svg" alt="TopviewR" width="160" height="160" />

[![Release](https://img.shields.io/github/v/release/Erreur32/TopviewR?style=for-the-badge&logo=github&logoColor=white&label=Release&color=111827)](https://github.com/Erreur32/TopviewR/releases)
[![Build](https://img.shields.io/github/actions/workflow/status/Erreur32/TopviewR/build.yml?branch=main&style=for-the-badge&logo=github&logoColor=white&label=Build&color=111827)](https://github.com/Erreur32/TopviewR/actions/workflows/build.yml)
[![Docker](https://img.shields.io/badge/Docker-ghcr.io-1f2937?style=for-the-badge&logo=docker&logoColor=38bdf8)](https://github.com/Erreur32/TopviewR/pkgs/container/topviewr)
![Arch](https://img.shields.io/badge/arch-amd64_|_arm64-111827?style=for-the-badge&logo=linux&logoColor=white)
[![btop](https://img.shields.io/badge/btop-1.4.8-111827?style=for-the-badge&logoColor=white)](https://github.com/aristocratos/btop)
[![htop](https://img.shields.io/badge/htop-3.5.3-111827?style=for-the-badge&logoColor=white)](https://github.com/htop-dev/htop)
[![nvtop](https://img.shields.io/badge/nvtop-3.3.2-111827?style=for-the-badge&logoColor=white)](https://github.com/Syllo/nvtop)
[![ttyd](https://img.shields.io/badge/ttyd-1.7.7-111827?style=for-the-badge&logoColor=white)](https://github.com/tsl0922/ttyd)
[![Alpine](https://img.shields.io/badge/Alpine-3.24-111827?style=for-the-badge&logo=alpinelinux&logoColor=0d597f)](https://alpinelinux.org/)
[![Trivy](https://img.shields.io/badge/Trivy-scanned-111827?style=for-the-badge&logo=aqua&logoColor=1904da)](https://github.com/aquasecurity/trivy)
[![License](https://img.shields.io/badge/License-Apache_2.0-111827?style=for-the-badge&color=111827&labelColor=111827&logoColor=white)](LICENSE)

**[btop](https://github.com/aristocratos/btop), [htop](https://github.com/htop-dev/htop) or [nvtop](https://github.com/Syllo/nvtop) in a browser tab, served by [ttyd](https://github.com/tsl0922/ttyd), hardened for LAN use. Drop-in replacement for the removed `big-bear-btop` image.**

[Why](#why-topviewr-exists) | [Built on](#built-on) | [Quick start](#quick-start) | [Switching](#switching-tools-in-the-browser) | [Login](#login-and-password) | [Security](#security) | [Variables](#variables) | [Migration](#migrating-from-big-bear-btop) | [Image tags](#image-tags) | [Changelog](CHANGELOG.md)

</div>

```sh
docker pull ghcr.io/erreur32/topviewr:latest
```

> **Renamed**: TopviewR was called **btop-web** up to v1.0.0. The old image `ghcr.io/erreur32/btop-web` still receives the same builds for now, so existing installs keep updating; switch your `image:` line to `ghcr.io/erreur32/topviewr` when you can. The old GitHub address redirects here.

## Why TopviewR exists

Many homelab setups used `bigbeartechworld/big-bear-btop` to show btop in a browser tab. That image is gone:

- **It was removed from Docker Hub.** The repository returns 404 and the registry 401, so existing servers can no longer pull or update it, and container managers (Dockhand, Watchtower, Portainer...) report `[Registry] ... 401` errors.
- **It was built on GoTTY**, which has been unmaintained since 2024.
- **It ran everything as root in a `privileged` container.** Anyone who could open the page could press `k` in btop and kill any process on the host (dockerd, sshd...).
- **It shipped an old btop** that was never updated.

TopviewR is a maintained replacement: same use case and same compose variables, but a current btop, an actively developed web terminal and safer defaults.

## What you get

- **btop 1.4.8** compiled from source (checksum verified, GPU support enabled), on **Alpine 3.24**, served by **ttyd 1.7.7**. The image is about 31 MB.
- **Rebuilt every week** for Alpine security fixes, with a Trivy scan on every build (0 known vulnerabilities on 2026-11-04).
- **Automatic btop updates**: a weekly job opens a PR when a new btop release is out.
- **Multi-arch** images: `linux/amd64` and `linux/arm64`.
- **NVIDIA GPUs** with the `:nvidia` variant (Debian, amd64), see [GPU](#gpu-btop-and-nvtop).
- **Three monitors in one image**, picked with `BTOP_TOOL`: **btop** (default), **htop 3.5.3** (Alpine package) or **nvtop 3.3.2** (GPU monitor, compiled from source). Same login, TLS and non-root protection for all three.
- **Drop-in compatible**: the old `GOTTY_AUTH_*` variables still work.

## Built on

TopviewR only packages and hardens these projects; all the monitoring work is theirs. Thanks to their authors.

| Project | Role in TopviewR | Repository |
|---|---|---|
| <img src="assets/apps/btop.svg" alt="" width="20" height="20" align="top" /> **btop** by aristocratos | default monitor (CPU, memory, disks, network, GPU, processes) | https://github.com/aristocratos/btop |
| <img src="assets/apps/htop.svg" alt="" width="20" height="20" align="top" /> **htop** by the htop authors | alternative process monitor (`BTOP_TOOL=htop`) | https://github.com/htop-dev/htop |
| <img src="assets/apps/nvtop.svg" alt="" width="20" height="20" align="top" /> **nvtop** by Maxime Schmitt | GPU monitor for AMD, Intel and NVIDIA (`BTOP_TOOL=nvtop`) | https://github.com/Syllo/nvtop |
| **ttyd** by Shuanglei Tao | web terminal: serves the monitor in the browser (auth, TLS, WebSocket) | https://github.com/tsl0922/ttyd |
| **Alpine Linux** | base image | https://alpinelinux.org |
| **tini** by Thomas Orozco | init process (signals, zombie reaping) | https://github.com/krallin/tini |
| **su-exec** by Natanael Copa | runs the monitor as a non-root user | https://github.com/ncopa/su-exec |
| **tmux** by Nicholas Marriott | switch layer: Esc menu and clickable bar (locked down, no shell) | https://github.com/tmux/tmux |
| **Trivy** by Aqua Security | vulnerability scan on every build | https://github.com/aquasecurity/trivy |

It replaces `bigbeartechworld/big-bear-btop` (Docker image and repository now removed), which was built on [GoTTY](https://github.com/yudai/gotty). Licenses: see [Credits and license](#credits-and-license).

## What changes compared to big-bear-btop

| | big-bear-btop | TopviewR |
|---|---|---|
| Image | `bigbeartechworld/big-bear-btop` (gone) | `ghcr.io/erreur32/topviewr` |
| Web terminal | GoTTY (unmaintained) | ttyd 1.7.7 |
| btop version | old, frozen | 1.4.8, updated automatically |
| btop runs as | root | UID 10001 (cannot signal host processes) |
| Password | optional | **required**, 12 characters minimum with `BTOP_PASS` |
| HTTPS | no | built in (`BTOP_TLS=auto` generates a self-signed certificate) |
| WebSocket origin check | no | yes (`ttyd -O`) |
| Max sessions | unlimited | 3 (`BTOP_MAX_CLIENTS`) |
| Recommended compose | `privileged`, `/proc`, `/sys`, `/dev` mounted | no `privileged`, `cap_drop: ALL` + 3 capabilities, read-only root |

What to expect when you switch:

- **Legacy compose (step 1 below)**: nothing changes for you except the image line. A `GOTTY_AUTH_PASS` shorter than 12 characters still works but logs a warning.
- **Hardened compose (step 2 below)**: the URL becomes `https://`, your browser warns once about the self-signed certificate, and you need a new password of at least 12 characters in `.env`. Network stats become the host's real interfaces instead of the container's `172.17.x` one.
- Starting without any password is refused, unless you explicitly set `BTOP_NO_AUTH=true`.
- The mounted config folder is chowned to UID 10001 so btop can save its settings.

## Quick start

```sh
cp .env.example .env
# edit .env: BTOP_PASS (12 characters min.), BTOP_TLS_SAN (server IP and hostname)
docker compose up -d
```

Open `https://<server-ip>:7681`. The browser warns once that the certificate is self-signed: accept the exception, then log in.

## Switching tools in the browser

The page opens on the default tool (`BTOP_TOOL`, btop unless set) with a one-line bar at the bottom:

```
 TopviewR @ host   Alt+1 [ btop ]  Alt+2 htop   Alt+3 nvtop        Esc: menu
```

- **Click** `btop`, `htop` or `nvtop` in the bar, or press **Alt+1**, **Alt+2**, **Alt+3** (with or without Shift, so AZERTY keyboards work too), to switch at once. Plain `1`, `2`, `3` stay with the tools (btop shows or hides its boxes, htop searches a PID).
- **Esc** opens the switch menu on top of any tool: `1` btop, `2` htop, `3` nvtop (or arrows + Enter, or the mouse), **Esc a second time** sends a real Esc to the current tool (closes btop's own Options/Help/Quit menus, a search in htop), `q` closes this menu and goes back to the tool, `x` closes the session.
- **Quitting a tool** (`q`, `F10`) shows a small list to pick another one.
- Inside a tool, the mouse keeps working as usual (btop and htop are clickable).

This layer is a locked-down tmux: every default tmux binding is removed (no prefix key, no command prompt, no new window or split), so it cannot open a shell; the only actions are starting one of the three tools and closing the session. `tests/test.sh` checks the binding list. Each browser tab gets its own tmux instance, destroyed when the tab closes. Set `BTOP_MENU=false` to start the tool directly, without the bar and the menu (old behavior).

## Login and password

The login lives in a `.env` file next to the compose file; the compose file only refers to it, so the password is never written in `docker-compose.yaml`.

```sh
# .env (never commit it, chmod 600)
BTOP_USER=admin
BTOP_PASS=change-me-at-least-12-chars   # openssl rand -base64 18
```

```yaml
# docker-compose.yaml
environment:
  BTOP_USER: ${BTOP_USER:-admin}
  BTOP_PASS: ${BTOP_PASS:?set BTOP_PASS in .env}
```

Docker Compose reads `.env` from the same folder by itself. Without `BTOP_PASS`, `docker compose up` refuses to start; with fewer than 12 characters, the container refuses to start. The browser then shows a standard login prompt (HTTP basic auth).

Legacy compose files that set `GOTTY_AUTH_USER` / `GOTTY_AUTH_PASS` directly in `environment:` keep working (see [migration](#migrating-from-big-bear-btop)).

## Security

**What is protected**

| Risk | Protection | Checked by |
|---|---|---|
| Killing host processes with the `k` key | btop runs as UID 10001 (`su-exec`), never root | `tests/test.sh`: `kill` on host PID 1 is refused |
| Password sniffed on the network | built-in TLS (`BTOP_TLS=auto`) | HTTPS test |
| Starting unprotected | refused without a password; 12 characters minimum | test |
| Malicious page opening the WebSocket | `ttyd -O` (origin checked) | test |
| Too many btop sessions | 3 clients max (`BTOP_MAX_CLIENTS`) | |
| Overpowered container | compose without `privileged`, `cap_drop: ALL` + 3 capabilities, `read_only`, `no-new-privileges` | |
| Known vulnerabilities in the image | Trivy scan on every build | `make scan` |
| Password read in `ps` by another host account | ttyd gets `-c TTYD_CREDENTIAL`; a small `LD_PRELOAD` shim (`ttyd-cred.c`) swaps in the value from ttyd's environment, readable only by root | test |

**Known limits**

- **Root on the host can still read the password** (`docker inspect`, the environment of ttyd), like any container secret, and so can members of the `docker` group. Use a dedicated password, never reused elsewhere.
- **No brute-force protection.** ttyd does not rate-limit attempts. Never expose the port to the Internet. For remote access use a VPN (WireGuard, Tailscale) or a reverse proxy with SSO plus `BTOP_AUTH_HEADER` (the port must then only be reachable by the proxy).
- ttyd itself runs as root (it reads the certificates and starts btop); only btop, the keyboard-driven part, is non-root. A small root `sh` stays between ttyd and the tool: without `CAP_KILL`, ttyd may not signal the non-root tool, but it can stop this `sh`, which ends the whole session when the tab closes.

## What btop sees (measured on 2026-11-04)

| View | `docker-compose.yaml` (hardened) | `docker-compose.legacy.yaml` (old compose) |
|---|---|---|
| CPU, memory, uptime | ✅ | ✅ |
| Host processes | ✅ (`pid: host`) | ✅ (`/proc` mounted) |
| Real host network | ✅ (`network_mode: host`) | ❌ only the container interface (172.17.x) |
| Host disks | ✅ via `/:/host:ro,rslave` | not checked |
| GPU | ✅ AMD and NVIDIA (see [GPU](#gpu-btop-and-nvtop)) | not tested |

## GPU (btop and nvtop)

Two images, same tools, scripts and hardening. Both start fine without a GPU: nvtop then says what to mount instead of crashing, and the startup header lists what it found.

| Image | Base | GPU | Size |
|---|---|---|---|
| `ghcr.io/erreur32/topviewr:latest` | Alpine (musl), amd64 + arm64 | AMD, Intel | ~31 MB |
| `ghcr.io/erreur32/topviewr:nvidia` | Debian 13 (glibc), amd64 | **NVIDIA**, AMD, Intel | ~155 MB |

NVIDIA needs its own image: btop and nvtop read NVIDIA GPUs through `libnvidia-ml`, which the NVIDIA container runtime mounts from the host driver. That library is built for glibc and crashes the tools on Alpine (musl).

**AMD or Intel** (either image): uncomment `devices: /dev/dri` in the compose file. On most hosts `/dev/dri/renderD*` belongs to the `render` group (mode 0660); the entrypoint runs the monitor with that group, so it can open the GPU while staying non-root.

**NVIDIA**: install the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) on the host (`docker info | grep -i runtimes` must list `nvidia`), then in the compose file:

```yaml
    image: ghcr.io/erreur32/topviewr:nvidia
    runtime: nvidia
```

The image already sets `NVIDIA_VISIBLE_DEVICES=all` and `NVIDIA_DRIVER_CAPABILITIES=utility` (usage, VRAM, temperatures, processes: all the tools need). Nothing else changes: same read-only, non-root, no-new-privileges setup.

Tested on 2026-11-10 with the hardened compose (non-root, read-only):

| GPU | btop | nvtop |
|---|---|---|
| AMD (amdgpu), Radeon 8060S | ✅ via `/sys` (integrated GPUs too, new in btop 1.4.8) | ✅ via libdrm: usage, clocks, VRAM, temperature, power, processes |
| NVIDIA (`:nvidia` image), RTX 3060 Ti, driver 550 | ✅ GPU meter | ✅ via NVML: usage, clocks, VRAM, temperature, fan, power, processes (other users' too) |
| Intel (i915 / xe) | partial: usage needs `perf` access, blocked for non-root when `kernel.perf_event_paranoid` > 2 (Debian default: 3) | ✅ via libdrm (not tested on hardware) |

- **Per-process GPU usage on AMD and Intel** is read from `/proc/<pid>/fdinfo`. As a non-root user, nvtop only sees it for processes it is allowed to inspect: global usage, VRAM and temperatures are shown, but GPU processes owned by root or by other users may be missing from the process list. That is the price of running non-root. NVIDIA reports processes through the driver, so they all show.
- The `:nvidia` image ships Debian's **htop 3.4.1** (Alpine: 3.5.3); btop, nvtop and ttyd are the same versions, built from source.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `BTOP_TOOL` | `btop` | monitor to run: `btop`, `htop` or `nvtop` |
| `BTOP_MENU` | `true` | bottom bar and Esc menu to switch tools; `false` starts `BTOP_TOOL` directly |
| `BTOP_USER` / `GOTTY_AUTH_USER` | `admin` | username |
| `BTOP_PASS` / `GOTTY_AUTH_PASS` | required | password (`BTOP_*` wins) |
| `BTOP_NO_AUTH=true` or `GOTTY_AUTH_ENABLED=false` | | disables auth (not recommended) |
| `BTOP_ALLOW_WEAK_PASS` | `false` | accepts fewer than 12 characters (tolerated with a warning for `GOTTY_AUTH_PASS`) |
| `BTOP_TLS` | `off` in the image, `auto` in the compose | `off`, `auto` (self-signed, generated in `/certs`), `on` (provide `/certs/cert.pem` and `key.pem`) |
| `BTOP_TLS_SAN` | | IPs and names added to the certificate, comma-separated |
| `BTOP_PORT` | `7681` | port |
| `BTOP_BIND` | all | listen IP or interface |
| `BTOP_UID` / `BTOP_GID` | `10001` / group of `/dev/dri/renderD*` if mounted, else `10001` | monitor user (chosen to match no host account) and group (the render group gives GPU access) |
| `BTOP_MAX_CLIENTS` | `3` | concurrent sessions |
| `BTOP_TITLE` | `TopviewR @ <hostname>` | browser tab title |
| `BTOP_FONT_SIZE` | `16` | font size |
| `BTOP_THEME` | `dark` | `light` for a light background |
| `BTOP_AUTH_HEADER` | | auth done by a reverse proxy (`ttyd -H`) |
| `BTOP_DEBUG` | `false` | `true` adds ttyd's notices to the logs (each connection, startup config); by default only errors and warnings |
| `BTOP_ARGS`, `TTYD_EXTRA_ARGS` | | extra btop and ttyd options |

btop config: `./config/btop.conf`, created on first start if missing (never overwritten). By default `use_fstab = false` and Docker's fake disks are filtered out, so the real host disks are shown.

## Migrating from big-bear-btop

First keep a copy of the old image if it is still cached:
```sh
docker image ls | grep big-bear && docker save bigbeartechworld/big-bear-btop -o big-bear-btop.tar
```

**Step 1: drop-in replacement** (nothing else changes). In your current compose file, only replace:
```yaml
image: ghcr.io/erreur32/topviewr:latest
```
then `docker compose up -d`. `GOTTY_*` variables keep working. See `docker-compose.legacy.yaml`.

**Step 2: switch to the hardened compose.** Copy `docker-compose.yaml` and `.env.example` next to the old one, fill in `.env` (`BTOP_CONTAINER_NAME` with your old container name, a new password, `BTOP_TLS_SAN`), move the old `.config/` folder to `config/`, then `docker compose up -d`. The URL becomes `https://`.

**Step 3:** re-enable automatic updates in your container manager.

**Rollback**: pin a previous dated tag (`image: ghcr.io/erreur32/topviewr:1.4.8-20261104`), or load the old image from the copy: `docker load -i big-bear-btop.tar`.

## Image tags

| Tag | What it is | When to use it |
|---|---|---|
| `latest` | last build of `main` | automatic updates (Watchtower, Dockhand...) |
| `v1.0.0` | a TopviewR release (see [CHANGELOG](CHANGELOG.md)) | pin a known version |
| `1.4.8` | last build shipping btop 1.4.8 | follow one btop version, still get Alpine fixes |
| `1.4.8-YYYYMMDD` | a dated weekly build | rollback |
| `nvidia`, `v1.4.0-nvidia`, `1.4.8-nvidia`, `1.4.8-YYYYMMDD-nvidia` | the same, Debian variant for NVIDIA GPUs (amd64) | NVIDIA hosts, see [GPU](#gpu-btop-and-nvtop) |

TopviewR has its own version (`v1.0.0`, `v1.1.0`...); the btop version it ships is in the `io.btop.version` image label and in the changelog.

## Build

```sh
make build    # local image topviewr:dev
make test     # build + end-to-end tests (needs Docker and python3)
make test-nvidia  # same for the Debian (NVIDIA) variant, topviewr:dev-nvidia
make scan     # Trivy
make buildx   # amd64 + arm64 without push (needs QEMU/binfmt for arm64)
scripts/dev.sh  # local test server from this tree (hardened compose, port 7682, logs in the foreground)
REGISTRY=ghcr.io/erreur32 make push
```

Bumping btop by hand: change `BTOP_VERSION` and `BTOP_SHA256` in `Dockerfile` and `Dockerfile.nvidia` (`curl -fsSL https://github.com/aristocratos/btop/archive/refs/tags/vX.Y.Z.tar.gz | sha256sum`).

## Automation (GitHub)

- `build.yml`: on every push, every PR and every Monday. Build, tests, Trivy, then multi-arch push to `ghcr.io/erreur32/topviewr` (and to the old name `ghcr.io/erreur32/btop-web` during the transition) with tags `latest`, `1.4.8` and `1.4.8-YYYYMMDD`.
- `btop-release.yml`: every Monday, opens a PR when a new btop release is out. PRs created with `GITHUB_TOKEN` do not trigger CI: close and reopen it, or run `build` by hand.
- `release.yml`: on each `vX.Y.Z` tag, creates the GitHub release with the matching CHANGELOG section; `build.yml` pushes the `vX.Y.Z` image tag at the same time.
- `codeql.yml`: CodeQL analysis of the workflows and the Python test client, on every push, every PR and every Monday.
- Dependabot: GitHub Actions and Alpine base image versions, plus security alerts and fixes.

## Credits and license

TopviewR's own files (scripts, compose files, Dockerfile, docs) are released under the [Apache License 2.0](LICENSE). The image bundles these unmodified third-party programs, each under its own license; their license texts are in the image under `/usr/local/share/licenses/` and in [`licenses/`](licenses/):

| Program | Version | License | Source code |
|---|---|---|---|
| [btop](https://github.com/aristocratos/btop) by aristocratos | 1.4.8 | Apache-2.0 | [v1.4.8 tarball](https://github.com/aristocratos/btop/archive/refs/tags/v1.4.8.tar.gz), built by the [Dockerfile](Dockerfile) |
| [htop](https://github.com/htop-dev/htop) by the htop authors | 3.5.3 | GPL-2.0-or-later | Alpine package, source in [Alpine aports](https://gitlab.alpinelinux.org/alpine/aports/-/tree/3.24-stable/main/htop) and [upstream 3.5.3](https://github.com/htop-dev/htop/tree/3.5.3) |
| [nvtop](https://github.com/Syllo/nvtop) by Maxime Schmitt | 3.3.2 | GPL-3.0-or-later | [3.3.2 tarball](https://github.com/Syllo/nvtop/archive/refs/tags/3.3.2.tar.gz) (sha256 in the Dockerfile), built unmodified by the [Dockerfile](Dockerfile) |
| [ttyd](https://github.com/tsl0922/ttyd) by Shuanglei Tao | 1.7.7 | MIT | Alpine package, [upstream 1.7.7](https://github.com/tsl0922/ttyd/tree/1.7.7) |
| [tmux](https://github.com/tmux/tmux) by Nicholas Marriott and contributors | 3.7c | ISC | Alpine package, [upstream](https://github.com/tmux/tmux) |

The other packages come from Alpine Linux 3.24 unchanged, under their own licenses. The TopviewR logo in `assets/` is original; btop, htop, nvtop and ttyd are the names of their own projects. The btop, htop and nvtop logos in `assets/apps/` are copied unmodified from their repositories (btop `Img/icon.svg`, htop `htop.svg`, nvtop `desktop/nvtop.svg`) and stay under their projects' licenses.
