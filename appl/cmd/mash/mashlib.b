implement Mashlib;

#
#	Mashlib	- All of the real work except for the parsing.
#

include	"mash.m";
include	"mashparse.m";

Iobuf:			import bufio;
HashTable, HashVal:	import hash;

include	"depends.b";
include	"dump.b";
include	"exec.b";
include	"expr.b";
include	"lex.b";
include	"misc.b";
include	"serve.b";
include	"symb.b";
include	"xeq.b";

lib:		Mashlib;

initmash(ctxt: ref Draw->Context, top: ref Tk->Toplevel, s: Sys, e: ref Env, l: Mashlib, p: Mashparse)
{
	gctxt = ctxt;
	gtop = top;
	sys = s;
	lib = l;
	parse = p;
	if (top != nil) {
		tk =  load Tk Tk->PATH;
		if (tk == nil)
			e.couldnot("load", Tk->PATH);
	}
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil)
		e.couldnot("load", Bufio->PATH);
	hash = load Hash Hash->PATH;
	if (hash == nil)
		e.couldnot("load", Hash->PATH);
	str = load String String->PATH;
	if (str == nil)
		e.couldnot("load", String->PATH);
	initlex();
	empty = "no" :: "value" :: nil;
	startserve = 0;
}

nonexistent(e: string): int
{
	errs := array[] of {"does not exist", "directory entry not found"};
	for (i := 0; i < len errs; i++){
		j := len errs[i];
		if (j <= len e && e[len e-j:] == errs[i])
			return 1;
	}
	return 0;
}
