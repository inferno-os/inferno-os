implement Mashbuiltin;

#
#	"builtins" builtin, defines:
#
#	env	- print environment or individual elements
#	eval	- interpret arguments as mash input
#	exit	- exit toplevel, eval or subshell
#	load	- load a builtin
#	prompt	- print or set prompt
#	quote	- print arguments quoted as input for mash
#	run	- interpret a file as mash input
#	status	- report existence of error output
#	time	- time the execution of a command
#	whatis	- print variable, function and builtin
#

include	"mash.m";
include	"mashparse.m";

mashlib:	Mashlib;

Cmd, Env, Stab:	import mashlib;
sys, bufio:	import mashlib;

Iobuf:	import bufio;

#
#	Interface to catch the use as a command.
#
init(nil: ref Draw->Context, nil: list of string)
{
	ssys := load Sys Sys->PATH;
	ssys->fprint(ssys->fildes(2), "builtins: cannot run as a command\n");
	raise "fail: error";
}

#
#	Used by whatis.
#
name(): string
{
	return "builtins";
}

#
#	Install commands.
#
mashinit(nil: list of string, lib: Mashlib, this: Mashbuiltin, e: ref Env)
{
	mashlib = lib;
	e.defbuiltin("env", this);
	e.defbuiltin("eval", this);
	e.defbuiltin("exit", this);
	e.defbuiltin("load", this);
	e.defbuiltin("prompt", this);
	e.defbuiltin("quote", this);
	e.defbuiltin("run", this);
	e.defbuiltin("status", this);
	e.defbuiltin("time", this);
	e.defbuiltin("whatis", this);
}

#
#	Execute a builtin.
#
mashcmd(e: ref Env, l: list of string)
{
	case hd l {
	"env" =>
		l = tl l;
		if (l == nil) {
			out := e.outfile();
			if (out == nil)
				return;
			prsymbs(out, e.global, "=");
			prsymbs(out, e.local, ":=");
			out.close();
		} else
			e.usage("env");
	"eval" =>
		eval(e, tl l);
	"exit" =>
		raise mashlib->EXIT;
	"load" =>
		l = tl l;
		if (len l == 1)
			e.doload(hd l);
		else
			e.usage("load file");
	"prompt" =>
		l = tl l;
		case len l {
		0 =>
			mashlib->prprompt(0);
		1 =>
			mashlib->prompt = hd l;
		2 =>
			mashlib->prompt = hd l;
			mashlib->contin = hd tl l;
		* =>
			e.usage("prompt [string]");
		}
	"quote" =>
		l = tl l;
		if (l != nil) {
			out := e.outfile();
			if (out == nil)
				return;
			f := 0;
			while (l != nil) {
				if (f)
					out.putc(' ');
				else
					f = 1;
				out.puts(mashlib->quote(hd l));
				l = tl l;
			}
			out.putc('\n');
			out.close();
		}
	"run" =>
		if (!run(e, tl l))
			e.usage("run [-] [-denx] file [arg ...]");
	"status" =>
		l = tl l;
		if (l != nil)
			status(e, l);
		else
			e.usage("status cmd [arg ...]");
	"time" =>
		l = tl l;
		if (l != nil)
			time(e, l);
		else
			e.usage("time cmd [arg ...]");
	"whatis" =>
		l = tl l;
		if (l != nil) {
			out := e.outfile();
			if (out == nil)
				return;
			while (l != nil) {
				whatis(e, out, hd l);
				l = tl l;
			}
			out.close();
		}
	}
}

#
#	Print a variable and its value.
#
prone(out: ref Iobuf, eq, s: string, v: list of string)
{
	out.puts(s);
	out.putc(' ');
	out.puts(eq);
	if (v != mashlib->empty) {
		do {
			out.putc(' ');
			out.puts(mashlib->quote(hd v));
			v = tl v;
		} while (v != nil);
	}
	out.puts(";\n");
}

#
#	Print the contents of a symbol table.
#
prsymbs(out: ref Iobuf, t: ref Stab, eq: string)
{
	if (t == nil)
		return;
	for (l := t.all(); l != nil; l = tl l) {
		s := hd l;
		v := s.value;
		if (v != nil)
			prone(out, eq, s.name, v);
	}
}

#
#	Print variables, functions and builtins.
#
whatis(e: ref Env, out: ref Iobuf, s: string)
{
	f := 0;
	v := e.global.find(s);
	if (v != nil) {
		if (v.value != nil)
			prone(out, "=", s, v.value);
		if (v.func != nil) {
			out.puts("fn ");
			out.puts(s);
			out.puts(" { ");
			out.puts(v.func.text());
			out.puts(" };\n");
		}
		if (v.builtin != nil) {
			out.puts("load ");
			out.puts(v.builtin->name());
			out.puts("; ");
			out.puts(s);
			out.puts(";\n");
		}
		f = 1;
	}
	if (e.local != nil) {
		v = e.local.find(s);
		if (v != nil) {
			prone(out, ":=", s, v.value);
			f = 1;
		}
	}
	if (!f) {
		out.puts(s);
		out.puts(": not found\n");
	}
}

#
#	Catenate arguments and interpret as mash input.
#
eval(e: ref Env, l: list of string)
{
	s: string;
	while (l != nil) {
		s = s + " " + hd l;
		l = tl l;
	}
	e = e.copy();
	e.flags &= ~mashlib->EInter;
	e.sopen(s);
	mashlib->parse->parse(e);
}

#
#	Interpret file as mash input.
#
run(e: ref Env, l: list of string): int
{
	f := 0;
	if (l == nil)
		return 0;
	e = e.copy();
	s := hd l;
	while (s[0] == '-') {
		if (s == "-")
			f = 1;
		else {
			for (i := 1; i < len s; i++) {
				case s[i] {
				'd' =>
					e.flags |= mashlib->EDumping;
				'e' =>
					e.flags |= mashlib->ERaise;
				'n' =>
					e.flags |= mashlib->ENoxeq;
				'x' =>
					e.flags |= mashlib->EEcho;
				* =>
					return 0;
				}
			}
		}
		l = tl l;
		if (l == nil)
			return 0;
		s = hd l;
	}
	fd := sys->open(s, Sys->OREAD);
	if (fd == nil) {
		err := mashlib->errstr();
		if (mashlib->nonexistent(err) && s[0] != '/' && s[0:2] != "./") {
			fd = sys->open(mashlib->LIB + s, Sys->OREAD);
			if (fd == nil)
				err = mashlib->errstr();
			else
				s = mashlib->LIB + s;
		}
		if (fd == nil) {
			if (!f)
				e.report(s + ": " + err);
			return 1;
		}
	}
	e.local = Stab.new();
	e.local.assign(mashlib->ARGS, tl l);
	e.flags &= ~mashlib->EInter;
	e.fopen(fd, s);
	mashlib->parse->parse(e);
	return 1;
}

#
#	Run a command and report true on no error output.
#
status(e: ref Env, l: list of string)
{
	in := child(e, l);
	if (in == nil)
		return;
	b := array[256] of byte;
	n := sys->read(in, b, len b);
	if (n != 0) {
		while (n > 0)
			n = sys->read(in, b, len b);
		if (n < 0)
			e.couldnot("read", "pipe");
	} else
		e.output(Mashlib->TRUE);
}

#
#	Status env child.
#
child(e: ref Env, l: list of string): ref Sys->FD
{
	e = e.copy();
	fds := e.pipe();
	if (fds == nil)
		return nil;
	if (sys->dup(fds[0].fd, 2) < 0) {
		e.couldnot("dup", "pipe");
		return nil;
	}
	t := e.stderr;
	e.stderr = fds[0];
	e.runit(l, nil, nil, 0);
	e.stderr = t;
	sys->dup(t.fd, 2);
	return fds[1];
}

#
#	Time the execution of a command.
#
time(e: ref Env, l: list of string)
{
	t1 := sys->millisec();
	e.runit(l, nil, nil, 1);
	t2 := sys->millisec();
	sys->fprint(e.stderr, "%.4g\n", real (t2 - t1) / 1000.0);
}
