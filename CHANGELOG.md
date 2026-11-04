# Changelog

All notable changes to btop-web are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
btop-web has its own version; the btop version it ships is listed in each entry.

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
