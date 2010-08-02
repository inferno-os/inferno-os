implement Wmexport;

#
# Copyright © 2003 Vita Nuova Holdings Limited.
#

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Wmcontext, Image: import draw;
include "wmlib.m";
	wmlib: Wmlib;
include "styx.m";
	styx: Styx;
	Rmsg, Tmsg: import styx;
include "styxservers.m";
	styxservers: Styxservers;
	Styxserver, Fid, Navigator, Navop: import styxservers;
	Enotdir, Enotfound: import Styxservers;

Wmexport: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

# filesystem looks like:
#	clone
#	1
#		wmctl
#		keyboard
#		pointer
#		winname

badmodule(p: string)
{
	sys->fprint(sys->fildes(2), "wmexport: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

user := "me";
qidseq := 1;
imgseq := 0;

pidregister: chan of (int, int);
flush: chan of (int, int, chan of int);

makeconn: chan of chan of (ref Conn, string);
delconn: chan of ref Conn;
reqpool: list of chan of (ref Tmsg, ref Conn, ref Fid);
reqidle: int;
reqdone: chan of chan of (ref Tmsg, ref Conn, ref Fid);

srv: ref Styxserver;
ctxt: ref Draw->Context;

conns: array of ref Conn;
nconns := 0;

Qerror, Qroot, Qdir, Qclone, Qwmctl, Qptr, Qkbd, Qwinname: con iota;
Shift: con 4;
Mask: con 16rf;

Maxreqidle: con 3;
Maxreplyidle: con 3;

Conn: adt {
	wm:		ref Wmcontext;
	iname:	string;				# name of image
	n:		int;
	nreads:	int;
};

# initial connection provides base-name (fid?) for images.
# full name could be:
#	window.fid.tag

init(drawctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	ctxt = drawctxt;
	if(ctxt == nil || ctxt.wm == nil){
		sys->fprint(sys->fildes(2), "wmexport: no window manager context\n");
		raise "fail:no wm";
	}
	draw = load Draw Draw->PATH;
	styx = load Styx Styx->PATH;
	if (styx == nil)
		badmodule(Styx->PATH);
	styx->init();
	styxservers = load Styxservers Styxservers->PATH;
	if (styxservers == nil)
		badmodule(Styxservers->PATH);
	styxservers->init(styx);

	wmlib = load Wmlib Wmlib->PATH;
	if(wmlib == nil)
		badmodule(Wmlib->PATH);
	wmlib->init();

	sys->pctl(Sys->FORKNS|Sys->NEWPGRP, nil);		# fork pgrp?

	ctxt = drawctxt;
	navops := chan of ref Navop;
	spawn navigator(navops);
	tchan: chan of ref Tmsg;
	(tchan, srv) = Styxserver.new(sys->fildes(0), Navigator.new(navops), big Qroot);
	srv.replychan = chan of ref Styx->Rmsg;
	spawn replymarshal(srv.replychan);
	spawn serve(tchan, navops);
}

serve(tchan: chan of ref Tmsg, navops: chan of ref Navop)
{
	pidregister = chan of (int, int);
	makeconn = chan of chan of (ref Conn, string);
	delconn = chan of ref Conn;
	flush = chan of (int, int, chan of int);
	reqdone = chan of chan of (ref Tmsg, ref Conn, ref Fid);
	spawn flushproc(flush);

Serve:
	for(;;)alt{
	gm := <-tchan =>
		if(gm == nil)
			break Serve;
		pick m := gm {
		Readerror =>
			sys->fprint(sys->fildes(2), "wmexport: fatal read error: %s\n", m.error);
			break Serve;
		Open =>
			(fid, mode, d, err) := srv.canopen(m);
			if(err != nil)
				srv.reply(ref Rmsg.Error(m.tag, err));
			else if(fid.qtype & Sys->QTDIR)
				srv.default(m);
			else
				request(ctxt, m, fid);
		Read =>
			(fid, err) := srv.canread(m);
			if(err != nil)
				srv.reply(ref Rmsg.Error(m.tag, err));
			else if(fid.qtype & Sys->QTDIR)
				srv.read(m);
			else
				request(ctxt, m, fid);
		Write =>
			(fid, err) := srv.canwrite(m);
			if(err != nil)
				srv.reply(ref Rmsg.Error(m.tag, err));
			else
				request(ctxt, m, fid);
		Flush =>
			done := chan of int;
			flush <-= (m.tag, m.oldtag, done);
			<-done;
		Clunk =>
			request(ctxt, m, srv.clunk(m));
		* =>
			srv.default(gm);
		}
	rc := <-makeconn =>
		if(nconns >= len conns)
			conns = (array[len conns + 5] of ref Conn)[0:] = conns;
		wm := wmlib->connect(ctxt);
		if(wm == nil)				# XXX this can't happen - give wmlib->connect an error return
			rc <-= (nil, "cannot connect");
		else{
			c := ref Conn(wm, nil, qidseq++, 0);
			conns[nconns++] = c;
			rc <-= (c, nil);
		}
	c := <-delconn =>
		for(i := 0; i < nconns; i++)
			if(conns[i] == c)
				break;
		nconns--;
		if(i < nconns)
			conns[i] = conns[nconns];
		conns[nconns] = nil;
	reqpool = <-reqdone :: reqpool =>
		if(reqidle++ > Maxreqidle){
			hd reqpool <-= (nil, nil, nil);
			reqpool = tl reqpool;
			reqidle--;
		}
	}
	navops <-= nil;
	kill(sys->pctl(0, nil), "killgrp");
}

nameimage(nil: ref Conn, img: ref Draw->Image): string
{
	if(img.iname != nil)
		return img.iname;
	for(i := 0; i < 100; i++){
		s := "inferno." + string imgseq++;
		if(img.name(s, 1) > 0)
			return s;
		if(img.iname != nil)
			return img.iname;		# a competing process has done it for us.
	}
sys->print("wmexport: no image names: %r\n");
raise "panic";
}

request(nil: ref Draw->Context, m: ref Styx->Tmsg, fid: ref Fid)
{
	n := int fid.path >> Shift;
	conn: ref Conn;
	for(i := 0; i < nconns; i++){
		if(conns[i].n == n){
			conn = conns[i];
			break;
		}
	}
	c: chan of (ref Tmsg, ref Conn, ref Fid);
	if(reqpool == nil){
		c = chan of (ref Tmsg, ref Conn, ref Fid);
		spawn requestproc(c);
	}else{
		(c, reqpool) = (hd reqpool, tl reqpool);
		reqidle--;
	}
	c <-= (m, conn, fid);
}

requestproc(req: chan of (ref Tmsg, ref Conn, ref Fid))
{
	pid := sys->pctl(0, nil);
	for(;;){
		(gm, c, fid) := <-req;
		if(gm == nil)
			break;
		pidregister <-= (pid, gm.tag);
		path := int fid.path;
		pick m := gm {
		Read =>
			if(c == nil)
				srv.replydirect(ref Rmsg.Error(m.tag, "connection is dead"));
			case path & Mask {
			Qwmctl =>
				# first read gets number of connection.
				m.offset = big 0;
				if(c.nreads++ == 0)
					srv.replydirect(styxservers->readstr(m, string c.n));
				else
					srv.replydirect(styxservers->readstr(m, <-c.wm.ctl));
			Qptr =>
				m.offset = big 0;
				p := <-c.wm.ptr;
				srv.replydirect(styxservers->readbytes(m,
					sys->aprint("m%11d %11d %11d %11ud ", p.xy.x, p.xy.y, p.buttons, p.msec)));
			Qkbd =>
				m.offset = big 0;
				s := "";
				s[0] = <-c.wm.kbd;
				srv.replydirect(styxservers->readstr(m, s));
			Qwinname =>
				m.offset = big 0;
				srv.replydirect(styxservers->readstr(m, c.iname));
			* =>
				srv.replydirect(ref Rmsg.Error(m.tag, "what was i thinking1?"));
			}
		Write =>
			if(c == nil)
				srv.replydirect(ref Rmsg.Error(m.tag, "connection is dead"));
			case path & Mask {
			Qwmctl =>
				if(sys->write(c.wm.connfd, m.data, len m.data) == -1){
					srv.replydirect(ref Rmsg.Error(m.tag, sys->sprint("%r")));
					break;
				}
				if(len m.data > 0 && int m.data[0] == '!'){
					i := <-c.wm.images;
					if(i == nil)
						i = <-c.wm.images;
					c.iname = nameimage(c, i);
				}
				srv.replydirect(ref Rmsg.Write(m.tag, len m.data));
			* =>
				srv.replydirect(ref Rmsg.Error(m.tag, "what was i thinking2?"));
			}
		Open =>
			if(c == nil && path != Qclone)
				srv.replydirect(ref Rmsg.Error(m.tag, "connection is dead"));
			err: string;
			q := qid(path);
			case path & Mask {
			Qclone =>
				cch := chan of (ref Conn, string);
				makeconn <-= cch;
				(c, err) = <-cch;
				if(c != nil)
					q = qid(Qwmctl | (c.n << Shift));
			Qptr =>
				if(sys->fprint(c.wm.connfd, "start ptr") == -1)
					err = sys->sprint("%r");
			Qkbd =>
				if(sys->fprint(c.wm.connfd, "start kbd") == -1)
					err = sys->sprint("%r");
			Qwmctl =>
				;
			Qwinname =>
				;
			* =>
				err = "what was i thinking3?";
			}
			if(err != nil)
				srv.replydirect(ref Rmsg.Error(m.tag, err));
			else{
				srv.replydirect(ref Rmsg.Open(m.tag, q, 0));
				fid.open(m.mode, q);
			}
		Clunk =>
			case path & Mask {
			Qwmctl =>
				if(c != nil)
					delconn <-= c;
			}
		* =>
			srv.replydirect(ref Rmsg.Error(gm.tag, "oh dear"));	
		}
		pidregister <-= (pid, -1);
		reqdone <-= req;
	}
}

qid(path: int): Sys->Qid
{
	return dirgen(path).t0.qid;
}
		
replyproc(c: chan of ref Rmsg, replydone: chan of chan of ref Rmsg)
{
	# hmm, this could still send a reply out-of-order with a flush
	while((m := <-c) != nil){
		srv.replydirect(m);
		replydone <-= c;
	}
}

# deal with reply messages coming from styxservers.
replymarshal(c: chan of ref Styx->Rmsg)
{
	replypool: list of chan of ref Rmsg;
	n := 0;
	replydone := chan of chan of ref Rmsg;
	for(;;) alt{
	m := <-c =>
		c: chan of ref Rmsg;
		if(replypool == nil){
			c = chan of ref Rmsg;
			spawn replyproc(c, replydone);
		}else{
			(c, replypool) = (hd replypool, tl replypool);
			n--;
		}
		c <-= m;
	replypool = <-replydone :: replypool =>
		if(++n > Maxreplyidle){
			hd replypool <-= nil;
			replypool = tl replypool;
			n--;
		}
	}
}

navigator(navops: chan of ref Navop)
{
	while((m := <-navops) != nil){
		path := int m.path;
		pick n := m {
		Stat =>
			n.reply <-= dirgen(int n.path);
		Walk =>
			name := n.name;
			case path & Mask {
			Qdir =>
				dp := path & ~Mask;
				case name {
				".." =>
					path = Qroot;
				"wmctl" =>
					path = Qwmctl | dp;
				"pointer" =>
					path = Qptr | dp;
				"keyboard" =>
					path = Qkbd | dp;
				"winname" =>
					path = Qwinname | dp;
				* =>
					path = Qerror;
				}
			Qroot =>
				case name{
				"clone" =>
					path = Qclone;
				* =>
					x := int name;
					path = Qerror;
					if(string x == name){
						for(i := 0; i < nconns; i++)
							if(conns[i].n == x){
								path = (x << Shift) | Qdir;
								break;
							}
					}
				}
			}
			n.reply <-= dirgen(path);
		Readdir =>
			err := "";
			d: array of int;
			case path & Mask {
			Qdir =>
				d = array[] of {Qwmctl, Qptr, Qkbd, Qwinname};
				for(i := 0; i < len d; i++)
					d[i] |= path & ~Mask;
			Qroot =>
				d = array[nconns + 1] of int;
				d[0] = Qclone;
				for(i := 0; i < nconns; i++)
					d[i + 1] = (conns[i].n<<Shift) | Qdir;
			}
			if(d == nil){
				n.reply <-= (nil, Enotdir);
				break;
			}
			for (i := n.offset; i < len d; i++)
				n.reply <-= dirgen(d[i]);
			n.reply <-= (nil, nil);
		}
	}
}

dirgen(path: int): (ref Sys->Dir, string)
{
	name: string;
	perm: int;
	case path & Mask {
	Qroot =>
		name = ".";
		perm = 8r555|Sys->DMDIR;
	Qdir =>
		name = string (path >> Shift);
		perm = 8r555|Sys->DMDIR;
	Qclone =>
		name = "clone";
		perm = 8r666;
	Qwmctl =>
		name = "wmctl";
		perm = 8r666;
	Qptr =>
		name = "pointer";
		perm = 8r444;
	Qkbd =>
		name = "keyboard";
		perm = 8r444;
	Qwinname =>
		name = "winname";
		perm = 8r444;
	* =>
		return (nil, Enotfound);
	}
	return (dir(path, name, perm), nil);
}

dir(path: int, name: string, perm: int): ref Sys->Dir
{
	d := ref sys->zerodir;
	d.qid.path = big path;
	if(perm & Sys->DMDIR)
		d.qid.qtype = Sys->QTDIR;
	d.mode = perm;
	d.name = name;
	d.uid = user;
	d.gid = user;
	return d;
}

flushproc(flush: chan of (int, int, chan of int))
{
	a: array of (int, int);		# (pid, tag)
	n := 0;
	for(;;)alt{
	(pid, tag) := <-pidregister =>
		if(tag == -1){
			for(i := 0; i < n; i++)
				if(a[i].t0 == pid)
					break;
			n--;
			if(i < n)
				a[i] = a[n];
		}else{
			if(n >= len a){
				na := array[n + 5] of (int, int);
				na[0:] = a;
				a = na;
			}
			a[n++] = (pid, tag);
		}
	(tag, oldtag, done) := <-flush =>
		for(i := 0; i < n; i++)
			if(a[i].t1 == oldtag){
				spawn doflush(tag, a[i].t0, done);
				break;
			}
		if(i == n)
			spawn doflush(tag, -1, done);
	}
}

doflush(tag: int, pid: int, done: chan of int)
{
	if(pid != -1){
		kill(pid, "kill");
		pidregister <-= (pid, -1);
	}
	srv.replydirect(ref Rmsg.Flush(tag));
	done <-= 1;
}

# return number of characters from s that will fit into
# max bytes when encoded as utf-8.
fullutf(s: string, max: int): int
{
	Bit1:	con 7;
	Bitx:	con 6;
	Bit2:	con 5;
	Bit3:	con 4;
	Bit4:	con 3;
	Rune1:	con (1<<(Bit1+0*Bitx))-1;		# 0000 0000 0111 1111
	Rune2:	con (1<<(Bit2+1*Bitx))-1;		# 0000 0111 1111 1111
	Rune3:	con (1<<(Bit3+2*Bitx))-1;		# 1111 1111 1111 1111
	nb := 0;
	for(i := 0; i < len s; i++){
		c := s[i];
		if(c <= Rune1)
			nb += 1;
		else if(c <= Rune2)
			nb += 2;
		else
			nb += 3;
		if(nb > max)
			break;
	}
	return i;
}

kill(pid: int, note: string): int
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", note) < 0)
		return -1;
	return 0;
}
