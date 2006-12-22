implement Wbserve;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Chans, Display, Image, Rect, Point : import draw;

Wbserve : module {
	init : fn (ctxt : ref Draw->Context, args : list of string);
};

WBW : con 600;
WBH : con 400;

savefile := "";

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	if (draw == nil)
		badmod(Draw->PATH);

	if (args == nil || tl args == nil)
		error("usage: wbsrv mntpt [savefile]");
	args = tl args;
	mntpt := hd args;
	args = tl args;

	display := Display.allocate(nil);
	if (display == nil)
		error(sys->sprint("cannot allocate display: %r"));

	bg: ref Draw->Image;
	if (args != nil) {
		savefile = hd args;
		bg = display.open(savefile);
	}
	r := Rect(Point(0,0), Point(WBW, WBH));
	wb := display.newimage(r, Draw->CMAP8, 0, Draw->White);
	if (wb == nil)
		error(sys->sprint("cannot allocate whiteboard image: %r"));
	if (bg != nil) {
		wb.draw(bg.r, bg, nil, Point(0,0));
		bg = nil;
	}

	nextmsg = ref Msg (nil, nil);

	sys->bind("#s", mntpt, Sys->MBEFORE);

	bit := sys->file2chan(mntpt, "wb.bit");
	strokes := sys->file2chan(mntpt, "strokes");

	spawn srv(wb, bit, strokes);
	if (savefile != nil)
		spawn saveit(display, wb);
}

srv(wb: ref Image, bit, strokes: ref Sys->FileIO)
{
	nwbbytes := draw->bytesperline(wb.r, wb.depth) * wb.r.dy();
	bithdr := sys->aprint("%11s %11d %11d %11d %11d ", wb.chans.text(), 0, 0, WBW, WBH);

	for (;;) alt {
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

pencol: int;
pen: ref Image;

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
	if (pen == nil || colour != pencol) {
		pencol = colour;
		pen = wb.display.newimage(Rect(Point(0,0), Point(1,1)), Draw->CMAP8, 1, pencol);
	}
	p0 := Point(x, y);
	while (toks != nil) {
		(x, toks) = (int hd toks, tl toks);
		(y, toks) = (int hd toks, tl toks);
		p1 := Point(x, y);
		# could use poly() instead of line()
		wb.line(p0, p1, Draw->Enddisc, Draw->Enddisc, width, pen, pen.r.min);
		p0 = p1;
	}
	return nil;
}

error(e: string)
{
	sys->fprint(stderr(), "wbsrv: %s\n", e);
	raise "fail:error";
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

badmod(path: string)
{
	sys->fprint(stderr(), "wbsrv: cannot load %s: %r\n", path);
	exit;
}

saveit(display: ref Display, img: ref Image)
{
	for (;;) {
		sys->sleep(300000);
		fd := sys->open(savefile, sys->OWRITE);
		if (fd == nil)
			exit;
		display.writeimage(fd, img);
	}
}