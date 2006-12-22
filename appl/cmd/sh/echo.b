implement Shellbuiltin;

include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Listnode, Context: import sh;
	myself: Shellbuiltin;

initbuiltin(ctxt: ref Context, shmod: Sh): string
{
	sys = load Sys Sys->PATH;
	sh = shmod;
	myself = load Shellbuiltin "$self";
	if (myself == nil)
		ctxt.fail("bad module", sys->sprint("echo: cannot load self: %r"));
	ctxt.addbuiltin("echo", myself);
	return nil;
}

whatis(nil: ref Sh->Context, nil: Sh, nil: string, nil: int): string
{
	return nil;
}

getself(): Shellbuiltin
{
	return myself;
}

runbuiltin(ctxt: ref Context, nil: Sh,
			argv: list of ref Listnode, last: int): string
{
	case (hd argv).word {
	"echo" =>
		return builtin_echo(ctxt, argv, last);
	}
	return nil;
}

runsbuiltin(nil: ref Sh->Context, nil: Sh,
			nil: list of ref Listnode): list of ref Listnode
{
	return nil;
}

argusage(ctxt: ref Context)
{
	ctxt.fail("usage", "usage: arg [opts {command}]... - args");
}

# converted from /appl/cmd/echo.b.
# should have exactly the same semantics.
builtin_echo(nil: ref Context, argv: list of ref Listnode, nil: int): string
{
	argv = tl argv;
	nonewline := 0;
	if (len argv > 0) {
		w := (hd argv).word;
		if (w == "-n" || w == "--") {
			nonewline = (w == "-n");
			argv = tl argv;
		}
	}
	s := "";
	if (argv != nil) {
		s = word(hd argv);
		for (argv = tl argv; argv != nil; argv = tl argv)
			s += " " + word(hd argv);
	}
	if (nonewline == 0) 
		s[len s] = '\n';
	{
		a := array of byte s;
		if (sys->write(sys->fildes(1), a, len a) != len a) {
			sys->fprint(sys->fildes(2), "echo: write error: %r\n");
			return "write error";
		}
		return nil;
	}
	exception{
		"write on closed pipe" =>
			sys->fprint(sys->fildes(2), "echo: write error: write on closed pipe\n");
			return "write error";
	}
}

word(n: ref Listnode): string
{
	if (n.word != nil)
		return n.word;
	if (n.cmd != nil)
		n.word = sh->cmd2string(n.cmd);
	return n.word;
}
