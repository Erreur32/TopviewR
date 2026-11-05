// LD_PRELOAD shim for ttyd: ttyd only takes the credential as `-c user:pass`, readable by any host account in `ps`
// (/proc/<pid>/cmdline is world-readable, /proc/<pid>/environ is not). entrypoint.sh passes `-c TTYD_CREDENTIAL`
// and the real value in that variable; this hands it to ttyd when getopt_long returns 'c'.
// The placeholder must differ from the command ttyd runs (`env`): ttyd finds where it starts by name.
// Without the shim, ttyd refuses the placeholder (no ':'), so it fails closed.
// It also hides ttyd's startup line `credential: <base64 of user:pass>` (printed at notice level, BTOP_DEBUG=true).
#define _GNU_SOURCE
#include <dlfcn.h>
#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int getopt_long(int argc, char *const argv[], const char *optstring, const struct option *longopts, int *longindex) {
	static __typeof__(getopt_long) *real;
	static char *cred;
	if (!real) {
		real = dlsym(RTLD_NEXT, "getopt_long");
		if (!real) abort();
		const char *c = getenv("TTYD_CREDENTIAL");
		if (c) cred = strdup(c);
		// keep both out of the environment ttyd passes to the tools
		unsetenv("TTYD_CREDENTIAL");
		unsetenv("LD_PRELOAD");
	}
	int r = real(argc, argv, optstring, longopts, longindex);
	if (r == 'c' && cred) optarg = cred;
	return r;
}

typedef void (*emit_fn)(int level, const char *line);
static emit_fn next_emit;

static void redacting_emit(int level, const char *line) {
	const char *p = strstr(line, "credential:");
	if (!p) return next_emit(level, line);
	char buf[256]; // keeps the "[timestamp] N:" prefix
	snprintf(buf, sizeof buf, "%.*scredential: (hidden by TopviewR)\n", p - line < 200 ? (int)(p - line) : 0, line);
	next_emit(level, buf);
}

// libwebsockets: ttyd calls it once, with NULL (keep the stderr emitter), right before printing its configuration
void lws_set_log_level(int level, emit_fn func) {
	static void (*real)(int, emit_fn);
	if (!real) {
		real = (void (*)(int, emit_fn))dlsym(RTLD_NEXT, "lws_set_log_level");
		next_emit = (emit_fn)dlsym(RTLD_NEXT, "lwsl_emit_stderr");
		if (!real || !next_emit) abort();
	}
	if (func) next_emit = func;
	real(level, redacting_emit);
}
