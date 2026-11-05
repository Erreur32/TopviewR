// LD_PRELOAD shim for ttyd: ttyd only takes the credential as `-c user:pass`, readable by any host account in `ps`
// (/proc/<pid>/cmdline is world-readable, /proc/<pid>/environ is not). entrypoint.sh passes `-c TTYD_CREDENTIAL`
// and the real value in that variable; this hands it to ttyd when getopt_long returns 'c'.
// The placeholder must differ from the command ttyd runs (`env`): ttyd finds where it starts by name.
// Without the shim, ttyd refuses the placeholder (no ':'), so it fails closed.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <getopt.h>
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
