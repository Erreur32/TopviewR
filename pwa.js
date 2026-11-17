// TopviewR PWA: ttyd serves a single page and nothing else, so the manifest and the PNG icons are built here.
// Icon: ?icon=logo|btop|htop|nvtop in the URL (each bookmark or installed app can have its own), else BTOP_ICON.
(function () {
	var ICONS = {/*ICONS*/};
	// replaced at start by BTOP_ICON (entrypoint.sh)
	var DEFAULT = "logo";
	var NAMES = { logo: "TopviewR", btop: "btop", htop: "htop", nvtop: "nvtop" };
	var q = new URLSearchParams(location.search).get("icon");
	var key = ICONS[q] ? q : (ICONS[DEFAULT] ? DEFAULT : "logo");
	function link(rel, href, extra) {
		var l = document.querySelector('link[rel="' + rel + '"]') || document.head.appendChild(document.createElement("link"));
		l.rel = rel; l.href = href;
		for (var a in extra || {}) l.setAttribute(a, extra[a]);
	}
	link("icon", ICONS[key], { type: "image/svg+xml" });
	var img = new Image();
	img.onload = function () {
		// the logo already has its own background; the tool icons are transparent: dark square behind, small margin
		function png(size) {
			var c = document.createElement("canvas"), x = c.getContext("2d");
			c.width = c.height = size;
			if (key === "logo") { x.drawImage(img, 0, 0, size, size); return c.toDataURL("image/png"); }
			x.fillStyle = "#0F172A"; x.fillRect(0, 0, size, size);
			var m = size * 0.14; x.drawImage(img, m, m, size - 2 * m, size - 2 * m);
			return c.toDataURL("image/png");
		}
		var name = (NAMES[key] || "TopviewR") + " @ " + location.hostname;
		var start = location.origin + location.pathname + "?icon=" + key;
		var manifest = {
			name: name, short_name: key === "logo" ? "TopviewR" : NAMES[key],
			start_url: start, scope: location.origin + "/", display: "standalone",
			background_color: "#0F172A", theme_color: "#0F172A",
			icons: [
				{ src: png(192), sizes: "192x192", type: "image/png", purpose: "any" },
				{ src: png(512), sizes: "512x512", type: "image/png", purpose: "any" }
			]
		};
		link("apple-touch-icon", png(180));
		link("manifest", URL.createObjectURL(new Blob([JSON.stringify(manifest)], { type: "application/manifest+json" })));
	};
	img.src = ICONS[key];
})();
