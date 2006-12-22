include	"sys.m";
include	"bufio.m";
include	"draw.m";
include	"hash.m";
include	"filepat.m";
include	"regex.m";
include	"sh.m";
include	"string.m";
include	"tk.m";

#
#	mash - Inferno make/shell
#
#	Bruce Ellis - 1Q 98
#

	Rin,
	Rout,
	Rappend,
	Rinout,
	Rcount
		: con iota;	# Redirections

	Icaret,
	Iicaret,
	Idollar,
	Idollarq,
	Imatch,
	Iword,
	Iexpr,
	Ibackq,
	Iquote,
	Iinpipe,
	Ioutpipe,
	Iredir
		: con iota;	# Items

	Csimple,
	Cseq,
	Cfor,
	Cif,
	Celse,
	Cwhile,
	Ccase,
	Ccases,
	Cmatched,
	Cdefeq,
	Ceq,
	Cfn,
	Crescue,
	Casync,
	Cgroup,
	Clistgroup,
	Csubgroup,
	Cnop,
	Cword,
	Clist,
	Ccaret,
	Chd,
	Clen,
	Cnot,
	Ctl,
	Ccons,
	Ceqeq,
	Cnoteq,
	Cmatch,
	Cpipe,
	Cdepend,
	Crule,
	Cprivate
		: con iota;	# Commands

	Svalue,
	Sfunc,
	Sbuiltin
		: con iota;	# Symbol types

Mashlib: module
{
	PATH:	con "/dis/lib/mashlib.dis";

	File: adt
	{
		in:	ref Bufio->Iobuf;
		name:	string;
		line:	int;
		eof:	int;
	};

	Src: adt
	{
		line:	int;
		file:	string;
	};

	Wquoted,
	Wexpand
		: con 1 << iota;

	Word: adt
	{
		text:	string;
		flags:	int;
		where:	Src;

		word:	fn(w: self ref Word, d: string): string;
	};

	Item: adt
	{
		op:		int;
		word:		ref Word;
		left, right:	ref Item;
		cmd:		ref Cmd;
		redir:		ref Redir;

		item1:		fn(op: int, l: ref Item): ref Item;
		item2:		fn(op: int, l, r: ref Item): ref Item;
		itemc:		fn(op: int, c: ref Cmd): ref Item;
		iteml:		fn(l: list of string): ref Item;
		itemr:		fn(op: int, i: ref Item): ref Item;
		itemw:		fn(s: string): ref Item;

		caret:		fn(i: self ref Item, e: ref Env): (string, list of string, int);
		ieval:		fn(i: self ref Item, e: ref Env): (string, list of string, int);
		ieval1:		fn(i: self ref Item, e: ref Env): ref Item;
		ieval2:		fn(i: self ref Item, e: ref Env): (string, list of string, int);
		reval:		fn(i: self ref Item, e: ref Env): (int, string);
		sword:		fn(i: self ref Item, e: ref Env): ref Item;
		text:		fn(i: self ref Item): string;
	};

	Redir: adt
	{
		op:	int;
		word:	ref Item;
	};

	Cmd: adt
	{
		op:		int;
		words:		cyclic list of ref Item;
		left, right:	cyclic ref Cmd;
		item:		cyclic ref Item;
		redirs:		cyclic list of ref Redir;
		value:		list of string;
		error:		int;

		cmd1:		fn(op: int, l: ref Cmd): ref Cmd;
		cmd2:		fn(op: int, l, r: ref Cmd): ref Cmd;
		cmd1i:		fn(op: int, l: ref Cmd, i: ref Item): ref Cmd;
		cmd1w:		fn(op: int, l: ref Cmd, w: list of ref Item): ref Cmd;
		cmde:		fn(c: self ref Cmd, op: int, l, r: ref Cmd): ref Cmd;
		cmdiw:		fn(op: int, i: ref Item, w: list of ref Item): ref Cmd;

		assign:		fn(c: self ref Cmd, e: ref Env, def: int);
		checkpipe:	fn(c: self ref Cmd, e: ref Env, f: int): int;
		cmdio:		fn(c: self ref Cmd, e: ref Env, i: ref Item);
		depend:		fn(c: self ref Cmd, e: ref Env);
		eeval:		fn(c: self ref Cmd, e: ref Env): (string, list of string);
		eeval1:		fn(c: self ref Cmd, e: ref Env): ref Cmd;
		eeval2:		fn(c: self ref Cmd, e: ref Env): (string, list of string, int);
		evaleq:		fn(c: self ref Cmd, e: ref Env): int;
		evalmatch:	fn(c: self ref Cmd, e: ref Env): int;
		mkcmd:		fn(c: self ref Cmd, e: ref Env, async: int): ref Cmd;
		quote:		fn(c: self ref Cmd, e: ref Env, back: int): ref Item;
		rotcases:	fn(c: self ref Cmd): ref Cmd;
		rule:		fn(c: self ref Cmd, e: ref Env);
		serve:		fn(c: self ref Cmd, e: ref Env, write: int): ref Item;
		simple:		fn(c: self ref Cmd, e: ref Env, wait: int);
		text:		fn(c: self ref Cmd): string;
		truth:		fn(c: self ref Cmd, e: ref Env): int;
		xeq:		fn(c: self ref Cmd, e: ref Env);
		xeqit:		fn(c: self ref Cmd, e: ref Env, wait: int);
	};

	Depend: adt
	{
		targets:	list of string;
		depends:	list of string;
		op:		int;
		cmd:		ref Cmd;
		mark:		int;
	};

	Target: adt
	{
		target:		string;
		depends:	list of ref Depend;

		find:		fn(s: string): ref Target;
	};

	Lhs: adt
	{
		text:	string;
		elems:	list of string;
		count:	int;
	};

	Rule: adt
	{
		lhs:	ref Lhs;
		rhs:	ref Item;
		op:	int;
		cmd:	ref Cmd;

		match:		fn(r: self ref Rule, a, n: int, t: list of string): int;
		matches:	fn(r: self ref Rule, t: list of string): array of string;
	};

	SHASH:	con 31;			# Symbol table hash size
	SMASK:	con 16r7FFFFFFF;	# Mask for SHASH bits

	Symb: adt
	{
		name:		string;
		value:		list of string;
		func:		ref Cmd;
		builtin:	Mashbuiltin;
		tag:		int;
	};

	Stab: adt
	{
		tab:		array of list of ref Symb;
		wmask:	int;
		copy:		int;

		new:		fn(): ref Stab;
		clone:		fn(t: self ref Stab): ref Stab;
		all:		fn(t: self ref Stab): list of ref Symb;
		assign:		fn(t: self ref Stab, s: string, v: list of string);
		defbuiltin:	fn(t: self ref Stab, s: string, b: Mashbuiltin);
		define:		fn(t: self ref Stab, s: string, f: ref Cmd);
		find:		fn(t: self ref Stab, s: string): ref Symb;
		func:		fn(t: self ref Stab, s: string): ref Cmd;
		update:		fn(t: self ref Stab, s: string, tag: int, v: list of string, f: ref Cmd, b: Mashbuiltin): ref Symb;
	};

	ETop, EInter, EEcho, ERaise, EDumping, ENoxeq:
		con 1 << iota;

	Env: adt
	{
		global:		ref Stab;
		local:		ref Stab;
		flags:		int;
		in, out:	ref Sys->FD;
		stderr:		ref Sys->FD;
		wait:		ref Sys->FD;
		file:		ref File;
		args:		array of string;
		level:		int;

		new:		fn(): ref Env;
		clone:		fn(e: self ref Env): ref Env;
		copy:		fn(e: self ref Env): ref Env;

		interactive:	fn(e: self ref Env, fd: ref Sys->FD);

		arg:		fn(e: self ref Env, s: string): string;
		builtin:	fn(e: self ref Env, s: string): Mashbuiltin;
		defbuiltin:	fn(e: self ref Env, s: string, b: Mashbuiltin);
		define:		fn(e: self ref Env, s: string, f: ref Cmd);
		dollar:		fn(e: self ref Env, s: string): ref Symb;
		func:		fn(e: self ref Env, s: string): ref Cmd;
		let:		fn(e: self ref Env, s: string, v: list of string);
		set:		fn(e: self ref Env, s: string, v: list of string);

		couldnot:	fn(e: self ref Env, what, who: string);
		diag:		fn(e: self ref Env, s: string): string;
		error:		fn(e: self ref Env, s: string);
		report:		fn(e: self ref Env, s: string);
		sopen:		fn(e: self ref Env, s: string);
		suck:		fn(e: self ref Env);
		undefined:	fn(e: self ref Env, s: string);
		usage:		fn(e: self ref Env, s: string);

		devnull:	fn(e: self ref Env): ref Sys->FD;
		fopen:		fn(e: self ref Env, fd: ref Sys->FD, s: string);
		outfile:	fn(e: self ref Env): ref Bufio->Iobuf;
		output:		fn(e: self ref Env, s: string);
		pipe:		fn(e: self ref Env): array of ref Sys->FD;
		runit:		fn(e: self ref Env, s: list of string, in, out: ref Sys->FD, wait: int);
		serve:		fn(e: self ref Env);
		servefd:	fn(e: self ref Env, fd: ref Sys->FD, write: int): string;
		servefile:	fn(e: self ref Env, n: string): (string, ref Sys->FileIO);

		doload:		fn(e: self ref Env, s: string);
		lex:		fn(e: self ref Env, y: ref Mashparse->YYSTYPE): int;
		mklist:		fn(e: self ref Env, l: list of ref Item): list of ref Item;
		mksimple:	fn(e: self ref Env, l: list of ref Item): ref Cmd;
	};

	initmash:	fn(ctxt: ref Draw->Context, top: ref Tk->Toplevel, s: Sys, e: ref Env, l: Mashlib, p: Mashparse);
	nonexistent:	fn(s: string): int;

	errstr:		fn(): string;
	exits:		fn(s: string);
	ident:		fn(s: string): int;
	initdep:	fn();
	prepareio:	fn(in, out: ref sys->FD): (int, ref Sys->FD);
	prprompt:	fn(n: int);
	quote:		fn(s: string): string;
	reap:		fn();
	revitems:	fn(l: list of ref Item): list of ref Item;
	revstrs:	fn(l: list of string): list of string;
	rulematch:	fn(s: string): list of ref Rule;

	ARGS:		con "args";
	BUILTINS:	con "builtins.dis";
	CHAN:		con "/chan";
	CONSOLE:	con "/dev/cons";
	DEVNULL:	con "/dev/null";
	EEXISTS:	con "file exists";
	EPIPE:		con "write on closed pipe";
	EXIT:		con "exit";
	FAILPAT:	con "fail:*";
	FAIL:		con "fail:";
	FAILLEN:	con len FAIL;
	HISTF:		con "history";
	LIB:		con "/dis/lib/mash/";
	MASHF:		con "mash";
	MASHINIT:	con "mashinit";
	PROFILE:	con "/lib/mashinit";
	TRUE:		con "true";
	MAXELEV:	con 256;

	sys:		Sys;
	bufio:		Bufio;
	filepat:	Filepat;
	hash:		Hash;
	regex:		Regex;
	str:		String;
	tk:		Tk;

	gctxt:		ref Draw->Context;
	gtop:		ref Tk->Toplevel;

	prompt:		string;
	contin:		string;

	empty:		list of string;

	PIDEXIT:	con 0;

	histchan:	chan of array of byte;
	inchan:		chan of array of byte;
	pidchan:	chan of int;
	servechan:	chan of array of byte;
	startserve:	int;

	rules:		list of ref Rule;
	dephash:	array of list of ref Target;

	parse:		Mashparse;
};

#
#	Interface to loadable builtin modules.  mashinit is called when a module
#	is loaded.  mashcmd is called for a builtin as defined by Env.defbuiltin().
#	init() is in the interface to catch the use of builtin modules as commands.
#	name() is used by whatis.
#
Mashbuiltin: module
{
	mashinit:	fn(l: list of string, lib: Mashlib, this: Mashbuiltin, e: ref Mashlib->Env);
	mashcmd:	fn(e: ref Mashlib->Env, l: list of string);
	init:		fn(ctxt: ref Draw->Context, args: list of string);
	name:		fn(): string;
};
