implement Xfidm;

include "common.m";

sys : Sys;
dat : Dat;
graph : Graph;
utils : Utils;
regx : Regx;
bufferm : Bufferm;
diskm : Diskm;
filem : Filem;
textm : Textm;
columnm : Columnm;
scrl : Scroll;
look : Look;
exec : Exec;
windowm : Windowm;
fsys : Fsys;
editm: Edit;
ecmd: Editcmd;
styxaux: Styxaux;

UTFmax : import Sys;
sprint : import sys;
Smsg0 : import Dat;
TRUE, FALSE, XXX, BUFSIZE, MAXRPC : import Dat;
EM_NORMAL, EM_RAW, EM_MASK : import Dat;
Qdir, Qcons, Qlabel, Qindex, Qeditout : import Dat;
QWaddr, QWdata, QWevent, QWconsctl, QWctl, QWbody, QWeditout, QWtag, QWrdsel, QWwrsel : import Dat;
seq, cxfidfree, Lock, Ref, Range, Mntdir, Astring : import dat;
error, warning, max, min, stralloc, strfree, strncmp : import utils;
address : import regx;
Buffer : import bufferm;
File : import filem;
Text : import textm;
scrdraw : import scrl;
Window : import windowm;
bflush : import graph;
Column : import columnm;
row : import dat;
FILE, QID, respond : import fsys;
oldtag, name, offset, count, data, setcount, setdata : import styxaux;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	dat = mods.dat;
	graph = mods.graph;
	utils = mods.utils;
	regx = mods.regx;
	filem = mods.filem;
	bufferm = mods.bufferm;
	diskm = mods.diskm;
	textm = mods.textm;
	columnm = mods.columnm;
	scrl = mods.scroll;
	look = mods.look;
	exec = mods.exec;
	windowm = mods.windowm;
	fsys = mods.fsys;
	editm = mods.edit;
	ecmd = mods.editcmd;
	styxaux = mods.styxaux;
}

nullxfid : Xfid;

newxfid() : ref Xfid
{
	x := ref Xfid;
	*x = nullxfid;
	x.buf = array[fsys->messagesize+UTFmax] of byte;
	return x;
}

Ctlsize : con 5*12;

Edel		:= "deleted window";
Ebadctl	:= "ill-formed control message";
Ebadaddr	:= "bad address syntax";
Eaddr	:= "address out of range";
Einuse	:= "already in use";
Ebadevent:= "bad event syntax";

clampaddr(w : ref Window)
{
	if(w.addr.q0 < 0)
		w.addr.q0 = 0;
	if(w.addr.q1 < 0)
		w.addr.q1 = 0;
	if(w.addr.q0 > w.body.file.buf.nc)
		w.addr.q0 = w.body.file.buf.nc;
	if(w.addr.q1 > w.body.file.buf.nc)
		w.addr.q1 = w.body.file.buf.nc;
}

xfidtid : array of int;
nxfidtid := 0;

xfidkill()
{
	if (sys == nil)
		return;
	thispid := sys->pctl(0, nil);
	for (i := 0; i < nxfidtid; i++)
		utils->postnote(Utils->PNPROC, thispid, xfidtid[i], "kill");
}

Xfid.ctl(x : self ref Xfid)
{
	x.tid = sys->pctl(0, nil);
	ox := xfidtid;
	xfidtid = array[nxfidtid+1] of int;
	xfidtid[0:] = ox[0:nxfidtid];
	xfidtid[nxfidtid++] = x.tid;
	ox = nil;
	for (;;) {
		f := <- x.c;
		case (f) {
			Xnil => ;
			Xflush => x.flush();
			Xwalk => x.walk(nil);
			Xopen => x.open();
			Xclose => x.close();
			Xread => x.read();
			Xwrite => x.write();
			* =>		error("bad case in Xfid.ctl()");
		}
		bflush();
		cxfidfree <-= x;
	}
}
 
Xfid.flush(x : self ref Xfid)
{
	fc : Smsg0;
	i, j : int;
	w : ref Window;
	c : ref Column;
	wx : ref Xfid;

	# search windows for matching tag
	row.qlock.lock();
loop:
	for(j=0; j<row.ncol; j++){
		c = row.col[j];
		for(i=0; i<c.nw; i++){
			w = c.w[i];
			w.lock('E');
			wx = w.eventx;
			if(wx!=nil && wx.fcall.tag==oldtag(x.fcall)){
				w.eventx = nil;
				wx.flushed = TRUE;
				wx.c <-= Xnil;
				w.unlock();
				break loop;
			}
			w.unlock();
		}
	}
	row.qlock.unlock();
	respond(x, fc, nil);
}
 
Xfid.walk(nil : self ref Xfid, cw: chan of ref Window)
{
	# fc : Smsg0;
	w : ref Window;

	# if(name(x.fcall) != "new")
	#	error("unknown path in walk\n");
	row.qlock.lock();	# tasks->procs now
	w = utils->newwindow(nil);
	w.settag();
	# w.refx.inc();
	# x.f.w = w;
	# x.f.qid.path = big QID(w.id, Qdir);
	# x.f.qid.qtype = Sys->QTDIR;
	# fc.qid = x.f.qid;
	row.qlock.unlock();
	# respond(x, fc, nil);
	cw <-= w;
}
 
Xfid.open(x : self ref Xfid)
{
	fc : Smsg0;
	w : ref Window;
	q : int;

	fc.iounit = 0;
	w = x.f.w;
	if(w != nil){
		t := w.body;
		row.qlock.lock();	# tasks->procs now
		w.lock('E');
		q = FILE(x.f.qid);
		case(q){
		QWaddr or QWdata or QWevent =>
			if(w.nopen[q]++ == byte 0){
				if(q == QWaddr){
					w.addr = (Range)(0,0);
					w.limit = (Range)(-1,-1);
				}
				if(q==QWevent && !w.isdir && w.col!=nil){
					w.filemenu = FALSE;
					w.settag();
				}
			}
		QWrdsel =>
			#
			# Use a temporary file.
			# A pipe would be the obvious, but we can't afford the
			# broken pipe notification.  Using the code to read QWbody
			# is n², which should probably also be fixed.  Even then,
			# though, we'd need to squirrel away the data in case it's
			# modified during the operation, e.g. by |sort
			#
			if(w.rdselfd != nil){
				w.unlock();
				respond(x, fc, Einuse);
				return;
			}
			w.rdselfd = diskm->tempfile();
			if(w.rdselfd == nil){
				w.unlock();
				respond(x, fc, "can't create temp file");
				return;
			}
			w.nopen[q]++;
			q0 := t.q0;
			q1 := t.q1;
			r := utils->stralloc(BUFSIZE);
			while(q0 < q1){
				n := q1 - q0;
				if(n > BUFSIZE)
					n = BUFSIZE;
				t.file.buf.read(q0, r, 0, n);
				s := array of byte r.s[0:n];
				m := len s;
				if(sys->write(w.rdselfd, s, m) != m){
					warning(nil, "can't write temp file for pipe command %r\n");
					break;
				}
				s = nil;
				q0 += n;
			}
			utils->strfree(r);
		QWwrsel =>
			w.nopen[q]++;
			seq++;
			t.file.mark();
			exec->cut(t, t, FALSE, TRUE);
			w.wrselrange = (Range)(t.q1, t.q1);
			w.nomark = TRUE;
		QWeditout =>
			if(editm->editing == FALSE){
				w.unlock();
				respond(x, fc, "permission denied");
				return;
			}
			w.wrselrange = (Range)(t.q1, t.q1);
			break;
		}
		w.unlock();
		row.qlock.unlock();
	}
	fc.qid = x.f.qid;
	fc.iounit = fsys->messagesize-Styx->IOHDRSZ;
	x.f.open = TRUE;
	respond(x, fc, nil);
}
 
Xfid.close(x : self ref Xfid)
{
	fc : Smsg0;
	w : ref Window;
	q : int;

	w = x.f.w;
	# BUG in C version ? fsysclunk() has just set busy, open to FALSE
	# x.f.busy = FALSE;
	# if(!x.f.open){
	#	if(w != nil)
	#		w.close();
	#	respond(x, fc, nil);
	#	return;
	# }
	# x.f.open = FALSE;
	if(w != nil){
		row.qlock.lock();	# tasks->procs now 
		w.lock('E');
		q = FILE(x.f.qid);
		case(q){
		QWctl =>
			if(w.ctlfid!=~0 && w.ctlfid==x.f.fid){
				w.ctlfid = ~0;
				w.ctllock.unlock();
			}
		QWdata or QWaddr or QWevent =>	
			# BUG: do we need to shut down Xfid?
			if (q == QWdata)
				w.nomark = FALSE;
			if(--w.nopen[q] == byte 0){
				if(q == QWdata)
					w.nomark = FALSE;
				if(q==QWevent && !w.isdir && w.col!=nil){
					w.filemenu = TRUE;
					w.settag();
				}
				if(q == QWevent){
					w.dumpstr = nil;
					w.dumpdir = nil;
				}
			}
		QWrdsel =>
			w.rdselfd = nil;
		QWwrsel =>
			w.nomark = FALSE;
			t :=w.body;
			# before: only did this if !w->noscroll, but that didn't seem right in practice
			t.show(min(w.wrselrange.q0, t.file.buf.nc),
				    min(w.wrselrange.q1, t.file.buf.nc), TRUE);
			scrdraw(t);
		QWconsctl=>
			w.echomode = EM_NORMAL;
		}
		w.close();
		w.unlock();
		row.qlock.unlock();
	}
	respond(x, fc, nil);
}
 
Xfid.read(x : self ref Xfid)
{
	fc : Smsg0;
	n, q : int;
	off : int;
	sbuf : string;
	buf : array of byte;
	w : ref Window;

	sbuf = nil;
	q = FILE(x.f.qid);
	w = x.f.w;
	if(w == nil){
		fc.count = 0;
		case(q){
		Qcons or Qlabel =>
			;
		Qindex =>
			x.indexread();
			return;
		* =>
			warning(nil, sprint("unknown qid %d\n", q));
		}
		respond(x, fc, nil);
		return;
	}
	w.lock('F');
	if(w.col == nil){
		w.unlock();
		respond(x, fc, Edel);
		return;
	}
	off = int offset(x.fcall);	
	case(q){
	QWaddr =>
		w.body.commit(TRUE);
		clampaddr(w);
		sbuf = sprint("%11d %11d ", w.addr.q0, w.addr.q1);
	QWbody =>
		x.utfread(w.body, 0, w.body.file.buf.nc, QWbody);
	QWctl =>
		sbuf = w.ctlprint(1);
	QWevent =>
		x.eventread(w);
	QWdata =>
		# BUG: what should happen if q1 > q0?
		if(w.addr.q0 > w.body.file.buf.nc){
			respond(x, fc, Eaddr);
			break;
		}
		w.addr.q0 += x.runeread(w.body, w.addr.q0, w.body.file.buf.nc);
		w.addr.q1 = w.addr.q0;
	QWtag =>
		x.utfread(w.tag, 0, w.tag.file.buf.nc, QWtag);
	QWrdsel =>
		sys->seek(w.rdselfd, big off, 0);
		n = count(x.fcall);
		if(n > BUFSIZE)
			n = BUFSIZE;
		b := array[n] of byte;
		n = sys->read(w.rdselfd, b, n);
		if(n < 0){
			respond(x, fc, "I/O error in temp file");
			break;
		}
		fc.count = n;
		fc.data = b;
		respond(x, fc, nil);
		b = nil;
	* =>
		sbuf = sprint("unknown qid %d in read", q);
		respond(x, fc, sbuf);
		sbuf = nil;
	}
	if (sbuf != nil) {
		buf = array of byte sbuf;
		sbuf = nil;
		n = len buf;
		if(off > n)
			off = n;
		if(off+count(x.fcall) > n)
			setcount(x.fcall, n-off);
		fc.count = count(x.fcall);
		fc.data = buf[off:];
		respond(x, fc, nil);
		buf = nil;
	}
	w.unlock();
}
 
Xfid.write(x : self ref Xfid)
{
	fc  : Smsg0;
	c, cnt, qid, q, nb, nr, eval : int;
	w : ref Window;
	r : string;
	a : Range;
	t : ref Text;
	q0, tq0, tq1 : int;
	md : ref Mntdir;

	qid = FILE(x.f.qid);
	w = x.f.w;
	row.qlock.lock();	# tasks->procs now
	if(w != nil){
		c = 'F';
		if(qid==QWtag || qid==QWbody)
			c = 'E';
		w.lock(c);
		if(w.col == nil){
			w.unlock();
			row.qlock.unlock();
			respond(x, fc, Edel);
			return;
		}
	}
	bodytag := 0;
	case(qid){
	Qcons =>
		md = x.f.mntdir;
		warning(md, string data(x.fcall));
		fc.count = count(x.fcall);
		respond(x, fc, nil);
	QWconsctl =>
		if (w != nil) {
			r = string data(x.fcall);
			if (strncmp(r, "rawon", 5) == 0)
				w.echomode = EM_RAW;
			else if (strncmp(r, "rawoff", 6) == 0)
				w.echomode = EM_NORMAL;
		}
		fc.count = count(x.fcall);
		respond(x, fc, nil);
	Qlabel =>
		fc.count = count(x.fcall);
		respond(x, fc, nil);
	QWaddr =>
		r = string data(x.fcall);
		nr = len r;
		t = w.body;
		w.commit(t);
		(eval, nb, a) = address(x.f.mntdir, t, w.limit, w.addr, nil, r, 0, nr, TRUE);
		r = nil;
		if(nb < nr){
			respond(x, fc, Ebadaddr);
			break;
		}
		if(!eval){
			respond(x, fc, Eaddr);
			break;
		}
		w.addr = a;
		fc.count = count(x.fcall);
		respond(x, fc, nil);
	Qeditout or
	QWeditout =>
		r = string data(x.fcall);
		nr = len r;
		if(w!=nil)
			err := ecmd->edittext(w.body.file, w.wrselrange.q1, r, nr);
		else
			err = ecmd->edittext(nil, 0, r, nr);
		r = nil;
		if(err != nil){
			respond(x, fc, err);
			break;
		}
		fc.count = count(x.fcall);
		respond(x, fc, nil);
		break;
	QWbody or QWwrsel =>
		t = w.body;
		bodytag = 1;
	QWctl =>
		x.ctlwrite(w);
	QWdata =>
		t = w.body;
		w.commit(t);
		if(w.addr.q0>t.file.buf.nc || w.addr.q1>t.file.buf.nc){
			respond(x, fc, Eaddr);
			break;
		}
		nb = sys->utfbytes(data(x.fcall), count(x.fcall));
		r = string data(x.fcall)[0:nb];
		nr = len r;
		if(w.nomark == FALSE){
			seq++;
			t.file.mark();
		}
		q0 = w.addr.q0;
		if(w.addr.q1 > q0){
			t.delete(q0, w.addr.q1, TRUE);
			w.addr.q1 = q0;
		}
		tq0 = t.q0;
		tq1 = t.q1;
		t.insert(q0, r, nr, TRUE, 0);
		if(tq0 >= q0)
			tq0 += nr;
		if(tq1 >= q0)
			tq1 += nr;
		if(!t.w.noscroll)
			t.show(tq0, tq1, TRUE);
		scrdraw(t);
		w.settag();
		r = nil;
		w.addr.q0 += nr;
		w.addr.q1 = w.addr.q0;
		fc.count = count(x.fcall);
		respond(x, fc, nil);
	QWevent =>
		x.eventwrite(w);
	QWtag =>
		t = w.tag;
		bodytag = 1;
	* =>
		r = sprint("unknown qid %d in write", qid);
		respond(x, fc, r);
		r = nil;
	}
	if (bodytag) {
		q = x.f.nrpart;
		cnt = count(x.fcall);
		if(q > 0){
			nd := array[cnt+q] of byte;
			nd[q:] = data(x.fcall)[0:cnt];
			nd[0:] = x.f.rpart[0:q];
			setdata(x.fcall, nd);
			cnt += q;
			x.f.nrpart = 0;
		}
		nb = sys->utfbytes(data(x.fcall), cnt);
		r = string data(x.fcall)[0:nb];
		nr = len r;
		if(nb < cnt){
			x.f.rpart = data(x.fcall)[nb:cnt];
			x.f.nrpart = cnt-nb;
		}
		if(nr > 0){
			t.w.commit(t);
			if(qid == QWwrsel){
				q0 = w.wrselrange.q1;
				if(q0 > t.file.buf.nc)
					q0 = t.file.buf.nc;
			}else
				q0 = t.file.buf.nc;
			if(qid == QWbody || qid == QWwrsel){
				if(!w.nomark){
					seq++;
					t.file.mark();
				}
				(q0, nr) = t.bsinsert(q0, r, nr, TRUE);
				if(qid!=QWwrsel && !t.w.noscroll)
					t.show(q0+nr, q0+nr, TRUE);
				scrdraw(t);
			}else
				t.insert(q0, r, nr, TRUE, 0);
			w.settag();
			if(qid == QWwrsel)
				w.wrselrange.q1 += nr;
			r = nil;
		}
		fc.count = count(x.fcall);
		respond(x, fc, nil);
	}
	if(w != nil)
		w.unlock();
	row.qlock.unlock();
}

Xfid.ctlwrite(x : self ref Xfid, w : ref Window)
{
	fc : Smsg0;
	i, m, n, nb : int;
	r, err, p, pp : string;
	q : int;
	scrdrw, settag : int;
	t : ref Text;

	err = nil;
	scrdrw = FALSE;
	settag = FALSE;
	w.tag.commit(TRUE);
	nb = sys->utfbytes(data(x.fcall), count(x.fcall));
	r = string data(x.fcall)[0:nb];
loop :
	for(n=0; n<len r; n+=m){
		p = r[n:];
		if(strncmp(p, "lock", 4) == 0){	# make window exclusive use
			w.ctllock.lock();
			w.ctlfid = x.f.fid;
			m = 4;
		}else
		if(strncmp(p, "unlock", 6) == 0){	# release exclusive use
			w.ctlfid = ~0;
			w.ctllock.unlock();
			m = 6;
		}else
		if(strncmp(p, "clean", 5) == 0){	# mark window 'clean', seq=0
			t = w.body;
			t.eq0 = ~0;
			t.file.reset();
			t.file.mod = FALSE;
			w.dirty = FALSE;
			settag = TRUE;
			m = 5;
		}else
		if(strncmp(p, "show", 4) == 0){	# show dot
			t = w.body;
			t.show(t.q0, t.q1, TRUE);
			m = 4;
		}else
		if(strncmp(p, "name ", 5) == 0){	# set file name
			pp = p[5:];
			m = 5;
			q = utils->strchr(pp, '\n');
			if(q<=0){
				err = Ebadctl;
				break;
			}
			nm := pp[0:q];
			for(i=0; i<len nm; i++)
				if(nm[i] <= ' '){
					err = "bad character in file name";
					break loop;
				}
			seq++;
			w.body.file.mark();
			w.setname(nm, len nm);
			m += (q+1);
		}else
		if(strncmp(p, "dump ", 5) == 0){	# set dump string
			pp = p[5:];
			m = 5;
			q = utils->strchr(pp, '\n');
			if(q<=0){
				err = Ebadctl;
				break;
			}
			nm := pp[0:q];
			w.dumpstr = nm;
			m += (q+1);
		}else
		if(strncmp(p, "dumpdir ", 8) == 0){	# set dump directory
			pp = p[8:];
			m = 8;
			q = utils->strchr(pp, '\n');
			if(q<=0){
				err = Ebadctl;
				break;
			}
			nm := pp[0:q];
			w.dumpdir = nm;
			m += (q+1);
		}else
		if(strncmp(p, "delete", 6) == 0){	# delete for sure
			w.col.close(w, TRUE);
			m = 6;
		}else
		if(strncmp(p, "del", 3) == 0){	# delete, but check dirty
			if(!w.clean(TRUE, FALSE)){
				err = "file dirty";
				break;
			}
			w.col.close(w, TRUE);
			m = 3;
		}else
		if(strncmp(p, "get", 3) == 0){	# get file
			exec->get(w.body, nil, nil, FALSE, nil, 0);
			m = 3;
		}else
		if(strncmp(p, "put", 3) == 0){	# put file
			exec->put(w.body, nil, nil, 0);
			m = 3;
		}else
		if(strncmp(p, "dot=addr", 8) == 0){	# set dot
			w.body.commit(TRUE);
			clampaddr(w);
			w.body.q0 = w.addr.q0;
			w.body.q1 = w.addr.q1;
			w.body.setselect(w.body.q0, w.body.q1);
			settag = TRUE;
			m = 8;
		}else
		if(strncmp(p, "addr=dot", 8) == 0){	# set addr
			w.addr.q0 = w.body.q0;
			w.addr.q1 = w.body.q1;
			m = 8;
		}else
		if(strncmp(p, "limit=addr", 10) == 0){	# set limit
			w.body.commit(TRUE);
			clampaddr(w);
			w.limit.q0 = w.addr.q0;
			w.limit.q1 = w.addr.q1;
			m = 10;
		}else
		if(strncmp(p, "nomark", 6) == 0){	# turn off automatic marking
			w.nomark = TRUE;
			m = 6;
		}else
		if(strncmp(p, "mark", 4) == 0){	# mark file
			seq++;
			w.body.file.mark();
			settag = TRUE;
			m = 4;
		}else
		if(strncmp(p, "noscroll", 8) == 0){	# turn off automatic scrolling
			w.noscroll = TRUE;
			m = 8;
		}else
		if(strncmp(p, "cleartag", 8) == 0){	# wipe tag right of bar
			w.cleartag();
			settag = TRUE;
			m = 8;
		}else
		if(strncmp(p, "scroll", 6) == 0){	# turn on automatic scrolling (writes to body only)
			w.noscroll = FALSE;
			m = 6;
		}else
		if(strncmp(p, "noecho", 6) == 0){	# don't echo chars - mask them
			w.echomode = EM_MASK;
			m = 6;
		}else
		if (strncmp(p, "echo", 4) == 0){		# echo chars (normal state)
			w.echomode = EM_NORMAL;
			m = 4;
		}else{
			err = Ebadctl;
			break;
		}
		while(m < len p && p[m] == '\n')
			m++;
	}
	
	ab := array of byte r[0:n];
	n = len ab;
	ab = nil;
	r = nil;
	if(err != nil)
		n = 0;
	fc.count = n;
	respond(x, fc, err);
	if(settag)
		w.settag();
	if(scrdrw)
		scrdraw(w.body);
}

Xfid.eventwrite(x : self ref Xfid, w : ref Window)
{
	fc : Smsg0;
	m, n, nb : int;
	r, err : string;
	p, q : int;
	t : ref Text;
	c : int;
	q0, q1 : int;

	err = nil;
	nb = sys->utfbytes(data(x.fcall), count(x.fcall));
	r = string data(x.fcall)[0:nb];
loop :
	for(n=0; n<len r; n+=m){
		p = n;
		w.owner = r[p++];	# disgusting
		c = r[p++];
		while(r[p] == ' ')
			p++;
		q0 = int r[p:];
		q = p;
		if (r[q] == '+' || r[q] == '-')
			q++;
		while (r[q] >= '0' && r[q] <= '9')
			q++;
		if(q == p) {
			err = Ebadevent;
			break;
		}
		p = q;
		while(r[p] == ' ')
			p++;
		q1 = int r[p:];
		q = p;
		if (r[q] == '+' || r[q] == '-')
			q++;
		while (r[q] >= '0' && r[q] <= '9')
			q++;
		if(q == p) {
			err = Ebadevent;
			break;
		}
		p = q;
		while(r[p] == ' ')
			p++;
		if(r[p++] != '\n') {
			err = Ebadevent;
			break;
		}
		m = p-n;
		if('a'<=c && c<='z')
			t = w.tag;
		else if('A'<=c && c<='Z')
			t = w.body;
		else {
			err = Ebadevent;
			break;
		}
		if(q0>t.file.buf.nc || q1>t.file.buf.nc || q0>q1) {
			err = Ebadevent;
			break;
		}
		# row.qlock.lock();
		case(c){
		'x' or 'X' =>
			exec->execute(t, q0, q1, TRUE, nil);
		'l' or 'L' =>
			look->look3(t, q0, q1, TRUE);
		* =>
			err = Ebadevent;
			break loop;
		}
		# row.qlock.unlock();
	}

	ab := array of byte r[0:n];
	n = len ab;
	ab = nil;
	r = nil;
	if(err != nil)
		n = 0;
	fc.count = n;
	respond(x, fc, err);
}

Xfid.utfread(x : self ref Xfid, t : ref Text, q0, q1 : int, qid : int)
{
	fc : Smsg0;
	w : ref Window;
	r : ref Astring;
	b, b1 : array of byte;
	q, off, boff : int;
	m, n, nr, nb : int;

	w = t.w;
	w.commit(t);
	off = int offset(x.fcall);
	r = stralloc(BUFSIZE);
	b1 = array[MAXRPC] of byte;
	n = 0;
	if(qid==w.utflastqid && off>=w.utflastboff && w.utflastq<=q1){
		boff = w.utflastboff;
		q = w.utflastq;
	}else{
		# BUG: stupid code: scan from beginning
		boff = 0;
		q = q0;
	}
	w.utflastqid = qid;
	while(q<q1 && n<count(x.fcall)){
		w.utflastboff = boff;
		w.utflastq = q;
		nr = q1-q;
		if(nr > BUFSIZE)
			nr = BUFSIZE;
		t.file.buf.read(q, r, 0, nr);
		b = array of byte r.s[0:nr];
		nb = len b;
		if(boff >= off){
			m = nb;
			if(boff+m > off+count(x.fcall))
				m = off+count(x.fcall) - boff;
			b1[n:] = b[0:m];
			n += m;
		}else if(boff+nb > off){
			if(n != 0)
				error("bad count in utfrune");
			m = nb - (off-boff);
			if(m > count(x.fcall))
				m = count(x.fcall);
			b1[0:] = b[off-boff:off-boff+m];
			n += m;
		}
		b = nil;
		boff += nb;
		q += nr;
	}
	strfree(r);
	r = nil;
	fc.count = n;
	fc.data = b1;
	respond(x, fc, nil);
	b1 = nil;
}

Xfid.runeread(x : self ref Xfid, t : ref Text, q0, q1 : int) : int
{
	fc : Smsg0;
	w : ref Window;
	r : ref Astring;
	junk, ok : int;
	b, b1 : array of byte;
	q, boff : int;
	i, rw, m, n, nr, nb : int;

	w = t.w;
	w.commit(t);
	r = stralloc(BUFSIZE);
	b1 = array[MAXRPC] of byte;
	n = 0;
	q = q0;
	boff = 0;
	while(q<q1 && n<count(x.fcall)){
		nr = q1-q;
		if(nr > BUFSIZE)
			nr = BUFSIZE;
		t.file.buf.read(q, r, 0, nr);
		b = array of byte r.s[0:nr];
		nb = len b;
		m = nb;
		if(boff+m > count(x.fcall)){
			i = count(x.fcall) - boff;
			# copy whole runes only
			m = 0;
			nr = 0;
			while(m < i){
				(junk, rw, ok) = sys->byte2char(b, m);
				if(m+rw > i)
					break;
				m += rw;
				nr++;
			}
			if(m == 0)
				break;
		}
		b1[n:] = b[0:m];
		b = nil;
		n += m;
		boff += nb;
		q += nr;
	}
	strfree(r);
	r = nil;
	fc.count = n;
	fc.data = b1;
	respond(x, fc, nil);
	b1 = nil;
	return q-q0;
}

Xfid.eventread(x : self ref Xfid, w : ref Window)
{
	fc : Smsg0;
	b : string;
	i, n : int;

	i = 0;
	x.flushed = FALSE;
	while(w.nevents == 0){
		if(i){
			if(!x.flushed)
				respond(x, fc, "window shut down");
			return;
		}
		w.eventx = x;
		w.unlock();
		<- x.c;
		w.lock('F');
		i++;
	}
	eveb := array of byte w.events;
	ne := len eveb;
	n = w.nevents;
	if(ne > count(x.fcall)) {
		ne = count(x.fcall);
		while (sys->utfbytes(eveb, ne) != ne)
			--ne;
		s := string eveb[0:ne];
		n = len s;
		s = nil;
	}
	fc.count = ne;
	fc.data = eveb;
	respond(x, fc, nil);
	b = w.events;
	w.events = w.events[n:];
	b = nil;
	w.nevents -= n;
	eveb = nil;
}

Xfid.indexread(x : self ref Xfid)
{
	fc : Smsg0;
	i, j, m, n, nmax, cnt, off : int;
	w : ref Window;
	b : array of byte;
	r : ref Astring;
	c : ref Column;

	row.qlock.lock();
	nmax = 0;
	for(j=0; j<row.ncol; j++){
		c = row.col[j];
		for(i=0; i<c.nw; i++){
			w = c.w[i];
			nmax += Ctlsize + w.tag.file.buf.nc*UTFmax + 1;
		}
	}
	nmax++;
	b = array[nmax] of byte;
	r = stralloc(BUFSIZE);
	n = 0;
	for(j=0; j<row.ncol; j++){
		c = row.col[j];
		for(i=0; i<c.nw; i++){
			w = c.w[i];
			# only show the currently active window of a set
			if(w.body.file.curtext != w.body)
				continue;
			ctls := w.ctlprint(0);
			ctlb := array of byte ctls;
			if (len ctls != Ctlsize || len ctlb != Ctlsize)
				error("bad length in indexread");
			b[n:] = ctlb[0:];
			n += Ctlsize;
			ctls = nil;
			ctlb = nil;
			m = min(BUFSIZE, w.tag.file.buf.nc);
			w.tag.file.buf.read(0, r, 0, m);
			rb := array of byte r.s[0:m];
			b[n:] = rb[0:len rb];
			m = n+len rb;
			rb = nil;
			while(n<m && b[n]!=byte '\n')
				n++;
			b[n++] = byte '\n';
		}
	}
	row.qlock.unlock();
	off = int offset(x.fcall);
	cnt = count(x.fcall);
	if(off > n)
		off = n;
	if(off+cnt > n)
		cnt = n-off;
	fc.count = cnt;
	fc.data = b[off:off+cnt];
	respond(x, fc, nil);
	b = nil;
	strfree(r);
	r = nil;
}
