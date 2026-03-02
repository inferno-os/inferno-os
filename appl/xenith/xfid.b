implement Xfidm;

include "common.m";

sys : Sys;
drawm : Draw;
dat : Dat;
graph : Graph;
utils : Utils;
regx : Regx;
bufferm : Bufferm;
diskm : Diskm;
filem : Filem;
textm : Textm;
columnm : Columnm;
rowm : Rowm;
scrl : Scroll;
look : Look;
exec : Exec;
windowm : Windowm;
fsys : Fsys;
editm: Edit;
ecmd: Editcmd;
styxaux: Styxaux;
xenith: Xenith;

UTFmax : import Sys;
sprint : import sys;
Rect : import drawm;
Smsg0 : import Dat;
TRUE, FALSE, XXX, BUFSIZE, MAXRPC : import Dat;
EM_NORMAL, EM_RAW, EM_MASK : import Dat;
Qdir, Qcons, Qlabel, Qindex, Qeditout : import Dat;
QWaddr, QWcolors, QWdata, QWevent, QWconsctl, QWctl, QWbody, QWedit, QWeditout, QWimage, QWtag, QWrdsel, QWwrsel : import Dat;
seq, cxfidfree, ccons, Lock, Ref, Range, Mntdir, ConsMsg, Astring : import dat;
error, warning, max, min, stralloc, strfree, strncmp : import utils;
address : import regx;
Buffer : import bufferm;
File : import filem;
Text : import textm;
scrdraw : import scrl;
Window : import windowm;
bflush : import graph;
Column : import columnm;
Row : import rowm;
row : import dat;
FILE, QID, respond : import fsys;
oldtag, name, offset, count, data, setcount, setdata : import styxaux;
tagcols, textcols : import xenith;
BACK, HIGH, BORD, TEXT, HTEXT : import Framem;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	drawm = mods.draw;
	dat = mods.dat;
	graph = mods.graph;
	utils = mods.utils;
	regx = mods.regx;
	filem = mods.filem;
	bufferm = mods.bufferm;
	diskm = mods.diskm;
	textm = mods.textm;
	columnm = mods.columnm;
	rowm = mods.rowm;
	scrl = mods.scroll;
	look = mods.look;
	exec = mods.exec;
	windowm = mods.windowm;
	fsys = mods.fsys;
	editm = mods.edit;
	ecmd = mods.editcmd;
	styxaux = mods.styxaux;
	xenith = mods.xenith;
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

waitproc(pid : int, sync: chan of int)
{
	fd : ref Sys->FD;
	n : int;

	sys->pctl(Sys->FORKFD, nil);
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
		dat->cwait <-= status;
	}
}

Xfid.ctl(x : self ref Xfid)
{
	x.tid = sys->pctl(0, nil);
	sync := chan of int;
	spawn waitproc(x.tid, sync);
	<-sync;
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
 
Xfid.walk(x : self ref Xfid, cw: chan of ref Window)
{
	# fc : Smsg0;
	w : ref Window;

	# if(name(x.fcall) != "new")
	#	error("unknown path in walk\n");
	row.qlock.lock();	# tasks->procs now
	w = utils->newwindow(nil);
	w.settag();
	# Track which mount session created this window
	if(x.f != nil && x.f.mntdir != nil)
		w.creatormnt = x.f.mntdir.id;
	else
		w.creatormnt = 0;
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
		QWaddr =>
			if(w.nopen[q]++ == byte 0){
				w.addr = (Range)(0,0);
				w.limit = (Range)(-1,-1);
			}
		QWdata or QWedit =>
			w.nopen[q]++;
			seq++;
			t.file.mark();
		QWevent =>
			if(w.nopen[q]++ == byte 0)
				if(!w.isdir && w.col!=nil){
					w.filemenu = FALSE;
					w.settag();
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
				row.qlock.unlock();
				respond(x, fc, Einuse);
				return;
			}
			w.rdselfd = diskm->tempfile();
			if(w.rdselfd == nil){
				w.unlock();
				row.qlock.unlock();
				respond(x, fc, "can't create temp file");
				return;
			}
			w.nopen[q]++;
			# Use saved range for Edit pipe commands to avoid race condition.
			# Between runpipe setting t.q0/t.q1 and this open, the selection
			# could be modified by other operations.
			q0, q1 : int;
			if(editm->editing && w.rdselrange.q1 > w.rdselrange.q0){
				q0 = w.rdselrange.q0;
				q1 = w.rdselrange.q1;
			} else {
				q0 = t.q0;
				q1 = t.q1;
			}
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
				row.qlock.unlock();
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
	x.f.busy = FALSE;
	if(x.f.open == FALSE){
		if(w != nil)
			w.close();
		x.f.w = nil;
		respond(x, fc, nil);
		return;
	}
	x.f.open = FALSE;
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
		QWdata or QWaddr or QWedit or QWevent =>	
			# BUG: do we need to shut down Xfid?
			if (q == QWdata || q == QWedit)
				w.nomark = FALSE;
			if(--w.nopen[q] == byte 0){
				if(q == QWdata || q == QWedit)
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
			w.rdselrange = (Range)(0, 0);
		QWwrsel =>
			w.nomark = FALSE;
			t :=w.body;
			# before: only did this if !w->noscroll, but that didn't seem right in practice
			t.show(min(w.wrselrange.q0, t.file.buf.nc),
				    min(w.wrselrange.q1, t.file.buf.nc));
			scrdraw(t);
		QWconsctl=>
			w.echomode = EM_NORMAL;
		}
		w.close();
		w.unlock();
		row.qlock.unlock();
	}
	x.f.w = nil;
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
		if(w.rendermode != 0 && w.contentdata != nil){
			# Serve raw text to 9P clients (AI sees source, not formatted view)
			sbuf = string w.contentdata;
		} else
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
	QWcolors =>
		if(w.colorstr != nil)
			sbuf = w.colorstr;
		else
			sbuf = defaultcolorstr();
	QWimage =>
		if(w.imagemode == 0 || w.bodyimage == nil)
			sbuf = "";
		else
			sbuf = sprint("%s %d %d\n", w.imagepath,
				w.bodyimage.r.dx(), w.bodyimage.r.dy());
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

	qid = FILE(x.f.qid);
	w = x.f.w;

	# Async console writes: queue on ccons and return immediately.
	# Avoids holding row.qlock during potentially heavy concurrent output
	# (e.g. multiple Veltro agents). waittask drains the channel.
	if(qid == Qcons) {
		ccons <-= ref ConsMsg(x.f.mntdir, string data(x.fcall));
		fc.count = count(x.fcall);
		respond(x, fc, nil);
		return;
	}

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
		# Handled above (async path via ccons channel)
		;
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
	QWedit =>
		r = string data(x.fcall);
		nr = len r;
		t = w.body;
		w.commit(t);
		if(w.nomark == FALSE)
			seq++;
		editm->editcmd(t, r, nr);
		r = nil;
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
		if(w.rendermode != 0 && qid == QWbody){
			respond(x, fc, "window in render mode");
			break;
		}
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
			t.show(tq0, tq1);
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
	QWcolors =>
		x.colorswrite(w);
	QWimage =>
		x.imagewrite(w);
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
					t.show(q0+nr, q0+nr);
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

# Helper for ctlwrite: handles lock/unlock, clean, show, name, dump commands
# Returns (handled, m, err, settag) - split to avoid yacc stack overflow
ctlcmd1(x: ref Xfid, w: ref Window, p: string): (int, int, string, int)
{
	m := 0;
	pp: string;
	q, i: int;
	t: ref Text;

	if(strncmp(p, "lock", 4) == 0){	# make window exclusive use
		w.ctllock.lock();
		w.ctlfid = x.f.fid;
		return (TRUE, 4, nil, FALSE);
	}
	if(strncmp(p, "unlock", 6) == 0){	# release exclusive use
		w.ctlfid = ~0;
		w.ctllock.unlock();
		return (TRUE, 6, nil, FALSE);
	}
	if(strncmp(p, "clean", 5) == 0){	# mark window 'clean', seq=0
		t = w.body;
		t.eq0 = ~0;
		t.file.reset();
		t.file.mod = FALSE;
		w.dirty = FALSE;
		return (TRUE, 5, nil, TRUE);
	}
	if(strncmp(p, "show", 4) == 0){	# show dot
		t = w.body;
		t.show(t.q0, t.q1);
		return (TRUE, 4, nil, FALSE);
	}
	if(strncmp(p, "name ", 5) == 0){	# set file name
		pp = p[5:];
		m = 5;
		q = utils->strchr(pp, '\n');
		if(q<=0)
			return (TRUE, 0, Ebadctl, FALSE);
		nm := pp[0:q];
		for(i=0; i<len nm; i++)
			if(nm[i] <= ' ')
				return (TRUE, 0, "bad character in file name", FALSE);
		seq++;
		w.body.file.mark();
		w.setname(nm, len nm);
		return (TRUE, m + q + 1, nil, FALSE);
	}
	if(strncmp(p, "dump ", 5) == 0){	# set dump string
		pp = p[5:];
		m = 5;
		q = utils->strchr(pp, '\n');
		if(q<=0)
			return (TRUE, 0, Ebadctl, FALSE);
		nm := pp[0:q];
		w.dumpstr = nm;
		return (TRUE, m + q + 1, nil, FALSE);
	}
	if(strncmp(p, "dumpdir ", 8) == 0){	# set dump directory
		pp = p[8:];
		m = 8;
		q = utils->strchr(pp, '\n');
		if(q<=0)
			return (TRUE, 0, Ebadctl, FALSE);
		nm := pp[0:q];
		w.dumpdir = nm;
		return (TRUE, m + q + 1, nil, FALSE);
	}
	if(strncmp(p, "delete", 6) == 0){	# delete for sure
		# Protect user-created windows from programmatic deletion
		if(x.f.mntdir != nil && w.creatormnt == 0)
			return (TRUE, 0, "permission denied: user window", FALSE);
		w.col.close(w, TRUE);
		return (TRUE, 6, nil, FALSE);
	}
	if(strncmp(p, "del", 3) == 0){	# delete, but check dirty
		# Protect user-created windows from programmatic deletion
		if(x.f.mntdir != nil && w.creatormnt == 0)
			return (TRUE, 0, "permission denied: user window", FALSE);
		if(!w.clean(TRUE, FALSE))
			return (TRUE, 0, "file dirty", FALSE);
		w.col.close(w, TRUE);
		return (TRUE, 3, nil, FALSE);
	}
	if(strncmp(p, "get", 3) == 0){	# get file
		exec->get(w.body, nil, nil, FALSE, nil, 0);
		return (TRUE, 3, nil, FALSE);
	}
	if(strncmp(p, "put", 3) == 0){	# put file
		exec->put(w.body, nil, nil, 0);
		return (TRUE, 3, nil, FALSE);
	}
	return (FALSE, 0, nil, FALSE);
}

# Helper for ctlwrite: handles addressing and marking commands
ctlcmd2(x: ref Xfid, w: ref Window, p: string): (int, int, string, int)
{
	if(strncmp(p, "dot=addr", 8) == 0){	# set dot
		w.body.commit(TRUE);
		clampaddr(w);
		w.body.q0 = w.addr.q0;
		w.body.q1 = w.addr.q1;
		w.body.setselect(w.body.q0, w.body.q1);
		return (TRUE, 8, nil, TRUE);
	}
	if(strncmp(p, "addr=dot", 8) == 0){	# set addr
		w.addr.q0 = w.body.q0;
		w.addr.q1 = w.body.q1;
		return (TRUE, 8, nil, FALSE);
	}
	if(strncmp(p, "limit=addr", 10) == 0){	# set limit
		w.body.commit(TRUE);
		clampaddr(w);
		w.limit.q0 = w.addr.q0;
		w.limit.q1 = w.addr.q1;
		return (TRUE, 10, nil, FALSE);
	}
	if(strncmp(p, "nomark", 6) == 0){	# turn off automatic marking
		w.nomark = TRUE;
		return (TRUE, 6, nil, FALSE);
	}
	if(strncmp(p, "mark", 4) == 0){	# mark file
		seq++;
		w.body.file.mark();
		return (TRUE, 4, nil, TRUE);
	}
	if(strncmp(p, "noscroll", 8) == 0){	# turn off automatic scrolling
		w.noscroll = TRUE;
		return (TRUE, 8, nil, FALSE);
	}
	if(strncmp(p, "cleartag", 8) == 0){	# wipe tag right of bar
		w.cleartag();
		return (TRUE, 8, nil, TRUE);
	}
	if(strncmp(p, "scroll", 6) == 0){	# turn on automatic scrolling (writes to body only)
		w.noscroll = FALSE;
		return (TRUE, 6, nil, FALSE);
	}
	if(strncmp(p, "noecho", 6) == 0){	# don't echo chars - mask them
		w.echomode = EM_MASK;
		return (TRUE, 6, nil, FALSE);
	}
	if(strncmp(p, "echo", 4) == 0){		# echo chars (normal state)
		w.echomode = EM_NORMAL;
		return (TRUE, 4, nil, FALSE);
	}
	return (FALSE, 0, nil, FALSE);
}

# Helper for ctlwrite: handles image and layout commands
ctlcmd3(x: ref Xfid, w: ref Window, p: string): (int, int, string, int)
{
	m: int;
	pp: string;
	q: int;

	if(strncmp(p, "image ", 6) == 0){	# load and display image
		pp = p[6:];
		m = 6;
		q = utils->strchr(pp, '\n');
		if(q <= 0)
			return (TRUE, 0, Ebadctl, FALSE);
		path := pp[0:q];
		err := w.loadimage(path);
		if(err != nil)
			return (TRUE, 0, err, FALSE);
		return (TRUE, m + q + 1, nil, FALSE);
	}
	if(strncmp(p, "clearimage", 10) == 0){	# return to text mode
		w.clearimage();
		return (TRUE, 10, nil, FALSE);
	}
	if(strncmp(p, "content ", 8) == 0){	# load and render content (renderer pipeline)
		pp = p[8:];
		m = 8;
		q = utils->strchr(pp, '\n');
		if(q <= 0)
			return (TRUE, 0, Ebadctl, FALSE);
		path := pp[0:q];
		err := w.loadcontent(path);
		if(err != nil)
			return (TRUE, 0, err, FALSE);
		return (TRUE, m + q + 1, nil, FALSE);
	}
	if(strncmp(p, "clearcontent", 12) == 0){	# return to text mode (alias)
		w.clearimage();
		return (TRUE, 12, nil, FALSE);
	}
	if(strncmp(p, "contentcmd ", 11) == 0){	# execute renderer command
		pp = p[11:];
		m = 11;
		q = utils->strchr(pp, '\n');
		if(q < 0)
			q = len pp;
		cmdstr := pp[0:q];
		# Parse "command arg" or just "command"
		sp := utils->strchr(cmdstr, ' ');
		cmd: string;
		arg: string;
		if(sp > 0){
			cmd = cmdstr[0:sp];
			arg = cmdstr[sp+1:];
		} else {
			cmd = cmdstr;
			arg = nil;
		}
		err := w.contentcommand(cmd, arg);
		if(err != nil)
			return (TRUE, 0, err, FALSE);
		return (TRUE, m + q + 1, nil, FALSE);
	}
	if(strncmp(p, "growfull", 8) == 0){	# full column (hides other windows)
		if(w.col != nil)
			w.col.grow(w, 3, 0);
		return (TRUE, 8, nil, FALSE);
	}
	if(strncmp(p, "growmax", 7) == 0){	# maximum size within column
		if(w.col != nil)
			w.col.grow(w, 2, 0);
		return (TRUE, 7, nil, FALSE);
	}
	if(strncmp(p, "grow", 4) == 0){	# moderate growth
		if(w.col != nil)
			w.col.grow(w, 1, 0);
		return (TRUE, 4, nil, FALSE);
	}
	if(strncmp(p, "moveto ", 7) == 0){	# move window to Y position in column
		pp = p[7:];
		m = 7;
		q = utils->strchr(pp, '\n');
		if(q < 0)
			q = len pp;
		if(q <= 0)
			return (TRUE, 0, Ebadctl, FALSE);
		ystr := pp[0:q];
		y := int ystr;
		if(w.col != nil){
			w.col.close(w, FALSE);
			w.col.add(w, nil, y);
		}
		m += q;
		if(q < len pp && pp[q] == '\n')
			m++;
		return (TRUE, m, nil, FALSE);
	}
	if(strncmp(p, "tocol ", 6) == 0){	# move to different column
		pp = p[6:];
		m = 6;
		q = utils->strchr(pp, '\n');
		if(q < 0)
			q = len pp;
		if(q <= 0)
			return (TRUE, 0, Ebadctl, FALSE);
		args := pp[0:q];
		colstr := args;
		yval := -1;
		sp := utils->strchr(args, ' ');
		if(sp > 0){
			colstr = args[0:sp];
			yval = int args[sp+1:];
		}
		colidx := int colstr;
		if(colidx < 0 || colidx >= row.ncol)
			return (TRUE, 0, "invalid column index", FALSE);
		if(w.col != nil){
			oldcol := w.col;
			newcol := row.col[colidx];
			if(newcol != oldcol){
				oldcol.close(w, FALSE);
				newcol.add(w, nil, yval);
			}
		}
		m += q;
		if(q < len pp && pp[q] == '\n')
			m++;
		return (TRUE, m, nil, FALSE);
	}
	if(strncmp(p, "newcol", 6) == 0){	# create new column
		xpos := -1;
		if(len p > 7 && p[6] == ' '){
			pp = p[7:];
			m = 7;
			q = utils->strchr(pp, '\n');
			if(q < 0)
				q = len pp;
			if(q > 0)
				xpos = int pp[0:q];
			m += q;
			if(q < len pp && pp[q] == '\n')
				m++;
		}else{
			m = 6;
		}
		row.add(nil, xpos);
		return (TRUE, m, nil, FALSE);
	}
	return (FALSE, 0, nil, FALSE);
}

Xfid.ctlwrite(x : self ref Xfid, w : ref Window)
{
	fc : Smsg0;
	m, n, nb : int;
	r, err, p : string;
	scrdrw, settag : int;
	handled, settag2 : int;

	err = nil;
	scrdrw = FALSE;
	settag = FALSE;
	w.tag.commit(TRUE);
	nb = sys->utfbytes(data(x.fcall), count(x.fcall));
	r = string data(x.fcall)[0:nb];
	for(n=0; n<len r; n+=m){
		p = r[n:];
		# Try each command group in turn
		(handled, m, err, settag2) = ctlcmd1(x, w, p);
		if(err != nil)
			break;
		if(handled){
			if(settag2) settag = TRUE;
		}else{
			(handled, m, err, settag2) = ctlcmd2(x, w, p);
			if(err != nil)
				break;
			if(handled){
				if(settag2) settag = TRUE;
			}else{
				(handled, m, err, settag2) = ctlcmd3(x, w, p);
				if(err != nil)
					break;
				if(handled){
					if(settag2) settag = TRUE;
				}else{
					err = Ebadctl;
					break;
				}
			}
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
# locked by parent otherwise we deadlock
#		row.qlock.lock();
		{
			case(c){
			'x' or 'X' =>
				exec->execute(t, q0, q1, TRUE, nil);
			'l' or 'L' =>
				look->look3(t, q0, q1, TRUE);
			* =>
				err = Ebadevent;
				break loop;
			}
		}
		exception{
			* =>
				warning(nil, "event handler: " + utils->getexc() + "\n");
		}
#		row.qlock.unlock();
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

# Return a string representation of the default theme colors
# Since Images don't expose RGB values directly, we return
# an indicator that defaults are being used
defaultcolorstr(): string
{
	return "# using default theme\n";
}

# Validate color format - simple check for key-value pairs
validcolorstr(s: string): int
{
	if(s == nil || len s == 0)
		return FALSE;

	i := 0;
	while(i < len s){
		# Skip whitespace
		while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n'))
			i++;
		if(i >= len s)
			break;

		# Skip comments
		if(s[i] == '#'){
			while(i < len s && s[i] != '\n')
				i++;
			continue;
		}

		# Find key
		j := i;
		while(j < len s && s[j] != ' ' && s[j] != '\t' && s[j] != '\n')
			j++;
		if(j == i)
			return FALSE;
		key := s[i:j];

		# Check for valid key
		validkey := 0;
		case key {
		"tagbg" or "tagfg" or "taghbg" or "taghfg" or "tagbord" or
		"bodybg" or "bodyfg" or "bodyhbg" or "bodyhfg" or "bord" =>
			validkey = 1;
		}
		if(!validkey)
			return FALSE;

		# Skip whitespace
		i = j;
		while(i < len s && (s[i] == ' ' || s[i] == '\t'))
			i++;

		# Find value (should be hex color)
		j = i;
		while(j < len s && s[j] != ' ' && s[j] != '\t' && s[j] != '\n')
			j++;
		if(j == i)
			return FALSE;
		# Value exists; move to next line
		i = j;
	}

	return TRUE;
}

# Extract key (first word) from a color setting line
extractcolorkey(s: string): string
{
	# Skip leading whitespace
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n'))
		i++;
	# Extract key until whitespace
	start := i;
	while(i < len s && s[i] != ' ' && s[i] != '\t' && s[i] != '\n')
		i++;
	if(i > start)
		return s[start:i];
	return "";
}

# Split colorstr into lines
splitcolorlines(s: string): list of string
{
	result: list of string;
	start := 0;
	for(i := 0; i <= len s; i++) {
		if(i == len s || s[i] == '\n') {
			if(i > start)
				result = s[start:i] :: result;
			start = i + 1;
		}
	}
	# Reverse the list
	rev: list of string;
	for(; result != nil; result = tl result)
		rev = hd result :: rev;
	return rev;
}

# Merge new color setting into existing colorstr
# Returns merged string with new value updating or adding to existing
mergecolorstr(existing, newval: string): string
{
	# Skip leading/trailing whitespace from newval
	i := 0;
	while(i < len newval && (newval[i] == ' ' || newval[i] == '\t' || newval[i] == '\n'))
		i++;
	j := len newval;
	while(j > i && (newval[j-1] == ' ' || newval[j-1] == '\t' || newval[j-1] == '\n'))
		j--;
	if(j <= i)
		return existing;
	newval = newval[i:j];

	newkey := extractcolorkey(newval);
	if(newkey == "")
		return existing;

	if(existing == nil || len existing == 0)
		return newval;

	# Parse existing into lines, replace matching key or append
	result := "";
	found := 0;
	lines := splitcolorlines(existing);
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		# Skip empty lines and comments
		linekey := extractcolorkey(line);
		if(linekey == "" || linekey[0] == '#')
			continue;

		if(linekey == newkey) {
			# Replace with new value
			if(len result > 0)
				result += "\n";
			result += newval;
			found = 1;
		} else {
			# Keep existing
			if(len result > 0)
				result += "\n";
			result += line;
		}
	}

	if(!found) {
		if(len result > 0)
			result += "\n";
		result += newval;
	}

	return result;
}

# Write handler for colors file
Xfid.colorswrite(x: self ref Xfid, w: ref Window)
{
	fc: Smsg0;

	nb := sys->utfbytes(data(x.fcall), count(x.fcall));
	r := string data(x.fcall)[0:nb];

	# Handle reset command
	if(r == "reset\n" || r == "reset"){
		w.colorstr = nil;
		w.applycolors();
		fc.count = count(x.fcall);
		respond(x, fc, nil);
		return;
	}

	# Split input into lines and validate/merge each
	newlines := splitcolorlines(r);
	for(; newlines != nil; newlines = tl newlines) {
		line := hd newlines;
		# Skip empty lines
		if(extractcolorkey(line) == "")
			continue;
		if(!validcolorstr(line)){
			respond(x, fc, "bad color format");
			return;
		}
		# Merge this line with existing settings
		w.colorstr = mergecolorstr(w.colorstr, line);
	}

	w.applycolors();
	fc.count = count(x.fcall);
	respond(x, fc, nil);
}

# Write handler for image file - load image from path
Xfid.imagewrite(x: self ref Xfid, w: ref Window)
{
	fc: Smsg0;

	nb := sys->utfbytes(data(x.fcall), count(x.fcall));
	r := string data(x.fcall)[0:nb];

	# Strip trailing newline if present
	if(len r > 0 && r[len r - 1] == '\n')
		r = r[:len r - 1];

	# Strip trailing whitespace
	while(len r > 0 && (r[len r - 1] == ' ' || r[len r - 1] == '\t'))
		r = r[:len r - 1];

	if(len r == 0){
		respond(x, fc, "empty path");
		return;
	}

	err := w.loadimage(r);
	if(err != nil){
		respond(x, fc, err);
		return;
	}

	fc.count = count(x.fcall);
	respond(x, fc, nil);
}
