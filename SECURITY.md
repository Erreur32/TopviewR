# Security policy

TopviewR puts a view of the host (processes, disks, network, GPU) in a browser tab, with keys that can signal processes: a flaw in it can matter. Thanks for reporting one privately.

## Reporting a vulnerability

Use **Report a vulnerability** in the [Security tab](https://github.com/Erreur32/TopviewR/security) of this repository. The report stays private until a fix is out. Please do not open a public issue or discussion for it.

Include what you can: the image tag, the compose file you use (without the password), the steps to reproduce and what an attacker gains.

## Supported versions

Only the latest release and the `latest` image get security fixes. The image is rebuilt every week for Alpine fixes.

## Scope notes

- TopviewR is meant for a LAN. ttyd has no brute-force protection: never expose the port to the Internet, use a VPN or a reverse proxy with SSO (`BTOP_AUTH_HEADER`).
- The monitor runs as UID 10001 and cannot signal host processes; ttyd itself runs as root to read the certificates.
- ttyd only accepts the password as a command-line argument; a small `LD_PRELOAD` shim (`ttyd-cred.c`) keeps it out of ttyd's command line, so it no longer shows in `ps` on the host nor in the process lists of btop and htop. Root on the host (or the `docker` group) can still read it, like any container secret. The password showing in any process command line **is** a vulnerability: please report it.
- The switch layer (tmux) has every default binding removed so it cannot open a shell. A way to reach a shell from the page **is** a vulnerability: please report it.
