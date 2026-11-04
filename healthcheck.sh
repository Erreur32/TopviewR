#!/bin/sh
# Healthy if ttyd answers: 200 (no auth) or 401 (auth enabled).
case "$(echo "${BTOP_TLS:-off}" | tr '[:upper:]' '[:lower:]')" in off|false|0) s=http ;; *) s=https ;; esac
h=127.0.0.1; case "${BTOP_BIND:-}" in *[0-9].*[0-9]) h="$BTOP_BIND" ;; esac
code="$(curl -sk -o /dev/null -m 4 -w '%{http_code}' "$s://$h:${BTOP_PORT:-7681}/")"
case "$code" in 200|401) exit 0 ;; *) echo "HTTP $code" >&2; exit 1 ;; esac
