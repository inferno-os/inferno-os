Command: module
{
	PATH:	con "/dis/sh.dis";

	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Sh: module
{
	PATH: con "/dis/sh.dis";
	initialise:		fn();
	init:			fn(ctxt: ref Draw->Context, argv: list of string);
	system:		fn(drawctxt: ref Draw->Context, cmd: string): string;
	run:			fn(drawctxt: ref Draw->Context, argv: list of string): string;
	parse:		fn(s: string): (ref Cmd, string);
	cmd2string:	fn(c: ref Cmd): string;

	Context: adt {
		new:			fn(drawcontext: ref Draw->Context): ref Context;
		get:			fn(c: self ref Context, name: string): list of ref Listnode;
		set:			fn(c: self ref Context, name: string, val: list of ref Listnode);
		setlocal:		fn(c: self ref Context, name: string, val: list of ref Listnode);
		envlist:		fn(c: self ref Context): list of (string, list of ref Listnode);
		push:		fn(c: self ref Context);
		pop:			fn(c: self ref Context);
		copy:		fn(c: self ref Context, copyenv: int): ref Context;
		run:			fn(c: self ref Context, args: list of ref Listnode, last: int): string;
		addmodule:	fn(c: self ref Context, name: string, mod: Shellbuiltin);
		addbuiltin:	fn(c: self ref Context, name: string, mod: Shellbuiltin);
		removebuiltin:	fn(c: self ref Context, name: string, mod: Shellbuiltin);
		addsbuiltin:	fn(c: self ref Context, name: string, mod: Shellbuiltin);
		removesbuiltin: fn(c: self ref Context, name: string, mod: Shellbuiltin);
		fail:			fn(c: self ref Context, ename, msg: string);
		options:		fn(c: self ref Context): int;
		setoptions:	fn(c: self ref Context, flags, on: int): int;
		INTERACTIVE, VERBOSE, EXECPRINT, ERROREXIT: con 1 << iota;

		env:			ref Environment;
		waitfd:		ref Sys->FD;
		drawcontext:	ref Draw->Context;
		keepfds:		list of int;
	};

	list2stringlist:	fn(nl: list of ref Listnode): list of string;
	stringlist2list:	fn(sl: list of string): list of ref Listnode;
	quoted:		fn(val: list of ref Listnode, quoteblocks: int): string;

	initbuiltin:		fn(c: ref Context, sh: Sh): string;
	whatis:		fn(nil: ref Sh->Context, nil: Sh, nil: string, nil: int): string;
	runbuiltin:	fn(c: ref Context, sh: Sh, cmd: list of ref Listnode, last: int): string;
	runsbuiltin:	fn(c: ref Context, sh: Sh, cmd: list of ref Listnode): list of ref Listnode;
	getself: 		fn(): Shellbuiltin;
	Cmd: type Node;
	Node: adt {
		ntype: int;
		left, right: ref Node;
		word: string;
		redir: ref Redir;
	};
	Redir: adt {
		rtype: int;
		fd1, fd2: int;
	};
	Var: adt {
		name: string;
		val: list of ref Listnode;
		flags: int;
		CHANGED, NOEXPORT: con (1 << iota);
	};
	Environment: adt {
		sbuiltins: ref Builtins;
		builtins: ref Builtins;
		bmods: list of (string, Shellbuiltin);
		localenv: ref Localenv;
	};
	Localenv: adt {
		vars: array of list of ref Var;
		pushed: ref Localenv;
		flags: int;
	};
	Listnode: adt {
		cmd: ref Node;
		word: string;
	};
	Builtins: adt {
		ba: array of (string, list of Shellbuiltin);
		n: int;
	};
	# node types
	n_BLOCK,  n_VAR, n_BQ, n_BQ2, n_REDIR,
	n_DUP, n_LIST, n_SEQ, n_CONCAT, n_PIPE, n_ADJ,
	n_WORD, n_NOWAIT, n_SQUASH, n_COUNT,
	n_ASSIGN, n_LOCAL: con iota;
	GLOB: con 1;
};

Shellbuiltin: module {
	initbuiltin: fn(c: ref Sh->Context, sh: Sh): string;
	runbuiltin: fn(c: ref Sh->Context, sh: Sh,
			cmd: list of ref Sh->Listnode, last: int): string;
	runsbuiltin: fn(c: ref Sh->Context, sh: Sh,
			cmd: list of ref Sh->Listnode): list of ref Sh->Listnode;
	BUILTIN, SBUILTIN, OTHER: con iota;
	whatis: fn(c: ref Sh->Context, sh: Sh, name: string, wtype: int): string;
	getself: fn(): Shellbuiltin;
};
