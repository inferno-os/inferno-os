implement Textm;

include "common.m";
include "keyboard.m";

sys : Sys;
utils : Utils;
framem : Framem;
drawm : Draw;
acme : Acme;
graph : Graph;
gui : Gui;
dat : Dat;
scrl : Scroll;
bufferm : Bufferm;
filem : Filem;
columnm : Columnm;
windowm : Windowm;
exec : Exec;

Dir, sprint : import sys;
frgetmouse : import acme;
min, warning, error, stralloc, strfree, isalnum : import utils;
Frame, frinsert, frdelete, frptofchar, frcharofpt, frselect, frdrawsel, frdrawsel0, frtick : import framem;
BUFSIZE, Astring, SZINT, TRUE, FALSE, XXX, Reffont, Dirlist,Scrollwid, Scrollgap, seq, mouse : import dat;
EM_NORMAL, EM_RAW, EM_MASK : import dat;
ALPHA_LATIN, ALPHA_GREEK, ALPHA_CYRILLIC: import Dat;
BACK, TEXT, HIGH, HTEXT : import Framem;
Flushon, Flushoff : import Draw;
Point, Display, Rect, Image : import drawm;
charwidth, bflush, draw : import graph;
black, white, mainwin, display : import gui;
Buffer : import bufferm;
File : import filem;
Column : import columnm;
Window : import windowm;
scrdraw : import scrl;

cvlist: adt {
	ld: int;
	nm: string;
	si: string;
	so: string;
};

#	"@@",  "'EKSTYZekstyz   ",	"ьЕКСТЫЗекстызъЁё",

latintab := array[] of {
	cvlist(
		ALPHA_LATIN,
		"latin",
		nil,
		nil
	),
	cvlist(
		ALPHA_GREEK,
		"greek",
		"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz",
		"ΑΒΞΔΕΦΓΘΙΪΚΛΜΝΟΠΨΡΣΤΥΫΩΧΗΖαβξδεφγθιϊκλμνοπψρστυϋωχηζ"
	),
	cvlist(
		ALPHA_CYRILLIC,
		"cyrillic",
		"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz",
		"АБЧДЭФГШИЙХЛМНОПЕРЩЦУВЮХЯЖабчдэфгшийхлмноперщцувюхяж"
	),
	cvlist(-1, nil, nil, nil)
};

alphabet := ALPHA_LATIN;	# per window perhaps

setalphabet(s: string)
{
	for(a := 0; latintab[a].ld != -1; a++){
		k := latintab[a].ld;
		for(i := 0; latintab[i].ld != -1; i++){
			if(s == transs(latintab[i].nm, k)){
				alphabet = latintab[i].ld;
				return;
			}
		}
	}
}

transc(c: int, k: int): int
{
	for(i := 0; latintab[i].ld != -1; i++){
		if(k == latintab[i].ld){
			si := latintab[i].si;
			so := latintab[i].so;
			ln := len si;
			for(j := 0; j < ln; j++)
				if(c == si[j])
					return so[j];
		}
	}
	return c;
}

transs(s: string, k: int): string
{
	ln := len s;
	for(i := 0; i < ln; i++)
		s[i] = transc(s[i], k);
	return s;
}

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	framem = mods.framem;
	dat = mods.dat;
	utils = mods.utils;
	drawm = mods.draw;
	acme = mods.acme;
	graph = mods.graph;
	gui = mods.gui;
	scrl = mods.scroll;
	bufferm = mods.bufferm;
	filem = mods.filem;
	columnm = mods.columnm;
	windowm = mods.windowm;
	exec = mods.exec;
}

TABDIR : con 3;	# width of tabs in directory windows

# remove eventually
KF : con 16rF000;
Kup : con KF | 16r0E;
Kleft : con KF | 16r11;
Kright : con KF | 16r12;
Kend : con KF | 16r18;
Kdown : con 16r80;


nulltext : Text;

newtext() : ref Text
{
	t := ref nulltext;
	t.frame = framem->newframe();
	return t;
}

Text.init(t : self ref Text, f : ref File, r : Rect, rf : ref Dat->Reffont, cols : array of ref Image)
{
	t.file = f;
	t.all = r;
	t.scrollr = r;
	t.scrollr.max.x = r.min.x+Scrollwid;
	t.lastsr = dat->nullrect;
	r.min.x += Scrollwid+Scrollgap;
	t.eq0 = ~0;
	t.ncache = 0;
	t.reffont = rf;
	t.tabstop = dat->maxtab;
	for(i:=0; i<Framem->NCOL; i++)
		t.frame.cols[i] = cols[i];
	t.redraw(r, rf.f, mainwin, -1);
}

Text.redraw(t : self ref Text, r : Rect, f : ref Draw->Font, b : ref Image, odx : int)
{
	framem->frinit(t.frame, r, f, b, t.frame.cols);
	rr := t.frame.r;
	rr.min.x -= Scrollwid;	# back fill to scroll bar
	draw(t.frame.b, rr, t.frame.cols[Framem->BACK], nil, (0, 0));
	# use no wider than 3-space tabs in a directory
	maxt := dat->maxtab;
	if(t.what == Body){
		if(t.w != nil && t.w.isdir)
			maxt = min(TABDIR, dat->maxtab);
		else
			maxt = t.tabstop;
	}
	t.frame.maxtab = maxt*charwidth(f, '0');
	# c = '0';
	# if(t.what==Body && t.w!=nil && t.w.isdir)
	#	c = ' ';
	# t.frame.maxtab = Dat->Maxtab*charwidth(f, c);
	if(t.what==Body && t.w.isdir && odx!=t.all.dx()){
		if(t.frame.maxlines > 0){
			t.reset();
			t.columnate(t.w.dlp,  t.w.ndl);
			t.show(0, 0, TRUE);
		}
	}else{
		t.fill();
		t.setselect(t.q0, t.q1);
	}
}

Text.reshape(t : self ref Text, r : Rect) : int
{
	odx : int;

	if(r.dy() > 0)
		r.max.y -= r.dy()%t.frame.font.height;
	else
		r.max.y = r.min.y;
	odx = t.all.dx();
	t.all = r;
	t.scrollr = r;
	t.scrollr.max.x = r.min.x+Scrollwid;
	t.lastsr = dat->nullrect;
	r.min.x += Scrollwid+Scrollgap;
	framem->frclear(t.frame, 0);
	# t.redraw(r, t.frame.font, t.frame.b, odx);
	t.redraw(r, t.frame.font, mainwin, odx);
	return r.max.y;
}

Text.close(t : self ref Text)
{
	t.cache = nil;
	framem->frclear(t.frame, 1);
	t.file.deltext(t);
	t.file = nil;
	t.reffont.close();
	if(dat->argtext == t)
		dat->argtext = nil;
	if(dat->typetext == t)
		dat->typetext = nil;
	if(dat->seltext == t)
		dat->seltext = nil;
	if(dat->mousetext == t)
		dat->mousetext = nil;
	if(dat->barttext == t)
		dat->barttext = nil;
}

dircmp(da : ref Dirlist, db : ref Dirlist) : int
{
	if (da.r < db.r)
		return -1;
	if (da.r > db.r)
		return 1;
	return 0;
}

qsort(a : array of ref Dirlist, n : int)
{
	i, j : int;
	t : ref Dirlist;

	while(n > 1) {
		i = n>>1;
		t = a[0]; a[0] = a[i]; a[i] = t;
		i = 0;
		j = n;
		for(;;) {
			do
				i++;
			while(i < n && dircmp(a[i], a[0]) < 0);
			do
				j--;
			while(j > 0 && dircmp(a[j], a[0]) > 0);
			if(j < i)
				break;
			t = a[i]; a[i] = a[j]; a[j] = t;
		}
		t = a[0]; a[0] = a[j]; a[j] = t;
		n = n-j-1;
		if(j >= n) {
			qsort(a, j);
			a = a[j+1:];
		} else {
			qsort(a[j+1:], n);
			n = j;
		}
	}
}

Text.columnate(t : self ref Text, dlp : array of ref Dirlist, ndl : int)
{
	i, j, w, colw, mint, maxt, ncol, nrow : int;
	dl : ref Dirlist;
	q1 : int;

	if(t.file.ntext > 1)
		return;
	mint = charwidth(t.frame.font, '0');
	# go for narrower tabs if set more than 3 wide
	t.frame.maxtab = min(dat->maxtab, TABDIR)*mint;
	maxt = t.frame.maxtab;
	colw = 0;
	for(i=0; i<ndl; i++){
		dl = dlp[i];
		w = dl.wid;
		if(maxt-w%maxt < mint)
			w += mint;
		if(w % maxt)
			w += maxt-(w%maxt);
		if(w > colw)
			colw = w;
	}
	if(colw == 0)
		ncol = 1;
	else
		ncol = utils->max(1, t.frame.r.dx()/colw);
	nrow = (ndl+ncol-1)/ncol;

	q1 = 0;
	for(i=0; i<nrow; i++){
		for(j=i; j<ndl; j+=nrow){
			dl = dlp[j];
			t.file.insert(q1, dl.r, len dl.r);
			q1 += len dl.r;
			if(j+nrow >= ndl)
				break;
			w = dl.wid;
			if(maxt-w%maxt < mint){
				t.file.insert(q1, "\t", 1);
				q1++;
				w += mint;
			}
			do{
				t.file.insert(q1, "\t", 1);
				q1++;
				w += maxt-(w%maxt);
			}while(w < colw);
		}
		t.file.insert(q1, "\n", 1);
		q1++;
	}
}

Text.loadx(t : self ref Text, q0 : int, file : string, setqid : int) : int
{
	rp : ref Astring;
	dl : ref Dirlist;
	dlp : array of ref Dirlist;
	i, n, ndl : int;
	fd : ref Sys->FD;
	q, q1 : int;
	d : Dir;
	u : ref Text;
	ok : int;

	if(t.ncache!=0 || t.file.buf.nc || t.w==nil || t!=t.w.body || (t.w.isdir && t.file.name==nil))
		error("text.load");

	{
		fd = sys->open(file, Sys->OREAD);
		if(fd == nil){
			warning(nil, sprint("can't open %s: %r\n", file));
			raise "e";
		}
		(ok, d) = sys->fstat(fd);
		if(ok){
			warning(nil, sprint("can't fstat %s: %r\n", file));
			raise "e";
		}
		if(d.qid.qtype & Sys->QTDIR){
			# this is checked in get() but it's possible the file changed underfoot 
			if(t.file.ntext > 1){
				warning(nil, sprint("%s is a directory; can't read with multiple windows on it\n", file));
				raise "e";
			}
			t.w.isdir = TRUE;
			t.w.filemenu = FALSE;
			if(t.file.name[len t.file.name-1] != '/')
				t.w.setname(t.file.name + "/", len t.file.name+1);
			dlp = nil;
			ndl = 0;
			for(;;){
				(nd, dbuf) := sys->dirread(fd);
				if(nd <= 0)
					break;
				for(i=0; i<nd; i++){
					dl = ref Dirlist;
					dl.r = dbuf[i].name;
					if(dbuf[i].mode & Sys->DMDIR)
						dl.r = dl.r + "/";
					dl.wid = graph->strwidth(t.frame.font, dl.r);
					ndl++;
					odlp := dlp;
					dlp = array[ndl] of ref Dirlist;
					dlp[0:] = odlp[0:ndl-1];
					odlp = nil;
					dlp[ndl-1] = dl;
				}
			}
			qsort(dlp, ndl);
			t.w.dlp = dlp;
			t.w.ndl = ndl;
			t.columnate(dlp, ndl);
			q1 = t.file.buf.nc;
		}else{
			tmp : int;
	
			t.w.isdir = FALSE;
			t.w.filemenu = TRUE;
			tmp = t.file.loadx(q0, fd);
			q1 = q0 + tmp;
		}
		fd = nil;
		if(setqid){
			t.file.dev = d.dev;
			t.file.mtime = d.mtime;
			t.file.qidpath = d.qid.path;
		}
		rp = stralloc(BUFSIZE);
		for(q=q0; q<q1; q+=n){
			n = q1-q;
			if(n > Dat->BUFSIZE)
				n = Dat->BUFSIZE;
			t.file.buf.read(q, rp, 0, n);
			if(q < t.org)
				t.org += n;
			else if(q <= t.org+t.frame.nchars)
				frinsert(t.frame, rp.s, n, q-t.org);
			if(t.frame.lastlinefull)
				break;
		}
		strfree(rp);
		rp = nil;
		for(i=0; i<t.file.ntext; i++){
			u = t.file.text[i];
			if(u != t){
				if(u.org > u.file.buf.nc)	# will be 0 because of reset(), but safety first 
					u.org = 0;
				u.reshape(u.all);
				u.backnl(u.org, 0);	# go to beginning of line 
			}
			u.setselect(q0, q0);
		}
		return q1-q0;
	}
	exception{
		* =>
			fd = nil;
			return 0;
	}
	return 0;
}

Text.bsinsert(t : self ref Text, q0 : int, r : string, n : int, tofile : int) : (int, int)
{
	tp : ref Astring;
	bp, up : int;
	i, initial : int;

	{
		if(t.what == Tag)	# can't happen but safety first: mustn't backspace over file name 
			raise "e";
		bp = 0;
		for(i=0; i<n; i++)
			if(r[bp++] == '\b'){
				--bp;
				initial = 0;
				tp = utils->stralloc(n);
				for (k := 0; k < i; k++)
					tp.s[k] = r[k];
				up = i;
				for(; i<n; i++){
					tp.s[up] = r[bp++];
					if(tp.s[up] == '\b')
						if(up == 0)
							initial++;
						else
							--up;
					else
						up++;
				}
				if(initial){
					if(initial > q0)
						initial = q0;
					q0 -= initial;
					t.delete(q0, q0+initial, tofile);
				}
				n = up;
				t.insert(q0, tp.s, n, tofile, 0);
				strfree(tp);
				tp = nil;
				return (q0, n);
			}
		raise "e";
		return(0, 0);
	}
	exception{
		* =>
			t.insert(q0, r, n, tofile, 0);
			return (q0, n);
	}
	return (0, 0);
}

Text.insert(t : self ref Text, q0 : int, r : string, n : int, tofile : int, echomode : int)
{
	c, i : int;
	u : ref Text;

	if(tofile && t.ncache != 0)
		error("text.insert");
	if(n == 0)
		return;
	if(tofile){
		t.file.insert(q0, r, n);
		if(t.what == Body){
			t.w.dirty = TRUE;
			t.w.utflastqid = -1;
		}
		if(t.file.ntext > 1)
			for(i=0; i<t.file.ntext; i++){
				u = t.file.text[i];
				if(u != t){
					u.w.dirty = TRUE;	# always a body 
					u.insert(q0, r, n, FALSE, echomode);
					u.setselect(u.q0, u.q1);
					scrdraw(u);
				}
			}		
	}
	if(q0 < t.q1)
		t.q1 += n;
	if(q0 < t.q0)
		t.q0 += n;
	if(q0 < t.org)
		t.org += n;
	else if(q0 <= t.org+t.frame.nchars) {
		if (echomode == EM_MASK && len r == 1 && r[0] != '\n')
			frinsert(t.frame, "*", n, q0-t.org);
		else
			frinsert(t.frame, r, n, q0-t.org);
	}
	if(t.w != nil){
		c = 'i';
		if(t.what == Body)
			c = 'I';
		if(n <= Dat->EVENTSIZE)
			t.w.event(sprint("%c%d %d 0 %d %s\n", c, q0, q0+n, n, r[0:n]));
		else
			t.w.event(sprint("%c%d %d 0 0 \n", c, q0, q0+n));
	}
}

Text.fill(t : self ref Text)
{
	rp : ref Astring;
	i, n, m, nl : int;

	if(t.frame.lastlinefull || t.nofill)
		return;
	if(t.ncache > 0){
		if(t.w != nil)
			t.w.commit(t);
		else
			t.commit(TRUE);
	}
	rp = stralloc(BUFSIZE);
	do{
		n = t.file.buf.nc-(t.org+t.frame.nchars);
		if(n == 0)
			break;
		if(n > 2000)	# educated guess at reasonable amount 
			n = 2000;
		t.file.buf.read(t.org+t.frame.nchars, rp, 0, n);
		#
		# it's expensive to frinsert more than we need, so
		# count newlines.
		#
		 
		nl = t.frame.maxlines-t.frame.nlines;
		m = 0;
		for(i=0; i<n; ){
			if(rp.s[i++] == '\n'){
				m++;
				if(m >= nl)
					break;
			}
		}
		frinsert(t.frame, rp.s, i, t.frame.nchars);
	}while(t.frame.lastlinefull == FALSE);
	strfree(rp);
	rp = nil;
}

Text.delete(t : self ref Text, q0 : int, q1 : int, tofile : int)
{
	n, p0, p1 : int;
	i, c : int;
	u : ref Text;

	if(tofile && t.ncache != 0)
		error("text.delete");
	n = q1-q0;
	if(n == 0)
		return;
	if(tofile){
		t.file.delete(q0, q1);
		if(t.what == Body){
			t.w.dirty = TRUE;
			t.w.utflastqid = -1;
		}
		if(t.file.ntext > 1)
			for(i=0; i<t.file.ntext; i++){
				u = t.file.text[i];
				if(u != t){
					u.w.dirty = TRUE;	# always a body 
					u.delete(q0, q1, FALSE);
					u.setselect(u.q0, u.q1);
					scrdraw(u);
				}
			}
	}
	if(q0 < t.q0)
		t.q0 -= min(n, t.q0-q0);
	if(q0 < t.q1)
		t.q1 -= min(n, t.q1-q0);
	if(q1 <= t.org)
		t.org -= n;
	else if(q0 < t.org+t.frame.nchars){
		p1 = q1 - t.org;
		if(p1 > t.frame.nchars)
			p1 = t.frame.nchars;
		if(q0 < t.org){
			t.org = q0;
			p0 = 0;
		}else
			p0 = q0 - t.org;
		frdelete(t.frame, p0, p1);
		t.fill();
	}
	if(t.w != nil){
		c = 'd';
		if(t.what == Body)
			c = 'D';
		t.w.event(sprint("%c%d %d 0 0 \n", c, q0, q1));
	}
}

onechar : ref Astring;

Text.readc(t : self ref Text, q : int) : int
{
	if(t.cq0<=q && q<t.cq0+t.ncache)
		return t.cache[q-t.cq0];
	if (onechar == nil)
		onechar = stralloc(1);
	t.file.buf.read(q, onechar, 0, 1);
	return onechar.s[0];
}

Text.bswidth(t : self ref Text, c : int) : int
{
	q, eq : int;
	r : int;
	skipping : int;

	# there is known to be at least one character to erase 
	if(c == 16r08)	# ^H: erase character 
		return 1;
	q = t.q0;
	skipping = TRUE;
	while(q > 0){
		r = t.readc(q-1);
		if(r == '\n'){		# eat at most one more character 
			if(q == t.q0)	# eat the newline 
				--q;
			break; 
		}
		if(c == 16r17){
			eq = isalnum(r);
			if(eq && skipping)	# found one; stop skipping 
				skipping = FALSE;
			else if(!eq && !skipping)
				break;
		}
		--q;
	}
	return t.q0-q;
}

Text.typex(t : self ref Text, r : int, echomode : int)
{
	q0, q1 : int;
	nnb, nb, n, i : int;
	u : ref Text;

	if(alphabet != ALPHA_LATIN)
		r = transc(r, alphabet);
	if (echomode == EM_RAW && t.what == Body) {
		if (t.w != nil) {
			s := "a";
			s[0] = r;
			t.w.event(sprint("R0 0 0 1 %s\n", s));
		}
		return;
	}
	if(t.what!=Body && r=='\n')
		return;
	case r {
		Dat->Kscrolldown=>
			if(t.what == Body){
				q0 = t.org+frcharofpt(t.frame, (t.frame.r.min.x, t.frame.r.min.y+2*t.frame.font.height));
				t.setorigin(q0, FALSE);
			}
			return;
		Dat->Kscrollup=>
			if(t.what == Body){
				q0 = t.backnl(t.org, 4);
				t.setorigin(q0, FALSE);
			}
			return;		
		Kdown or Keyboard->Down =>
			n = t.frame.maxlines/3;
			q0 = t.org+frcharofpt(t.frame, (t.frame.r.min.x, t.frame.r.min.y+n*t.frame.font.height));
			t.setorigin(q0, FALSE);
			return;
		Keyboard->Pgdown =>
			n = 2*t.frame.maxlines/3;
			q0 = t.org+frcharofpt(t.frame, (t.frame.r.min.x, t.frame.r.min.y+n*t.frame.font.height));
			t.setorigin(q0, FALSE);
			return;
		Kup or Keyboard->Up =>
			n = t.frame.maxlines/3;
			q0 = t.backnl(t.org, n);
			t.setorigin(q0, FALSE);
			return;
		Keyboard->Pgup =>
			n = 2*t.frame.maxlines/3;
			q0 = t.backnl(t.org, n);
			t.setorigin(q0, FALSE);
			return;
		Keyboard->Home =>
			t.commit(TRUE);
			t.show(0, 0, FALSE);
			return;
		Kend or Keyboard->End =>
			t.commit(TRUE);
			t.show(t.file.buf.nc, t.file.buf.nc, FALSE);
			return;
		Kleft or Keyboard->Left =>
			t.commit(TRUE);
			if(t.q0 != t.q1)
				t.show(t.q0, t.q0, TRUE);
			else if(t.q0 != 0)
				t.show(t.q0-1, t.q0-1, TRUE);
			return;
		Kright or Keyboard->Right =>
			t.commit(TRUE);
			if(t.q0 != t.q1)
				t.show(t.q1, t.q1, TRUE);
			else if(t.q1 != t.file.buf.nc)
				t.show(t.q1+1, t.q1+1, TRUE);
			return;
		1 =>  	# ^A: beginning of line
			t.commit(TRUE);
			# go to where ^U would erase, if not already at BOL
			nnb = 0;
			if(t.q0>0 && t.readc(t.q0-1)!='\n')
				nnb = t.bswidth(16r15);
			t.show(t.q0-nnb, t.q0-nnb, TRUE);
			return;
		5 =>  	# ^E: end of line
			t.commit(TRUE);
			q0 = t.q0;
			while(q0<t.file.buf.nc && t.readc(q0)!='\n')
				q0++;
			t.show(q0, q0, TRUE);
			return;
	}
	if(t.what == Body){
		seq++;
		t.file.mark();
	}
	if(t.q1 > t.q0){
		if(t.ncache != 0)
			error("text.type");
		exec->cut(t, t, TRUE, TRUE);
		t.eq0 = ~0;
		if (r == 16r08 || r == 16r7f){	# erase character : odd if a char then erased
			t.show(t.q0, t.q0,TRUE);
			return;
		}
	}
	t.show(t.q0, t.q0, TRUE);
	case(r){
	16r1B =>
		if(t.eq0 != ~0)
			t.setselect(t.eq0, t.q0);
		if(t.ncache > 0){
			if(t.w != nil)
				t.w.commit(t);
			else
				t.commit(TRUE);
		}
		return;
	16r08 or 16r15 or 16r17 =>
		# ^H: erase character or ^U: erase line or ^W: erase word 
		if(t.q0 == 0)
			return;
if(0)	# DEBUGGING 
	for(i=0; i<t.file.ntext; i++){
		u = t.file.text[i];
		if(u.cq0!=t.cq0 && (u.ncache!=t.ncache || t.ncache!=0))
			error("text.type inconsistent caches");
	}
		nnb = t.bswidth(r);
		q1 = t.q0;
		q0 = q1-nnb;
		for(i=0; i<t.file.ntext; i++){
			u = t.file.text[i];
			u.nofill = TRUE;
			nb = nnb;
			n = u.ncache;
			if(n > 0){
				if(q1 != u.cq0+n)
					error("text.type backspace");
				if(n > nb)
					n = nb;
				u.ncache -= n;
				u.delete(q1-n, q1, FALSE);
				nb -= n;
			}
			if(u.eq0==q1 || u.eq0==~0)
				u.eq0 = q0;
			if(nb && u==t)
				u.delete(q0, q0+nb, TRUE);
			if(u != t)
				u.setselect(u.q0, u.q1);
			else
				t.setselect(q0, q0);
			u.nofill = FALSE;
		}
		for(i=0; i<t.file.ntext; i++)
			t.file.text[i].fill();
		return;
	16r7f or Keyboard->Del =>
		# Delete character - forward delete
		t.commit(TRUE);
		if(t.q0 >= t.file.buf.nc)
			return;
		nnb = 1;
		q0 = t.q0;
		q1 = q0+nnb;
		for(i=0; i<t.file.ntext; i++){
			u = t.file.text[i];
			if (u!=t)
				u.commit(FALSE);
			u.nofill = TRUE;
			if(u.eq0==q1 || u.eq0==~0)
				u.eq0 = q0;
			if(u==t)
				u.delete(q0, q1, TRUE);
			if(u != t)
				u.setselect(u.q0, u.q1);
			else
				t.setselect(q0, q0);
			u.nofill = FALSE;
		}
		for(i=0; i<t.file.ntext; i++)
			t.file.text[i].fill();
		return;
	}
	# otherwise ordinary character; just insert, typically in caches of all texts 
if(0)	# DEBUGGING 
	for(i=0; i<t.file.ntext; i++){
		u = t.file.text[i];
		if(u.cq0!=t.cq0 && (u.ncache!=t.ncache || t.ncache!=0))
			error("text.type inconsistent caches");
	}
	for(i=0; i<t.file.ntext; i++){
		u = t.file.text[i];
		if(u.eq0 == ~0)
			u.eq0 = t.q0;
		if(u.ncache == 0)
			u.cq0 = t.q0;
		else if(t.q0 != u.cq0+u.ncache)
			error("text.type cq1");
		str := "Z";
		str[0] = r;
		u.insert(t.q0, str, 1, FALSE, echomode);
		str = nil;
		if(u != t)
			u.setselect(u.q0, u.q1);
		if(u.ncache == u.ncachealloc){
			u.ncachealloc += 10;
			u.cache += "1234567890";
		}
		u.cache[u.ncache++] = r;
	}
	t.setselect(t.q0+1, t.q0+1);
	if(r=='\n' && t.w!=nil)
		t.w.commit(t);
}

Text.commit(t : self ref Text, tofile : int)
{
	if(t.ncache == 0)
		return;
	if(tofile)
		t.file.insert(t.cq0, t.cache, t.ncache);
	if(t.what == Body){
		t.w.dirty = TRUE;
		t.w.utflastqid = -1;
	}
	t.ncache = 0;
}

clicktext : ref Text;
clickmsec : int = 0;
selecttext : ref Text;
selectq : int = 0;

#
# called from frame library
#
 
framescroll(f : ref Frame, dl : int)
{
	if(f != selecttext.frame)
		error("frameselect not right frame");
	selecttext.framescroll(dl);
}

Text.framescroll(t : self ref Text, dl : int)
{
	q0 : int;

	if(dl == 0){
		scrl->scrsleep(100);
		return;
	}
	if(dl < 0){
		q0 = t.backnl(t.org, -dl);
		if(selectq > t.org+t.frame.p0)
			t.setselect0(t.org+t.frame.p0, selectq);
		else
			t.setselect0(selectq, t.org+t.frame.p0);
	}else{
		if(t.org+t.frame.nchars == t.file.buf.nc)
			return;
		q0 = t.org+frcharofpt(t.frame, (t.frame.r.min.x, t.frame.r.min.y+dl*t.frame.font.height));
		if(selectq > t.org+t.frame.p1)
			t.setselect0(t.org+t.frame.p1, selectq);
		else
			t.setselect0(selectq, t.org+t.frame.p1);
	}
	t.setorigin(q0, TRUE);
}


Text.select(t : self ref Text, double : int)
{
	q0, q1 : int;
	b, x, y : int;
	state : int;

	selecttext = t;
	#
	# To have double-clicking and chording, we double-click
	# immediately if it might make sense.
	#
	 
	b = mouse.buttons;
	q0 = t.q0;
	q1 = t.q1;
	selectq = t.org+frcharofpt(t.frame, mouse.xy);
	if(double || (clicktext==t && mouse.msec-clickmsec<500))
	if(q0==q1 && selectq==q0){
		(q0, q1) = t.doubleclick(q0, q1);
		t.setselect(q0, q1);
		bflush();
		x = mouse.xy.x;
		y = mouse.xy.y;
		# stay here until something interesting happens 
		do
			frgetmouse();
		while(mouse.buttons==b && utils->abs(mouse.xy.x-x)<3 && utils->abs(mouse.xy.y-y)<3);
		mouse.xy.x = x;	# in case we're calling frselect 
		mouse.xy.y = y;
		q0 = t.q0;	# may have changed 
		q1 = t.q1;
		selectq = q0;
	}
	if(mouse.buttons == b){
		t.frame.scroll = 1;
		frselect(t.frame, mouse);
		# horrible botch: while asleep, may have lost selection altogether 
		if(selectq > t.file.buf.nc)
			selectq = t.org + t.frame.p0;
		t.frame.scroll = 0;
		if(selectq < t.org)
			q0 = selectq;
		else
			q0 = t.org + t.frame.p0;
		if(selectq > t.org+t.frame.nchars)
			q1 = selectq;
		else
			q1 = t.org+t.frame.p1;
	}
	if(q0 == q1){
		if(q0==t.q0 && (double || clicktext==t && mouse.msec-clickmsec<500)){
			(q0, q1) = t.doubleclick(q0, q1);
			clicktext = nil;
		}else{
			clicktext = t;
			clickmsec = mouse.msec;
		}
	}else
		clicktext = nil;
	t.setselect(q0, q1);
	bflush();
	state = 0;	# undo when possible; +1 for cut, -1 for paste 
	while(mouse.buttons){
		mouse.msec = 0;
		b = mouse.buttons;
		if(b & 6){
			if(state==0 && t.what==Body){
				seq++;
				t.w.body.file.mark();
			}
			if(b & 2){
				if(state==-1 && t.what==Body){
					t.w.undo(TRUE);
					t.setselect(q0, t.q0);
					state = 0;
				}else if(state != 1){
					exec->cut(t, t, TRUE, TRUE);
					state = 1;
				}
			}else{
				if(state==1 && t.what==Body){
					t.w.undo(TRUE);
					t.setselect(q0, t.q1);
					state = 0;
				}else if(state != -1){
					exec->paste(t, t, TRUE, FALSE);
					state = -1;
				}
			}
			scrdraw(t);
			utils->clearmouse();
		}
		bflush();
		while(mouse.buttons == b)
			frgetmouse();
		clicktext = nil;
	}
}

Text.show(t : self ref Text, q0 : int, q1 : int, doselect : int)
{
	qe : int;
	nl : int;
	q : int;

	if(t.what != Body){
		if(doselect)
			t.setselect(q0, q1);
		return;
	}
	if(t.w!=nil && t.frame.maxlines==0)
		t.col.grow(t.w, 1, 0);
	if(doselect)
		t.setselect(q0, q1);
	qe = t.org+t.frame.nchars;
	if(t.org<=q0 && (q0<qe || (q0==qe && qe==t.file.buf.nc+t.ncache)))
		scrdraw(t);
	else{
		if(t.w.nopen[Dat->QWevent]>byte 0)
			nl = 3*t.frame.maxlines/4;
		else
			nl = t.frame.maxlines/4;
		q = t.backnl(q0, nl);
		# avoid going backwards if trying to go forwards - long lines! 
		if(!(q0>t.org && q<t.org))
			t.setorigin(q, TRUE);
		while(q0 > t.org+t.frame.nchars)
			t.setorigin(t.org+1, FALSE);
	}
}

region(a, b : int) : int
{
	if(a < b)
		return -1;
	if(a == b)
		return 0;
	return 1;
}

selrestore(f : ref Frame, pt0 : Point, p0 : int, p1 : int)
{
	if(p1<=f.p0 || p0>=f.p1){
		# no overlap
		frdrawsel0(f, pt0, p0, p1, f.cols[BACK], f.cols[TEXT]);
		return;
	}
	if(p0>=f.p0 && p1<=f.p1){
		# entirely inside
		frdrawsel0(f, pt0, p0, p1, f.cols[HIGH], f.cols[HTEXT]);
		return;
	}
	# they now are known to overlap
	# before selection
	if(p0 < f.p0){
		frdrawsel0(f, pt0, p0, f.p0, f.cols[BACK], f.cols[TEXT]);
		p0 = f.p0;
		pt0 = frptofchar(f, p0);
	}
	# after selection
	if(p1 > f.p1){
		frdrawsel0(f, frptofchar(f, f.p1), f.p1, p1, f.cols[BACK], f.cols[TEXT]);
		p1 = f.p1;
	}
	# inside selection
	frdrawsel0(f, pt0, p0, p1, f.cols[HIGH], f.cols[HTEXT]);
}

Text.setselect(t : self ref Text, q0 : int, q1 : int)
{
	p0, p1 : int;

	# t.p0 and t.p1 are always right; t.q0 and t.q1 may be off 
	t.q0 = q0;
	t.q1 = q1;
	# compute desired p0,p1 from q0,q1
	p0 = q0-t.org;
	p1 = q1-t.org;
	if(p0 < 0)
		p0 = 0;
	if(p1 < 0)
		p1 = 0;
	if(p0 > t.frame.nchars)
		p0 = t.frame.nchars;
	if(p1 > t.frame.nchars)
		p1 = t.frame.nchars;
	if(p0==t.frame.p0 && p1==t.frame.p1)
		return;
	# screen disagrees with desired selection
	if(t.frame.p1<=p0 || p1<=t.frame.p0 || p0==p1 || t.frame.p1==t.frame.p0){
		# no overlap or too easy to bother trying
		frdrawsel(t.frame, frptofchar(t.frame, t.frame.p0), t.frame.p0, t.frame.p1, 0);
		frdrawsel(t.frame, frptofchar(t.frame, p0), p0, p1, 1);
		t.frame.p0 = p0;
		t.frame.p1 = p1;
		return;
	}
	# overlap; avoid unnecessary painting
	if(p0 < t.frame.p0){
		# extend selection backwards
		frdrawsel(t.frame, frptofchar(t.frame, p0), p0, t.frame.p0, 1);
	}else if(p0 > t.frame.p0){
		# trim first part of selection
		frdrawsel(t.frame, frptofchar(t.frame, t.frame.p0), t.frame.p0, p0, 0);
	}
	if(p1 > t.frame.p1){
		# extend selection forwards
		frdrawsel(t.frame, frptofchar(t.frame, t.frame.p1), t.frame.p1, p1, 1);
	}else if(p1 < t.frame.p1){
		# trim last part of selection
		frdrawsel(t.frame, frptofchar(t.frame, p1), p1, t.frame.p1, 0);
	}
	t.frame.p0 = p0;
	t.frame.p1 = p1;
}

Text.setselect0(t : self ref Text, q0 : int, q1 : int)
{
	t.q0 = q0;
	t.q1 = q1;
}

xselect(f : ref Frame, mc : ref Draw->Pointer, col, colt : ref Image) : (int, int)
{
	p0, p1, q, tmp : int;
	mp, pt0, pt1, qt : Point;
	reg, b : int;

	# when called button 1 is down
	mp = mc.xy;
	b = mc.buttons;

	# remove tick
	if(f.p0 == f.p1)
		frtick(f, frptofchar(f, f.p0), 0);
	p0 = p1 = frcharofpt(f, mp);
	pt0 = frptofchar(f, p0);
	pt1 = frptofchar(f, p1);
	reg = 0;
	frtick(f, pt0, 1);
	do{
		q = frcharofpt(f, mc.xy);
		if(p1 != q){
			if(p0 == p1)
				frtick(f, pt0, 0);
			if(reg != region(q, p0)){	# crossed starting point; reset
				if(reg > 0)
					selrestore(f, pt0, p0, p1);
				else if(reg < 0)
					selrestore(f, pt1, p1, p0);
				p1 = p0;
				pt1 = pt0;
				reg = region(q, p0);
				if(reg == 0)
					frdrawsel0(f, pt0, p0, p1, col, colt);
			}
			qt = frptofchar(f, q);
			if(reg > 0){
				if(q > p1)
					frdrawsel0(f, pt1, p1, q, col, colt);
				else if(q < p1)
					selrestore(f, qt, q, p1);
			}else if(reg < 0){
				if(q > p1)
					selrestore(f, pt1, p1, q);
				else
					frdrawsel0(f, qt, q, p1, col, colt);
			}
			p1 = q;
			pt1 = qt;
		}
		if(p0 == p1)
			frtick(f, pt0, 1);
		bflush();
		frgetmouse();
	}while(mc.buttons == b);
	if(p1 < p0){
		tmp = p0;
		p0 = p1;
		p1 = tmp;
	}
	pt0 = frptofchar(f, p0);
	if(p0 == p1)
		frtick(f, pt0, 0);
	selrestore(f, pt0, p0, p1);
	# restore tick
	if(f.p0 == f.p1)
		frtick(f, frptofchar(f, f.p0), 1);
	bflush();
	return (p0, p1);
}

Text.select23(t : self ref Text, q0 : int, q1 : int, high, low : ref Image, mask : int) : (int, int, int)
{
	p0, p1 : int;
	buts : int;

	(p0, p1) = xselect(t.frame, mouse, high, low);
	buts = mouse.buttons;
	if((buts & mask) == 0){
		q0 = p0+t.org;
		q1 = p1+t.org;
	}
	while(mouse.buttons)
		frgetmouse();
	return (buts, q0, q1);
}

Text.select2(t : self ref Text, q0 : int, q1 : int) : (int, ref Text, int, int)
{
	buts : int;
	
	(buts, q0, q1) = t.select23(q0, q1, acme->but2col, acme->but2colt, 4);
	if(buts & 4)
		return (0, nil, q0, q1);
	if(buts & 1)	# pick up argument 
		return (1, dat->argtext, q0, q1);
	return (1, nil, q0, q1);
}

Text.select3(t : self ref Text, q0 : int, q1 : int) : (int, int, int)
{
	buts : int;
	
	(buts, q0, q1) = t.select23(q0, q1, acme->but3col, acme->but3colt, 1|2);
	return (buts == 0, q0, q1);
}

left := array[4] of {
	"{[(<«",
	"\n",
	"'\"`",
	nil
};
right := array[4] of {
	"}])>»",
	"\n",
	"'\"`",
	nil
};

Text.doubleclick(t : self ref Text, q0 : int, q1 : int) : (int, int)
{
	c, i : int;
	r, l : string;
	p : int;
	q : int;
	res : int;

	for(i=0; left[i]!=nil; i++){
		q = q0;
		l = left[i];
		r = right[i];
		# try matching character to left, looking right 
		if(q == 0)
			c = '\n';
		else
			c = t.readc(q-1);
		p = utils->strchr(l, c);
		if(p >= 0){
			(res, q) = t.clickmatch(c, r[p], 1, q);
			if (res)
				q1 = q-(c!='\n');
			return (q0, q1);
		}
		# try matching character to right, looking left 
		if(q == t.file.buf.nc)
			c = '\n';
		else
			c = t.readc(q);
		p = utils->strchr(r, c);
		if(p >= 0){
			(res, q) = t.clickmatch(c, l[p], -1, q);
			if (res){
				q1 = q0+(q0<t.file.buf.nc && c=='\n');
				q0 = q;
				if(c!='\n' || q!=0 || t.readc(0)=='\n')
					q0++;
			}
			return (q0, q1);
		}
	}
	# try filling out word to right 
	while(q1<t.file.buf.nc && isalnum(t.readc(q1)))
		q1++;
	# try filling out word to left 
	while(q0>0 && isalnum(t.readc(q0-1)))
		q0--;
	return (q0, q1);
}

Text.clickmatch(t : self ref Text, cl : int, cr : int, dir : int, q : int) : (int, int)
{
	c : int;
	nest : int;

	nest = 1;
	for(;;){
		if(dir > 0){
			if(q == t.file.buf.nc)
				break;
			c = t.readc(q);
			q++;
		}else{
			if(q == 0)
				break;
			q--;
			c = t.readc(q);
		}
		if(c == cr){
			if(--nest==0)
				return (1, q);
		}else if(c == cl)
			nest++;
	}
	return (cl=='\n' && nest==1, q);
}

Text.forwnl(t : self ref Text, p : int, n : int) : int
{
	i, j : int;

	e := t.file.buf.nc-1;
	i = n;
	while(i-- > 0 && p<e){
		++p;
		if(p == e)
			break;
		for(j=128; --j>0 && p<e; p++)
			if(t.readc(p)=='\n')
				break;
	}
	return p;
}

Text.backnl(t : self ref Text, p : int, n : int) : int
{
	i, j : int;

	# look for start of this line if n==0 
	if(n==0 && p>0 && t.readc(p-1)!='\n')
		n = 1;
	i = n;
	while(i-- > 0 && p>0){
		--p;	# it's at a newline now; back over it 
		if(p == 0)
			break;
		# at 128 chars, call it a line anyway 
		for(j=128; --j>0 && p>0; p--)
			if(t.readc(p-1)=='\n')
				break;
	}
	return p;
}

Text.setorigin(t : self ref Text, org : int, exact : int)
{
	i, a : int;
	r : ref Astring;
	n : int;

	t.frame.b.flush(Flushoff);
	if(org>0 && !exact){
		# org is an estimate of the char posn; find a newline 
		# don't try harder than 256 chars 
		for(i=0; i<256 && org<t.file.buf.nc; i++){
			if(t.readc(org) == '\n'){
				org++;
				break;
			}
			org++;
		}
	}
	a = org-t.org;
	fixup := 0;
	if(a>=0 && a<t.frame.nchars){
		frdelete(t.frame, 0, a);
		fixup = 1;		# frdelete can leave end of last line in wrong selection mode; it doesn't know what follows 
	}
	else if(a<0 && -a<t.frame.nchars){
		n = t.org - org;
		r = utils->stralloc(n);
		t.file.buf.read(org, r, 0, n);
		frinsert(t.frame, r.s, n, 0);
		utils->strfree(r);
		r = nil;
	}else
		frdelete(t.frame, 0, t.frame.nchars);
	t.org = org;
	t.fill();
	scrdraw(t);
	t.setselect(t.q0, t.q1);
	if(fixup && t.frame.p1 > t.frame.p0)
		frdrawsel(t.frame, frptofchar(t.frame, t.frame.p1-1), t.frame.p1-1, t.frame.p1, 1);
	t.frame.b.flush(Flushon);
}

Text.reset(t : self ref Text)
{
	t.file.seq = 0;
	t.eq0 = ~0;
	# do t.delete(0, t.nc, TRUE) without building backup stuff 
	t.setselect(t.org, t.org);
	frdelete(t.frame, 0, t.frame.nchars);
	t.org = 0;
	t.q0 = 0;
	t.q1 = 0;
	t.file.reset();
	t.file.buf.reset();
}
