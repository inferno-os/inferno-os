implement Shellbuiltin;

include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Listnode, Context: import sh;
	myself: Shellbuiltin;
include "filepat.m";
	filepat: Filepat;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

builtinnames := array[] of {
	"if", "while", "~", "!", "apply", "for",
	"status", "pctl", "fn", "subfn", "and", "or",
	"raise", "rescue", "flag", "getlines", "no",
};

sbuiltinnames := array[] of {
	"hd", "tl", "index", "split", "join", "pid", "parse", "env", "pipe",
};

initbuiltin(ctxt: ref Context, shmod: Sh): string
{
	sys = load Sys Sys->PATH;
	sh = shmod;
	myself = load Shellbuiltin "$self";
	if (myself == nil)
		ctxt.fail("bad module", sys->sprint("std: cannot load self: %r"));
	filepat = load Filepat Filepat->PATH;
	if (filepat == nil)
		ctxt.fail("bad module",
			sys->sprint("std: cannot load: %s: %r", Filepat->PATH));
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil)
		ctxt.fail("bad module",
			sys->sprint("std: cannot load: %s: %r", Bufio->PATH));
	names := builtinnames;
 	for (i := 0; i < len names; i++)
		ctxt.addbuiltin(names[i], myself);
	names = sbuiltinnames;
	for (i = 0; i < len names; i++)
		ctxt.addsbuiltin(names[i], myself);
	env := ctxt.envlist();
	for (; env != nil; env = tl env) {
		(name, val) := hd env;
		if (len name > 3 && name[0:3] == "fn-")
			fndef(ctxt, name[3:], val, 0);
		if (len name > 4 && name[0:4] == "sfn-")
			fndef(ctxt, name[4:], val, 1);
	}
	return nil;
}

whatis(c: ref Sh->Context, sh: Sh, name: string, wtype: int): string
{
	ename, fname: string;
	case wtype {
	BUILTIN =>
		(ename, fname) = ("fn-", "fn ");
	SBUILTIN =>
		(ename, fname) = ("sfn-", "subfn ");
	OTHER =>
		return nil;
	}

	val := c.get(ename + name);
	if (val != nil)
		return fname + name + " " + sh->quoted(hd val :: nil, 0);
	return nil;
}

getself(): Shellbuiltin
{
	return myself;
}

runbuiltin(c: ref Sh->Context, nil: Sh,
			cmd: list of ref Sh->Listnode, last: int): string
{
	status: string;
	name := (hd cmd).word;
	val := c.get("fn-" + name);
	if (val != nil)
		return c.run(hd val :: tl cmd, last);
	case name {
	"if" =>		status = builtin_if(c, cmd, last);
	"while" =>		status = builtin_while(c, cmd, last);
	"and" =>		status = builtin_and(c, cmd, last);
	"apply" =>	status = builtin_apply(c, cmd, last);
	"for" =>		status = builtin_for(c, cmd, last);
	"or" =>		status = builtin_or(c, cmd, last);
	"!" =>		status = builtin_not(c, cmd, last);
	"fn" =>		status = builtin_fn(c, cmd, last, 0);
	"subfn" =>	status = builtin_fn(c, cmd, last, 1);
	"~" =>		status = builtin_twiddle(c, cmd, last);
	"status" =>	status = builtin_status(c, cmd, last);
	"pctl" =>		status = builtin_pctl(c, cmd, last);
	"raise" =>		status = builtin_raise(c, cmd, last);
	"rescue" =>	status = builtin_rescue(c, cmd, last);
	"flag" =>		status = builtin_flag(c, cmd, last);
	"getlines" =>	status = builtin_getlines(c, cmd, last);
	"no" =>		status = builtin_no(c, cmd, last);
	}
	return status;
}

runsbuiltin(c: ref Sh->Context, nil: Sh,
			cmd: list of ref Sh->Listnode): list of ref Listnode
{
	name := (hd cmd).word;
	val := c.get("sfn-" + name);
	if (val != nil)
		return runsubfn(c, val, tl cmd);
	case name {
	"pid" =>
		return ref Listnode(nil, string sys->pctl(0, nil)) :: nil;
	"hd" =>
		if (tl cmd == nil)
			return nil;
		return hd tl cmd :: nil;
	"tl" =>
		if (tl cmd == nil)
			return nil;
		return tl tl cmd;
	"index" =>
		return sbuiltin_index(c, cmd);
	"split" =>
		return sbuiltin_split(c, cmd);
	"join" =>
		return sbuiltin_join(c, cmd);
	"parse" =>
		return sbuiltin_parse(c, cmd);
	"env" =>
		return sbuiltin_env(c, cmd);
	"pipe" =>
		return sbuiltin_pipe(c, cmd);
	}
	return nil;
}

runsubfn(ctxt: ref Context, body, args: list of ref Listnode): list of ref Listnode
{
	if (body == nil)
		return nil;
	ctxt.push();
	{
		ctxt.setlocal("result", nil);
		ctxt.run(hd body :: args, 0);
		result := ctxt.get("result");
		ctxt.pop();
		return result;
	} exception e {
	"fail:*" =>
		ctxt.pop();
		raise e;
	}
}

sbuiltin_index(ctxt: ref Context, val: list of ref Listnode): list of ref Listnode
{
	if (len val < 2 || (hd tl val).word == nil)
		builtinusage(ctxt, "index num list");
	k := int (hd tl val).word - 1;
	val = tl tl val;
	for (; k > 0 && val != nil; k--)
		val = tl val;
	if (val != nil)
		val = hd val :: nil;
	return val;
}

# return a parsed version of a string, raising a "parse error" exception if
# it fails. the string must be a braced command block.
sbuiltin_parse(ctxt: ref Context, args: list of ref Listnode): list of ref Listnode
{
	if (len args != 2)
		builtinusage(ctxt, "parse arg");
	args = tl args;
	if ((hd args).cmd != nil)
		return ref Listnode((hd args).cmd, nil) :: nil;
	w := (hd args).word;
	if (w == nil || w[0] != '{')	#}
		ctxt.fail("parse error", "parse: argument must be a braced block");
	(n, err) := sh->parse(w);
	if (err != nil)
		ctxt.fail("parse error", "parse: " + err);
	return ref Listnode(n, nil) :: nil;
}

sbuiltin_env(ctxt: ref Context, nil: list of ref Listnode): list of ref Listnode
{
	vl: list of string;
	for (e := ctxt.envlist(); e != nil; e = tl e) {
		(n, v) := hd e;
		if (v != nil)		# XXX this is debatable... someone might want to see null local vars.
			vl = n :: vl;
	}
	return sh->stringlist2list(vl);
}

word(n: ref Listnode): string
{
	if (n.word != nil)
		return n.word;
	if (n.cmd != nil)
		n.word = sh->cmd2string(n.cmd);
	return n.word;
}

# usage: split [separators] value
sbuiltin_split(ctxt: ref Context, args: list of ref Listnode): list of ref Listnode
{
	n := len args;
	if (n < 2  || n > 3)
		builtinusage(ctxt, "split [separators] value");
	seps: string;
	if (n == 2) {
		ifs := ctxt.get("ifs");
		if (ifs == nil)
			ctxt.fail("usage", "split: $ifs not set");
		seps = word(hd ifs);
	} else {
		args = tl args;
		seps = word(hd args);
	}
	(nil, toks) := sys->tokenize(word(hd tl args), seps);
	return sh->stringlist2list(toks);
}

sbuiltin_join(ctxt: ref Context, args: list of ref Listnode): list of ref Listnode
{
	args = tl args;
	if (args == nil)
		builtinusage(ctxt, "join separator [arg...]");
	seps := word(hd args);
	if (tl args == nil)
		return ref Listnode(nil, nil) :: nil;
	s := word(hd tl args);
	for (args = tl tl args; args != nil; args = tl args)
		s += seps + word(hd args);
	return ref Listnode(nil, s) :: nil;
}

builtin_fn(ctxt: ref Context, args: list of ref Listnode, nil: int, issub: int): string
{
	n := len args;
	title := (hd args).word;
	if (n < 2)
		builtinusage(ctxt, title + " [name...] [{body}]");
	for (al := tl args; tl al != nil; al = tl al)
		if ((hd al).cmd != nil)
			builtinusage(ctxt, title + " [name...] [{body}]");
	if ((hd al).cmd != nil) {
		cmd := hd al :: nil;
		for (al = tl args; tl al != nil; al = tl al)
			fndef(ctxt, (hd al).word, cmd, issub);
	} else {
		for (al = tl args; al != nil; al = tl al)
			fnundef(ctxt, (hd al).word, issub);
	}
	return nil;
}

fndef(ctxt: ref Context, name: string, cmd: list of ref Listnode, issub: int)
{
	if (cmd == nil)
		return;
	if (issub) {
		ctxt.set("sfn-" + name, cmd);
		ctxt.addsbuiltin(name, myself);
	} else {
		ctxt.set("fn-" + name, cmd);
		ctxt.addbuiltin(name, myself);
	}
}

fnundef(ctxt: ref Context, name: string, issub: int)
{
	if (issub) {
		ctxt.set("sfn-" + name, nil);
		ctxt.removesbuiltin(name, myself);
	} else {
		ctxt.set("fn-" + name, nil);
		ctxt.removebuiltin(name, myself);
	}
}

builtin_flag(ctxt: ref Context, args: list of ref Listnode, nil: int): string
{
	n := len args;
	if (n < 2 || n > 3 || len (hd tl args).word != 1)
		builtinusage(ctxt, "flag [vxei] [+-]");
	flag := (hd tl args).word[0];
	p := "";
	if (n == 3)
		p = (hd tl tl args).word;
	mask := 0;
	case flag {
	'v' =>	mask = Context.VERBOSE;
	'x' =>	mask = Context.EXECPRINT;
	'e' =>	mask = Context.ERROREXIT;
	'i' =>		mask = Context.INTERACTIVE;
	* =>		builtinusage(ctxt, "flag [vxei] [+-]");
	}
	case p {
	"" =>		if (ctxt.options() & mask)
				return nil;
			return "not set";
	"-" =>	ctxt.setoptions(mask, 0);
	"+" =>	ctxt.setoptions(mask, 1);
	* =>		builtinusage(ctxt, "flag [vxei] [+-]");
	}
	return nil;
}

builtin_no(nil: ref Context, args: list of ref Listnode, nil: int): string
{
	if (tl args != nil)
		return "yes";
	return nil;
}

iscmd(n: ref Listnode): int
{
	return n.cmd != nil || (n.word != nil && n.word[0] == '{');
}

builtin_if(ctxt: ref Context, args: list of ref Listnode, nil: int): string
{
	args = tl args;
	nargs := len args;
	if (nargs < 2)
		builtinusage(ctxt, "if {cond} {action} [{cond} {action}]... [{elseaction}]");

	status: string;
	dolstar := ctxt.get("*");
	while (args != nil) {
		cmd: ref Listnode = nil;
		if (tl args == nil) {
			cmd = hd args;
			args = tl args;
		} else {
			if (!iscmd(hd args))
				builtinusage(ctxt, "if [{cond} {action}]... [{elseaction}]");

			status = ctxt.run(hd args :: dolstar, 0);
			if (status == nil) {
				cmd = hd tl args;
				args = nil;
			} else
				args = tl tl args;
			setstatus(ctxt, status);
		}
		if (cmd != nil) {
			if (!iscmd(cmd))
				builtinusage(ctxt, "if [{cond} {action}]... [{elseaction}]");

			status = ctxt.run(cmd :: dolstar, 0);
		}
	}
	return status;	
}

builtin_or(ctxt: ref Context, args: list of ref Listnode, nil: int): string
{
	s: string;
	dolstar := ctxt.get("*");
	for (args = tl args; args != nil; args = tl args) {
		if (!iscmd(hd args))
			builtinusage(ctxt, "or [{cmd} ...]");
		if ((s = ctxt.run(hd args :: dolstar, 0)) == nil)
			return nil;
		else
			setstatus(ctxt, s);
	}
	return s;
}

builtin_and(ctxt: ref Context, args: list of ref Listnode, nil: int): string
{
	dolstar := ctxt.get("*");
	for (args = tl args; args != nil; args = tl args) {
		if (!iscmd(hd args))
			builtinusage(ctxt, "and [{cmd} ...]");
		if ((s := ctxt.run(hd args :: dolstar, 0)) != nil)
			return s;
		else
			setstatus(ctxt, nil);
	}
	return nil;
}

builtin_while(ctxt: ref Context, args: list of ref Listnode, nil: int) : string
{
	args = tl args;
	if (len args != 2 || !iscmd(hd args) || !iscmd(hd tl args))
		builtinusage(ctxt, "while {condition} {cmd}");

	dolstar := ctxt.get("*");
	cond := hd args :: dolstar;
	action := hd tl args :: dolstar;
	status := "";
	
	for(;;){
		{
			while (ctxt.run(cond, 0) == nil)
				status = setstatus(ctxt, ctxt.run(action, 0));
			return status;
		} exception e{
		"fail:*" =>
			if (loopexcept(e) == BREAK)
				return status;
		}
	}
}

builtin_getlines(ctxt: ref Context, argv: list of ref Listnode, nil: int) : string
{
	n := len argv;
	if (n < 2  || n > 3)
		builtinusage(ctxt, "getlines [separators] {cmd}");
	argv = tl argv;
	seps := "\n";
	if (n == 3) {
		seps = word(hd argv);
		argv = tl argv;
	}
	if (len seps == 0)
		builtinusage(ctxt, "getlines [separators] {cmd}");
	if (!iscmd(hd argv))
		builtinusage(ctxt, "getlines [separators] {cmd}");
	cmd := hd argv :: ctxt.get("*");
	stdin := bufio->fopen(sys->fildes(0), Sys->OREAD);
	if (stdin == nil)
		ctxt.fail("bad input", sys->sprint("getlines: cannot open stdin: %r"));
	status := "";
	ctxt.push();
	for(;;){
		{
			for (;;) {
				s: string;
				if (len seps == 1)
					s = stdin.gets(seps[0]);
				else
					s = stdin.gett(seps);
				if (s == nil)
					break;
				# make sure we don't lose the last unterminated line
				lastc := s[len s - 1];
				if (lastc == seps[0])
					s = s[0:len s - 1];
				else for (i := 1; i < len seps; i++) {
					if (lastc == seps[i]) {
						s = s[0:len s - 1];
						break;
					}
				}
				ctxt.setlocal("line", ref Listnode(nil, s) :: nil);
				status = setstatus(ctxt, ctxt.run(cmd, 0));
			}
			ctxt.pop();
			return status;
		} exception e {
		"fail:*" =>
			ctxt.pop();
			if (loopexcept(e) == BREAK)
				return status;
			ctxt.push();
		}
	}
}

# usage: raise [name]
builtin_raise(ctxt: ref Context, args: list of ref Listnode, nil: int) : string
{
	ename: ref Listnode;
	if (tl args == nil) {
		e := ctxt.get("exception");
		if (e == nil)
			ctxt.fail("bad raise context", "raise: no exception found");
		ename = (hd e);
	} else
		ename = hd tl args;
	if (ename.word == nil && ename.cmd != nil)
		ctxt.fail("bad raise context", "raise: bad exception name");
	xraise("fail:" + ename.word);
	return nil;
}

# usage: rescue pattern rescuecmd cmd
builtin_rescue(ctxt: ref Context, args: list of ref Listnode, last: int) : string
{
	args = tl args;
	if (len args != 3 || !iscmd(hd tl args) || !iscmd(hd tl tl args))
		builtinusage(ctxt, "rescue pattern {rescuecmd} {cmd}");
	if ((hd args).word == nil && (hd args).cmd != nil)
		ctxt.fail("usage", "rescue: bad pattern");
	dolstar := ctxt.get("*");
	handler := hd tl args :: dolstar;
	code := hd tl tl args :: dolstar;
	{
		return ctxt.run(code, 0);
	} exception e {
	"fail:*" =>
		ctxt.push();
		ctxt.set("exception", ref Listnode(nil, e[5:]) :: nil);
		{
			status := ctxt.run(handler, last);
			ctxt.pop();
			return status;
		} exception {
		"fail:*" =>
			ctxt.pop();
			raise e;
		}
	}
}

builtin_not(ctxt: ref Context, args: list of ref Listnode, last: int): string
{
	# syntax: ! cmd [args...]
	args = tl args;
	if (args == nil || ctxt.run(args, last) == nil)
		return "false";
	return "";
}

builtin_for(ctxt: ref Context, args: list of ref Listnode, nil: int): string
{
	Usage: con "for var in [item...] {cmd}";
	args = tl args;
	if (args == nil)
		builtinusage(ctxt, Usage);
	var := (hd args).word;
	if (var == nil)
		ctxt.fail("bad assign", "for: bad variable name");
	args = tl args;
	if (args == nil || (hd args).word != "in")
		builtinusage(ctxt, Usage);
	args = tl args;
	if (args == nil)
		builtinusage(ctxt, Usage);
	for (eargs := args; tl eargs != nil; eargs = tl eargs)
			;
	cmd := hd eargs;
	if (!iscmd(cmd))
		builtinusage(ctxt, Usage);

	status := "";
	dolstar := ctxt.get("*");
	for(;;){
		{
			for (; tl args != nil; args = tl args) {
				ctxt.setlocal(var, hd args :: nil);
				status = setstatus(ctxt, ctxt.run(cmd :: dolstar, 0));
			}
			return status;
		} exception e {
		"fail:*" =>
			if (loopexcept(e) == BREAK)
				return status;
			args = tl args;
		}
	}
}

CONTINUE, BREAK: con iota;
loopexcept(ename: string): int
{
	case ename[5:] {
	"break" =>
		return BREAK;
	"continue" =>
		return CONTINUE;
	* =>
		raise ename;
	}
	return 0;
}

builtin_apply(ctxt: ref Context, args: list of ref Listnode, nil: int): string
{
	args = tl args;
	if (args == nil || !iscmd(hd args))
		builtinusage(ctxt, "apply {cmd} [val...]");

	status := "";
	cmd := hd args;
	for(;;){
		{
			for (args = tl args; args != nil; args = tl args)
				status = setstatus(ctxt, ctxt.run(cmd :: hd args :: nil, 0));

			return status;
		} exception e{
		"fail:*" =>
			if (loopexcept(e) == BREAK)
				return status;
		}
	}
}

builtin_status(nil: ref Context, args: list of ref Listnode, nil: int): string
{
	if (tl args != nil)
		return (hd tl args).word;
	return "";
}

pctlnames := array[] of {
	("newfd", Sys->NEWFD),
	("forkfd", Sys->FORKFD),
	("newns", Sys->NEWNS),
	("forkns", Sys->FORKNS),
	("newpgrp", Sys->NEWPGRP),
	("nodevs", Sys->NODEVS)
};

builtin_pctl(ctxt: ref Context, argv: list of ref Listnode, nil: int): string
{
	if (len argv < 2)
		builtinusage(ctxt, "pctl option... [fdnum...]");

	finalmask := 0;
	fdlist: list of int;
	for (argv = tl argv; argv != nil; argv = tl argv) {
		w := (hd argv).word;
		if (isnum(w))
			fdlist = int w :: fdlist;
		else {
			for (i := 0; i < len pctlnames; i++) {
				(name, mask) := pctlnames[i];
				if (name == w) {
					finalmask |= mask;
					break;
				}
			}
			if (i == len pctlnames)
				ctxt.fail("usage", "pctl: unknown flag " + w);
		}
	}
	sys->pctl(finalmask, fdlist);
	return nil;
}

# usage: ~ value pattern...
builtin_twiddle(ctxt: ref Context, argv: list of ref Listnode, nil: int): string
{
	argv = tl argv;
	if (argv == nil)
		builtinusage(ctxt, "~ word [pattern...]");
	if (tl argv == nil)
		return "no match";
	w := word(hd argv);

	for (argv = tl argv; argv != nil; argv = tl argv)
		if (filepat->match(word(hd argv), w))
			return "";

	return "no match";
}

#builtin_echo(ctxt: ref Context, argv: list of ref Listnode, nil: int): string
#{
#	argv = tl argv;
#	nflag := 0;
#	if (argv != nil && word(hd argv) == "-n") {
#		nflag = 1;
#		argv = tl argv;
#	}
#	s: string;
#	if (argv != nil) {
#		s = word(hd argv);
#		for (argv = tl argv; argv != nil; argv = tl argv)
#			s += " " + word(hd argv);
#	}
#	e: int;
#	if (nflag)
#		e = sys->print("%s", s);
#	else
#		e = sys->print("%s\n", s);
#	if (e == -1) {
#		err := sys->sprint("%r");
#		if (ctxt.options() & ctxt.VERBOSE)
#			sys->fprint(sys->fildes(2), "echo: write error: %s\n", err);
#		return err;
#	}
#	return nil;
#}

ENOEXIST: con "file does not exist";
TMPDIR: con "/tmp/pipes";
sbuiltin_pipe(ctxt: ref Context, argv: list of ref Listnode): list of ref Listnode
{
	n: int;
	if (len argv != 3 || !iscmd(hd tl tl argv))
		builtinusage(ctxt, "pipe (from|to|fdnum) {cmd}");
	s := (hd tl argv).word;
	case s {
	"from" =>
		n = 1;
	"to" =>
		n = 0;
	* =>
		if (!isnum(s))
			builtinusage(ctxt, "pipe (from|to|fdnum) {cmd}");
		n = int s;
	}
	pipeid := ctxt.get("pipeid");
	seq: int;
	if (pipeid == nil)
		seq = 0;
	else
		seq = int (hd pipeid).word;
	id := "pipe." + string sys->pctl(0, nil) + "." + string seq;
	ctxt.set("pipeid", ref Listnode(nil, string ++seq) :: nil);
	mkdir(TMPDIR);
	d := "/tmp/" + id + "d";
	if (mkdir(d) == -1)
		ctxt.fail("bad pipe", sys->sprint("pipe: cannot make %s: %r", d));
	if (sys->bind("#|", d, Sys->MREPL) == -1) {
		sys->remove(d);
		ctxt.fail("bad pipe", sys->sprint("pipe: cannot bind pipe onto %s: %r", d));
	}
	if (rename(d + "/data", id + "x") == -1 || rename(d + "/data1", id + "y")) {
		sys->unmount(nil, d);
		sys->remove(d);
		ctxt.fail("bad pipe", sys->sprint("pipe: cannot rename pipe: %r"));
	}
	if (sys->bind(d, TMPDIR, Sys->MBEFORE) == -1) {
		sys->unmount(nil, d);
		sys->remove(d);
		ctxt.fail("bad pipe", sys->sprint("pipe: cannot bind pipe dir: %r"));
	}
	sys->unmount(nil, d);
	sys->remove(d);
	sync := chan of string;
	spawn runpipe(sync, ctxt, n, TMPDIR + "/" + id + "x", hd tl tl argv);
	if ((e := <-sync) != nil)
		ctxt.fail("bad pipe", e);
	return ref Listnode(nil, TMPDIR + "/" + id + "y") :: nil;
}

mkdir(f: string): int
{
	if (sys->create(f, Sys->OREAD, Sys->DMDIR | 8r777) == nil)
		return -1;
	return 0;
}

runpipe(sync: chan of string, ctxt: ref Context, fdno: int, p: string, cmd: ref Listnode)
{
	sys->pctl(Sys->FORKFD, nil);
	ctxt = ctxt.copy(1);
	if ((fd := sys->open(p, Sys->ORDWR)) == nil) {
		sync <-= sys->sprint("cannot open %s: %r", p);
		exit;
	}
	sys->dup(fd.fd, fdno);
	fd = nil;
	sync <-= nil;
	ctxt.run(cmd :: ctxt.get("*"), 1);
}

rename(x, y: string): int
{
	(ok, nil) := sys->stat(x);
	if (ok == -1)
		return -1;
	inf := sys->nulldir;
	inf.name = y;
	if (sys->wstat(x, inf) == -1)
		return -1;
	return 0;
}
	
builtinusage(ctxt: ref Context, s: string)
{
	ctxt.fail("usage", "usage: " + s);
}

setstatus(ctxt: ref Context, val: string): string
{
	ctxt.setlocal("status", ref Listnode(nil, val) :: nil);
	return val;
}

# same as sys->raise(), but check that length of error string is
# acceptable, and truncate as appropriate.
xraise(s: string)
{
	d := array of byte s;
	if (len d > Sys->WAITLEN)
		raise string d[0:Sys->WAITLEN];
	else {
		d = nil;
		raise s;
	}
}

isnum(s: string): int
{
	for (i := 0; i < len s; i++)
		if (s[i] > '9' || s[i] < '0')
			return 0;
	return 1;
}

