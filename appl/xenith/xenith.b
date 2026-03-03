implement Xenith;

include "common.m";

sys : Sys;
bufio : Bufio;
workdir : Workdir;
drawm : Draw;
styx : Styx;
xenith : Xenith;
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
asyncio: Asyncio;
imgload: Imgload;
render: Render;

sprint : import sys;
BACK, HIGH, BORD, TEXT, HTEXT, NCOL : import Framem;
Point, Rect, Font, Image, Display, Pointer: import drawm;
TRUE, FALSE, maxtab : import dat;
Ref, Reffont, Command, Timer, Lock, Cursor, Dirlist, ConsMsg : import dat;
row, reffont, activecol, mouse, typetext, mousetext, barttext, argtext, seltext, button, modbutton, colbutton, arrowcursor, boxcursor, plumbed : import dat;
Xfid : import xfidm;
cmouse, ckeyboard, cwait, ccommand, ckill, cxfidalloc, cxfidfree, cerr, ccons, cplumb, cedit, casync, scrollstate : import dat;
AsyncMsg : import asyncio;
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
	xenithctxt = ctxt;

	sys = load Sys Sys->PATH;
	sys->pctl(Sys->NEWPGRP, nil);

	{
		# tfd = sys->create("./time", Sys->OWRITE, 8r600);
		# lasttime = sys->millisec();
		bufio = load Bufio Bufio->PATH;
		workdir = load Workdir Workdir->PATH;
		drawm = load Draw Draw->PATH;
	
		styx = load Styx Styx->PATH;
	
		xenith = load Xenith SELF;
	
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
		asyncio = load Asyncio path(Asyncio->PATH);
		imgload = load Imgload path(Imgload->PATH);
		render = load Render path(Render->PATH);

		mods := ref Dat->Mods(sys, bufio, drawm, styx, styxaux,
						xenith, gui, graph, dat, framem,
						utils, regx, scrl,
						textm, filem, windowm, rowm, columnm,
						bufferm, diskm, exec, look, timerm,
						fsys, xfidm, plumbmsg, editm, editlog, editcmd,
						asyncio);
	
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
		asyncio->init(mods);
		imgload->init(display);
		if(render != nil)
			render->init(display);

		utils->debuginit();
	
	
		main(argl);
	}
#	exception{
#		* =>
#			sys->fprint(sys->fildes(2), "xenith: fatal: %s\n", utils->getexc());
#			sys->print("xenith: fatal: %s\n", utils->getexc());
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
		 return "/usr/jrf/xenith/" + p;
	}
}

waitpid0, waitpid1 : int;
mainpid : int;

fontcache : array of ref Reffont;
nfontcache : int;
reffonts : array of ref Reffont;
deffontnames := array[2] of {
	"/fonts/dejavu/DejaVuSans/unicode.14.font",
	"/fonts/dejavu/DejaVuSansMono/unicode.14.font",
};

# Theme definitions: (env-var-suffix, color-value)
# Color values: hex "#RRGGBB" (UPPERCASE!), mixed "#RRGGBB/#RRGGBB", or named
# Official Catppuccin Mocha palette from https://github.com/catppuccin/catppuccin
catppuccintheme := array[] of {
	# Body (text area) colors
	("bg-text-0", "#1E1E2E"),		# Base - main background
	("fg-text-0", "#CDD6F4"),		# Text - main foreground
	("bg-text-1", "#585B70"),		# Surface2 - selection background
	("fg-text-1", "#CDD6F4"),		# Text - selection foreground
	("bg-text-2", "#F38BA8"),		# Red - button 2 background
	("fg-text-2", "#1E1E2E"),		# Base - button 2 text
	("bg-text-3", "#A6E3A1"),		# Green - button 3 background
	("fg-text-3", "#1E1E2E"),		# Base - button 3 text
	("bord-text-0", "#89B4FA"),		# Blue - body border
	# Tag colors
	("bg-tag-0", "#313244"),			# Surface0 - tag background
	("fg-tag-0", "#CDD6F4"),			# Text - tag foreground
	("bg-tag-1", "#45475A"),			# Surface1 - tag selection
	("fg-tag-1", "#CDD6F4"),			# Text - tag selection text
	("bord-tag-0", "#89B4FA"),		# Blue - tag border
	# Border colors
	("bord-col-0", "#45475A"),		# Surface1 - column border
	("bord-row-0", "#45475A"),		# Surface1 - row border
	# Modifier button
	("mod-but-0", "#CBA6F7"),		# Mauve - modifier button
	# Empty space background
	("bg-col-0", "#181825"),			# Mantle - empty area background
};

themename : string;

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
	f := utils->getenv("xenith-font");
	if (f != nil)
		fontnames[0] = f;
	f = utils->getenv("xenith-Font");
	if (f != nil)
		fontnames[1] = f;
	arg = arginit(argl);
	while(ac = argopt(arg)) case(ac){
	'a' =>
		dat->globalautoindent = TRUE;
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
	't' =>
		themename = argf(arg);
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
	sys->bind("/xenith/dis", "/dis", Sys->MBEFORE);
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

	colinit();
	applytheme(themename);
	usercolinit();
	iconinit();
	timerm->timerinit();
	regx->rxinit();

	# Buffered channels to prevent spawned commands from blocking on sends
	cwait = chan[16] of string;
	ccommand = chan[8] of ref Command;
	ckill = chan[4] of string;
	cxfidalloc = chan of ref Xfid;  # Keep unbuffered - synchronous allocation
	cxfidfree = chan[8] of ref Xfid;
	cerr = chan[32] of string;
	ccons = chan[64] of ref ConsMsg;
	cplumb = chan[8] of ref Msg;
	cedit = chan[1] of int;

	gui->spawnprocs();
	# spawn keyboardproc();
	# spawn mouseproc();
	sync := chan of int;
	spawn waitproc(sys->pctl(0, nil), sync);
	<- sync;

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
	# Run the plumber inside acme, so plumber can start acme clients
	spawn exec->run(nil, "{bind -bc '#splumber' /chan; plumber > /tmp/plumb.log >[2=1]&}", nil, 0, TRUE, nil, nil, FALSE);
	spawn plumbproc();

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
	sys->fprint(sys->fildes(2), "xenith: %s\n", msg);
	sys->print("xenith: %s\n", msg);
	# exit;
}

xenithexit(err: string)
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
	exception e{
		* =>
			shutdown(utils->getexc());
			raise e;
			# xenithexit(nil);
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
			*mouse = *<-dat->cmouse =>
				row.qlock.lock();
				if (mouse.buttons & M_QUIT) {
					if (row.clean(TRUE))
						xenithexit(nil);
					# shutdown("kill");
					row.qlock.unlock();
					break;
				}
				if (mouse.buttons & M_HELP) {
					row.qlock.unlock();  # Release before warning to avoid blocking
					warning(nil, "no help provided (yet)");
					bflush();
					break;
				}
				if(mouse.buttons & M_RESIZE){
					clipr := mainwin.clipr;  # Capture state before releasing lock
					row.qlock.unlock();  # Release during expensive draw operations
					draw(mainwin, mainwin.r, bgcol, nil, mainwin.r.min);
					scrl->scrresize();
					row.qlock.lock();  # Reacquire for reshape
					row.reshape(clipr);
					row.qlock.unlock();
					bflush();
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
				# Focus-follows-mouse: update active window/column when mouse enters
				if(t != nil){
					if(t.w != nil)
						dat->activewin = t.w;
					if(t.col != nil)
						activecol = t.col;
				}
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
				# Check for active scroll state and handle updates/end
				if(scrollstate != nil && scrollstate.active) {
					# Check if button released
					if(!(mouse.buttons & (1<<(scrollstate.but-1)))) {
						scrl->scrollend();
					} else {
						# Update scroll position
						scrl->scrollupdate();
					}
					bflush();
					row.qlock.unlock();
					break;
				}
				if(t.what==Body && mouse.xy.in(t.scrollr)){
					if(w != nil && w.imagemode){
						# Image mode: scroll wheel → smooth pan or page navigation
						if(mouse.buttons & (8|16)){
							imagescroll(w, mouse.buttons);
						}
						bflush();
						row.qlock.unlock();
						break;
					}
					if(but){
						# Start non-blocking scroll
						w.lock('M');
						t.eq0 = ~0;
						scrl->scrollstart(t, but);
						# Do first update immediately
						scrl->scrollupdate();
						w.unlock();
					} else if(mouse.buttons & (8|16)){
						# Scroll wheel on scrollbar - Acme-style variable speed
						# Near top = slow (1 line), near bottom = fast (10 lines)
						h := t.scrollr.max.y - t.scrollr.min.y;
						if(h > 0){
							# Use integer math: nlines = 1 + (offset * 9) / h
							offset := mouse.xy.y - t.scrollr.min.y;
							nlines := 1 + (offset * 9) / h;
							if(nlines < 1) nlines = 1;
							if(nlines > 10) nlines = 10;
							if(mouse.buttons & 8)
								but = Dat->Kscrollup;
							else
								but = Dat->Kscrolldown;
							w.lock('M');
							t.eq0 = ~0;
							i := 0;
							while(i < nlines){
								t.typex(but, 0);
								i++;
							}
							w.unlock();
						}
					}
					bflush();
					row.qlock.unlock();
					break;
				}

# Scroll wheel - scroll window body from anywhere in window
				if(w != nil && (mouse.buttons &(8|16))){
					if(w.imagemode){
						imagescroll(w, mouse.buttons);
						bflush();
						row.qlock.unlock();
						break;
					}
					if(mouse.buttons & 8)
						but = Dat->Kscrollup;
					else
						but = Dat->Kscrolldown;
					w.lock('M');
					w.body.eq0 = ~0;
					w.body.typex(but, 0);
					w.unlock();
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
						if(w != nil && w.imagemode && t.what == Body){
							# Drag to pan in image mode body
							imagedrag(w);
						} else {
							t.select(0);
							if(w != nil)
								w.settag();
							argtext = t;
							seltext = t;
							if(t.col != nil)
								activecol = t.col;	# button 1 only
							if(t.w != nil && t == t.w.body)
								dat->activewin = t.w;
						}
					}else if(mouse.buttons & 2){
						if(w != nil && w.imagemode && t.what == Body){
							# No text execution in image mode body
							;
						} else {
							(ok, argt, q0, q1) = t.select2(q0, q1);
							if(ok)
								exec->execute(t, q0, q1, FALSE, argt);
						}
					}else if(mouse.buttons & 4){
						if(w != nil && w.imagemode && t.what == Body){
							# No text look in image mode body
							;
						} else {
							(ok, q0, q1) = t.select3(q0, q1);
							if(ok){
								{
									look->look3(t, q0, q1, FALSE);
								}
							exception{
								* =>
									warning(nil, "look3: " + utils->getexc() + "\n");
							}
							}
						}
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
					{
						if (!found || act == nil || act == "showfile")
							look->plumblook(m);
						else if (act == "showdata")
							look->plumbshow(m);
					}
					exception{
						* =>
							warning(nil, "plumb: " + utils->getexc() + "\n");
					}
				}
				bflush();
			amsg := <-casync =>
				# Handle async I/O results
				pick msg := amsg {
					Chunk =>
						# Future: insert chunk into file
						row.qlock.lock();
						row.qlock.unlock();
					Progress =>
						# Future: show progress indicator
						;
					Complete =>
						row.qlock.lock();
						if(msg.err != nil)
							warning(nil, sprint("async read: %s\n", msg.err));
						row.qlock.unlock();
					Error =>
						row.qlock.lock();
						warning(nil, sprint("async read error: %s\n", msg.err));
						row.qlock.unlock();
					ImageData =>
						# Spawn decode in background task for true concurrency
						if(msg.err != nil) {
							row.qlock.lock();
							warning(nil, sprint("image load: %s\n", msg.err));
							row.qlock.unlock();
						} else if(msg.data != nil) {
							# Spawn decode task - it will send ImageDecoded when done
							spawn decodetask(msg.winid, msg.path, msg.data);
						}
					ImageDecoded =>
						# Apply decoded image to window
						row.qlock.lock();
						if(msg.err != nil) {
							warning(nil, sprint("image decode: %s\n", msg.err));
						} else if(msg.image != nil) {
							w := look->lookid(msg.winid, 0);
							if(w != nil && w.col != nil) {
								w.bodyimage = msg.image;
								w.zoomedcache = nil;
								w.imagepath = msg.path;
								w.imagemode = 1;
								w.imageoffset = Point(0, 0);
								w.drawimage();
							}
						}
						row.qlock.unlock();
					ImageProgress =>
						# Progressive image update - redraw partial image
						row.qlock.lock();
						if(msg.image != nil) {
							w := look->lookid(msg.winid, 0);
							if(w != nil && w.col != nil) {
								# Update window with partial image
								w.bodyimage = msg.image;
								w.zoomedcache = nil;
								w.imagepath = msg.path;
								w.imagemode = 1;
								w.imageoffset = Point(0, 0);
								w.drawimage();
							}
						}
						row.qlock.unlock();
					ContentData =>
						# Dispatch content through renderer pipeline
						if(msg.err != nil) {
							row.qlock.lock();
							warning(nil, sprint("content load: %s\n", msg.err));
							row.qlock.unlock();
						} else if(msg.data != nil) {
							# Store raw data on window for renderer commands
							row.qlock.lock();
							w := look->lookid(msg.winid, 0);
							if(w != nil && w.col != nil)
								w.contentdata = msg.data;
							row.qlock.unlock();
							spawn rendertask(msg.winid, msg.path, msg.data);
						}
					ContentDecoded =>
						# Apply rendered content to window
						row.qlock.lock();
						w := look->lookid(msg.winid, 0);
						if(w != nil)
							w.rendering = 0;
						if(msg.err != nil) {
							warning(nil, sprint("content render: %s\n", msg.err));
						} else if(msg.image != nil) {
							if(w != nil && w.col != nil) {
								w.bodyimage = msg.image;
								w.zoomedcache = nil;
								w.imagepath = msg.path;
								w.imagemode = 1;
								# Cache renderer on window for command dispatch
								if(render != nil) {
									(rmod, nil) := render->findbyext(msg.path);
									w.contentrenderer = rmod;
								}
								w.drawimage();
								w.settag1();
								# If renderer extracted text, load it into body buffer
								if(msg.text != nil && len msg.text > 0) {
									w.body.file.buf.insert(0, msg.text, len msg.text);
								}
							}
						}
						# Dispatch pending command if queued during render
						if(w != nil && w.pendingcmd != nil){
							pcmd := w.pendingcmd;
							w.pendingcmd = nil;
							w.asynccontentcommand(pcmd, nil);
						}
						row.qlock.unlock();
					ContentProgress =>
						# Progressive content render update
						row.qlock.lock();
						if(msg.image != nil) {
							w := look->lookid(msg.winid, 0);
							if(w != nil && w.col != nil) {
								w.bodyimage = msg.image;
								w.zoomedcache = nil;
								w.imagepath = msg.path;
								w.imagemode = 1;
								w.imageoffset = Point(0, 0);
								w.drawimage();
							}
						}
						row.qlock.unlock();
					TextData =>
						# Insert text chunk into file buffer
						row.qlock.lock();
						if(msg.err != nil) {
							warning(nil, sprint("text load: %s\n", msg.err));
						} else {
							w := look->lookid(msg.winid, 0);
							if(w != nil && w.col != nil && w.body.file != nil) {
								# Insert chunk into buffer
								w.body.file.buf.insert(msg.q0 + msg.offset, msg.data, len msg.data);
								# Fill frame to show content as it loads
								t := w.body;
								t.fill();
								scrl->scrdraw(t);
							}
						}
						row.qlock.unlock();
					TextComplete =>
						# Mark file as fully loaded
						row.qlock.lock();
						if(msg.err != nil) {
							warning(nil, sprint("text load: %s\n", msg.err));
						} else {
							w := look->lookid(msg.winid, 0);
							if(w != nil && w.col != nil) {
								w.body.file.unread = 0;
								w.dirty = FALSE;
								w.asyncload = nil;
								w.settag();
								# Ensure frame is fully populated and displayed
								w.body.fill();
								scrl->scrdraw(w.body);
							}
						}
						row.qlock.unlock();
					DirEntry =>
						# Add directory entry to window's list
						row.qlock.lock();
						w := look->lookid(msg.winid, 0);
						if(w != nil && w.col != nil && w.isdir) {
							# Add entry to dlp array
							dl := ref Dirlist(msg.name, 0);  # Width calculated later
							ndl := w.ndl + 1;
							odlp := w.dlp;
							w.dlp = array[ndl] of ref Dirlist;
							if(odlp != nil)
								w.dlp[0:] = odlp[0:w.ndl];
							w.dlp[ndl-1] = dl;
							w.ndl = ndl;
						}
						row.qlock.unlock();
					DirComplete =>
						# Finalize directory listing
						row.qlock.lock();
						if(msg.err != nil) {
							warning(nil, sprint("dir load: %s\n", msg.err));
						} else {
							w := look->lookid(msg.winid, 0);
							if(w != nil && w.col != nil && w.isdir) {
								w.body.file.unread = 0;
								w.asyncload = nil;
								# Sort and display directory entries
								textm->dirfinalize(w.body);
								w.settag();
								w.body.fill();
								scrl->scrdraw(w.body);
							}
						}
						row.qlock.unlock();
					SaveProgress =>
						# Update status during async file save (for future progress indicator)
						;
					SaveComplete =>
						# Finish async file save
						row.qlock.lock();
						w := look->lookid(msg.winid, 0);
						if(w != nil && w.col != nil && w.asyncsave != nil) {
							f := w.body.file;
							if(msg.err != nil) {
								warning(nil, sprint("save error: %s\n", msg.err));
							} else {
								# Update file metadata on success
								if(w.savename == f.name) {
									# Saved entire file to its own name
									(ok, d) := sys->stat(msg.path);
									if(ok >= 0) {
										f.qidpath = d.qid.path;
										f.dev = d.dev;
										f.mtime = msg.mtime;
									}
									f.mod = FALSE;
									w.dirty = FALSE;
									f.unread = FALSE;
									for(i := 0; i < f.ntext; i++) {
										f.text[i].w.putseq = f.seq;
										f.text[i].w.dirty = FALSE;
									}
								}
								w.settag();
							}
							w.asyncsave = nil;
							w.savename = nil;
						}
						row.qlock.unlock();
				}
				bflush();
			}
		}
	}
	exception e {
		* =>
			shutdown(utils->getexc());
			raise e;
			# xenithexit(nil);
	}
}

# Background task to decode image without blocking UI
decodetask(winid: int, path: string, data: array of byte)
{
	im: ref Image;
	err: string;

	# Create progress channel for progressive updates
	progress := chan[4] of ref Imgload->ImgProgress;

	# Spawn progress forwarder
	spawn progressforwarder(winid, path, progress);

	{
		(im, err) = imgload->readimagedataprogressive(data, path, progress);
	}
	exception e {
		"out of memory*" =>
			err = "image too large for heap (try: emu -pheap=128000000)";
			im = nil;
		* =>
			err = "decode failed: " + utils->getexc();
			im = nil;
	}

	# Close progress channel (nil signals end)
	progress <-= nil;

	# Send result back to main loop - retry if channel full
	for(;;) {
		alt {
			casync <-= ref AsyncMsg.ImageDecoded(winid, path, im, err) => ;
			* =>
				# Channel full - yield and retry
				sys->sleep(1);
				continue;
		}
		break;
	}
}

# Forward progress updates to main loop
progressforwarder(winid: int, path: string, progress: chan of ref Imgload->ImgProgress)
{
	for(;;) {
		p := <-progress;
		if(p == nil)
			return;  # Done

		# Forward to main loop - non-blocking to avoid stalling decode
		alt {
			casync <-= ref AsyncMsg.ImageProgress(winid, path, p.image, p.rowsdone, p.rowstotal) => ;
			* => ;  # Drop if channel full
		}
	}
}

# Background task to render content through the renderer registry
rendertask(winid: int, path: string, data: array of byte)
{
	im: ref Image;
	text: string;
	err: string;

	if(render == nil) {
		err = "render module not available";
	} else {
		# Find the appropriate renderer for this content
		(renderer, ferr) := render->find(data, path);
		if(renderer == nil) {
			err = ferr;
		} else {
			# Create progress channel
			progress := chan[4] of ref Renderer->RenderProgress;

			# Spawn progress forwarder
			spawn renderprogressforwarder(winid, path, progress);

			{
				(im, text, err) = renderer->render(data, path, 0, 0, progress);
			}
			exception e {
				"out of memory*" =>
					err = "content too large for heap";
					im = nil;
				"*" =>
					err = "render failed: " + e;
					im = nil;
			}

			# Signal end of progress
			progress <-= nil;
		}
	}

	# Send result back to main loop
	for(;;) {
		alt {
			casync <-= ref AsyncMsg.ContentDecoded(winid, path, im, text, err) => ;
			* =>
				sys->sleep(1);
				continue;
		}
		break;
	}
}

# Forward renderer progress updates to main loop
renderprogressforwarder(winid: int, path: string, progress: chan of ref Renderer->RenderProgress)
{
	for(;;) {
		p := <-progress;
		if(p == nil)
			return;

		alt {
			casync <-= ref AsyncMsg.ContentProgress(winid, path, p.image, p.done, p.total) => ;
			* => ;  # Drop if channel full
		}
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
	{
		alt{
		err = <-cerr =>
			row.qlock.lock();
			warning(nil, err);
			err = nil;
			bflush();
			row.qlock.unlock();
			break;
		cmsg := <-ccons =>
			row.qlock.lock();
			warning(cmsg.md, cmsg.text);
			cmsg = nil;
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
				{
					if(look->search(t, c.name, len c.name)){
						t.delete(t.q0, t.q1, TRUE);
						t.setselect(0, 0);
					}
				}
				exception{
					* =>
						warning(nil, "search: " + utils->getexc() + "\n");
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
	exception{
		* =>
			warning(nil, "waittask: " + utils->getexc() + "\n");
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

imagescroll(w: ref Window, buttons: int)
{
	if(w.bodyimage == nil)
		return;

	imw := w.bodyimage.r.dx();
	imh := w.bodyimage.r.dy();
	bodyw := w.body.all.dx();
	bodyh := w.body.all.dy();
	if(imw <= 0 || imh <= 0 || bodyw <= 0 || bodyh <= 0)
		return;

	# Compute virtual display dimensions (same formula as drawimage)
	scalex := (bodyw * 1000) / imw;
	scaley := (bodyh * 1000) / imh;
	fitscale := scalex;
	if(scaley < fitscale)
		fitscale = scaley;
	zoom := w.zoomscale;
	if(zoom < 100)
		zoom = 100;
	dispw := (imw * fitscale * zoom) / (1000 * 100);
	disph := (imh * fitscale * zoom) / (1000 * 100);
	if(dispw < 1) dispw = 1;
	if(disph < 1) disph = 1;

	if(dispw <= bodyw && disph <= bodyh){
		# Image fits at this zoom — page navigation
		if(buttons & 16)
			w.asynccontentcommand("NextPage", nil);
		else if(buttons & 8)
			w.asynccontentcommand("PrevPage", nil);
		return;
	}

	# Zoomed in — smooth scroll by 20% of viewport
	vph := (bodyh * imh) / disph;
	step := vph / 5;
	if(step < 10) step = 10;

	oy := w.imageoffset.y;
	maxoy := imh - vph;
	if(maxoy < 0) maxoy = 0;

	if(buttons & 16){
		# Scroll down
		if(oy >= maxoy){
			# At bottom — next page, start at top
			w.imageoffset.y = 0;
			w.asynccontentcommand("NextPage", nil);
			return;
		}
		oy += step;
	} else if(buttons & 8){
		# Scroll up
		if(oy <= 0){
			# At top — prev page, start at bottom
			w.imageoffset.y = 16r7FFFFFFF;
			w.asynccontentcommand("PrevPage", nil);
			return;
		}
		oy -= step;
	}
	if(oy < 0) oy = 0;
	if(oy > maxoy) oy = maxoy;
	w.imageoffset.y = oy;
	w.drawimage();
}

imagedrag(w: ref Window)
{
	# Pre-render full page at zoom level (one-time cost)
	prerendered := w.prerenderzoomed();
	if(prerendered == nil)
		return;	# Not zoomed or no image

	r := w.body.all;
	bodyw := r.dx();
	bodyh := r.dy();
	pw := prerendered.r.dx();
	ph := prerendered.r.dy();
	imw := w.bodyimage.r.dx();
	imh := w.bodyimage.r.dy();

	# Convert current source offset to display coordinates
	dispox := (w.imageoffset.x * pw) / imw;
	dispoy := (w.imageoffset.y * ph) / imh;

	startmx := mouse.xy.x;
	startmy := mouse.xy.y;
	startdox := dispox;
	startdoy := dispoy;

	ox := dispox;
	oy := dispoy;

	maxox := pw - bodyw;
	maxoy := ph - bodyh;
	if(maxox < 0) maxox = 0;
	if(maxoy < 0) maxoy = 0;

	while(mouse.buttons & 1){
		dx := startmx - mouse.xy.x;
		dy := startmy - mouse.xy.y;
		ox = startdox + dx;
		oy = startdoy + dy;

		# Clamp
		if(ox < 0) ox = 0;
		if(oy < 0) oy = 0;
		if(ox > maxox) ox = maxox;
		if(oy > maxoy) oy = maxoy;

		# Fast blit from pre-rendered image (no scaling needed)
		draw(mainwin, r, w.body.frame.cols[BACK], nil, Point(0, 0));
		draw(mainwin, r, prerendered, nil, Point(prerendered.r.min.x + ox, prerendered.r.min.y + oy));
		bflush();
		*mouse = *<-dat->cmouse;
	}

	# Convert final display offset back to source coordinates
	w.imageoffset.x = (ox * imw) / pw;
	w.imageoffset.y = (oy * imh) / ph;

	# Drain remaining button events
	while(mouse.buttons)
		frgetmouse();

	# Final quality render at new position
	w.drawimage();
}

frgetmouse()
{
	bflush();
	*mouse = *<-dat->cmouse;
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

colinit()
{
	tagcols = array[NCOL] of ref Draw->Image;
	textcols = array[NCOL] of ref Draw->Image;

	tagcols[BACK] = display.colormix(Draw->Palebluegreen, Draw->White);
	tagcols[HIGH] = display.color(Draw->Palegreygreen);
	tagcols[BORD] = display.color(Draw->Purpleblue);
	tagcols[TEXT] = black;
	tagcols[HTEXT] = black;
	textcols[BACK] = display.colormix(Draw->Paleyellow, Draw->White);
	textcols[HIGH] = display.color(Draw->Darkyellow);
	textcols[BORD] = display.color(Draw->Yellowgreen);
	textcols[TEXT] = black;
	textcols[HTEXT] = black;

	but2col = display.rgb(16raa, 16r00, 16r00);
	but3col = display.rgb(16r00, 16r66, 16r00);
	but2colt = white;
	but3colt = white;
	modbutcol =  display.rgb(16r00, 16r00, 16r99);
	
	colbordercol = display.black;
	rowbordercol = display.black;
	bgcol = white;		# Default background for empty areas
}

iconinit()
{
	r : Rect;

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
	draw(modbutton, r, modbutcol, nil, (0, 0));	# was DMedblue

	r = button.r;
	colbutton = balloc(r, mainwin.chans, Draw->White);
	draw(colbutton, r, tagcols[BACK], nil, r.min);
	r.max.x -= 2;
	draw(colbutton, r, tagcols[BORD], nil, (0, 0));

	arrowcursor = ref Cursor((-1, -1), (16, 32), arrowbits);
	boxcursor = ref Cursor((-7, -7), (16, 32), boxbits);

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
	d := 0;
	if (s[n] >= 'A' && s[n] <= 'F')
		d = ((s[n] - 'A' + 10)<<4);
	else
		d =  ((s[n]-'0') << 4);
	n++;
	if (s[n] >= 'A' && s[n] <= 'F')
		d |= (s[n] - 'A' + 10);
	else
		d |=  (s[n]-'0');
	
	return d;
}

rgb(s : string, n : int) : (int, int, int)
{
	return (col(s, n), col(s, n+2), col(s, n+4));
}
	
cenv(s : string, t : string, but : int, i : ref Image) : ref Image
{
	c := utils->getenv("xenith-" + s + "-" + t + "-" + string but);
	if (c == nil)
		c = utils->getenv("xenith-" + s + "-" + string but);
	if (c == nil && but != 0)
		c = utils->getenv("xenith-" + s);
	if(c != nil && c[0] == '\''){
		c = c[1:len c - 1];
	}
	if (c != nil) {
		if (c[0] == '#' && len c >= 7) {
			(r, g, b) := rgb(c, 1);
			cmap1 := (r<<24 | g <<16 | b << 8 | 16rff);
			if (len c >= 15 && c[7] == '/' && c[8] == '#') {
				(r, g, b) = rgb(c, 9);
				cmap2 :=(r<<24 | g <<16 | b << 8 | 16rff);
				return display.colormix(cmap1, cmap2);
			}
			return display.color(cmap1);
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

applytheme(name: string)
{
	if (name == nil || name == "" || name == "plan9")
		return;		# Default theme, no env vars needed

	theme: array of (string, string);
	case name {
	"catppuccin" or "dark" or "mocha" =>
		theme = catppuccintheme;
	* =>
		warning(nil, "unknown theme: " + name + "\n");
		return;
	}

	for (i := 0; i < len theme; i++)
		utils->setenv("xenith-" + theme[i].t0, theme[i].t1);
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
	modbutcol = cenv("mod", "but", 0, modbutcol);
	tagcols[TEXT] = cenv("fg", "tag", 0, tagcols[TEXT]);
	tagcols[BACK] = cenv("bg", "tag", 0, tagcols[BACK]);
	tagcols[HTEXT] = cenv("fg", "tag", 1, tagcols[HTEXT]);
	tagcols[HIGH] = cenv("bg", "tag", 1, tagcols[HIGH]);
	colbordercol = cenv("bord", "col", 0, display.black);
	rowbordercol = cenv("bord", "row", 0, display.black);
	tagcols[BORD] = cenv("bord", "tag", 0, tagcols[BORD]);
	textcols[BORD] = cenv("bord", "text", 0, textcols[BORD]);
	bgcol = cenv("bg", "col", 0, bgcol);
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
		while(plumbmsg->init(1, "edit", Dat->PLUMBSIZE) < 0){
			sys->sleep(2000);
		}
		plumbed = 1;
		for(;;){
			msg := Msg.recv();
			if(msg == nil){
				sys->print("Xenith: can't read /chan/plumb.edit: %r\n");
				plumbpid = 0;
				plumbed = 0;
				break;
			}
			if(msg.kind != "text"){
				sys->print("Xenith: can't interpret '%s' kind of message\n", msg.kind);
				continue;
			}
			# sys->print("msg %s\n", string msg.data);
			cplumb <-= msg;
		}
	}
}
