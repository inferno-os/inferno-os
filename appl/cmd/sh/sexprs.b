implement Shellbuiltin;

# parse/generate sexprs.

include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Listnode, Context: import sh;
	myself: Shellbuiltin;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "sexprs.m";
	sexprs: Sexprs;
	Sexp: import sexprs;

# getsexprs cmd
# islist val
# ${els se}
# ${text se}
# ${textels se}

# ${mktext val}
# ${mklist [val...]}
# ${mktextlist [val...]}

Maxerrs: con 10;

initbuiltin(ctxt: ref Context, shmod: Sh): string
{
	sys = load Sys Sys->PATH;
	sh = shmod;
	myself = load Shellbuiltin "$self";
	if (myself == nil)
		ctxt.fail("bad module", sys->sprint("sexpr: cannot load self: %r"));
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil)
		ctxt.fail("bad module", sys->sprint("sexpr: cannot load: %s: %r", Bufio->PATH));
	sexprs = load Sexprs Sexprs->PATH;
	if(sexprs == nil)
		ctxt.fail("bad module", sys->sprint("sexpr: cannot load: %s: %r", Sexprs->PATH));
	sexprs->init();
	ctxt.addbuiltin("getsexprs", myself);
	ctxt.addbuiltin("islist", myself);
	ctxt.addsbuiltin("els", myself);
	ctxt.addsbuiltin("text", myself);
	ctxt.addsbuiltin("b64", myself);
	ctxt.addsbuiltin("textels", myself);
	ctxt.addsbuiltin("mktext", myself);
	ctxt.addsbuiltin("mklist", myself);
	ctxt.addsbuiltin("mktextlist", myself);

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

runbuiltin(c: ref Sh->Context, nil: Sh,
			cmd: list of ref Sh->Listnode, nil: int): string
{
	case (hd cmd).word {
	"getsexprs" =>
		return builtin_getsexprs(c, tl cmd);
	"islist" =>
		return builtin_islist(c, tl cmd);
	}
	return nil;
}

runsbuiltin(c: ref Sh->Context, nil: Sh,
			cmd: list of ref Sh->Listnode): list of ref Listnode
{
	case (hd cmd).word {
	"els" =>
		return sbuiltin_els(c, tl cmd);
	"text" =>
		return sbuiltin_text(c, tl cmd);
	"b64" =>
		return sbuiltin_b64(c, tl cmd);
	"textels" =>
		return sbuiltin_textels(c, tl cmd);
	"mktext" =>
		return sbuiltin_mktext(c, tl cmd);
	"mklist" =>
		return sbuiltin_mklist(c, tl cmd);
	"mktextlist" =>
		return sbuiltin_mktextlist(c, tl cmd);
	}
	return nil;
}

builtin_getsexprs(ctxt: ref Context, argv: list of ref Listnode): string
{
	n := len argv;
	if (n != 1 || !iscmd(hd argv))
		builtinusage(ctxt, "getsexprs {cmd}");
	cmd := hd argv :: ctxt.get("*");
	stdin := bufio->fopen(sys->fildes(0), Sys->OREAD);
	if (stdin == nil)
		ctxt.fail("bad input", sys->sprint("getsexprs: cannot open stdin: %r"));
	status := "";
	nerrs := 0;
	ctxt.push();
	for(;;){
		{
			for (;;) {
				(se, err) := Sexp.read(stdin);
				if(err != nil){
					sys->fprint(sys->fildes(2), "getsexprs: error on read: %s\n", err);
					if(++nerrs > Maxerrs)
						raise "fail:too many errors";
					continue;
				}
				if(se == nil)
					break;
				nerrs = 0;
				ctxt.setlocal("sexp", ref Listnode(nil, se.text()) :: nil);
				status = setstatus(ctxt, ctxt.run(cmd, 0));
			}
			ctxt.pop();
			return status;
		}exception e{
		"fail:*" =>
			ctxt.pop();
			if (loopexcept(e) == BREAK)
				return status;
			ctxt.push();
		}
	}
}

builtin_islist(ctxt: ref Context, argv: list of ref Listnode): string
{
	if(argv == nil || tl argv != nil)
		builtinusage(ctxt, "islist sexp");
	w := word(hd argv);
	if(w != nil && w[0] =='(')
		return nil;
	if(parse(ctxt, hd argv).islist())
		return nil;
	return "not a list";
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

iscmd(n: ref Listnode): int
{
	return n.cmd != nil || (n.word != nil && n.word[0] == '{');
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

sbuiltin_els(ctxt: ref Context, val: list of ref Listnode): list of ref Listnode
{
	if (val == nil || tl val != nil)
		builtinusage(ctxt, "els sexp");
	r, rr: list of ref Listnode;
	for(els := parse(ctxt, hd val).els(); els != nil; els = tl els)
		r = ref Listnode(nil, (hd els).text()) :: r;
	for(; r != nil; r = tl r)
		rr = hd r :: rr;
	return rr;
}

sbuiltin_text(ctxt: ref Context, val: list of ref Listnode): list of ref Listnode
{
	if(val == nil || tl val != nil)
		builtinusage(ctxt, "text sexp");
	return ref Listnode(nil, parse(ctxt, hd val).astext()) :: nil;
}

sbuiltin_b64(ctxt: ref Context, val: list of ref Listnode): list of ref Listnode
{
	if(val == nil || tl val != nil)
		builtinusage(ctxt, "b64 sexp");
	return ref Listnode(nil, parse(ctxt, hd val).b64text()) :: nil;
}

sbuiltin_textels(ctxt: ref Context, val: list of ref Listnode): list of ref Listnode
{
	if (val == nil || tl val != nil)
		builtinusage(ctxt, "textels sexp");
	r, rr: list of ref Listnode;
	for(els := parse(ctxt, hd val).els(); els != nil; els = tl els)
		r = ref Listnode(nil, (hd els).astext()) :: r;
	for(; r != nil; r = tl r)
		rr = hd r :: rr;
	return rr;
}

sbuiltin_mktext(ctxt: ref Context, val: list of ref Listnode): list of ref Listnode
{
	if (val == nil || tl val != nil)
		builtinusage(ctxt, "mktext sexp");
	return ref Listnode(nil, (ref Sexp.String(word(hd val), nil)).text()) :: nil;
}

sbuiltin_mklist(nil: ref Context, val: list of ref Listnode): list of ref Listnode
{
	if(val == nil)
		return ref Listnode(nil, "()") :: nil;
	s := "(" + word(hd val);
	for(val = tl val; val != nil; val = tl val)
		s += " " + word(hd val);
	s[len s] = ')';
	return ref Listnode(nil, s) :: nil;
}

sbuiltin_mktextlist(nil: ref Context, val: list of ref Listnode): list of ref Listnode
{
	if(val == nil)
		return ref Listnode(nil, "()") :: nil;
	s := "(" + (ref Sexp.String(word(hd val), nil)).text();
	for(val = tl val; val != nil; val = tl val)
		s += " " + (ref Sexp.String(word(hd val), nil)).text();
	s[len s] = ')';
	return ref Listnode(nil, s) :: nil;
}

parse(ctxt: ref Context, val: ref Listnode): ref Sexp
{
	(se, rest, err) := Sexp.parse(word(val));
	if(rest != nil){
		for(i := 0; i < len rest; i++)
			if(rest[i] != ' ' && rest[i] != '\t' && rest[i] != '\n')
				ctxt.fail("bad sexp", sys->sprint("extra text found at end of s-expression %#q", word(val)));
	}
	if(err != nil)
		ctxt.fail("bad sexp", err);
	return se;
}

word(n: ref Listnode): string
{
	if (n.word != nil)
		return n.word;
	if (n.cmd != nil)
		n.word = sh->cmd2string(n.cmd);
	return n.word;
}
