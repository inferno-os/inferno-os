implement Wmlib;

#
# Copyright © 2003 Vita Nuova Holdings Limited
#

# basic window manager functionality, used by
# tkclient and wmclient to create more usable functionality.

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Image, Screen, Rect, Point, Pointer, Wmcontext, Context: import draw;
include "wmsrv.m";
include "wmlib.m";

Client: adt{
	ptrpid:	int;
	kbdpid:	int;
	ctlpid:	int;
	req:		chan of (array of byte, Sys->Rwrite);
	dir:		string;
	ctlfd:		ref Sys->FD;
	winfd:	ref Sys->FD;
};

DEVWM: con "/mnt/wm";
Ptrsize: con 1+4*12;		# 'm' plus 4 12-byte decimal integers

kbdstarted: int;
ptrstarted: int;
wptr: chan of Point;		# set mouse position (only if we've opened /dev/pointer directly)
cswitch: chan of (string, int, chan of string);	# switch cursor images (as for wptr)

init()
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
}

#	(_screen, dispi) := ctxt.display.getwindow("/dev/winname", nil, nil, 1); XXX corrupts heap... fix it!

makedrawcontext(): ref Draw->Context
{
	display := Display.allocate(nil);
	if(display == nil){
		sys->fprint(sys->fildes(2), "wmlib: can't allocate Display: %r\n");
		raise "fail:no display";
	}
	return ref Draw->Context(display, nil, nil);
}

importdrawcontext(devdraw, mntwm: string): (ref Draw->Context, string)
{
	if(mntwm == nil)
		mntwm = "/mnt/wm";

	display := Display.allocate(devdraw);
	if(display == nil)
		return (nil, sys->sprint("cannot allocate display: %r"));
	(ok, nil) := sys->stat(mntwm + "/clone");
	if(ok == -1)
		return (nil, "cannot find wm namespace");
	wc := chan of (ref Draw->Context, string);
	spawn wmproxy(display, mntwm, wc);
	return <-wc;
}

# XXX we have no way of knowing when this process should go away...
# perhaps a Draw->Context should hold a file descriptor
# so that we do.
wmproxy(display: ref Display, dir: string, wc: chan of (ref Draw->Context, string))
{
	wmsrv := load Wmsrv Wmsrv->PATH;
	if(wmsrv == nil){
		wc <-= (nil, sys->sprint("cannot load %s: %r", Wmsrv->PATH));
		return;
	}
	sys->pctl(Sys->NEWFD, 1 :: 2 :: nil);

	(wm, join, req) := wmsrv->init();
	if(wm == nil){
		wc <-= (nil, sys->sprint("%r"));
		return;
	}
	wc <-= (ref Draw->Context(display, nil, wm), nil);

	clients: array of ref Client;
	for(;;) alt{
	(sc, rc) := <-join =>
		sync := chan of (ref Client, string);
		spawn clientproc(display, sc, dir, sync);
		(c, err) := <-sync;
		rc <-= err;
		if(c != nil){
			if(sc.id >= len clients)
				clients = (array[sc.id + 1] of ref Client)[0:] = clients;
			clients[sc.id] = c;
		}
	(sc, data, rc) := <-req =>
		clients[sc.id].req <-= (data, rc);
		if(rc == nil)
			clients[sc.id] = nil;
	}
}

zclient: Client;
clientproc(display: ref Display, sc: ref Wmsrv->Client, dir: string, rc: chan of (ref Client, string))
{
	ctlfd := sys->open(dir + "/clone", Sys->ORDWR);
	if(ctlfd == nil){
		rc <-= (nil, sys->sprint("cannot open %s/clone: %r", dir));
		return;
	}
	buf := array[20] of byte;
	n := sys->read(ctlfd, buf, len buf);
	if(n <= 0){
		rc <-= (nil, "cannot read ctl id");
		return;
	}
	sys->fprint(ctlfd, "fixedorigin");
	dir += "/" + string buf[0:n];
	c := ref zclient;
	c.req = chan of (array of byte, Sys->Rwrite);
	c.dir = dir;
	c.ctlfd = ctlfd;
	if ((c.winfd = sys->open(dir + "/winname", Sys->OREAD)) == nil){
		rc <-= (nil, sys->sprint("cannot open %s/winname: %r", dir));
		return;
	}
	rc <-= (c, nil);

	pidc := chan of int;
	spawn ctlproc(pidc, ctlfd, sc.ctl);
	c.ctlpid = <-pidc;
	for(;;) {
		(data, drc) := <-c.req;
		if(drc == nil)
			break;
		err := handlerequest(display, c, sc, data);
		n = len data;
		if(err != nil)
			n = -1;
		alt{
		drc <-= (n, err) =>;
		* =>;
		}
	}
	sc.stop <-= 1;
	kill(c.kbdpid, "kill");
	kill(c.ptrpid, "kill");
	kill(c.ctlpid, "kill");
	c.ctlfd = nil;
	c.winfd = nil;
}

handlerequest(display: ref Display, c: ref Client, sc: ref Wmsrv->Client, data: array of byte): string
{
	req := string data;
	if(req == nil)
		return nil;
	(w, e) := qword(req, 0);
	case w {
	"start" =>
		(w, e) = qword(req, e);
		case w {
		"ptr" or
		"mouse" =>
			if(c.ptrpid == -1)
				return "already started";
			fd := sys->open(c.dir + "/pointer", Sys->OREAD);
			if(fd == nil)
				return sys->sprint("cannot open %s: %r", c.dir + "/pointer");
			sync := chan of int;
			spawn ptrproc(sync, fd, sc.ptr);
			c.ptrpid = <-sync;
			return nil;
		"kbd" =>
			if(c.kbdpid == -1)
				return "already started";
			sync := chan of (int, string);
			spawn kbdproc(sync, c.dir + "/keyboard", sc.kbd);
			(pid, err) := <-sync;
			c.kbdpid = pid;
			return err;
		}
	}

	if(sys->write(c.ctlfd, data, len data) == -1)
		return sys->sprint("%r");
	if(req[0] == '!'){
		buf := array[100] of byte;
		n := sys->read(c.winfd, buf, len buf);
		if(n <= 0)
			return sys->sprint("read winname: %r");
		name := string buf[0:n];
		# XXX this is the dodgy bit...
		i := display.namedimage(name);
		if(i == nil)
			return sys->sprint("cannot get image %#q: %r", name);
		s := Screen.allocate(i, display.white, 0);
		i = s.newwindow(i.r, Draw->Refnone, Draw->Nofill);
		rc := chan of int;
		sc.images <-= (nil, i, rc);
		if(<-rc == -1)
			return "image request already in progress";
	}
	return nil;
}

connect(ctxt: ref Context): ref Wmcontext
{
	# don't automatically make a new Draw->Context, 'cos the
	# client should be aware that there's no wm so multiple
	# windows won't work correctly.
	# ... unless there's an exported wm available, of course!
	if(ctxt == nil){
		sys->fprint(sys->fildes(2), "wmlib: no draw context\n");
		raise "fail:error";
	}
	if(ctxt.wm == nil){
		wm := ref Wmcontext(
			chan of int,
			chan of ref Draw->Pointer,
			chan of string,
			nil,	# unused
			chan of ref Image,
			nil,
			ctxt
		);
		return wm;
	}
	fd := sys->open("/chan/wmctl", Sys->ORDWR);
	if(fd == nil){
		sys->fprint(sys->fildes(2), "wmlib: cannot open /chan/wmctl: %r\n");
		raise "fail:error";
	}
	buf := array[32] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0){
		sys->fprint(sys->fildes(2), "wmlib: cannot get window token: %r\n");
		raise "fail:error";
	}
	reply := chan of (string, ref Wmcontext);
	ctxt.wm <-= (string buf[0:n], reply);
	(err, wm) := <-reply;
	if(err != nil){
		sys->fprint(sys->fildes(2), "wmlib: cannot connect: %s\n", err);
		raise "fail:" + err;
	}
	wm.connfd = fd;
	wm.ctxt = ctxt;
	return wm;
}

startinput(wm: ref Wmcontext, devs: list of string): string
{
	for(; devs != nil; devs = tl devs)
		wmctl(wm, "start " + hd devs);
	return nil;
}

reshape(wm: ref Wmcontext, name: string, r: Draw->Rect, i: ref Draw->Image, how: string): ref Draw->Image
{
	if(name == nil)
		return nil;
	(nil, ni, err) := wmctl(wm, sys->sprint("!reshape %s -1 %d %d %d %d %s", name, r.min.x, r.min.y, r.max.x, r.max.y, how));
	if(err == nil)
		return ni;
	return i;
}

#
# wmctl implements the default window behaviour
#
wmctl(wm: ref Wmcontext, request: string): (string, ref Image, string)
{
	(w, e) := qword(request, 0);
	case w {
	"exit" =>
		kill(sys->pctl(0, nil), "killgrp");
		exit;
	* =>
		if(wm.connfd != nil){
			# standard form for requests: if request starts with '!',
			# then the next word gives the tag of the window that the
			# request applies to, and a new image is provided.
			if(sys->fprint(wm.connfd, "%s", request) == -1){
				sys->fprint(sys->fildes(2), "wmlib: wm request '%s' failed\n", request);
				return (nil, nil, sys->sprint("%r"));
			}
			if(request[0] == '!'){
				i := <-wm.images;
				if(i == nil)
					i = <-wm.images;
				return (qword(request, e).t0, i, nil);
			}
			return (nil, nil, nil);
		}
		# requests we can handle ourselves, if we have to.
		case w{
		"start" =>
			(w, e) = qword(request, e);
			case w{
			"ptr" or
			"mouse" =>
				if(!ptrstarted){
					fd := sys->open("/dev/pointer", Sys->ORDWR);
					if(fd != nil)
						wptr = chan of Point;
					else
						fd = sys->open("/dev/pointer", Sys->OREAD);
					if(fd == nil)
						return (nil, nil, sys->sprint("cannot open /dev/pointer: %r"));
					cfd := sys->open("/dev/cursor", Sys->OWRITE);
					if(cfd != nil)
						cswitch = chan of (string, int, chan of string);
					spawn wptrproc(fd, cfd);
					sync := chan of int;
					spawn ptrproc(sync, fd, wm.ptr);
					<-sync;
					ptrstarted = 1;
				}
			"kbd" =>
				if(!kbdstarted){
					sync := chan of (int, string);
					spawn kbdproc(sync, "/dev/keyboard", wm.kbd);
					(nil, err) := <-sync;
					if(err != nil)
						return (nil, nil, err);
					spawn sendreq(wm.ctl, "haskbdfocus 1");
					kbdstarted = 1;
				}
			* =>
				return (nil, nil, "unknown input source");
			}
			return (nil, nil, nil);
		"ptr" =>
			if(wptr == nil)
				return (nil, nil, "cannot change mouse position");
			p: Point;
			(w, e) = qword(request, e);
			p.x = int w;
			(w, e) = qword(request, e);
			p.y = int w;
			wptr <-= p;
			return (nil, nil, nil);
		"cursor" =>
			if(cswitch == nil)
				return (nil, nil, "cannot switch cursor");
			cswitch <-= (request, e, reply := chan of string);
			return (nil, nil, <-reply);
		* =>
			return (nil, nil, "unknown wmctl request");
		}
	}
}

sendreq(c: chan of string, s: string)
{
	c <-= s;
}

ctlproc(sync: chan of int, fd: ref Sys->FD, ctl: chan of string)
{
	sync <-= sys->pctl(0, nil);
	buf := array[4096] of byte;
	while((n := sys->read(fd, buf, len buf)) > 0)
		ctl <-= string buf[0:n];
}

kbdproc(sync: chan of (int, string), f: string, keys: chan of int)
{
	sys->pctl(Sys->NEWFD, nil);
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil){
		sync <-= (-1, sys->sprint("cannot open /dev/keyboard: %r"));
		return;
	}
	sync <-= (sys->pctl(0, nil), nil);
	buf := array[12] of byte;
	while((n := sys->read(fd, buf, len buf)) > 0){
		s := string buf[0:n];
		for(j := 0; j < len s; j++)
			keys <-= int s[j];
	}
}

wptrproc(pfd, cfd: ref Sys->FD)
{
	if(wptr == nil && cswitch == nil)
		return;
	if(wptr == nil)
		wptr = chan of Point;
	if(cswitch == nil)
		cswitch = chan of (string, int, chan of string);
	for(;;)alt{
	p := <-wptr =>
		sys->fprint(pfd, "m%11d %11d", p.x, p.y);
	(c, start, reply) := <-cswitch =>
		buf: array of byte;
		if(start == len c){
			buf = array[0] of byte;
		}else{
			hot, size: Point;
			(w, e) := qword(c, start);
			hot.x = int w;
			(w, e) = qword(c, e);
			hot.y = int w;
			(w, e) = qword(c, e);
			size.x = int w;
			(w, e) = qword(c, e);
			size.y = int w;
			((d0, d1), nil) := splitqword(c, e);
			nb := size.x/8*size.y;
			if(d1 - d0 != nb * 2){
				reply <-= "inconsistent cursor image data";
				break;
			}
			buf = array[4*4 + nb] of byte;
			bplong(buf, 0*4, hot.x);
			bplong(buf, 1*4, hot.y);
			bplong(buf, 2*4, size.x);
			bplong(buf, 3*4, size.y);
			j := 4*4;
			for(i := d0; i < d1; i += 2)
				buf[j++] = byte ((hexc(c[i]) << 4) | hexc(c[i+1]));
		}
		if(sys->write(cfd, buf, len buf) != len buf)
			reply <-= sys->sprint("%r");
		else
			reply <-= nil;
	}
}

hexc(c: int): int
{
	if(c >= '0' && c <= '9')
		return c - '0';
	if(c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	if(c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	return 0;
}

bplong(d: array of byte, o: int, x: int)
{
	d[o] = byte x;
	d[o+1] = byte (x >> 8);
	d[o+2] = byte (x >> 16);
	d[o+3] = byte (x >> 24);
}

ptrproc(sync: chan of int, fd: ref Sys->FD, ptr: chan of ref Draw->Pointer)
{
	sync <-= sys->pctl(0, nil);

	b:= array[Ptrsize] of byte;
	while(sys->read(fd, b, len b) > 0){
		p := bytes2ptr(b);
		if(p != nil)
			ptr <-= p;
	}
}

bytes2ptr(b: array of byte): ref Pointer
{
	if(len b < Ptrsize || int b[0] != 'm')
		return nil;
	x := int string b[1:13];
	y := int string b[13:25];
	but := int string b[25:37];
	msec := int string b[37:49];
	return ref Pointer (but, (x, y), msec);
}

snarfbuf: string;		# at least we get *something* when there's no wm.

snarfget(): string
{
	fd := sys->open("/chan/snarf", sys->OREAD);
	if(fd == nil)
		return snarfbuf;

	buf := array[8192] of byte;
	nr := 0;
	while ((n := sys->read(fd, buf[nr:], len buf - nr)) > 0) {
		nr += n;
		if (nr == len buf) {
			nbuf := array[len buf * 2] of byte;
			nbuf[0:] = buf;
			buf = nbuf;
		}
	}
	return string buf[0:nr];
}

snarfput(buf: string)
{
	fd := sys->open("/chan/snarf", sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "%s", buf);
	else
		snarfbuf = buf;
}

# return (qslice, end).
# the slice has a leading quote if the word is quoted; it does not include the terminating quote.
splitqword(s: string, start: int): ((int, int), int)
{
	for(; start < len s; start++)
		if(s[start] != ' ')
			break;
	if(start >= len s)
		return ((start, start), start);
	i := start;
	end := -1;
	if(s[i] == '\''){
		gotq := 0;
		for(i++; i < len s; i++){
			if(s[i] == '\''){
				if(i + 1 >= len s || s[i + 1] != '\''){
					end = i+1;
					break;
				}
				i++;
				gotq = 1;
			}
		}
		if(!gotq && i > start+1)
			start++;
		if(end == -1)
			end = i;
	} else {
		for(; i < len s; i++)
			if(s[i] == ' ')
				break;
		end = i;
	}
	return ((start, i), end);
}

# unquote a string slice as returned by sliceqword.
qslice(s: string, r: (int, int)): string
{
	if(r.t0 == r.t1)
		return nil;
	if(s[r.t0] != '\'')
		return s[r.t0:r.t1];
	t := "";
	for(i := r.t0 + 1; i < r.t1; i++){
		t[len t] = s[i];
		if(s[i] == '\'')
			i++;
	}
	return t;
}

qword(s: string, start: int): (string, int)
{
	(w, next) := splitqword(s, start);
	return (qslice(s, w), next);
}

s2r(s: string, e: int): (Rect, int)
{
	r: Rect;
	w: string;
	(w, e) = qword(s, e);
	r.min.x = int w;
	(w, e) = qword(s, e);
	r.min.y = int w;
	(w, e) = qword(s, e);
	r.max.x = int w;
	(w, e) = qword(s, e);
	r.max.y = int w;
	return (r, e);
}

kill(pid: int, note: string): int
{
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil)		# dodgy failover
		fd = sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", note) < 0)
		return -1;
	return 0;
}
