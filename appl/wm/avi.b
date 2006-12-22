implement WmAVI;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Rect, Display, Image: import draw;

include "tk.m";
	tk: Tk;
	Toplevel: import tk;

include	"tkclient.m";
	tkclient: Tkclient;
	ctxt: ref Draw->Context;

include "selectfile.m";
	selectfile: Selectfile;

include "dialog.m";
	dialog: Dialog;

include "riff.m";
	avi: Riff;
	AVIhdr, AVIstream, RD: import avi;
	video: ref AVIstream;

WmAVI: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Stopped, Playing, Paused: con iota;
state	:= Stopped;


cmap: array of byte;
codedbuf: array of byte;
pixelbuf: array of byte;
pixelrec: Draw->Rect;

task_cfg := array[] of {
	"canvas .c",
	"frame .b",
	"button .b.File -text File -command {send cmd file}",
	"button .b.Stop -text Stop -command {send cmd stop}",
	"button .b.Pause -text Pause -command {send cmd pause}",
	"button .b.Play -text Play -command {send cmd play}",
	"frame .f",
	"label .f.file -text {File:}",
	"label .f.name",
	"pack .f.file .f.name -side left",
	"pack .b.File .b.Stop .b.Pause .b.Play -side left",
	"pack .f -fill x",
	"pack .b -anchor w",
	"pack .c -side bottom -fill both -expand 1",
	"pack propagate . 0",
};

init(xctxt: ref Draw->Context, nil: list of string)
{
	sys  = load Sys  Sys->PATH;
	draw = load Draw Draw->PATH;
	tk   = load Tk   Tk->PATH;
	tkclient= load Tkclient Tkclient->PATH;
	dialog = load Dialog Dialog->PATH;
	selectfile = load Selectfile Selectfile->PATH;

	ctxt = xctxt;

	sys->pctl(Sys->NEWPGRP, nil);

	tkclient->init();
	dialog->init();
	selectfile->init();

	(t, wmctl) := tkclient->toplevel(ctxt, "", "AVI Player", 0);

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");

	for (c:=0; c<len task_cfg; c++)
		tk->cmd(t, task_cfg[c]);

	tk->cmd(t, "bind . <Configure> {send cmd resize}");
	tk->cmd(t, "update");
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "kbd"::"ptr"::nil);

	avi = load Riff Riff->PATH;
	if(avi == nil) {
		dialog->prompt(ctxt, t.image, "error -fg red", "Loading Interfaces",
			"Failed to load the RIFF/AVI\ninterface:"+sys->sprint("%r"),
			0, "Exit"::nil);
		return;
	}
	avi->init();

	fname := "";
	state = Stopped;

	for(;;) alt {
	s := <-t.ctxt.kbd =>
		tk->keyboard(t, s);
	s := <-t.ctxt.ptr =>
		tk->pointer(t, *s);
	s := <-t.ctxt.ctl or
	s = <-t.wreq or
	s = <-wmctl =>
		if(s == "exit") {
			state = Stopped;
			return;
		}
		tkclient->wmctl(t, s);
	press := <-cmd =>
		case press {
		"file" =>
			state = Stopped;
			patterns := list of {
				"*.avi (Microsoft movie files)",
				"* (All Files)"
			};
			fname = selectfile->filename(ctxt, t.image, "Locate AVI files",
				patterns, nil);
			if(fname != nil) {
				tk->cmd(t, ".f.name configure -text {"+fname+"}");
				tk->cmd(t, "update");
			}
		"play" =>
			if (state != Stopped) {
				state = Playing;
				continue;
			}
			if(fname != nil) {
				state = Playing;
				spawn play(t, fname);
			}
		"pause" =>
			if(state == Playing)
				state = Paused;
		"stop" =>
			state = Stopped;
		}
	}
}

play(t: ref Toplevel, file: string)
{
	sp := list of { "Stop Play" };

	(r, err) := avi->open(file);
	if(err != nil) {
		dialog->prompt(ctxt, t.image, "error -fg red", "Open AVI file", err, 0, sp);
		return;
	}

	err = avi->r.check4("AVI ");
	if(err != nil) {
		dialog->prompt(ctxt, t.image, "error -fg red", "Read AVI format", err, 0, sp);
		return;
	}

	(code, l) := avi->r.gethdr();
	if(code != "LIST") {
		dialog->prompt(ctxt, t.image, "error -fg red", "Parse AVI headers",
				"no list under AVI section header", 0, sp);
		return;
	}

	err = avi->r.check4("hdrl");
	if(err != nil) {
		dialog->prompt(ctxt, t.image, "error -fg red", "Read AVI header", err, 0, sp);
		return;
	}

	avihdr: ref AVIhdr;
	(avihdr, err) = avi->r.avihdr();
	if(err != nil) {
		dialog->prompt(ctxt, t.image, "error -fg red", "Read AVI header", err, 0, sp);
		return;
	}

	#
	# read the stream info & format structures
	#
	stream := array[avihdr.streams] of ref AVIstream;
	for(i := 0; i < avihdr.streams; i++) {
		(stream[i], err) = avi->r.streaminfo();
		if(err != nil) {
			dialog->prompt(ctxt, t.image, "error -fg red", "Parse AVI headers",
				"Failed to parse stream headers\n"+err, 0, sp);
			return;
		}
		if(stream[i].stype == "vids") {
			video = stream[i];
			err = video.fmt2binfo();
			if(err != nil) {
				dialog->prompt(ctxt, t.image, "error -fg red",
					"Parse AVI Video format",
					"Invalid stream headers\n"+err, 0, sp);
				return;
			}
		}
	}

	img: ref Draw->Image;
	if(video != nil) {
		case video.binfo.compression {
		* =>
			dialog->prompt(ctxt, t.image, "error -fg red",
					"Parse AVI Compression method",
					"unknown compression/encoding method", 0, sp);
			return;
		avi->BI_RLE8 =>
			cmap = array[len video.binfo.cmap] of byte;
			for(i = 0; i < len video.binfo.cmap; i++) {
				e := video.binfo.cmap[i];
				cmap[i] = byte ctxt.display.rgb2cmap(e.r, e.g, e.b);
			}
			break;
		}
		chans: draw->Chans;
		case video.binfo.bitcount {
		* =>
			dialog->prompt(ctxt, t.image, "error -fg red",
					"Check AVI Video format",
					string video.binfo.bitcount+
					" bits per pixel not supported", 0, sp);
			return;
		8 =>
			chans = Draw->CMAP8;
			mem := video.binfo.width*video.binfo.height;
			pixelbuf = array[mem] of byte;
		};
		pixelrec.min = (0, 0);
		pixelrec.max = (video.binfo.width, video.binfo.height);
		img = ctxt.display.newimage(pixelrec, chans, 0, Draw->White);
		if (img == nil) {
				sys->fprint(sys->fildes(2), "coffee: failed to allocate image\n");	
		exit;
		}
	}

	#
	# Parse out the junk headers we don't understand
	#
	parse: for(;;) {
		(code, l) = avi->r.gethdr();
		if(l < 0)
			break;

		case code {
		* =>
#			sys->print("%s %d\n", code, l);
			avi->r.skip(l);
		"LIST" =>
			err = avi->r.check4("movi");
			if(err != nil) {
				dialog->prompt(ctxt, t.image, "error -fg red",
					"Strip AVI headers",
					"no movi chunk", 0, sp);
				return;
			}
			break parse;
		}
	}

	canvr := canvsize(t);
	p := (Draw->Point)(0, 0);
	dx := canvr.dx();
	if(dx > video.binfo.width)
		p.x = (dx - video.binfo.width)/2;

	dy := canvr.dy();
	if(dy > video.binfo.height)
		p.y = (dy - video.binfo.height)/2;

	canvr = canvr.addpt(p);

	chunk: for(;;) {
		while(state == Paused)
			sys->sleep(0);
		if(state == Stopped)
			break chunk;
		(code, l) = avi->r.gethdr();
		if(l <= 0)
			break;
		if(l & 1)
			l++;
		case code {
		* =>
			avi->r.skip(l);
		"00db" =>			# Stream 0 Video DIB
			dib(r, img, l);
		"00dc" =>			# Stream 0 Video DIB compressed
			dibc(r, img, l);
			t.image.draw(canvr, img, nil, img.r.min);
		"idx1" =>
			break chunk;
		}
	}
	state = Stopped;
}

dib(r: ref RD, i: ref Draw->Image, l: int): int
{
	if(len codedbuf < l)
		codedbuf = array[l] of byte;

	if(r.readn(codedbuf, l) != l)
		return -1;

	case video.binfo.bitcount {
	8 =>
		for(k := 0; k < l; k++)
			codedbuf[k] = cmap[int codedbuf[k]];
	
		i.writepixels(pixelrec, codedbuf);
	}
	return 0;
}

dibc(r: ref RD, i: ref Draw->Image, l: int): int
{
	if(len codedbuf < l)
		codedbuf = array[l] of byte;

	if(r.readn(codedbuf, l) != l)
		return -1;

	case video.binfo.compression {
	avi->BI_RLE8 =>
		p := 0;
		posn := 0;
		x := 0;
		y := video.binfo.height-1;
		w := video.binfo.width;
		decomp: while(p < l) {
			n := int codedbuf[p++];
			if(n == 0) {
				esc := int codedbuf[p++];
				case esc {
				0 =>			# end of line
					x = 0;
					y--;
				1 =>			# end of image
					break decomp;
				2 =>			# Delta dx,dy
					x += int codedbuf[p++];
					y -= int codedbuf[p++];
				* =>
					posn = x+y*w;
					for(k := 0; k < esc; k++)
						pixelbuf[posn++] = cmap[int codedbuf[p++]];
					x += esc;
					if(p & 1)
						p++;
				};
			}
			else {
				posn = x+y*w;
				v := cmap[int codedbuf[p++]];
				for(k := 0; k < n; k++)
					pixelbuf[posn++] = v;
				x += n;
			}
		}
		i.writepixels(pixelrec, pixelbuf);
	}
	return 0;
}

canvsize(t: ref Toplevel): Rect
{
	r: Rect;

	r.min.x = int tk->cmd(t, ".c cget -actx");
	r.min.y = int tk->cmd(t, ".c cget -acty");
	r.max.x = r.min.x + int tk->cmd(t, ".c cget -width");
	r.max.y = r.min.y + int tk->cmd(t, ".c cget -height");

	return r;
}
