implement Shellbuiltin;

include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Listnode, Context: import sh;
	myself: Shellbuiltin;
include "itslib.m";
	itslib: Itslib;
	Tconfig, S_INFO, S_WARN, S_ERROR, S_FATAL: import itslib;

tconf: ref Tconfig;

initbuiltin(ctxt: ref Context, shmod: Sh): string
{
	sys = load Sys Sys->PATH;
	itslib = load Itslib Itslib->PATH;
	if (itslib != nil)
		tconf = itslib->init();
	sh = shmod;
	myself = load Shellbuiltin "$self";
	if (myself == nil)
		ctxt.fail("bad module", sys->sprint("its: cannot load self: %r"));
	ctxt.addbuiltin("report", myself);
	return nil;
}

getself(): Shellbuiltin
{
	return myself;
}


whatis(nil: ref Sh->Context, nil: Sh, nil: string, nil: int): string
{
	return nil;
}



runbuiltin(ctxt: ref Sh->Context, nil: Sh,
			cmd: list of ref Sh->Listnode, nil: int): string
{
	case (hd cmd).word {
	"report" =>
		if (len cmd < 4)
			rusage(ctxt);
		cmd = tl cmd;
		sevstr := (hd cmd).word;
		sev := sevtran(sevstr);
		if (sev < 0)
			rusage(ctxt);
		cmd = tl cmd;
		verb := (hd cmd).word;
		cmd = tl cmd;
		mtext := "";
		i := 0;
		while (len cmd) {
			msg :=  (hd cmd).word;
			cmd = tl cmd;
			if (i++ > 0)
				mtext = mtext + " ";
			mtext = mtext + msg;
		}
		if (tconf != nil)
			tconf.report(int sev, int verb, mtext);
		else
			sys->fprint(sys->fildes(2), "[itslib missing] %s %s\n", sevstr, mtext);
	}
	return nil;
}


runsbuiltin(nil: ref Sh->Context, nil: Sh,
			nil: list of ref Sh->Listnode): list of ref Listnode
{
	return nil;
}


sevtran(sname: string): int
{
	SEVMAP :=  array[] of {"INF", "WRN", "ERR", "FTL"};
	for (i:=0; i<len SEVMAP; i++)
		if (sname == SEVMAP[i])
			return i;
	return -1;
}

rusage(ctxt: ref Context)
{
	ctxt.fail("usage", "usage: report INF|WRN|ERR|FTL verbosity message[...]");
}

