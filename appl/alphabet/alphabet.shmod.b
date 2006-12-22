implement Alphabetsh, Shellbuiltin;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Context, Listnode: import sh;
	n_WORD: import sh;
include "alphabet/reports.m";
	reports: Reports;
	report, Report: import reports;
include "readdir.m";
	readdir: Readdir;
include "alphabet.m";
	alphabet: Alphabet;
	Value, CHECK, ONDEMAND: import alphabet;
include "alphabet/abc.m";

Alphabetsh: module {};

myself: Shellbuiltin;

initbuiltin(ctxt: ref Sh->Context, shmod: Sh): string
{
	sys = load Sys Sys->PATH;
	myself = load Shellbuiltin "$self";
	sh = shmod;
	if (myself == nil)
		ctxt.fail("bad module", sys->sprint("file2chan: cannot load self: %r"));

	alphabet = load Alphabet Alphabet->PATH;
	if(alphabet == nil)
		ctxt.fail("bad module", sys->sprint("alphabet: cannot load %q: %r", Alphabet->PATH));
	reports = load Reports Reports->PATH;
	if(reports == nil)
		ctxt.fail("bad module", sys->sprint("alphabet: cannot load %q: %r", Reports->PATH));
	readdir = load Readdir Readdir->PATH;
	if(readdir == nil)
		ctxt.fail("bad module", sys->sprint("alphabet: cannot load %q: %r", Readdir->PATH));

	alphabet->init();
	alphabet->setautodeclare(1);

	if((decls := ctxt.get("autodeclares")) != nil){
		for(; decls != nil; decls = tl decls){
			d := hd decls;
			if(d.cmd == nil){
				err: string;
				(d.cmd, err) = sh->parse(d.word);
				if(err != nil){
					sys->fprint(sys->fildes(2), "alphabet: warning: bad autodeclaration: %s\n", err);
					continue;
				}
			}
			{
				declares(ctxt, nil::d::nil);
			}exception{
			"fail:*" =>
				;
			}
		}
	}

	ctxt.addbuiltin("declare", myself);
	ctxt.addbuiltin("declares", myself);
	ctxt.addbuiltin("undeclare", myself);
	ctxt.addbuiltin("define", myself);
	ctxt.addbuiltin("import", myself);
	ctxt.addbuiltin("autodeclare", myself);
	ctxt.addbuiltin("type", myself);
	ctxt.addbuiltin("typeset", myself);
	ctxt.addbuiltin("autoconvert", myself);
	ctxt.addbuiltin("-", myself);
	ctxt.addbuiltin("info", myself);
	ctxt.addbuiltin("clear", myself);

#	ctxt.addsbuiltin("-", myself);
	ctxt.addsbuiltin("rewrite", myself);
	ctxt.addsbuiltin("modules", myself);
	ctxt.addsbuiltin("types", myself);
	ctxt.addsbuiltin("usage", myself);
	return nil;
}

runbuiltin(c: ref Sh->Context, nil: Sh,
			cmd: list of ref Listnode, nil: int): string
{
	case (hd cmd).word {
	"declare" =>
		return declare(c, cmd);
	"declares" =>
		return declares(c, cmd);
	"undeclare" =>
		return undeclare(c, cmd);
	"define" =>
		return define(c, cmd);
	"import" =>
		return importf(c, cmd);
	"type" =>
		return importtype(c, cmd);
	"typeset" =>
		return typeset(c, cmd);
	"autoconvert" =>
		return autoconvert(c, cmd);
	"autodeclare" =>
		if(len cmd != 2)
			usage(c, "usage: autodeclare 0/1");
		alphabet->setautodeclare(int word(hd tl cmd));
	"info" =>
		return info(c, cmd);
	"clear" =>
		a := load Alphabet Alphabet->PATH;
		if(a == nil)
			c.fail("bad module", sys->sprint("alphabet: cannot load %q: %r", Alphabet->PATH));
		alphabet->quit();
		alphabet = a;
		alphabet->init();
		alphabet->setautodeclare(1);
	"-" =>
		return eval(c, cmd);
	}
	return nil;
}

whatis(nil: ref Sh->Context, nil: Sh, mod: string, wtype: int): string
{
	if(wtype == OTHER){
		(qname, sig, def) := alphabet->getmodule(mod);
		if(qname == nil)
			return nil;
		s := sys->sprint("declare %q %q", qname, sig);
		if(def != nil){
			for(i := len sig-1; i >= 0; i--){
				if(sig[i] == '>'){
					sig = sig[0:i-1];
					break;
				}
			}
			s += sys->sprint("; define %q {(%s); %s}", qname, sig, sh->cmd2string(def));
		}
		return s;
	}
	return nil;
}

getself(): Shellbuiltin
{
	return myself;
}

runsbuiltin(ctxt: ref Context, nil: Sh,
			argv: list of ref Listnode): list of ref Listnode
{
	case (hd argv).word {
	"rewrite" =>
		return rewrite(ctxt, argv);
	"modules" =>
		return sh->stringlist2list(alphabet->getmodules());
	"types" =>
		ts := "";
		if(tl argv != nil)
			ts = word(hd tl argv);
		r := sh->stringlist2list(alphabet->gettypes(ts));
		if(r == nil)
			ctxt.fail("error", sys->sprint("unknown typeset %q", ts));
		return r;
	"usage" =>
		if(len argv != 2)
			usage(ctxt, "usage qname");
		(qname, u, nil) := alphabet->getmodule(word(hd tl argv));
		if(qname == nil)
			ctxt.fail("error", "module not declared");
		return ref Listnode(nil, u) :: nil;
	}
	return nil;
}

usage(ctxt: ref Context, s: string)
{
	ctxt.fail("usage", "usage: " + s);
}

declares(ctxt: ref Sh->Context, argv: list of ref Listnode): string
{
	argv = tl argv;
	if(argv == nil || (hd argv).cmd == nil)
		ctxt.fail("usage", "usage: declares decls");
	decls := (hd argv).cmd;
	declares := load Declares Declares->PATH;
	if(declares == nil)
		ctxt.fail("bad module", sys->sprint("alphabet: cannot load %q: %r", Declares->PATH));
	{
		declares->init();
	} exception e {
	"fail:*" =>
		ctxt.fail("declares init", e[5:]);
	}

	spawn printerrors(errorc := chan of string);
	e := declares->declares(alphabet, decls, errorc, nil);
	declares->quit();
	if(e != nil)
		ctxt.fail("bad declaration", sys->sprint("alphabet: declaration failed: %s", e));
	return nil;
}

rewrite(ctxt: ref Sh->Context, argv: list of ref Listnode): list of ref Listnode
{
	argv = tl argv;
	n := len argv;
	if(n != 1 && n != 2 || (hd argv).cmd == nil)
		usage(ctxt, "rewrite {expr} [desttype]");
	spawn printerrors(errorc := chan of string);
	desttype := "";
	if(n == 2)
		desttype = word(hd tl argv);
	(c, usage) := alphabet->rewrite((hd argv).cmd, desttype, errorc);
	errorc <-= nil;
	if(c == nil)
		raise "fail:bad expression";
	return (ref Listnode(c, nil) :: ref Listnode(nil, usage) :: nil);
}

# XXX add support for optional ONDEMAND and CHECK flags
declare(ctxt: ref Sh->Context, argv: list of ref Listnode): string
{
	argv = tl argv;
	n := len argv;
	if(n < 1 || n > 2)
		usage(ctxt, "declare qname [type]");
	decltype := "";
	if(n == 2)
		decltype = word(hd tl argv);
	e := alphabet->declare(word(hd argv), decltype, 0);
	if(e != nil)
		ctxt.fail("error", sys->sprint("cannot declare %s: %s", word(hd argv), e));
	return nil;
}

undeclare(ctxt: ref Sh->Context, argv: list of ref Listnode): string
{
	argv = tl argv;
	if(argv == nil)
		usage(ctxt, "undeclare name...");
	for(; argv != nil; argv = tl argv){
		if((e := alphabet->undeclare(word(hd argv))) != nil)
			sys->fprint(sys->fildes(2), "alphabet: cannot undeclare %q: %s\n", word(hd argv), e);
	}
	return nil;
}

# usage define name expr
define(ctxt: ref Sh->Context, argv: list of ref Listnode): string
{
	argv = tl argv;
	if(len argv != 2 || (hd tl argv).cmd == nil)
		usage(ctxt, "define name {expr}");
	
	spawn printerrors(errorc := chan of string);

	err := alphabet->define((hd argv).word, (hd tl argv).cmd, errorc);
	errorc <-= nil;
	if(err != nil)
		raise "fail:bad define: "+err;
	return nil;
}

importf(ctxt: ref Sh->Context, argv: list of ref Listnode): string
{
	argv = tl argv;
	if(argv == nil)
		usage(ctxt, "import qname...");
	errs := 0;
	for(; argv != nil; argv = tl argv){
		e := alphabet->importmodule(word(hd argv));
		if(e != nil){
			sys->fprint(sys->fildes(2), "alphabet: cannot import %s: %s\n", word(hd argv), e);
			errs++;
		}
	}
	if(errs)
		raise "fail:import error";
	return nil;
}

importtype(ctxt: ref Sh->Context, argv: list of ref Listnode): string
{
	argv = tl argv;
	if(argv == nil)
		usage(ctxt, "type qname...");
	errs := 0;
	for(; argv != nil; argv = tl argv){
		e := alphabet->importtype(word(hd argv));
		if(e != nil){
			sys->fprint(sys->fildes(2), "alphabet: cannot import type %s: %s\n", word(hd argv), e);
			errs++;
		}
	}
	if(errs)
		raise "fail:type declare error";
	return nil;
}

typeset(ctxt: ref Sh->Context, argv: list of ref Listnode): string
{
	argv = tl argv;
	if(len argv != 1)
		usage(ctxt, "typeset qname");
	spawn printerrors(errorc := chan of string);
	e := alphabet->loadtypeset(word(hd argv), nil, errorc);	# XXX errorc?
	errorc <-= nil;
	if(e != nil)
		ctxt.fail("error", sys->sprint("cannot load typeset %q: %s", word(hd argv), e));
	return nil;
}

autoconvert(ctxt: ref Sh->Context, argv: list of ref Listnode): string
{
	argv = tl argv;
	if(len argv != 3)
		usage(ctxt, "autoconvert src dst fn");
	src := word(hd argv);
	dst := word(hd tl argv);
	expr := (hd tl tl argv).cmd;
	if(expr == nil)
		expr = ref Sh->Cmd(Sh->n_WORD, nil, nil, (hd tl tl argv).word, nil);
	spawn printerrors(errorc := chan of string);
	e := alphabet->autoconvert(src, dst, expr, errorc);
	errorc <-= nil;
	if(e != nil)
		ctxt.fail("error", sys->sprint("cannot autoconvert %s to %s via %s: %s",
				src, dst, word(hd tl tl argv), e));
	return nil;
}

info(ctxt: ref Sh->Context, argv: list of ref Listnode): string
{
	first := 1;
	if(tl argv != nil)
		usage(ctxt, "info");
	for(tsl := alphabet->gettypesets(); tsl != nil; tsl = tl tsl){
		ts := hd tsl;
		r := alphabet->gettypesetmodules(ts);
		if(r == nil)
			continue;
		if(first == 0)
			sys->print("\n");
		sys->print("typeset %s\n", ts);
		while((mod := <-r) != nil){
			(qname, u, nil) := alphabet->getmodule(ts+"/"+mod);
			if(qname != nil)
				sys->print("%s %s\n", qname, u);
		}
		first = 0;
	}
	acl := alphabet->getautoconversions();
	if(acl != nil)
		sys->print("\n");

	for(; acl != nil; acl = tl acl){
		(src, dst, via) := hd acl;
		sys->print("autoconvert %q %q %s\n", src, dst, sh->cmd2string(via));
	}
	return nil;
}

eval(ctxt: ref Sh->Context, argv: list of ref Listnode): string
{
	argv = tl argv;
	if(argv == nil || (hd argv).cmd == nil)
		usage(ctxt, "- {expr} [arg...]");
	c := (hd argv).cmd;
	if(c == nil)
		c = mkw((hd argv).word);


	args: list of ref Value;
	for(argv = tl argv; argv != nil; argv = tl argv){
		if((hd argv).cmd != nil)
			args = ref Value.Vc((hd argv).cmd) :: args;
		else
			args = ref Value.Vs((hd argv).word) :: args;
	}
	return alphabet->eval(c, ctxt.drawcontext, rev(args));
}

rev[T](x: list of T): list of T
{
	l: list of T;
	for(; x != nil; x = tl x)
		l = hd x :: l;
	return l;
}

word(n: ref Listnode): string
{
	if (n.word != nil)
		return n.word;
	if (n.cmd != nil)
		n.word = sh->cmd2string(n.cmd);
	return n.word;
}

printerrors(c: chan of string)
{
	while((s := <-c) != nil)
		sys->fprint(sys->fildes(2), "e: %s\n", s);
}

mkw(w: string): ref Sh->Cmd
{
	return ref Sh->Cmd(n_WORD, nil, nil, w, nil);
}
