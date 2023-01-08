%{
include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
include "string.m";
	str: String;
include "filepat.m";
	filepat: Filepat;
include "env.m";
	env: Env;
include "sh.m";
	myself: Sh;
	myselfbuiltin: Shellbuiltin;

YYSTYPE: adt {
	node:	ref Node;
	word:	string;

	redir:	ref Redir;
	optype:	int;
};

YYLEX: adt {
	lval:			YYSTYPE;
	err:			string;	# if error has occurred
	errline:		int;		# line it occurred on.
	path:			string;	# name of file that's being read.

	# free caret state
	wasdollar:		int;
	atendword:	int;
	eof:			int;
	cbuf:			array of int;	# last chars read
	ncbuf:		int;			# number of chars in cbuf

	f:			ref Bufio->Iobuf;
	s:			string;
	strpos: 		int;			# string pos/cbuf index

	linenum:		int;
	prompt:		string;
	lastnl:		int;

	initstring:		fn(s: string): ref YYLEX;
	initfile:		fn(fd: ref Sys->FD, path: string): ref YYLEX;
	lex:			fn(l: self ref YYLEX): int;
	error:		fn(l: self ref YYLEX, err: string);
	getc:			fn(l: self ref YYLEX): int;
	ungetc:		fn(l: self ref YYLEX);

	EOF:			con -1;
};

Options: adt {
	lflag,
	nflag:		int;
	ctxtflags:		int;
	carg:			string;
};

%}

%module Sh {
	# module definition is in shell.m
}

%token DUP REDIR WORD OP END ERROR ANDAND OROR

%type <node> redir word nlsimple simple cmd shell assign
%type <node> cmdsan cmdsa pipe comword line body list and2 or2
%type <redir> DUP REDIR '|'
%type <optype> OP '='
%type <word> WORD

%start shell
%%
shell:	line end		{yylex.lval.node = $line; return 0;}
	| error end		{yylex.lval.node = nil; return 0;}
end:	END
	| '\n'
line:	or2
	| cmdsa line		{$$ = mkseq($cmdsa, $line); }
body:	or2
	| cmdsan body		{$$ = mkseq($cmdsan, $body); }
cmdsa: 	or2  ';'		{$$ = $or2; }
	| or2 '&'			{$$ = ref Node(n_NOWAIT, $or2, nil, nil, nil); }
cmdsan:	cmdsa
	| or2 '\n'			{$$ = $or2; }
or2:	and2
	| or2 OROR and2 {
		$$ = mk(n_ADJ,
				mk(n_ADJ,
					ref Node(n_WORD,nil,nil,"or",nil),
					mk(n_BLOCK, $or2, nil)
				),
				mk(n_BLOCK,$and2,nil)
			);
	}
and2: pipe
	| and2 ANDAND pipe {
		$$ = mk(n_ADJ,
				mk(n_ADJ,
					ref Node(n_WORD,nil,nil,"and",nil),
					mk(n_BLOCK, $and2, nil)
				),
				mk(n_BLOCK,$pipe,nil)
			);
	}
pipe:					{$$ = nil;}
	| cmd
	| pipe '|' optnl cmd	{$$ = ref Node(n_PIPE, $pipe, $cmd, nil, $2); }
cmd:	simple
	| redir cmd		{$$ = mk(n_ADJ, $redir, $cmd); }
	| redir
	| assign
assign: word '=' assign	{$$ = mk($2, $word, $assign); }
	| word '=' simple	{$$ = mk($2, $word, $simple); }
	| word '='			{$$ = mk($2, $word, nil); }
redir:	DUP			{$$ = ref Node(n_DUP, nil, nil, nil, $DUP); }
	| REDIR word		{$$ = ref Node(n_REDIR, $word, nil, nil, $REDIR); }
simple:	word
	| simple word		{$$ = mk(n_ADJ, $simple, $word); }
	| simple redir		{$$ = mk(n_ADJ, $simple, $redir); }
list:	optnl			{$$ = nil;}
	| nlsimple optnl
nlsimple: optnl word		{$$ = $word; }
	| nlsimple optnl word	{$$ = mk(n_ADJ, $nlsimple, $word); }
	| nlsimple optnl redir  {$$ = mk(n_ADJ, $nlsimple, $redir); }
word:	comword
	| word '^' optnl comword	{$$ = mk(n_CONCAT, $word, $comword); }
comword: WORD		{$$ = ref Node(n_WORD, nil, nil, $WORD, nil); }
	| OP comword		{$$ = mk($OP, $comword, nil); }
	| '(' list ')'			{$$ = mk(n_LIST, $list, nil); }
	| '{' body '}'		{$$ = mk(n_BLOCK, $body, nil); }
optnl:  # null
	| optnl '\n'
%%

EPERM: con "permission denied";
EPIPE: con "write on closed pipe";

#SHELLRC: con "lib/profile";
LIBSHELLRC: con "/lib/sh/profile";
BUILTINPATH: con "/dis/sh";

DEBUG: con 0;

ENVSEP: con 0;				# word separator in external environment
ENVHASHSIZE: con 7;		# XXX profile usage of this...
OAPPEND: con 16r80000;		# make sure this doesn't clash with O* constants in sys.m
OMASK: con 7;

usage()
{
	sys->fprint(stderr(), "usage: sh [-ilexn] [-c command] [file [arg...]]\n");
	raise "fail:usage";
}

badmodule(path: string)
{
	sys->fprint(sys->fildes(2), "sh: cannot load %s: %r\n", path);
	raise "fail:bad module" ;
}

initialise()
{
	if (sys == nil) {
		sys = load Sys Sys->PATH;

		filepat = load Filepat Filepat->PATH;
		if (filepat == nil) badmodule(Filepat->PATH);

		str = load String String->PATH;
		if (str == nil) badmodule(String->PATH);

		bufio = load Bufio Bufio->PATH;
		if (bufio == nil) badmodule(Bufio->PATH);

		myself = load Sh "$self";
		if (myself == nil) badmodule("$self(Sh)");

		myselfbuiltin = load Shellbuiltin "$self";
		if (myselfbuiltin == nil) badmodule("$self(Shellbuiltin)");

		env = load Env Env->PATH;
	}
}
blankopts: Options;
init(drawcontext: ref Draw->Context, argv: list of string)
{
	initialise();
	opts := blankopts;
	if (argv != nil) {
		if ((hd argv)[0] == '-')
			opts.lflag++;
		argv = tl argv;
	}

	interactive := 0;
loop: while (argv != nil && hd argv != nil && (hd argv)[0] == '-') {
		for (i := 1; i < len hd argv; i++) {
			c := (hd argv)[i];
			case c {
			'i' =>
				interactive = Context.INTERACTIVE;
			'l' =>
				opts.lflag++;	# login (read $home/lib/profile)
			'n' =>
				opts.nflag++;	# don't fork namespace
			'e' =>
				opts.ctxtflags |= Context.ERROREXIT;
			'x' =>
				opts.ctxtflags |= Context.EXECPRINT;
			'c' =>
				arg: string;
				if (i < len hd argv - 1) {
					arg = (hd argv)[i + 1:];
				} else if (tl argv == nil || hd tl argv == "") {
					usage();
				} else {
					arg = hd tl argv;
					argv = tl argv;
				}
				argv = tl argv;
				opts.carg = arg;
				continue loop;
			}
		}
		argv = tl argv;
	}

	sys->pctl(Sys->FORKFD, nil);
	if (!opts.nflag)
		sys->pctl(Sys->FORKNS, nil);
	ctxt := Context.new(drawcontext);
	ctxt.setoptions(opts.ctxtflags, 1);
	if (opts.carg != nil) {
		status := ctxt.run(stringlist2list("{" + opts.carg + "}" :: argv), !interactive);
		if (!interactive) {
			if (status != nil)
				raise "fail:" + status;
			exit;
		}
		setstatus(ctxt, status);
	}

	# if login shell, run standard init script
	if (opts.lflag)
		runscript(ctxt, LIBSHELLRC, nil, 0);

	if (argv == nil) {
#		if (opts.lflag)
#			runscript(ctxt, SHELLRC, nil, 0);
		if (isconsole(sys->fildes(0)))
			interactive |= ctxt.INTERACTIVE;
		ctxt.setoptions(interactive, 1);
		runfile(ctxt, sys->fildes(0), "stdin", nil);
	} else {
		ctxt.setoptions(interactive, 1);
		runscript(ctxt, hd argv, stringlist2list(tl argv), 1);
	}
}

# XXX should this refuse to parse a non braced-block?
parse(s: string): (ref Node, string)
{
	initialise();
	
	lex := YYLEX.initstring(s);

	return doparse(lex, "", 0);
}

system(drawctxt: ref Draw->Context, cmd: string): string
{
	initialise();
	{
		(n, err) := parse(cmd);
		if (err != nil)
			return err;
		if (n == nil)
			return nil;
		return Context.new(drawctxt).run(ref Listnode(n, nil) :: nil, 0);
	} exception e {
	"fail:*" =>
		return failurestatus(e);
	}
}

run(drawctxt: ref Draw->Context, argv: list of string): string
{
	initialise();
	{
		return Context.new(drawctxt).run(stringlist2list(argv), 0);
	} exception e {
	"fail:*" =>
		return failurestatus(e);
	}
}

isconsole(fd: ref Sys->FD): int
{
	(ok1, d1) := sys->fstat(fd);
	(ok2, d2) := sys->stat("/dev/cons");
	if (ok1 < 0 || ok2 < 0)
		return 0;
	return d1.dtype == d2.dtype && d1.qid.path == d2.qid.path;
}

# run commands from file _path_
runscript(ctxt: ref Context, path: string, args: list of ref Listnode, reporterr: int)
{
	{
		fd := sys->open(path, Sys->OREAD);
		if (fd != nil)
			runfile(ctxt, fd, path, args);
		else if (reporterr)
			ctxt.fail("bad script path", sys->sprint("sh: cannot open %s: %r", path));
	} exception {
	"fail:*" =>
		if(!reporterr)
			return;
		raise;
	}
}

# run commands from the opened file fd.
# if interactive is non-zero, print a command prompt at appropriate times.
runfile(ctxt: ref Context, fd: ref Sys->FD, path: string, args: list of ref Listnode)
{
	ctxt.push();
	{
		ctxt.setlocal("0", stringlist2list(path :: nil));
		ctxt.setlocal("*", args);
		lex := YYLEX.initfile(fd, path);
		if (DEBUG) debug(sprint("parse(interactive == %d)", (ctxt.options() & ctxt.INTERACTIVE) != 0));
		prompt := "" :: "" :: nil;
		laststatus: string;
		while (!lex.eof) {
			interactive := ctxt.options() & ctxt.INTERACTIVE;
			if (interactive) {
				prompt = list2stringlist(ctxt.get("prompt"));
				if (prompt == nil)
					prompt = "; " :: "" :: nil;
	
				sys->fprint(stderr(), "%s", hd prompt);
				if (tl prompt == nil) {
					prompt = hd prompt :: "" :: nil;
				}
			}
			(n, err) := doparse(lex, hd tl prompt, !interactive);
			if (err != nil) {
				sys->fprint(stderr(), "sh: %s\n", err);
				if (!interactive)
					raise "fail:parse error";
			} else if (n != nil) {
				if (interactive) {
					{
						laststatus = walk(ctxt, n, 0);
					} exception e2 {
					"fail:*" =>
						laststatus = failurestatus(e2);
					}
				} else
					laststatus = walk(ctxt, n, 0);
				setstatus(ctxt, laststatus);
				if ((ctxt.options() & ctxt.ERROREXIT) && laststatus != nil)
					break;
			}
		}
		if (laststatus != nil)
			raise "fail:" + laststatus;
		ctxt.pop();
	}
	exception {
	"fail:*" =>
		ctxt.pop();
		raise;
	}
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

Redirword: adt {
	fd: ref Sys->FD;
	w: string;
	r: Redir;
};

Redirlist: adt {
	r: list of Redirword;
};

# a hack so that the structure of walk() doesn't change much
# to accomodate echo|wc&
# transform the above into {echo|wc}$*&
# which should amount to exactly the same thing.
pipe2cmd(n: ref Node): ref Node
{
	if (n == nil || n.ntype != n_PIPE)
		return n;
	return mk(n_ADJ, mk(n_BLOCK,n,nil), mk(n_VAR,ref Node(n_WORD,nil,nil,"*",nil),nil));
}

# walk a node tree.
# last is non-zero if this walk is the last action
# this shell process will take before exiting (i.e. redirections
# don't require a new process to avoid side effects)
walk(ctxt: ref Context, n: ref Node, last: int): string
{
	if (DEBUG) debug(sprint("walking: %s", cmd2string(n)));
	# avoid tail recursion stack explosion
	while (n != nil && n.ntype == n_SEQ) {
		status := walk(ctxt, n.left, 0);
		if (ctxt.options() & ctxt.ERROREXIT && status != nil)
			raise "fail:" + status;
		setstatus(ctxt, status);
		n = n.right;
	}
	if (n == nil)
		return nil;
	case (n.ntype) {
	n_PIPE =>
		return waitfor(ctxt, walkpipeline(ctxt, n, nil, -1));
	n_ASSIGN or n_LOCAL =>
		assign(ctxt, n);
		return nil;
	* =>
		bg := 0;
		if (n.ntype == n_NOWAIT) {
			bg = 1;
			n = pipe2cmd(n.left);
		}

		redirs := ref Redirlist(nil);
		line := glob(glom(ctxt, n, redirs, nil));

		if (bg) {
			startchan := chan of (int, ref Expropagate);
			spawn runasync(ctxt, 1, line, redirs, startchan);
			(pid, nil) := <-startchan;
			redirs = nil;
			if (DEBUG) debug("started background process "+ string pid);
			ctxt.set("apid", ref Listnode(nil, string pid) :: nil);
			return nil;
		} else {
			return runsync(ctxt, line, redirs, last);
		}
	}
}

assign(ctxt: ref Context, n: ref Node): list of ref Listnode
{
	redirs := ref Redirlist;
	val: list of ref Listnode;
	if (n.right != nil && (n.right.ntype == n_ASSIGN || n.right.ntype == n_LOCAL))
		val = assign(ctxt, n.right);
	else
		val = glob(glom(ctxt, n.right, redirs, nil));
	vars := glom(ctxt, n.left, redirs, nil);
	if (vars == nil)
		ctxt.fail("bad assign", "sh: nil variable name");
	if (redirs.r != nil)
		ctxt.fail("bad assign", "sh: redirections not allowed in assignment");
	tval := val;
	for (; vars != nil; vars = tl vars) {
		vname := deglob((hd vars).word);
		if (vname == nil) 
			ctxt.fail("bad assign", "sh: bad variable name");
		v: list of ref Listnode = nil;
		if (tl vars == nil)
			v = tval;
		else if (tval != nil)
			v = hd tval :: nil;
		if (n.ntype == n_ASSIGN)
			ctxt.set(vname, v);
		else
			ctxt.setlocal(vname, v);
		if (tval != nil)
			tval = tl tval;
	}
	return val;
}

walkpipeline(ctxt: ref Context, n: ref Node, wrpipe: ref Sys->FD, wfdno: int): list of int
{
	if (n == nil)
		return nil;

	fds := array[2] of ref Sys->FD;
	pids: list of int;
	rfdno := -1;
	if (n.ntype == n_PIPE) {
		if (sys->pipe(fds) == -1)
			ctxt.fail("no pipe", sys->sprint("sh: cannot make pipe: %r"));
		nwfdno := -1;
		if (n.redir != nil) {
			(fd1, fd2) := (n.redir.fd2, n.redir.fd1);
			if (fd2 == -1)
				(fd1, fd2) = (fd2, fd1);
			(nwfdno, rfdno) = (fd2, fd1);
		}
		pids = walkpipeline(ctxt, n.left, fds[1], nwfdno);
		fds[1] = nil;
		n = n.right;
	}
	r := ref Redirlist(nil);
	rlist := glob(glom(ctxt, n, r, nil));
	if (fds[0] != nil) {
		if (rfdno == -1)
			rfdno = 0;
		r.r = Redirword(fds[0], nil, Redir(Sys->OREAD, rfdno, -1)) :: r.r;
	}
	if (wrpipe != nil) {
		if (wfdno == -1)
			wfdno = 1;
		r.r = Redirword(wrpipe, nil, Redir(Sys->OWRITE, wfdno, -1)) :: r.r;
	}
	startchan := chan of (int, ref Expropagate);
	spawn runasync(ctxt, 1, rlist, r, startchan);
	(pid, nil) := <-startchan;
	if (DEBUG) debug("started pipe process "+string pid);
	return pid :: pids;
}

makeredir(f: string, mode: int, fd: int): Redirword
{
	return Redirword(nil, f, Redir(mode, fd, -1));
}

# expand substitution operators in a node list
glom(ctxt: ref Context, n: ref Node, redirs: ref Redirlist, onto: list of ref Listnode)
		: list of ref Listnode
{
	if (n == nil) return nil;

	if (n.ntype != n_ADJ)
		return listjoin(glomoperation(ctxt, n, redirs), onto);

	nlist := glom(ctxt, n.right, redirs, onto);

	if (n.left.ntype != n_ADJ) {
		# if it's a terminal node
		nlist = listjoin(glomoperation(ctxt, n.left, redirs), nlist);
	} else
		nlist = glom(ctxt, n.left, redirs, nlist);
	return nlist;
}

listjoin(left, right: list of ref Listnode): list of ref Listnode
{
	l: list of ref Listnode;
	for (; left != nil; left = tl left)
		l = hd left :: l;
	for (; l != nil; l = tl l)
		right = hd l :: right;
	return right;
}

pipecmd(ctxt: ref Context, cmd: list of ref Listnode, redir: ref Redir): ref Sys->FD
{
	if(redir.fd2 != -1 || (redir.rtype & OAPPEND))
		ctxt.fail("bad redir", "sh: bad redirection");
	r := *redir;
	case redir.rtype {
	Sys->OREAD =>
		r.rtype = Sys->OWRITE;
	Sys->OWRITE =>
		r.rtype = Sys->OREAD;
	}
			
	p := array[2] of ref Sys->FD;
	if(sys->pipe(p) == -1)
		ctxt.fail("no pipe", sys->sprint("sh: cannot make pipe: %r"));
	startchan := chan of (int, ref Expropagate);
	spawn runasync(ctxt, 1, cmd, ref Redirlist((p[1], nil, r) :: nil), startchan);
	p[1] = nil;
	<-startchan;
	return p[0];
}

glomoperation(ctxt: ref Context, n: ref Node, redirs: ref Redirlist): list of ref Listnode
{
	if (n == nil)
		return nil;

	nlist: list of ref Listnode;
	case n.ntype {
	n_WORD =>
		nlist = ref Listnode(nil, n.word) :: nil;
	n_REDIR =>
		wlist := glob(glom(ctxt, n.left, ref Redirlist(nil), nil));
		if (len wlist != 1)
			ctxt.fail("bad redir", "sh: single redirection operand required");
		if((hd wlist).cmd != nil){
			fd := pipecmd(ctxt, wlist, n.redir);
			redirs.r = Redirword(fd, nil, (n.redir.rtype, fd.fd, -1)) :: redirs.r;
			nlist = ref Listnode(nil, "/fd/"+string fd.fd) :: nil;
		}else{
			redirs.r = Redirword(nil, (hd wlist).word, *n.redir) :: redirs.r;
		}
	n_DUP =>
		redirs.r = Redirword(nil, "", *n.redir) :: redirs.r;
	n_LIST =>
		nlist = glom(ctxt, n.left, redirs, nil);
	n_CONCAT =>
		nlist = concat(ctxt, glom(ctxt, n.left, redirs, nil), glom(ctxt, n.right, redirs, nil));
	n_VAR or n_SQUASH or n_COUNT =>
		arg := glom(ctxt, n.left, ref Redirlist(nil), nil);
		if (len arg == 1 && (hd arg).cmd != nil)
			nlist = subsbuiltin(ctxt, (hd arg).cmd.left);
		else if (len arg != 1 || (hd arg).word == nil)
			ctxt.fail("bad $ arg", "sh: bad variable name");
		else
			nlist = ctxt.get(deglob((hd arg).word));
		case n.ntype {
		n_VAR =>;
		n_COUNT =>
			nlist = ref Listnode(nil, string len nlist) :: nil;
		n_SQUASH =>
			# XXX could squash with first char of $ifs, perhaps
			nlist = ref Listnode(nil, squash(list2stringlist(nlist), " ")) :: nil;
		}
	n_BQ or n_BQ2 =>
		arg := glom(ctxt, n.left, ref Redirlist(nil), nil);
		seps := "";
		if (n.ntype == n_BQ) {
			seps = squash(list2stringlist(ctxt.get("ifs")), "");
			if (seps == nil)
				seps = " \t\n\r";
		}
		(nlist, nil) = bq(ctxt, glob(arg), seps);
	n_BLOCK =>
		nlist = ref Listnode(n, "") :: nil;
	n_ASSIGN or n_LOCAL =>
		ctxt.fail("bad assign", "sh: assignment in invalid context");
	* =>
		panic("bad node type "+string n.ntype+" in glomop");
	}
	return nlist;
}

subsbuiltin(ctxt: ref Context, n: ref Node): list of ref Listnode
{
	if (n == nil || n.ntype == n_SEQ ||
			n.ntype == n_PIPE || n.ntype == n_NOWAIT)
		ctxt.fail("bad $ arg", "sh: invalid argument to ${} operator");
	r := ref Redirlist;
	cmd := glob(glom(ctxt, n, r, nil));
	if (r.r != nil)
		ctxt.fail("bad $ arg", "sh: redirection not allowed in substitution");
	r = nil;
	if (cmd == nil || (hd cmd).word == nil || (hd cmd).cmd != nil)
		ctxt.fail("bad $ arg", "sh: bad builtin name");

	(nil, bmods) := findbuiltin(ctxt.env.sbuiltins, (hd cmd).word);
	if (bmods == nil)
		ctxt.fail("builtin not found",
			sys->sprint("sh: builtin %s not found", (hd cmd).word));
	return (hd bmods)->runsbuiltin(ctxt, myself, cmd);
}

#
# backquote substitution (could be done in a builtin)
#

getbq(nil: ref Context, fd: ref Sys->FD, seps: string): list of ref Listnode
{
	buf := array[Sys->ATOMICIO] of byte;
	buflen := 0;
	while ((n := sys->read(fd, buf[buflen:], len buf - buflen)) > 0) {
		buflen += n;
		if (buflen == len buf) {
			nbuf := array[buflen * 2] of byte;
			nbuf[0:] = buf[0:];
			buf = nbuf;
		}
	}
	l: list of string;
	if (seps != nil)
		(nil, l) = sys->tokenize(string buf[0:buflen], seps);
	else
		l = string buf[0:buflen] :: nil;
	buf = nil;
	return stringlist2list(l);
}

bq(ctxt: ref Context, cmd: list of ref Listnode, seps: string): (list of ref Listnode, string)
{
	fds := array[2] of ref Sys->FD;
	if (sys->pipe(fds) == -1)
		ctxt.fail("no pipe", sys->sprint("sh: cannot make pipe: %r"));

	r := rdir(fds[1]);
	fds[1] = nil;
	startchan := chan of (int, ref Expropagate);
	spawn runasync(ctxt, 0, cmd, r, startchan);
	(exepid, exprop) := <-startchan;
	r = nil;
	bqlist := getbq(ctxt, fds[0], seps);
	waitfor(ctxt, exepid :: nil);
	if (exprop.name != nil)
		raise exprop.name;
	return (bqlist, nil);
}

# get around compiler temporaries bug
rdir(fd: ref Sys->FD): ref Redirlist
{
	return  ref Redirlist(Redirword(fd, nil, Redir(Sys->OWRITE, 1, -1)) :: nil);
}

#
# concatenation
#

concatwords(p1, p2: ref Listnode): ref Listnode
{
	if (p1.word == nil && p1.cmd != nil)
		p1.word = cmd2string(p1.cmd);
	if (p2.word == nil && p2.cmd != nil)
		p2.word = cmd2string(p2.cmd);
	return ref Listnode(nil, p1.word + p2.word);
}

concat(ctxt: ref Context, nl1, nl2: list of ref Listnode): list of ref Listnode
{
	if (nl1 == nil || nl2 == nil) {
		if (nl1 == nil && nl2 == nil)
			return nil;
		ctxt.fail("bad concatenation", "sh: null list in concatenation");
	}

	ret: list of ref Listnode;
	if (tl nl1 == nil || tl nl2 == nil) {
		for (p1 := nl1; p1 != nil; p1 = tl p1)
			for (p2 := nl2; p2 != nil; p2 = tl p2)
				ret = concatwords(hd p1, hd p2) :: ret;
	} else {
		if (len nl1 != len nl2)
			ctxt.fail("bad concatenation", "sh: lists of differing sizes can't be concatenated");
		while (nl1 != nil) {
			ret = concatwords(hd nl1, hd nl2) :: ret;
			(nl1, nl2) = (tl nl1, tl nl2);
		}
	}
	return revlist(ret);
}

Expropagate: adt {
	name: string;
};

# run an asynchronous process, first redirecting its I/O
# as specified in _redirs_.
# it sends its process ID down _startchan_ before executing.
# it has to jump through one or two hoops to make sure
# Sys->FD ref counting is done correctly. this code
# is more sensitive than you might think.
runasync(ctxt: ref Context, copyenv: int, argv: list of ref Listnode, redirs: ref Redirlist,
		startchan: chan of (int, ref Expropagate))
{
	status: string;

	pid := sys->pctl(sys->FORKFD, nil);
	if (DEBUG) debug(sprint("in async (len redirs: %d)", len redirs.r));
	ctxt = ctxt.copy(copyenv);
	exprop := ref Expropagate;
	{
		newfdl := doredirs(ctxt, redirs);
		redirs = nil;
		if (newfdl != nil)
			sys->pctl(Sys->NEWFD, newfdl);
		# stop the old waitfd from holding the intermediate
		# file descriptor group open.
		ctxt.waitfd = waitfd();
		# N.B. it's important that the sync is done here, not
		# before doredirs, as otherwise there's some sort of
		# race condition that leads to pipe non-completion.
		startchan <-= (pid, exprop);
		startchan = nil;
		status = ctxt.run(argv, copyenv);
	} exception e {
	"fail:*" =>
		exprop.name = e;
		if (startchan != nil)
			startchan <-= (pid, exprop);
		raise e;
	}
	if (status != nil) {
		# don't propagate bad status as an exception.
		raise "fail:" + status;
	}
}

# run a synchronous process
runsync(ctxt: ref Context, argv: list of ref Listnode,
		redirs: ref Redirlist, last: int): string
{
	if (DEBUG) debug(sys->sprint("in sync (len redirs: %d; last: %d)", len redirs.r, last));
	if (redirs.r != nil && !last) {
		# a new process is required to shield redirection side effects
		startchan := chan of (int, ref Expropagate);
		spawn runasync(ctxt, 0, argv, redirs, startchan);
		(pid, exprop) := <-startchan;
		redirs = nil;
		r := waitfor(ctxt, pid :: nil);
		if (exprop.name != nil)
			raise exprop.name;
		return r;
	} else {
		newfdl := doredirs(ctxt, redirs);
		redirs = nil;
		if (newfdl != nil)
			sys->pctl(Sys->NEWFD, newfdl);
		return ctxt.run(argv, last);
	}
}

# path is prefixed with: "/", "#", "./" or "../"
absolute(p: string): int
{
	if (len p < 2)
		return 0;
	if (p[0] == '/' || p[0] == '#')
		return 1;
	if (len p < 3 || p[0] != '.')
		return 0;
	if (p[1] == '/')
		return 1;
	if (p[1] == '.' && p[2] == '/')
		return 1;
	return 0;
}

runexternal(ctxt: ref Context, args: list of ref Listnode, last: int): string
{
	progname := (hd args).word;
	disfile := 0;
	if (len progname >= 4 && progname[len progname-4:] == ".dis")
		disfile = 1;
	pathlist: list of string;
	if (absolute(progname))
		pathlist = list of {""};
	else if ((pl := ctxt.get("path")) != nil)
		pathlist = list2stringlist(pl);
	else
		pathlist = list of {"/dis", "."};

	err := "";
	do {
		path: string;
		if (hd pathlist != "")
			path = hd pathlist + "/" + progname;
		else
			path = progname;

		npath := path;
		if (!disfile)
			npath += ".dis";
		mod := load Command npath;
		if (mod != nil) {
			argv := list2stringlist(args);
			export(ctxt.env.localenv);

			if (last) {
				{
					sys->pctl(Sys->NEWFD, ctxt.keepfds);
					mod->init(ctxt.drawcontext, argv);
					exit;
				} exception e {
				EPIPE =>
					return EPIPE;
				"fail:*" =>
					return failurestatus(e);
				}
			}
			extstart := chan of int;
			spawn externalexec(mod, ctxt.drawcontext, argv, extstart, ctxt.keepfds);
			pid := <-extstart;
			if (DEBUG) debug("started external externalexec; pid is "+string pid);
			return waitfor(ctxt, pid :: nil);
		}
		err = sys->sprint("%r");
		if (nonexistent(err)) {
			# try and run it as a shell script
			if (!disfile && (fd := sys->open(path, Sys->OREAD)) != nil) {
				(ok, info) := sys->fstat(fd);
				# make permission checking more accurate later
				if (ok == 0 && (info.mode & Sys->DMDIR) == 0
						&& (info.mode & 8r111) != 0)
					return runhashpling(ctxt, fd, path, tl args, last);
			};
			err = sys->sprint("%r");
		}
		pathlist = tl pathlist;
	} while (pathlist != nil && nonexistent(err));
	diagnostic(ctxt, sys->sprint("%s: %s", progname, err));
	return err;
}

failurestatus(e: string): string
{
	s := e[5:];
	while(s != nil && (s[0] == ' ' || s[0] == '\t'))
		s = s[1:];
	if(s != nil)
		return s;
	return "failed";
}

runhashpling(ctxt: ref Context, fd: ref Sys->FD,
		path: string, argv: list of ref Listnode, last: int): string
{
	header := array[1024] of byte;
	n := sys->read(fd, header, len header);
	for (i := 0; i < n; i++)
		if (header[i] == byte '\n')
			break;
	if (i == n || i < 3 || header[0] != byte('#') || header[1] != byte('!')) {
		diagnostic(ctxt, "bad script header on " + path);
		return "bad header";
	}
	(nil, args) := sys->tokenize(string header[2:i], " \t");
	if (args == nil) {
		diagnostic(ctxt, "empty header on " + path);
		return "bad header";
	}
	header = nil;
	fd = nil;
	nargs: list of ref Listnode;
	for (; args != nil; args = tl args)
		nargs = ref Listnode(nil, hd args) :: nargs;
	nargs = ref Listnode(nil, path) :: nargs;
	for (; argv != nil; argv = tl argv)
		nargs = hd argv :: nargs;
	return runexternal(ctxt, revlist(nargs), last);
}

runblock(ctxt: ref Context, args: list of ref Listnode, last: int): string
{
	# block execute (we know that hd args represents a block)
	cmd := (hd args).cmd;
	if (cmd == nil) {
		# parse block from first argument
		lex := YYLEX.initstring((hd args).word);

		err: string;
		(cmd, err) = doparse(lex, "", 0);
		if (cmd == nil)
			ctxt.fail("parse error", "sh: "+err);

		(hd args).cmd = cmd;
	}
	# now we've got a parsed block
	ctxt.push();
	{
		ctxt.setlocal("0", hd args :: nil);
		ctxt.setlocal("*", tl args);
		if (cmd != nil && cmd.ntype == n_BLOCK)
			cmd = cmd.left;
		status := walk(ctxt, cmd, last);
		ctxt.pop();
		return status;
	} exception {
	"fail:*" =>
		ctxt.pop();
		raise;
	}
}

# return (ok, val) where ok is non-zero is builtin was found,
# val is return status of builtin
trybuiltin(ctxt: ref Context, args: list of ref Listnode, lseq: int)
		: (int, string)
{
	(nil, bmods) := findbuiltin(ctxt.env.builtins, (hd args).word);
	if (bmods == nil)
		return (0, nil);
	return (1, (hd bmods)->runbuiltin(ctxt, myself, args, lseq));
}

keepfdstr(ctxt: ref Context): string
{
	s := "";
	for (f := ctxt.keepfds; f != nil; f = tl f) {
		s += string hd f;
		if (tl f != nil)
			s += ",";
	}
	return s;
}

externalexec(mod: Command,
		drawcontext: ref Draw->Context, argv: list of string, startchan: chan of int, keepfds: list of int)
{
	if (DEBUG) debug(sprint("externalexec(%s,... [%d args])", hd argv, len argv));
	sys->pctl(Sys->NEWFD, keepfds);
	startchan <-= sys->pctl(0, nil);
	{
		mod->init(drawcontext, argv);
	}
	exception {
	EPIPE =>
		raise "fail:" + EPIPE;
	}
}

dup(ctxt: ref Context, fd1, fd2: int): int
{
	# shuffle waitfd out of the way if it's being attacked
	if (ctxt.waitfd.fd == fd2) {
		ctxt.waitfd = waitfd();
		if (ctxt.waitfd.fd == fd2)
			panic(sys->sprint("reopen of waitfd gave same fd (%d)", ctxt.waitfd.fd));
	}
	return sys->dup(fd1, fd2);
}

# with thanks to tiny/sh.b
# return error status if redirs failed
doredirs(ctxt: ref Context, redirs: ref Redirlist): list of int
{
	if (redirs.r == nil)
		return nil;
	keepfds := ctxt.keepfds;
	rl := redirs.r;
	redirs = nil;
	for (; rl != nil; rl = tl rl) {
		(rfd, path, (mode, fd1, fd2)) := hd rl;
		if (path == nil && rfd == nil) {
			# dup
			if (fd1 == -1 || fd2 == -1)
				ctxt.fail("bad redir", "sh: invalid dup");

			if (dup(ctxt, fd2, fd1) == -1)
				ctxt.fail("bad redir", sys->sprint("sh: cannot dup: %r"));
			keepfds = fd1 :: keepfds;
			continue;
		}
		# redir
		if (fd1 == -1) {
			if ((mode & OMASK) == Sys->OWRITE)
				fd1 = 1;
			else
				fd1 = 0;
		}
		if (rfd == nil) {
			(append, omode) := (mode & OAPPEND, mode & ~OAPPEND);
			err := "";
			case mode {
			Sys->OREAD =>
				rfd = sys->open(path, omode);
			Sys->OWRITE | OAPPEND or
			Sys->ORDWR =>
				rfd = sys->open(path, omode);
				err = sprint("%r");
				if (rfd == nil && nonexistent(err)) {
					rfd = sys->create(path, omode, 8r666);
					err = nil;
				}
			Sys->OWRITE =>
				rfd = sys->create(path, omode, 8r666);
				err = sprint("%r");
				if (rfd == nil && err == EPERM) {
					# try open; can't create on a file2chan (pipe)
					rfd = sys->open(path, omode);
					nerr := sprint("%r");
					if(!nonexistent(nerr))
						err = nerr;
				}
			}
			if (rfd == nil) {
				if (err == nil)
					err = sprint("%r");
				ctxt.fail("bad redir", sys->sprint("sh: cannot open %s: %s", path, err));
			}
			if (append)
				sys->seek(rfd, big 0, Sys->SEEKEND);	# not good enough, but alright for some purposes.
		}
		# XXX what happens if rfd.fd == fd1?
		# it probably gets closed automatically... which is not what we want!
		dup(ctxt, rfd.fd, fd1);
		keepfds = fd1 :: keepfds;
	}
	ctxt.keepfds = keepfds;
	return ctxt.waitfd.fd :: keepfds;
}

#
# waiter utility routines
#

waitfd(): ref Sys->FD
{
	wf := string sys->pctl(0, nil) + "/wait";
	waitfd := sys->open("#p/"+wf, Sys->OREAD);
	if (waitfd == nil)
		waitfd = sys->open("/prog/"+wf, Sys->OREAD);
	if (waitfd == nil)
		panic(sys->sprint("cannot open wait file: %r"));
	return waitfd;
}

waitfor(ctxt: ref Context, pids: list of int): string
{
	if (pids == nil)
		return nil;
	status := array[len pids] of string;
	wcount := len status;
	buf := array[Sys->WAITLEN] of byte;
	onebad := 0;
	for(;;){
		n := sys->read(ctxt.waitfd, buf, len buf);
		if(n < 0)
			panic(sys->sprint("error on wait read: %r"));
		(who, line, s) := parsewaitstatus(ctxt, string buf[0:n]);
		if (s != nil) {
			if (len s >= 5 && s[0:5] == "fail:")
				s = failurestatus(s);
			else
				diagnostic(ctxt, line);
		}
		for ((i, pl) := (0, pids); pl != nil; (i, pl) = (i+1, tl pl))
			if (who == hd pl)
				break;
		if (i < len status) {
			# wait returns two records for a killed process...
			if (status[i] == nil || s != "killed") {
				onebad += s != nil;
				status[i] = s;
				if (wcount-- <= 1)
					break;
			}
		}
	}
	if (!onebad)
		return nil;
	r := status[len status - 1];
	for (i := len status - 2; i >= 0; i--)
		r += "|" + status[i];
	return r;
}

parsewaitstatus(ctxt: ref Context, status: string): (int, string, string)
{
	for (i := 0; i < len status; i++)
		if (status[i] == ' ')
			break;
	if (i == len status - 1 || status[i+1] != '"')
		ctxt.fail("bad wait read",
			sys->sprint("sh: bad exit status '%s'", status));

	for (i+=2; i < len status; i++)
		if (status[i] == '"')
			break;
	if (i > len status - 2 || status[i+1] != ':')
		ctxt.fail("bad wait read",
			sys->sprint("sh: bad exit status '%s'", status));

	return (int status, status, status[i+2:]);
}

panic(s: string)
{
	sys->fprint(stderr(), "sh panic: %s\n", s);
	raise "panic";
}

diagnostic(ctxt: ref Context, s: string)
{
	if (ctxt.options() & Context.VERBOSE)
		sys->fprint(stderr(), "sh: %s\n", s);
}

#
# Sh environment stuff
#

Context.new(drawcontext: ref Draw->Context): ref Context
{
	initialise();
	if (env != nil)
		env->clone();
	ctxt := ref Context(
		ref Environment(
			ref Builtins(nil, 0),
			ref Builtins(nil, 0),
			nil,
			newlocalenv(nil)
		),
		waitfd(),
		drawcontext,
		0 :: 1 :: 2 :: nil
	);
	myselfbuiltin->initbuiltin(ctxt, myself);
	ctxt.env.localenv.flags = ctxt.VERBOSE;
	for (vl := ctxt.get("autoload"); vl != nil; vl = tl vl)
		if ((hd vl).cmd == nil && (hd vl).word != nil)
			loadmodule(ctxt, (hd vl).word);
	return ctxt;
}

Context.copy(ctxt: self ref Context, copyenv: int): ref Context
{
	# XXX could check to see that we are definitely in a
	# new process, because there'll be problems if not (two processes
	# simultaneously reading the same wait file)
	nctxt := ref Context(ctxt.env, waitfd(), ctxt.drawcontext, ctxt.keepfds);
			
	if (copyenv) {
		if (env != nil)
			env->clone();
		nctxt.env = ref Environment(
			copybuiltins(ctxt.env.sbuiltins),
			copybuiltins(ctxt.env.builtins),
			ctxt.env.bmods,
			copylocalenv(ctxt.env.localenv)
		);
	}
	return nctxt;
}

Context.set(ctxt: self ref Context, name: string, val: list of ref Listnode)
{
	e := ctxt.env.localenv;
	idx := hashfn(name, len e.vars);
	for (;;) {
		v := hashfind(e.vars, idx, name);
		if (v == nil) {
			if (e.pushed == nil) {
				flags := Var.CHANGED;
				if (noexport(name))
					flags |= Var.NOEXPORT;
				hashadd(e.vars, idx, ref Var(name, val, flags));
				return;
			}
		} else {
			v.val = val;
			v.flags |= Var.CHANGED;
			return;
		}
		e = e.pushed;
	}
}

Context.get(ctxt: self ref Context, name: string): list of ref Listnode
{
	if (name == nil)
		return nil;

	idx := -1;
	# cope with $1, $2, etc
	if (name[0] > '0' && name[0] <= '9') {
		i: int;
		for (i = 0; i < len name; i++)
			if (name[i] < '0' || name[i] > '9')
				break;
		if (i >= len name) {
			idx = int name - 1;
			name = "*";
		}
	}

	v := varfind(ctxt.env.localenv, name);
	if (v != nil) {
		if (idx != -1)
			return index(v.val, idx);
		return v.val;
	}
	return nil;
}

# return the whole environment.
Context.envlist(ctxt: self ref Context): list of (string, list of ref Listnode)
{
	t := array[ENVHASHSIZE] of list of ref Var;
	for (e := ctxt.env.localenv; e != nil; e = e.pushed) {
		for (i := 0; i < len e.vars; i++) {
			for (vl := e.vars[i]; vl != nil; vl = tl vl) {
				v := hd vl;
				idx := hashfn(v.name, len e.vars);
				if (hashfind(t, idx, v.name) == nil)
					hashadd(t, idx, v);
			}
		}
	}

	l: list of (string, list of ref Listnode);
	for (i := 0; i < ENVHASHSIZE; i++) {
		for (vl := t[i]; vl != nil; vl = tl vl) {
			v := hd vl;
			l = (v.name, v.val) :: l;
		}
	}
	return l;
}

Context.setlocal(ctxt: self ref Context, name: string, val: list of ref Listnode)
{
	e := ctxt.env.localenv;
	idx := hashfn(name, len e.vars);
	v := hashfind(e.vars, idx, name);
	if (v == nil) {
		flags := Var.CHANGED;
		if (noexport(name))
			flags |= Var.NOEXPORT;
		hashadd(e.vars, idx, ref Var(name, val, flags));
	} else {
		v.val = val;
		v.flags |= Var.CHANGED;
	}
}


Context.push(ctxt: self ref Context)
{
	ctxt.env.localenv = newlocalenv(ctxt.env.localenv);
}

Context.pop(ctxt: self ref Context)
{
	if (ctxt.env.localenv.pushed == nil)
		panic("unbalanced contexts in shell environment");
	else {
		oldv := ctxt.env.localenv.vars;
		ctxt.env.localenv = ctxt.env.localenv.pushed;
		for (i := 0; i < len oldv; i++) {
			for (vl := oldv[i]; vl != nil; vl = tl vl) {
				if ((v := varfind(ctxt.env.localenv, (hd vl).name)) != nil)
					v.flags |= Var.CHANGED;
				else
					ctxt.set((hd vl).name, nil);
			}
		}
	}
}

Context.run(ctxt: self ref Context, args: list of ref Listnode, last: int): string
{
	if (args == nil || ((hd args).cmd == nil && (hd args).word == nil))
		return nil;
	cmd := hd args;
	if (cmd.cmd != nil || cmd.word[0] == '{')	# }
		return runblock(ctxt, args, last);

	if (ctxt.options() & ctxt.EXECPRINT)
		sys->fprint(stderr(), "%s\n", quoted(args, 0));
	(doneit, status) := trybuiltin(ctxt, args, last);
	if (!doneit)
		status = runexternal(ctxt, args, last);

	return status;
}

Context.addmodule(ctxt: self ref Context, name: string, mod: Shellbuiltin)
{
	mod->initbuiltin(ctxt, myself);
	ctxt.env.bmods = (name, mod->getself()) :: ctxt.env.bmods;
}

Context.addbuiltin(c: self ref Context, name: string, mod: Shellbuiltin)
{
	addbuiltin(c.env.builtins, name, mod);
}

Context.removebuiltin(c: self ref Context, name: string, mod: Shellbuiltin)
{
	removebuiltin(c.env.builtins, name, mod);
}

Context.addsbuiltin(c: self ref Context, name: string, mod: Shellbuiltin)
{
	addbuiltin(c.env.sbuiltins, name, mod);
}

Context.removesbuiltin(c: self ref Context, name: string, mod: Shellbuiltin)
{
	removebuiltin(c.env.sbuiltins, name, mod);
}

varfind(e: ref Localenv, name: string): ref Var
{
	idx := hashfn(name, len e.vars);
	for (; e != nil; e = e.pushed)
		for (vl := e.vars[idx]; vl != nil; vl = tl vl)
			if ((hd vl).name == name)
				return hd vl;
	return nil;
}

Context.fail(ctxt: self ref Context, ename: string, err: string)
{
	if (ctxt.options() & Context.VERBOSE)
		sys->fprint(stderr(), "%s\n", err);
	raise "fail:" + ename;
}

Context.setoptions(ctxt: self ref Context, flags, on: int): int
{
	old := ctxt.env.localenv.flags;
	if (on)
		ctxt.env.localenv.flags |= flags;
	else
		ctxt.env.localenv.flags &= ~flags;
	return old;
}

Context.options(ctxt: self ref Context): int
{
	return ctxt.env.localenv.flags;
}

hashfn(s: string, n: int): int
{
	h := 0;
	m := len s;
	for(i:=0; i<m; i++){
		h = 65599*h+s[i];
	}
	return (h & 16r7fffffff) % n;
}

# the following two functions cheat by getting the caller
# to calculate the actual hash function. this is to avoid
# the hash function being calculated once in every scope
# of a context until the variable is found (or stored).
hashfind(ht: array of list of ref Var, idx: int, n: string): ref Var
{
	for (ent := ht[idx]; ent != nil; ent = tl ent)
		if ((hd ent).name == n)
			return hd ent;
	return nil;
}

hashadd(ht: array of list of ref Var, idx: int, v: ref Var)
{
	ht[idx] = v :: ht[idx];
}

copylocalenv(e: ref Localenv): ref Localenv
{
	nvars := array[len e.vars] of list of ref Var;
	flags := e.flags;
	for (; e != nil; e = e.pushed)
		for (i := 0; i < len nvars; i++)
			for (vl := e.vars[i]; vl != nil; vl = tl vl) {
				idx := hashfn((hd vl).name, len nvars);
				if (hashfind(nvars, idx, (hd vl).name) == nil)
					hashadd(nvars, idx, ref *(hd vl));
			}
	return ref Localenv(nvars, nil, flags);
}

# make new local environment. if it's got no pushed levels,
# then get all variables from the global environment.
newlocalenv(pushed: ref Localenv): ref Localenv
{
	e := ref Localenv(array[ENVHASHSIZE] of list of ref Var, pushed, 0);
	if (pushed == nil && env != nil) {
		for (vl := env->getall(); vl != nil; vl = tl vl) {
			(name, val) := hd vl;
			hashadd(e.vars, hashfn(name, len e.vars), ref Var(name, envstringtoval(val), 0));
		}
	}
	if (pushed != nil)
		e.flags = pushed.flags;
	return e;
}

copybuiltins(b: ref Builtins): ref Builtins
{
	nb := ref Builtins(array[b.n] of (string, list of Shellbuiltin), b.n);
	nb.ba[0:] = b.ba[0:b.n];
	return nb;
}

findbuiltin(b: ref Builtins, name: string): (int, list of Shellbuiltin)
{
	lo := 0;
	hi := b.n - 1;
	while (lo <= hi) {
		mid := (lo + hi) / 2;
		(bname, bmod) := b.ba[mid];
		if (name < bname)
			hi = mid - 1;
		else if (name > bname)
			lo = mid + 1;
		else
			return (mid, bmod);
	}
	return (lo, nil);
}

removebuiltin(b: ref Builtins, name: string, mod: Shellbuiltin)
{
	(n, bmods) := findbuiltin(b, name);
	if (bmods == nil)
		return;
	if (hd bmods == mod) {
		if (tl bmods != nil)
			b.ba[n] = (name, tl bmods);
		else {
			b.ba[n:] = b.ba[n+1:b.n];
			b.ba[--b.n] = (nil, nil);
		}
	}
}

# add builtin; if it already exists, then replace it. if mod is nil then remove it.
# builtins that refer to myselfbuiltin are special - they
# are never removed, neither are they entirely replaced, only covered.
# no external module can redefine the name "builtin"
addbuiltin(b: ref Builtins, name: string, mod: Shellbuiltin)
{
	if (mod == nil || (name == "builtin" && mod != myselfbuiltin))
		return;
	(n, bmods) := findbuiltin(b, name);
	if (bmods != nil) {
		if (hd bmods == myselfbuiltin)
			b.ba[n] = (name, mod :: bmods);
		else
			b.ba[n] = (name, mod :: nil);
	} else {
		if (b.n == len b.ba) {
			nb := array[b.n + 10] of (string, list of Shellbuiltin);
			nb[0:] = b.ba[0:b.n];
			b.ba = nb;
		}
		b.ba[n+1:] = b.ba[n:b.n];
		b.ba[n] = (name, mod :: nil);
		b.n++;
	}
}

removebuiltinmod(b: ref Builtins, mod: Shellbuiltin)
{
	j := 0;
	for (i := 0; i < b.n; i++) {
		(name, bmods) := b.ba[i];
		if (hd bmods == mod)
			bmods = tl bmods;
		if (bmods != nil)
			b.ba[j++] = (name, bmods);
	}
	b.n = j;
	for (; j < i; j++)
		b.ba[j] = (nil, nil);
}

export(e: ref Localenv)
{
	if (env == nil)
		return;
	if (e.pushed != nil)
		export(e.pushed);

	for (i := 0; i < len e.vars; i++) {
		for (vl := e.vars[i]; vl != nil; vl = tl vl) {
			v := hd vl;
			# a bit inefficient: a local variable will get several putenvs.
			if ((v.flags & Var.CHANGED) && !(v.flags & Var.NOEXPORT)) {
				setenv(v.name, v.val);
				v.flags &= ~Var.CHANGED;
			}
		}
	}
}

noexport(name: string): int
{
	case name {
		"0" or "*" or "status" => return 1;
	}
	return 0;
}

index(val: list of ref Listnode, k: int): list of ref Listnode
{
	for (; k > 0 && val != nil; k--)
		val = tl val;
	if (val != nil)
		val = hd val :: nil;
	return val;
}

getenv(name: string): list of ref Listnode
{
	if (env == nil)
		return nil;
	return envstringtoval(env->getenv(name));
}

envstringtoval(v: string): list of ref Listnode
{
	return stringlist2list(str->unquoted(v));
}

XXXenvstringtoval(v: string): list of ref Listnode
{
	if (len v == 0)
		return nil;
	start := len v;
	val: list of ref Listnode;
	for (i := start - 1; i >= 0; i--) {
		if (v[i] == ENVSEP) {
			val = ref Listnode(nil, v[i+1:start]) :: val;
			start = i;
		}
	}
	return ref Listnode(nil, v[0:start]) :: val;
}

setenv(name: string, val: list of ref Listnode)
{
	if (env == nil)
		return;
	env->setenv(name, quoted(val, 1));
}

#
# globbing and general wildcard handling
#

containswildchar(s: string): int
{
	# try and avoid being fooled by GLOB characters in quoted
	# text. we'll only be fooled if the GLOB char is followed
	# by a wildcard char, or another GLOB.
	for (i := 0; i < len s; i++) {
		if (s[i] == GLOB && i < len s - 1) {
			case s[i+1] {
			'*' or '[' or '?' or GLOB =>
				return 1;
			}
		}
	}
	return 0;
}

# remove GLOBs, and quote other wildcard characters
patquote(word: string): string
{
	outword := "";
	for (i := 0; i < len word; i++) {
		case word[i] {
		'[' or '*' or '?' or '\\' =>
			outword[len outword] = '\\';
		GLOB =>
			i++;
			if (i >= len word)
				return outword;
			if(word[i] == '[' && i < len word - 1 && word[i+1] == '~')
				word[i+1] = '^';
		}
		outword[len outword] = word[i];
	}
	return outword;
}

# get rid of GLOB characters
deglob(s: string): string
{
	j := 0;
	for (i := 0; i < len s; i++) {
		if (s[i] != GLOB) {
			if (i != j)		# a worthy optimisation???
				s[j] = s[i];
			j++;
		}
	}
	if (i == j)
		return s;
	return s[0:j];
}

# expand wildcards in _nl_
glob(nl: list of ref Listnode): list of ref Listnode
{
	new: list of ref Listnode;
	while (nl != nil) {
		n := hd nl;
		if (containswildchar(n.word)) {
			qword := patquote(n.word);
			files := filepat->expand(qword);
			if (files == nil)
				files = deglob(n.word) :: nil;
			while (files != nil) {
				new = ref Listnode(nil, hd files) :: new;
				files = tl files;
			}
		} else
			new = n :: new;
		nl = tl nl;
	}
	ret := revlist(new);
	return ret;
}

#
# general list manipulation utility routines
#

# return string equivalent of nl
list2stringlist(nl: list of ref Listnode): list of string
{
	ret: list of string = nil;

	while (nl != nil) {
		newel: string;
		el := hd nl;
		if (el.word != nil || el.cmd == nil)
			newel = el.word;
		else
			el.word = newel = cmd2string(el.cmd);
		ret = newel::ret;
		nl = tl nl;
	}

	sl := revstringlist(ret);
	return sl;
}

stringlist2list(sl: list of string): list of ref Listnode
{
	ret: list of ref Listnode;

	while (sl != nil) {
		ret = ref Listnode(nil, hd sl) :: ret;
		sl = tl sl;
	}
	return revlist(ret);
}

revstringlist(l: list of string): list of string
{
	t: list of string;

	while(l != nil) {
		t = hd l :: t;
		l = tl l;
	}
	return t;
}

revlist(l: list of ref Listnode): list of ref Listnode
{
	t: list of ref Listnode;

	while(l != nil) {
		t = hd l :: t;
		l = tl l;
	}
	return t;
}

#
# node to string conversion functions
#

fdassignstr(isassign: int, redir: ref Redir): string
{
	l: string = nil;
	if (redir.fd1 >= 0)
		l = string redir.fd1;
	
	if (isassign) {
		r: string = nil;
		if (redir.fd2 >= 0)
			r = string redir.fd2;
		return "[" + l + "=" + r + "]";
	}
	return "[" + l + "]";
}

redirstr(rtype: int): string
{
	case rtype {
	* or
	Sys->OREAD =>	return "<";
	Sys->OWRITE =>	return ">";
	Sys->OWRITE|OAPPEND =>	return ">>";
	Sys->ORDWR =>	return "<>";
	}
}

cmd2string(n: ref Node): string
{
	if (n == nil)
		return "";

	s: string;
	case n.ntype {
	n_BLOCK =>	s = "{" + cmd2string(n.left) + "}";
	n_VAR =>		s = "$" + cmd2string(n.left);
				# XXX can this ever occur?
				if (n.right != nil)
					s += "(" + cmd2string(n.right) + ")";
	n_SQUASH =>	s = "$\"" + cmd2string(n.left);
	n_COUNT =>	s = "$#" + cmd2string(n.left);
	n_BQ =>		s = "`" + cmd2string(n.left);
	n_BQ2 =>		s = "\"" + cmd2string(n.left);
	n_REDIR =>	s = redirstr(n.redir.rtype);
				if (n.redir.fd1 != -1)
					s += fdassignstr(0, n.redir);
				s += cmd2string(n.left);
	n_DUP =>		s = redirstr(n.redir.rtype) + fdassignstr(1, n.redir);
	n_LIST =>		s = "(" + cmd2string(n.left) + ")";
	n_SEQ =>		s = cmd2string(n.left) + ";" + cmd2string(n.right);
	n_NOWAIT =>	s = cmd2string(n.left) + "&";
	n_CONCAT =>	s = cmd2string(n.left) + "^" + cmd2string(n.right);
	n_PIPE =>		s = cmd2string(n.left) + "|";
				if (n.redir != nil && (n.redir.fd1 != -1 || n.redir.fd2 != -1))
					s += fdassignstr(n.redir.fd2 != -1, n.redir);
				s += cmd2string(n.right);
	n_ASSIGN =>	s = cmd2string(n.left) + "=" + cmd2string(n.right);
	n_LOCAL =>	s = cmd2string(n.left) + ":=" + cmd2string(n.right);
	n_ADJ =>		s = cmd2string(n.left) + " " + cmd2string(n.right);
	n_WORD =>	s = quote(n.word, 1);
	* =>			s = sys->sprint("unknown%d", n.ntype);
	}
	return s;
}

# convert s into a suitable format for reparsing.
# if glob is true, then GLOB chars are significant.
# XXX it might be faster in the more usual cases 
# to run through the string first and only build up
# a new string once we've discovered it's necessary.
quote(s: string, glob: int): string
{
	needquote := 0;
	t := "";
	for (i := 0; i < len s; i++) {
		case s[i] {
		'{' or '}' or '(' or ')' or '`' or '&' or ';' or '=' or '>' or '<' or '#' or
		'|' or '*' or '[' or '?' or '$' or '^' or ' ' or '\t' or '\n' or '\r' =>
			needquote = 1;
		'\'' =>
			t[len t] = '\'';
			needquote = 1;
		GLOB =>
			if (glob) {
				if (i < len s - 1)
					i++;
			}
		}
		t[len t] = s[i];
	}
	if (needquote || t == nil)
		t = "'" + t + "'";
	return t;
}

squash(l: list of string, sep: string): string
{
	if (l == nil)
		return nil;
	s := hd l;
	for (l = tl l; l != nil; l = tl l)
		s += sep + hd l;
	return s;
}

debug(s: string)
{
	if (DEBUG) sys->fprint(stderr(), "%s\n", string sys->pctl(0, nil) + ": " + s);
}

#
# built-in commands
#

initbuiltin(c: ref Context, nil: Sh): string
{
	names := array[] of {"load", "unload", "loaded", "builtin", "syncenv", "whatis", "run", "exit", "@"};
	for (i := 0; i < len names; i++)
		c.addbuiltin(names[i], myselfbuiltin);
	c.addsbuiltin("loaded", myselfbuiltin);
	c.addsbuiltin("quote", myselfbuiltin);
	c.addsbuiltin("bquote", myselfbuiltin);
	c.addsbuiltin("unquote", myselfbuiltin);
	c.addsbuiltin("builtin", myselfbuiltin);
	return nil;
}

whatis(nil: ref Sh->Context, nil: Sh, nil: string, nil: int): string
{
	return nil;
}

runsbuiltin(ctxt: ref Context, nil: Sh, argv: list of ref Listnode): list of ref Listnode
{
	case (hd argv).word {
	"loaded" =>	return sbuiltin_loaded(ctxt, argv);
	"bquote" =>	return sbuiltin_quote(ctxt, argv, 0);
	"quote" =>	return sbuiltin_quote(ctxt, argv, 1);
	"unquote" =>	return sbuiltin_unquote(ctxt, argv);
	"builtin" =>	return sbuiltin_builtin(ctxt, argv);
	}
	return nil;
}

runbuiltin(ctxt: ref Context, nil: Sh, args: list of ref Listnode, lseq: int): string
{
	status := "";
	name := (hd args).word;
	case name {
	"load" =>		status = builtin_load(ctxt, args, lseq);
	"loaded" =>	status = builtin_loaded(ctxt, args, lseq);
	"unload" =>	status = builtin_unload(ctxt, args, lseq);
	"builtin" =>	status = builtin_builtin(ctxt, args, lseq);
	"whatis" =>	status = builtin_whatis(ctxt, args, lseq);
	"run" =>		status = builtin_run(ctxt, args, lseq);
	"exit" =>		status = builtin_exit(ctxt, args, lseq);
	"syncenv" =>	export(ctxt.env.localenv);
	"@" =>		status = builtin_subsh(ctxt, args, lseq);
	}
	return status;
}

sbuiltin_loaded(ctxt: ref Context, nil: list of ref Listnode): list of ref Listnode
{
	v: list of ref Listnode;
	for (bl := ctxt.env.bmods; bl != nil; bl = tl bl) {
		(name, nil) := hd bl;
		v = ref Listnode(nil, name) :: v;
	}
	return v;
}

sbuiltin_quote(nil: ref Context, argv: list of ref Listnode, quoteblocks: int): list of ref Listnode
{
	return ref Listnode(nil, quoted(tl argv, quoteblocks)) :: nil;
}

sbuiltin_builtin(ctxt: ref Context, args: list of ref Listnode): list of ref Listnode
{
	if (args == nil || tl args == nil)
		builtinusage(ctxt, "builtin command [args ...]");
	name := (hd tl args).word;
	(nil, mods) := findbuiltin(ctxt.env.sbuiltins, name);
	for (; mods != nil; mods = tl mods)
		if (hd mods == myselfbuiltin)
			return (hd mods)->runsbuiltin(ctxt, myself, tl args);
	ctxt.fail("builtin not found", sys->sprint("sh: builtin %s not found", name));
	return nil;
}

sbuiltin_unquote(ctxt: ref Context, argv: list of ref Listnode): list of ref Listnode
{
	argv = tl argv;
	if (argv == nil || tl argv != nil)
		builtinusage(ctxt, "unquote arg");
	
	arg := (hd argv).word;
	if (arg == nil && (hd argv).cmd != nil)
		arg = cmd2string((hd argv).cmd);
	return stringlist2list(str->unquoted(arg));
}

getself(): Shellbuiltin
{
	return myselfbuiltin;
}

builtinusage(ctxt: ref Context, s: string)
{
	ctxt.fail("usage", "sh: usage: " + s);
}

builtin_exit(nil: ref Context, nil: list of ref Listnode, nil: int): string
{
	# XXX using this primitive can cause
	# environment stack not to be popped properly.
	exit;
}

builtin_subsh(ctxt: ref Context, args: list of ref Listnode, nil: int): string
{
	if (tl args == nil)
		return nil;
	startchan := chan of (int, ref Expropagate);
	spawn runasync(ctxt, 0, tl args, ref Redirlist, startchan);
	(exepid, exprop) := <-startchan;
	status := waitfor(ctxt, exepid :: nil);
	if (exprop.name != nil)
		raise exprop.name;
	return status;
}

builtin_loaded(ctxt: ref Context, nil: list of ref Listnode, nil: int): string
{
	b := ctxt.env.builtins;
	for (i := 0; i < b.n; i++) {
		(name, bmods) := b.ba[i];
		sys->print("%s\t%s\n", name, modname(ctxt, hd bmods));
	}
	b = ctxt.env.sbuiltins;
	for (i = 0; i < b.n; i++) {
		(name, bmods) := b.ba[i];
		sys->print("${%s}\t%s\n", name, modname(ctxt, hd bmods));
	}
	return nil;
}

# it's debateable whether this should throw an exception or
# return a failed exit status - however, most scripts don't
# check the status and do need the module they're loading,
# so i think the exception is probably more useful...
builtin_load(ctxt: ref Context, args: list of ref Listnode, nil: int): string
{
	if (tl args == nil || (hd tl args).word == nil)
		builtinusage(ctxt, "load path...");
	args = tl args;
	if (args == nil)
		builtinusage(ctxt, "load path...");
	for (; args != nil; args = tl args) {
		s := loadmodule(ctxt, (hd args).word);
		if (s != nil)
			raise "fail:" + s;
	}
	return nil;
}

builtin_unload(ctxt: ref Context, args: list of ref Listnode, nil: int): string
{
	if (tl args == nil)
		builtinusage(ctxt, "unload path...");
	status := "";
	for (args = tl args; args != nil; args = tl args)
		if ((s := unloadmodule(ctxt, (hd args).word)) != nil)
			status = s;
	return status;
}

builtin_run(ctxt: ref Context, args: list of ref Listnode, nil: int): string
{
	if (tl args == nil || (hd tl args).word == nil)
		builtinusage(ctxt, "run path");
	ctxt.push();
	{
		ctxt.setoptions(ctxt.INTERACTIVE, 0);
		runscript(ctxt, (hd tl args).word, tl tl args, 1);
		ctxt.pop();
		return nil;
	} exception e {
	"fail:*" =>
		ctxt.pop();
		return failurestatus(e);
	}
}

# four categories:
# environment variables
# substitution builtins
# braced blocks
# builtins (including those defined by externally loaded modules)
# or external programs
# other
builtin_whatis(ctxt: ref Context, args: list of ref Listnode, nil: int): string
{
	if (len args < 2)
		builtinusage(ctxt, "whatis name ...");
	err := "";
	for (args = tl args; args != nil; args = tl args)
		if ((e := whatisit(ctxt, hd args)) != nil)
			err = e;
	return err;
}

whatisit(ctxt: ref Context, el: ref Listnode): string
{
	if (el.cmd != nil) {
		sys->print("%s\n", cmd2string(el.cmd));
		return nil;
	}
	found := 0;
	name := el.word;
	if (name != nil && name[0] == '{') {	#}
		sys->print("%s\n", name);
		return nil;;
	}
	if (name == nil)
		return nil;		# XXX questionable
	w: string;
	val := ctxt.get(name);
	if (val != nil) {
		found++;
		w += sys->sprint("%s=%s\n", quote(name, 0), quoted(val, 0));
	}
	(nil, mods) := findbuiltin(ctxt.env.sbuiltins, name);
	if (mods != nil) {
		mod := hd mods;
		if (mod == myselfbuiltin)
			w += "${builtin " + name + "}\n";
		else {
			mw := mod->whatis(ctxt, myself, name, Shellbuiltin->SBUILTIN);
			if (mw == nil)
				mw = "${" + name + "}";
			w += "load " + modname(ctxt, mod) + "; " + mw + "\n";
		}
		found++;
	}
	(nil, mods) = findbuiltin(ctxt.env.builtins, name);
	if (mods != nil) {
		mod := hd mods;
		if (mod == myselfbuiltin)
			sys->print("builtin %s\n", name);
		else {
			mw := mod->whatis(ctxt, myself, name, Shellbuiltin->BUILTIN);
			if (mw == nil)
				mw = name;
			w += "load " + modname(ctxt, mod) + "; " + mw + "\n";
		}
		found++;
	} else {
		disfile := 0;	
		if (len name >= 4 && name[len name-4:] == ".dis")
			disfile = 1;
		pathlist: list of string;
		if (len name >= 2 && (name[0] == '/' || name[0:2] == "./"))
			pathlist = list of {""};
		else if ((pl := ctxt.get("path")) != nil)
			pathlist = list2stringlist(pl);
		else
			pathlist = list of {"/dis", "."};
	
		foundpath := "";
		while (pathlist != nil) {
			path: string;
			if (hd pathlist != "")
				path = hd pathlist + "/" + name;
			else
				path = name;
			if (!disfile && (fd := sys->open(path, Sys->OREAD)) != nil) {
				if (executable(sys->fstat(fd), 8r111)) {
					foundpath = path;
					break;
				}
			}
			if (!disfile)
				path += ".dis";
			if (executable(sys->stat(path), 8r444)) {
				foundpath = path;
				break;
			}
			pathlist = tl pathlist;
		}
		if (foundpath != nil)
			w += foundpath + "\n";
	}
	for (bmods := ctxt.env.bmods; bmods != nil; bmods = tl bmods) {
		(modname, mod) := hd bmods;
		if ((mw := mod->whatis(ctxt, myself, name, Shellbuiltin->OTHER)) != nil)
			w += "load " + modname + "; " + mw + "\n";
	}
	if (w == nil) {
		sys->fprint(stderr(), "%s: not found\n", name);
		return "not found";
	}
	sys->print("%s", w);
	return nil;
}

# execute a command ignoring names defined by externally defined modules
builtin_builtin(ctxt: ref Context, args: list of ref Listnode, last: int): string
{
	if (len args < 2)
		builtinusage(ctxt, "builtin command [args ...]");
	name := (hd tl args).word;
	if (name == nil || name[0] == '{') {
		diagnostic(ctxt, name + " not found");
		return "not found";
	}
	(nil, mods) := findbuiltin(ctxt.env.builtins, name);
	for (; mods != nil; mods = tl mods)
		if (hd mods == myselfbuiltin)
			return (hd mods)->runbuiltin(ctxt, myself, tl args, last);
	if (ctxt.options() & ctxt.EXECPRINT)
		sys->fprint(stderr(), "%s\n", quoted(tl args, 0));
	return runexternal(ctxt, tl args, last);
}

modname(ctxt: ref Context, mod: Shellbuiltin): string
{
	for (ml := ctxt.env.bmods; ml != nil; ml = tl ml) {
		(bname, bmod) := hd ml;
		if (bmod == mod)
			return bname;
	}
	return "builtin";
}

loadmodule(ctxt: ref Context, name: string): string
{
	# avoid loading the same module twice (it's convenient
	# to have load be a null-op if the module required is already loaded)
	for (bl := ctxt.env.bmods; bl != nil; bl = tl bl) {
		(bname, nil) := hd bl;
		if (bname == name)
			return nil;
	}
	path := name;
	if (len path < 4 || path[len path-4:] != ".dis")
		path += ".dis";
	if (path[0] != '/' && path[0:2] != "./")
		path = BUILTINPATH + "/" + path;
	mod := load Shellbuiltin path;
	if (mod == nil) {
		diagnostic(ctxt, sys->sprint("load: cannot load %s: %r", path));
		return "bad module";
	}
	s := mod->initbuiltin(ctxt, myself);
	ctxt.env.bmods = (name, mod->getself()) :: ctxt.env.bmods;
	if (s != nil) {
		unloadmodule(ctxt, name);
		diagnostic(ctxt, "load: module init failed: " + s);
	}
	return s;
}

unloadmodule(ctxt: ref Context, name: string): string
{
	bl: list of (string, Shellbuiltin);
	mod: Shellbuiltin;
	for (cl := ctxt.env.bmods; cl != nil; cl = tl cl) {
		(bname, bmod) := hd cl;
		if (bname == name)
			mod = bmod;
		else
			bl = hd cl :: bl;
	}
	if (mod == nil) {
		diagnostic(ctxt, sys->sprint("module %s not found", name));
		return "not found";
	}
	for (ctxt.env.bmods = nil; bl != nil; bl = tl bl)
		ctxt.env.bmods = hd bl :: ctxt.env.bmods;
	removebuiltinmod(ctxt.env.builtins, mod);
	removebuiltinmod(ctxt.env.sbuiltins, mod);
	return nil;
}

executable(s: (int, Sys->Dir), mode: int): int
{
	(ok, info) := s;
	return ok != -1 && (info.mode & Sys->DMDIR) == 0
			&& (info.mode & mode) != 0;
}

quoted(val: list of ref Listnode, quoteblocks: int): string
{
	s := "";
	for (; val != nil; val = tl val) {
		el := hd val;
		if (el.cmd == nil || (quoteblocks && el.word != nil))
			s += quote(el.word, 0);
		else {
			cmd := cmd2string(el.cmd);
			if (quoteblocks)
				cmd = quote(cmd, 0);
			s += cmd;
		}
		if (tl val != nil)
			s[len s] = ' ';
	}
	return s;
}

setstatus(ctxt: ref Context, val: string): string
{
	ctxt.setlocal("status", ref Listnode(nil, val) :: nil);
	return val;
}

#
# beginning of parser routines
#

doparse(l: ref YYLEX, prompt: string, showline: int): (ref Node, string)
{
	l.prompt = prompt;
	l.err = nil;
	l.lval.node = nil;
	yyparse(l);
	l.lastnl = 0;		# don't print secondary prompt next time
	if (l.err != nil) {
		s: string;
		if (l.err == nil)
			l.err = "unknown error";
		if (l.errline > 0 && showline)
			s = sys->sprint("%s:%d: %s", l.path, l.errline, l.err);
		else
			s = l.path + ": parse error: " + l.err;
		return (nil, s);
	}
	return (l.lval.node, nil);
}

blanklex: YYLEX;	# for hassle free zero initialisation

YYLEX.initstring(s: string): ref YYLEX
{
	ret := ref blanklex;
	ret.s = s;
	ret.path="internal";
	ret.strpos = 0;
	return ret;
}

YYLEX.initfile(fd: ref Sys->FD, path: string): ref YYLEX
{
	lex := ref blanklex;
	lex.f = bufio->fopen(fd, bufio->OREAD);
	lex.path = path;
	lex.cbuf = array[2] of int;		# number of characters of pushback
	lex.linenum = 1;
	lex.prompt = "";
	return lex;
}

YYLEX.error(l: self ref YYLEX, s: string)
{
	if (l.err == nil) {
		l.err = s;
		l.errline = l.linenum;
	}
}

NOTOKEN: con -1;

YYLEX.lex(l: self ref YYLEX): int
{
	# the following are allowed a free caret:
	# $, word and quoted word;
	# also, allowed chrs in unquoted word following dollar are [a-zA-Z0-9*_]
	endword := 0;
	wasdollar := 0;
	tok := NOTOKEN;
	while (tok == NOTOKEN) {
		case c := l.getc() {
		l.EOF =>
			tok = END;
		'\n' =>
			tok = '\n';
		'\r' or '\t' or ' ' =>
			;
		'#' =>
			while ((c = l.getc()) != '\n' && c != l.EOF)
				;
			l.ungetc();
		';' =>	tok = ';';
		'&' =>
			c = l.getc();
			if(c == '&')
				tok = ANDAND;
			else{
				l.ungetc();
				tok = '&';
			}
		'^' =>	tok = '^';
		'{' =>	tok = '{';
		'}' =>	tok = '}';
		')' =>	tok = ')';
		'(' => tok = '(';
		'=' => (tok, l.lval.optype) = ('=', n_ASSIGN);
		'$' =>
			if (l.atendword) {
				l.ungetc();
				tok = '^';
				break;
			}
			case (c = l.getc()) {
			'#' =>
				l.lval.optype = n_COUNT;
			'"' =>
				l.lval.optype = n_SQUASH;
			* =>
				l.ungetc();
				l.lval.optype = n_VAR;
			}
			tok = OP;
			wasdollar = 1;
		'"' or '`'=>
			if (l.atendword) {
				tok = '^';
				l.ungetc();
				break;
			}
			tok = OP;
			if (c == '"')
				l.lval.optype = n_BQ2;
			else
				l.lval.optype = n_BQ;
		'>' or '<' =>
			rtype: int;
			nc := l.getc();
			if (nc == '>') {
				if (c == '>')
					rtype = Sys->OWRITE | OAPPEND;
				else
					rtype = Sys->ORDWR;
				nc = l.getc();
			} else if (c == '>')
				rtype = Sys->OWRITE;
			else
				rtype = Sys->OREAD;
			tok = REDIR;
			if (nc == '[') {
				(tok, l.lval.redir) = readfdassign(l);
				if (tok == ERROR)
					(l.err, l.errline) = ("syntax error in redirection", l.linenum);
			} else {
				l.ungetc();
				l.lval.redir = ref Redir(-1, -1, -1);
			}
			if (l.lval.redir != nil)
				l.lval.redir.rtype = rtype;
		'|' =>
			tok = '|';
			l.lval.redir = nil;
			if ((c = l.getc()) == '[') {
				(tok, l.lval.redir) = readfdassign(l);
				if (tok == ERROR) {
					(l.err, l.errline) = ("syntax error in pipe redirection", l.linenum);
					return tok;
				}
				tok = '|';
			} else if(c == '|')
				tok = OROR;
			else
				l.ungetc();

		'\'' =>
			if (l.atendword) {
				l.ungetc();
				tok = '^';
				break;
			}
			startline := l.linenum;
			s := "";
			for(;;) {
				while ((nc := l.getc()) != '\'' && nc != l.EOF)
					s[len s] = nc;
				if (nc == l.EOF) {
					(l.err, l.errline) = ("unterminated string literal", startline);
					return ERROR;
				}
				if (l.getc() != '\'') {
					l.ungetc();
					break;
				}
				s[len s] = '\'';	# 'xxx''yyy' becomes WORD(xxx'yyy)
			}
			l.lval.word = s;
			tok = WORD;
			endword = 1;

		* =>
			if (c == ':') {
				if (l.getc() == '=') {
					tok = '=';
					l.lval.optype = n_LOCAL;
					break;
				}
				l.ungetc();
			}
			if (l.atendword) {
				l.ungetc();
				tok = '^';
				break;
			}
			allowed: string;
			if (l.wasdollar)
				allowed = "a-zA-Z0-9*_";
			else
				allowed = "^\n \t\r|$'#<>;^(){}`&=\"";
			word := "";
			loop: do {
				case c {
				'*' or '?' or '[' or GLOB =>
					word[len word] = GLOB;
				':' =>
					nc := l.getc();
					l.ungetc();
					if (nc == '=')
						break loop;
				}
				word[len word] = c;
			} while ((c = l.getc()) != l.EOF && str->in(c, allowed));
			l.ungetc();
			l.lval.word = word;
			tok = WORD;
			endword = 1;
		}
		l.atendword = endword;
		l.wasdollar = wasdollar;
	}
#	sys->print("token %s\n", tokstr(tok));
	return tok;
}

tokstr(t: int): string
{
	s: string;
	case t {
	'\n' => s = "'\\n'";
	33 to 127 => s = sprint("'%c'", t);
	DUP=>	s = "DUP";
	REDIR =>s = "REDIR";
	WORD =>	s = "WORD";
	OP =>	s = "OP";
	END =>	s = "END";
	ERROR=>	s = "ERROR";
	* =>
		s = "<unknowntok"+ string t + ">";
	}
	return s;
}

YYLEX.ungetc(lex: self ref YYLEX)
{
	lex.strpos--;
	if (lex.f != nil) {
		lex.ncbuf++;
		if (lex.strpos < 0)
			lex.strpos = len lex.cbuf - 1;
	}
}
		
YYLEX.getc(lex: self ref YYLEX): int
{
	if (lex.eof)				# EOF sticks
		return lex.EOF;
	c: int;
	if (lex.f != nil) {
		if (lex.ncbuf > 0) {
			c = lex.cbuf[lex.strpos++];
			if (lex.strpos >= len lex.cbuf)
				lex.strpos = 0;
			lex.ncbuf--;
		} else {
			if (lex.lastnl && lex.prompt != nil)
				sys->fprint(stderr(), "%s", lex.prompt);
			c = bufio->lex.f.getc();
			if (c == bufio->ERROR || c == bufio->EOF) {
				lex.eof = 1;
				c = lex.EOF;
			} else if (c == '\n')
				lex.linenum++;
			lex.lastnl = (c == '\n');
			lex.cbuf[lex.strpos++] = c;
			if (lex.strpos >= len lex.cbuf)
				lex.strpos = 0;
		}
	} else {
		if (lex.strpos >= len lex.s) {
			lex.eof = 1;
			c = lex.EOF;
		} else
			c = lex.s[lex.strpos++];
	}
	return c;
}

# read positive decimal number; return -1 if no number found.
readnum(lex: ref YYLEX): int
{
	sum := nc := 0;
	while ((c := lex.getc()) >= '0' && c <= '9') {
		sum = (sum * 10) + (c - '0');
		nc++;
	}
	lex.ungetc();
	if (nc == 0)
		return -1;
	return sum;
}

# return tuple (toktype, lhs, rhs).
# -1 signifies no number present.
# '[' char has already been read.
readfdassign(lex: ref YYLEX): (int, ref Redir)
{
	n1 := readnum(lex);
	if ((c := lex.getc()) != '=') {
		if (c == ']')
			return (REDIR, ref Redir(-1, n1, -1));

		return (ERROR, nil);
	}
	n2 := readnum(lex);
	if (lex.getc() != ']')
		return (ERROR, nil);
	return (DUP, ref Redir(-1, n1, n2));
}

mkseq(left, right: ref Node): ref Node
{
	if (left != nil && right != nil)
		return mk(n_SEQ, left, right);
	else if (left == nil)
		return right;
	return left;
}

mk(ntype: int, left, right: ref Node): ref Node
{
	return ref Node(ntype, left, right, nil, nil);
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}
