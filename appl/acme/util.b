implement Utils;

include "common.m";
include "sh.m";
include "env.m";

sys : Sys;
draw : Draw;
gui : Gui;
acme : Acme;
dat : Dat;
graph : Graph;
textm : Textm;
windowm : Windowm;
columnm : Columnm;
rowm : Rowm;
scrl : Scroll;
look : Look;

RELEASECOPY : import acme;
Point, Rect : import draw;
Astring, TRUE, FALSE, Mntdir, Lock : import dat;
mouse, activecol, seltext, row : import dat;
cursorset : import graph;
mainwin : import gui;
Text : import textm;
Window : import windowm;
Column : import columnm;
Row : import rowm;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	draw = mods.draw;
	gui = mods.gui;
	acme = mods.acme;
	dat = mods.dat;
	graph = mods.graph;
	textm = mods.textm;
	windowm = mods.windowm;
	columnm = mods.columnm;
	rowm = mods.rowm;
	scrl = mods.scroll;
	look = mods.look;

	stderr = sys->fildes(2);
}

min(x : int, y : int) : int
{
	if (x < y)
		return x;
	return y;
}

max(x : int, y : int) : int
{
	if (x > y)
		return x;
	return y;
}

abs(x : int) : int
{
	if (x < 0)
		return -x;
	return x;
}

isalnum(c : int) : int
{
	#
	# Hard to get absolutely right.  Use what we know about ASCII
	# and assume anything above the Latin control characters is
	# potentially an alphanumeric.
	#
	if(c <= ' ')
		return FALSE;
	if(16r7F<=c && c<=16rA0)
		return FALSE;
	if(strchr("!\"#$%&'()*+,-./:;<=>?@[\\]^`{|}~", c) >= 0)
		return FALSE;
	return TRUE;
	# return ('a' <= c && c <= 'z') || 
	#	   ('A' <= c && c <= 'Z') ||
	#	   ('0' <= c && c <= '9');
}

strchr(s : string, c : int) : int
{
	for (i := 0; i < len s; i++)
		if (s[i] == c)
			return i;
	return -1;
} 

strrchr(s : string, c : int) : int
{
	for (i := len s - 1; i >= 0; i--)
		if (s[i] == c)
			return i;
	return -1;
}

strncmp(s, t : string, n : int) : int
{
	if (len s > n)
		s = s[0:n];
	if (len t > n)
		t = t[0:n];
	if (s < t)
		return -1;
	if (s > t)
		return 1;
	return 0;
}

env : Env;

getenv(s : string) : string
{
	if (env == nil)
		env = load Env Env->PATH;
	e := env->getenv(s);
	if(e != nil && e[len e - 1] == '\n')	# shell bug
		return e[0: len e -1];
	return e;
}

setenv(s, t : string)
{
	if (env == nil)
		env = load Env Env->PATH;
	env->setenv(s, t);
}

stob(s : string, n : int) : array of byte
{
	b := array[2*n] of byte;
	for (i := 0; i < n; i++) {
		b[2*i] = byte (s[i]&16rff);
		b[2*i+1] = byte ((s[i]>>8)&16rff);
	}
	return b;
}

btos(b : array of byte, s : ref Astring)
{
	n := (len b)/2;
	for (i := 0; i < n; i++)
		s.s[i] = int b[2*i] | ((int b[2*i+1])<<8);
}

reverse(ol : list of string) : list of string
{
	nl : list of string;

	nl = nil;
	while (ol != nil) {
		nl = hd ol :: nl;
		ol = tl ol;
	}
	return nl;
}

nextarg(p : ref Arg) : int
{
	bp : string;

	if(p.av != nil){
		bp = hd p.av;
		if(bp != nil && bp[0] == '-'){
			p.p = bp[1:];
			p.av = tl p.av;
			return 1;
		}
	}
	p.p = nil;
	return 0;
}

arginit(av : list of string) : ref Arg
{
	p : ref Arg;

	p = ref Arg;
	p.arg0 = hd av;
	p.av = tl av;
	nextarg(p);
	return p;
}

argopt(p : ref Arg) : int
{
	r : int;

	if(p.p == nil && nextarg(p) == 0)
		return 0;
	r = p.p[0];
	p.p = p.p[1:];
	return r;
}

argf(p : ref Arg) : string
{
	bp : string;

	if(p.p != nil){
		bp = p.p;
		p.p = nil;
	} else if(p.av != nil){
		bp = hd p.av;
		p.av = tl p.av;
	} else
		bp = nil;
	return bp;
}

exec(cmd : string, argl : list of string)
{
	file := cmd;
	if(len file<4 || file[len file-4:]!=".dis")
		file += ".dis";

	c := load Command file;
	if(c == nil) {
		err := sys->sprint("%r");
		if(file[0]!='/' && file[0:2]!="./"){
			c = load Command "/dis/"+file;
			if(c == nil)
				err = sys->sprint("%r");
		}
		if(c == nil){
			# debug(sys->sprint("file %s not found\n", file));
			sys->fprint(stderr, "%s: %s\n", cmd, err);
			return;
		}
	}
	c->init(acme->acmectxt, argl);
}

getuser() : string
{
  	fd := sys->open("/dev/user", sys->OREAD);
  	if(fd == nil)
    		return "";

  	buf := array[128] of byte;
  	n := sys->read(fd, buf, len buf);
  	if(n < 0)
    		return "";

  	return string buf[0:n];	
}

gethome(usr : string) : string
{
	if (usr == nil)
		usr = "tmp";
	return "/usr/" + usr;
}

postnote(t : int, this : int, pid : int, note : string) : int
{
	if (pid == this || pid == 0)
		return 0;
	# fd := sys->open("/prog/" + string pid + "/ctl", sys->OWRITE);
	fd := sys->open("#p/" + string pid + "/ctl", sys->OWRITE);
	if (fd == nil)
		return -1;
	if (t == PNGROUP)
		note += "grp";
	sys->fprint(fd, "%s", note);
	fd = nil;
	return 0;
}

error(s : string)
{
	sys->fprint(stderr, "acme: %s: %r\n", s);
	debug(sys->sprint("error %s : %r\n", s));
	# s[-1] = 0;	# create broken process for debugging
	acme->acmeexit("error");
}

dlock : ref Lock;
dfd : ref Sys->FD;

debuginit()
{
	if (RELEASECOPY)
		return;
	dfd = sys->create("./debug", Sys->OWRITE, 8r600);
	# fd = nil;
	dlock = Lock.init();
}

debugpr(s : string)
{
	if (RELEASECOPY)
		return;
	# fd := sys->open("./debug", Sys->OWRITE);
	# sys->seek(fd, big 0, Sys->SEEKEND);
	sys->fprint(dfd, "%s", s);
	# fd = nil;
}

debug(s : string)
{
	if (RELEASECOPY)
		return;
	if (dfd == nil)
		return;
	dlock.lock();
	debugpr(s);	
	dlock.unlock();
}

memfd : ref Sys->FD;
memb : array of byte;

memdebug(s : string)
{
	if (RELEASECOPY)
		return;
	dlock.lock();
	if (memfd == nil) {
		sys->bind("#c", "/usr/jrf/mnt", Sys->MBEFORE);
		memfd = sys->open("/usr/jrf/mnt/memory", Sys->OREAD);
		memb = array[1024] of byte;
	}
	sys->seek(memfd, big 0, 0);
	n := sys->read(memfd, memb, len memb);
	if (n <= 0) {
		dlock.unlock();
		debug(sys->sprint("bad read %r\n"));
		return;
	}
	s = s + " : " + string memb[0:n] + "\n";
	dlock.unlock();
	debug(s);
	s = nil;
}

rgetc(s : string, n : int) : int
{
	if (n < 0 || n >= len s)
		return 0;
	return s[n];
}

tgetc(t : ref Text, n : int) : int
{
	if(n >= t.file.buf.nc)
		return 0;
	return t.readc(n);
}

skipbl(r : string, n : int) : (string, int)
{
	i : int = 0;

	while(n>0 && (r[i]==' ' || r[i]=='\t' || r[i]=='\n')){
		--n;
		i++;
	}
	return (r[i:], n);
}

findbl(r : string, n : int) : (string, int)
{
	i : int = 0;

	while(n>0 && r[i]!=' ' && r[i]!='\t' && r[i]!='\n'){
		--n;
		i++;
	}
	return (r[i:], n);
}

prevmouse : Point;
mousew : ref Window;

savemouse(w : ref Window)
{
	prevmouse = mouse.xy;
	mousew = w;
}

restoremouse(w : ref Window)
{
	if(mousew!=nil && mousew==w)
		cursorset(prevmouse);
	mousew = nil;
}

clearmouse()
{
	mousew = nil;
}

#
# Heuristic city.
#
newwindow(t : ref Text) : ref Window
{
	c : ref Column;
	w, bigw, emptyw : ref Window;
	emptyb : ref Text;
	i, y, el : int;

	if(activecol != nil)
		c = activecol;
	else if(seltext != nil && seltext.col != nil)
		c = seltext.col;
	else if(t != nil && t.col != nil)
		c = t.col;
	else{
		if(row.ncol==0 && row.add(nil, -1)==nil)
			error("can't make column");
		c = row.col[row.ncol-1];
	}
	activecol = c;
	if(t==nil || t.w==nil || c.nw==0)
		return c.add(nil, nil, -1);

	# find biggest window and biggest blank spot
	emptyw = c.w[0];
	bigw = emptyw;
	for(i=1; i<c.nw; i++){
		w = c.w[i];
		# use >= to choose one near bottom of screen
		if(w.body.frame.maxlines >= bigw.body.frame.maxlines)
			bigw = w;
		if(w.body.frame.maxlines-w.body.frame.nlines >= emptyw.body.frame.maxlines-emptyw.body.frame.nlines)
			emptyw = w;
	}
	emptyb = emptyw.body;
	el = emptyb.frame.maxlines-emptyb.frame.nlines;
	# if empty space is big, use it
	if(el>15 || (el>3 && el>(bigw.body.frame.maxlines-1)/2))
		y = emptyb.frame.r.min.y+emptyb.frame.nlines*(graph->font).height;
	else{
		# if this window is in column and isn't much smaller, split it
		if(t.col==c && t.w.r.dy()>2*bigw.r.dy()/3)
			bigw = t.w;
		y = (bigw.r.min.y + bigw.r.max.y)/2;
	}
	w = c.add(nil, nil, y);
	if(w.body.frame.maxlines < 2)
		w.col.grow(w, 1, 1);
	return w;
}

stralloc(n : int) : ref Astring
{
	r := ref Astring;
	ab := array[n] of { * => byte 'z' };
	r.s = string ab;
	if (len r.s != n)
		error("bad stralloc");
	ab = nil;
	return r;
}

strfree(s : ref Astring)
{
	s.s = nil;
	s = nil;
}

access(s : string) : int
{
	fd := sys->open(s, 0);
	if (fd == nil)
		return -1;
	fd = nil;
	return 0;
}

errorwin(dir : string, ndir : int, incl : array of string, nincl : int) : ref Window
{
	w : ref Window;
	r : string;
	i, n : int;

	n = ndir;
	r = dir + "+Errors";
	n += 7;
	w = look->lookfile(r, n);
	if(w == nil){
		w = row.col[row.ncol-1].add(nil, nil, -1);
		w.filemenu = FALSE;
		w.setname(r, n);
	}
	r = nil;
	for(i=nincl; --i>=0; )
		w.addincl(incl[i], n);
	return w;
}

warning(md : ref Mntdir, s : string)
{
	n, q0, owner : int;
	w : ref Window;
	t : ref Text;

	debug(sys->sprint("warning %s\n", s));
	if (row == nil) {
		sys->fprint(sys->fildes(2), "warning: %s\n", s);
		debug(s); 
		debug("\n");
		return;
	}	
	if(row.ncol == 0){	# really early error
		row.init(mainwin.clipr);
		row.add(nil, -1);
		row.add(nil, -1);
		if(row.ncol == 0)
			error("initializing columns in warning()");
	}
	if(md != nil){
		for(;;){
			w = errorwin(md.dir, md.ndir, md.incl, md.nincl);
			w.lock('E');
			if (w.col != nil)
				break;
			# window was deleted too fast
			w.unlock();
		}
	}else
		w = errorwin(nil, 0, nil, 0);
	t = w.body;
	owner = w.owner;
	if(owner == 0)
		w.owner = 'E';
	w.commit(t);
	(q0, n) = t.bsinsert(t.file.buf.nc, s, len s, TRUE);
	t.show(q0, q0+n);
	t.w.settag();
	scrl->scrdraw(t);
	w.owner = owner;
	w.dirty = FALSE;
	if(md != nil)
		w.unlock();
}

getexc(): string
{
	f := "/prog/"+string sys->pctl(0, nil)+"/exception";
	if((fd := sys->open(f, Sys->OREAD)) == nil)
		return nil;
	b := array[8192] of byte;
	if((n := sys->read(fd, b, len b)) < 0)
		return nil;
	return string b[0: n];
}

# returns pc, module, exception
readexc(): (int, string, string)
{
	s := getexc();
	if(s == nil)
		return (0, nil, nil);
	(m, l) := sys->tokenize(s, " ");
	if(m < 3)
		return (0, nil, nil);
	pc := int hd l;	l = tl l;
	mod := hd l;	l = tl l;
	exc := hd l;	l = tl l;
	for( ; l != nil; l = tl l)
		exc += " " + hd l;
	return (pc, mod, exc);
}
