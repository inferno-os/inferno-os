implement Exec;

include "common.m";

sys : Sys;
dat : Dat;
acme : Acme;
utils : Utils;
graph : Graph;
gui : Gui;
lookx : Look;
bufferm : Bufferm;
textm : Textm;
scrl : Scroll;
filem : Filem;
windowm : Windowm;
rowm : Rowm;
columnm : Columnm;
fsys : Fsys;
editm: Edit;

Dir, OREAD, OWRITE : import Sys;
EVENTSIZE, QWaddr, QWdata, QWevent, Astring : import dat;
Lock, Reffont, Ref, seltext, seq, row : import dat;
warning, error, skipbl, findbl, stralloc, strfree, exec : import utils;
dirname : import lookx;
Body, Text : import textm;
File : import filem;
sprint : import sys;
TRUE, FALSE, XXX, BUFSIZE : import Dat;
Buffer : import bufferm;
Row : import rowm;
Column : import columnm;
Window : import windowm;
setalphabet: import textm;

# snarfbuf : ref Buffer;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	dat = mods.dat;
	acme = mods.acme;
	utils = mods.utils;
	graph = mods.graph;
	gui = mods.gui;
	lookx = mods.look;
	bufferm = mods.bufferm;
	textm = mods.textm;
	scrl = mods.scroll;
	filem = mods.filem;
	rowm = mods.rowm;
	windowm = mods.windowm;
	columnm = mods.columnm;
	fsys = mods.fsys;
	editm = mods.edit;

	snarfbuf = bufferm->newbuffer();
}

Exectab : adt {
	name : string;
	fun : int;
	mark : int;
	flag1 : int;
	flag2 : int;
};

F_ALPHABET, F_CUT, F_DEL, F_DELCOL, F_DUMP, F_EDIT, F_EXITX, F_FONTX, F_GET, F_ID, F_INCL, F_KILL, F_LIMBO, F_LINENO, F_LOCAL, F_LOOK, F_NEW, F_NEWCOL, F_PASTE, F_PUT, F_PUTALL, F_UNDO, F_SEND, F_SORT, F_TAB, F_ZEROX : con iota;

exectab := array[] of {
	Exectab ( "Alphabet",	F_ALPHABET,	FALSE,	XXX,		XXX		),
	Exectab ( "Cut",		F_CUT,		TRUE,	TRUE,	TRUE	),
	Exectab ( "Del",			F_DEL,		FALSE,	FALSE,	XXX		),
	Exectab ( "Delcol",		F_DELCOL,	FALSE,	XXX,		XXX		),
	Exectab ( "Delete",		F_DEL,		FALSE,	TRUE,	XXX		),
	Exectab ( "Dump",		F_DUMP,		FALSE,	TRUE,	XXX		),
	Exectab ( "Edit",		F_EDIT,		FALSE,	XXX,		XXX		),
	Exectab ( "Exit",		F_EXITX,		FALSE,	XXX,		XXX		),
	Exectab ( "Font",		F_FONTX,		FALSE,	XXX,		XXX		),
	Exectab ( "Get",			F_GET,		FALSE,	TRUE,	XXX		),
	Exectab ( "ID",			F_ID,		FALSE,	XXX,		XXX		),
	Exectab ( "Incl",		F_INCL,		FALSE,	XXX,		XXX		),
	Exectab ( "Kill",			F_KILL,		FALSE,	XXX,		XXX		),
	Exectab ( "Limbo",		F_LIMBO,		FALSE,	XXX,		XXX   	),
	Exectab ( "Lineno",		F_LINENO,	FALSE,	XXX,		XXX		),
	Exectab ( "Load",		F_DUMP,		FALSE,	FALSE,	XXX		),
	Exectab ( "Local",		F_LOCAL,		FALSE,	XXX,		XXX		),
	Exectab ( "Look",		F_LOOK,		FALSE,	XXX,		XXX		),
	Exectab ( "New",		F_NEW,		FALSE,	XXX,		XXX		),
	Exectab ( "Newcol",		F_NEWCOL,	FALSE,	XXX,		XXX		),
	Exectab ( "Paste",		F_PASTE,		TRUE,	TRUE,	XXX		),
	Exectab ( "Put",			F_PUT,		FALSE,	XXX,		XXX		),
	Exectab ( "Putall",		F_PUTALL,	FALSE,	XXX,		XXX		),
	Exectab ( "Redo",		F_UNDO,		FALSE,	FALSE,	XXX		),
	Exectab ( "Send",		F_SEND,		TRUE,	XXX,		XXX		),
	Exectab ( "Snarf",		F_CUT,		FALSE,	TRUE,	FALSE	),
	Exectab ( "Sort",		F_SORT,		FALSE,	XXX,		XXX		),
	Exectab ( "Tab",		F_TAB,		FALSE,	XXX,		XXX		),
	Exectab ( "Undo",		F_UNDO,		FALSE,	TRUE,	XXX		),
	Exectab ( "Zerox",		F_ZEROX,		FALSE,	XXX,		XXX		),
	Exectab ( nil, 			0,			0,		0,		0		),
};

runfun(fun : int, et, t, argt : ref Text, flag1, flag2 : int, arg : string, narg : int)
{
	case (fun) {
		F_ALPHABET	=> alphabet(et, argt, arg, narg);
		F_CUT 	 	=> cut(et, t, flag1, flag2);
		F_DEL 		=> del(et, flag1);
		F_DELCOL	=> delcol(et);
		F_DUMP 		=> dump(argt, flag1, arg, narg);
		F_EDIT		=> edit(et, argt, arg, narg);
		F_EXITX		=> exitx();
		F_FONTX		=> fontx(et, t, argt, arg, narg);
		F_GET 		=> get(et, t, argt, flag1, arg, narg);
		F_ID 		=> id(et);
		F_INCL 		=> incl(et, argt, arg, narg);
		F_KILL 		=> kill(argt, arg, narg);
		F_LIMBO		=> limbo(et);
		F_LINENO		=> lineno(et);
		F_LOCAL 		=> local(et, argt, arg);
		F_LOOK 		=> look(et, t, argt);
		F_NEW 		=> lookx->new(et, t, argt, flag1, flag2, arg, narg);
		F_NEWCOL	=> newcol(et);
		F_PASTE		=> paste(et, t, flag1, flag2);
		F_PUT		=> put(et, argt, arg, narg);
		F_PUTALL 	=> putall();
		F_UNDO 		=> undo(et, flag1);
		F_SEND		=> send(et, t);
		F_SORT		=> sort(et);
		F_TAB		=> tab(et, argt, arg, narg);
		F_ZEROX		=> zerox(et, t);
		*			=> error("bad case in runfun()");
	}
}	
		
lookup(r : string, n : int) : int
{
	nr : int;

	(r, n) = skipbl(r, n);
	if(n == 0)
		return -1;
	(nil, nr) = findbl(r, n);
	nr = n-nr;
	for(i := 0; exectab[i].name != nil; i++)
		if (r[0:nr] == exectab[i].name)
			return i;
	return -1;
}

isexecc(c : int) : int
{
	if(lookx->isfilec(c))
		return 1;
	return c=='<' || c=='|' || c=='>';
}

execute(t : ref Text, aq0 : int, aq1 : int, external : int, argt : ref Text)
{
	q0, q1 : int;
	r : ref Astring;
	s, dir, aa, a : string;
	e : int;
	c, n, f : int;

	q0 = aq0;
	q1 = aq1;
	if(q1 == q0){	# expand to find word (actually file name) 
		# if in selection, choose selection 
		if(t.q1>t.q0 && t.q0<=q0 && q0<=t.q1){
			q0 = t.q0;
			q1 = t.q1;
		}else{
			while(q1<t.file.buf.nc && isexecc(c=t.readc(q1)) && c!=':')
				q1++;
			while(q0>0 && isexecc(c=t.readc(q0-1)) && c!=':')
				q0--;
			if(q1 == q0)
				return;
		}
	}
	r = stralloc(q1-q0);
	t.file.buf.read(q0, r, 0, q1-q0);
	e = lookup(r.s, q1-q0);
	if(!external && t.w!=nil && t.w.nopen[QWevent]>byte 0){
		f = 0;
		if(e >= 0)
			f |= 1;
		if(q0!=aq0 || q1!=aq1){
			t.file.buf.read(aq0, r, 0, aq1-aq0);
			f |= 2;
		}
		(aa, a) = getbytearg(argt, TRUE, TRUE);
		if(a != nil){	
			if(len a > EVENTSIZE){	# too big; too bad 
				aa = a = nil;
				warning(nil, "`argument string too long\n");
				return;
			}
			f |= 8;
		}
		c = 'x';
		if(t.what == Body)
			c = 'X';
		n = aq1-aq0;
		if(n <= EVENTSIZE)
			t.w.event(sprint("%c%d %d %d %d %s\n", c, aq0, aq1, f, n, r.s[0:n]));
		else
			t.w.event(sprint("%c%d %d %d 0 \n", c, aq0, aq1, f));
		if(q0!=aq0 || q1!=aq1){
			n = q1-q0;
			t.file.buf.read(q0, r, 0, n);
			if(n <= EVENTSIZE)
				t.w.event(sprint("%c%d %d 0 %d %s\n", c, q0, q1, n, r.s[0:n]));
			else
				t.w.event(sprint("%c%d %d 0 0 \n", c, q0, q1));
		}
		if(a != nil){
			t.w.event(sprint("%c0 0 0 %d %s\n", c, len a, a));
			if(aa != nil)
				t.w.event(sprint("%c0 0 0 %d %s\n", c, len aa, aa));
			else
				t.w.event(sprint("%c0 0 0 0 \n", c));
		}
		strfree(r);
		r = nil;
		a = aa = nil;
		return;
	}
	if(e >= 0){
		if(exectab[e].mark && seltext!=nil)
		if(seltext.what == Body){
			seq++;
			seltext.w.body.file.mark();
		}
		(s, n) = skipbl(r.s, q1-q0);
		(s, n) = findbl(s, n);
		(s, n) = skipbl(s, n);
		runfun(exectab[e].fun, t, seltext, argt, exectab[e].flag1, exectab[e].flag2, s, n);
		strfree(r);
		r = nil;
		return;
	}

	(dir, n) = dirname(t, nil, 0);
	if(n==1 && dir[0]=='.'){	# sigh 
		dir = nil;
		n = 0;
	}
	(aa, a) = getbytearg(argt, TRUE, TRUE);
	if(t.w != nil)
		t.w.refx.inc();
	spawn run(t.w, r.s, dir, n, TRUE, aa, a, FALSE);
}

printarg(argt : ref Text, q0 : int, q1 : int) : string
{
	buf : string;

	if(argt.what!=Body || argt.file.name==nil)
		return nil;
	if(q0 == q1)
		buf = sprint("%s:#%d", argt.file.name, q0);
	else
		buf = sprint("%s:#%d,#%d", argt.file.name, q0, q1);
	return buf;
}

getarg(argt : ref Text, doaddr : int, dofile : int) : (string, string, int)
{
	r : ref Astring;
	n : int;
	e : Dat->Expand;
	a : string;
	ok : int;

	if(argt == nil)
		return (nil, nil, 0);
	a = nil;
	argt.commit(TRUE);
	(ok, e) = lookx->expand(argt, argt.q0, argt.q1);
	if (ok) {
		e.bname = nil;
		if(len e.name && dofile){
			if(doaddr)
				a = printarg(argt, e.q0, e.q1);
			return (a, e.name, len e.name);
		}
		e.name = nil;
	}else{
		e.q0 = argt.q0;
		e.q1 = argt.q1;
	}
	n = e.q1 - e.q0;
	r = stralloc(n);
	argt.file.buf.read(e.q0, r, 0, n);
	if(doaddr)
		a = printarg(argt, e.q0, e.q1);
	return(a, r.s, n);
}

getbytearg(argt : ref Text, doaddr : int, dofile : int) : (string, string)
{
	r : string;
	n : int;
	aa : string;

	(aa, r, n) = getarg(argt, doaddr, dofile);
	if(r == nil)
		return (nil, nil);
	return (aa, r);
}

newcol(et : ref Text)
{
	c : ref Column;

	c = et.row.add(nil, -1);
	if(c != nil)
		c.add(nil, nil, -1).settag();
}

delcol(et : ref Text)
{
	c := et.col;
	if(c==nil || !c.clean(FALSE))
		return;
	for(i:=0; i<c.nw; i++){
		w := c.w[i];
		if(int w.nopen[QWevent]+int w.nopen[QWaddr]+int w.nopen[QWdata] > 0){
			warning(nil, sys->sprint("can't delete column; %s is running an external command\n", w.body.file.name));
			return;
		}
	}
	c.row.close(c, TRUE);
}

del(et : ref Text, flag1 : int)
{
	if(et.col==nil || et.w == nil)
		return;
	if(flag1 || et.w.body.file.ntext>1 || et.w.clean(FALSE, FALSE))
		et.col.close(et.w, TRUE);
}

sort(et : ref Text)
{
	if(et.col != nil)
		et.col.sort();
}

seqof(w: ref Window, isundo: int): int
{
	# if it's undo, see who changed with us
	if(isundo)
		return w.body.file.seq;
	# if it's redo, see who we'll be sync'ed up with
	return w.body.file.redoseq();
}

undo(et : ref Text, flag1 : int)
{
	i, j: int;
	c: ref Column;
	w: ref Window;
	seq: int;

	if(et==nil || et.w== nil)
		return;
	seq = seqof(et.w, flag1);
	for(i=0; i<row.ncol; i++){
		c = row.col[i];
		for(j=0; j<c.nw; j++){
			w = c.w[j];
			if(seqof(w, flag1) == seq)
				w.undo(flag1);
		}
	}
	# et.w.undo(flag1);
}

getname(t : ref Text, argt : ref Text, arg : string, narg : int, isput : int) : string
{
	r, dir : string;
	i, n, ndir, promote : int;

	(nil, r, n) = getarg(argt, FALSE, TRUE);
	promote = FALSE;
	if(r == nil)
		promote = TRUE;
	else if(isput){
		# if are doing a Put, want to synthesize name even for non-existent file 
		# best guess is that file name doesn't contain a slash 
		promote = TRUE;
		for(i=0; i<n; i++)
			if(r[i] == '/'){
				promote = FALSE;
				break;
			}
		if(promote){
			t = argt;
			arg = r;
			narg = n;
		}
	}
	if(promote){
		n = narg;
		if(n <= 0)
			return t.file.name;
		# prefix with directory name if necessary 
		dir = nil;
		ndir = 0;
		if(n>0 && arg[0]!='/'){
			(dir, ndir) = dirname(t, nil, 0);
			if(n==1 && dir[0]=='.'){	# sigh 
				dir = nil;
				ndir = 0;
			}
		}
		if(dir != nil){
			r = dir[0:ndir] + arg[0:n];
			dir = nil;
			n += ndir;
		}else
			r = arg[0:n];
	}
	return r;
}

zerox(et : ref Text, t : ref Text)
{
	nw : ref Window;
	c, locked : int;

	locked = FALSE;
	if(t!=nil && t.w!=nil && t.w!=et.w){
		locked = TRUE;
		c = 'M';
		if(et.w != nil)
			c = et.w.owner;
		t.w.lock(c);
	}
	if(t == nil)
		t = et;
	if(t==nil || t.w==nil)
		return;
	t = t.w.body;
	if(t.w.isdir)
		warning(nil, sprint("%s is a directory; Zerox illegal\n", t.file.name));
	else{
		nw = t.w.col.add(nil, t.w, -1);
		# ugly: fix locks so w.unlock works 
		nw.lock1(t.w.owner);
	}
	if(locked)
		t.w.unlock();
}

get(et : ref Text, t : ref Text, argt : ref Text, flag1 : int, arg : string, narg : int)
{
	name : string;
	r : string;
	i, n, dirty : int;
	w : ref Window;
	u : ref Text;
	d : Dir;
	ok : int;

	if(flag1)
		if(et==nil || et.w==nil)
			return;
	if(!et.w.isdir && (et.w.body.file.buf.nc>0 && !et.w.clean(TRUE, FALSE)))
		return;
	w = et.w;
	t = w.body;
	name = getname(t, argt, arg, narg, FALSE);
	if(name == nil){
		warning(nil, "no file name\n");
		return;
	}
	if(t.file.ntext>1){
		(ok, d) = sys->stat(name);
		if (ok == 0 && d.qid.qtype & Sys->QTDIR) {
			warning(nil, sprint("%s is a directory; can't read with multiple windows on it\n", name));
			return;
		}
	}
	r = name;
	n = len name;
	for(i=0; i<t.file.ntext; i++){
		u = t.file.text[i];
		# second and subsequent calls with zero an already empty buffer, but OK 
		u.reset();
		u.w.dirfree();
	}
	samename := r[0:n] == t.file.name;
	t.loadx(0, name, samename);
	if(samename){
		t.file.mod = FALSE;
		dirty = FALSE;
	}else{
		t.file.mod = TRUE;
		dirty = TRUE;
	}
	for(i=0; i<t.file.ntext; i++)
		t.file.text[i].w.dirty = dirty;
	name = nil;
	r = nil;
	w.settag();
	t.file.unread = FALSE;
	for(i=0; i<t.file.ntext; i++){
		u = t.file.text[i];
		u.w.tag.setselect(u.w.tag.file.buf.nc, u.w.tag.file.buf.nc);
		scrl->scrdraw(u);
	}
}

putfile(f: ref File, q0: int, q1: int, name: string)
{
	n : int;
	r, s : ref Astring;
	w : ref Window;
	i, q : int;
	fd : ref Sys->FD;
	d : Dir;
	ok : int;

	w = f.curtext.w;
	
	{
		if(name == f.name){
			(ok, d) = sys->stat(name);
			if(ok >= 0 && (f.dev!=d.dev || f.qidpath!=d.qid.path || f.mtime<d.mtime)){
				f.dev = d.dev;
				f.qidpath = d.qid.path;
				f.mtime = d.mtime;
				if(f.unread)
					warning(nil, sys->sprint("%s not written; file already exists\n", name));
				else
					warning(nil, sys->sprint("%s modified since last read\n", name));
				raise "e";
			}
		}
		fd = sys->create(name, OWRITE, 8r664);	# was 666
		if(fd == nil){
			warning(nil, sprint("can't create file %s: %r\n", name));
			raise "e";
		}
		r = stralloc(BUFSIZE);
		s = stralloc(BUFSIZE);
		
		{
			(ok, d) = sys->fstat(fd);
			if(ok>=0 && (d.mode&Sys->DMAPPEND) && d.length>big 0){
				warning(nil, sprint("%s not written; file is append only\n", name));
				raise "e";
			}
			for(q = q0; q < q1; q += n){
				n = q1 - q;
				if(n > BUFSIZE)
					n = BUFSIZE;
				f.buf.read(q, r, 0, n);
				ab := array of byte r.s[0:n];
				if(sys->write(fd, ab, len ab) != len ab){
					ab = nil;
					warning(nil, sprint("can't write file %s: %r\n", name));
					raise "e";
				}
				ab = nil;
			}
			if(name == f.name){
				d0 : Dir;
		
				if(q0 != 0 || q1 != f.buf.nc){
					f.mod = TRUE;
					w.dirty = TRUE;
					f.unread = TRUE;
				}
				else{
					(ok, d0) = sys->fstat(fd);	# use old values if we failed
					if (ok >= 0)
						d = d0;
					f.qidpath = d.qid.path;
					f.dev = d.dev;
					f.mtime = d.mtime;
					f.mod = FALSE;
					w.dirty = FALSE;
					f.unread = FALSE;
				}
				for(i=0; i<f.ntext; i++){
					f.text[i].w.putseq = f.seq;
					f.text[i].w.dirty = w.dirty;
				}
			}
			strfree(s);
			strfree(r);
			s = r = nil;
			name = nil;
			fd = nil;
			w.settag();
		}
		exception{
			* =>
				strfree(s);
				strfree(r);
				s = r = nil;
				fd = nil;
				raise "e";
		}
	}
	exception{
		* =>
			name = nil;
			return;
	}
}

put(et : ref Text, argt : ref Text, arg : string, narg : int)
{
	namer : string;
	name : string;
	w : ref Window;

	if(et==nil || et.w==nil || et.w.isdir)
		return;
	w = et.w;
	f := w.body.file;
	
	name = getname(w.body, argt, arg, narg, TRUE);
	if(name == nil){
		warning(nil, "no file name\n");
		return;
	}
	namer = name;
	putfile(f, 0, f.buf.nc, namer);
	name = nil;
}

dump(argt : ref Text, isdump : int, arg : string, narg : int)
{
	name : string;

	if(narg)
		name = arg;
	else
		(nil, name) = getbytearg(argt, FALSE, TRUE);
	if(isdump)
		row.dump(name);
	else {
		if (!row.qlock.locked())
			error("row not locked in dump()");
		row.loadx(name, FALSE);
	}
	name = nil;
}

cut(et : ref Text, t : ref Text, dosnarf : int, docut : int)
{
	q0, q1, n, locked, c : int;
	r : ref Astring;

	# use current window if snarfing and its selection is non-null 
	if(et!=t && dosnarf && et.w!=nil){
		if(et.w.body.q1>et.w.body.q0){
			t = et.w.body;
			t.file.mark();	# seq has been incremented by execute
		}
		else if(et.w.tag.q1>et.w.tag.q0)
			t = et.w.tag;
	}
	if(t == nil)
		return;
	locked = FALSE;
	if(t.w!=nil && et.w!=t.w){
		locked = TRUE;
		c = 'M';
		if(et.w != nil)
			c = et.w.owner;
		t.w.lock(c);
	}
	if(t.q0 == t.q1){
		if(locked)
			t.w.unlock();
		return;
	}
	if(dosnarf){
		q0 = t.q0;
		q1 = t.q1;
		snarfbuf.delete(0, snarfbuf.nc);
		r = stralloc(BUFSIZE);
		while(q0 < q1){
			n = q1 - q0;
			if(n > BUFSIZE)
				n = BUFSIZE;
			t.file.buf.read(q0, r, 0, n);
			snarfbuf.insert(snarfbuf.nc, r.s, n);
			q0 += n;
		}
		strfree(r);
		r = nil;
		acme->putsnarf();
	}
	if(docut){
		t.delete(t.q0, t.q1, TRUE);
		t.setselect(t.q0, t.q0);
		if(t.w != nil){
			scrl->scrdraw(t);
			t.w.settag();
		}
	}else if(dosnarf)	# Snarf command 
		dat->argtext = t;
	if(locked)
		t.w.unlock();
}

paste(et : ref Text, t : ref Text, selectall : int, tobody: int)
{
	c : int;
	q, q0, q1, n : int;
	r : ref Astring;

	# if(tobody), use body of executing window  (Paste or Send command)
	if(tobody && et!=nil && et.w!=nil){
		t = et.w.body;
		t.file.mark();	# seq has been incremented by execute
	}
	if(t == nil)
		return;

	acme->getsnarf();
	if(t==nil || snarfbuf.nc==0)
		return;
	if(t.w!=nil && et.w!=t.w){
		c = 'M';
		if(et.w != nil)
			c = et.w.owner;
		t.w.lock(c);
	}
	cut(t, t, FALSE, TRUE);
	q = 0;
	q0 = t.q0;
	q1 = t.q0+snarfbuf.nc;
	r = stralloc(BUFSIZE);
	while(q0 < q1){
		n = q1 - q0;
		if(n > BUFSIZE)
			n = BUFSIZE;
		if(r == nil)
			r = stralloc(n);
		snarfbuf.read(q, r, 0, n);
		t.insert(q0, r.s, n, TRUE, 0);
		q += n;
		q0 += n;
	}
	strfree(r);
	r = nil;
	if(selectall)
		t.setselect(t.q0, q1);
	else
		t.setselect(q1, q1);
	if(t.w != nil){
		scrl->scrdraw(t);
		t.w.settag();
	}
	if(t.w!=nil && et.w!=t.w)
		t.w.unlock();
}

look(et : ref Text, t : ref Text, argt : ref Text)
{
	r : string;
	s : ref Astring;
	n : int;

	if(et != nil && et.w != nil){
		t = et.w.body;
		(nil, r, n) = getarg(argt, FALSE, FALSE);
		if(r == nil){
			n = t.q1-t.q0;
			s = stralloc(n);
			t.file.buf.read(t.q0, s, 0, n);
			r = s.s;
		}
		lookx->search(t, r, n);
		r = nil;
	}
}

send(et : ref Text, t : ref Text)
{
	if(et.w==nil)
		return;
	t = et.w.body;
	if(t.q0 != t.q1)
		cut(t, t, TRUE, FALSE);
	t.setselect(t.file.buf.nc, t.file.buf.nc);
	paste(t, t, TRUE, TRUE);
	if(t.readc(t.file.buf.nc-1) != '\n'){
		t.insert(t.file.buf.nc, "\n", 1, TRUE, 0);
		t.setselect(t.file.buf.nc, t.file.buf.nc);
	}
}

edit(et: ref Text, argt: ref Text, arg: string, narg: int)
{
	r: string;
	leng: int;

	if(et == nil)
		return;
	(nil, r, leng) = getarg(argt, FALSE, TRUE);
	seq++;
	if(r != nil){
		editm->editcmd(et, r, leng);
		r = nil;
	}else
		editm->editcmd(et, arg, narg);
}

exitx()
{
	if(row.clean(TRUE))
		acme->acmeexit(nil);
}

putall()
{
	i, j, e : int;
	w : ref Window;
	c : ref Column;
	a : string;

	for(i=0; i<row.ncol; i++){
		c = row.col[i];
		for(j=0; j<c.nw; j++){
			w = c.w[j];
			if(w.isscratch || w.isdir || len w.body.file.name==0)
				continue;
			if(w.nopen[QWevent] > byte 0)
				continue;
			a = w.body.file.name;
			e = utils->access(a);
			if(w.body.file.mod || w.body.ncache)
				if(e < 0)
					warning(nil, sprint("no auto-Put of %s: %r\n", a));
				else{
					w.commit(w.body);
					put(w.body, nil, nil, 0);
				}
			a = nil;
		}
	}
}

id(et : ref Text)
{
	if(et != nil && et.w != nil)
		warning(nil, sprint("/mnt/acme/%d/\n", et.w.id));
}

limbo(et: ref Text)
{
	s := getname(et.w.body, nil, nil, 0, 0);
	if(s == nil)
		return;
	for(l := len s; l > 0 && s[--l] != '/'; )
		;
	if(s[l] == '/')
		s = s[l+1: ];
	s = "limbo -gw " + s;
	(dir, n) := dirname(et, nil, 0);
	if(n==1 && dir[0]=='.'){	# sigh 
		dir = nil;
		n = 0;
	}
	spawn run(nil, s, dir, n, TRUE, nil, nil, FALSE);
}

local(et : ref Text, argt : ref Text, arg : string)
{
	a, aa : string;
	dir : string;
	n : int;

	(aa, a) = getbytearg(argt, TRUE, TRUE);

	(dir, n) = dirname(et, nil, 0);
	if(n==1 && dir[0]=='.'){	# sigh 
		dir = nil;
		n = 0;
	}
	spawn run(nil, arg, dir, n, FALSE, aa, a, FALSE);
}

kill(argt : ref Text, arg : string, narg : int)
{
	a, cmd, r : string;
	na : int;

	(nil, r, na) = getarg(argt, FALSE, FALSE);
	if(r != nil)
		kill(nil, r, na);
	# loop condition: *arg is not a blank 
	for(;;){
		(a, na) = findbl(arg, narg);
		if(a == arg)
			break;
		cmd = arg[0:narg-na];
		dat->ckill <-= cmd;
		(arg, narg) = skipbl(a, na);
	}
}

lineno(et : ref Text)
{
	n : int;

	if (et == nil || et.w == nil || (et = et.w.body) == nil)
		return;
	q0 := et.q0;
	q1 := et.q1;
	if (q0 < 0 || q1 < 0 || q0 > q1)
		return;
	ln0 := 1;
	ln1 := 1;
	rp := stralloc(BUFSIZE);
	nc := et.file.buf.nc;
	if (q0 >= nc)
		q0 = nc-1;
	if (q1 >= nc)
		q1 = nc-1;
	for (q := 0; q < q1; ) {
		if (q+BUFSIZE > nc)
			n = nc-q;
		else
			n = BUFSIZE;
		et.file.buf.read(q, rp, 0, n);
		for (i := 0; i < n && q < q1; i++) {
			if (rp.s[i] == '\n') {
				if (q < q0)
					ln0++;
				if (q < q1-1)
					ln1++;
			}
			q++;
		}
	}
	rp = nil;
	if (et.file.name != nil)
		file := et.file.name + ":";
	else
		file = nil;
	if (ln0 == ln1)
		warning(nil, sprint("%s%d\n", file, ln0));
	else
		warning(nil, sprint("%s%d,%d\n", file, ln0, ln1));
}

fontx(et : ref Text, t : ref Text, argt : ref Text, arg : string, narg : int)
{
	a, r, flag, file : string;
	na, nf : int;
	aa : string;
	newfont : ref Reffont;
	dp : ref Dat->Dirlist;
	i, fix : int;

	if(et==nil || et.w==nil)
		return;
	t = et.w.body;
	flag = nil;
	file = nil;
	# loop condition: *arg is not a blank 
	nf = 0;
	for(;;){
		(a, na) = findbl(arg, narg);
		if(a == arg)
			break;
		r = arg[0:narg-na];
		if(r == "fix" || r == "var"){
			flag = nil;
			flag = r;
		}else{
			file = r;
			nf = narg-na;
		}
		(arg, narg) = skipbl(a, na);
	}
	(nil, r, na) = getarg(argt, FALSE, TRUE);
	if(r != nil)
		if(r == "fix" || r == "var"){
			flag = nil;
			flag = r;
		}else{
			file = r;
			nf = na;
		}
	fix = 1;
	if(flag != nil)
		fix = flag == "fix";
	else if(file == nil){
		newfont = Reffont.get(FALSE, FALSE, FALSE, nil);
		if(newfont != nil)
			fix = newfont.f.name == t.frame.font.name;
	}
	if(file != nil){
		aa = file[0:nf];
		newfont = Reffont.get(fix, flag!=nil, FALSE, aa);
		aa = nil;
	}else
		newfont = Reffont.get(fix, FALSE, FALSE, nil);
	if(newfont != nil){
		graph->draw(gui->mainwin, t.w.r, acme->textcols[Framem->BACK], nil, (0, 0));
		t.reffont.close();
		t.reffont = newfont;
		t.frame.font = newfont.f;
		if(t.w.isdir){
			t.all.min.x++;	# force recolumnation; disgusting! 
			for(i=0; i<t.w.ndl; i++){
				dp = t.w.dlp[i];
				aa = dp.r;
				dp.wid = graph->strwidth(newfont.f, aa);
				aa = nil;
			}
		}
		# avoid shrinking of window due to quantization 
		t.w.col.grow(t.w, -1, 1);
	}
	file = nil;
	flag = nil;
}

incl(et : ref Text, argt : ref Text, arg : string, narg : int)
{
	a, r : string;
	w : ref Window;
	na, n, leng : int;

	if(et==nil || et.w==nil)
		return;
	w = et.w;
	n = 0;
	(nil, r, leng) = getarg(argt, FALSE, TRUE);
	if(r != nil){
		n++;
		w.addincl(r, leng);
	}
	# loop condition: *arg is not a blank 
	for(;;){
		(a, na) = findbl(arg, narg);
		if(a == arg)
			break;
		r = arg[0:narg-na];
		n++;
		w.addincl(r, narg-na);
		(arg, narg) = skipbl(a, na);
	}
	if(n==0 && w.nincl){
		for(n=w.nincl; --n>=0; )
			warning(nil, sprint("%s ", w.incl[n]));
		warning(nil, "\n");
	}
}

tab(et : ref Text, argt : ref Text, arg : string, narg : int)
{
	a, r, p : string;
	w : ref Window;
	na, leng, tab : int;

	if(et==nil || et.w==nil)
		return;
	w = et.w;
	(nil, r, leng) = getarg(argt, FALSE, TRUE);
	tab = 0;
	if(r!=nil && leng>0){
		p = r[0:leng];
		if('0'<=p[0] && p[0]<='9')
			tab = int p;
		p = nil;
	}else{
		(a, na) = findbl(arg, narg);
		if(a != arg){
			p = arg[0:narg-na];
			if('0'<=p[0] && p[0]<='9')
				tab = int p;
			p = nil;
		}
	}
	if(tab > 0){
		if(w.body.tabstop != tab){
			w.body.tabstop = tab;
			w.reshape(w.r, 1);
		}
	}else
		warning(nil, sys->sprint("%s: Tab %d\n", w.body.file.name, w.body.tabstop));
}

alphabet(et: ref Text, argt: ref Text, arg: string, narg: int)
{
	r: string;
	leng: int;

	if(et == nil)
		return;
	(nil, r, leng) = getarg(argt, FALSE, FALSE);
	if(r != nil)
		setalphabet(r[0:leng]);
	else
		setalphabet(arg[0:narg]);
}

runfeed(p : array of ref Sys->FD, c : chan of int)
{
	n : int;
	buf : array of byte;
	s : string;

	sys->pctl(Sys->FORKFD, nil);
	c <-= 1;
	# p[1] = nil;
	buf = array[256] of byte;
	for(;;){
		if((n = sys->read(p[0], buf, 256)) <= 0)
			break;
		s = string buf[0:n];
		dat->cerr <-= s;
		s = nil;
	}
	buf = nil;
	exit;
}

run(win : ref Window, s : string, rdir : string, ndir : int, newns : int, argaddr : string, arg : string, iseditcmd: int)
{
	c : ref Dat->Command;
	name, dir : string;
	e, t : int;
	av : list of string;
	r : int;
	incl : array of string;
	inarg, i, nincl : int;
	tfd : ref Sys->FD;
	p : array of ref Sys->FD;
	pc : chan of int;
	winid : int;

	c = ref Dat->Command;
	t = 0;
	while(t < len s && (s[t]==' ' || s[t]=='\n' || s[t]=='\t'))
		t++;
	for(e=t; e < len s; e++)
		if(s[e]==' ' || s[e]=='\n' || s[e]=='\t' )
			break;
	name = s[t:e];
	e = utils->strrchr(name, '/');
	if(e >= 0)
		name = name[e+1:];
	name += " ";	# add blank here for ease in waittask 
	c.name = name;
	name = nil;
	pipechar := 0;
	if (t < len s && (s[t] == '<' || s[t] == '|' || s[t] == '>')){
		pipechar = s[t++];
		s = s[t:];
	}
	c.pid = sys->pctl(0, nil);
	c.iseditcmd = iseditcmd;
	c.text = s;
	dat->ccommand <-= c;
	#
	# must pctl() after communication because rendezvous name
	# space is part of RFNAMEG.
	#
	 
	if(newns){
		wids : string = "";
		filename: string;

		if(win != nil){
			filename = win.body.file.name;
			wids = string win.id;
			nincl = win.nincl;
			incl = array[nincl] of string;
			for(i=0; i<nincl; i++)
				incl[i] = win.incl[i];
			winid = win.id;
			win.close();
		}else{
			winid = 0;
			nincl = 0;
			incl = nil;
			if(dat->activewin != nil)
				winid = (dat->activewin).id;
		}
		# sys->pctl(Sys->FORKNS|Sys->FORKFD|Sys->NEWPGRP, nil);
		sys->pctl(Sys->FORKNS|Sys->NEWFD|Sys->FORKENV|Sys->NEWPGRP, 0::1::2::fsys->fsyscfd()::nil);
		if(rdir != nil){
			dir = rdir[0:ndir];
			sys->chdir(dir);	# ignore error: probably app. window 
			dir = nil;
		}
		if(filename != nil)
			utils->setenv("%", filename);
		c.md = fsys->fsysmount(rdir, ndir, incl, nincl);
		if(c.md == nil){
			# error("child: can't mount /mnt/acme");
			warning(nil, "can't mount /mnt/acme");
			exit;
		}
		if(winid > 0 && (pipechar=='|' || pipechar=='>')){
			buf := sys->sprint("/mnt/acme/%d/rdsel", winid);
			tfd = sys->open(buf, OREAD);
		}
		else
			tfd = sys->open("/dev/null", OREAD);
		sys->dup(tfd.fd, 0);
		tfd = nil;
		if((winid > 0 || iseditcmd) && (pipechar=='|' || pipechar=='<')){
			buf: string;

			if(iseditcmd){
				if(winid > 0)
					buf = sprint("/mnt/acme/%d/editout", winid);
				else
 					buf = sprint("/mnt/acme/editout");
			}
			else
				buf = sys->sprint("/mnt/acme/%d/wrsel", winid);
			tfd = sys->open(buf, OWRITE);
		}
		else
			tfd = sys->open("/dev/cons", OWRITE);
		sys->dup(tfd.fd, 1);
		tfd = nil;
		if(winid > 0 && (pipechar=='|' || pipechar=='<')){
			tfd = sys->open("/dev/cons", OWRITE);
			sys->dup(tfd.fd, 2);
		}
		else
			sys->dup(1, 2);
		tfd = nil;
		utils->setenv("acmewin", wids);
	}else{
		if(win != nil)
			win.close();
		sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
		if(rdir != nil){
			dir = rdir[0:ndir];
			sys->chdir(dir);	# ignore error: probably app. window 
			dir = nil;
		}
		p = array[2] of ref Sys->FD;
		if(sys->pipe(p) < 0){
			error("child: can't pipe");
			exit;
		}
		pc = chan of int;
		spawn runfeed(p, pc);
		<-pc;
		pc = nil;
		fsys->fsysclose();
		tfd = sys->open("/dev/null", OREAD);
		sys->dup(tfd.fd, 0);
		tfd = nil;
		sys->dup(p[1].fd, 1);
		sys->dup(1, 2);
		p[0] = p[1] = nil;
	}

	if(argaddr != nil)
		utils->setenv("acmeaddr", argaddr);
	hard := 0;
	if(len s > 512-10)	# may need to print into stack 
		hard = 1;
	else {
		inarg = FALSE;
		for(e=0; e < len s; e++){
			r = s[e];
			if(r==' ' || r=='\t')
				continue;
			if(r < ' ') {
				hard = 1;
				break;
			}
			if(utils->strchr("#;&|^$=`'{}()<>[]*?^~`", r) >= 0) {
				hard = 1;
				break;
			}
			inarg = TRUE;
		}
		if (!hard) {
			if(!inarg)
				exit;
			av = nil;
			sa := -1;
			for(e=0; e < len s; e++){
				r = s[e];
				if(r==' ' || r=='\t'){
					if (sa >= 0) {
						av = s[sa:e] :: av;
						sa = -1;
					}
					continue;
				}
				if (sa < 0)
					sa = e;
			}
			if (sa >= 0)
				av = s[sa:e] :: av;
			if (arg != nil)
				av = arg :: av;
			av = utils->reverse(av);
			c.av = av;
			exec(hd av, av);
			dat->cwait <-= string c.pid + " \"Exec\":";
			exit;
		}
	}

	if(arg != nil){
		s = sprint("%s '%s'", s, arg);	# BUG: what if quote in arg? 
		c.text = s;
	}
	av = nil;
	av = s :: av;
	av = "-c" :: av;
	av = "/dis/sh" :: av;
	exec(hd av, av);
	dat->cwait <-= string c.pid + " \"Exec\":";
	exit;
}

# Nasty bug causes
# Edit ,|nonexistentcommand
# (or ,> or ,<) to lock up acme.  Easy fix.  Add these two lines
# to the failure case of runwaittask():
#
# /sys/src/cmd/acme/exec.c:1287 a exec.c:1288,1289
# else{
# if(c->iseditcmd)
# sendul(cedit, 0);
# free(c->name);
# free(c->text);
# free(c);
# }


