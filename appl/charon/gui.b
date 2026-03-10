# Gui implementation for running under wm (tk window manager)
implement Gui;

include "common.m";
include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;

include "widget.m";
	widgetmod: Widget;
	Scrollbar, Statusbar: import widgetmod;

sys: Sys;

D: Draw;
	Font,Point, Rect, Image, Screen, Display: import D;
	menumod: Menu;
	Popup: import menumod;

CU: CharonUtils;

E: Events;
	Event: import E;


WINDOW, CTLS, PROG, STATUS, BORDER, EXIT: con 1 << iota;
REQD: con ~0;

mousegrabbed := 0;
offset: Point;
ZP: con Point(0,0);
popup: ref Popup;
gctl: chan of string;
drawctxt: ref Draw->Context;
window: ref Window;
menu: ref Menu->Popup;

realwin: ref Draw->Image;
mask: ref Draw->Image;

# Statusbar state
statbar: ref Statusbar;
guifont: ref Font;
curinputmode := MNONE;
inputbuf := "";
cururl := "";		# last URL set via seturl
curstatus := "";	# last status set via setstatus

# Keyboard escape sequence state (for filterkbd)
kbdescstate := 0;
kbdescarg := 0;

# B2 mouse tracking
lastbuttons := 0;

# Key codes for escape sequence parsing
KCup:		con 16rFF52;
KCdown:		con 16rFF54;
KCleft:		con 16rFF51;
KCright:	con 16rFF53;
KChome:		con 16rFF61;
KCend:		con 16rFF57;
KCpgup:		con 16rFF55;
KCpgdown:	con 16rFF56;

init(ctxt: ref Draw->Context, cu: CharonUtils): ref Draw->Context
{
	sys = load Sys Sys->PATH;
	D = load Draw Draw->PATH;
	CU = cu;
	E = cu->E;
	if((CU->config).doacme){
		display=ctxt.display;
		makewins();
		progress = chan of Progressmsg;
		pidc := chan of int;
		spawn doacmeprogmon(pidc);
		<- pidc;
		return ctxt;
	}
	wmclient = load Wmclient Wmclient->PATH;
	wmclient->init();
	if (ctxt == nil)
		ctxt = wmclient->makedrawcontext();
	if(ctxt == nil) {
		# Headless mode: no display available.
		# Drain the progress channel so goproc never blocks on it.
		progress = chan of Progressmsg;
		pidc := chan of int;
		spawn doacmeprogmon(pidc);
		<-pidc;
		return nil;
	}

	menumod = load Menu Menu->PATH;

	win := wmclient->window(ctxt, "charon", Wmclient->Plain);
	window = win;
	drawctxt = ctxt;
	display = win.display;
	guifont = Font.open(display, "/fonts/combined/unicode.sans.14.font");
	if(guifont == nil)
		guifont = Font.open(display, "*default*");
	if(menumod != nil) {
		menumod->init(display, guifont);
		menu = menumod->new(array[] of {"back", "forward", "reload", "stop", "go to URL", "home"});
	}

	# Initialise widget toolkit for statusbar
	widgetmod = load Widget Widget->PATH;
	if(widgetmod != nil) {
		widgetmod->init(display, guifont);
		statbar = Statusbar.new(Rect((0, 0), (0, 0)));
	}

	gctl = chan of string;
	win.reshape(Rect((0, 0), (display.image.r.dx(), display.image.r.dy())));
	win.startinput( "kbd"::"ptr"::nil);
	win.onscreen(nil);
	makewins();
	mask = display.opaque;
	progress = chan of Progressmsg;
	pidc := chan of int;
	spawn progmon(pidc);
	<- pidc;
	spawn evhandle(win, E->evchan);
	return ctxt;
}

doacmeprogmon(pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	for (;;) {
		<- progress;
	}
}

progmon(pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	for (;;) {
		msg := <- progress;
		# just handle stop button for now
		if (msg.bsid == -1) {
			case (msg.state) {
			Pstart =>	stopbutton(1);
			* =>		stopbutton(0);
			}
		}
	}
}

st2s := array [] of {
	Punused => "unused",
	Pstart => "start",
	Pconnected => "connected",
	Psslconnected => "sslconnected",
	Phavehdr => "havehdr",
	Phavedata => "havedata",
	Pdone => "done",
	Perr => "error",
	Paborted => "aborted",
};

prprog(m:Progressmsg)
{
	sys->print("%d %s %d%% %s\n", m.bsid, st2s[m.state], m.pcnt, m.s);
}


r2s(r: Rect): string
{
	return sys->sprint("%d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
}

# Filter keyboard input through escape sequence state machine.
# Returns translated key code, or -1 if consumed (mid-sequence).
filterkbd(c: int): int
{
	if(c >= 16rFF00)
		return c;
	case kbdescstate {
	0 =>
		if(c == 27) {
			kbdescstate = 1;
			return -1;
		}
	1 =>
		kbdescstate = 0;
		if(c == '[') {
			kbdescstate = 2;
			kbdescarg = 0;
			return -1;
		}
		# Alt+arrow keys
		if(c == KCleft)
			return -2;	# alt-left = back
		if(c == KCright)
			return -3;	# alt-right = forward
	2 =>
		kbdescstate = 0;
		if(c == 'A') return E->Kup;
		if(c == 'B') return E->Kdown;
		if(c == 'C') return E->Kright;
		if(c == 'D') return E->Kleft;
		if(c == 'H') return E->Khome;
		if(c == 'F') return E->Kend;
		if(c >= '1' && c <= '9') {
			kbdescarg = c - '0';
			kbdescstate = 3;
			return -1;
		}
		return -1;
	3 =>
		if(c == '~') {
			kbdescstate = 0;
			if(kbdescarg == 1 || kbdescarg == 7) return E->Khome;
			if(kbdescarg == 4 || kbdescarg == 8) return E->Kend;
			if(kbdescarg == 5) return E->Kpgup;
			if(kbdescarg == 6) return E->Kpgdown;
			return -1;
		}
		if(c >= '0' && c <= '9') {
			kbdescarg = kbdescarg * 10 + (c - '0');
			return -1;
		}
		kbdescstate = 0;
		return -1;
	}
	return c;
}

evhandle(w: ref Window, evchan: chan of ref Event)
{
	last : Draw->Pointer;
	wmsize := startwmsize();
	for(;;) {
		ev: ref Event = nil;
		alt {
		wmsz := <-wmsize =>
			w.image = w.screen.newwindow(wmsz, Draw->Refnone, Draw->Nofill);
			makewins();
			ev = ref Event.Ereshape(mainwin.r);
			offset = ZP;
		ctl := <-w.ctl or
		ctl = <-w.ctxt.ctl =>
			w.wmctl(ctl);
			if(ctl != nil && ctl[0] == '!'){
				makewins();
				ev = ref Event.Ereshape(mainwin.r);
				offset = ZP;
			}
		p := <-w.ctxt.ptr =>
			if(w.pointer(*p))
				continue;
			if(p.buttons & 4){
				if(menumod == nil || menu == nil)
					continue;
				n := menu.show(window.image, p.xy, w.ctxt.ptr);
				case n {
				0 => ev = ref Event.Eback;
				1 => ev = ref Event.Efwd;
				2 => ev = ref Event.Ego("", "_top", 0, E->EGreload);
				3 => ev = ref Event.Estop;
				4 => startinput(MURL);
				5 => ev = ref Event.Ego("about:blank", "_top", 0, E->EGnormal);
				}
			}else if(p.buttons & (8|16)) {
				if(p.buttons & 8)
					ev = ref Event.Escrollr(0, Point(0, -60));
				else
					ev = ref Event.Escrollr(0, Point(0, 60));
			}else {
				pt := p.xy;
				pt = pt.sub(offset);
				# Distinguish B1 from B2
				b1 := p.buttons & 1;
				b2 := p.buttons & 2;
				lb1 := lastbuttons & 1;
				lb2 := lastbuttons & 2;
				if(b2 && !lb2) {
					# B2 down — paste-to-navigate
					ev = ref Event.Emouse(pt, E->Mmbuttondown);
				} else if(!b2 && lb2) {
					# B2 up — complete paste-to-navigate
					ev = ref Event.Emouse(pt, E->Mmbuttonup);
				} else if(b1 && !lb1) {
					ev = ref Event.Emouse(pt, E->Mlbuttondown);
				} else if(!b1 && lb1) {
					ev = ref Event.Emouse(pt, E->Mlbuttonup);
				} else if(b1 && lb1) {
					ev = ref Event.Emouse(pt, E->Mldrag);
				} else if(b2 && lb2) {
					ev = ref Event.Emouse(pt, E->Mmdrag);
				}
				lastbuttons = p.buttons;
				last = *p;
			}
		k := <-w.ctxt.kbd =>
			# Filter through escape sequence parser
			k = filterkbd(k);
			if(k == -1)
				continue;	# consumed mid-sequence

			# If in input mode, route to statusbar
			if(curinputmode != MNONE) {
				if(statbar != nil) {
					(done, val) := statbar.key(k);
					if(done == 1) {
						mode := curinputmode;
						curinputmode = MNONE;
						inputbuf = "";
						case mode {
						MURL =>
							val = guistrip(val);
							if(val != "") {
								if(!hasprefix(guitolower(val), "http://") &&
								   !hasprefix(guitolower(val), "https://"))
									val = "https://" + val;
								ev = ref Event.Ego(val, "_top", 0, E->EGnormal);
							}
						MLINK =>
							n := guiatoi(val);
							if(n > 0)
								ev = ref Event.Efollow(n);
						}
					} else if(done < 0) {
						curinputmode = MNONE;
						inputbuf = "";
					} else {
						inputbuf = statbar.buf;
					}
					# Redraw statusbar on any input key
					if(mainwin != nil)
						drawstatusbar(mainwin);
				}
				continue;
			}

			# Alt-arrow shortcuts (from filterkbd)
			if(k == -2) {
				ev = ref Event.Eback;
			} else if(k == -3) {
				ev = ref Event.Efwd;
			} else {
				ev = ref Event.Ekey(k);
			}
		}
		if (ev != nil)
			evchan <-= ev;
	}
}

makewins()
{
	if((CU->config).doacme){
		mainwin = display.newimage(Rect(display.image.r.min, ((CU->config).defaultwidth, display.image.r.max.y)), display.image.chans, 0, D->White);
		return;
		if(mainwin == nil)
			CU->raisex(sys->sprint("EXFatal: can't initialize windows: %r"));
	}
	if(window.image == nil)
		return;
	mainwin = window.image;
	realwin = mainwin;
}

hidewins()
{
	if((CU->config).doacme)
		return;
}

snarfput(nil: string)
{
	if((CU->config).doacme)
		return;
}

snarfget(): string
{
	if((CU->config).doacme || wmclient == nil)
		return nil;
	return wmclient->snarfget();
}

setstatus(s: string)
{
	if((CU->config).doacme)
		return;
	curstatus = s;
}

seturl(url: string)
{
	if((CU->config).doacme)
		return;
	cururl = url;
	if(window != nil && url != nil && url != "")
		window.settitle(url);
}

auth(realm: string): (int, string, string)
{
	user := prompt(realm + " username?", nil).t1;
	passwd := prompt("password?", nil).t1;
	if(user == nil)
		return (0, nil, nil);
	return (1, user, passwd);
}

alert(msg: string)
{
sys->print("ALERT:%s\n", msg);
	return;
}

confirm(msg: string): int
{
sys->print("CONFIRM:%s\n", msg);
	return -1;
}

prompt(nil, nil: string): (int, string)
{
	if((CU->config).doacme)
		return (-1, "");
	return (-1, "");
}

stopbutton(nil: int)
{
	if((CU->config).doacme)
		return;
}

backbutton(nil: int)
{
	if((CU->config).doacme)
		return;
}

fwdbutton(nil: int)
{
	if((CU->config).doacme)
		return;
}

flush(nil: Rect)
{
	if((CU->config).doacme)
		return;
	if(mainwin != nil) {
		drawstatusbar(mainwin);
		mainwin.flush(D->Flushnow);
	}
}

clientfocus()
{
	if((CU->config).doacme)
		return;
}

exitcharon()
{
	hidewins();
	E->evchan <-= ref Event.Equit(0);
}

tkupdate()
{
}

getpopup(nil: Rect): ref Menu->Popup
{
	return nil;
}

cancelpopup(): int
{
	if (popup == nil)
		return 0;
	popup = nil;
	return 1;
}

# ── Statusbar functions ──────────────────────────────────────

statusbarheight(): int
{
	if(statbar == nil || widgetmod == nil)
		return 0;
	return widgetmod->statusheight();
}

drawstatusbar(dst: ref Image)
{
	if(statbar == nil || dst == nil)
		return;
	r := dst.r;
	sth := statusbarheight();
	if(sth <= 0)
		return;
	sbr := Rect((r.min.x, r.max.y - sth), r.max);
	statbar.resize(sbr);
	if(curinputmode != MNONE) {
		# Input mode — prompt is already set
		;
	} else {
		statbar.prompt = nil;
		if(cururl != nil && cururl != "")
			statbar.left = cururl;
		else if(curstatus != nil && curstatus != "")
			statbar.left = curstatus;
		else
			statbar.left = "";
		if(linkcount > 0)
			statbar.right = sys->sprint("%d links", linkcount);
		else
			statbar.right = "";
		statbar.leftcolor = nil;
	}
	statbar.draw(dst);
}

startinput(mode: int)
{
	curinputmode = mode;
	inputbuf = "";
	if(statbar == nil)
		return;
	if(mode == MURL) {
		statbar.prompt = "URL: ";
		statbar.buf = "";
		if(cururl != nil && cururl != "") {
			inputbuf = cururl;
			statbar.buf = cururl;
		}
	} else if(mode == MLINK) {
		statbar.prompt = "Link #: ";
		statbar.buf = "";
	}
	if(mainwin != nil) {
		drawstatusbar(mainwin);
		mainwin.flush(D->Flushnow);
	}
}

inputmode(): int
{
	return curinputmode;
}

# ── String helpers ────────────────────────────────────────────

guistrip(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n'))
		i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\n'))
		j--;
	if(i >= j)
		return "";
	return s[i:j];
}

guitolower(s: string): string
{
	result := "";
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c >= 'A' && c <= 'Z')
			c += 'a' - 'A';
		result[len result] = c;
	}
	return result;
}

guiatoi(s: string): int
{
	s = guistrip(s);
	n := 0;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c < '0' || c > '9')
			break;
		n = n * 10 + (c - '0');
	}
	return n;
}

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}


startwmsize(): chan of Rect
{
	rchan := chan of Rect;
	fd := sys->open("#w/wmsize", Sys->OREAD);
	if(fd == nil)
		return rchan;
	sync := chan of int;
	spawn wmsizeproc(sync, fd, rchan);
	<-sync;
	return rchan;
}

Wmsize: con 1+4*12;		# 'm' plus 4 12-byte decimal integers

wmsizeproc(sync: chan of int, fd: ref Sys->FD, ptr: chan of Rect)
{
	sync <-= sys->pctl(0, nil);

	b:= array[Wmsize] of byte;
	while(sys->read(fd, b, len b) > 0){
		p := bytes2rect(b);
		if(p != nil)
			ptr <-= *p;
	}
}

bytes2rect(b: array of byte): ref Rect
{
	if(len b < Wmsize || int b[0] != 'm')
		return nil;
	x := int string b[1:13];
	y := int string b[13:25];
	return ref Rect((0,0), (x, y));
}
