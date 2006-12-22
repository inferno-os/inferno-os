implement Service;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Chans, Display, Image, Rect, Point : import draw;

include "../service.m";

WBW : con 234;
WBH : con 279;

init(nil : list of string) : (string, string, ref Sys->FD)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	if (draw == nil)
		return ("cannot load Draw module", nil, nil);

	p := array [2] of ref Sys->FD;
	if (sys->pipe(p) == -1)
		return (sys->sprint("cannot create pipe: %r"), nil, nil);

	display := Display.allocate(nil);
	if (display == nil)
		return (sys->sprint("cannot allocate display: %r"), nil, nil);

	r := Rect(Point(0,0), Point(WBW, WBH));
	wb := display.newimage(r, Draw->CMAP8, 0, Draw->White);
	if (wb == nil)
		return (sys->sprint("cannot allocate whiteboard image: %r"), nil, nil);

	nextmsg = ref Msg (nil, nil);
	spawn wbsrv(p[1], wb);
	return (nil, "/chan", p[0]);
}

wbsrv(fd : ref Sys->FD, wb: ref Image)
{
	sys->pctl(Sys->FORKNS, nil);
	sys->unmount(nil, "/chan");
	sys->bind("#s", "/chan", Sys->MREPL);

	bit := sys->file2chan("/chan", "wb.bit");
	strokes := sys->file2chan("/chan", "strokes");
	
	hangup := chan of int;
	spawn export(fd, hangup);

	nwbbytes := draw->bytesperline(wb.r, wb.depth) * wb.r.dy();
	bithdr := sys->aprint("%11s %11d %11d %11d %11d ", wb.chans.text(), 0, 0, WBW, WBH);

	for (;;) alt {
	<-hangup =>
		sys->print("whiteboard:hangup\n");
		return;
		
	(offset, count, fid, r) := <-bit.read =>
		if (r == nil) {
			closeclient(fid);
			continue;
		}
		c := getclient(fid);
		if (c == nil) {
			# new client
			c = newclient(fid);
			data := array [len bithdr + nwbbytes] of byte;
			data[0:] = bithdr;
			wb.readpixels(wb.r, data[len bithdr:]);
			c.bitdata = data;
		}
		if (offset >= len c.bitdata) {
			rreply(r, (nil, nil));
			continue;
		}
		rreply(r, (c.bitdata[offset:], nil));

	(offset, data, fid, w) := <-bit.write =>
		if (w != nil)
			wreply(w, (0, "permission denied"));

	(offset, count, fid, r) := <-strokes.read =>
		if (r == nil) {
			closeclient(fid);
			continue;
		}
		c := getclient(fid);
		if (c == nil) {
			c = newclient(fid);
			c.nextmsg = nextmsg;
		}
		d := c.nextmsg.data;
		if (d == nil) {
			c.pending = r;
			c.pendlen = count;
			continue;
		}
		c.nextmsg = c.nextmsg.next;
		rreply(r, (d, nil));

	(offset, data, fid, w) := <-strokes.write =>
		if (w == nil) {
			closeclient(fid);
			continue;
		}
		err := drawstrokes(wb, data);
		if (err != nil) {
			wreply(w, (0, err));
			continue;
		}
		wreply(w, (len data, nil));
		writeclients(data);
	}
}

rreply(rc: chan of (array of byte, string), reply: (array of byte, string))
{
	alt {
	rc <-= reply =>;
	* =>;
	}
}

wreply(wc: chan of (int, string), reply: (int, string))
{
	alt {
	wc <-= reply=>;
	* =>;
	}
}

export(fd : ref Sys->FD, done : chan of int)
{
	sys->export(fd, "/", Sys->EXPWAIT);
	done <-= 1;
}

Msg : adt {
	data : array of byte;
	next : cyclic ref Msg;
};

Client : adt {
	fid : int;
	bitdata : array of byte;		# bit file client
	nextmsg : ref Msg;			# strokes file client
	pending : Sys->Rread;
	pendlen : int;
};

nextmsg : ref Msg;
clients : list of ref Client;

newclient(fid : int) : ref Client
{
	c := ref Client(fid, nil, nil, nil, 0);
	clients = c :: clients;
	return c;
}

getclient(fid : int) : ref Client
{
	for(cl := clients; cl != nil; cl = tl cl)
		if((c := hd cl).fid == fid)
			return c;
	return nil;
}

closeclient(fid : int)
{
	nl: list of ref Client;
	for(cl := clients; cl != nil; cl = tl cl)
		if((hd cl).fid != fid)
			nl = hd cl :: nl;
	clients = nl;
}

writeclients(data : array of byte)
{
	nm := ref Msg(nil, nil);
	nextmsg.data = data;
	nextmsg.next = nm;

	for(cl := clients; cl != nil; cl = tl cl){
		if ((c := hd cl).pending != nil) {
			n := c.pendlen;
			if (n > len data)
				n = len data;
			alt{
			c.pending <-= (data[0:n], nil) => ;
			* => ;
			}
			c.pending = nil;
			c.nextmsg = nm;
		}
	}
	nextmsg = nm;
}

# data: colour width p0 p1 pn*

drawstrokes(wb: ref Image, data : array of byte) : string
{
	(n, toks) := sys->tokenize(string data, " ");
	if (n < 6 || n & 1)
		return "bad data";

	colour, width, x, y : int;
	(colour, toks) = (int hd toks, tl toks);
	(width, toks) = (int hd toks, tl toks);
	(x, toks) = (int hd toks, tl toks);
	(y, toks) = (int hd toks, tl toks);
	pen := wb.display.newimage(Rect(Point(0,0), Point(1,1)), Draw->CMAP8, 1, colour);
	p0 := Point(x, y);
	while (toks != nil) {
		(x, toks) = (int hd toks, tl toks);
		(y, toks) = (int hd toks, tl toks);
		p1 := Point(x, y);
		# could use poly() instead of line()
		wb.line(p0, p1, Draw->Endsquare, Draw->Endsquare, width, pen, pen.r.min);
		p0 = p1;
	}
	return nil;
}
