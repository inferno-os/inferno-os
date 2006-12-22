implement Wmsrv;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Image, Point, Rect, Screen, Pointer, Context, Wmcontext: import draw;
include "wmsrv.m";

zorder: ref Client;		# top of z-order list, linked by znext.

ZR: con Rect((0, 0), (0, 0));
Iqueue: adt {
	h, t: list of int;
	n: int;
	put:			fn(q: self ref Iqueue, s: int);
	get:			fn(q: self ref Iqueue): int;
	peek:		fn(q: self ref Iqueue): int;
	nonempty:	fn(q: self ref Iqueue): int;
};
Squeue: adt {
	h, t: list of string;
	n: int;
	put:			fn(q: self ref Squeue, s: string);
	get:			fn(q: self ref Squeue): string;
	peek:		fn(q: self ref Squeue): string;
	nonempty:	fn(q: self ref Squeue): int;
};
# Ptrqueue is the same as the other queues except it merges events
# that have the same button state.
Ptrqueue: adt {
	last: ref Pointer;
	h, t: list of ref Pointer;
	put:			fn(q: self ref Ptrqueue, s: ref Pointer);
	get:			fn(q: self ref Ptrqueue): ref Pointer;
	peek:		fn(q: self ref Ptrqueue): ref Pointer;
	nonempty:	fn(q: self ref Ptrqueue): int;
	flush:		fn(q: self ref Ptrqueue);
};

init(): 	(chan of (string, chan of (string, ref Wmcontext)),
		chan of (ref Client, chan of string),
		chan of (ref Client, array of byte, Sys->Rwrite))
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;

	sys->bind("#s", "/chan", Sys->MBEFORE);

	ctlio := sys->file2chan("/chan", "wmctl");
	if(ctlio == nil){
		sys->werrstr(sys->sprint("can't create /chan/wmctl: %r"));
		return (nil, nil, nil);
	}

	wmreq := chan of (string, chan of (string, ref Wmcontext));
	join := chan of (ref Client, chan of string);
	req := chan of (ref Client, array of byte, Sys->Rwrite);
	spawn wm(ctlio, wmreq, join, req);
	return (wmreq, join, req);
}

wm(ctlio: ref Sys->FileIO,
			wmreq: chan of (string, chan of (string, ref Wmcontext)),
			join: chan of (ref Client, chan of string),
			req: chan of (ref Client, array of byte, Sys->Rwrite))
{
	clients: array of ref Client;

	for(;;)alt{
	(cmd, rc) := <-wmreq =>
		token := int cmd;
		for(i := 0; i < len clients; i++)
			if(clients[i] != nil && clients[i].token == token)
				break;

		if(i == len clients){
			spawn senderror(rc, "not found");
			break;
		}
		c := clients[i];
		if(c.stop != nil){
			spawn senderror(rc, "already started");
			break;
		}
		ok := chan of string;
		join <-= (c, ok);
		if((e := <-ok) != nil){
			spawn senderror(rc, e);
			break;
		}
		c.stop = chan of int;
		spawn childminder(c, rc);

	(nil, nbytes, fid, rc) := <-ctlio.read =>
		if(rc == nil)
			break;
		c := findfid(clients, fid);
		if(c == nil){
			c = ref Client(
				chan of int,
				chan of ref Draw->Pointer,
				chan of string,
				nil,
				0,
				nil,
				nil,
				nil,

				chan of (ref Point, ref Image, chan of int),
				-1,
				fid,
				fid,			# token; XXX could be random integer + fid
				newwmcontext()
			);
			clients = addclient(clients, c);
		}
		alt{
		rc <-= (sys->aprint("%d", c.token), nil) => ;
		* => ;
		}
	(nil, data, fid, wc) := <-ctlio.write =>
		c := findfid(clients, fid);
		if(wc != nil){
			if(c == nil){
				alt{
				wc <-= (0, "must read first") => ;
				* => ;
				}
				break;
			}
			req <-= (c, data, wc);
		}else if(c != nil){
			req <-= (c, nil, nil);
			delclient(clients, c);
		}
	}
}

# buffer all events between a window manager and
# a client, so that one recalcitrant child can't
# clog the whole system.
childminder(c: ref Client, rc: chan of (string, ref Wmcontext))
{
	wmctxt := c.wmctxt;

	dummykbd := chan of int;
	dummyptr := chan of ref Pointer;
	dummyimg := chan of ref Image;
	dummyctl := chan of string;

	kbdq := ref Iqueue;
	ptrq := ref Ptrqueue;
	ctlq := ref Squeue;

	Imgnone, Imgsend, Imgsendnil1, Imgsendnil2, Imgorigin: con iota;
	img, sendimg: ref Image;
	imgorigin: Point;
	imgstate := Imgnone;

	# send reply to client, but make sure we don't block.
Reply:
	for(;;) alt{
	rc <-= (nil, ref *wmctxt) =>
		break Reply;
	<-c.stop =>
		exit;
	key := <-c.kbd =>
		kbdq.put(key);
	ptr := <-c.ptr =>
		ptrq.put(ptr);
	ctl := <-c.ctl =>
		ctlq.put(ctl);
	}

	for(;;){
		outkbd := dummykbd;
		key := -1;
		if(kbdq.nonempty()){
			key = kbdq.peek();
			outkbd = wmctxt.kbd;
		}

		outptr := dummyptr;
		ptr: ref Pointer;
		if(ptrq.nonempty()){
			ptr = ptrq.peek();
			outptr = wmctxt.ptr;
		}

		outctl := dummyctl;
		ctl: string;
		if(ctlq.nonempty()){
			ctl = ctlq.peek();
			outctl = wmctxt.ctl;
		}

		outimg := dummyimg;
		case imgstate{
		Imgsend =>
			outimg = wmctxt.images;
			sendimg = img;
		Imgsendnil1 or
		Imgsendnil2 or
		Imgorigin =>
			outimg = wmctxt.images;
			sendimg = nil;
		}

		alt{
		outkbd <-= key =>
			kbdq.get();
		outptr <-= ptr =>
			ptrq.get();
		outctl <-= ctl =>
			ctlq.get();
		outimg <-= sendimg =>
			case imgstate{
			Imgsend =>
				imgstate = Imgnone;
				img = sendimg = nil;
			Imgsendnil1 =>
				imgstate = Imgsendnil2;
			Imgsendnil2 =>
				imgstate = Imgnone;
			Imgorigin =>
				if(img.origin(imgorigin, imgorigin) == -1){
					# XXX what can we do about this? there's no way at the moment
					# of getting the information about the origin failure back to the wm,
					# so we end up with an inconsistent window position.
					# if the window manager blocks while we got the sync from
					# the client, then a client could block the whole window manager
					# which is what we're trying to avoid.
					# but there's no other time we could set the origin of the window,
					# and not risk mucking up the window contents.
					# the short answer is that running out of image space is Bad News.
				}
				imgstate = Imgsend;
			}

		# XXX could mark the application as unresponding if any of these queues
		# start growing too much.
		ch := <-c.kbd =>
			kbdq.put(ch);
		p := <-c.ptr =>
			if(p == nil)
				ptrq.flush();
			else
				ptrq.put(p);
		e := <-c.ctl =>
			ctlq.put(e);
		(o, i, reply) := <-c.images =>
			# can't queue multiple image requests.
			if(imgstate != Imgnone)
				reply <-= -1;
			else {
				# if the origin is being set, then we first send a nil image
				# to indicate that this is happening, and then the
				# image itself (reorigined).
				# if a nil image is being set, then we
				# send nil twice.
				if(o != nil){
					imgorigin = *o;
					imgstate = Imgorigin;
					img = i;
				}else if(i != nil){
					img = i;
					imgstate = Imgsend;
				}else
					imgstate = Imgsendnil1;
				reply <-= 0;
			}
		<-c.stop =>
			# XXX do we need to unblock channels, kill, etc.?
			# we should perhaps drain the ctl output channel here
			# if possible, exiting if it times out.
			exit;
		}
	}
}

findfid(clients: array of ref Client, fid: int): ref Client
{
	for(i := 0; i < len clients; i++)
		if(clients[i] != nil && clients[i].fid == fid)
			return clients[i];
	return nil;
}

addclient(clients: array of ref Client, c: ref Client): array of ref Client
{
	for(i := 0; i < len clients; i++)
		if(clients[i] == nil){
			clients[i] = c;
			c.id = i;
			return clients;
		}
	nc := array[len clients + 4] of ref Client;
	nc[0:] = clients;
	nc[len clients] = c;
	c.id = len clients;
	return nc;
}

delclient(clients: array of ref Client, c: ref Client)
{
	clients[c.id] = nil;
}

senderror(rc: chan of (string, ref Wmcontext), e: string)
{
	rc <-= (e, nil);
}

Client.window(c: self ref Client, tag: string): ref Window
{
	for (w := c.wins; w != nil; w = tl w)
		if((hd w).tag == tag)
			return hd w;
	return nil;
}

Client.image(c: self ref Client, tag: string): ref Draw->Image
{
	w := c.window(tag);
	if(w != nil)
		return w.img;
	return nil;
}

Client.setimage(c: self ref Client, tag: string, img: ref Draw->Image): int
{
	# if img is nil, remove window from list.
	if(img == nil){
		# usual case:
		if(c.wins != nil && (hd c.wins).tag == tag){
			c.wins = tl c.wins;
			return -1;
		}
		nw: list of ref Window;
		for (w := c.wins; w != nil; w = tl w)
			if((hd w).tag != tag)
				nw = hd w :: nw;
		c.wins = nil;
		for(; nw != nil; nw = tl nw)
			c.wins = hd nw :: c.wins;
		return -1;
	}
	for(w := c.wins; w != nil; w = tl w)
		if((hd w).tag == tag)
			break;
	win: ref Window;
	if(w != nil)
		win = hd w;
	else{
		win = ref Window(tag, ZR, nil);
		c.wins = win :: c.wins;
	}
	win.img = img;
	win.r = img.r;			# save so clients can set logical origin
	rc := chan of int;
	c.images <-= (nil, img, rc);
	return <-rc;
}

# tell a client about a window that's moved to screen coord o.
Client.setorigin(c: self ref Client, tag: string, o: Draw->Point): int
{
	w := c.window(tag);
	if(w == nil)
		return -1;
	img := w.img;
	if(img == nil)
		return -1;
	rc := chan of int;
	c.images <-= (ref o, w.img, rc);
	if(<-rc != -1){
		w.r = (o, o.add(img.r.size()));
		return 0;
	}
	return -1;
}

clientimages(c: ref Client): array of ref Image
{
	a := array[len c.wins] of ref Draw->Image;
	i := 0;
	for(w := c.wins; w != nil; w = tl w)
		if((hd w).img != nil)
			a[i++] = (hd w).img;
	return a[0:i];
}

Client.top(c: self ref Client)
{
	imgs := clientimages(c);
	if(len imgs > 0)
		imgs[0].screen.top(imgs);

	if(zorder == c)
		return;

	prev: ref Client;
	for(z := zorder; z != nil; (prev, z) = (z, z.znext))
		if(z == c)
			break;
	if(prev != nil)
		prev.znext = c.znext;
	c.znext = zorder;
	zorder = c;
}

Client.bottom(c: self ref Client)
{
	if(c.znext == nil)
		return;
	imgs := clientimages(c);
	if(len imgs > 0)
		imgs[0].screen.bottom(imgs);
	prev: ref Client;
	for(z := zorder; z != nil; (prev, z) = (z, z.znext))
		if(z == c)
			break;
	if(prev != nil)
		prev.znext = c.znext;
	else
		zorder = c.znext;
	z = c.znext;
	c.znext = nil;
	for(; z != nil; (prev, z) = (z, z.znext))
		;
	if(prev != nil)
		prev.znext = c;
	else
		zorder = c;
}

Client.hide(nil: self ref Client)
{
}

Client.unhide(nil: self ref Client)
{
}

Client.remove(c: self ref Client)
{
	prev: ref Client;
	for(z := zorder; z != nil; (prev, z) = (z, z.znext))
		if(z == c)
			break;
	if(z == nil)
		return;
	if(prev != nil)
		prev.znext = z.znext;
	else if(z != nil)
		zorder = zorder.znext;
}

find(p: Draw->Point): ref Client
{
	for(z := zorder; z != nil; z = z.znext)
		if(z.contains(p))
			return z;
	return nil;
}

top(): ref Client
{
	return zorder;
}

Client.contains(c: self ref Client, p: Point): int
{
	for(w := c.wins; w != nil; w = tl w)
		if((hd w).r.contains(p))
			return 1;
	return 0;
}

r2s(r: Rect): string
{
	return string r.min.x + " " + string r.min.y + " " +
			string r.max.x + " " + string r.max.y;
}

newwmcontext(): ref Wmcontext
{
	return ref Wmcontext(
		chan of int,
		chan of ref Pointer,
		chan of string,
		nil,
		chan of ref Image,
		nil,
		nil
	);
}

Iqueue.put(q: self ref Iqueue, s: int)
{
	q.t = s :: q.t;
}
Iqueue.get(q: self ref Iqueue): int
{
	s := -1;
	if(q.h == nil){
		for(t := q.t; t != nil; t = tl t)
			q.h = hd t :: q.h;
		q.t = nil;
	}
	if(q.h != nil){
		s = hd q.h;
		q.h = tl q.h;
	}
	return s;
}
Iqueue.peek(q: self ref Iqueue): int
{
	s := -1;
	if (q.h == nil && q.t == nil)
		return s;
	s = q.get();
	q.h = s :: q.h;
	return s;
}
Iqueue.nonempty(q: self ref Iqueue): int
{
	return q.h != nil || q.t != nil;
}


Squeue.put(q: self ref Squeue, s: string)
{
	q.t = s :: q.t;
}
Squeue.get(q: self ref Squeue): string
{
	s: string;
	if(q.h == nil){
		for(t := q.t; t != nil; t = tl t)
			q.h = hd t :: q.h;
		q.t = nil;
	}
	if(q.h != nil){
		s = hd q.h;
		q.h = tl q.h;
	}
	return s;
}
Squeue.peek(q: self ref Squeue): string
{
	s: string;
	if (q.h == nil && q.t == nil)
		return s;
	s = q.get();
	q.h = s :: q.h;
	return s;
}
Squeue.nonempty(q: self ref Squeue): int
{
	return q.h != nil || q.t != nil;
}

Ptrqueue.put(q: self ref Ptrqueue, s: ref Pointer)
{
	if(q.last != nil && s.buttons == q.last.buttons)
		*q.last = *s;
	else{
		q.t = s :: q.t;
		q.last = s;
	}
}
Ptrqueue.get(q: self ref Ptrqueue): ref Pointer
{
	s: ref Pointer;
	h := q.h;
	if(h == nil){
		for(t := q.t; t != nil; t = tl t)
			h = hd t :: h;
		q.t = nil;
	}
	if(h != nil){
		s = hd h;
		h = tl h;
		if(h == nil)
			q.last = nil;
	}
	q.h = h;
	return s;
}
Ptrqueue.peek(q: self ref Ptrqueue): ref Pointer
{
	s: ref Pointer;
	if (q.h == nil && q.t == nil)
		return s;
	t := q.last;
	s = q.get();
	q.h = s :: q.h;
	q.last = t;
	return s;
}
Ptrqueue.nonempty(q: self ref Ptrqueue): int
{
	return q.h != nil || q.t != nil;
}
Ptrqueue.flush(q: self ref Ptrqueue)
{
	q.h = q.t = nil;
}
