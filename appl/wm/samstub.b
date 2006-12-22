implement Samstub;

include "sys.m";
sys: Sys;
fprint, FD, fildes: import sys;

stderr: ref FD;

include "draw.m";
draw: Draw;

include "samterm.m";
samterm: Samterm;
Text, Menu, Context, Flayer, Section: import samterm;

include "samtk.m";
samtk: Samtk;
panic, whichtext, whichmenu: import samtk;

include "samstub.m";

sendsam:	chan of ref Sammsg;
recvsam:	chan of ref Sammsg;

snarflen:	int;

ctxt: ref Context;

requested: list of (int, int);

tname := array [] of {
	"Tversion",
	"Tstartcmdfile",
	"Tcheck",
	"Trequest",
	"Torigin",
	"Tstartfile",
	"Tworkfile",
	"Ttype",
	"Tcut",
	"Tpaste",
	"Tsnarf",
	"Tstartnewfile",
	"Twrite",
	"Tclose",
	"Tlook",
	"Tsearch",
	"Tsend",
	"Tdclick",
	"Tstartsnarf",
	"Tsetsnarf",
	"Tack",
	"Texit",
};

hname := array [] of {
	"Hversion",
	"Hbindname",
	"Hcurrent",
	"Hnewname",
	"Hmovname",
	"Hgrow",
	"Hcheck0",
	"Hcheck",
	"Hunlock",
	"Hdata",
	"Horigin",
	"Hunlockfile",
	"Hsetdot",
	"Hgrowdata",
	"Hmoveto",
	"Hclean",
	"Hdirty",
	"Hcut",
	"Hsetpat",
	"Hdelname",
	"Hclose",
	"Hsetsnarf",
	"Hsnarflen",
	"Hack",
	"Hexit",
};

init(c: ref Context)
{
	ctxt = c;
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;

	stderr = fildes(2);

	samterm = load Samterm Samterm->PATH;

	samtk = load Samtk Samtk->PATH;
	samtk->init(ctxt);

	requested = nil;
}

start(): (ref Samio, chan of ref Sammsg)
{
	sys = load Sys Sys->PATH;

	sys->bind("#C", "/", sys->MAFTER);

	# Allocate a cmd device
	ctl := sys->open("/cmd/clone", sys->ORDWR);
	if(ctl == nil) {
		fprint(stderr, "can't open /cmd/clone\n");
		return (nil, nil);
	}

	# Find out which one
	buf := array[32] of byte;
	n := sys->read(ctl, buf, len buf);
	if(n <= 0) {
		fprint(stderr, "can't read cmd device\n");
		return (nil, nil);
	}

	dir := "/cmd/"+string buf[0:n];

	# Start the Command
	n = sys->fprint(ctl, "exec "+ SAM);
	if(n <= 0) {
		fprint(stderr, "can't exec %s\n", SAM);
		return (nil, nil);
	}

	data := sys->open(dir+"/data", sys->ORDWR);
	if(data == nil) {
		fprint(stderr, "can't open cmd data file\n");
		return (nil, nil);
	}

	sendsam = chan of ref Sammsg;
	recvsam = chan of ref Sammsg;

	samio := ref Samio(ctl, data, array[1] of byte, 0, 0);

	spawn sender(samio, sendsam);
	spawn receiver(samio, recvsam);

	return (samio, recvsam);
}

sender(samio: ref Samio, c: chan of ref Sammsg)
{
	fprint(ctxt.logfd, "sender started\n");
	for (;;) {
		h := <- c;
		if (h == nil) return;
		buf := array[3 + len h.mdata] of byte;
		buf[0] = byte h.mtype;
		buf[1] = byte h.mcount;
		buf[2] = byte (h.mcount >> 8);
		buf[3:] = h.mdata;
		sys->write(samio.data, buf, len buf);
	}
}

receiver(samio: ref Samio, msgchan: chan of ref Sammsg)
{
	c: int;

	fprint(ctxt.logfd, "receiver started\n");

	state := 0;
	i := 0;
	errs := 0;

	h: ref Sammsg;

	for (;;) {
		if (samio.count == 0) {
			n := sys->read(samio.data, samio.buffer, len samio.buffer);
			if (n <= 0) {
				fprint(stderr, "Read error on sam's pipe\n");
				return;
			}
			samio.index = 0;
			samio.count = n;
		}
		samio.count--;

		c = int samio.buffer[samio.index++];

		case state {
		0 =>
			h = ref Sammsg(c, 0, nil);
			state++;
			continue;
		1 =>
			h.mcount = c;
			state++;
			continue;
		2 =>
			h.mcount = h.mcount|(c<<8);
			if (h.mcount > DATASIZE || h.mcount < 0)
				panic("receiver: count>DATASIZE");
			if(h.mcount != 0) {
				h.mdata = array[h.mcount] of byte;
				i = 0;
				state++;
				continue;
			}
		3 =>
			h.mdata[i++] = byte c;
			if(i < h.mcount){
				continue;
			}
		}
		msgchan <- = h;
		h = nil;
		state = 0;
	}
}

inmesg(h: ref Sammsg): int
{

	case h.mtype {

	Hversion =>
		m := h.inshort(0);
		fprint(ctxt.logfd, "Hversion: %d\n", m);

	Hbindname =>
		m := h.inshort(0);
		vl := h.invlong(2);
		fprint(ctxt.logfd, "Hbindname: %ux, %bux\n", m, vl);
		bindname(m, int vl);

	Hcurrent =>
		m := h.inshort(0);
		fprint(ctxt.logfd, "Hcurrent: %d\n", m);
		hcurrent(m);

	Hmovname =>
		m := h.inshort(0);
		fprint(ctxt.logfd, "Hmovname: %d, %s\n", m, string h.mdata[2:]);
		movename(m, string h.mdata[2:]);

	Hgrow =>
		m := h.inshort(0);
		l1 := h.inlong(2);
		l2 := h.inlong(6);
		fprint(ctxt.logfd, "Hgrow: %d, %d, %d\n", m, l1, l2);
		hgrow(m, l1, l2);

	Hnewname =>
		m := h.inshort(0);
		fprint(ctxt.logfd, "Hnewname: %d\n", m);
		newname(m);

	Hcheck0 =>
		m := h.inshort(0);
		fprint(ctxt.logfd, "Hcheck0: %d\n", m);
		i := whichmenu(m);
		if (i >= 0) {
			t := ctxt.menus[i].text;
			if (t != nil)
				t.lock++;
			outTs(Tcheck, m);
		}

	Hcheck =>
		m := h.inshort(0);
		fprint(ctxt.logfd, "Hcheck: %d\n", m);
		i := whichmenu(m);
		if (i >= 0) {
			t := ctxt.menus[i].text;
			if (t != nil && t.lock)
				t.lock--;
			hcheck(t);
		}

	Hunlock =>
		fprint(ctxt.logfd, "Hunlock\n");
		clrlock();

	Hdata =>
		m := h.inshort(0);
		l := h.inlong(2);
		fprint(ctxt.logfd, "Hdata: %d, %d, %s\n",
			m, l, contract(string h.mdata[6:]));
		hdata(m, l, string h.mdata[6:]);

	Horigin =>
		m := h.inshort(0);
		l := h.inlong(2);
		fprint(ctxt.logfd, "Horigin: %d, %d\n", m, l);
		horigin(m, l);

	Hunlockfile =>
		m := h.inshort(0);
		fprint(ctxt.logfd, "Hunlockfile: %d\n", m);
		clrlock();

	Hsetdot =>
		m := h.inshort(0);
		l1 := h.inlong(2);
		l2 := h.inlong(6);
		fprint(ctxt.logfd, "Hsetdot: %d, %d, %d\n", m, l1, l2);
		hsetdot(m, l1, l2);

	Hgrowdata =>
		m := h.inshort(0);
		l1 := h.inlong(2);
		l2 := h.inlong(6);
		fprint(ctxt.logfd, "Hgrowdata: %d, %d, %d, %s\n",
			m, l1, l2, contract(string h.mdata[10:]));
		hgrowdata(m, l1, l2, string h.mdata[10:]);

	Hmoveto =>
		m := h.inshort(0);
		l := h.inlong(2);
		fprint(ctxt.logfd, "Hmoveto: %d, %d\n", m, l);
		hmoveto(m, l);

	Hclean =>
		m := h.inshort(0);
		fprint(ctxt.logfd, "Hclean: %d\n", m);
		hclean(m);

	Hdirty =>
		m := h.inshort(0);
		fprint(ctxt.logfd, "Hdirty: %d\n", m);
		hdirty(m);

	Hdelname =>
		m := h.inshort(0);
		fprint(ctxt.logfd, "Hdelname: %d\n", m);
		hdelname(m);

	Hcut =>
		m := h.inshort(0);
		l1 := h.inlong(2);
		l2 := h.inlong(6);
		fprint(ctxt.logfd, "Hcut: %d, %d, %d\n",
			m, l1, l2);
		hcut(m, l1, l2);

	Hclose =>
		m := h.inshort(0);
		fprint(ctxt.logfd, "Hclose: %d\n", m);
		hclose(m);

	Hsetpat =>
		fprint(ctxt.logfd, "Hsetpat: %s\n", string h.mdata);
		samtk->hsetpat(string h.mdata);

	Hsetsnarf =>
		m := h.inshort(0);
		fprint(ctxt.logfd, "Hsetsnarf: %d\n", m);

	Hsnarflen =>
		snarflen = h.inlong(0);
		fprint(ctxt.logfd, "Hsnarflen: %d\n", snarflen);

	Hack =>
		fprint(ctxt.logfd, "Hack\n");
		outT0(Tack);

	Hexit =>
		fprint(ctxt.logfd, "Hexit\n");
		return 1;

	-1 =>
		panic("rcv error");

	* =>
		fprint(ctxt.logfd, "type %d\n", h.mtype);
		panic("rcv unknown");
	}
	return 0;
}

Sammsg.inshort(h: self ref Sammsg, n: int): int
{
	return	((int h.mdata[n+1])<<8) |
		((int h.mdata[n]));
}

Sammsg.inlong(h: self ref Sammsg, n: int): int
{
	return	((int h.mdata[n+3])<<24) |
		((int h.mdata[n+2])<<16) |
		((int h.mdata[n+1])<< 8) |
		((int h.mdata[n]));
}

Sammsg.invlong(h: self ref Sammsg, n: int): big
{
	return	((big h.mdata[n+7])<<56) |
		((big h.mdata[n+6])<<48) |
		((big h.mdata[n+5])<<40) |
		((big h.mdata[n+4])<<32) |
		((big h.mdata[n+3])<<24) |
		((big h.mdata[n+2])<<16) |
		((big h.mdata[n+1])<< 8) |
		((big h.mdata[n]));
}

Sammsg.outcopy(h: self ref Sammsg, pos: int, data: array of byte)
{
	h.mdata[pos:] = data;
}

Sammsg.outshort(h: self ref Sammsg, pos: int, s: int)
{
	h.mdata[pos++]	= byte s;
	h.mdata[pos]	= byte (s >> 8);
}

Sammsg.outlong(h: self ref Sammsg, pos: int, s: int)
{
	h.mdata[pos++]	= byte s;
	h.mdata[pos++]	= byte (s >> 8);
	h.mdata[pos++]	= byte (s >> 16);
	h.mdata[pos]	= byte (s >> 24);
}

Sammsg.outvlong(h: self ref Sammsg, pos: int, s: big)
{
	h.mdata[pos++]	= byte s;
	h.mdata[pos++]	= byte (s >> 8);
	h.mdata[pos++]	= byte (s >> 16);
	h.mdata[pos++]	= byte (s >> 24);
	h.mdata[pos++]	= byte (s >> 32);
	h.mdata[pos++]	= byte (s >> 40);
	h.mdata[pos++]	= byte (s >> 48);
	h.mdata[pos]	= byte (s >> 56);
}

outT0(t: int)
{
	fprint(ctxt.logfd, "\t\t\t\t\t%s\n", tname[t]);
	h := ref Sammsg(t, 0, nil);
	sendsam <- = h;
}

outTs(t, s: int)
{
	fprint(ctxt.logfd, "\t\t\t\t\t%s %ux\n", tname[t], s);
	a := array[2] of byte;
	h := ref Sammsg(t, 2, a);
	h.outshort(0, s);
	sendsam <- = h;
}
	
outTv(t: int, i: big)
{
	fprint(ctxt.logfd, "\t\t\t\t\t%s %bux\n", tname[t], i);
	a := array[8] of byte;
	h := ref Sammsg(t, 8, a);
	h.outvlong(0, i);
	sendsam <- = h;
}

outTsll(t, m, l1, l2: int)
{	fprint(ctxt.logfd, "\t\t\t\t\t%s %d %d %d\n", tname[t], m, l1, l2);
	a := array[10] of byte;
	h := ref Sammsg(t, 10, a);
	h.outshort(0, m);
	h.outlong(2, l1);
	h.outlong(6, l2);
	sendsam <- = h;
}

outTsl(t, m, l: int)
{	fprint(ctxt.logfd, "\t\t\t\t\t%s %d %d\n", tname[t], m, l);
	a := array[6] of byte;
	h := ref Sammsg(t, 6, a);
	h.outshort(0, m);
	h.outlong(2, l);
	sendsam <- = h;
}

outTsls(t, m, l1, l2: int)
{	fprint(ctxt.logfd, "\t\t\t\t\t%s %d %d %d\n", tname[t], m, l1, l2);
	a := array[8] of byte;
	h := ref Sammsg(t, 8, a);
	h.outshort(0, m);
	h.outlong(2, l1);
	h.outshort(6, l2);
	sendsam <- = h;
}
	
outTslS(t, s1, l1: int, s: string)
{
	fprint(ctxt.logfd, "\t\t\t\t\t%s %d %d %s\n", tname[t], s1, l1, s);
	a := array[6 + len array of byte s] of byte;
	h := ref Sammsg(t, len a, a);
	h.outshort(0, s1);
	h.outlong(2, l1);
	h.outcopy(6, array of byte s);
	sendsam <- = h;
}

newname(tag: int)
{
	menuins(0, "dummy", nil, tag);
}

bindname(tag, l: int)
{
	if ((m := whichmenu(tag)) < 0) panic("bindname: whichmenu");
	if ((l = whichtext(l)) < 0) panic("bindname: whichtext");
	if (ctxt.menus[m].text != nil)
		return;		# Already bound
	t := ctxt.texts[l];
	t.tag = tag;
	for (fls := t.flayers; fls != nil; fls = tl fls) (hd fls).tag = tag;
	ctxt.menus[m].text = t;
}

menuins(m: int, s: string, t: ref Text, tag: int)
{
	newmenus := array [len ctxt.menus+1] of ref Menu;
	menu := ref Menu(
		tag,	# tag
		s,	# name
		t	# text
	);
	if (m > 0)
		newmenus[0:] = ctxt.menus[0:m];
	newmenus[m] = menu;
	if (m < len ctxt.menus)
		newmenus[m+1:] = ctxt.menus[m:];	
	ctxt.menus = newmenus;

	samtk->menuins(m, s);
}

menudel(m: int)
{
	if (len ctxt.menus == 0 || m >= len ctxt.menus || ctxt.menus[m].text != nil)
		panic("menudel");
	newmenus := array [len ctxt.menus - 1] of ref Menu;
	newmenus[0:] = ctxt.menus[0:m];
	newmenus[m:] = ctxt.menus[m+1:];
	ctxt.menus = newmenus;
	samtk->menudel(m);
}

outcmd() {
	if(ctxt.work != nil) {
		fl := ctxt.work;
		outTsll(Tworkfile, fl.tag, fl.dot.first, fl.dot.last);
	}
}

hclose(m: int)
{
	i: int;

	# close LAST window of a file
	if((m = whichmenu(m)) < 0) panic("hclose: whichmenu");
	t := ctxt.menus[m].text;
	if (tl t.flayers != nil) panic("hclose: flayers");
	fl := hd t.flayers;
	fl.t = nil;
	for (i = 0; i< len ctxt.flayers; i++)
		if (ctxt.flayers[i] == fl) break;
	if (i == len ctxt.flayers) panic("hclose: ctxt.flayers");
	samtk->chandel(i);
	t.flayers = nil;
	for (i = 0; i< len ctxt.texts; i++)
		if (ctxt.texts[i] == ctxt.menus[m].text) break;
	if (i == len ctxt.texts) panic("hclose: ctxt.texts");
	ctxt.texts[i:] = ctxt.texts[i+1:];
	ctxt.texts = ctxt.texts[:len ctxt.texts - 1];
	ctxt.menus[m].text = nil;
	ctxt.which = nil;
	samtk->focus(hd ctxt.cmd.flayers);
}

close(win, tag: int)
{
	nfls: list of ref Flayer;

	if ((m := whichtext(tag)) < 0) panic("close: text");
	t := ctxt.texts[m];
	if ((m = whichmenu(tag)) < 0) panic("close: menu");
	if (len t.flayers == 1) {
		outTs(Tclose, tag);
		setlock();
		return;
	}
	fl := ctxt.flayers[win];
	nfls = nil;
	for (fls := t.flayers; fls != nil; fls = tl fls)
		if (hd fls != fl) nfls = hd fls :: nfls;
	t.flayers = nfls;
	samtk->chandel(win);
	fl.t = nil;
	samtk->settitle(t, ctxt.menus[m].name);
	ctxt.which = nil;
}

hdelname(m: int)
{
	# close LAST window of a file
	if((m = whichmenu(m)) < 0) panic("hdelname: whichmenu");
	if (ctxt.menus[m].text != nil) panic("hdelname: text");
	ctxt.menus[m:] = ctxt.menus[m+1:];
	ctxt.menus = ctxt.menus[:len ctxt.menus - 1];
	samtk->menudel(m);
	ctxt.which = nil;
}

hdirty(m: int)
{
	if((m = whichmenu(m)) < 0) panic("hdirty: whichmenu");
	if (ctxt.menus[m].text == nil) panic("hdirty: text");
	ctxt.menus[m].text.state |= Samterm->Dirty;
	samtk->settitle(ctxt.menus[m].text, ctxt.menus[m].name);
}

hclean(m: int)
{
	if((m = whichmenu(m)) < 0) panic("hclean: whichmenu");
	if (ctxt.menus[m].text == nil) panic("hclean: text");
	ctxt.menus[m].text.state &= ~Samterm->Dirty;
	samtk->settitle(ctxt.menus[m].text, ctxt.menus[m].name);
}

movename(tag: int, s: string)
{
	i := whichmenu(tag);
	if (i < 0) panic("movename: whichmenu");

	t := ctxt.menus[i].text;

	ctxt.menus[i].text = nil;	# suppress panic in menudel
	menudel(i);

	if(t == ctxt.cmd)
		i = 0;
	else {
		if (len ctxt.menus > 0 && ctxt.menus[0].text == ctxt.cmd)
			i = 1;
		else
			i = 0;
		for(; i < len ctxt.menus; i++) {
			if (s < ctxt.menus[i].name)
				break;
		}
	}
	if (t != nil) samtk->settitle(t, s);
	menuins(i, s, t, tag);
}

hcheck(t: ref Text)
{
	if (t == nil) {
		fprint(ctxt.logfd, "hcheck: no text in menu entry\n");
		return;
	}
	for (fls := t.flayers; fls != nil; fls = tl fls) {
		fl := hd fls;
		scrollto(fl, fl.scope.first);
	}
}

setlock()
{
	ctxt.lock++;
	samtk->allflayers("cursor -bitmap cursor.wait");
}

clrlock()
{
	if (ctxt.lock > 0)
		ctxt.lock--;
	else
		fprint(ctxt.logfd, "lock: wasn't locked\n");
	if (ctxt.lock == 0)
		samtk->allflayers("cursor -default; update");
}

hcut(m, where, howmuch: int)
{
	if((m = whichmenu(m)) < 0) panic("hcut: whichmenu");
	t := ctxt.menus[m].text;
	if (t == nil) panic("hcut -- no text");

#	sctdump(t.sects, "Hcut, before");
	t.nrunes -= howmuch;
	t.sects = sctdelete(t.sects, where, howmuch);
#	sctdump(t.sects, "Hcut, after");
	for (fls := t.flayers; fls != nil; fls = tl fls) {
		fl := hd fls;
		if (where < fl.scope.first) {
			if (where + howmuch <= fl.scope.first)
				fl.scope.first -= howmuch;
			else
				fl.scope.first = where;
		}
		if (where < fl.scope.last) {
			if (where + howmuch <= fl.scope.last)
				fl.scope.last -= howmuch;
			else
				fl.scope.last = where;
		}
	}
}

hgrow(tag, l1, l2: int)
{
	if((m := whichmenu(tag)) < 0) panic("hgrow: whichmenu");
	t := ctxt.menus[m].text;
	grow(t, l1, l2);
}

hdata(m, l: int, s: string)
{
	nr: list of (int, int);

	if((m = whichmenu(m)) < 0) panic("hdata: whichmenu");
	t := ctxt.menus[m].text;
	if (t == nil) panic("hdata -- no text");
	if (s != "") {
		t.sects = sctput(t.sects, l, s);
		updatefls(t, l, s);
	}
	for (nr = nil; requested != nil; requested = tl requested) {
		(r1, r2) := hd requested;
		if (r1 != m || r2 != l)
			nr = (r1, r2) :: nr;
	}
	requested = nr;
	clrlock();
}

hgrowdata(tag, l1, l2: int, s: string)
{
	if((m := whichmenu(tag)) < 0) panic("hgrow: whichmenu");
	t := ctxt.menus[m].text;
	if (t == nil) panic("hdata -- no text");
	grow(t, l1, l2);
	t.sects = sctput(t.sects, l1, s);
	updatefls(t, l1, s);
}

hsetdot(m, l1, l2: int)
{
	if((m = whichmenu(m)) < 0) panic("hsetdot: whichmenu");
	t := ctxt.menus[m].text;
	if (t == nil || t.flayers == nil) panic("hsetdot -- no text");
	samtk->setdot(hd t.flayers, l1, l2);
}

hcurrent(tag: int)
{
	if ((i := whichmenu(tag)) < 0) panic("hcurrent: whichmenu");
	if (ctxt.menus[i].text == nil) {
		n := startfile(tag);
		ctxt.menus[i].text = ctxt.texts[n];
		if (ctxt.menus[i].name != nil)
			samtk->settitle(ctxt.texts[n], ctxt.menus[i].name);
	}
	ctxt.work = hd ctxt.menus[i].text.flayers;
}

hmoveto(m, l: int)
{
	if((m = whichmenu(m)) < 0) panic("hmoveto: whichmenu");
	t := ctxt.menus[m].text;
	fl := hd t.flayers;
	if (fl.scope.first <= l &&
	   (l < fl.scope.last || fl.scope.last == fl.scope.first))
		return;
	(n, p) := sctrevcnt(t.sects, l, fl.lines/2);
#	fprint(ctxt.logfd, "hmoveto: (n, p) = (%d, %d)\n", n, p);
	if (n < 0) {
		outTsll(Torigin, t.tag, l, fl.lines/2);
		setlock();
		return;
	}
	scrollto(fl, p);
}

startcmdfile()
{
	t := ctxt.tag++;
	n := newtext(t, 1);
	ctxt.cmd = ctxt.texts[n];
	outTv(Tstartcmdfile, big t);
}

startnewfile()
{
	t := ctxt.tag++;
	n := newtext(t, 0);
	outTv(Tstartnewfile, big t);
}

startfile(tag: int): int
{
	n := newtext(tag, 0);
	outTv(Tstartfile, big tag);
	setlock();
	return n;
}

horigin(m, l: int)
{
	if((m = whichmenu(m)) < 0) panic("hmoveto: whichmenu");
	t := ctxt.menus[m].text;
	fl := hd t.flayers;
	scrollto(fl, l);
	clrlock();
}

scrollto(fl: ref Flayer, where: int)
{
	s: string;
	n: int;

	tag := fl.tag;
	if ((i := whichtext(tag)) < 0) panic("scrollto: whichtext");
	t := ctxt.texts[i];
	
	samtk->flclear(fl);
	(n, s) = sctgetlines(t.sects, where, fl.lines);
	fl.scope.first = where;
	fl.scope.last = where + len s;
	if (s != "")
		samtk->flinsert(fl, where, s);
	if (n == 0) {
		samtk->setscrollbar(t, fl);
	} else {
		(h, l) := scthole(t, fl.scope.last);
		fl.scope.last = h;
		if (l > 0)
			outrequest(tag, h, l);
		else
			if (fl.scope.first > t.nrunes) {
				fl.scope.first = t.nrunes;
				fl.scope.last = t.nrunes;
				samtk->setscrollbar(t, fl);
			}
	}
}

scthole(t: ref Text, f: int): (int, int)
{
	p := 0;
	h := -1;
	l := 0;
	for (scts := t.sects; scts != nil; scts = tl scts) {
		sct := hd scts;
		nr := sct.nrunes;
		nt := len sct.text;
		if (h >= 0) {
			if (sct.text == "") {
				l += nr;
				if (l >= 512) return (h,512);
			} else
				return (h,l);
		}
		if (h < 0 && f < nr) {
			if (nt < nr) {
				if (f < nt) {
					h = p + nt;
					l = nr - nt;
				} else {
					h = p + f;
					l = nr - f;
				}
				if (l >= 512) return (h,512);
			}
		}
		p += sct.nrunes;
		f -= sct.nrunes;
	}
	if (h == -1) return (p, 0);
	return (h, l);
}

# return (x, p): x = -1: p -> hole; x = 0: p -> line n; x > 0: p -> eof
sctlinecount(t: ref Text, pos, n: int): (int, int)
{
	i: int;

	p := 0;
	for (scts := t.sects; scts != nil; scts = tl scts) {
		sct := hd scts;
		nr := sct.nrunes;
		nt := len sct.text;
		if (pos < nr) {
			if (pos > 0) i = pos; else i = 0;
			while (i < nt) {
				if (sct.text[i++] == '\n') n--;
				if (n == 0) return (0, p + i);
			}
			if (nt < nr) return (-1, p + nt);
		}
		p += sct.nrunes;
		pos -= sct.nrunes;
	}
	return (n, p);
}

sctrevcnt(scts: list of ref Section, pos, n: int): (int, int)
{
	if (scts == nil) return (n, 0);
	sct := hd scts;
	scts = tl scts;
	nt := len sct.text;
	nr := sct.nrunes;
	if (pos >= nr) {
		(n, pos) = sctrevcnt(scts, pos - nr, n);
		pos += nr;
	}
	if (n > 0) {
		if (nt < nr && pos > nt)
			return(-1, pos);
		for (i := pos-1; i >= 0; i--) {
			if (sct.text[i] == '\n') n--;
			if (n == 0) break;
		}
		return (n, i + 1);	
	}
	return (n, pos);
}

insertfls(t: ref Text, l: int, s: string)
{
	for (fls := t.flayers; fls != nil; fls = tl fls) {
		fl := hd fls;
		if (l < fl.scope.first || l > fl.scope.last) continue;
		samtk->flinsert(fl, l, s);
		samtk->setscrollbar(t, fl);
		fl.scope.last += len s;
	}
}

updatefls(t: ref Text, l: int, s: string)
{
	for (fls := t.flayers; fls != nil; fls = tl fls) {
		fl := hd fls;
		if (l < fl.scope.first || l > fl.scope.last) continue;
		samtk->flinsert(fl, l, s);
		(x, p) := sctlinecount(t, fl.scope.first, fl.lines);
		fl.scope.last = p;
		if (x >= 0) {
			if (p > l + len s) {
				samtk->flinsert(fl, l + len s,
					sctget(t.sects, l + len s, p));
			}
			if (x == 0)
				samtk->fldelexcess(fl);
		} else {
			(h1, h2) := scthole(t, l);
			fl.scope.last = h1;
			if (h2 > 0) {
				outrequest(t.tag, h1, h2);
				continue;
			} else {
				panic("Can't happen ??");
			}
		}
		samtk->setscrollbar(t, fl);
	}
}

outrequest(tag, h1, h2: int) {
	for (l := requested; l != nil; l = tl l) {
		(r1, r2) := hd l;
		if (r1 == tag && r2 == h1) return;
	}
	outTsls(Trequest, tag, h1, h2);
	requested = (tag, h1) :: requested;
	setlock();
}

deletefls(t: ref Text, pos, nbytes: int)
{
	for (fls := t.flayers; fls != nil; fls = tl fls) {
		fl := hd fls;
		if (pos >= fl.scope.last) continue;
		if (pos + nbytes <= fl.scope.first || pos >= fl.scope.last) {
			fl.scope.first -= nbytes;
			fl.scope.last -= nbytes;
			continue;
		}
		samtk->fldelete(fl, pos, pos + nbytes);
		(x, p) := sctlinecount(t, fl.scope.first, fl.lines);
		if (x >= 0 && p > fl.scope.last) {
			samtk->flinsert(fl, fl.scope.last,
				sctget(t.sects, fl.scope.last, p));
			fl.scope.last = p;
		} else {
			fl.scope.last = p;
			(h1, h2) := scthole(t, fl.scope.last);
			if (h2 > 0)
				outrequest(t.tag, h1, h2);
		}
		samtk->setscrollbar(t, fl);
	}
}

contract(s: string): string
{
	if (len s < 32)
		cs := s;
	else
		cs = s[0:16] + " ... " + s[len s - 16:];
	for (i := 0; i < len cs; i++)
		if (cs[i] == '\n') cs[i] = '\u008a';
	return cs;
}

cleanout()
{
	if ((fl := ctxt.which) == nil) return;
	if ((i := whichtext(fl.tag)) < 0) panic("cleanout: whichtext");
	t := ctxt.texts[i];

	if (fl.typepoint >= 0 && fl.dot.first > fl.typepoint) {
		s := sctget(t.sects, fl.typepoint, fl.dot.first);
		outTslS(Samstub->Ttype, fl.tag, fl.typepoint, s);
		t.state &= ~Samterm->LDirty;
	}
	fl.typepoint = -1;
}

newtext(tag, tp: int): int
{
	n := len ctxt.texts;
	t := ref Text(
		tag,					# tag
		0,					# lock
		samtk->newflayer(tag, tp) :: nil,	# flayers
		0,					# nrunes
		nil,					# sects
		0					# state
	);
	texts := array [n + 1] of ref Text;
	texts[0:] = ctxt.texts;
	texts[n] = t;
	ctxt.texts = texts;
	samtk->newcur(t, hd t.flayers);
	return n;
}

keypress(key: string)
{
	# Find text and flayer
	fl := ctxt.which;
	tag := fl.tag;
	if ((i := whichtext(tag)) < 0) panic("keypress: whichtext");
	t := ctxt.texts[i];

	if (fl.dot.last != fl.dot.first) {
		cut(t, fl);
	}

	case (key) {
	"\b" =>
		if (t.nrunes == 0 || fl.dot.first == 0)
			return;
		fl.dot.first--;
		if (fl.typepoint >= 0 && fl.dot.first >= fl.typepoint) {
			t.nrunes -= fl.dot.last - fl.dot.first;
			t.sects = sctdelete(t.sects, fl.dot.first, fl.dot.last - fl.dot.first);
			deletefls(t, fl.dot.first, fl.dot.last - fl.dot.first);
			if (fl.dot.first == fl.typepoint) {
				fl.typepoint = -1;
				t.state &= ~Samterm->LDirty;
				if ((i = whichmenu(tag)) < 0)
					panic("keypress: whichmenu");
				samtk->settitle(t, ctxt.menus[i].name);
			}
		} else {
			cut(t, fl);
		}
	* =>
		if (fl.typepoint < 0) {
			fl.typepoint = fl.dot.first;
			t.state |= Samterm->LDirty;
			if ((i = whichmenu(tag)) < 0)
				panic("keypress: whichmenu");
			samtk->settitle(t, ctxt.menus[i].name);
		}
		if (fl.dot.first > t.nrunes)
			panic("keypress -- cursor > file len");
		t.sects = sctmakeroom(t.sects, fl.dot.first, len key);
		t.nrunes += len key;
		t.sects = sctput(t.sects, fl.dot.first, key);
		insertfls(t, fl.dot.first, key);
		f := fl.dot.first + len key;
		samtk->setdot(fl, f, f);
		if (key == "\n") {
			if (f >= fl.scope.last) {
				(n, p) := sctrevcnt(t.sects, f-1, 2*fl.lines/3);
				if (n < 0) {
					outTsll(Torigin, t.tag, f-1, 2*fl.lines/3);
					setlock();
				} else {
					scrollto(fl, p);
				}
			}
			if (t == ctxt.cmd && fl.dot.last == t.nrunes) {
				outcmd();
				setlock();
			}
			cleanout();
		}
	}
	return;
}

cut(t: ref Text, fl: ref Flayer)
{
	if (fl.typepoint >= 0) panic("cut: typepoint");
	outTsll(Tcut, fl.tag, fl.dot.first, fl.dot.last);
	t.nrunes -= fl.dot.last - fl.dot.first;
	t.sects = sctdelete(t.sects, fl.dot.first, fl.dot.last - fl.dot.first);
	deletefls(t, fl.dot.first, fl.dot.last - fl.dot.first);
}

paste(t: ref Text, fl: ref Flayer)
{
	if (fl.typepoint >= 0) panic("paste: typepoint");
	if (snarflen == 0) return;
	if (fl.dot.first < fl.dot.last) cut(t, fl);
	outTsl(Tpaste, fl.tag, fl.dot.first);
}

snarf(nil: ref Text, fl: ref Flayer)
{
	if (fl.typepoint >= 0) panic("snarf: typepoint");
	if (fl.dot.first == fl.dot.last) return;
	snarflen = fl.dot.last - fl.dot.first;
	outTsll(Tsnarf, fl.tag, fl.dot.first, fl.dot.last);
}

look(nil: ref Text, fl: ref Flayer)
{
	if (fl.typepoint >= 0) panic("look: typepoint");
	outTsll(Tlook, fl.tag, fl.dot.first, fl.dot.last);
	setlock();
}

send(nil: ref Text, fl: ref Flayer)
{
	if (fl.typepoint >= 0) panic("send: typepoint");
	outcmd();
	outTsll(Tsend, fl.tag, fl.dot.first, fl.dot.last);
	setlock();
}

search(nil: ref Text, fl: ref Flayer)
{
	if (fl.typepoint >= 0) panic("search: typepoint");
	outcmd();
	outT0(Tsearch);
	setlock();
}

zerox(t: ref Text)
{
	fl := samtk->newflayer(t.tag, ctxt.cmd == t);
	t.flayers = fl :: t.flayers;
	m := whichmenu(t.tag);
	samtk->settitle(t, ctxt.menus[m].name);
	samtk->newcur(t, fl);
	scrollto(fl, 0);
}

sctget(scts: list of ref Section, p1, p2: int): string
{
	while (scts != nil) {
		sct := hd scts; scts = tl scts;
		ln := len sct.text;
		if (p1 < sct.nrunes) {
			if (ln < sct.nrunes && p2 > ln) {
				sctdump(scts, "panic");
				panic("sctget - asking for a hole");
			}
			if (p2 > sct.nrunes) {
				s := sct.text[p1:];
				return s + sctget(scts, 0, p2 - ln);
			}
			return sct.text[p1:p2];
		}
		p1 -= sct.nrunes;
		p2 -= sct.nrunes;
	}
	return "";
}

sctgetlines(scts: list of ref Section, p, n: int): (int, string)
{
	s := "";
	while (scts != nil) {
		sct := hd scts; scts = tl scts;
		ln := len sct.text;
		if (p < sct.nrunes) {
			if (p > ln) return (n, s);
			if (p > 0) b := p; else b = 0;
			for (i := b; i < ln && n > 0;   ) {
				if (sct.text[i++] == '\n') n--;
			}
			if ( i > b)
				s = s + sct.text[b:i];
			if (n == 0 || ln < sct.nrunes) return (n, s);
		}
		p -= sct.nrunes;
	}
	return (n, s);
}

sctput(scts: list of ref Section, pos: int, s: string): list of ref Section
{
	# There should be a hole to receive text
	if (scts == nil  && s != "") panic("sctput: scts is nil\n");
	sct := hd scts;
	l := len sct.text;
	if (sct.nrunes <= pos) {
		return sct :: sctput(tl scts, pos-sct.nrunes, s);
	}
	if (pos < l) {
		sctdump(scts, "panic");
		panic("sctput: overwriting");
	}
	if (pos == l) {
		if (sct.nrunes < l + len s) {
			sct.text += s[:sct.nrunes-l];
			return sct :: sctput(tl scts, 0, s[sct.nrunes-l:]);
		} 
		sct.text += s;	
		return sct :: tl scts;
	}
	nrunes := sct.nrunes;
	sct.nrunes = pos;
	if (nrunes < pos + len s)
		return	sct ::
			ref Section(nrunes-pos, s[:nrunes-pos]) ::
			sctput(tl scts, 0, s[nrunes-pos:]);
	return sct :: ref Section(nrunes-pos, s) :: tl scts;
}

sctmakeroom(scts: list of ref Section, pos: int, l: int): list of ref Section
{
	if (scts == nil) {
		if (pos) panic("sctmakeroom: beyond end of sections");
		return ref Section(l, nil) :: nil;
	}
	sct := hd scts;
	if (sct.nrunes < pos)
		return sct :: sctmakeroom(tl scts, pos-sct.nrunes, l);
	if (len sct.text <= pos) {
		# just add to the hole at end of section
		sct.nrunes += l;
		return sct :: tl scts;
	}
	if (pos == 0) {
		# text is non-nil!
		bsct := ref Section(l, nil);
		return bsct :: scts;
	}
	bsct := ref Section(pos + l, sct.text[0:pos]);
	esct := ref Section(sct.nrunes-pos, sct.text[pos:]);
	return bsct :: esct :: tl scts;
}

sctdelete(scts: list of ref Section, start, nbytes: int): list of ref Section
{
	if (nbytes == 0) return scts;
	if (scts == nil) panic("sctdelete: at eof");
	sct := hd scts;
	scts = tl scts;
	nrunes := sct.nrunes;
	if (start + nbytes < len sct.text) {
		sct.text = sct.text[0:start] + sct.text[start+nbytes:];
		sct.nrunes -= nbytes;
		return sct :: scts;
	}
	if (start < nrunes) {
		if (start > 0) {
			if (start < len sct.text)
				sct.text = sct.text[0:start];
			if (start + nbytes <= nrunes) {
				sct.nrunes -= nbytes;
				return sct :: scts;
			}
			sct.nrunes = start;
			return sct :: sctdelete(scts, 0, nbytes-nrunes+start);
		}
		if (nbytes < nrunes) {
			sct.text = "";
			sct.nrunes -= nbytes;
			return sct :: scts;
		}
		return sctdelete(scts, 0, nbytes - nrunes);
	}
	return sct :: sctdelete(scts, start - nrunes, nbytes);
}

grow(t: ref Text, at, l: int)
{
#	sctdump(t.sects, "grow, before");
	t.sects = sctmakeroom(t.sects, at, l);
	t.nrunes += l;
#	sctdump(t.sects, "grow, after");
	for (fls := t.flayers; fls != nil; fls = tl fls) {
		fl := hd fls;
		if (at < fl.scope.first) fl.scope.first += l;
		if (at < fl.scope.last) fl.scope.last += l;
	}
}

findhole(t: ref Text): (int, int)
{
	for (fls := t.flayers; fls != nil; fls = tl fls) {
		(h, l) := scthole(t, (hd fls).scope.first);
		if (l > 0) return (h, l);
	}
	return (0, 0);
}

sctdump(scts: list of ref Section, s: string)
{
	fprint(ctxt.logfd, "Sctdump: %s\n", s);
	p := 0;
	while (scts != nil) {
		sct := hd scts; scts = tl scts;
		fprint(ctxt.logfd, "\tsct@%4d len=%4d len txt=%4d: %s\n",
			p, sct.nrunes, len sct.text, contract(sct.text));
		p += sct.nrunes;
	}
	fprint(ctxt.logfd, "\tend@%4d\n", p);
}
