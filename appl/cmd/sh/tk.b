implement Shellbuiltin;

include "sys.m";
	sys: Sys;
include "draw.m";
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "sh.m";
	sh: Sh;
	Listnode, Context: import sh;
	myself: Shellbuiltin;

tklock: chan of int;

chans := array[23] of list of (string, chan of string);
wins := array[16] of list of (int, ref Tk->Toplevel);
winid := 0;

badmodule(ctxt: ref Context, p: string)
{
	ctxt.fail("bad module", sys->sprint("tk: cannot load %s: %r", p));
}

initbuiltin(ctxt: ref Context, shmod: Sh): string
{
	sys = load Sys Sys->PATH;
	sh = shmod;

	myself = load Shellbuiltin "$self";
	if (myself == nil) badmodule(ctxt, "self");

	tk = load Tk Tk->PATH;
	if (tk == nil) badmodule(ctxt, Tk->PATH);

	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil) badmodule(ctxt, Tkclient->PATH);
	tkclient->init();

	tklock = chan[1] of int;

	ctxt.addbuiltin("tk", myself);
	ctxt.addbuiltin("chan", myself);
	ctxt.addbuiltin("send", myself);

	ctxt.addsbuiltin("tk", myself);
	ctxt.addsbuiltin("recv", myself);
	ctxt.addsbuiltin("alt", myself);
	ctxt.addsbuiltin("tkquote", myself);
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
			cmd: list of ref Listnode, nil: int): string
{
	case (hd cmd).word {
	"tk" =>		return builtin_tk(ctxt, cmd);
	"chan" =>		return builtin_chan(ctxt, cmd);
	"send" =>		return builtin_send(ctxt, cmd);
	}
	return nil;
}

runsbuiltin(ctxt: ref Context, nil: Sh,
			cmd: list of ref Listnode): list of ref Listnode
{
	case (hd cmd).word {
	"tk" =>		return sbuiltin_tk(ctxt, cmd);
	"recv" =>		return sbuiltin_recv(ctxt, cmd);
	"alt" =>		return sbuiltin_alt(ctxt, cmd);
	"tkquote" =>	return sbuiltin_tkquote(ctxt, cmd);
	}
	return nil;
}

builtin_tk(ctxt: ref Context, argv: list of ref Listnode): string
{
	# usage:	tk window _title_ _options_
	#		tk wintitle _winid_ _title_
	#		tk _winid_ _cmd_
	if (tl argv == nil)
		ctxt.fail("usage", "usage: tk (<winid>|window|onscreen|winctlwintitle|del|namechan) args...");
	argv = tl argv;
	w := (hd argv).word;
	case w {
	"window" =>
		remark(ctxt, string makewin(ctxt, tl argv));
	"wintitle" =>
		argv = tl argv;
		# change the title of a window
		if (len argv != 2 || !isnum((hd argv).word))
			ctxt.fail("usage", "usage: tk wintitle winid title");
		tkclient->settitle(egetwin(ctxt, hd argv), word(hd tl argv));
	"winctl" =>
		argv = tl argv;
		if (len argv != 2 || !isnum((hd argv).word))
			ctxt.fail("usage", "usage: tk winctl winid cmd");
		wid := (hd argv).word;
		win := egetwin(ctxt, hd argv);
		rq := word(hd tl argv);
		if (rq == "exit") {
			delwin(int wid);
			delchan(wid);
		}
		tkclient->wmctl(win, rq);
	"onscreen" =>
		argv = tl argv;
		if (len argv < 1 || !isnum((hd argv).word))
			ctxt.fail("usage", "usage: tk onscreen winid [how]");
		how := "";
		if(tl argv != nil)
			how = word(hd tl argv);
		win := egetwin(ctxt, hd argv);
		tkclient->startinput(win, "ptr" :: "kbd" :: nil);
		tkclient->onscreen(win, how);
	"namechan" =>
		argv = tl argv;
		n := len argv;
		if (n < 2 || n > 3 || !isnum((hd argv).word))
			ctxt.fail("usage", "usage: tk namechan winid chan [name]");
		name: string;
		if (n == 3)
			name = word(hd tl tl argv);
		else
			name = word(hd tl argv);
		tk->namechan(egetwin(ctxt, hd argv), egetchan(ctxt, hd tl argv), name);

	"del" =>
		if (len argv < 2)
			ctxt.fail("usage", "usage: tk del id...");
		for (argv = tl argv; argv != nil; argv = tl argv) {
			id := (hd argv).word;
			if (isnum(id))
				delwin(int id);
			delchan(id);
		}
	* =>
		e := tkcmd(ctxt, argv);
		if (e != nil)
			remark(ctxt, e);
		if (e != nil && e[0] == '!')
			return e;
	}
	return nil;
}

remark(ctxt: ref Context, s: string)
{
	if (ctxt.options() & ctxt.INTERACTIVE)
		sys->print("%s\n", s);
}

# create a new window (and its associated channel)
makewin(ctxt: ref Context, argv: list of ref Listnode): int
{
	if (argv == nil)
		ctxt.fail("usage", "usage: tk window title options");

	if (ctxt.drawcontext == nil)
		ctxt.fail("no draw context", sys->sprint("tk: no graphics context available"));

	(title, options) := (word(hd argv), concat(tl argv));
	(top, topchan) := tkclient->toplevel(ctxt.drawcontext, options, title, Tkclient->Appl);
	newid := addwin(top);
	addchan(string newid, topchan);
	return newid;
}

builtin_chan(ctxt: ref Context, argv: list of ref Listnode): string
{
	# create a new channel
	argv = tl argv;
	if (argv == nil)
		ctxt.fail("usage", "usage: chan name....");
	for (; argv != nil; argv = tl argv) {
		name := (hd argv).word;
		if (name == nil || isnum(name))
			ctxt.fail("bad chan", "tk: bad channel name "+q(name));
		if (addchan(name, chan of string) == nil)
			ctxt.fail("bad chan", "tk: channel "+q(name)+" already exists");
	}
	return nil;
}

builtin_send(ctxt: ref Context, argv: list of ref Listnode): string
{
	if (len argv != 3)
		ctxt.fail("usage", "usage: send chan arg");
	argv = tl argv;
	c := egetchan(ctxt, hd argv);
	c <-= word(hd tl argv);
	return nil;
}


sbuiltin_tk(ctxt: ref Context, argv: list of ref Listnode): list of ref Listnode
{
	# usage:	tk _winid_ _command_
	#		tk window _title_ _options_
	argv = tl argv;
	if (argv == nil)
		ctxt.fail("usage", "tk (window|wid) args");
	case (hd argv).word {
	"window" =>
		return ref Listnode(nil, string makewin(ctxt, tl argv)) :: nil;
	"winids" =>
		ret: list of ref Listnode;
		for (i := 0; i < len wins; i++)
			for (wl := wins[i]; wl != nil; wl = tl wl)
				ret = ref Listnode(nil, string (hd wl).t0) :: ret;
		return ret;
	* =>
		return ref Listnode(nil, tkcmd(ctxt, argv)) :: nil;
	}
}

sbuiltin_alt(ctxt: ref Context, argv: list of ref Listnode): list of ref Listnode
{
	# usage: alt chan ...
	argv = tl argv;
	if (argv == nil)
		ctxt.fail("usage", "usage: alt chan...");
	nc := len argv;
	kbd := array[nc] of chan of int;
	ptr := array[nc] of chan of ref Draw->Pointer;
	ca := array[nc * 3] of chan of string;
	win := array[nc] of ref Tk->Toplevel;
	
	cname := array[nc] of string;
	i := 0;
	for (; argv != nil; argv = tl argv) {
		w := (hd argv).word;
		ca[i*3] = egetchan(ctxt, hd argv);
		cname[i] = w;
		if(isnum(w)){
			win[i] = egetwin(ctxt, hd argv);
			ca[i*3+1] = win[i].ctxt.ctl;
			ca[i*3+2] = win[i].wreq;
			ptr[i] = win[i].ctxt.ptr;
			kbd[i] = win[i].ctxt.kbd;
		}
		i++;
	}
	for(;;) alt{
	(n, key) := <-kbd =>
		tk->keyboard(win[n], key);
	(n, p) := <-ptr =>
		tk->pointer(win[n], *p);
	(n, v) := <-ca =>
		return ref Listnode(nil, cname[n/3]) :: ref Listnode(nil, v) :: nil;
	}
}

sbuiltin_recv(ctxt: ref Context, argv: list of ref Listnode): list of ref Listnode
{
	# usage: recv chan
	if (len argv != 2)
		ctxt.fail("usage", "usage: recv chan");
	ch := hd tl argv;
	c := egetchan(ctxt, ch);
	if(!isnum(ch.word))
		return ref Listnode(nil, <-c) :: nil;

	win := egetwin(ctxt, ch);
	for(;;)alt{
	key := <-win.ctxt.kbd =>
		tk->keyboard(win, key);
	p := <-win.ctxt.ptr =>
		tk->pointer(win, *p);
	s := <-win.ctxt.ctl or
	s = <-win.wreq or
	s = <-c =>
		return ref Listnode(nil, s) :: nil;
	}
}

sbuiltin_tkquote(ctxt: ref Context, argv: list of ref Listnode): list of ref Listnode
{
	if (len argv != 2)
		ctxt.fail("usage", "usage: tkquote arg");
	return ref Listnode(nil, tk->quote(word(hd tl argv))) :: nil;
}

tkcmd(ctxt: ref Context, argv: list of ref Listnode): string
{
	if (argv == nil || !isnum((hd argv).word))
		ctxt.fail("usage", "usage: tk winid command");

	return tk->cmd(egetwin(ctxt, hd argv), concat(tl argv));
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

q(s: string): string
{
	return "'" + s + "'";
}

egetchan(ctxt: ref Context, n: ref Listnode): chan of string
{
	if ((c := getchan(n.word)) == nil)
		ctxt.fail("bad chan", "tk: bad channel name "+ q(n.word));
	return c;
}

# assumes that n.word has been checked and found to be numeric.
egetwin(ctxt: ref Context, n: ref Listnode): ref Tk->Toplevel
{
	wid := int n.word;
	if (wid < 0 || (top := getwin(wid)) == nil)
		ctxt.fail("bad win", "tk: unknown window id " + q(n.word));
	return top;
}

getchan(name: string): chan of string
{
	n := hashfn(name, len chans);
	for (cl := chans[n]; cl != nil; cl = tl cl) {
		(cname, c) := hd cl;
		if (cname == name)
			return c;
	}
	return nil;
}

addchan(name: string, c: chan of string): chan of string
{
	n := hashfn(name, len chans);
	tklock <-= 1;
	if (getchan(name) == nil)
		chans[n] = (name, c) :: chans[n];
	<-tklock;
	return c;
}

delchan(name: string)
{
	n := hashfn(name, len chans);
	tklock <-= 1;
	ncl: list of (string, chan of string);
	for (cl := chans[n]; cl != nil; cl = tl cl) {
		(cname, nil) := hd cl;
		if (cname != name)
			ncl = hd cl :: ncl;
	}
	chans[n] = ncl;
	<-tklock;
}

addwin(top: ref Tk->Toplevel): int
{
	tklock <-= 1;
	id := winid++;
	slot := id % len wins;
	wins[slot] = (id, top) :: wins[slot];
	<-tklock;
	return id;
}

delwin(id: int)
{
	tklock <-= 1;
	slot := id % len wins;
	nwl: list of (int, ref Tk->Toplevel);
	for (wl := wins[slot]; wl != nil; wl = tl wl) {
		(wid, nil) := hd wl;
		if (wid != id)
			nwl = hd wl :: nwl;
	}
	wins[slot] = nwl;
	<-tklock;
}

getwin(id: int): ref Tk->Toplevel
{
	slot := id % len wins;
	for (wl := wins[slot]; wl != nil; wl = tl wl) {
		(wid, top) := hd wl;
		if (wid == id)
			return top;
	}
	return nil;
}

word(n: ref Listnode): string
{
	if (n.word != nil)
		return n.word;
	if (n.cmd != nil)
		n.word = sh->cmd2string(n.cmd);
	return n.word;
}

isnum(s: string): int
{
	for (i := 0; i < len s; i++)
		if (s[i] > '9' || s[i] < '0')
			return 0;
	return 1;
}

concat(argv: list of ref Listnode): string
{
	if (argv == nil)
		return nil;
	s := word(hd argv);
	for (argv = tl argv; argv != nil; argv = tl argv)
		s += " " + word(hd argv);
	return s;
}

lockproc(c: chan of int)
{
	sys->pctl(Sys->NEWFD|Sys->NEWNS, nil);
	for(;;){
		c <-= 1;
		<-c;
	}
}
