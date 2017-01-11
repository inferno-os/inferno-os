implement Look;

include "common.m";

sys : Sys;
draw : Draw;
utils : Utils;
dat : Dat;
graph : Graph;
acme : Acme;
framem : Framem;
regx : Regx;
bufferm : Bufferm;
textm : Textm;
windowm : Windowm;
columnm : Columnm;
exec : Exec;
scrl : Scroll;
plumbmsg : Plumbmsg;

sprint : import sys;
Point : import draw;
warning, isalnum, stralloc, strfree, strchr, tgetc : import utils;
Range, TRUE, FALSE, XXX, BUFSIZE, Astring : import Dat;
Expand, seltext, row : import dat;
cursorset : import graph;
frptofchar : import framem;
isaddrc, isregexc, address : import regx;
Buffer : import bufferm;
Text : import textm;
Window : import windowm;
Column : import columnm;
Msg : import plumbmsg;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	draw = mods.draw;
	utils = mods.utils;
	graph = mods.graph;
	acme = mods.acme;
	framem = mods.framem;
	regx = mods.regx;
	dat = mods.dat;
	bufferm = mods.bufferm;
	textm = mods.textm;
	windowm = mods.windowm;
	columnm = mods.columnm;
	exec = mods.exec;
	scrl = mods.scroll;
	plumbmsg = mods.plumbmsg;
}

nuntitled : int;

look3(t : ref Text, q0 : int, q1 : int, external : int)
{
	n, c, f : int;
	ct : ref Text;
	e : Expand;
	r : ref Astring;
	expanded : int;

	ct = seltext;
	if(ct == nil)
		seltext = t;
	(expanded, e) = expand(t, q0, q1);
	if(!external && t.w!=nil && t.w.nopen[Dat->QWevent]>byte 0){
		if(!expanded)
			return;
		f = 0;
		if((e.at!=nil && t.w!=nil) || (e.name!=nil && lookfile(e.name, len e.name)!=nil))
			f = 1;		# acme can do it without loading a file 
		if(q0!=e.q0 || q1!=e.q1)
			f |= 2;	# second (post-expand) message follows 
		if(e.name != nil)
			f |= 4;	# it's a file name 
		c = 'l';
		if(t.what == Textm->Body)
			c = 'L';
		n = q1-q0;
		if(n <= Dat->EVENTSIZE){
			r = stralloc(n);
			t.file.buf.read(q0, r, 0, n);
			t.w.event(sprint("%c%d %d %d %d %s\n", c, q0, q1, f, n, r.s[0:n]));
			strfree(r);
			r = nil;
		}else
			t.w.event(sprint("%c%d %d %d 0 \n", c, q0, q1, f));
		if(q0==e.q0 && q1==e.q1)
			return;
		if(e.name != nil){
			n = len e.name;
			if(e.a1 > e.a0)
				n += 1+(e.a1-e.a0);
			r = stralloc(n);
			for (i := 0; i < len e.name; i++)
				r.s[i] = e.name[i];
			if(e.a1 > e.a0){
				r.s[len e.name] = ':';
				e.at.file.buf.read(e.a0, r, len e.name+1, e.a1-e.a0);
			}
		}else{
			n = e.q1 - e.q0;
			r = stralloc(n);
			t.file.buf.read(e.q0, r, 0, n);
		}
		f &= ~2;
		if(n <= Dat->EVENTSIZE)
			t.w.event(sprint("%c%d %d %d %d %s\n", c, e.q0, e.q1, f, n, r.s[0:n]));
		else
			t.w.event(sprint("%c%d %d %d 0 \n", c, e.q0, e.q1, f));
		strfree(r);
		r = nil;
		return;
	}
	if(0 && dat->plumbed){	# don't do yet : 2 acmes running => only 1 receives msg
		m := ref Msg;
		m.src = "acme";
		m.dst = nil;
		(dir, nil) := dirname(t, nil, 0);
		if(dir == ".")	# sigh
			dir = nil;
		if(dir == nil)
			dir = acme->wdir;
		m.dir = dir;
		m.kind = "text";
		m.attr = nil;
		if(q1 == q0){
			if(t.q1>t.q0 && t.q0<=q0 && q0<=t.q1){
				q0 = t.q0;
				q1 = t.q1;
			}else{
				p := q0;
				while(q0 > 0 && (c = tgetc(t, q0-1)) != ' ' && c != '\t' && c != '\n')
					q0--;
				while(q1 < t.file.buf.nc && (c = tgetc(t, q1)) != ' ' && c != '\t' && c != '\n')
					q1++;
				if(q1 == q0)
					return;
				m.attr = "click=" + string (p-q0);
			}
		}
		r = stralloc(q1-q0);
		t.file.buf.read(q0, r, 0, q1-q0);
		m.data = array of byte r.s;
		strfree(r);
		if(m.send() >= 0)
			return;
		# plumber failed to match : fall through
	}
	if(!expanded)
		return;
	if(e.name != nil || e.at != nil)
		(nil, e) = openfile(t, e);
	else{
		if(t.w == nil)
			return;
		ct = t.w.body;
		if(t.w != ct.w)
			ct.w.lock('M');
		if(t == ct)
			ct.setselect(e.q1, e.q1);
		n = e.q1 - e.q0;
		r = stralloc(n);
		t.file.buf.read(e.q0, r, 0, n);
		if(search(ct, r.s, n) && e.jump)
			cursorset(frptofchar(ct.frame, ct.frame.p0).add((4, ct.frame.font.height-4)));
		if(t.w != ct.w)
			ct.w.unlock();
		strfree(r);
		r = nil;
	}
	e.name = nil;
	e.bname = nil;
}

plumblook(m : ref Msg)
{
	e : Expand;

	if (len m.data > Dat->PLUMBSIZE) {
		warning(nil, sys->sprint("plumb message too long : %s\n", string m.data));
		return;
	}
	e.q0 = e.q1 = 0;
	if (len m.data == 0)
		return;
	e.ar = nil;
	e.name = string m.data;
	if(e.name[0] != '/' && m.dir != nil)
		e.name = m.dir + "/" + e.name;
	(e.name, nil) = cleanname(e.name, len e.name);
	e.bname = e.name;
	e.jump = TRUE;
	e.a0 = e.a1 = 0;
	(found, addr) := plumbmsg->lookup(plumbmsg->string2attrs(m.attr), "addr");
	if (found && addr != nil) {
		e.ar = addr;
		e.a1 = len addr;
	}
	openfile(nil, e);
	e.at = nil;
}

plumbshow(m : ref Msg)
{
	w := utils->newwindow(nil);
	(found, name) := plumbmsg->lookup(plumbmsg->string2attrs(m.attr), "filename");
	if (!found || name == nil) {
		nuntitled++;
		name = "Untitled-" + string nuntitled;
	}
	if (name[0] != '/' && m.dir != nil)
		name = m.dir + "/" + name;
	(name, nil) = cleanname(name, len name);
	w.setname(name, len name);
	d := string m.data;
	w.body.insert(0, d, len d, TRUE, FALSE);
	w.body.file.mod = FALSE;
	w.dirty = FALSE;
	w.settag();
	scrl->scrdraw(w.body);
	w.tag.setselect(w.tag.file.buf.nc, w.tag.file.buf.nc);
}

search(ct : ref Text, r : string, n : int) : int
{
	q, nb, maxn : int;
	around : int;
	s : ref Astring;
	b, c : int;

	if(n==0 || n>ct.file.buf.nc)
		return FALSE;
	if(2*n > BUFSIZE){
		warning(nil, "string too long\n");
		return FALSE;
	}
	maxn = utils->max(2*n, BUFSIZE);
	s = utils->stralloc(BUFSIZE);
	b = nb = 0;
	around = 0;
	q = ct.q1;
	for(;;){
		if(q >= ct.file.buf.nc){
			q = 0;
			around = 1;
			nb = 0;
		}
		if(nb > 0){
			for (c = 0; c < nb; c++)
				if (s.s[b+c] == r[0])
					break;
			if(c >= nb){
				q += nb;
				nb = 0;
				if(around && q>=ct.q1)
					break;
				continue;
			}
			q += c;
			nb -= c;
			b += c;
		}
		# reload if buffer covers neither string nor rest of file 
		if(nb<n && nb!=ct.file.buf.nc-q){
			nb = ct.file.buf.nc-q;
			if(nb >= maxn)
				nb = maxn-1;
			ct.file.buf.read(q, s, 0, nb);
			b = 0;
		}
		if(n <= nb && s.s[b:b+n] == r[0:n]){
			if(ct.w != nil){
				ct.show(q, q+n, TRUE);
				ct.w.settag();
			}else{
				ct.q0 = q;
				ct.q1 = q+n;
			}
			seltext = ct;
			utils->strfree(s);
			s = nil;
			return TRUE;
		}
		if(around && q>=ct.q1)
			break;
		--nb;
		b++;
		q++;
	}
	utils->strfree(s);
	s = nil;
	return FALSE;
}

isfilec(r : int) : int
{
	if(isalnum(r))
		return TRUE;
	if(strchr(".-+/:", r) >= 0)
		return TRUE;
	return FALSE;
}

cleanname(b : string, n : int) : (string, int)
{
	i, j, found : int;

	b = b[0:n];
	# compress multiple slashes 
	for(i=0; i<n-1; i++)
		if(b[i]=='/' && b[i+1]=='/'){
			b = b[0:i] + b[i+1:];
			--n;
			--i;
		}
	#  eliminate ./ 
	for(i=0; i<n-1; i++)
		if(b[i]=='.' && b[i+1]=='/' && (i==0 || b[i-1]=='/')){
			b = b[0:i] + b[i+2:];
			n -= 2;
			--i;
		}
	# eliminate trailing . 
	if(n>=2 && b[n-2]=='/' && b[n-1]=='.') {
		--n;
		b = b[0:n];
	}
	do{
		# compress xx/.. 
		found = FALSE;
		for(i=1; i<=n-3; i++)
			if(b[i:i+3] == "/.."){
				if(i==n-3 || b[i+3]=='/'){
					found = TRUE;
					break;
				}
			}
		if(found)
			for(j=i-1; j>=0; --j)
				if(j==0 || b[j-1]=='/'){
					i += 3;		# character beyond .. 
					if(i<n && b[i]=='/')
						++i;
					b = b[0:j] + b[i:];
					n -= (i-j);
					break;
				}
	}while(found);
	if(n == 0){
		b = ".";
		n = 1;
	}
	return (b, n);
}

includefile(dir : string, file : string, nfile : int) : (string, int)
{
	m, n : int;
	a : string;

	if (dir == ".") {
		m = 0;
		a = file;
	}
	else {
		m = 1 + len dir;
		a = dir + "/" + file;
	}
	n = utils->access(a);
	if(n < 0) {
		a = nil;
		return (nil, 0);
	}
	file = nil;
	return cleanname(a, m+nfile);
}

objdir : string;

includename(t : ref Text , r : string, n : int) : (string, int)
{
	file : string;
	i, nfile : int;
	w : ref Window;

	{
		w = t.w;
		if(n==0 || r[0]=='/' || w==nil)
			raise "e";
		if(n>2 && r[0]=='.' && r[1]=='/')
			raise "e";
		file = nil;
		nfile = 0;
		(file, nfile) = includefile(".", r, n);
		if (file == nil) {
			(dr, dn) := dirname(t, r, n);
			(file, nfile) = includefile(".", dr, dn);
		}
		if (file == nil) {
			for(i=0; i<w.nincl && file==nil; i++)
				(file, nfile) = includefile(w.incl[i], r, n);
		}
		if(file == nil)
			(file, nfile) = includefile("/module", r, n);
		if(file == nil)
			(file, nfile) = includefile("/include", r, n);
		if(file==nil && objdir!=nil)
			(file, nfile) = includefile(objdir, r, n);
		if(file == nil)
			raise "e";
		return (file, nfile);
	}
	exception{
		* =>
			return (r, n);
	}
	return (nil, 0);
}

dirname(t : ref Text, r : string, n : int) : (string, int)
{
	b : ref Astring;
	c : int;
	m, nt : int;
	slash : int;

	{
		b = nil;
		if(t == nil || t.w == nil)
			raise "e";
		nt = t.w.tag.file.buf.nc;
		if(nt == 0)
			raise "e";
		if(n>=1 &&  r[0]=='/')
			raise "e";
		b = stralloc(nt+n+1);
		t.w.tag.file.buf.read(0, b, 0, nt);
		slash = -1;
		for(m=0; m<nt; m++){
			c = b.s[m];
			if(c == '/')
				slash = m;
			if(c==' ' || c=='\t')
				break;
		}
		if(slash < 0)
			raise "e";
		for (i := 0; i < n; i++)
			b.s[slash+1+i] = r[i];
		r = nil;
		return cleanname(b.s, slash+1+n);
	}
	exception{
		* =>
			b = nil;
			if(r != nil)
				return cleanname(r, n);
			return (r, n);
	}
	return (nil, 0);
}

expandfile(t : ref Text, q0 : int, q1 : int, e : Expand) : (int, Expand)
{
	i, n, nname, colon : int;
	amin, amax : int;
	r : ref Astring;
	c : int;
	w : ref Window;

	amax = q1;
	if(q1 == q0){
		colon = -1;
		while(q1<t.file.buf.nc && isfilec(c=t.readc(q1))){
			if(c == ':'){
				colon = q1;
				break;
			}
			q1++;
		}
		while(q0>0 && (isfilec(c=t.readc(q0-1)) || isaddrc(c) || isregexc(c))){
			q0--;
			if(colon==-1 && c==':')
				colon = q0;
		}
		#
		# if it looks like it might begin file: , consume address chars after :
		# otherwise terminate expansion at :
		#
		
		if(colon>=0 && colon<t.file.buf.nc-1 && isaddrc(t.readc(colon+1))){
			q1 = colon+1;
			while(q1<t.file.buf.nc-1 && isaddrc(t.readc(q1)))
				q1++;
		}else if(colon >= 0)
			q1 = colon;
		if(q1 > q0)
			if(colon >= 0){	# stop at white space
				for(amax=colon+1; amax<t.file.buf.nc; amax++)
					if((c=t.readc(amax))==' ' || c=='\t' || c=='\n')
						break;
			}else
				amax = t.file.buf.nc;
	}
	amin = amax;
	e.q0 = q0;
	e.q1 = q1;
	n = q1-q0;
	if(n == 0)
		return (FALSE, e);
	# see if it's a file name 
	r = stralloc(n);
	t.file.buf.read(q0, r, 0, n);
	# first, does it have bad chars? 
	nname = -1;
	for(i=0; i<n; i++){
		c = r.s[i];
		if(c==':' && nname<0){
			if(q0+i+1<t.file.buf.nc && (i==n-1 || isaddrc(t.readc(q0+i+1))))
				amin = q0+i;
			else {
				strfree(r);
				r = nil;
				return (FALSE, e);
			}
			nname = i;
		}
	}
	if(nname == -1)
		nname = n;
	for(i=0; i<nname; i++)
		if(!isfilec(r.s[i])) {
			strfree(r);
			r = nil;
			return (FALSE, e);
		}
	#
	# See if it's a file name in <>, and turn that into an include
	# file name if so.  Should probably do it for "" too, but that's not
	# restrictive enough syntax and checking for a #include earlier on the
	# line would be silly.
	#
	 
	isfile := 0;
	if(q0>0 && t.readc(q0-1)=='<' && q1<t.file.buf.nc && t.readc(q1)=='>')
		(r.s, nname) = includename(t, r.s, nname);
	else if(q0>0 && t.readc(q0-1)=='"' && q1<t.file.buf.nc && t.readc(q1)=='"')
		(r.s, nname) = includename(t, r.s, nname);
	else if(amin == q0)
		isfile = 1;
	else
		(r.s, nname) = dirname(t, r.s, nname);
	if (!isfile) {
		e.bname = r.s;
		# if it's already a window name, it's a file 
		w = lookfile(r.s, nname);
		# if it's the name of a file, it's a file 
		if(w == nil && utils->access(e.bname) < 0){
			e.bname = nil;
			strfree(r);
			r = nil;
			return (FALSE, e);
		}
	}

	e.name = r.s[0:nname];
	e.at = t;
	e.a0 = amin+1;
	(nil, e.a1, nil) = address(nil, nil, (Range)(-1,-1), (Range)(0, 0), t, nil, e.a0, amax, FALSE);
	strfree(r);
	r = nil;
	return (TRUE, e);
}

expand(t : ref Text, q0 : int, q1 : int) : (int, Expand)
{
	e : Expand;
	ok : int;

	e.q0 = e.q1 = e.a0 = e.a1 = 0;
	e.name = e.bname = nil;
	e.at = nil;
	# if in selection, choose selection 
	e.jump = TRUE;
	if(q1==q0 && t.q1>t.q0 && t.q0<=q0 && q0<=t.q1){
		q0 = t.q0;
		q1 = t.q1;
		if(t.what == Textm->Tag)
			e.jump = FALSE;
	}

	(ok, e) = expandfile(t, q0, q1, e);
	if (ok)
		return (TRUE, e);

	if(q0 == q1){
		while(q1<t.file.buf.nc && isalnum(t.readc(q1)))
			q1++;
		while(q0>0 && isalnum(t.readc(q0-1)))
			q0--;
	}
	e.q0 = q0;
	e.q1 = q1;
	return (q1 > q0, e);
}

lookfile(s : string, n : int) : ref Window
{
	i, j, k : int;
	w : ref Window;
	c : ref Column;
	t : ref Text;

	# avoid terminal slash on directories 
	if(n > 1 && s[n-1] == '/')
		--n;
	for(j=0; j<row.ncol; j++){
		c = row.col[j];
		for(i=0; i<c.nw; i++){
			w = c.w[i];
			t = w.body;
			k = len t.file.name;
			if(k>0 && t.file.name[k-1] == '/')
				k--;
			if(t.file.name[0:k] == s[0:n]){
				w = w.body.file.curtext.w;
				if(w.col != nil)	# protect against race deleting w
					return w;
			}
		}
	}
	return nil;
}

lookid(id : int, dump : int) : ref Window
{
	i, j : int;
	w : ref Window;
	c : ref Column;

	for(j=0; j<row.ncol; j++){
		c = row.col[j];
		for(i=0; i<c.nw; i++){
			w = c.w[i];
			if(dump && w.dumpid == id)
				return w;
			if(!dump && w.id == id)
				return w;
		}
	}
	return nil;
}

openfile(t : ref Text, e : Expand) : (ref Window, Expand)
{
	r : Range;
	w, ow : ref Window;
	eval, i, n : int;

	if(e.name == nil){
		w = t.w;
		if(w == nil)
			return (nil, e);
	}else
		w = lookfile(e.name, len e.name);
	if(w != nil){
		t = w.body;
		if(!t.col.safe && t.frame.maxlines==0) # window is obscured by full-column window
			t.col.grow(t.col.w[0], 1, 1);
	}
	else{
		ow = nil;
		if(t != nil)
			ow = t.w;
		w = utils->newwindow(t);
		t = w.body;
		w.setname(e.name, len e.name);
		t.loadx(0, e.bname, 1);
		t.file.mod = FALSE;
		t.w.dirty = FALSE;
		t.w.settag();
		t.w.tag.setselect(t.w.tag.file.buf.nc, t.w.tag.file.buf.nc);
		if(ow != nil)
			for(i=ow.nincl; --i>=0; ){
				n = len ow.incl[i];
				w.addincl(ow.incl[i], n);	# really do want to copy here
			}
	}
	if(e.a1 == e.a0)
		eval = FALSE;
	else
		(eval, nil, r) = address(nil, t, (Range)(-1, -1), (Range)(t.q0, t.q1), e.at, e.ar, e.a0, e.a1, TRUE);
		# was (eval, nil, r) = address(nil, t, (Range)(-1, -1), (Range)(t.q0, t.q1), e.at, nil, e.a0, e.a1, TRUE);
	if(eval == FALSE){
		r.q0 = t.q0;
		r.q1 = t.q1;
	}
	t.show(r.q0, r.q1, TRUE);
	t.w.settag();
	seltext = t;
	if(e.jump)
		cursorset(frptofchar(t.frame, t.frame.p0).add((4, t.frame.font.height-4)));
	return (w, e);
}

new(et : ref Text, t : ref Text, argt : ref Text, flag1 : int, flag2 : int, arg : string, narg : int)
{
	ndone : int;
	a, f : string;
	na, nf : int;
	e : Expand;

	(nil, a, na) = exec->getarg(argt, FALSE, TRUE);
	if(a != nil){
		new(et, t, nil, flag1, flag2, a, na);
		if(narg == 0)
			return;
	}
	# loop condition: *arg is not a blank 
	for(ndone=0; ; ndone++){
		(a, na) = utils->findbl(arg, narg);
		if(a == arg){
			if(ndone==0 && et.col!=nil)
				et.col.add(nil, nil, -1).settag();
			break;
		}
		nf = narg-na;
		f = arg[0:nf];	# want a copy
		(f, nf) = dirname(et, f, nf);
		e.q0 = e.q1 = e.a0 = e.a1 = 0;
		e.at = nil;
		e.name = f;
		e.bname = f;
		e.jump = TRUE;
		(nil, e) = openfile(et, e);
		f = nil;
		e.bname = nil;
		(arg, narg) = utils->skipbl(a, na);
	}
}
