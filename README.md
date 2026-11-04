# btop-web, btop in your browser

<div align="center">

<img src="assets/logo.svg" alt="btop" width="341" height="90" />

[![Release](https://img.shields.io/github/v/release/Erreur32/btop-web?style=for-the-badge&logo=github&logoColor=white&label=Release&color=111827)](https://github.com/Erreur32/btop-web/releases)
[![Build](https://img.shields.io/github/actions/workflow/status/Erreur32/btop-web/build.yml?branch=main&style=for-the-badge&logo=github&logoColor=white&label=Build&color=111827)](https://github.com/Erreur32/btop-web/actions/workflows/build.yml)
[![Docker](https://img.shields.io/badge/Docker-ghcr.io-1f2937?style=for-the-badge&logo=docker&logoColor=38bdf8)](https://github.com/Erreur32/btop-web/pkgs/container/btop-web)
![Arch](https://img.shields.io/badge/arch-amd64_|_arm64-111827?style=for-the-badge&logo=linux&logoColor=white)
![btop](https://img.shields.io/badge/btop-1.4.8-111827?style=for-the-badge&logoColor=white)
![ttyd](https://img.shields.io/badge/ttyd-1.7.7-111827?style=for-the-badge&logoColor=white)
![Alpine](https://img.shields.io/badge/Alpine-3.24-111827?style=for-the-badge&logo=alpinelinux&logoColor=0d597f)
![Trivy](https://img.shields.io/badge/Trivy-scanned-111827?style=for-the-badge&logo=aqua&logoColor=1904da)
[![License](https://img.shields.io/badge/License-Apache_2.0-111827?style=for-the-badge&color=111827&labelColor=111827&logoColor=white)](LICENSE)

**[btop](https://github.com/aristocratos/btop) in a browser tab, served by [ttyd](https://github.com/tsl0922/ttyd), hardened for LAN use. Drop-in replacement for the removed `big-bear-btop` image.**

[Why](#why-btop-web-exists) | [Quick start](#quick-start) | [Login](#login-and-password) | [Security](#security) | [Variables](#variables) | [Migration](#migrating-from-big-bear-btop) | [Image tags](#image-tags) | [Changelog](CHANGELOG.md)

</div>

```sh
docker pull ghcr.io/erreur32/btop-web:latest
```

## Why btop-web exists

Many homelab setups used `bigbeartechworld/big-bear-btop` to show btop in a browser tab. That image is gone:

- **It was removed from Docker Hub.** The repository returns 404 and the registry 401, so existing servers can no longer pull or update it, and container managers (Dockhand, Watchtower, Portainer...) report `[Registry] ... 401` errors.
- **It was built on GoTTY**, which has been unmaintained since 2024.
- **It ran everything as root in a `privileged` container.** Anyone who could open the page could press `k` in btop and kill any process on the host (dockerd, sshd...).
- **It shipped an old btop** that was never updated.

btop-web is a maintained replacement: same use case and same compose variables, but a current btop, an actively developed web terminal and safer defaults.

## What you get

- **btop 1.4.8** compiled from source (checksum verified, GPU support enabled), on **Alpine 3.24**, served by **ttyd 1.7.7**. The image is about 31 MB.
- **Rebuilt every week** for Alpine security fixes, with a Trivy scan on every build (0 known vulnerabilities on 2026-11-04).
- **Automatic btop updates**: a weekly job opens a PR when a new btop release is out.
- **Multi-arch** images: `linux/amd64` and `linux/arm64`.
- **Drop-in compatible**: the old `GOTTY_AUTH_*` variables still work.

## What changes compared to big-bear-btop

| | big-bear-btop | btop-web |
|---|---|---|
| Image | `bigbeartechworld/big-bear-btop` (gone) | `ghcr.io/erreur32/btop-web` |
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

**Known limits**

- **The password is visible in `ps` on the host**, and in btop's own process list (ttyd command line). ttyd only accepts credentials as an argument. Anyone with a shell on the server can read it: use a dedicated password, never reused elsewhere.
- **No brute-force protection.** ttyd does not rate-limit attempts. Never expose the port to the Internet. For remote access use a VPN (WireGuard, Tailscale) or a reverse proxy with SSO plus `BTOP_AUTH_HEADER` (the port must then only be reachable by the proxy).
- ttyd itself runs as root (it reads the certificates and starts btop); only btop, the keyboard-driven part, is non-root.

## What btop sees (measured on 2026-11-04)

| View | `docker-compose.yaml` (hardened) | `docker-compose.legacy.yaml` (old compose) |
|---|---|---|
| CPU, memory, uptime | ✅ | ✅ |
| Host processes | ✅ (`pid: host`) | ✅ (`/proc` mounted) |
| Real host network | ✅ (`network_mode: host`) | ❌ only the container interface (172.17.x) |
| Host disks | ✅ via `/:/host:ro,rslave` | not checked |
| GPU | not tested (test machine has no GPU) | not tested |

GPU: uncomment `devices: /dev/dri` for Intel or AMD. Integrated AMD GPUs are read through `/sys` (new in btop 1.4.8). NVIDIA will probably not work: `libnvidia-ml` is built for glibc and the image uses musl.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `BTOP_USER` / `GOTTY_AUTH_USER` | `admin` | username |
| `BTOP_PASS` / `GOTTY_AUTH_PASS` | required | password (`BTOP_*` wins) |
| `BTOP_NO_AUTH=true` or `GOTTY_AUTH_ENABLED=false` | | disables auth (not recommended) |
| `BTOP_ALLOW_WEAK_PASS` | `false` | accepts fewer than 12 characters (tolerated with a warning for `GOTTY_AUTH_PASS`) |
| `BTOP_TLS` | `off` in the image, `auto` in the compose | `off`, `auto` (self-signed, generated in `/certs`), `on` (provide `/certs/cert.pem` and `key.pem`) |
| `BTOP_TLS_SAN` | | IPs and names added to the certificate, comma-separated |
| `BTOP_PORT` | `7681` | port |
| `BTOP_BIND` | all | listen IP or interface |
| `BTOP_UID` / `BTOP_GID` | `10001` | btop user (chosen to match no host account) |
| `BTOP_MAX_CLIENTS` | `3` | concurrent sessions |
| `BTOP_TITLE` | `btop @ <hostname>` | browser tab title |
| `BTOP_FONT_SIZE` | `14` | font size |
| `BTOP_THEME` | `dark` | `light` for a light background |
| `BTOP_AUTH_HEADER` | | auth done by a reverse proxy (`ttyd -H`) |
| `BTOP_ARGS`, `TTYD_EXTRA_ARGS` | | extra btop and ttyd options |

btop config: `./config/btop.conf`, created on first start if missing (never overwritten). By default `use_fstab = false` and Docker's fake disks are filtered out, so the real host disks are shown.

## Migrating from big-bear-btop

First keep a copy of the old image if it is still cached:
```sh
docker image ls | grep big-bear && docker save bigbeartechworld/big-bear-btop -o big-bear-btop.tar
```

**Step 1: drop-in replacement** (nothing else changes). In your current compose file, only replace:
```yaml
image: ghcr.io/erreur32/btop-web:latest
```
then `docker compose up -d`. `GOTTY_*` variables keep working. See `docker-compose.legacy.yaml`.

**Step 2: switch to the hardened compose.** Copy `docker-compose.yaml` and `.env.example` next to the old one, fill in `.env` (`BTOP_CONTAINER_NAME` with your old container name, a new password, `BTOP_TLS_SAN`), move the old `.config/` folder to `config/`, then `docker compose up -d`. The URL becomes `https://`.

**Step 3:** re-enable automatic updates in your container manager.

**Rollback**: pin a previous dated tag (`image: ghcr.io/erreur32/btop-web:1.4.8-20261104`), or load the old image from the copy: `docker load -i big-bear-btop.tar`.

## Image tags

| Tag | What it is | When to use it |
|---|---|---|
| `latest` | last build of `main` | automatic updates (Watchtower, Dockhand...) |
| `v1.0.0` | a btop-web release (see [CHANGELOG](CHANGELOG.md)) | pin a known version |
| `1.4.8` | last build shipping btop 1.4.8 | follow one btop version, still get Alpine fixes |
| `1.4.8-YYYYMMDD` | a dated weekly build | rollback |

btop-web has its own version (`v1.0.0`, `v1.1.0`...); the btop version it ships is in the `io.btop.version` image label and in the changelog.

## Build

```sh
make build    # local image btop-web:dev
make test     # build + end-to-end tests (needs Docker and python3)
make scan     # Trivy
make buildx   # amd64 + arm64 without push (needs QEMU/binfmt for arm64)
scripts/dev.sh  # local test server from this tree (hardened compose, port 7682, logs in the foreground)
REGISTRY=ghcr.io/erreur32 make push
```

Bumping btop by hand: change `BTOP_VERSION` and `BTOP_SHA256` in the `Dockerfile` (`curl -fsSL https://github.com/aristocratos/btop/archive/refs/tags/vX.Y.Z.tar.gz | sha256sum`).

## Automation (GitHub)

- `build.yml`: on every push, every PR and every Monday. Build, tests, Trivy, then multi-arch push to `ghcr.io/erreur32/btop-web` with tags `latest`, `1.4.8` and `1.4.8-YYYYMMDD`.
- `btop-release.yml`: every Monday, opens a PR when a new btop release is out. PRs created with `GITHUB_TOKEN` do not trigger CI: close and reopen it, or run `build` by hand.
- `release.yml`: on each `vX.Y.Z` tag, creates the GitHub release with the matching CHANGELOG section; `build.yml` pushes the `vX.Y.Z` image tag at the same time.
- Dependabot: GitHub Actions and Alpine base image versions.

## Credits and license

- [btop](https://github.com/aristocratos/btop) by aristocratos (Apache-2.0), logo in `assets/` from the btop repository.
- [ttyd](https://github.com/tsl0922/ttyd) by tsl0922 (MIT).
- btop-web is released under the [Apache License 2.0](LICENSE).
