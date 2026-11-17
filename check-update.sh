#!/bin/sh
# Writes the latest TopviewR release to $2 if it is newer than the running version $1.
# One HTTPS request to the public GitHub API, no token and no personal data; offline or
# rate-limited requests are ignored. Called once at container start (see entrypoint.sh).
set -eu

version="${1:-}"
out="${2:-/tmp/.topviewr-update}"

# The menu reads this file: clear it first so a stale value is never shown.
: > "$out" 2>/dev/null || exit 0
case "$version" in ''|*[!0-9.]*) exit 0 ;; esac

latest="$(curl -fsSL --connect-timeout 2 --max-time 3 \
	-H 'Accept: application/vnd.github+json' \
	-H "User-Agent: TopviewR/$version" \
	https://api.github.com/repos/Erreur32/TopViewR/releases/latest 2>/dev/null \
	| sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
latest="${latest#v}"
case "$latest" in ''|*[!0-9.]*) exit 0 ;; esac
[ "$latest" != "$version" ] || exit 0

# sort -V is in busybox (Alpine) and coreutils (Debian)
newest="$(printf '%s\n%s\n' "$version" "$latest" | sort -V | tail -1)"
if [ "$newest" = "$latest" ]; then
	printf '%s\n' "$latest" > "$out" 2>/dev/null || true
fi
exit 0
