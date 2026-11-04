# Changelog

All notable changes to TopviewR (named btop-web up to 1.0.0) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
TopviewR has its own version; the btop version it ships is listed in each entry.

## [1.1.0] - 2026-11-05

Renamed from btop-web to **TopviewR**. Ships **btop 1.4.8**, **htop 3.5.3**, **nvtop 3.3.2** and **ttyd 1.7.7** on **Alpine 3.24**, for `linux/amd64` and `linux/arm64`.

### Added

- **htop and nvtop**: `BTOP_TOOL=htop` or `BTOP_TOOL=nvtop` runs htop 3.5.3 or nvtop 3.3.2 instead of btop, with the same login, TLS and non-root protection. nvtop is compiled from source (checksum verified), it is not in Alpine stable. Their settings are saved in the config volume (`htop/`, `nvtop/`).
- **Switch tools from the browser**: a bottom bar with clickable `btop`, `htop`, `nvtop`, and `Esc` opens a switch menu on top of any tool (`m` still sends Esc to the tool, so btop's own menu stays reachable). Built on a locked-down tmux with every default binding removed: it cannot open a shell. `BTOP_MENU=false` keeps the old behavior.
- **Passwords removed from the tools environment**: htop's environment view could show `BTOP_PASS`.
- **Third-party licenses in the image**: license texts of btop, htop, nvtop and ttyd in `/usr/local/share/licenses/`, sources and licenses listed in the README; the image license label now reads `Apache-2.0 AND GPL-2.0-or-later AND GPL-3.0-or-later AND MIT AND ISC`.
- **GPU access for the non-root monitor**: when `/dev/dri/renderD*` is mounted, the monitor runs with its group (usually `render`) unless `BTOP_GID` is set.
- **TopviewR logo, favicon and page title**: the browser tab shows the TopviewR icon; the page is ttyd's own, taken from the installed ttyd at build time so it always matches its version. The default tab title is `TopviewR @ <hostname>`.
- **htop Black Night theme by default**: until another theme is picked in htop (F2, Colors), it is then saved in the config volume.

### Changed

- **Renamed to TopviewR**: the repository is now `Erreur32/TopviewR` (the old address redirects) and the image `ghcr.io/erreur32/topviewr`. The old image name `ghcr.io/erreur32/btop-web` still gets the same builds for now: only the `image:` line has to change, all `BTOP_*` variables stay the same.
- **Bigger text**: default font size is now 16 (`BTOP_FONT_SIZE`).

### Fixed

- **btop settings when another tool is the default**: `btop.conf` is created whatever `BTOP_TOOL` is, since the menu can start btop from htop or nvtop.

## [1.0.0] - 2026-11-04

First release. Ships **btop 1.4.8** and **ttyd 1.7.7** on **Alpine 3.24**, for `linux/amd64` and `linux/arm64`.

### Added

- **btop in the browser**: btop compiled from source (checksum verified, GPU support), served by ttyd.
- **Drop-in replacement for `bigbeartechworld/big-bear-btop`**: the old `GOTTY_AUTH_*` variables still work, so only the `image:` line of an existing compose file changes.
- **Hardened defaults**: btop runs as UID 10001 and cannot signal host processes, a password of at least 12 characters is required, WebSocket origin is checked, 3 sessions max.
- **Built-in HTTPS**: `BTOP_TLS=auto` generates a self-signed certificate kept in `/certs`.
- **Hardened compose** (`docker-compose.yaml`): no `privileged`, `cap_drop: ALL` plus 3 capabilities, read-only root filesystem, real host network and disks.
- **Local test server**: `scripts/dev.sh` builds the tree and runs it on port 7682 with the logs in the foreground.
- **Automation**: weekly rebuild with a Trivy scan, a PR when a new btop release is out, Dependabot, GitHub release on each tag.

### Fixed

- **arm64 build**: btop only compiles its Intel GPU sources on x86_64; they are now enabled on every architecture so the link no longer fails.
- **Zombie processes**: with `pid: host` tini is not PID 1; `TINI_SUBREAPER=1` lets it reap them (and removes the startup warning).
