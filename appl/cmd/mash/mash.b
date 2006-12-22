implement Mash;

#
#	mash - Inferno make/shell
#
#	Bruce Ellis - 1Q 98
#

include	"mash.m";
include	"mashparse.m";

#
#	mash consists of three modules plus library modules and loadable builtins.
#
#	This module, Mash, loads the other two (Mashparse and Mashlib), loads
#	the builtin "builtins", initializes things and calls the parser.
#
#	It has two entry points.  One is the traditional init() function and the other,
#	tkinit, is an interface to WmMash that allows the "tk" builtin to cooperate
#	with the command window.
#

Mash: module
{
	tkinit:	fn(ctxt: ref Draw->Context, top: ref Tk->Toplevel, args: list of string);
	init:		fn(ctxt: ref Draw->Context, args: list of string);
};

Iobuf:	import Bufio;

sys:		Sys;
lib:		Mashlib;
parse:	Mashparse;

Env, Stab:	import lib;

cmd:		string;

#
#	Check for /dev/console.
#
isconsole(fd: ref Sys->FD): int
{
	(ok1, d1) := sys->fstat(fd);
	(ok2, d2) := sys->stat(lib->CONSOLE);
	if (ok1 < 0 || ok2 < 0)
		return 0;
	return d1.dtype == d2.dtype && d1.qid.path == d2.qid.path;
}

usage(e: ref Env)
{
	sys->fprint(e.stderr, "usage: mash [-denx] [-c command] [src [args]]\n");
	lib->exits("usage");
}

flags(e: ref Env, l: list of string): list of string
{
	while (l != nil && len hd l && (s := hd l)[0] == '-') {
		l = tl l;
		if (s == "--")
			break;
		n := len s;
		for (i := 1; i < n; i++) {
			case s[i] {
			'c' =>
				if (++i < n) {
					if (l != nil)
						usage(e);
					cmd = s[i:];
				} else {
					if (len l != 1)
						usage(e);
					cmd = hd l;
				}
				return nil;
			'd' =>
				e.flags |= lib->EDumping;
			'e' =>
				e.flags |= lib->ERaise;
			'n' =>
				e.flags |= lib->ENoxeq;
			'x' =>
				e.flags |= lib->EEcho;
			* =>
				usage(e);
			}
		}
	}
	return l;
}

tkinit(ctxt: ref Draw->Context, top: ref Tk->Toplevel, args: list of string)
{
	fd: ref Sys->FD;
	sys = load Sys Sys->PATH;
	stderr := sys->fildes(2);
	lib = load Mashlib Mashlib->PATH;
	if (lib == nil) {
		sys->fprint(stderr, "could not load %s: %r\n", Mashlib->PATH);
		exit;
	}
	parse = load Mashparse Mashparse->PATH;
	if (parse == nil) {
		sys->fprint(stderr, "could not load %s: %r\n", Mashparse->PATH);
		exit;
	}
	e := Env.new();
	e.stderr = stderr;
	stderr = nil;
	lib->initmash(ctxt, top, sys, e, lib, parse);
	parse->init(lib);
	boot := args == nil;
	if (!boot)
		args = flags(e, tl args);
	e.doload(lib->LIB + lib->BUILTINS);
	lib->prompt = "mash% ";
	lib->contin = "\t";
	if (cmd == nil && args == nil && !boot) {
		e.global.assign(lib->MASHINIT, "true" :: nil);
		fd = sys->open(lib->PROFILE, Sys->OREAD);
		if (fd != nil) {
			e.fopen(fd, lib->PROFILE);
			parse->parse(e);
			fd = nil;
		}
	}
	e.global.assign(lib->MASHINIT, nil);
	if (cmd == nil) {
		if (args != nil) {
			s := hd args;
			args = tl args;
			fd = sys->open(s, Sys->OREAD);
			if (fd == nil)
				e.couldnot("open", s);
			e.fopen(fd, s);
			e.global.assign(lib->ARGS, args);
		}
		if (fd == nil) {
			fd = sys->fildes(0);
			if (isconsole(fd))
				e.interactive(fd);
			e.fopen(fd, "<stdin>");
			fd = nil;
		}
	} else
		e.sopen(cmd);
	parse->parse(e);
}

init(ctxt: ref Draw->Context, args: list of string)
{
	tkinit(ctxt, nil, args);
}
