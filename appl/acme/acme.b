implement Acme;

include "common.m";

sys : Sys;
bufio : Bufio;
workdir : Workdir;
drawm : Draw;
styx : Styx;
acme : Acme;
gui : Gui;
graph : Graph;
dat : Dat;
framem : Framem;
utils : Utils;
regx : Regx;
scrl : Scroll;
textm : Textm;
filem : Filem;
windowm : Windowm;
rowm : Rowm;
columnm : Columnm;
bufferm : Bufferm;
diskm : Diskm;
exec : Exec;
look : Look;
timerm : Timerm;
fsys : Fsys;
xfidm : Xfidm;
plumbmsg : Plumbmsg;
editm: Edit;
editlog: Editlog;
editcmd: Editcmd;
styxaux: Styxaux;

sprint : import sys;
BACK, HIGH, BORD, TEXT, HTEXT, NCOL : import Framem;
Point, Rect, Font, Image, Display, Pointer: import drawm;
TRUE, FALSE, maxtab : import dat;
Ref, Reffont, Command, Timer, Lock, Cursor : import dat;
row, reffont, activecol, mouse, typetext, mousetext, barttext, argtext, seltext, button, modbutton, colbutton, arrowcursor, boxcursor, plumbed : import dat;
Xfid : import xfidm;
cmouse, ckeyboard, cwait, ccommand, ckill, cxfidalloc, cxfidfree, cerr, cplumb, cedit : import dat;
font, bflush, balloc, draw : import graph;
Arg, PNPROC, PNGROUP : import utils;
arginit, argopt, argf, error, warning, postnote : import utils;
yellow, green, red, blue, black, white, mainwin, display : import gui;
Disk : import diskm;
Row : import rowm;
Column : import columnm;
Window : import windowm;
Text, Tag, Body, Columntag : import textm;
Buffer : import bufferm;
snarfbuf : import exec;
Msg : import plumbmsg;

tfd : ref Sys->FD;
lasttime : int;

init(ctxt : ref Draw->Context, argl : list of string)
{
	acmectxt = ctxt;

	sys = load Sys Sys->PATH;
	sys->pctl(Sys->NEWPGRP, nil);

	{
		# tfd = sys->create("./time", Sys->OWRITE, 8r600);
		# lasttime = sys->millisec();
		bufio = load Bufio Bufio->PATH;
		workdir = load Workdir Workdir->PATH;
		drawm = load Draw Draw->PATH;
	
		styx = load Styx Styx->PATH;
	
		acme = load Acme SELF;
	
		gui = load Gui path(Gui->PATH);
		graph = load Graph path(Graph->PATH);
		dat = load Dat path(Dat->PATH);
		framem = load Framem path(Framem->PATH);
		utils = load Utils path(Utils->PATH);
		regx = load Regx path(Regx->PATH);
		scrl = load Scroll path(Scroll->PATH);
		textm = load Textm path(Textm->PATH);
		filem = load Filem path(Filem->PATH);
		windowm = load Windowm path(Windowm->PATH);
		rowm = load Rowm path(Rowm->PATH);
		columnm = load Columnm path(Columnm->PATH);
		bufferm = load Bufferm path(Bufferm->PATH);
		diskm = load Diskm path(Diskm->PATH);
		exec = load Exec path(Exec->PATH);
		look = load Look path(Look->PATH);
		timerm = load Timerm path(Timerm->PATH);
		fsys = load Fsys path(Fsys->PATH);
		xfidm = load Xfidm path(Xfidm->PATH);
		plumbmsg = load Plumbmsg Plumbmsg->PATH;
		editm = load Edit path(Edit->PATH);
		editlog = load Editlog path(Editlog->PATH);
		editcmd = load Editcmd path(Editcmd->PATH);
		styxaux = load Styxaux path(Styxaux->PATH);
		
		mods := ref Dat->Mods(sys, bufio, drawm, styx, styxaux,
						acme, gui, graph, dat, framem,
						utils, regx, scrl,
						textm, filem, windowm, rowm, columnm,
						bufferm, diskm, exec, look, timerm,
						fsys, xfidm, plumbmsg, editm, editlog, editcmd);
	
		styx->init();
		styxaux->init();
	
		utils->init(mods);
		gui->init(mods);
		graph->init(mods);
		dat->init(mods);
		framem->init(mods);
		regx->init(mods);
		scrl->init(mods);
		textm->init(mods);
		filem->init(mods);
		windowm->init(mods);
		rowm->init(mods);
		columnm->init(mods);
		bufferm->init(mods);
		diskm->init(mods);
		exec->init(mods);
		look->init(mods);
		timerm->init(mods);
		fsys->init(mods);
		xfidm->init(mods);
		editm->init(mods);
		editlog->init(mods);
		editcmd->init(mods);
	
		utils->debuginit();
	
		if (plumbmsg->init(1, "edit", Dat->PLUMBSIZE) >= 0)
			plumbed = 1;
	
		main(argl);
	
	}
#	exception{
#		* =>
#			sys->fprint(sys->fildes(2), "acme: fatal: %s\n", utils->getexc());
#			sys->print("acme: fatal: %s\n", utils->getexc());
#			shutdown("error");
#	}
}

timing(s : string)
{
	thistime := sys->millisec();
	sys->fprint(tfd, "%s	%d\n", s, thistime-lasttime);
	lasttime = thistime;
}

path(p : string) : string
{
	if (RELEASECOPY)
		return p;
	else {
		# inlined strrchr since not loaded yet
		 for (n := len p - 1; n >= 0; n--)
			if (p[n] == '/')
				break;
		 if (n >= 0)
			p = p[n+1:];
		 return "/usr/jrf/acme/" + p;
	}
}

waitpid0, waitpid1 : int;
mainpid : int;

fontcache : array of ref Reffont;
nfontcache : int;
reffonts : array of ref Reffont;
deffontnames := array[2] of {
	"/fonts/lucidasans/euro.8.font",
	"/fonts/lucm/unicode.9.font",
};

command : ref Command;

WPERCOL : con 8;

NSnarf : con 32;
snarfrune : ref Dat->Astring;

main(argl : list of string)
{
	i, ac : int;
	loadfile : string;
	p : int;
	c : ref Column;
	arg : ref Arg;
	ncol : int;

	ncol = -1;

	mainpid = sys->pctl(0, nil);
	loadfile = nil;
	fontnames = array[2] of string;
	fontnames[0:] = deffontnames[0:2];
	f := utils->getenv("acme-font");
	if (f != nil)
		fontnames[0] = f;
	f = utils->getenv("acme-Font");
	if (f != nil)
		fontnames[1] = f;
	arg = arginit(argl);
	while(ac = argopt(arg)) case(ac){
	'b' =>
		dat->bartflag = TRUE;
	'c' =>
		ncol = int argf(arg);
	'f' =>
		fontnames[0] = argf(arg);
	'F' =>
		fontnames[1] = argf(arg);
	'l' =>
		loadfile = argf(arg);
	}

	dat->home = utils->getenv("home");
	if (dat->home == nil)
		dat->home = utils->gethome(utils->getuser());
	ts := utils->getenv("tabstop");
	if (ts != nil)
		maxtab = int ts;
	if (maxtab <= 0)
		maxtab = 4;
	snarfrune = utils->stralloc(NSnarf);
	sys->pctl(Sys->FORKNS|Sys->FORKENV, nil);
	utils->setenv("font", fontnames[0]);
	sys->bind("/acme/dis", "/dis", Sys->MBEFORE);
	wdir = workdir->init();
	if (wdir == nil)
		wdir = ".";
	workdir = nil;

	graph->binit();
	font = Font.open(display, fontnames[0]);
	if(font == nil){
		fontnames[0] = deffontnames[0];
		font = Font.open(display, fontnames[0]);
		if (font == nil) {
			warning(nil, sprint("can't open font file %s: %r\n", fontnames[0]));
			return;
		}
	}
	reffont = ref Reffont;
	reffont.r = Ref.init();
	reffont.f = font;
	reffonts = array[2] of ref Reffont;
	reffonts[0] = reffont;
	reffont.r.inc();	# one to hold up 'font' variable 
	reffont.r.inc();	# one to hold up reffonts[0] 
	fontcache = array[1] of ref Reffont;
	nfontcache = 1;
	fontcache[0] = reffont;

	iconinit();
	usercolinit();
	timerm->timerinit();
	regx->rxinit();

	cwait = chan of string;
	ccommand = chan of ref Command;
	ckill = chan of string;
	cxfidalloc = chan of ref Xfid;
	cxfidfree = chan of ref Xfid;
	cerr = chan of string;
	cplumb = chan of ref Msg;
	cedit = chan of int;

	gui->spawnprocs();
	# spawn keyboardproc();
	# spawn mouseproc();
	sync := chan of int;
	spawn waitproc(sys->pctl(0, nil), sync);
	<- sync;
	spawn plumbproc();

	fsys->fsysinit();
	dat->disk = (dat->disk).init();
	row = rowm->newrow();
	if(loadfile != nil) {
		row.qlock.lock();	# tasks->procs now 
		row.loadx(loadfile, TRUE);
		row.qlock.unlock();
	}
	else{
		row.init(mainwin.clipr);
		if(ncol < 0){
			if(arg.av == nil)
				ncol = 2;
			else{
				ncol = (len arg.av+(WPERCOL-1))/WPERCOL;
				if(ncol < 2)
					ncol = 2;
			}
		}
		if(ncol == 0)
			ncol = 2;
		for(i=0; i<ncol; i++){
			c = row.add(nil, -1);
			if(c==nil && i==0)
				error("initializing columns");
		}
		c = row.col[row.ncol-1];
		if(arg.av == nil)
			readfile(c, wdir);
		else
			i = 0;
			for( ; arg.av != nil; arg.av = tl arg.av){
				filen := hd arg.av;
				p = utils->strrchr(filen, '/');
				if((p>=0 && filen[p:] == "/guide") || i/WPERCOL>=row.ncol)
					readfile(c, filen);
				else
					readfile(row.col[i/WPERCOL], filen);
				i++;
			}
	}
	bflush();

	spawn keyboardtask();
	spawn mousetask();
	spawn waittask();
	spawn xfidalloctask();

	# notify(shutdown);
	# waitc := chan of int;
	# <-waitc;
	# killprocs();
	exit;
}

readfile(c : ref Column, s : string)
{
	w : ref Window;
	r : string;
	nr : int;

	w = c.add(nil, nil, -1);
	(r, nr) = look->cleanname(s, len s);
	w.setname(r, nr);
	w.body.loadx(0, s, 1);
	w.body.file.mod = FALSE;
	w.dirty = FALSE;
	w.settag();
	scrl->scrdraw(w.body);
	w.tag.setselect(w.tag.file.buf.nc, w.tag.file.buf.nc);
}

oknotes := array[6] of {
	"delete",
	"hangup",
	"kill",
	"exit",
	"error",
	nil
};

dumping : int;

shutdown(msg : string)
{
	i : int;

	# notify(nil);
	if(!dumping && msg != "kill" && msg != "exit" && (1 || sys->pctl(0, nil)==mainpid) && row != nil){
		dumping = TRUE;
		row.dump(nil);
	}
	for(i=0; oknotes[i] != nil; i++)
		if(utils->strncmp(oknotes[i], msg, len oknotes[i]) == 0) {
			killprocs();
			exit;
		}
	# killprocs();
	sys->fprint(sys->fildes(2), "acme: %s\n", msg);
	sys->print("acme: %s\n", msg);
	# exit;
}

acmeexit(err: string)
{
	if(err != nil)
		shutdown(err);
	graph->cursorswitch(nil);
	if (plumbed)
		plumbmsg->shutdown();
	killprocs();
	gui->killwins();
	exit;
}

killprocs()
{
	c : ref Command;
	kill := "kill";
	thispid := sys->pctl(0, nil);
	fsys->fsysclose();

	postnote(PNPROC, thispid, mousepid, kill);
	postnote(PNPROC, thispid, keyboardpid, kill);
	postnote(PNPROC, thispid, timerpid, kill);
	postnote(PNPROC, thispid, waitpid0, kill);
	postnote(PNPROC, thispid, waitpid1, kill);
	postnote(PNPROC, thispid, fsyspid, kill);
	postnote(PNPROC, thispid, mainpid, kill);
	postnote(PNPROC, thispid, keytid, kill);
	postnote(PNPROC, thispid, mousetid, kill);
	postnote(PNPROC, thispid, waittid, kill);
	postnote(PNPROC, thispid, xfidalloctid, kill);
	# postnote(PNPROC, thispid, lockpid, kill);
	postnote(PNPROC, thispid, plumbpid, kill);

	# draw(mainwin, mainwin.r, white, nil, mainwin.r.min);

	for(c=command; c != nil; c=c.next)
		postnote(PNGROUP, thispid, c.pid, "kill");

	xfidm->xfidkill();
}

keytid : int;
mousetid : int;
waittid : int;
xfidalloctid : int;

keyboardtask()
{
	r : int;
	timer : ref Timer;
	null : ref Timer;
	t : ref Text;

	{
		keytid = sys->pctl(0, nil);
		null = ref Timer;
		null.c = chan of int;
		timer = null;
		typetext = nil;
		for(;;){
			alt{
			<-(timer.c) =>
				timerm->timerstop(timer);
				t = typetext;
				if(t!=nil && t.what==Tag && !t.w.qlock.locked()){
					t.w.lock('K');
					t.w.commit(t);
					t.w.unlock();
					bflush();
				}
				timer = null;
			r = <-ckeyboard =>
				gotkey := 1;
				while (gotkey) {
					typetext = row.typex(r, mouse.xy);
					t = typetext;
					if(t!=nil && t.col!=nil)
						activecol = t.col;
					if(t!=nil && t.w!=nil)
						t.w.body.file.curtext = t.w.body;
					if(timer != null)
						spawn timerm->timerwaittask(timer);
					if(t!=nil && t.what==Tag)
						timer = timerm->timerstart(500);
					else
						timer = null;
					alt {
						r = <- ckeyboard =>
							gotkey = 1;	# do this case again
						* =>
							gotkey = 0;
					}
					bflush();
				}
			}
		}
	}
	exception{
		* =>
			shutdown(utils->getexc());
			raise;
			# acmeexit(nil);
	}
}

mousetask()
{
	t, argt : ref Text;
	but, ok : int;
	q0, q1 : int;
	w : ref Window;
	m : ref Msg;

	{
		mousetid = sys->pctl(0, nil);
		sync := chan of int;
		spawn waitproc(mousetid, sync);
		<- sync;
		for(;;){
			alt{
			*mouse = *<-cmouse =>
				row.qlock.lock();
				if (mouse.buttons & M_QUIT) {
					if (row.clean(TRUE))
						acmeexit(nil);
					# shutdown("kill");
					row.qlock.unlock();
					break;
				}
				if (mouse.buttons & M_HELP) {
					warning(nil, "no help provided (yet)");
					bflush();
					row.qlock.unlock();
					break;
				}
				if(mouse.buttons & M_RESIZE){
					draw(mainwin, mainwin.r, white, nil, mainwin.r.min);
					scrl->scrresize();
					row.reshape(mainwin.clipr);
					bflush();
					row.qlock.unlock();
					break;
				}
				t = row.which(mouse.xy);
				if(t!=mousetext && mousetext!=nil && mousetext.w!=nil){
					mousetext.w.lock('M');
					mousetext.eq0 = ~0;
					mousetext.w.commit(mousetext);
					mousetext.w.unlock();
				}
				mousetext = t;
				if(t == nil) {
					bflush();
					row.qlock.unlock();
					break;
				}
				w = t.w;
				if(t==nil || mouse.buttons==0) {
					bflush();
					row.qlock.unlock();
					break;
				}
				if(w != nil)
					w.body.file.curtext = w.body;
				but = 0;
				if(mouse.buttons == 1)
					but = 1;
				else if(mouse.buttons == 2)
					but = 2;
				else if(mouse.buttons == 4)
					but = 3;
				barttext = t;
				if(t.what==Body && mouse.xy.in(t.scrollr)){
					if(but){
						w.lock('M');
						t.eq0 = ~0;
						scrl->scroll(t, but);
						t.w.unlock();
					}
					bflush();
					row.qlock.unlock();
					break;
				}
				if(mouse.xy.in(t.scrollr)){
					if(but){
						if(t.what == Columntag)
							row.dragcol(t.col);
						else if(t.what == Tag){
							t.col.dragwin(t.w, but);
							if(t.w != nil)
								barttext = t.w.body;
						}
						if(t.col != nil)
							activecol = t.col;
					}
					bflush();
					row.qlock.unlock();
					break;
				}
				if(mouse.buttons){
					if(w != nil)
						w.lock('M');
					t.eq0 = ~0;
					if(w != nil)
						w.commit(t);
					else
						t.commit(TRUE);
					if(mouse.buttons & 1){
						t.select(0);
						if(w != nil)
							w.settag();
						argtext = t;
						seltext = t;
						if(t.col != nil)
							activecol = t.col;	# button 1 only 
						if(t.w != nil && t == t.w.body)
							dat->activewin = t.w;
					}else if(mouse.buttons & 2){
						(ok, argt, q0, q1) = t.select2(q0, q1);
						if(ok)
							exec->execute(t, q0, q1, FALSE, argt);
					}else if(mouse.buttons & 4){
						(ok, q0, q1) = t.select3(q0, q1);
						if(ok)
							look->look3(t, q0, q1, FALSE);
					}
					if(w != nil)
						w.unlock();
					bflush();
					row.qlock.unlock();
					break;
				}
			m = <- cplumb =>
				if (m.kind == "text") {
					attrs := plumbmsg->string2attrs(m.attr);
					(found, act) := plumbmsg->lookup(attrs, "action");
					if (!found || act == nil || act == "showfile")
						look->plumblook(m);
					else if (act == "showdata")
						look->plumbshow(m);
				}
				bflush();
			}
		}
	}
	exception{
		* =>
			shutdown(utils->getexc());
			raise;
			# acmeexit(nil);
	}
}

# list of processes that have exited but we have not heard of yet
Pid : adt {
	pid : int;
	msg : string;
	next : cyclic ref Pid;
};

waittask()
{
	status : string;
	c, lc : ref Command;
	pid : int;
	found : int;
	cmd : string;
	err : string;
	t : ref Text;
	pids : ref Pid;

	waittid = sys->pctl(0, nil);
	command = nil;
	for(;;){
		alt{
		err = <-cerr =>
			row.qlock.lock();
			warning(nil, err);
			err = nil;
			bflush();
			row.qlock.unlock();
			break;
		cmd = <-ckill =>
			found = FALSE;
			for(c=command; c != nil; c=c.next){
				# -1 for blank 
				if(c.name[0:len c.name - 1] == cmd){
					if(postnote(PNGROUP, waittid, c.pid, "kill") < 0)
						warning(nil, sprint("kill %s: %r\n", cmd));
					found = TRUE;
				}
			}
			if(!found)
				warning(nil, sprint("Kill: no process %s\n", cmd));
			cmd = nil;
			break;
		status = <-cwait =>
			pid = int status;
			lc = nil;
			for(c=command; c != nil; c=c.next){
				if(c.pid == pid){
					if(lc != nil)
						lc.next = c.next;
					else
						command = c.next;
					break;
				}
				lc = c;
			}
			row.qlock.lock();
			t = row.tag;
			t.commit(TRUE);
			if(c == nil){
				# warning(nil, sprint("unknown child pid %d\n", pid));
				p := ref Pid;
				p.pid = pid;
				p.msg = status;
				p.next = pids;
				pids = p;
			}
			else{
				if(look->search(t, c.name, len c.name)){
					t.delete(t.q0, t.q1, TRUE);
					t.setselect(0, 0);
				}
				if(status[len status - 1] != ':')
					warning(c.md, sprint("%s\n", status));
				bflush();
			}
			row.qlock.unlock();
			if(c != nil){
				if(c.iseditcmd)
					cedit <- = 0;
				fsys->fsysdelid(c.md);
				c = nil;
			}
			break;
		c = <-ccommand =>
			lastp : ref Pid = nil;
			for(p := pids; p != nil; p = p.next){
				if(p.pid == c.pid){
					status = p.msg;
					if(status[len status - 1] != ':')
						warning(c.md, sprint("%s\n", status));
					if(lastp == nil)
						pids = p.next;
					else
						lastp.next = p.next;
					if(c.iseditcmd)
						cedit <- = 0;
					fsys->fsysdelid(c.md);
					c = nil;
					break;
				}
				lastp = p;
			}	
			c.next = command;
			command = c;
			row.qlock.lock();
			t = row.tag;
			t.commit(TRUE);
			t.insert(0, c.name, len c.name, TRUE, 0);
			t.setselect(0, 0);
			bflush();
			row.qlock.unlock();
			break;
		}
	}
}

xfidalloctask()
{
	xfree, x : ref Xfid;

	xfidalloctid = sys->pctl(0, nil);
	xfree = nil;
	for(;;){
		alt{
		<-cxfidalloc =>
			x = xfree;
			if(x != nil)
				xfree = x.next;
			else{
				x = xfidm->newxfid();
				x.c = chan of int;
				spawn x.ctl();
			}
			cxfidalloc <-= x;
			break;
		x = <-cxfidfree =>
			x.next = xfree;
			xfree = x;
			break;
		}
	}
}

frgetmouse()
{
	bflush();
	*mouse = *<-cmouse;
}

waitproc(pid : int, sync: chan of int)
{
	fd : ref Sys->FD;
	n : int;

	if (waitpid0 == 0)
		waitpid0 = sys->pctl(0, nil);
	else
		waitpid1 = sys->pctl(0, nil);
	sys->pctl(Sys->FORKFD, nil);
	# w := sprint("/prog/%d/wait", pid);
	w := sprint("#p/%d/wait", pid);
	fd = sys->open(w, Sys->OREAD);
	if (fd == nil)
		error("fd == nil in waitproc");
	sync <-= 0;
	buf := array[Sys->WAITLEN] of byte;
	status := "";
	for(;;){
		if ((n = sys->read(fd, buf, len buf))<0)
			error("bad read in waitproc");
		status = string buf[0:n];
		cwait <-= status;
	}
}

get(fix : int, save : int, setfont : int, name : string) : ref Reffont
{
	r : ref Reffont;
	f : ref Font;
	i : int;

	r = nil;
	if(name == nil){
		name = fontnames[fix];
		r = reffonts[fix];
	}
	if(r == nil){
		for(i=0; i<nfontcache; i++)
			if(name ==  fontcache[i].f.name){
				r = fontcache[i];
				break;
			}
		if (i >= nfontcache) {
			f = Font.open(display, name);
			if(f == nil){
				warning(nil, sprint("can't open font file %s: %r\n", name));
				return nil;
			}
			r = ref Reffont;
			r.r = Ref.init();
			r.f = f;
			ofc := fontcache;
			fontcache = array[nfontcache+1] of ref Reffont;
			fontcache[0:] = ofc[0:nfontcache];
			ofc = nil;
			fontcache[nfontcache++] = r;
		}
	}
	if(save){
		r.r.inc();
		if(reffonts[fix] != nil)
			reffonts[fix].close();
		reffonts[fix] = r;
		fontnames[fix] = name;
	}
	if(setfont){
		reffont.f = r.f;
		r.r.inc();
		reffonts[0].close();
		font = r.f;
		reffonts[0] = r;
		r.r.inc();
		iconinit();
	}
	r.r.inc();
	return r;
}

close(r : ref Reffont)
{
	i : int;

	if(r.r.dec() == 0){
		for(i=0; i<nfontcache; i++)
			if(r == fontcache[i])
				break;
		if(i >= nfontcache)
			warning(nil, "internal error: can't find font in cache\n");
		else{
			fontcache[i:] = fontcache[i+1:nfontcache];
			nfontcache--;
		}
		r.f = nil;
		r = nil;
	}
}

arrowbits := array[64] of {
	 byte 16rFF, byte 16rE0, byte 16rFF, byte 16rE0,
	 byte 16rFF, byte 16rC0, byte 16rFF, byte 16r00,
	 byte 16rFF, byte 16r00, byte 16rFF, byte 16r80,
	 byte 16rFF, byte 16rC0, byte 16rFF, byte 16rE0,
	 byte 16rE7, byte 16rF0, byte 16rE3, byte 16rF8,
	 byte 16rC1, byte 16rFC, byte 16r00, byte 16rFE,
	 byte 16r00, byte 16r7F, byte 16r00, byte 16r3E,
	 byte 16r00, byte 16r1C, byte 16r00, byte 16r08,

	 byte 16r00, byte 16r00, byte 16r7F, byte 16rC0,
	 byte 16r7F, byte 16r00, byte 16r7C, byte 16r00,
	 byte 16r7E, byte 16r00, byte 16r7F, byte 16r00,
	 byte 16r6F, byte 16r80, byte 16r67, byte 16rC0,
	 byte 16r43, byte 16rE0, byte 16r41, byte 16rF0,
	 byte 16r00, byte 16rF8, byte 16r00, byte 16r7C,
	 byte 16r00, byte 16r3E, byte 16r00, byte 16r1C,
	 byte 16r00, byte 16r08, byte 16r00, byte 16r00,
};

# outer boundary of width 1 is white
# next  boundary of width 3 is black
# next  boundary of width 1 is white
# inner boundary of width 4 is transparent
boxbits := array[64] of {
	 byte 16rFF, byte 16rFF, byte 16rFF, byte 16rFF, 
	 byte 16rFF, byte 16rFF, byte 16rFF, byte 16rFF,
	 byte 16rFF, byte 16rFF, byte 16rF8, byte 16r1F,
	 byte 16rF8, byte 16r1F, byte 16rF8, byte 16r1F,
	 byte 16rF8, byte 16r1F, byte 16rF8, byte 16r1F,
	 byte 16rF8, byte 16r1F, byte 16rFF, byte 16rFF,
	 byte 16rFF, byte 16rFF, byte 16rFF, byte 16rFF,
	 byte 16rFF, byte 16rFF, byte 16rFF, byte 16rFF,


	 byte 16r00, byte 16r00, byte 16r7F, byte 16rFE,
	 byte 16r7F, byte 16rFE, byte 16r7F, byte 16rFE,
	 byte 16r70, byte 16r0E, byte 16r70, byte 16r0E,
	 byte 16r70, byte 16r0E, byte 16r70, byte 16r0E,
	 byte 16r70, byte 16r0E, byte 16r70, byte 16r0E,
	 byte 16r70, byte 16r0E, byte 16r70, byte 16r0E,
	 byte 16r7F, byte 16rFE, byte 16r7F, byte 16rFE,
	 byte 16r7F, byte 16rFE, byte 16r00, byte 16r00,
};

iconinit()
{
	r : Rect;

	# Blue
	tagcols = array[NCOL] of ref Draw->Image;
	tagcols[BACK] = display.colormix(Draw->Palebluegreen, Draw->White);
	tagcols[HIGH] = display.color(Draw->Palegreygreen);
	tagcols[BORD] = display.color(Draw->Purpleblue);
	tagcols[TEXT] = black;
	tagcols[HTEXT] = black;

	# Yellow
	textcols = array[NCOL] of ref Draw->Image;
	textcols[BACK] = display.colormix(Draw->Paleyellow, Draw->White);
	textcols[HIGH] = display.color(Draw->Darkyellow);
	textcols[BORD] = display.color(Draw->Yellowgreen); 
	textcols[TEXT] = black;
	textcols[HTEXT] = black;

	if(button != nil)
		button = modbutton = colbutton = nil;

	r = ((0, 0), (Dat->Scrollwid+2, font.height+1));
	button = balloc(r, mainwin.chans, Draw->White);
	draw(button, r, tagcols[BACK], nil, r.min);
	r.max.x -= 2;
	draw(button, r, tagcols[BORD], nil, (0, 0));   
	r = r.inset(2);
	draw(button, r, tagcols[BACK], nil, (0, 0));

	r = button.r;
	modbutton = balloc(r, mainwin.chans, Draw->White);
	draw(modbutton, r, tagcols[BACK], nil, r.min);
	r.max.x -= 2;
	draw(modbutton, r, tagcols[BORD], nil, (0, 0));
	r = r.inset(2);
	draw(modbutton, r, display.rgb(16r00, 16r00, 16r99), nil, (0, 0));	# was DMedblue

	r = button.r;
	colbutton = balloc(r, mainwin.chans, Draw->White);
	draw(colbutton, r, tagcols[BACK], nil, r.min);
	r.max.x -= 2;
	draw(colbutton, r, tagcols[BORD], nil, (0, 0));

#	arrowcursor = ref Cursor((-1, -1), (16, 32), arrowbits);
	boxcursor = ref Cursor((-7, -7), (16, 32), boxbits);

	but2col = display.rgb(16raa, 16r00, 16r00);
	but3col = display.rgb(16r00, 16r66, 16r00);
	but2colt = white;
	but3colt = white;

	graph->cursorswitch(arrowcursor);
}

colrec : adt {
	name : string;
	image : ref Image;
};

coltab : array of colrec;

cinit() 
{
	coltab = array[6] of colrec;
	coltab[0].name = "yellow"; coltab[0].image = yellow;
	coltab[1].name = "green"; coltab[1].image = green;
	coltab[2].name = "red"; coltab[2].image = red;
	coltab[3].name = "blue"; coltab[3].image = blue;
	coltab[4].name = "black"; coltab[4].image = black;
	coltab[5].name = "white"; coltab[5].image = white;
}

col(s : string, n : int) : int
{
	return ((s[n]-'0') << 4) | (s[n+1]-'0');
}

rgb(s : string, n : int) : (int, int, int)
{
	return (col(s, n), col(s, n+2), col(s, n+4));
}

cenv(s : string, t : string, but : int, i : ref Image) : ref Image
{
	c := utils->getenv("acme-" + s + "-" + t + "-" + string but);
	if (c == nil)
		c = utils->getenv("acme-" + s + "-" + string but);
	if (c == nil && but != 0)
		c = utils->getenv("acme-" + s);
	if (c != nil) {
		if (c[0] == '#' && len c >= 7) {
			(r1, g1, b1) := rgb(c, 1);
			if (len c >= 15 && c[7] == '/' && c[8] == '#') {
				(r2, g2, b2) := rgb(c, 9);
				return display.colormix((r1<<24)|(g1<<16)|(b1<<8)|16rFF, (r2<<24)|(g2<<16)|(b2<<8)|16rFF);
			}
			return display.color((r1<<24)|(g1<<16)|(b1<<8)|16rFF);
		}
		for (j := 0; j < len c; j++)
			if (c[j] >= 'A' && c[j] <= 'Z')
				c[j] += 'a'-'A';
		for (j = 0; j < len coltab; j++)
			if (c == coltab[j].name)
				return coltab[j].image;
	}
	return i;
}

usercolinit()
{
	cinit();
	textcols[TEXT] = cenv("fg", "text", 0, textcols[TEXT]);
	textcols[BACK] = cenv("bg", "text", 0, textcols[BACK]);
	textcols[HTEXT] = cenv("fg", "text", 1, textcols[HTEXT]);
	textcols[HIGH] = cenv("bg", "text", 1, textcols[HIGH]);
	but2colt= cenv("fg", "text", 2, but2colt);
	but2col = cenv("bg", "text", 2, but2col);
	but3colt = cenv("fg", "text", 3, but3colt);
	but3col = cenv("bg", "text", 3, but3col);
	tagcols[TEXT] = cenv("fg", "tag", 0, tagcols[TEXT]);
	tagcols[BACK] = cenv("bg", "tag", 0, tagcols[BACK]);
	tagcols[HTEXT] = cenv("fg", "tag", 1, tagcols[HTEXT]);
	tagcols[HIGH] = cenv("bg", "tag", 1, tagcols[HIGH]);
}

getsnarf()
{
	# return;
	fd := sys->open("/chan/snarf", sys->OREAD);
	if(fd == nil)
		return;
	snarfbuf.reset();
	snarfbuf.loadx(0, fd);
}

putsnarf()
{
	n : int;

	# return;
	if(snarfbuf.nc == 0)
		return;
	fd := sys->open("/chan/snarf", sys->OWRITE);
	if(fd == nil)
		return;
  	for(i:=0; i<snarfbuf.nc; i+=n){
		n = snarfbuf.nc-i;
		if(n >= NSnarf)
			n = NSnarf;
		snarfbuf.read(i, snarfrune, 0, n);
		sys->fprint(fd, "%s", snarfrune.s[0:n]);
	}
}

plumbpid : int;

plumbproc()
{
	plumbpid = sys->pctl(0, nil);
	for(;;){
		msg := Msg.recv();
		if(msg == nil){
			sys->print("Acme: can't read /chan/plumb.edit: %r\n");
			plumbpid = 0;
			plumbed = 0;
			return;
		}
		if(msg.kind != "text"){
			sys->print("Acme: can't interpret '%s' kind of message\n", msg.kind);
			continue;
		}
# sys->print("msg %s\n", string msg.data);
		cplumb <-= msg;
	}
}
