implement Drawmux;

include "sys.m";
include "draw.m";
include "drawmux.m";

include "drawoffs.m";

sys : Sys;
draw : Draw;

Display, Point, Rect, Chans : import draw;

Ehungup : con "Hangup";

drawR: Draw->Rect;
drawchans: Draw->Chans;
drawop := Draw->SoverD;
drawfd: ref Sys->FD;
images: ref Imageset;
screens: ref Screenset;
viewers: list of ref Viewer;
drawlock: chan of chan of int;
readdata: array of byte;
nhangups := 0;
prevnhangups := 0;

init() : (string, ref Draw->Display)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;

	if (draw == nil)
		return (sys->sprint("cannot load %s: %r", Draw->PATH), nil);
	drawlock = chan of chan of int;
	images = Imageset.new();
	screens = Screenset. new();
	res := chan of (string, ref Draw->Display);
	spawn getdisp(res);
	r := <- res;
	return r;
}

newviewer(fd : ref Sys->FD)
{
	reply := array of byte sys->sprint("%.11d %.11d ", drawR.max.x - drawR.min.x, drawR.max.y - drawR.min.y);
	if (sys->write(fd, reply, len reply) != len reply) {
#		sys->print("viewer hangup\n");
		return;
	}

	buf := array [Sys->ATOMICIO] of byte;
	n := sys->read(fd, buf, len buf);
	if (n < 24)
		return;
	pubscr := int string buf[0:12];
	chans := Chans.mk(string buf[12:24]);

	sys->pctl(Sys->FORKNS, nil);
	sys->mount(fd, nil, "/", Sys->MREPL, nil);
	cfd := sys->open("/new", Sys->OREAD);
	sys->read(cfd, buf, len buf);
	cnum := int string buf[0:12];
	cdata := sys->sprint("/%d/data", cnum);
	datafd := sys->open(cdata, Sys->ORDWR);

	if (datafd == nil) {
#		sys->print("cannot open viewer data file: %r\n");
		return;
	}
	Viewer.new(datafd, pubscr, chans);
}

getdisp(result : chan of (string, ref Draw->Display))
{	
	sys->pctl(Sys->FORKNS, nil);
	sys->bind("#i", "/dev", Sys->MREPL);
	sys->bind("#s", "/dev/draw", Sys->MBEFORE);
	newio := sys->file2chan("/dev/draw", "new");
	if (newio == nil) {
		result <- = ("cannot create /dev/new file2chan", nil);
		return;
	}
	spawn srvnew(newio);
	disp := Display.allocate(nil);
	if (disp == nil) {
		result <-= (sys->sprint("%r"), nil);
		return;
	}
	
	draw->disp.image.draw(disp.image.r, disp.rgb(0,0,0), nil, Point(0,0));
	result <- = (nil, disp);
}

srvnew(newio : ref Sys->FileIO)
{
	for (;;) alt {
	(offset, count, fid, rc) := <- newio.read =>
		if (rc != nil) {
			c := chan of (string, ref Sys->FD);
			fd := sys->open("#i/draw/new", Sys->OREAD);
			# +1 because of a sprint() nasty in devdraw.c
			buf := array [(12 * 12)+1] of byte;
			nn := sys->read(fd, buf, len buf);
			cnum := int string buf[0:12];
			drawchans = Chans.mk(string buf[24:36]);
			# repl is at [36:48]
			drawR.min.x = int string buf[48:60];
			drawR.min.y = int string buf[60:72];
			drawR.max.x = int string buf[72:84];
			drawR.max.y = int string buf[84:96];

			bwidth := bytesperline(drawR, drawchans);
			img := ref Image (0, 0, 0, 0, drawchans, 0, drawR, drawR, Draw->Black, nil, drawR.min, bwidth, 0, "");
			images.add(0, img);

			cdir := sys->sprint("/dev/draw/%d", cnum);
			dpath := sys->sprint("#i/draw/%d/data", cnum);
			drawfd = sys->open(dpath, Sys->ORDWR);
			fd = nil;
			if (drawfd == nil) {
				rc <-= (nil, sys->sprint("%r"));
				return;
			}
			sys->bind("#s", cdir, Sys->MBEFORE);
			drawio := sys->file2chan(cdir, "data");
			spawn drawclient(drawio);
			rc <- = (buf, nil);
			return;
		}
	(offset, data, fid, wc) := <- newio.write =>
		if (wc != nil)
			writereply(wc, (0, "permission denied"));
	}
}

# for simplicity make the file 'exclusive use'
drawclient(drawio : ref Sys->FileIO)
{
	activefid := -1;
	closecount := 2;

	for (;closecount;) {
		alt {
		unlock := <- drawlock =>
			<- unlock;
	
		(offset, count, fid, rc) := <- drawio.read =>
				if (activefid == -1)
					activefid = fid;
	
				if (rc == nil) {
					closecount--;
					continue;
				}
				if (fid != activefid) {
					rc <-= (nil, "file busy");
					continue;
				}
				if (readdata == nil) {
					rc <-= (nil, nil);
					continue;
				}
				if (count > len readdata)
					count = len readdata;
				rc <- = (readdata[0:count], nil);
				readdata = nil;
	
		(offset, data, fid, wc) := <- drawio.write =>
			if (wc == nil) {
				closecount--;
				continue;
			}
			writereply(wc, process(data));
		}
		if (nhangups != prevnhangups) {
			ok : list of ref Viewer;
			for (ok = nil; viewers != nil; viewers = tl viewers) {
				v := hd viewers;
				if (!v.hungup)
					ok = v :: ok;
				else {
#					sys->print("shutting down Viewer\n");
					v.output <- = (nil, nil);
				}
			}
			viewers = ok;
			prevnhangups = nhangups;
		}
	}
#	sys->print("DRAWIO DONE!\n");
}

writereply(wc : chan of (int, string), val : (int, string))
{
	alt {
	wc <-= val =>
		;
	* =>
		;
	}
}

Image: adt {
	id: int;
	refc: int;
	screenid: int;
	refresh: int;
	chans: Draw->Chans;
	repl: int;
	R: Draw->Rect;
	clipR: Draw->Rect;
	rrggbbaa: int;
	font: ref Font;
	lorigin: Draw->Point;
	bwidth: int;
	dirty: int;
	name: string;
};

Screen: adt {
	id: int;
	imageid: int;
	fillid: int;
	windows: array of int;

	setz: fn (s: self ref Screen, z: array of int, top: int);
	addwin: fn (s: self ref Screen, wid: int);
	delwin: fn (s: self ref Screen, wid: int);
};

Font: adt {
	ascent: int;
	chars: array of ref Fontchar;
};

Fontchar: adt {
	srcid: int;
	R: Draw->Rect;
	P: Draw->Point;
	left: int;
	width: int;
};

Idpair: adt {
	key: int;
	val: int;
	next: cyclic ref Idpair;
};

Idmap: adt {
	buckets: array of ref Idpair;

	new: fn (): ref Idmap;
	add: fn (m: self ref Idmap, key, val: int);
	del: fn (m: self ref Idmap, key: int);
	lookup: fn (m: self ref Idmap, key: int): int;
};

Imageset: adt {
	images: array of ref Image;
	ixmap: ref Idmap;
	freelist: list of int;
	new: fn (): ref Imageset;
	add: fn (s: self ref Imageset, id: int, img: ref Image);
	del: fn (s: self ref Imageset, id: int);
	lookup: fn (s: self ref Imageset, id: int): ref Image;
	findname: fn(s: self ref Imageset, name: string): ref Image;
};

Screenset: adt {
	screens: array of ref Screen;
	ixmap: ref Idmap;
	freelist: list of int;
	new: fn (): ref Screenset;
	add: fn (s: self ref Screenset, scr: ref Screen);
	del: fn (s: self ref Screenset, id: int);
	lookup: fn (s: self ref Screenset, id: int): ref Screen;
};


Drawreq: adt {
	data: array of byte;
	pick {
#	a =>	# allocate image
#		id: int;
#		screenid: int;
#		refresh: int;
#		ldepth: int;
#		repl: int;
#		R: Draw->Rect;
#		clipR: Draw->Rect;
#		value: int;
	b =>	# new allocate image
		id: int;
		screenid: int;
		refresh: int;
		chans: Draw->Chans;
		repl: int;
		R: 	Draw->Rect;
		clipR: Draw->Rect;
		rrggbbaa: int;
	A => # allocate screen
		id: int;
		imageid: int;
		fillid: int;
	c => # set clipr and repl
		dstid: int;
		repl: int;
		clipR: Draw->Rect;
#	x => # move cursor
#	C => # set cursor image and hotspot
#		_: int;
	d => # general draw op
		dstid: int;
		srcid: int;
		maskid: int;
	D => # debug mode
		_: int;
	e => # draw ellipse
		dstid: int;
		srcid: int;
	f => # free image
		id: int;
		img: ref Image;	# helper for Viewers
	F =>	 # free screen
		id: int;
	i => # convert image to font
		fontid: int;
		nchars: int;
		ascent: int;
	l => # load a char into font
		fontid: int;
		srcid: int;
		index: int;
		R: Draw->Rect;
		P: Draw->Point;
		left: int;
		width: int;
	L => # draw line
		dstid: int;
		srcid: int;
	n =>	# attach to named image
		dstid: int;
		name: string;
	N => # name image
		dstid: int;
		in: int;
		name: string;
	o =>	# set window origins
		id: int;
		rmin: Draw->Point;
		screenrmin: Draw->Point;
	O => # set next compositing op
		op: int;
	p =>	# draw polygon
		dstid: int;
		srcid: int;
	r =>	# read pixels
		id: int;
		R: Draw->Rect;
	s =>	# draw text
		dstid: int;
		srcid: int;
		fontid: int;
	x => # draw text with bg
		dstid: int;
		srcid: int;
		fontid: int;
		bgid: int;
	S =>	# import public screen
	t =>	# adjust window z order
		top: int;
		ids: array of int;
	v =>	 # flush updates to display
	y =>	# write pixels
		id: int;
		R: Draw->Rect;
	}
};

getreq(data : array of byte, ix : int) : (ref Drawreq, string)
{
	mlen := 0;
	err := "short draw message";
	req : ref Drawreq;

	case int data[ix] {
	'b' => # alloc image
		mlen = 1+4+4+1+4+1+(4*4)+(4*4)+4;
		if (mlen+ix <= len data) {
			data = data[ix:ix+mlen];
			r := ref Drawreq.b;
			r.data = data;
			r.id = get4(data, OPb_id);
			r.screenid = get4(data, OPb_screenid);
			r.refresh = get1(data, OPb_refresh);
			r.chans = Draw->Chans(get4(data, OPb_chans));
			r.repl = get1(data, OPb_repl);
			r.R = getR(data, OPb_R);
			r.clipR = getR(data, OPb_clipR);
			r.rrggbbaa = get4(data, OPb_rrggbbaa);
			req = r;
		}
	'A' => # alloc screen
		mlen = 1+4+4+4+1;
		if (mlen+ix <= len data) {
			data = data[ix:ix+mlen];
			r := ref Drawreq.A;
			r.data = data;
			r.id = get4(data, OPA_id);
			r.imageid = get4(data, OPA_imageid);
			r.fillid = get4(data, OPA_fillid);
			req = r;
		}
	'c' => # set clipR
		mlen = 1+4+1+(4*4);
		if (mlen+ix <= len data) {
			data = data[ix:ix+mlen];
			r := ref Drawreq.c;
			r.data = data;
			r.dstid = get4(data, OPc_dstid);
			r.repl = get1(data, OPc_repl);
			r.clipR = getR(data, OPc_clipR);
			req = r;
		}
	'd' => # draw
		mlen = 1+4+4+4+(4*4)+(2*4)+(2*4);
		if (mlen+ix <= len data) {
			data = data[ix:ix+mlen];
			r := ref Drawreq.d;
			r.data = data;
			r.dstid = get4(data, OPd_dstid);
			r.srcid = get4(data, OPd_srcid);
			r.maskid = get4(data, OPd_maskid);
			req = r;
		}
	'D' =>
		# debug mode
		mlen = 1+1;
		if (mlen+ix <= len data) {
			req = ref Drawreq.v;
			req.data = data[ix:ix+mlen];
		}
	'e' or
	'E' => # ellipse
		mlen = 1+4+4+(2*4)+4+4+4+(2*4)+4+4;
		if (mlen+ix <= len data) {
			data = data[ix:ix+mlen];
			r := ref Drawreq.e;
			r.data = data;
			r.dstid = get4(data, OPe_dstid);
			r.srcid = get4(data, OPe_srcid);
			req = r;
		}
	'f' => # free image
		mlen = 1+4;
		if (mlen+ix <= len data) {
			data = data[ix:ix+mlen];
			r := ref Drawreq.f;
			r.data = data;
			r.id = get4(data, OPf_id);
			req = r;
		}
	'F' => # free screen
		mlen = 1+4;
		if (mlen+ix <= len data) {
			data = data[ix:ix+mlen];
			r := ref Drawreq.f;
			r.data = data;
			r.id = get4(data, OPF_id);
			req = r;
		}
	'i' =>	 # alloc font
		mlen = 1+4+4+1;
		if (mlen+ix <= len data) {
			data = data[ix:ix+mlen];
			r := ref Drawreq.i;
			r.data = data;
			r.fontid = get4(data, OPi_fontid);
			r.nchars = get4(data, OPi_nchars);
			r.ascent = get1(data, OPi_ascent);
			req = r;
		}
	'l' =>	 # load font char
		mlen = 1+4+4+2+(4*4)+(2*4)+1+1;
		if (mlen+ix <= len data) {
			data = data[ix:ix+mlen];
			r := ref Drawreq.l;
			r.data = data;
			r.fontid = get4(data, OPl_fontid);
			r.srcid = get4(data, OPl_srcid);
			r.index = get2(data, OPl_index);
			r.R = getR(data, OPl_R);
			r.P = getP(data, OPl_P);
			r.left = get1(data, OPl_left);
			r.width = get1(data, OPl_width);
			req = r;
		}
	'L' => # line
		mlen = 1+4+(2*4)+(2*4)+4+4+4+4+(2*4);
		if (mlen+ix <= len data) {
			data = data[ix:ix+mlen];
			r := ref Drawreq.L;
			r.data = data;
			r.dstid = get4(data, OPL_dstid);
			r.srcid = get4(data, OPL_srcid);
			req = r;
		}
	'n' => # attach to named image
		mlen = 1+4+1;
		if (mlen+ix < len data) {
			mlen += get1(data, ix+OPn_j);
			if (mlen+ix <= len data) {
				data = data[ix:ix+mlen];
				r := ref Drawreq.n;
				r.data = data;
				r.dstid = get4(data, OPn_dstid);
				r.name = string data[OPn_name:];
				req = r;
			}
		}
	'N' => # name image
		mlen = 1+4+1+1;
		if (mlen+ix < len data) {
			mlen += get1(data, ix+OPN_j);
			if (mlen+ix <= len data) {
				data = data[ix:ix+mlen];
				r := ref Drawreq.N;
				r.data = data;
				r.dstid = get4(data, OPN_dstid);
				r.in = get1(data, OPN_in);
				r.name = string data[OPN_name:];
				req = r;
			}
		}
	'o' => # set origins
		mlen = 1+4+(2*4)+(2*4);
		if (mlen+ix <= len data) {
			data = data[ix:ix+mlen];
			r := ref Drawreq.o;
			r.data = data;
			r.id = get4(data, OPo_id);
			r.rmin = getP(data, OPo_rmin);
			r.screenrmin = getP(data, OPo_screenrmin);
			req = r;
		}
	'O' => # set next compop
		mlen = 1+1;
		if (mlen+ix <= len data) {
			data = data[ix:ix+mlen];
			r := ref Drawreq.O;
			r.data = data;
			r.op = get1(data, OPO_op);
			req = r;
		}
	'p' or
	'P' => # polygon
		mlen = 1+4+2+4+4+4+4+(2*4);
		if (mlen + ix <= len data) {
			n := get2(data, ix+OPp_n);
			nb := coordslen(data, ix+OPp_P0, 2*(n+1));
			if (nb == -1)
				err = "bad coords";
			else {
				mlen += nb;
				if (mlen+ix <= len data) {
					data = data[ix:ix+mlen];
					r := ref Drawreq.p;
					r.data = data;
					r.dstid = get4(data, OPp_dstid);
					r.srcid = get4(data, OPp_srcid);
					req = r;
				}
			}
		}
	'r' =>	 # read pixels
		mlen = 1+4+(4*4);
		if (mlen+ix <= len data) {
			data = data[ix:ix+mlen];
			r := ref Drawreq.r;
			r.data = data;
			r.id = get4(data, OPr_id);
			r.R = getR(data, OPr_R);
			req = r;
		}
	's' => # text
		mlen = 1+4+4+4+(2*4)+(4*4)+(2*4)+2;
		if (ix+mlen <= len data) {
			ni := get2(data, ix+OPs_ni);
			mlen += (2*ni);
			if (mlen+ix <= len data) {
				data = data[ix:ix+mlen];
				r := ref Drawreq.s;
				r.data = data;
				r.dstid = get4(data, OPs_dstid);
				r.srcid = get4(data, OPs_srcid);
				r.fontid = get4(data, OPs_fontid);
				req = r;
			}
		}
	'x' => # text with bg img
		mlen = 1+4+4+4+(2*4)+(4*4)+(2*4)+2+4+(2*4);
		if (ix+mlen <= len data) {
			ni := get2(data, ix+OPx_ni);
			mlen += (2*ni);
			if (mlen+ix <= len data) {
				data = data[ix:ix+mlen];
				r := ref Drawreq.x;
				r.data = data;
				r.dstid = get4(data, OPx_dstid);
				r.srcid = get4(data, OPx_srcid);
				r.fontid = get4(data, OPx_fontid);
				r.bgid = get4(data, OPx_bgid);
				req = r;
			}
		}
	'S' => # import public screen
		mlen = 1+4+4;
		if (mlen+ix <= len data) {
			data = data[ix:ix+mlen];
			req = ref Drawreq.S;
			req.data = data;
		}
	't' => # adjust window z order
		mlen = 1+1+2;
		if (ix+mlen<= len data) {
			nw := get2(data, ix+OPt_nw);
			mlen += (4*nw);
			if (mlen+ix <= len data) {
				data = data[ix:ix+mlen];
				r := ref Drawreq.t;
				r.data = data;
				r.top = get1(data, OPt_top);
				r.ids = array [nw] of int;
				for (n := 0; n < nw; n++)
					r.ids[n] = get4(data, OPt_id + 4*n);
				req = r;
			}
		}
	'v' => # flush
		req = ref Drawreq.v;
		req.data = data[ix:ix+1];
	'y' or
	'Y' =>	# write pixels
		mlen = 1+4+(4*4);
		if (ix+mlen <= len data) {
			imgid := get4(data, ix+OPy_id);
			img := images.lookup(imgid);
			compd := data[ix] == byte 'Y';
			r := getR(data, ix+OPy_R);
			n := imglen(img, data, ix+mlen, r, compd);
			if (n == -1)
				err ="bad image data";
			mlen += n;
			if (mlen+ix <= len data)
				req = ref Drawreq.y (data[ix:ix+mlen], imgid, r);
		}
	* =>
		err = "bad draw command";
	}

	if (req == nil)
		return (nil, err);
	return (req, nil);
}

process(data : array of byte) : (int, string)
{
	offset := 0;
	while (offset < len data) {
		(req, err) := getreq(data, offset);
		if (err != nil)
			return (0, err);
		offset += len req.data;
		n := sys->write(drawfd, req.data, len req.data);
		if (n <= 0)
			return (n, sys->sprint("[%c] %r", int req.data[0]));

		readn := 0;
		sendtoviews := 1;

		# actions that must be done before sending to Viewers
		pick r := req {
		b =>	# allocate image
			bwidth := bytesperline(r.R, r.chans);
			img := ref Image (r.id, 0, r.screenid, r.refresh, r.chans, r.repl, r.R, r.clipR, r.rrggbbaa, nil, r.R.min, bwidth, 0, "");
			images.add(r.id, img);
			if (r.screenid != 0) {
				scr := screens.lookup(r.screenid);
				scr.addwin(r.id);
			}

		A =>	# allocate screen
			scr := ref Screen (r.id, r.imageid, r.fillid, nil);
			screens.add(scr);
			# we never allocate public screens on our Viewers
			put1(r.data, OPA_public, 0);
			dirty(r.imageid, 0);

		c =>	# set clipr and repl
			img := images.lookup(r.dstid);
			img.repl = r.repl;
			img.clipR = r.clipR;

		d =>	# general draw op
			dirty(r.dstid, 1);
			drawop = Draw->SoverD;

		e =>	# draw ellipse
			dirty(r.dstid, 1);
			drawop = Draw->SoverD;

		f => # free image
			# help out Viewers, real work is done later
			r.img = images.lookup(r.id);

		L =>	# draw line
			dirty(r.dstid, 1);
			drawop = Draw->SoverD;

		n =>	# attach to named image
			img := images.findname(r.name);
			images.add(r.dstid, img);
			
		N => # name image
			img := images.lookup(r.dstid);
			if (r.in)
				img.name = r.name;
			else
				img.name = nil;

		o => # set image origins
			img := images.lookup(r.id);
			deltax := img.lorigin.x - r.rmin.x;
			deltay := img.lorigin.y - r.rmin.y;
			w := img.R.max.x - img.R.min.x;
			h := img.R.max.y - img.R.min.y;
			
			img.R = Draw->Rect(r.screenrmin, (r.screenrmin.x + w, r.screenrmin.y + h));
			img.clipR = Draw->Rect((img.clipR.min.x - deltax, img.clipR.min.y - deltay), (img.clipR.max.x - deltax, img.clipR.max.y - deltay));
			img.lorigin = r.rmin;

		O =>	# set compositing op
			drawop = r.op;

		p =>	# draw polygon
			dirty(r.dstid, 1);
			drawop = Draw->SoverD;

		r => # read pixels
			img := images.lookup(r.id);
			bpl := bytesperline(r.R, img.chans);
			readn = bpl * (r.R.max.y - r.R.min.y);

		s =>	# draw text
			dirty(r.dstid, 1);
			drawop = Draw->SoverD;

		x => # draw text with bg
			dirty(r.dstid, 1);
			drawop = Draw->SoverD;

		t =>	# adjust window z order
			if (r.ids != nil) {
				img := images.lookup(r.ids[0]);
				scr := screens.lookup(img.screenid);
				scr.setz(r.ids, r.top);
			}

		y =>	# write pixels
			dirty(r.id, 1);
		}

		if (readn) {
			rdata := array [readn] of byte;
			if (sys->read(drawfd, rdata, readn) == readn)
				readdata = rdata;
		}

		for (vs := viewers; vs != nil; vs = tl vs) {
			v := hd vs;
			v.process(req);
		}

		# actions that must only be done after sending to Viewers
		pick r := req {
		f => # free image
			img := images.lookup(r.id);
			if (img.screenid != 0) {
				scr := screens.lookup(img.screenid);
				scr.delwin(img.id);
			}
			images.del(r.id);

		F =>	# free screen
			scr := screens.lookup(r.id);
			for (i := 0; i < len scr.windows; i++) {
				img := images.lookup(scr.windows[i]);
				img.screenid = 0;
			}
			screens.del(r.id);

		i => # convert image to font
			img := images.lookup(r.fontid);
			font := ref Font;
			font.ascent = r.ascent;
			font.chars = array[r.nchars] of ref Fontchar;
			img.font = font;

		l =>	# load a char into font
			img := images.lookup(r.fontid);
			font := img.font;
			fc := ref Fontchar(r.srcid, r.R, r.P, r.left, r.width);
			font.chars[r.index] = fc;
		}
	}
	return (offset, nil);
}

coordslen(data : array of byte, ix, n : int) : int
{
	start := ix;
	dlen := len data;
	if (ix == dlen)
		return -1;
	while (ix < dlen && n) {
		n--;
		if ((int data[ix++]) & 16r80)
			ix += 2;
	}
	if (n)
		return -1;
	return ix - start;
}


imglen(i : ref Image, data : array of byte, ix : int, r : Draw->Rect, comp : int) : int
{
	bpl := bytesperline(r, i.chans);
	if (!comp)
		return (r.max.y - r.min.y) * bpl;
	y := r.min.y;
	lineix := byteaddr(i, r.min);
	elineix := lineix+bpl;
	start := ix;
	eix := len data;
	for (;;) {
		if (lineix == elineix) {
			if (++y == r.max.y)
				break;
			lineix = byteaddr(i, Point(r.min.x, y));
			elineix = lineix+bpl;
		}
		if (ix == eix)	# buffer too small
			return -1;
		c := int data[ix++];
		if (c >= 128) {
			for (cnt := c-128+1; cnt != 0; --cnt) {
				if (ix == eix)	# buffer too small
					return -1;
				if (lineix == elineix)	# phase error
					return -1;
				lineix++;
				ix++;
			}
		} else {
			if (ix == eix)	# short buffer
				return -1;
			ix++;
			for (cnt := (c >> 2)+3; cnt != 0; --cnt) {
				if (lineix == elineix) # phase error
					return -1;
				lineix++;
			}
		}
	}
	return ix-start;
}

byteaddr(i: ref Image, p: Point): int
{
	x := p.x - i.lorigin.x;
	y := p.y - i.lorigin.y;
	bits := i.chans.depth();
	if (bits == 0)
		# invalid chans
		return 0;
	return (y*i.bwidth)+(x<<3)/bits;
}

bytesperline(r: Draw->Rect, chans: Draw->Chans): int
{
	d := chans.depth();
	l, t: int;

	if(r.min.x >= 0){
		l = (r.max.x*d+8-1)/8;
		l -= (r.min.x*d)/8;
	}else{			# make positive before divide
		t = (-r.min.x*d+8-1)/8;
		l = t+(r.max.x*d+8-1)/8;
	}
	return l;
}

get1(data : array of byte, ix : int) : int
{
	return int data[ix];
}

put1(data : array of byte, ix, val : int)
{
	data[ix] = byte val;
}

get2(data : array of byte, ix : int) : int
{
	return int data[ix] | ((int data[ix+1]) << 8);
}

put2(data : array of byte, ix, val : int)
{
	data[ix] = byte val;
	data[ix+1] = byte (val >> 8);
}

get4(data : array of byte, ix : int) : int
{
	return int data[ix] | ((int data[ix+1]) << 8) | ((int data[ix+2]) << 16) | ((int data[ix+3]) << 24);
}

put4(data : array of byte, ix, val : int)
{
	data[ix] = byte val;
	data[ix+1] = byte (val >> 8);
	data[ix+2] = byte (val >> 16);
	data[ix+3] = byte (val >> 24);
}

getP(data : array of byte, ix : int) : Draw->Point
{
	x := int data[ix] | ((int data[ix+1]) << 8) | ((int data[ix+2]) << 16) | ((int data[ix+3]) << 24);
	ix += 4;
	y := int data[ix] | ((int data[ix+1]) << 8) | ((int data[ix+2]) << 16) | ((int data[ix+3]) << 24);
	return Draw->Point(x, y);
}

putP(data : array of byte, ix : int, P : Draw->Point)
{
	val := P.x;
	data[ix] = byte val;
	data[ix+1] = byte (val >> 8);
	data[ix+2] = byte (val >> 16);
	data[ix+3] = byte (val >> 24);
	val = P.y;
	ix += 4;
	data[ix] = byte val;
	data[ix+1] = byte (val >> 8);
	data[ix+2] = byte (val >> 16);
	data[ix+3] = byte (val >> 24);
}

getR(data : array of byte, ix : int) : Draw->Rect
{
	minx := int data[ix] | ((int data[ix+1]) << 8) | ((int data[ix+2]) << 16) | ((int data[ix+3]) << 24);
	ix += 4;
	miny := int data[ix] | ((int data[ix+1]) << 8) | ((int data[ix+2]) << 16) | ((int data[ix+3]) << 24);
	ix += 4;
	maxx :=  int data[ix] | ((int data[ix+1]) << 8) | ((int data[ix+2]) << 16) | ((int data[ix+3]) << 24);
	ix += 4;
	maxy :=  int data[ix] | ((int data[ix+1]) << 8) | ((int data[ix+2]) << 16) | ((int data[ix+3]) << 24);
	
	return Draw->Rect(Draw->Point(minx, miny), Draw->Point(maxx, maxy));
}

putR(data : array of byte, ix : int , R : Draw->Rect)
{
	val := R.min.x;
	data[ix] = byte val;
	data[ix+1] = byte (val >> 8);
	data[ix+2] = byte (val >> 16);
	data[ix+3] = byte (val >> 24);
	val = R.min.y;
	ix += 4;
	data[ix] = byte val;
	data[ix+1] = byte (val >> 8);
	data[ix+2] = byte (val >> 16);
	data[ix+3] = byte (val >> 24);
	val = R.max.x;
	ix += 4;
	data[ix] = byte val;
	data[ix+1] = byte (val >> 8);
	data[ix+2] = byte (val >> 16);
	data[ix+3] = byte (val >> 24);
	val = R.max.y;
	ix += 4;
	data[ix] = byte val;
	data[ix+1] = byte (val >> 8);
	data[ix+2] = byte (val >> 16);
	data[ix+3] = byte (val >> 24);
}

dirty(id, v : int)
{
	img := images.lookup(id);
	img.dirty = v;
}

Screen.setz(s : self ref Screen, z : array of int, top : int)
{
	old := s.windows;
	nw := array [len old] of int;
	# use a dummy idmap to ensure uniqueness;
	ids := Idmap.new();
	ix := 0;
	if (top) {
		for (i := 0; i < len z; i++) {
			if (ids.lookup(z[i]) == -1) {
				ids.add(z[i], 0);
				nw[ix++] = z[i];
			}
		}
	}
	for (i := 0; i < len old; i++) {
		if (ids.lookup(old[i]) == -1) {
			ids.add(old[i], 0);
			nw[ix++] = old[i];
		}
	}
	if (!top) {
		for (i = 0; i < len z; i++) {
			if (ids.lookup(z[i]) == -1) {
				ids.add(z[i], 0);
				nw[ix++] = z[i];
			}
		}
	}
	s.windows = nw;
}

Screen.addwin(s : self ref Screen, wid : int)
{
	nw :=  array [len s.windows + 1] of int;
	nw[0] = wid;
	nw[1:] = s.windows;
	s.windows = nw;
}

Screen.delwin(s : self ref Screen, wid : int)
{
	if (len s.windows == 1) {
		# assert s.windows[0] == wid
		s.windows = nil;
		return;
	}
	nw := array [len s.windows - 1] of int;
	ix := 0;
	for (i := 0; i < len s.windows; i++) {
		if (s.windows[i] == wid)
			continue;
		nw[ix++] = s.windows[i];
	}
	s.windows = nw;
}

Idmap.new() : ref Idmap
{
	m := ref Idmap;
	m.buckets = array[256] of ref Idpair;
	return m;
}

Idmap.add(m : self ref Idmap, key, val : int)
{
	h := key & 16rff;
	m.buckets[h] = ref Idpair (key, val, m.buckets[h]);
}

Idmap.del(m : self ref Idmap, key : int)
{
	h := key &16rff;
	prev := m.buckets[h];
	if (prev == nil)
		return;
	if (prev.key == key) {
		m.buckets[h] = m.buckets[h].next;
		return;
	}
	for (idp := prev.next; idp != nil; idp = idp.next) {
		if (idp.key == key)
			break;
		prev = idp;
	}
	if (idp != nil)
		prev.next = idp.next;
}

Idmap.lookup(m :self ref Idmap, key : int) : int
{
	h := key &16rff;
	for (idp := m.buckets[h]; idp != nil; idp = idp.next) {
		if (idp.key == key)
			return idp.val;
	}
	return -1;
}

Imageset.new() : ref Imageset
{
	s := ref Imageset;
	s.images = array [32] of ref Image;
	s.ixmap = Idmap.new();
	for (i := 0; i < len s.images; i++)
		s.freelist = i :: s.freelist;
	return s;
}

Imageset.add(s: self ref Imageset, id: int, img: ref Image)
{
	if (s.freelist == nil) {
		n := 2 * len s.images;
		ni := array [n] of ref Image;
		ni[:] = s.images;
		for (i := len s.images; i < n; i++)
			s.freelist = i :: s.freelist;
		s.images = ni;
	}
	ix := hd s.freelist;
	s.freelist = tl s.freelist;
	s.images[ix] = img;
	s.ixmap.add(id, ix);
	img.refc++;
}

Imageset.del(s: self ref Imageset, id: int)
{
	ix := s.ixmap.lookup(id);
	if (ix == -1)
		return;
	img := s.images[ix];
	if (img != nil)
		img.refc--;
	s.images[ix] = nil;
	s.freelist = ix :: s.freelist;
	s.ixmap.del(id);
}

Imageset.lookup(s : self ref Imageset, id : int ) : ref Image
{
	ix := s.ixmap.lookup(id);
	if (ix == -1)
		return nil;
	return s.images[ix];
}

Imageset.findname(s: self ref Imageset, name: string): ref Image
{
	for (ix := 0; ix < len s.images; ix++) {
		img := s.images[ix];
		if (img != nil && img.name == name)
			return img;
	}
	return nil;
}

Screenset.new() : ref Screenset
{
	s := ref Screenset;
	s.screens = array [32] of ref Screen;
	s.ixmap = Idmap.new();
	for (i := 0; i < len s.screens; i++)
		s.freelist = i :: s.freelist;
	return s;
}

Screenset.add(s : self ref Screenset, scr : ref Screen)
{
	if (s.freelist == nil) {
		n := 2 * len s.screens;
		ns := array [n] of ref Screen;
		ns[:] = s.screens;
		for (i := len s.screens; i < n; i++)
			s.freelist = i :: s.freelist;
		s.screens = ns;
	}
	ix := hd s.freelist;
	s.freelist = tl s.freelist;
	s.screens[ix] = scr;
	s.ixmap.add(scr.id, ix);
}

Screenset.del(s : self ref Screenset, id : int)
{
	ix := s.ixmap.lookup(id);
	if (ix == -1)
		return;
	s.screens[ix] = nil;
	s.freelist = ix :: s.freelist;
	s.ixmap.del(id);
}

Screenset.lookup(s : self ref Screenset, id : int ) : ref Screen
{
	ix := s.ixmap.lookup(id);
	if (ix == -1)
		return nil;
	return s.screens[ix];
}


Viewer : adt {
	imgmap:	ref Idmap;
	scrmap:	ref Idmap;
	chanmap:	ref Idmap;	# maps to 1 for images that require chan conversion

	imageid:	int;
	screenid:	int;
	whiteid:	int;
	hungup:	int;
	dchans:	Draw->Chans;	# chans.desc of remote display img

	# temporary image for chan conversion
	tmpid:	int;
	tmpR:	Draw->Rect;

	output:	chan of (array of byte, chan of string);

	new:		fn(fd: ref Sys->FD, pubscr: int, chans: Draw->Chans): string;
	process:	fn(v: self ref Viewer, req: ref Drawreq);
	getimg:	fn(v: self ref Viewer, id: int): int;
	getscr:	fn(v: self ref Viewer, id, win: int): (int, int);
	copyimg:	fn(v: self ref Viewer, img: ref Image, id: int);
	chanconv:	fn(v: self ref Viewer, img: ref Image, id: int, r: Rect, ymsg: array of byte);
};

vwriter(fd : ref Sys->FD, datac : chan of array of byte, nc : chan of string)
{
	for (;;) {
		data := <- datac;
		if (data == nil)
			return;
		n := sys->write(fd, data, len data);
		if (n != len data) {
#			sys->print("[%c]: %r\n", int data[0]);
#			sys->print("[%c] datalen %d got %d error: %r\n", int data[0], len data, n);
			nc <-= sys->sprint("%r");
		} else {
#			sys->print("[%c]", int data[0]);
			nc <-= nil;
		}
	}
}

vbmsg : adt {
	data : array of byte;
	rc : chan of string;
	next : cyclic ref vbmsg;
};

vbuffer(v : ref Viewer, fd : ref Sys->FD)
{
	ioc := v.output;
	datac := chan of array of byte;
	errc := chan of string;
	spawn vwriter(fd, datac, errc);
	fd = nil;

	msghd : ref vbmsg;
	msgtl : ref vbmsg;

Loop:
	for (;;) alt {
	(data, rc) := <- ioc =>
		if (data == nil)
			break Loop;
		if (msgtl != nil) {
			if (msgtl != msghd && msgtl.rc == nil && (len msgtl.data + len data) <= Sys->ATOMICIO) {
				ndata := array [len msgtl.data + len data] of byte;
				ndata[:] = msgtl.data;
				ndata[len msgtl.data:] = data;
				msgtl.data = ndata;
				msgtl.rc = rc;
			} else {
				msgtl.next = ref vbmsg (data, rc, nil);
				msgtl = msgtl.next;
			}
		} else {
			msghd = ref vbmsg (data, rc, nil);
			msgtl = msghd;
			datac <-= data;
		}
	err := <- errc =>
		if (msghd.rc != nil)
			msghd.rc <- = err;
		msghd = msghd.next;
		if (msghd != nil)
			datac <-= msghd.data;
		else
			msgtl = nil;
		if (err == Ehungup) {
			nhangups++;
			v.hungup = 1;
		}
	}
	# shutdown vwriter (may be blocked sending on errc)
	for (;;) alt {
	<- errc =>
		;
	datac <- = nil =>
		return;
	}
}

Viewer.new(fd: ref Sys->FD, pubscr: int, chans: Draw->Chans): string
{
	v := ref Viewer;
	v.output = chan of (array of byte, chan of string);
	spawn vbuffer(v, fd);

	v.imgmap = Idmap.new();
	v.scrmap = Idmap.new();
	v.chanmap = Idmap.new();
	v.imageid = 0;
	v.screenid = pubscr;
	v.hungup = 0;
	v.dchans = chans;
	v.tmpid = 0;
	v.tmpR = Rect((0,0), (0,0));

#D := array[1+1] of byte;
#D[0] = byte 'D';
#D[1] = byte 1;
#v.output <-= (D, nil);

	reply := chan of string;
	# import remote public screen into our remote draw client
	S := array [1+4+4] of byte;
	S[0] = byte 'S';
	put4(S, OPS_id, pubscr);
	put4(S, OPS_chans, chans.desc);
	v.output <-= (S, reply);
	err := <- reply;
	if (err != nil) {
		v.output <-= (nil, nil);
		return err;
	}

	# create remote window
	dispid := ++v.imageid;
	b := array [1+4+4+1+4+1+(4*4)+(4*4)+4] of byte;
	b[0] = byte 'b';
	put4(b, OPb_id, dispid);
	put4(b, OPb_screenid, pubscr);
	put1(b, OPb_refresh, 0);
	put4(b, OPb_chans, chans.desc);
	put1(b, OPb_repl, 0);
	putR(b, OPb_R, drawR);
	putR(b, OPb_clipR, drawR);
	put4(b, OPb_rrggbbaa, Draw->White);
	v.output <-= (b, reply);
	err = <- reply;
	if (err != nil) {
		v.output <-= (nil, nil);
		return err;
	}

	# map local display image id to remote window image id
	v.imgmap.add(0, dispid);
	if (!drawchans.eq(chans))
		# writepixels on this image must be chan converted
		v.chanmap.add(0, 1);

	# create 'white' repl image for use as mask
	v.whiteid = ++v.imageid;
	put4(b, OPb_id, v.whiteid);
	put4(b, OPb_screenid, 0);
	put1(b, OPb_refresh, 0);
	put4(b, OPb_chans, (Draw->RGBA32).desc);
	put1(b, OPb_repl, 1);
	putR(b, OPb_R, Rect((0,0), (1,1)));
	putR(b, OPb_clipR, Rect((-16r3FFFFFFF, -16r3FFFFFFF), (16r3FFFFFFF, 16r3FFFFFFF)));
	put4(b, OPb_rrggbbaa, Draw->White);
	v.output <-= (b, reply);
	err = <- reply;
	if (err != nil) {
		v.output <-= (nil, nil);
		return err;
	}

	img := images.lookup(0);
	key := chan of int;
	drawlock <- = key;
	v.copyimg(img, dispid);

	O := array [1+1] of byte;
	O[0] = byte 'O';
	O[1] = byte drawop;
	v.output <-= (O, nil);

	flush := array [1] of byte;
	flush[0] = byte 'v';
	v.output <- = (flush, nil);
	viewers = v :: viewers;
	key <-= 1;
	return nil;
}

Viewer.process(v : self ref Viewer, req : ref Drawreq)
{
	data := req.data;
	pick r := req {
	b => # allocate image
		imgid := ++v.imageid;
		if (r.screenid != 0) {
			(scrid, mapchans) := v.getscr(r.screenid, 0);
			put4(data, OPb_screenid, scrid);
			if (mapchans) {
				put4(data, OPb_chans, v.dchans.desc);
				v.chanmap.add(r.id, 1);
			}
		}
		v.imgmap.add(r.id, imgid);
		put4(data, OPb_id, imgid);

	A => # allocate screen
		imgid := v.getimg(r.imageid);
		put4(data, OPA_fillid, v.getimg(r.fillid));
		put4(data, OPA_imageid, imgid);
		reply := chan of string;
		for (i := 0; i < 25; i++) {
			put4(data, OPA_id, ++v.screenid);
			v.output <-= (data, reply);
			if (<-reply == nil) {
				v.scrmap.add(r.id, v.screenid);
				return;
			}
		}
		return;

	c => # set clipr and repl
		put4(data, OPc_dstid, v.getimg(r.dstid));

	d =>	 # general draw op
		dstid := v.imgmap.lookup(r.dstid);
		if (dstid == -1) {
			# don't do draw op as getimg() will do a writepixels
			v.getimg(r.dstid);
			return;
		}
		put4(data, OPd_maskid, v.getimg(r.maskid));
		put4(data, OPd_srcid, v.getimg(r.srcid));
		put4(data, OPd_dstid, dstid);

	e =>	 # draw ellipse
		dstid := v.imgmap.lookup(r.dstid);
		if (dstid == -1) {
			# don't do draw op as getimg() will do a writepixels
			v.getimg(r.dstid);
			return;
		}
		put4(data, OPe_srcid, v.getimg(r.srcid));
		put4(data, OPe_dstid, dstid);

	f => # free image
		id := v.imgmap.lookup(r.img.id);
		if (id == -1)
			# Viewer has never seen this image - ignore
			return;
		v.imgmap.del(r.id);
		# Viewers alias named images - only delete if last reference
		if (r.img.refc > 1)
			return;
		v.chanmap.del(r.img.id);
		put4(data, OPf_id, id);

	F => # free screen
		id := v.scrmap.lookup(r.id);
		scr := screens.lookup(r.id);
		# image and fill are free'd separately
		#v.imgmap.del(scr.imageid);
		#v.imgmap.del(scr.fillid);
		if (id == -1)
			return;
		put4(data, OPF_id, id);

	i => # convert image to font
		put4(data, OPi_fontid, v.getimg(r.fontid));

	l => # load a char into font
		put4(data, OPl_srcid, v.getimg(r.srcid));
		put4(data, OPl_fontid, v.getimg(r.fontid));

	L => # draw line
		dstid := v.imgmap.lookup(r.dstid);
		if (dstid == -1) {
			# don't do draw op as getimg() will do a writepixels
			v.getimg(r.dstid);
			return;
		}
		put4(data, OPL_srcid, v.getimg(r.srcid));
		put4(data, OPL_dstid, dstid);

#	n =>	# attach to named image
#	N =>	# name
#		Handled by id remapping to avoid clashes in namespace of remote viewers.
#		If it is a name we know then the id is remapped within the images Imageset
#		Otherwise, there is nothing we can do other than ignore all ops related to the id.

	o =>	 # set image origins
		id := v.imgmap.lookup(r.id);
		if (id == -1)
			# Viewer has never seen this image - ignore
			return;
		put4(data, OPo_id, id);

	O =>	# set next compositing op
		;

	p =>	 # draw polygon
		dstid := v.imgmap.lookup(r.dstid);
		if (dstid == -1) {
			# don't do draw op as getimg() will do a writepixels
			v.getimg(r.dstid);
			return;
		}
		put4(data, OPp_srcid, v.getimg(r.srcid));
		put4(data, OPp_dstid, dstid);

	s => # draw text
		dstid := v.imgmap.lookup(r.dstid);
		if (dstid == -1) {
			# don't do draw op as getimg() will do a writepixels
			v.getimg(r.dstid);
			return;
		}
		put4(data, OPs_fontid, v.getimg(r.fontid));
		put4(data, OPs_srcid, v.getimg(r.srcid));
		put4(data, OPs_dstid, dstid);

	x =>	# draw text with bg
		dstid := v.imgmap.lookup(r.dstid);
		if (dstid == -1) {
			# don't do draw op as getimg() will do a writepixels
			v.getimg(r.dstid);
			return;
		}
		put4(data, OPx_fontid, v.getimg(r.fontid));
		put4(data, OPx_srcid, v.getimg(r.srcid));
		put4(data, OPx_bgid, v.getimg(r.bgid));
		put4(data, OPx_dstid, dstid);

	t => # adjust window z order
		for (i := 0; i < len r.ids; i++)
			put4(data, OPt_id + 4*i, v.getimg(r.ids[i]));

	v => # flush updates to display
			;

	y => # write pixels
		id := v.imgmap.lookup(r.id);
		if (id == -1) {
			# don't do draw op as getimg() will do a writepixels
			v.getimg(r.id);
			return;
		}
		if (!drawchans.eq(v.dchans) && v.chanmap.lookup(r.id) != -1) {
			# chans clash
			img := images.lookup(r.id);
			# copy data as other Viewers may alter contents
			copy := (array [len data] of byte)[:] = data;
			v.chanconv(img, id, r.R, copy);
			return;
		}
		put4(data, OPy_id, id);

	* =>
		return;
	}
	# send out a copy of the data as other Viewers may alter contents
	copy := array [len data] of byte;
	copy[:] = data;
	v.output <-= (copy, nil);
}

Viewer.getimg(v: self ref Viewer, localid: int) : int
{
	remid := v.imgmap.lookup(localid);
	if (remid != -1)
		return remid;

	img := images.lookup(localid);
	if (img.id != localid) {
		# attached via name, see if we have the aliased image
		remid = v.imgmap.lookup(img.id);
		if (remid != -1) {
			# we have it, add mapping to save us this trouble next time
			v.imgmap.add(localid, remid);
			return remid;
		}
	}
	# is the image a window?
	scrid := 0;
	mapchans := 0;
	if (img.screenid != 0)
		(scrid, mapchans) = v.getscr(img.screenid, img.id);

	vid := ++v.imageid;
	# create the image
	# note: clipr for image creation has to be based on screen co-ords
	clipR := img.clipR.subpt(img.lorigin);
	clipR = clipR.addpt(img.R.min);
	b := array [1+4+4+1+4+1+(4*4)+(4*4)+4] of byte;
	b[0] = byte 'b';
	put4(b, OPb_id, vid);
	put4(b, OPb_screenid, scrid);
	put1(b, OPb_refresh, 0);
	if (mapchans)
		put4(b, OPb_chans, v.dchans.desc);
	else
		put4(b, OPb_chans, img.chans.desc);
	put1(b, OPb_repl, img.repl);
	putR(b, OPb_R, img.R);
	putR(b, OPb_clipR, clipR);
	put4(b, OPb_rrggbbaa, img.rrggbbaa);
	v.output <-= (b, nil);

	v.imgmap.add(img.id, vid);
	if (mapchans)
		v.chanmap.add(img.id, 1);

	# set the origin
	if (img.lorigin.x != img.R.min.x || img.lorigin.y != img.R.min.y) {
		o := array [1+4+(2*4)+(2*4)] of byte;
		o[0] = byte 'o';
		put4(o, OPo_id, vid);
		putP(o, OPo_rmin, img.lorigin);
		putP(o, OPo_screenrmin, img.R.min);
		v.output <-= (o, nil);
	}

	# is the image a font?
	if (img.font != nil) {
		f := img.font;
		i := array [1+4+4+1] of byte;
		i[0] = byte 'i';
		put4(i, OPi_fontid, vid);
		put4(i, OPi_nchars, len f.chars);
		put1(i, OPi_ascent, f.ascent);
		v.output <-= (i, nil);
	
		for (index := 0; index < len f.chars; index++) {
			ch := f.chars[index];
			if (ch == nil)
				continue;
			l := array [1+4+4+2+(4*4)+(2*4)+1+1] of byte;
			l[0] = byte 'l';
			put4(l, OPl_fontid, vid);
			put4(l, OPl_srcid, v.getimg(ch.srcid));
			put2(l, OPl_index, index);
			putR(l, OPl_R, ch.R);
			putP(l, OPl_P, ch.P);
			put1(l, OPl_left, ch.left);
			put1(l, OPl_width, ch.width);
			v.output <-= (l, nil);
		}
	}

	# if 'dirty' then writepixels
	if (img.dirty)
		v.copyimg(img, vid);

	return vid;
}

Viewer.copyimg(v : self ref Viewer, img : ref Image, id : int)
{
	dx := img.R.max.x - img.R.min.x;
	dy := img.R.max.y - img.R.min.y;
	srcR := Rect (img.lorigin, (img.lorigin.x + dx, img.lorigin.y + dy));
	bpl := bytesperline(srcR, img.chans);
	rlen : con 1+4+(4*4);
	ystep := (Sys->ATOMICIO - rlen)/ bpl;
	minx := srcR.min.x;
	maxx := srcR.max.x;
	maxy := srcR.max.y;

	chanconv := 0;
	if (!drawchans.eq(v.dchans) && v.chanmap.lookup(img.id) != -1)
		chanconv = 1;

	for (y := img.lorigin.y; y < maxy; y += ystep) {
		if (y + ystep > maxy)
			ystep = (maxy - y);
		R := Draw->Rect((minx, y), (maxx, y+ystep));
		r := array [rlen] of byte;
		r[0] = byte 'r';
		put4(r, OPr_id, img.id);
		putR(r, OPr_R, R);
		if (sys->write(drawfd, r, len r) != len r)
			break;

		nb := bpl * ystep;
		ymsg := array [1+4+(4*4)+nb] of byte;
		ymsg[0] = byte 'y';
#		put4(ymsg, OPy_id, id);
		putR(ymsg, OPy_R, R);
		n := sys->read(drawfd, ymsg[OPy_data:], nb);
		if (n != nb)
			break;
		if (chanconv)
			v.chanconv(img, id, R, ymsg);
		else {
			put4(ymsg, OPy_id, id);
			v.output <-= (ymsg, nil);
		}
	}
}

Viewer.chanconv(v: self ref Viewer, img: ref Image, id: int, r: Rect, ymsg: array of byte)
{
	# check origin matches and enough space in conversion image
	if (!(img.lorigin.eq(v.tmpR.min) && r.inrect(v.tmpR))) {
		# create new tmp image
		if (v.tmpid != 0) {
			f := array [1+4] of byte;
			f[0] = byte 'f';
			put4(f, OPf_id, v.tmpid);
			v.output <-= (f, nil);
		}
		v.tmpR = Rect((0,0), (img.R.dx(), img.R.dy())).addpt(img.lorigin);
		v.tmpid = ++v.imageid;
		b := array [1+4+4+1+4+1+(4*4)+(4*4)+4] of byte;
		b[0] = byte 'b';
		put4(b, OPb_id, v.tmpid);
		put4(b, OPb_screenid, 0);
		put1(b, OPb_refresh, 0);
		put4(b, OPb_chans, drawchans.desc);
		put1(b, OPb_repl, 0);
		putR(b, OPb_R, v.tmpR);
		putR(b, OPb_clipR, v.tmpR);
		put4(b, OPb_rrggbbaa, Draw->Nofill);
		v.output <-= (b, nil);
	}
	# writepixels to conversion image
	put4(ymsg, OPy_id, v.tmpid);
	v.output <-= (ymsg, nil);

	# ensure that drawop is Draw->S
	if (drawop != Draw->S) {
		O := array [1+1] of byte;
		O[0] = byte 'O';
		put1(O, OPO_op, Draw->S);
		v.output <-= (O, nil);
	}
	# blit across to real target
	d := array [1+4+4+4+(4*4)+(2*4)+(2*4)] of byte;
	d[0] = byte 'd';
	put4(d, OPd_dstid, id);
	put4(d, OPd_srcid, v.tmpid);
	put4(d, OPd_maskid, v.whiteid);
	putR(d, OPd_R, r);
	putP(d, OPd_P0, r.min);
	putP(d, OPd_P1, r.min);
	v.output <-= (d, nil);

	# restore drawop if necessary
	if (drawop != Draw->S) {
		O := array [1+1] of byte;
		O[0] = byte 'O';
		put1(O, OPO_op, drawop);
		v.output <-= (O, nil);
	}
}

# returns (rid, map)
# rid == remote screen id
# map indicates that chan mapping is required for windows on this screen

Viewer.getscr(v : self ref Viewer, localid, winid : int) : (int, int)
{
	remid := v.scrmap.lookup(localid);
	if (remid != -1) {
		if (drawchans.eq(v.dchans))
			return (remid, 0);
		scr := screens.lookup(localid);
		if (v.chanmap.lookup(scr.imageid) == -1)
			return (remid, 0);
		return (remid, 1);
	}

	scr := screens.lookup(localid);
	imgid := v.getimg(scr.imageid);
	fillid := v.getimg(scr.fillid);
	A := array [1+4+4+4+1] of byte;
	A[0] = byte 'A';
	put4(A, OPA_imageid, imgid);
	put4(A, OPA_fillid, fillid);
	put1(A, OPA_public, 0);

	reply := chan of string;
	for (i := 0; i < 25; i++) {
		put4(A, OPA_id, ++v.screenid);
		v.output <-= (A, reply);
		if (<-reply != nil)
			continue;
		v.scrmap.add(localid, v.screenid);
		break;
	}
	# if i == 25 then we have a problem
	# ...
	if (i == 25) {
#		sys->print("failed to create remote screen\n");
		return (0, 0);
	}

	# pre-construct the windows on this screen
	for (ix := len scr.windows -1; ix >=0; ix--)
		if (scr.windows[ix] != winid)
			v.getimg(scr.windows[ix]);

	if (drawchans.eq(v.dchans))
		return (v.screenid, 0);
	if (v.chanmap.lookup(scr.imageid) == -1)
		return (v.screenid, 0);
	return (v.screenid, 1);
}
