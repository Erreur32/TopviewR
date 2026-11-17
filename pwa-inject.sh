#!/bin/sh
# Build step: puts the PWA script (pwa.js + the four SVG icons) into ttyd's page. Usage: pwa-inject.sh index.html
# Expects /tmp/pwa.js, /tmp/logo.svg and /tmp/apps/{btop,htop,nvtop}.svg; fails if the page has no </head>.
set -eu
page="$1"
icons="logo:\"data:image/svg+xml;base64,$(base64 -w0 /tmp/logo.svg)\""
for t in btop htop nvtop; do
  icons="$icons,$t:\"data:image/svg+xml;base64,$(base64 -w0 "/tmp/apps/$t.svg")\""
done
# one line without comments (the page itself is a single 700 KB line, so sed does the insertion), escaped for sed
js="$(sed -e '/^[[:space:]]*\/\//d' -e "s|/\*ICONS\*/|$icons|" /tmp/pwa.js | tr '\n\t' '  ' | sed -e 's/[\\&|]/\\&/g')"
sed -i "s|</head>|<script>$js</script></head>|" "$page"
grep -q 'URL.createObjectURL' "$page"
