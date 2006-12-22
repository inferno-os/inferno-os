implement Shellbuiltin;

include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Listnode, Context: import sh;
	myself: Shellbuiltin;
include "string.m";
	str: String;

initbuiltin(ctxt: ref Context, shmod: Sh): string
{
	sys = load Sys Sys->PATH;
	sh = shmod;
	myself = load Shellbuiltin "$self";
	if (myself == nil)
		ctxt.fail("bad module", sys->sprint("string: cannot load self: %r"));
	str = load String String->PATH;
	if (str == nil)
		ctxt.fail("bad module",
			sys->sprint("string: cannot load %s: %r", String->PATH));
	ctxt.addbuiltin("prefix", myself);
	ctxt.addbuiltin("in", myself);
	names := array[] of {
	"splitl", "splitr", "drop", "take", "splitstrl", "splitstrr",
	"tolower", "toupper", "len", "alen", "slice", "fields",
	"padl", "padr",
	};
	for (i := 0; i < len names; i++)
		ctxt.addsbuiltin(names[i], myself);
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
			argv: list of ref Listnode, nil: int): string
{
	case (hd argv).word {
	"prefix" =>
		(a, b) := earg2("prefix", ctxt, argv);
		if (!str->prefix(a, b))
			return "false";
	"in" =>
		(a, b) := earg2("in", ctxt, argv);
		if (a == nil || !str->in(a[0], b))
			return "false";
	}
	return nil;
}

runsbuiltin(ctxt: ref Context, nil: Sh,
			argv: list of ref Listnode): list of ref Listnode
{
	name := (hd argv).word;
	case name {
	"splitl" =>
		(a, b) := earg2("splitl", ctxt, argv);
		return mk2(str->splitl(a, b));
	"splitr" =>
		(a, b) := earg2("splitr", ctxt, argv);
		return mk2(str->splitr(a, b));
	"drop" =>
		(a, b) := earg2("drop", ctxt, argv);
		return mk1(str->drop(a, b));
	"take" =>
		(a, b) := earg2("take", ctxt, argv);
		return mk1(str->take(a, b));
	"splitstrl" =>
		(a, b) := earg2("splitstrl", ctxt, argv);
		return mk2(str->splitstrl(a, b));
	"splitstrr" =>
		(a, b) := earg2("splitstrr", ctxt, argv);
		return mk2(str->splitstrr(a, b));
	"tolower" =>
		return mk1(str->tolower(earg1("tolower", ctxt, argv)));
	"toupper" =>
		return mk1(str->toupper(earg1("tolower", ctxt, argv)));
	"len" =>
		return mk1(string len earg1("len", ctxt, argv));
	"alen" =>
		return mk1(string len array of byte earg1("alen", ctxt, argv));
	"slice" =>
		return sbuiltin_slice(ctxt, argv);
	"fields" =>
		return sbuiltin_fields(ctxt, argv);
	"padl" =>
		return sbuiltin_pad(ctxt, argv, -1);
	"padr" =>
		return sbuiltin_pad(ctxt, argv, 1);
	}
	return nil;
}

sbuiltin_pad(ctxt: ref Context, argv: list of ref Listnode, dir: int): list of ref Listnode
{
	if (tl argv == nil || !isnum((hd tl argv).word))
		ctxt.fail("usage", "usage: " + (hd argv).word + " n [arg...]");

	argv = tl argv;
	n := int (hd argv).word * dir;
	s := "";
	for (argv = tl argv; argv != nil; argv = tl argv) {
		s += word(hd argv);
		if (tl argv != nil)
			s[len s] = ' ';
	}
	if (n != 0)
		s =  sys->sprint("%*s", n, s);
	return ref Listnode(nil, s) :: nil;
}

sbuiltin_fields(ctxt: ref Context, argv: list of ref Listnode): list of ref Listnode
{
	argv = tl argv;
	if (len argv != 2)
		ctxt.fail("usage", "usage: fields cl s");
	cl := word(hd argv);
	s := word(hd tl argv);

	r: list of string;

	n := 0;
	for (i := 0; i < len s; i++) {
		if (str->in(s[i], cl)) {
			r = s[n:i] :: r;
			n = i + 1;
		}
	}
	r = s[n:i] :: r;
	rl: list of ref Listnode;
	for (; r != nil; r = tl r)
		rl = ref Listnode(nil, hd r) :: rl;
	return rl;
}


sbuiltin_slice(ctxt: ref Context, argv: list of ref Listnode): list of ref Listnode
{
	argv = tl argv;
	if (len argv != 3 || !isnum((hd argv).word) ||
			(hd tl argv).word != "end" && !isnum((hd tl argv).word))
		ctxt.fail("usage", "usage: slice start end arg");
	n1 := int (hd argv).word;
	n2: int;
	s := word(hd tl tl argv);
	r := "";
	if ((hd tl argv).word == "end")
		n2 = len s;
	else
		n2 = int (hd tl argv).word;
	if (n2 > len s)
		n2 = len s;
	if (n1 > len s)
		n1 = len s;
	if (n2 > n1)
		r = s[n1:n2];
	return mk1(r);
}

earg2(cmd: string, ctxt: ref Context, argv: list of ref Listnode): (string, string)
{
	argv = tl argv;
	if (len argv != 2)
		ctxt.fail("usage", "usage: " + cmd + " arg1 arg2");
	return (word(hd argv), word(hd tl argv));
}

earg1(cmd: string, ctxt: ref Context, argv: list of ref Listnode): string
{
	if (len argv != 2)
		ctxt.fail("usage", "usage: " + cmd + " arg");
	return word(hd tl argv);
}

mk2(x: (string, string)): list of ref Listnode
{
	(a, b) := x;
	return ref Listnode(nil, a) :: ref Listnode(nil, b) :: nil;
}

mk1(x: string): list of ref Listnode
{
	return ref Listnode(nil, x) :: nil;
}

isnum(s: string): int
{
	for (i := 0; i < len s; i++)
		if (s[i] > '9' || s[i] < '0')
			return 0;
	return 1;
}

word(n: ref Listnode): string
{
	if (n.word != nil)
		return n.word;
	if (n.cmd != nil)
		n.word = sh->cmd2string(n.cmd);
	return n.word;
}
