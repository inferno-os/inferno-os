implement LuciConv;

#
# luciconv - Conversation zone for Lucifer
#
# Receives a sub-Image from the WM tiler (lucifer) and renders the
# conversation zone into it.  Runs as an independent goroutine.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Font, Point, Rect, Image, Display, Screen, Pointer: import draw;

include "bufio.m";

include "rlayout.m";

include "lucitheme.m";

include "menu.m";

LuciConv: module
{
	PATH: con "/dis/luciconv.dis";
	init: fn(img: ref Draw->Image, dsp: ref Draw->Display,
	         font: ref Draw->Font, mfont: ref Draw->Font,
	         mountpt: string, actid: int,
	         mouse: chan of ref Draw->Pointer,
	         kbd:   chan of int,
	         evch:  chan of string,
	         rsz:   chan of ref Draw->Image);
};

# --- ADTs ---

ConvMsg: adt {
	role:	string;
	text:	string;
	using:	string;
	rendimg: ref Image;
};

TileRect: adt {
	r:   Rect;
	msg: ref ConvMsg;
};

Attr: adt {
	key: string;
	val: string;
};

# --- Module-level state ---

rlay: Rlayout;
DocNode: import rlay;

menumod: Menu;
Popup: import menumod;

stderr: ref Sys->FD;
mainwin: ref Image;		# current zone sub-image
backbuf: ref Image;		# off-screen back buffer for double-buffered redraw
display_g: ref Display;
mainfont: ref Font;
monofont_g: ref Font;
mountpt_g: string;
actid_g := -1;

# Colors
bgcol: ref Image;
accentcol: ref Image;
textcol: ref Image;
text2col: ref Image;
dimcol: ref Image;
humancol: ref Image;
veltrocol: ref Image;
inputcol: ref Image;
cursorcol: ref Image;
redcol: ref Image;
codebgcol_g: ref Image;

# Conversation state
msgstore: array of ref ConvMsg;
nmsg := 0;
inputbuf: string;
inputpos := 0;		# cursor position within inputbuf
scrollpx := 0;
maxscrollpx := 0;
viewport_h := 400;
lastrendw := 0;
username := "human";

# Voice input state
VOICE_IDLE: con 0;
VOICE_REC: con 1;
voicestate := VOICE_IDLE;
voicech: chan of string;
micrect: Rect;  # Hit area for mic button
inputrect: Rect;  # Hit area for input field

# Tile layout (populated by drawconversation, used for click hit-testing)
tilelayout: array of ref TileRect;
ntiles := 0;

# --- init ---

init(img: ref Draw->Image, dsp: ref Draw->Display,
     font: ref Draw->Font, mfont: ref Draw->Font,
     mountpt: string, actid: int,
     mouse: chan of ref Draw->Pointer,
     kbd:   chan of int,
     evch:  chan of string,
     rsz:   chan of ref Draw->Image)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	stderr = sys->fildes(2);

	mainwin = img;
	display_g = dsp;
	mainfont = font;
	monofont_g = mfont;
	mountpt_g = mountpt;
	actid_g = actid;

	# Create colors from theme
	lucitheme := load Lucitheme Lucitheme->PATH;
	if(lucitheme == nil) {
		sys->fprint(sys->fildes(2), "luciconv: cannot load lucitheme: %r\n");
		return;
	}
	th := lucitheme->gettheme();
	bgcol = dsp.color(th.bg);
	accentcol = dsp.color(th.accent);
	textcol = dsp.color(th.text);
	text2col = dsp.color(th.text2);
	dimcol = dsp.color(th.dim);
	humancol = dsp.color(th.human);
	veltrocol = dsp.color(th.veltro);
	inputcol = dsp.color(th.input);
	cursorcol = dsp.color(th.cursor);
	redcol = dsp.color(th.red);
	codebgcol_g = dsp.color(th.codebg);

	# Load rlayout for markdown rendering
	rlay = load Rlayout Rlayout->PATH;
	if(rlay != nil)
		rlay->init(dsp);

	# Load menu module
	menumod = load Menu Menu->PATH;
	if(menumod == nil)
		sys->fprint(stderr, "luciconv: cannot load menu: %r\n");
	else
		menumod->init(display_g, mainfont);

	inputbuf = "";
	inputpos = 0;
	username = readdevuser();
	voicech = chan of string;
	msgstore = array[32] of ref ConvMsg;
	nmsg = 0;

	if(actid >= 0)
		loadmessages();

	redrawconv();

	# Event loop
	prevbuttons := 0;
	for(;;) alt {
	p := <-mouse =>
		wasdown := prevbuttons;
		prevbuttons = p.buttons;
		# Scroll wheel (buttons 8=up, 16=down)
		if(p.buttons & 8) {
			scrollpx += mainfont.height * 3;
			if(scrollpx > maxscrollpx)
				scrollpx = maxscrollpx;
			redrawconv();
		} else if(p.buttons & 16) {
			scrollpx -= mainfont.height * 3;
			if(scrollpx < 0)
				scrollpx = 0;
			redrawconv();
		}
		# Button-1 just pressed
		if(p.buttons == 1 && wasdown == 0) {
			# Check mic button first
			if(micrect.dx() > 0 && micrect.contains(p.xy)) {
				startvoice();
				redrawconv();
			} else {
				# Tile snarf
				for(tj := 0; tj < ntiles; tj++) {
					if(tilelayout[tj] != nil && tilelayout[tj].r.contains(p.xy)) {
						writetosnarf(tilelayout[tj].msg.text);
						break;
					}
				}
			}
		}
		# Button-3 press: context menu
		if((p.buttons & 4) != 0 && (wasdown & 4) == 0) {
			if(inputrect.dx() > 0 && inputrect.contains(p.xy)) {
				# Input field context menu
				if(menumod != nil) {
					items := array[] of {"Copy", "Paste"};
					pop := menumod->new(items);
					result := pop.show(mainwin, p.xy, mouse);
					if(result == 0) {
						# Copy input buffer to snarf
						if(len inputbuf > 0)
							writetosnarf(inputbuf);
					} else if(result == 1) {
						# Paste from snarf into input buffer at cursor
						s := readfromsnarf();
						if(s != nil && len s > 0) {
							inputbuf = inputbuf[0:inputpos] + s + inputbuf[inputpos:];
							inputpos += len s;
						}
					}
					redrawconv();
				}
			} else {
				for(ti := 0; ti < ntiles; ti++) {
					if(tilelayout[ti] != nil && tilelayout[ti].r.contains(p.xy)) {
						msg := tilelayout[ti].msg;
						if(msg != nil && menumod != nil) {
							items := array[] of {"Copy"};
							pop := menumod->new(items);
							result := pop.show(mainwin, p.xy, mouse);
							if(result == 0)
								writetosnarf(msg.text);
							redrawconv();
						}
						break;
					}
				}
			}
			prevbuttons = 0;
		}
	k := <-kbd =>
		case k {
		0 =>
			# Ctrl+Space — toggle voice input
			startvoice();
		1 =>
			# Ctrl-A — beginning of line
			inputpos = 0;
		2 =>
			# Ctrl-B — back one character
			if(inputpos > 0)
				inputpos--;
		4 =>
			# Ctrl-D — delete character at cursor
			if(inputpos < len inputbuf)
				inputbuf = inputbuf[0:inputpos] + inputbuf[inputpos+1:];
		5 =>
			# Ctrl-E — end of line
			inputpos = len inputbuf;
		6 =>
			# Ctrl-F — forward one character
			if(inputpos < len inputbuf)
				inputpos++;
		8 or 127 =>
			# Backspace / Ctrl-H — delete character before cursor
			if(inputpos > 0) {
				inputbuf = inputbuf[0:inputpos-1] + inputbuf[inputpos:];
				inputpos--;
			}
		11 =>
			# Ctrl-K — kill from cursor to end of line
			inputbuf = inputbuf[0:inputpos];
		'\n' or 13 =>
			# Enter — send input
			if(len inputbuf > 0) {
				sendinput(inputbuf);
				inputbuf = "";
				inputpos = 0;
			}
		21 =>
			# Ctrl-U — kill whole line
			inputbuf = "";
			inputpos = 0;
		23 =>
			# Ctrl-W — delete word back
			if(inputpos > 0) {
				p := inputpos;
				# Skip trailing whitespace
				while(p > 0 && (inputbuf[p-1] == ' ' || inputbuf[p-1] == '\t'))
					p--;
				# Skip word characters
				while(p > 0 && inputbuf[p-1] != ' ' && inputbuf[p-1] != '\t')
					p--;
				inputbuf = inputbuf[0:p] + inputbuf[inputpos:];
				inputpos = p;
			}
		27 =>
			# Escape — clear buffer
			inputbuf = "";
			inputpos = 0;
		16rFF51 =>
			# Left arrow
			if(inputpos > 0)
				inputpos--;
		16rFF53 =>
			# Right arrow
			if(inputpos < len inputbuf)
				inputpos++;
		16rFF61 =>
			# Home
			inputpos = 0;
		16rFF57 =>
			# End
			inputpos = len inputbuf;
		16rF00E =>
			# Page Up — half viewport
			scrollpx += viewport_h / 2;
			if(scrollpx > maxscrollpx)
				scrollpx = maxscrollpx;
		16rF00F =>
			# Page Down — half viewport
			scrollpx -= viewport_h / 2;
			if(scrollpx < 0)
				scrollpx = 0;
		* =>
			if(k >= 32 && k < 16rFFFF) {
				ch := "x";
				ch[0] = k;
				inputbuf = inputbuf[0:inputpos] + ch + inputbuf[inputpos:];
				inputpos++;
			}
		}
		redrawconv();
	vtext := <-voicech =>
		# Voice transcription result received
		voicestate = VOICE_IDLE;
		if(vtext != nil && vtext != "" && !hasprefix(vtext, "error:")) {
			inputbuf = vtext;
			sendinput(inputbuf);
			inputbuf = "";
			inputpos = 0;
		}
		redrawconv();
	ev := <-evch =>
		handleevent(ev);
		redrawconv();
	newimg := <-rsz =>
		mainwin = newimg;
		# Invalidate render caches on resize
		for(ri := 0; ri < nmsg; ri++)
			msgstore[ri].rendimg = nil;
		lastrendw = 0;
		redrawconv();
	}
}

handleevent(ev: string)
{
	if(hasprefix(ev, "switchactivity ")) {
		newid := strtoint(ev[len "switchactivity ":]);
		if(newid >= 0) {
			actid_g = newid;
			loadmessages();
		}
	} else if(hasprefix(ev, "conversation update ")) {
		idx := strtoint(ev[len "conversation update ":]);
		if(idx >= 0)
			updatemessage(idx);
	} else if(hasprefix(ev, "conversation ")) {
		idx := strtoint(ev[len "conversation ":]);
		if(idx >= 0)
			loadmessage(idx);
	} else if(hasprefix(ev, "theme ")) {
		reloadcolors();
	}
}

reloadcolors()
{
	lucitheme := load Lucitheme Lucitheme->PATH;
	if(lucitheme == nil)
		return;
	th := lucitheme->gettheme();
	bgcol = display_g.color(th.bg);
	accentcol = display_g.color(th.accent);
	textcol = display_g.color(th.text);
	text2col = display_g.color(th.text2);
	dimcol = display_g.color(th.dim);
	humancol = display_g.color(th.human);
	veltrocol = display_g.color(th.veltro);
	inputcol = display_g.color(th.input);
	cursorcol = display_g.color(th.cursor);
	redcol = display_g.color(th.red);
	codebgcol_g = display_g.color(th.codebg);
	# Invalidate rendered message caches so they redraw with new colours
	for(i := 0; i < nmsg; i++)
		msgstore[i].rendimg = nil;
	lastrendw = 0;
}

# --- Drawing ---

redrawconv()
{
	if(mainwin == nil)
		return;
	mr := mainwin.r;
	if(backbuf == nil || backbuf.r.dx() != mr.dx() || backbuf.r.dy() != mr.dy() ||
			backbuf.r.min.x != mr.min.x || backbuf.r.min.y != mr.min.y)
		backbuf = display_g.newimage(mr, mainwin.chans, 0, Draw->Nofill);
	front := mainwin;
	if(backbuf != nil)
		mainwin = backbuf;
	mainwin.draw(mainwin.r, bgcol, nil, (0, 0));
	drawconversation(mainwin.r);
	if(backbuf != nil) {
		mainwin = front;
		mainwin.draw(mainwin.r, backbuf, nil, backbuf.r.min);
	}
	mainwin.flush(Draw->Flushnow);
}

drawconversation(zone: Rect)
{
	pad := 8;
	inputh := mainfont.height + 2 * pad;
	msgy := zone.max.y - inputh - 2;

	# Draw input field at bottom
	inputr := Rect((zone.min.x + pad, zone.max.y - inputh),
		(zone.max.x - pad, zone.max.y));
	inputrect = inputr;
	mainwin.draw(inputr, inputcol, nil, (0, 0));

	# Mic button at right edge of input
	miclabel: string;
	miccol: ref Image;
	case voicestate {
	VOICE_REC =>
		miclabel = "REC";
		miccol = accentcol;
	* =>
		miclabel = "mic";
		miccol = dimcol;
	}
	micw := mainfont.width(miclabel) + 2 * pad;
	micx := inputr.max.x - micw;
	micy := inputr.min.y;
	micrect = Rect((micx, micy), (inputr.max.x, inputr.max.y));
	ity := inputr.min.y + (inputh - mainfont.height) / 2;
	mainwin.text((micx + pad, ity), miccol, (0, 0), mainfont, miclabel);
	# Separator line between input and mic
	mainwin.draw(Rect((micx - 1, micy + 4), (micx, inputr.max.y - 4)),
		dimcol, nil, (0, 0));

	# Input text — scroll so cursor is always visible
	itx := inputr.min.x + pad;
	maxitw := inputr.dx() - 2 * pad - 8 - micw;
	cw := 8;

	# Clamp inputpos
	if(inputpos < 0)
		inputpos = 0;
	if(inputpos > len inputbuf)
		inputpos = len inputbuf;

	# Find a visible window of inputbuf that keeps the cursor in view.
	# Start by including the cursor position, then expand left/right.
	vstart := inputpos;
	vend := inputpos;

	# Expand right first
	while(vend < len inputbuf && mainfont.width(inputbuf[vstart:vend+1]) + cw <= maxitw)
		vend++;
	# Expand left
	while(vstart > 0 && mainfont.width(inputbuf[vstart-1:vend]) + cw <= maxitw)
		vstart--;

	itext := inputbuf[vstart:vend];
	mainwin.text((itx, ity), textcol, (0, 0), mainfont, itext);

	# Block cursor at cursor position within visible text
	pre := inputbuf[vstart:inputpos];
	ch := mainfont.height;
	cx := itx + mainfont.width(pre);
	cy := ity;
	mainwin.draw(Rect((cx, cy), (cx + cw, cy + ch)), cursorcol, nil, (0, 0));

	if(nmsg == 0) {
		drawcentertext(Rect((zone.min.x, zone.min.y), (zone.max.x, msgy)),
			"No messages yet");
		return;
	}

	# Reset tile layout
	tilelayout = array[nmsg + 1] of ref TileRect;
	ntiles = 0;

	tilegap := 4;
	tpadv := 3;
	tilew := zone.dx() - 2 * pad;
	tilex := zone.min.x + pad;

	# Invalidate render cache on width change
	if(tilew != lastrendw) {
		for(ci := 0; ci < nmsg; ci++)
			msgstore[ci].rendimg = nil;
		lastrendw = tilew;
	}

	marr := msgstore;

	# Pass 1: estimate heights
	harr := array[nmsg] of int;
	total_h := 0;
	for(pi := 0; pi < nmsg; pi++) {
		# Skip empty messages (e.g. tool_use responses with no text content)
		# and stale streaming cursors ("▌", "…") left by dropped events.
		t := strip(marr[pi].text);
		if(t == "" || t == "▌" || t == "…") {
			harr[pi] = 0;
			continue;
		}
		imgh: int;
		if(marr[pi].rendimg != nil)
			imgh = marr[pi].rendimg.r.dy();
		else {
			ls := wraptext(marr[pi].text, tilew - 8);
			n := 0;
			for(wl := ls; wl != nil; wl = tl wl)
				n++;
			imgh = n * mainfont.height;
		}
		harr[pi] = mainfont.height + imgh + 2 * tpadv;
		total_h += harr[pi] + tilegap;
	}

	viewport_h = msgy - zone.min.y;
	newmax := total_h - viewport_h;
	if(newmax < 0)
		newmax = 0;
	maxscrollpx = newmax;
	if(scrollpx > maxscrollpx)
		scrollpx = maxscrollpx;

	# Pass 2: render visible messages
	codebg := codebgcol_g;
	ey := msgy + scrollpx;
	for(ri := nmsg - 1; ri >= 0; ri--) {
		if(harr[ri] == 0)
			continue;
		tiletop_e := ey - harr[ri] - tilegap;
		if(tiletop_e >= msgy) {
			ey = tiletop_e;
			continue;
		}
		if(tiletop_e + harr[ri] <= zone.min.y)
			break;
		streaming := len marr[ri].text > 0 &&
			marr[ri].text[len marr[ri].text - 1] == 16r258C;
		if(marr[ri].rendimg == nil && rlay != nil && marr[ri].role != "human" &&
				!streaming) {
			bgc_r := veltrocol;
			style_r := ref Rlayout->Style(
				tilew, 4,
				mainfont, monofont_g,
				textcol, bgc_r, accentcol, codebg,
				100
			);
			(img, nil) := rlay->render(rlay->parsemd(marr[ri].text), style_r);
			marr[ri].rendimg = img;
			if(img != nil)
				harr[ri] = mainfont.height + img.r.dy() + 2 * tpadv;
		}
		ey = tiletop_e;
	}

	# Draw messages bottom-up
	y := msgy + scrollpx;
	for(i := nmsg - 1; i >= 0; i--) {
		tileh := harr[i];
		if(tileh == 0)
			continue;
		tiletop := y - tileh - tilegap;

		if(tiletop >= msgy) {
			y = tiletop;
			continue;
		}
		if(tiletop + tileh <= zone.min.y)
			break;

		msg := marr[i];
		human := msg.role == "human";
		errrole := msg.role == "error";
		tilecol: ref Image;
		rolecol: ref Image;
		if(human) {
			tilecol = humancol;
			rolecol = text2col;
		} else if(errrole) {
			tilecol = redcol;
			rolecol = textcol;
		} else {
			tilecol = veltrocol;
			rolecol = accentcol;
		}

		drawtop := tiletop;
		if(drawtop < zone.min.y) drawtop = zone.min.y;
		drawbot := tiletop + tileh;
		if(drawbot > msgy) drawbot = msgy;
		if(drawtop < drawbot) {
			tiler := Rect((tilex, drawtop), (tilex + tilew, drawbot));
			mainwin.draw(tiler, tilecol, nil, (0, 0));
		}
		if(ntiles < len tilelayout)
			tilelayout[ntiles++] = ref TileRect(
				Rect((tilex, tiletop), (tilex + tilew, tiletop + tileh)), msg);

		ty := tiletop + tpadv;
		rolelabel := msg.role;
		if(human)
			rolelabel = username;
		if(ty >= zone.min.y && ty + mainfont.height <= msgy) {
			if(human)
				mainwin.text((tilex + tilew - mainfont.width(rolelabel), ty),
					rolecol, (0, 0), mainfont, rolelabel);
			else
				mainwin.text((tilex, ty), rolecol, (0, 0), mainfont, rolelabel);
		}
		ty += mainfont.height;

		if(human) {
			lines := wraptext(msg.text, tilew - 8);
			for(ll := lines; ll != nil; ll = tl ll) {
				if(ty >= msgy) break;
				if(ty + mainfont.height > zone.min.y) {
					lx := tilex + tilew - mainfont.width(hd ll);
					mainwin.text((lx, ty), textcol, (0, 0), mainfont, hd ll);
				}
				ty += mainfont.height;
			}
		} else if(errrole) {
			lines := wraptext(msg.text, tilew - 8);
			for(ll := lines; ll != nil; ll = tl ll) {
				if(ty >= msgy) break;
				if(ty + mainfont.height > zone.min.y)
					mainwin.text((tilex, ty), textcol, (0, 0), mainfont, hd ll);
				ty += mainfont.height;
			}
		} else if(msg.rendimg != nil) {
			imgh := msg.rendimg.r.dy();
			srcy := 0;
			dsty := ty;
			if(dsty < zone.min.y) {
				srcy = zone.min.y - dsty;
				dsty = zone.min.y;
			}
			enddsty := ty + imgh;
			if(enddsty > msgy) enddsty = msgy;
			if(dsty < enddsty)
				mainwin.draw(Rect((tilex, dsty), (tilex + tilew, enddsty)),
					msg.rendimg, nil, (0, srcy));
		} else {
			lines := wraptext(msg.text, tilew - 8);
			for(ll := lines; ll != nil; ll = tl ll) {
				if(ty >= msgy) break;
				if(ty + mainfont.height > zone.min.y)
					mainwin.text((tilex, ty), textcol, (0, 0), mainfont, hd ll);
				ty += mainfont.height;
			}
		}

		y = tiletop;
	}
}

drawcentertext(r: Rect, text: string)
{
	tw := mainfont.width(text);
	tx := r.min.x + (r.dx() - tw) / 2;
	ty := r.min.y + (r.dy() - mainfont.height) / 2;
	mainwin.text((tx, ty), dimcol, (0, 0), mainfont, text);
}

# --- Namespace loading ---

loadmessages()
{
	nmsg = 0;
	msgstore = array[32] of ref ConvMsg;
	base := sys->sprint("%s/activity/%d/conversation", mountpt_g, actid_g);
	for(i := 0; ; i++) {
		s := readfile(sys->sprint("%s/%d", base, i));
		if(s == nil)
			break;
		s = strip(s);
		attrs := parseattrs(s);
		role := getattr(attrs, "role");
		text := getattr(attrs, "text");
		using := getattr(attrs, "using");
		if(role == nil) role = "?";
		if(text == nil) text = "";
		appendmsg(ref ConvMsg(role, text, using, nil));
	}
}

loadmessage(idx: int)
{
	base := sys->sprint("%s/activity/%d/conversation", mountpt_g, actid_g);
	s := readfile(sys->sprint("%s/%d", base, idx));
	if(s == nil)
		return;
	s = strip(s);
	attrs := parseattrs(s);
	role := getattr(attrs, "role");
	text := getattr(attrs, "text");
	using := getattr(attrs, "using");
	if(role == nil) role = "?";
	if(text == nil) text = "";
	if(idx < nmsg) {
		msgstore[idx].role = role;
		msgstore[idx].text = text;
		msgstore[idx].using = using;
		msgstore[idx].rendimg = nil;
		return;
	}
	msg := ref ConvMsg(role, text, using, nil);
	if(role == "human" && nmsg > 0) {
		last := msgstore[nmsg - 1];
		if(last.role == "human" && last.text == text)
			return;
	}
	appendmsg(msg);
	scrollpx = 0;
}

updatemessage(idx: int)
{
	if(idx < 0 || idx >= nmsg)
		return;
	base := sys->sprint("%s/activity/%d/conversation", mountpt_g, actid_g);
	s := readfile(sys->sprint("%s/%d", base, idx));
	if(s == nil)
		return;
	s = strip(s);
	attrs := parseattrs(s);
	text := getattr(attrs, "text");
	if(text == nil) text = "";
	role := getattr(attrs, "role");
	if(role != nil && role != "")
		msgstore[idx].role = role;
	msgstore[idx].text = text;
	msgstore[idx].rendimg = nil;
}

sendinput(text: string)
{
	if(actid_g < 0)
		return;
	appendmsg(ref ConvMsg("human", text, nil, nil));
	scrollpx = 0;
	path := sys->sprint("%s/activity/%d/conversation/input", mountpt_g, actid_g);
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil) {
		sys->fprint(stderr, "luciconv: can't open %s: %r\n", path);
		return;
	}
	b := array of byte text;
	sys->write(fd, b, len b);
}

# --- Voice input ---

startvoice()
{
	if(voicestate != VOICE_IDLE)
		return;
	# Check if speech9p is mounted
	(ok, nil) := sys->stat("/n/speech/hear");
	if(ok < 0) {
		sys->fprint(stderr, "luciconv: /n/speech not mounted\n");
		return;
	}
	voicestate = VOICE_REC;
	spawn voiceworker(voicech);
}

VOICE_TIMEOUT_MS: con 30000;

VoiceFD: adt {
	fd: ref Sys->FD;
};

voiceworker(ch: chan of string)
{
	fd := sys->open("/n/speech/hear", Sys->ORDWR);
	if(fd == nil) {
		ch <-= "error: cannot open /n/speech/hear";
		return;
	}

	# Write start command to begin recording
	cmd := array of byte "start 5000";
	if(sys->write(fd, cmd, len cmd) < 0) {
		ch <-= "error: write to hear failed";
		return;
	}

	# Read transcription result with timeout.
	# Use a shared VoiceFD ref so timeout can nil the fd,
	# preventing voiceread from looping after timeout.
	# NOTE: if voiceread is blocked inside sys->read when timeout
	# fires, it will remain blocked until the underlying kernel FD
	# is closed or the read returns.  This is a known limitation
	# of Limbo's FD model -- there is no sys->close().
	sys->seek(fd, big 0, Sys->SEEKSTART);
	vfd := ref VoiceFD(fd);
	resultch := chan of string;
	spawn voiceread(vfd, resultch);

	timeoutch := chan of int;
	spawn voicetimeout(timeoutch, VOICE_TIMEOUT_MS);

	alt {
		result := <-resultch =>
			ch <-= result;
		<-timeoutch =>
			vfd.fd = nil;
			ch <-= "error: voice recognition timed out";
	}
}

voiceread(vfd: ref VoiceFD, ch: chan of string)
{
	result := "";
	buf := array[8192] of byte;
	for(;;) {
		fd := vfd.fd;
		if(fd == nil)
			break;
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}
	ch <-= result;
}

voicetimeout(ch: chan of int, ms: int)
{
	sys->sleep(ms);
	ch <-= 1;
}

# --- Word wrapping ---

wraptext(text: string, maxw: int): list of string
{
	if(text == nil || text == "")
		return "" :: nil;

	lines: list of string;
	line := "";

	i := 0;
	while(i < len text) {
		while(i < len text && (text[i] == ' ' || text[i] == '\t'))
			i++;
		if(i >= len text)
			break;
		wstart := i;
		while(i < len text && text[i] != ' ' && text[i] != '\t' && text[i] != '\n')
			i++;
		word := text[wstart:i];

		if(i < len text && text[i] == '\n') {
			if(line != "")
				line += " " + word;
			else
				line = word;
			lines = line :: lines;
			line = "";
			i++;
			continue;
		}

		candidate: string;
		if(line != "")
			candidate = line + " " + word;
		else
			candidate = word;

		if(mainfont.width(candidate) > maxw && line != "") {
			lines = line :: lines;
			line = word;
		} else {
			line = candidate;
		}
	}
	if(line != "")
		lines = line :: lines;
	if(lines == nil)
		return "" :: nil;

	rev: list of string;
	for(; lines != nil; lines = tl lines)
		rev = hd lines :: rev;
	return rev;
}

# --- Attribute parsing ---

parseattrs(s: string): list of ref Attr
{
	kstarts := array[32] of int;
	eqposs := array[32] of int;
	nkp := 0;

	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;

	j := i;
	while(j < len s) {
		if(s[j] == '=') {
			kstart := j - 1;
			while(kstart > i && s[kstart - 1] != ' ' && s[kstart - 1] != '\t')
				kstart--;
			if(kstart >= 0 && kstart < j) {
				if(kstart == 0 || kstart == i || s[kstart - 1] == ' ' || s[kstart - 1] == '\t') {
					if(nkp >= len kstarts) {
						nks := array[len kstarts * 2] of int;
						nks[0:] = kstarts[0:nkp];
						kstarts = nks;
						neq := array[len eqposs * 2] of int;
						neq[0:] = eqposs[0:nkp];
						eqposs = neq;
					}
					kstarts[nkp] = kstart;
					eqposs[nkp] = j;
					nkp++;
				}
			}
		}
		j++;
	}

	attrs: list of ref Attr;
	for(k := 0; k < nkp; k++) {
		key := s[kstarts[k]:eqposs[k]];
		vstart := eqposs[k] + 1;
		vend: int;
		if(key != "text" && key != "data" && k + 1 < nkp) {
			vend = kstarts[k + 1];
			while(vend > vstart && (s[vend - 1] == ' ' || s[vend - 1] == '\t'))
				vend--;
		} else
			vend = len s;
		val := "";
		if(vstart < vend)
			val = s[vstart:vend];
		attrs = ref Attr(key, val) :: attrs;
		if(key == "text" || key == "data")
			break;
	}

	rev: list of ref Attr;
	for(; attrs != nil; attrs = tl attrs)
		rev = hd attrs :: rev;
	return rev;
}

getattr(attrs: list of ref Attr, key: string): string
{
	for(; attrs != nil; attrs = tl attrs)
		if((hd attrs).key == key)
			return (hd attrs).val;
	return nil;
}

# --- Helpers ---

writetosnarf(text: string)
{
	fd := sys->open("/dev/snarf", Sys->OWRITE);
	if(fd == nil)
		return;
	b := array of byte text;
	sys->write(fd, b, len b);
}

readfromsnarf(): string
{
	fd := sys->open("/dev/snarf", Sys->OREAD);
	if(fd == nil)
		return nil;
	result := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}
	if(result == "")
		return nil;
	return result;
}

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	result := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}
	if(result == "")
		return nil;
	return result;
}

readdevuser(): string
{
	fd := sys->open("/dev/user", Sys->OREAD);
	if(fd == nil)
		return "human";
	buf := array[64] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return "human";
	s := string buf[0:n];
	while(len s > 0 && (s[len s - 1] == '\n' || s[len s - 1] == ' '))
		s = s[0:len s - 1];
	if(len s == 0)
		return "human";
	return s;
}

strip(s: string): string
{
	while(len s > 0 && (s[len s - 1] == '\n' || s[len s - 1] == ' ' || s[len s - 1] == '\t'))
		s = s[0:len s - 1];
	return s;
}

strtoint(s: string): int
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n'))
		i++;
	if(i >= len s)
		return -1;
	n := 0;
	for(; i < len s; i++) {
		c := s[i];
		if(c < '0' || c > '9')
			return -1;
		if(n > 214748364 || (n == 214748364 && (c - '0') > 7))
			return -1;
		n = n * 10 + (c - '0');
	}
	return n;
}

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

listlen(l: list of string): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}

# --- Message store ---

appendmsg(m: ref ConvMsg)
{
	# O(1) append using array-backed store
	if(nmsg >= len msgstore) {
		newcap := len msgstore * 2;
		if(newcap < 32)
			newcap = 32;
		ns := array[newcap] of ref ConvMsg;
		ns[0:] = msgstore[0:nmsg];
		msgstore = ns;
	}
	msgstore[nmsg++] = m;
}
