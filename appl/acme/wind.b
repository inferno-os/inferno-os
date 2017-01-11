implement Windowm;

include "common.m";

sys : Sys;
utils : Utils;
drawm : Draw;
graph : Graph;
gui : Gui;
dat : Dat;
bufferm : Bufferm;
textm : Textm;
filem : Filem;
look : Look;
scrl : Scroll;
acme : Acme;

sprint : import sys;
FALSE, TRUE, XXX, Astring : import Dat;
Reffont, reffont, Lock, Ref, button, modbutton : import dat;
Point, Rect, Image : import drawm;
min, max, error, warning, stralloc, strfree : import utils;
font, draw : import graph;
black, white, mainwin : import gui;
Buffer : import bufferm;
Body, Text, Tag : import textm;
File : import filem;
Xfid : import Xfidm;
scrdraw : import scrl;
tagcols, textcols : import acme;
BORD : import Framem;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	dat = mods.dat;
	utils = mods.utils;
	drawm = mods.draw;
	graph = mods.graph;
	gui = mods.gui;
	textm = mods.textm;
	filem = mods.filem;
	bufferm = mods.bufferm;
	look = mods.look;
	scrl = mods.scroll;
	acme = mods.acme;
}

winid : int;
nullwin : Window;

Window.init(w : self ref Window, clone : ref Window, r : Rect)
{
	r1, br : Rect;
	f : ref File;
	rf : ref Reffont;
	rp : ref Astring;
	nc : int;
	dummy : ref File = nil;

	c := w.col;
	*w = nullwin;
	w.col = c;
	w.nopen = array[Dat->QMAX] of byte;
	for (i := 0; i < Dat->QMAX; i++)
		w.nopen[i] = byte 0;
	w.qlock = Lock.init();
	w.ctllock = Lock.init();
	w.refx = Ref.init();
	w.tag = textm->newtext();
	w.tag.w = w;
	w.body = textm->newtext();
	w.body.w = w;
	w.id = ++winid;
	w.refx.inc();
	w.ctlfid = ~0;
	w.utflastqid = -1;
	r1 = r;
	r1.max.y = r1.min.y + font.height;
	reffont.r.inc();
	f = dummy.addtext(w.tag);
	w.tag.init(f, r1, reffont, tagcols);
	w.tag.what = Tag;
	# tag is a copy of the contents, not a tracked image 
	if(clone != nil){
		w.tag.delete(0, w.tag.file.buf.nc, TRUE);
		nc = clone.tag.file.buf.nc;
		rp = utils->stralloc(nc);
		clone.tag.file.buf.read(0, rp, 0, nc);
		w.tag.insert(0, rp.s, nc, TRUE, 0);
		utils->strfree(rp);
		rp = nil;
		w.tag.file.reset();
		w.tag.setselect(nc, nc);
	}
	r1 = r;
	r1.min.y += font.height + 1;
	if(r1.max.y < r1.min.y)
		r1.max.y = r1.min.y;
	f = nil;
	if(clone != nil){
		f = clone.body.file;
		w.body.org = clone.body.org;
		w.isscratch = clone.isscratch;
		rf = Reffont.get(FALSE, FALSE, FALSE, clone.body.reffont.f.name);
	}else
		rf = Reffont.get(FALSE, FALSE, FALSE, nil);
	f = f.addtext(w.body);
	w.body.what = Body;
	w.body.init(f, r1, rf, textcols);
	r1.min.y -= 1;
	r1.max.y = r1.min.y+1;
	draw(mainwin, r1, tagcols[BORD], nil, (0, 0));
	scrdraw(w.body);
	w.r = r;
	w.r.max.y = w.body.frame.r.max.y;
	br.min = w.tag.scrollr.min;
	br.max.x = br.min.x + button.r.dx();
	br.max.y = br.min.y + button.r.dy();
	draw(mainwin, br, button, nil, button.r.min);
	w.filemenu = TRUE;
	w.maxlines = w.body.frame.maxlines;
	if(clone != nil){
		w.dirty = clone.dirty;
		w.body.setselect(clone.body.q0, clone.body.q1);
		w.settag();
	}
}

Window.reshape(w : self ref Window, r : Rect, safe : int) : int
{
	r1, br : Rect;
	y : int;
	b : ref Image;

	r1 = r;
	r1.max.y = r1.min.y + font.height;
	y = r1.max.y;
	if(!safe || !w.tag.frame.r.eq(r1)){
		y = w.tag.reshape(r1);
		b = button;
		if(w.body.file.mod && !w.isdir && !w.isscratch)
			b = modbutton;
		br.min = w.tag.scrollr.min;
		br.max.x = br.min.x + b.r.dx();
		br.max.y = br.min.y + b.r.dy();
		draw(mainwin, br, b, nil, b.r.min);
	}
	if(!safe || !w.body.frame.r.eq(r1)){
		if(y+1+font.height > r.max.y){		# no body 
			r1.min.y = y;
			r1.max.y = y;
			w.body.reshape(r1);
			w.r = r;
			w.r.max.y = y;
			return y;
		}
		r1 = r;
		r1.min.y = y;
		r1.max.y = y + 1;
		draw(mainwin, r1, tagcols[BORD], nil, (0, 0));
		r1.min.y = y + 1;
		r1.max.y = r.max.y;
		y = w.body.reshape(r1);
		w.r = r;
		w.r.max.y = y;
		scrdraw(w.body);
	}
	w.maxlines = min(w.body.frame.nlines, max(w.maxlines, w.body.frame.maxlines));
	return w.r.max.y;
}

Window.lock1(w : self ref Window, owner : int)
{
	w.refx.inc();
	w.qlock.lock();
	w.owner = owner;
}

Window.lock(w : self ref Window, owner : int)
{
	i : int;
	f : ref File;

	f = w.body.file;
	for(i=0; i<f.ntext; i++)
		f.text[i].w.lock1(owner);
}

Window.unlock(w : self ref Window)
{
	f := w.body.file;
	#
	# subtle: loop runs backwards to avoid tripping over
	# winclose indirectly editing f.text and freeing f
	# on the last iteration of the loop
	#
	for(i:=f.ntext-1; i>=0; i--){
		w = f.text[i].w;
		w.owner = 0;
		w.qlock.unlock();
		w.close();
	}
}

Window.mousebut(w : self ref Window)
{
	graph->cursorset(w.tag.scrollr.min.add(w.tag.scrollr.max).div(2));
}

Window.dirfree(w : self ref Window)
{
	i : int;
	dl : ref Dat->Dirlist;

	if(w.isdir){
		for(i=0; i<w.ndl; i++){
			dl = w.dlp[i];
			dl.r = nil;
			dl = nil;
		}
	}
	w.dlp = nil;
	w.ndl = 0;
}

Window.close(w : self ref Window)
{
	i : int;

	if(w.refx.dec() == 0){
		w.dirfree();
		w.tag.close();
		w.body.close();
		if(dat->activewin == w)
			dat->activewin = nil;
		for(i=0; i<w.nincl; i++)
			w.incl[i] = nil;
		w.incl = nil;
		w.events = nil;
		w = nil;
	}
}

Window.delete(w : self ref Window)
{
	x : ref Xfid;

	x = w.eventx;
	if(x != nil){
		w.nevents = 0;
		w.events = nil;
		w.eventx = nil;
		x.c <-= Xfidm->Xnil;
	}
}

Window.undo(w : self ref Window, isundo : int)
{
	body : ref Text;
	i : int;
	f : ref File;
	v : ref Window;

	if(w==nil)
		return;
	w.utflastqid = -1;
	body = w.body;
	(body.q0, body.q1) = body.file.undo(isundo, body.q0, body.q1);
	body.show(body.q0, body.q1, TRUE);
	f = body.file;
	for(i=0; i<f.ntext; i++){
		v = f.text[i].w;
		v.dirty = (f.seq != v.putseq);
		if(v != w){
			v.body.q0 = v.body.frame.p0+v.body.org;
			v.body.q1 = v.body.frame.p1+v.body.org;
		}
	}
	w.settag();
}

Window.setname(w : self ref Window, name : string, n : int)
{
	t : ref Text;
	v : ref Window;
	i : int;

	t = w.body;
	if(t.file.name == name)
		return;
	w.isscratch = FALSE;
	if(n>=6 && name[n-6:n] == "/guide")
		w.isscratch = TRUE;
	else if(n>=7 && name[n-7:n] == "+Errors")
		w.isscratch = TRUE;
	t.file.setname(name, n);
	for(i=0; i<t.file.ntext; i++){
		v = t.file.text[i].w;
		v.settag();
		v.isscratch = w.isscratch;
	}
}

Window.typex(w : self ref Window, t : ref Text, r : int)
{
	i : int;

	t.typex(r, w.echomode);
	if(t.what == Body)
		for(i=0; i<t.file.ntext; i++)
			scrdraw(t.file.text[i]);
	w.settag();
}

Window.cleartag(w : self ref Window)
{
	i, n : int;
	r : ref Astring;

	# w must be committed 
	n = w.tag.file.buf.nc;
	r = utils->stralloc(n);
	w.tag.file.buf.read(0, r, 0, n);
	for(i=0; i<n; i++)
		if(r.s[i]==' ' || r.s[i]=='\t')
			break;
	for(; i<n; i++)
		if(r.s[i] == '|')
			break;
	if(i == n)
		return;
	i++;
	w.tag.delete(i, n, TRUE);
	utils->strfree(r);
	r = nil;
	w.tag.file.mod = FALSE;
	if(w.tag.q0 > i)
		w.tag.q0 = i;
	if(w.tag.q1 > i)
		w.tag.q1 = i;
	w.tag.setselect(w.tag.q0, w.tag.q1);
}

Window.settag(w : self ref Window)
{
	i : int;
	f : ref File;

	f = w.body.file;
	for(i=0; i<f.ntext; i++){
		v := f.text[i].w;
		if(v.col.safe || v.body.frame.maxlines>0)
			v.settag1();
	}
}

Window.settag1(w : self ref Window)
{
	ii, j, k, n, bar, dirty : int;
	old : ref Astring;
	new : string;
	r : int;
	b : ref Image;
	q0, q1 : int;
	br : Rect;

	if(w.tag.ncache!=0 || w.tag.file.mod)
		w.commit(w.tag);	# check file name; also can now modify tag
	old = utils->stralloc(w.tag.file.buf.nc);
	w.tag.file.buf.read(0, old, 0, w.tag.file.buf.nc);
	for(ii=0; ii<w.tag.file.buf.nc; ii++)
		if(old.s[ii]==' ' || old.s[ii]=='\t')
			break;
	if(old.s[0:ii] != w.body.file.name){
		w.tag.delete(0, ii, TRUE);
		w.tag.insert(0, w.body.file.name, len w.body.file.name, TRUE, 0);
		strfree(old);
		old = nil;
		old = utils->stralloc(w.tag.file.buf.nc);
		w.tag.file.buf.read(0, old, 0, w.tag.file.buf.nc);
	}
	new = w.body.file.name + " Del Snarf";
	if(w.filemenu){
		if(w.body.file.delta.nc>0 || w.body.ncache)
			new += " Undo";
		if(w.body.file.epsilon.nc > 0)
			new += " Redo";
		dirty = w.body.file.name != nil && (w.body.ncache || w.body.file.seq!=w.putseq);
		if(!w.isdir && dirty)
			new += " Put";
	}
	if(w.isdir)
		new += " Get";
	l := len w.body.file.name;
	if(l >= 2 && w.body.file.name[l-2: ] == ".b")
		new += " Limbo";
	new += " |";
	r = utils->strchr(old.s, '|');
	if(r >= 0)
		k = r+1;
	else{
		k = w.tag.file.buf.nc;
		if(w.body.file.seq == 0)
			new += " Look ";
	}
	if(new != old.s[0:k]){
		n = k;
		if(n > len new)
			n = len new;
		for(j=0; j<n; j++)
			if(old.s[j] != new[j])
				break;
		q0 = w.tag.q0;
		q1 = w.tag.q1;
		w.tag.delete(j, k, TRUE);
		w.tag.insert(j, new[j:], len new - j, TRUE, 0);
		# try to preserve user selection 
		r = utils->strchr(old.s, '|');
		if(r >= 0){
			bar = r;
			if(q0 > bar){
				bar = utils->strchr(new, '|')-bar;
				w.tag.q0 = q0+bar;
				w.tag.q1 = q1+bar;
			}
		}
	}
	strfree(old);
	old = nil;
	new = nil;
	w.tag.file.mod = FALSE;
	n = w.tag.file.buf.nc+w.tag.ncache;
	if(w.tag.q0 > n)
		w.tag.q0 = n;
	if(w.tag.q1 > n)
		w.tag.q1 = n;
	w.tag.setselect(w.tag.q0, w.tag.q1);
	b = button;
	if(!w.isdir && !w.isscratch && (w.body.file.mod || w.body.ncache))
		b = modbutton;
	br.min = w.tag.scrollr.min;
	br.max.x = br.min.x + b.r.dx();
	br.max.y = br.min.y + b.r.dy();
	draw(mainwin, br, b, nil, b.r.min);
}

Window.commit(w : self ref Window, t : ref Text)
{
	r : ref Astring;
	i : int;
	f : ref File;

	t.commit(TRUE);
	f = t.file;
	if(f.ntext > 1)
		for(i=0; i<f.ntext; i++)
			f.text[i].commit(FALSE);	# no-op for t 
	if(t.what == Body)
		return;
	r = utils->stralloc(w.tag.file.buf.nc);
	w.tag.file.buf.read(0, r, 0, w.tag.file.buf.nc);
	for(i=0; i<w.tag.file.buf.nc; i++)
		if(r.s[i]==' ' || r.s[i]=='\t')
			break;
	if(r.s[0:i] != w.body.file.name){
		dat->seq++;
		w.body.file.mark();
		w.body.file.mod = TRUE;
		w.dirty = TRUE;
		w.setname(r.s, i);
		w.settag();
	}
	utils->strfree(r);
	r = nil;
}

Window.addincl(w : self ref Window, r : string, n : int)
{
	{
		(ok, d) := sys->stat(r);
		if(ok < 0){
			if(r[0] == '/')
				raise "e";
			(r, n) = look->dirname(w.body, r, n);
			(ok, d) = sys->stat(r);
			if(ok < 0)
				raise "e";
		}
		if((d.mode&Sys->DMDIR) == 0){
			warning(nil, sprint("%s: not a directory\n", r));
			r = nil;
			return;
		}
		w.nincl++;
		owi := w.incl;
		w.incl = array[w.nincl] of string;
		w.incl[1:] = owi[0:w.nincl-1];
		owi = nil;
		w.incl[0] = r;
		r = nil;
	}
	exception{
		* =>
			warning(nil, sprint("%s: %r\n", r));
			r = nil;
	}
}

Window.clean(w : self ref Window, conservative : int, exiting : int) : int	# as it stands, conservative is always TRUE 
{
	if(w.isscratch || w.isdir)	# don't whine if it's a guide file, error window, etc. 
		return TRUE;
	if((!conservative||exiting) && w.nopen[Dat->QWevent]>byte 0)
		return TRUE;
	if(w.dirty){
		if(w.body.file.name != nil)
			warning(nil, sprint("%s modified\n", w.body.file.name));
		else{
			if(w.body.file.buf.nc < 100)	# don't whine if it's too small 
				return TRUE;
			warning(nil, "unnamed file modified\n");
		}
		w.dirty = FALSE;
		return FALSE;
	}
	return TRUE;
}

Window.ctlprint(w : self ref Window, fonts : int) : string
{
	s := sprint("%11d %11d %11d %11d %11d ", w.id, w.tag.file.buf.nc,
			w.body.file.buf.nc, w.isdir, w.dirty);
	if(fonts)
		return sprint("%s%11d %q %11d ", s, w.body.frame.r.dx(),
			w.body.reffont.f.name, w.body.frame.maxtab);
	return s;
}

Window.event(w : self ref Window, fmt : string)
{
	n : int;
	x : ref Xfid;

	if(w.nopen[Dat->QWevent] == byte 0)
		return;
	if(w.owner == 0)
		error("no window owner");
	n = len fmt;
	w.events[len w.events] = w.owner;
	w.events += fmt;
	w.nevents += n+1;
	x = w.eventx;
	if(x != nil){
		w.eventx = nil;
		x.c <-= Xfidm->Xnil;
	}
}
