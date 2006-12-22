Debug: module
{
	PATH:	con "/dis/lib/debug.dis";

	Terror, Tid, Tadt, Tadtpick, Tarray, Tbig, Tbyte, Tchan, Treal,
	Tfn, Targ, Tlocal, Tglobal, Tint, Tlist, Tmodule, Tnil, Tnone,
	Tref, Tstring, Ttuple, Tend, Targs, Tslice, Tpoly: con iota;

	Pos: adt
	{
		file:		string;
		line:		int;		# line number: origin 1
		pos:		int;		# character within the line: origin 0
	};
	Src: adt
	{
		start:		Pos;		# range within source files
		stop:		Pos;
	};
	Id: adt
	{
		src:		ref Src;
		name:		string;
		offset:		int;		# start of pc, offset in frame, etc
		stoppc:		int;		# limit pc of function
		t:		cyclic ref Type;
	};
	Type: adt
	{
		src:		ref Src;
		kind:		int;
		size:		int;
		name:		string;			# for adts, modules
		Of:		cyclic ref Type;	# for lists, arrays, etc.
		ids:		cyclic array of ref Id;	# for adts, etc. locals for fns
		tags:		cyclic array of ref Type;# for adts with pick tags

		text:		fn(t: self ref Type, sym: ref Sym): string;
		getkind:	fn(t: self ref Type, sym: ref Sym): int;
	};
	Sym: adt
	{
		path:		string;
		name:		string;		# implements name
		src:		array of ref Src;
		srcstmt:	array of int;
		adts:		array of ref Type;
		fns:		array of ref Id;
		vars:		array of ref Id;

		srctopc:	fn(s: self ref Sym, src: ref Src): int;
		pctosrc:	fn(s: self ref Sym, pc: int): ref Src;
	};

	Module: adt
	{
		path:	string;		# from whence loaded
		code:	int;		# address of code start
		data:	int;		# address of data
		comp:	int;		# compiled to native assembler?
		sym:	ref Sym;

		addsym:	fn(m: self ref Module, sym: ref Sym);
		stdsym:	fn(m: self ref Module);
		dis:	fn(m: self ref Module): string;
		sbl:	fn(m: self ref Module): string;
	};

	StepExp, StepStmt, StepOver, StepOut: con iota;
	Prog: adt
	{
		id:	int;
		heap:	ref Sys->FD;	# prog heap file
		ctl:	ref Sys->FD;	# prog control file
		dbgctl:	ref Sys->FD;	# debug file
		stk:	ref Sys->FD;	# stack file

		status:	fn(p: self ref Prog): (int, string, string, string);
		stack:	fn(p: self ref Prog): (array of ref Exp, string);
		step:	fn(p: self ref Prog, how: int): string;
		cont:	fn(p: self ref Prog): string;
		grab:	fn(p: self ref Prog): string;
		start:	fn(p: self ref Prog): string;
		stop:	fn(p: self ref Prog): string;
		unstop:	fn(p: self ref Prog): string;
		kill:	fn(p: self ref Prog): string;
		event:	fn(p: self ref Prog): string;
		setbpt:	fn(p: self ref Prog, dis: string, pc: int): string;
		delbpt:	fn(p: self ref Prog, dis: string, pc: int): string;
	};

	Exp: adt
	{
		name:	string;
		offset:	int;
		pc:	int;
		m:	ref Module;
		p:	ref Prog;

		# this is private
		id:	ref Id;

		expand:	fn(e: self ref Exp): array of ref Exp;
		val:	fn(e: self ref Exp): (string, int);
		typename:	fn(e: self ref Exp): string;
		kind: fn(e: self ref Exp): int;
		src:	fn(e: self ref Exp): ref Src;
		findsym:fn(e: self ref Exp): string;
		srcstr:	fn(e: self ref Exp): string;
	};

	init:		fn(): int;
	sym:		fn(sbl: string): (ref Sym, string);
	prog:	fn(pid: int): (ref Prog, string);
	startprog:	fn(dis, dir: string, ctxt: ref Draw->Context, argv: list of string): (ref Prog, string);
};
