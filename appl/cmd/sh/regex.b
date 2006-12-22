implement Shellbuiltin;

include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Listnode, Context: import sh;
	myself: Shellbuiltin;
include "regex.m";
	regex: Regex;

initbuiltin(ctxt: ref Context, shmod: Sh): string
{
	sys = load Sys Sys->PATH;
	sh = shmod;
	myself = load Shellbuiltin "$self";
	if (myself == nil)
		ctxt.fail("bad module", sys->sprint("regex: cannot load self: %r"));
	regex = load Regex Regex->PATH;
	if (regex == nil)
		ctxt.fail("bad module",
			sys->sprint("regex: cannot load %s: %r", Regex->PATH));
	ctxt.addbuiltin("match", myself);
	ctxt.addsbuiltin("re", myself);
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
	"match" =>
		return builtin_match(ctxt, argv);
	}
	return nil;
}

whatis(nil: ref Sh->Context, nil: Sh, nil: string, nil: int): string
{
	return nil;
}

runsbuiltin(ctxt: ref Context, nil: Sh,
			argv: list of ref Listnode): list of ref Listnode
{
	name := (hd argv).word;
	case name {
	"re" =>
		return sbuiltin_re(ctxt, argv);
	}
	return nil;
}

sbuiltin_re(ctxt: ref Context, argv: list of ref Listnode): list of ref Listnode
{
	if (tl argv == nil)
		ctxt.fail("usage", "usage: re (g|v|s|sg|m|mg|M) arg...");
	argv = tl argv;
	w := (hd argv).word;
	case w {
	"g" or
	"v" =>
		return sbuiltin_sel(ctxt, argv, w == "v");
	"s" or
	"sg" =>
		return sbuiltin_sub(ctxt, argv, w == "sg");
	"m" =>
		return sbuiltin_match(ctxt, argv, 0);
	"mg" =>
		return sbuiltin_gmatch(ctxt, argv);
	"M" =>
		return sbuiltin_match(ctxt, argv, 1);
	* =>
		ctxt.fail("usage", "usage: re (g|v|s|sg|m|mg|M) arg...");
		return nil;
	}
}

sbuiltin_match(ctxt: ref Context, argv: list of ref Listnode, aflag: int): list of ref Listnode
{
	if (len argv != 3)
		ctxt.fail("usage", "usage: re " + (hd argv).word + " arg");
	argv = tl argv;
	re := getregex(ctxt, word(hd argv), aflag);
	w := word(hd tl argv);
	a := regex->execute(re, w);
	if (a == nil)
		return nil;
	ret: list of ref Listnode;
	for (i := len a - 1; i >= 0; i--)
		ret = ref Listnode(nil, elem(a, i, w)) :: ret;
	return ret;
}

sbuiltin_gmatch(ctxt: ref Context, argv: list of ref Listnode): list of ref Listnode
{
	if (len argv != 3)
		ctxt.fail("usage", "usage: re mg arg");
	argv = tl argv;
	re := getregex(ctxt, word(hd argv), 0);
	w := word(hd tl argv);
	ret, nret: list of ref Listnode;
	beg := 0;
	while ((a := regex->executese(re, w, (beg, len w), beg == 0, 1)) != nil) {
		(s, e) := a[0];
		ret = ref Listnode(nil, w[s:e]) :: ret;
		if (s == e)
			break;
		beg = e;
	}
	for (; ret != nil; ret = tl ret)
		nret = hd ret :: nret;
	return nret;
}

sbuiltin_sel(ctxt: ref Context, argv: list of ref Listnode, vflag: int): list of ref Listnode
{
	cmd := (hd argv).word;
	argv = tl argv;
	if (argv == nil)
		ctxt.fail("usage", "usage: " + cmd + " regex [arg...]");
	re := getregex(ctxt, word(hd argv), 0);
	ret, nret: list of ref Listnode;
	for (argv = tl argv; argv != nil; argv = tl argv)
		if (vflag ^ (regex->execute(re, word(hd argv)) != nil))
			ret = hd argv :: ret;
	for (; ret != nil; ret = tl ret)
		nret = hd ret :: nret;
	return nret;
}

sbuiltin_sub(ctxt: ref Context, argv: list of ref Listnode, gflag: int): list of ref Listnode
{
	cmd := (hd argv).word;
	argv = tl argv;
	if (argv == nil || tl argv == nil)
		ctxt.fail("usage", "usage: " + cmd + " regex subs [arg...]");
	re := getregex(ctxt, word(hd argv), 1);
	subs := word(hd tl argv);
	ret, nret: list of ref Listnode;
	for (argv = tl tl argv; argv != nil; argv = tl argv)
		ret = ref Listnode(nil, substitute(word(hd argv), re, subs, gflag).t1) :: ret;
	for (; ret != nil; ret = tl ret)
		nret = hd ret :: nret;
	return nret;
}

builtin_match(ctxt: ref Context, argv: list of ref Listnode): string
{
	if (tl argv == nil)
		ctxt.fail("usage", "usage: match regexp [arg...]");
	re := getregex(ctxt, word(hd tl argv), 0);
	for (argv = tl tl argv; argv != nil; argv = tl argv)
		if (regex->execute(re, word(hd argv)) == nil)
			return "no match";
	return nil;
}

substitute(w: string, re: Regex->Re, subs: string, gflag: int): (int, string)
{
	matched := 0;
	s := "";
	beg := 0;
	do {
		a := regex->executese(re, w, (beg, len w), beg == 0, 1);
		if (a == nil)
			break;
		matched = 1;
		s += w[beg:a[0].t0];
		for (i := 0; i < len subs; i++) {
			if (subs[i] != '\\' || i == len subs - 1)
				s[len s] = subs[i];
			else {
				c := subs[++i];
				if (c < '0' || c > '9')
					s[len s] = c;
				else
					s += elem(a, c - '0', w);
			}
		}
		beg = a[0].t1;
		if (a[0].t0 == a[0].t1)
			break;
	} while (gflag && beg < len w);
	return (matched, s + w[beg:]);
}

elem(a: array of (int, int), i: int, w: string): string
{
	if (i < 0 || i >= len a)
		return nil;		# XXX could raise failure here. (invalid backslash escape)
	(s, e) := a[i];
	if (s == -1)
		return nil;
	return w[s:e];
}

# XXX could do regex caching here if it was worth it.
getregex(ctxt: ref Context, res: string, flag: int): Regex->Re
{
	(re, err) := regex->compile(res, flag);
	if (re == nil)
		ctxt.fail("bad regex", "regex: bad regex \"" + res + "\": " + err);
	return re;
}

word(n: ref Listnode): string
{
	if (n.word != nil)
		return n.word;
	if (n.cmd != nil)
		n.word = sh->cmd2string(n.cmd);
	return n.word;
}
