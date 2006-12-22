implement Itslib;

include "sys.m";
	sys: Sys;
include "itslib.m";
include "env.m";
	env: Env;


init(): ref Tconfig
{
	sys = load Sys Sys->PATH;
	tc := ref Tconfig(-1, sys->fildes(2));
	env = load Env Env->PATH;
	if (env == nil)
		sys->fprint(sys->fildes(2), "Failed to load %s\n", Env->PATH);
	else {
		vstr := env->getenv(ENV_VERBOSITY);
		mstr := env->getenv(ENV_MFD);
		if (vstr != nil && mstr != nil) {
			tc.verbosity = int vstr;
			tc.mfd = sys->fildes(int mstr);
		}
	}
	if (tc.verbosity >= 0)
		tc.report(S_STIME, 0, sys->sprint("%d", sys->millisec()));
	else 
		sys->fprint(sys->fildes(2), "Test is running standalone\n");
	return tc;
}

Tconfig.report(tc: self ref Tconfig, sev: int, verb: int, msg: string)
{
	if (sev < 0 || sev > S_ETIME) {
		sys->fprint(sys->fildes(2), "Tconfig.report: Bad severity code: %d\n", sev);
		sev = 0;
	}
	if (tc.mfd != nil && sys->fprint(tc.mfd, "%d%d%s\n", sev, verb, msg) <=0)
		tc.mfd = nil;		# Master test process was probably killed
}

Tconfig.done(tc: self ref Tconfig)
{
	tc.report(S_ETIME, 0, sys->sprint("%d", sys->millisec()));
}
