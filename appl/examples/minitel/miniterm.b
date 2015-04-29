#
# Copyright © 1998 Vita Nuova Limited.  All rights reserved.
#

implement Miniterm;

include "sys.m";
	sys: Sys;
	print, fprint, sprint, read: import sys;
include "draw.m";
	draw: Draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "dial.m";
	dial: Dial;

include "miniterm.m";

Miniterm: module
{
	init:		fn(ctxt: ref Draw->Context, argv: list of string);

};

pgrp: 		int 			= 0;
debug:		array of int	= array[256] of {* => 0};
stderr:		ref Sys->FD;

# Minitel terminal identification request - reply sequence
TERMINALID1 := array [] of {
	byte SOH,
	byte 'S', byte 'X', byte '1', byte 'H', byte 'N',
	byte EOT
};
TERMINALID2 := array [] of {
	byte SOH,
	byte 'C', byte 'g', byte '1',
	byte EOT
};

# Minitel module identifiers
Mscreen, Mmodem, Mkeyb, Msocket, Nmodule: con iota;
Pscreen, Pmodem, Pkeyb, Psocket: con (1 << iota);
Modname := array [Nmodule] of {
	Mscreen		=> "S",
	Mmodem		=> "M",
	Mkeyb 		=> "K",
	Msocket		=> "C",
	*			=> "?",
};

# attributes common to all modules
Module: adt {
	path:		int;					# bitset to connected modules
	disabled:	int;
};

# A BufChan queues events from the terminal to the modules
BufChan: adt {
	path:		int;					# id bit
	ch:		chan of ref Event;		# set to `in' or `dummy' channel 
	ev:		ref Event;				# next event to send
	in:		chan of ref Event;		# real channel for Events to the device
	q:		array of ref Event;		# subsequent events to send
};

# holds state information for the minitel `protocol` (chapter 6)
PState: adt {
	state:		int;
	arg:			array of int;		# up to 3 arguments: X,Y,Z
	nargs:		int;				# expected number of arguments
	n:			int;				# progress
	skip:			int;				# transparency; bytes to skip
};
PSstart, PSesc, PSarg: con iota;	# states

# Terminal display modes
Videotex, Mixed, Ascii,

# Connection methods
Direct, Network,

# Terminal connection states
Local, Connecting, Online,

# Special features
Echo
	: con (1 << iota);

Terminal: adt {
	in:		chan of ref Event;
	out:		array of ref BufChan;	# buffered output to the minitel modules

	mode:	int;					# display mode
	state:	int;					# connection state
	spec:	int;					# special features
	connect:	int;					# Direct, or Network
	toplevel:	ref Tk->Toplevel;
	cmd:		chan of string;			# from Tk
	proto:	array of ref PState;		# minitel protocol state
	netaddr:	string;				# network address to dial
	buttonsleft: int;				# display buttons on the LHS (40 cols)
	terminalid: array of byte;			# ENQROM response
	kbctl:	chan of string;			# softkeyboard control
	kbmode:	string;				# softkeyboard mode

	init:		fn(t: self ref Terminal, toplevel: ref Tk->Toplevel, connect: int);
	run:		fn(t: self ref Terminal, done: chan of int);
	reset:	fn(t: self ref Terminal);
	quit:		fn(t: self ref Terminal);
	layout:	fn(t: self ref Terminal, cols: int);
	setkbmode:	fn(t: self ref Terminal, tmode: int);
};

include "arg.m";
include "event.m";
include "event.b";

include "keyb.b";
include "modem.b";
include "socket.b";
include "screen.b";

K:		ref Keyb;
M:		ref Modem;
C:		ref Socket;
S:		ref Screen;
T:		ref Terminal;
Modules:	array of ref Module;


init(ctxt: ref Draw->Context, argv: list of string)
{
	s: string;
	netaddr: string = nil;

	sys = load Sys Sys->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	tkclient->init();
	draw = load Draw Draw->PATH;
	dial = load Dial Dial->PATH;
	stderr = sys->fildes(2);
	pgrp = sys->pctl(Sys->NEWPGRP|Sys->FORKNS, nil);

	arg := load Arg Arg->PATH;
	arg->init(argv);
	arg->setusage("miniterm [netaddr]");
	while((c := arg->opt()) != 0){
		case c {
		'D' =>
			s = arg->earg();
			for(i := 0; i < len s; i++){
				c = s[i];
				if(c < len debug)
					debug[c] += 1;
			}
		* =>
			arg->usage();
		}
	}
	argv = arg->argv();
	if(len argv > 0) {
		netaddr = hd argv;
		argv = tl argv;
	}

	if(argv != nil)
		arg->usage();
	arg = nil;

	# usage:	miniterm modem[!init[!number]]
	#	or	miniterm tcp!a.b.c.d
	connect: int;
	initstr := dialstr := string nil;
	if(netaddr == nil)
		netaddr = "tcp!pdc.minitelfr.com!513";	# gateway
	(nil, words) := sys->tokenize(netaddr, "!");
	if(len words == 0) {
		connect = Direct;
		words = "modem" :: nil;
	}
	if(hd words == "modem") {
		connect = Direct;
		words = tl words;
		if(words != nil) {
			initstr = hd words;
			words = tl words;
			if(words != nil)
				dialstr = hd words;
		}
		if(initstr == "*")
			initstr = nil;
		if(dialstr == "*")
			dialstr = nil;
	} else {
		connect = Network;
		dialstr = netaddr;
	}

	T = ref Terminal;
	K = ref Keyb;
	M = ref Modem;
	C = ref Socket;
	S = ref Screen;
	Modules = array [Nmodule] of {
		Mscreen	=> S.m,
		Mmodem	=> M.m,
		Mkeyb 	=> K.m,
		Msocket	=> C.m,
	};

	toplevel := tk->toplevel(ctxt.display, "");
	inittk(toplevel, connect);

	T.init(toplevel, connect);
	K.init(toplevel);
	M.init(connect, initstr, dialstr);
	C.init();
	case connect {
	Direct =>
		S.init(ctxt, Rect((0,0), (640,425)), Rect((0,0), (640,425)));
	Network =>
		S.init(ctxt, Rect((0,0), (596,440)), Rect((0,50), (640,350)));
	}

	done := chan of int;
	spawn K.run();
	spawn M.run();
	spawn C.run();
	spawn S.run();
	spawn T.run(done);
	<- done;

	# now tidy up
	K.quit();
	M.quit();
	C.quit();
	S.quit();
	T.quit();
}

# the keyboard module handles keypresses and focus
BTN40x25: con "-height 24 -font {/fonts/lucidasans/unicode.6.font}";
BTNCTL: con "-width 60 -height 20 -font {/fonts/lucidasans/unicode.7.font}";
BTNMAIN: con "-width 80 -height 20 -font {/fonts/lucidasans/unicode.7.font}";

tkinitbs := array[] of {
	"button .cxfin -text {Cx/Fin} -command {send keyb skey Connect}",
	"button .done -text {Quitter} -command {send keyb skey Exit}",
	"button .hup -text {Raccr.} -command {send term hangup}",
	"button .somm -text {Somm.} -command {send keyb skey Index}",
	"button .guide -text {Guide} -command {send keyb skey Guide}",
	"button .annul -text {Annul.} -command {send keyb skey Cancel}",
	"button .corr -text {Corr.} -command {send keyb skey Correct}",
	"button .retour -text {Retour} -command {send keyb skey Previous}",
	"button .suite -text {Suite} -command {send keyb skey Next}",
	"button .repet -text {Répét.} -command {send keyb skey Repeat}",
	"button .envoi -text {Envoi} -command {send keyb skey Send}",
	"button .play -text {P} -command {send term play}",
#	"button .db -text {D} -command {send term debug}" ,
	"button .kb -text {Clavier} -command {send term keyboard}",
	"button .move -text {<-} -command {send term buttonsleft} " + BTN40x25,
};

tkinitdirect := array [] of {
	". configure -background black -height 480 -width 640",

	".cxfin configure " + BTNCTL,
	".hup configure " + BTNCTL,
	".done configure " + BTNCTL,
	".somm configure " + BTNMAIN,
	".guide configure " + BTNMAIN,
	".annul configure " + BTNMAIN,
	".corr configure " + BTNMAIN,
	".retour configure " + BTNMAIN,
	".suite configure " + BTNMAIN,
	".repet configure " + BTNMAIN,
	".envoi configure " + BTNMAIN,
#	".play configure " + BTNCTL,
#	".db configure " + BTNCTL,
	".kb configure " + BTNCTL,

	"canvas .c -height 425 -width 640 -background black",
	"bind .c <Configure> {send term resize}",
	"bind .c <Key> {send keyb key %K}",
	"bind .c <FocusIn> {send keyb focusin}",
	"bind .c <FocusOut> {send keyb focusout}",
	"bind .c <ButtonRelease> {focus .c; send keyb click %x %y}",
	"frame .k -height 55 -width 640 -background black",
	"pack propagate .k no",
	"frame .klhs -background black",
	"frame .krhs -background black",
	"frame .krows -background black",
	"frame .k1 -background black",
	"frame .k2 -background black",
	"pack .cxfin -in .klhs -anchor w -pady 4",
	"pack .hup -in .klhs -anchor w",
	"pack .somm .annul .retour .repet -in .k1 -side left -padx 2",
	"pack .guide .corr .suite .envoi -in .k2 -side left -padx 2",
	"pack .kb -in .krhs -anchor e -pady 4",
	"pack .done -in .krhs -anchor e",
	"pack .k1 -in .krows -pady 4",
	"pack .k2 -in .krows",
	"pack .klhs .krows .krhs -in .k -side left -expand 1 -fill x",
	"pack .c .k",
	"focus .c",
	"update",
};

tkinitip := array [] of {
	". configure -background black -height 440 -width 640",

	# ip 40x25 mode support
	"canvas .c40 -height 440 -width 596 -background black",
	"bind .c40 <Configure> {send term resize}",
	"bind .c40 <Key> {send keyb key %K}",
	"bind .c40 <FocusIn> {send keyb focusin}",
	"bind .c40 <FocusOut> {send keyb focusout}",
	"bind .c40 <ButtonRelease> {focus .c40; send keyb click %x %y}",
	"frame .k -height 427 -width 44 -background black",
	"frame .gap1 -background black",
	"frame .gap2 -background black",
	"pack propagate .k no",

	# ip 80x25 mode support
	"frame .padtop -height 50",
	"canvas .c80 -height 300 -width 640 -background black",
	"bind .c80 <Configure> {send term resize}",
	"bind .c80 <Key> {send keyb key %K}",
	"bind .c80 <FocusIn> {send keyb focusin}",
	"bind .c80 <FocusOut> {send keyb focusout}",
	"bind .c80 <ButtonRelease> {focus .c80; send keyb click %x %y}",
	"frame .k80 -height 90 -width 640 -background black",
	"pack propagate .k80 no",
	"frame .klhs -background black",
	"frame .krows -background black",
	"frame .krow1 -background black",
	"frame .krow2 -background black",
	"frame .krhs -background black",
	"pack .krow1 .krow2 -in .krows -pady 2",
	"pack .klhs -in .k80 -side left",
	"pack .krows -in .k80 -side left -expand 1",
	"pack .krhs -in .k80 -side left",
};

tkip40x25show := array [] of {
	".cxfin configure " + BTN40x25,
	".hup configure " + BTN40x25,
	".done configure " + BTN40x25,
	".somm configure " + BTN40x25,
	".guide configure " + BTN40x25,
	".annul configure " + BTN40x25,
	".corr configure " + BTN40x25,
	".retour configure " + BTN40x25,
	".suite configure " + BTN40x25,
	".repet configure " + BTN40x25,
	".envoi configure " + BTN40x25,
	".play configure " + BTN40x25,
#	".db configure " + BTN40x25,
	".kb configure " + BTN40x25,
	"pack .cxfin -in .k -side top -fill x",
	"pack .gap1 -in .k -side top -expand 1",
	"pack .guide .repet .somm .annul .corr .retour .suite .envoi -in .k -side top -fill x",
	"pack .gap2 -in .k -side top -expand 1",
	"pack .done .hup .kb .move -in .k -side bottom -pady 2 -fill x",
#	"pack .db -in .k -side bottom",
};

tkip40x25lhs := array [] of {
	".move configure -text {->} -command {send term buttonsright}",
	"pack .k .c40 -side left",
	"focus .c40",
	"update",
};

tkip40x25rhs := array [] of {
	".move configure -text {<-} -command {send term buttonsleft}",
	"pack .c40 .k -side left",
	"focus .c40",
	"update",
};

tkip40x25hide := array [] of {
	"pack forget .k .c40",
};

tkip80x25show := array [] of {
	".cxfin configure " + BTNCTL,
	".hup configure " + BTNCTL,
	".done configure " + BTNCTL,
	".somm configure " + BTNMAIN,
	".guide configure " + BTNMAIN,
	".annul configure " + BTNMAIN,
	".corr configure " + BTNMAIN,
	".retour configure " + BTNMAIN,
	".suite configure " + BTNMAIN,
	".repet configure " + BTNMAIN,
	".envoi configure " + BTNMAIN,
#	".play configure " + BTNCTL,
#	".db configure " + BTNCTL,
	".kb configure " + BTNCTL,

	"pack .cxfin .hup -in .klhs -anchor w -pady 2",
	"pack .somm .annul .retour .repet -in .krow1 -side left -padx 2",
	"pack .guide .corr .suite .envoi -in .krow2 -side left -padx 2",
	"pack .done .kb -in .krhs -anchor e -pady 2",
	"pack .padtop .c80 .k80 -side top",
	"focus .c80",
	"update",
};

tkip80x25hide := array [] of {
	"pack forget .padtop .c80 .k80",
};

inittk(toplevel: ref Tk->Toplevel, connect: int)
{
	tkcmds(toplevel, tkinitbs);
	if(connect == Direct)
		tkcmds(toplevel, tkinitdirect);
	else
		tkcmds(toplevel, tkinitip);
}

Terminal.layout(t: self ref Terminal, cols: int)
{
	if(t.connect == Direct)
		return;
	if(cols == 80) {
		tkcmds(t.toplevel, tkip40x25hide);
		tkcmds(t.toplevel, tkip80x25show);
	} else {
		tkcmds(t.toplevel, tkip80x25hide);
		tkcmds(t.toplevel, tkip40x25show);
		if (t.buttonsleft)
			tkcmds(t.toplevel, tkip40x25lhs);
		else
			tkcmds(t.toplevel, tkip40x25rhs);
	}
}

Terminal.init(t: self ref Terminal, toplevel: ref Tk->Toplevel, connect: int)
{
	t.in = chan of ref Event;
	t.proto = array [Nmodule] of {
		Mscreen	=>	ref PState(PSstart, array [] of {0,0,0}, 0, 0, 0),
		Mmodem	=>	ref PState(PSstart, array [] of {0,0,0}, 0, 0, 0),
		Mkeyb	=>	ref PState(PSstart, array [] of {0,0,0}, 0, 0, 0),
		Msocket	=>	ref PState(PSstart, array [] of {0,0,0}, 0, 0, 0),
	};

	t.toplevel = toplevel;
	t.connect = connect;
	if (t.connect == Direct)
		t.spec = 0;
	else
		t.spec = Echo;
	t.cmd = chan of string;
	tk->namechan(t.toplevel, t.cmd, "term");		# Tk -> terminal
	t.state = Local;
	t.buttonsleft = 0;
	t.kbctl = nil;
	t.kbmode = "minitel";
	t.reset();
}

Terminal.reset(t: self ref Terminal)
{
	t.mode = Videotex;
}

Terminal.run(t: self ref Terminal, done: chan of int)
{
	t.out = array [Nmodule] of {
		Mscreen	=> ref BufChan(Pscreen, nil, nil, S.in, array [0] of ref Event),
		Mmodem	=> ref BufChan(Pmodem, nil, nil, M.in, array [0] of ref Event),
		Mkeyb 	=> ref BufChan(Pkeyb, nil, nil, K.in, array [0] of ref Event),
		Msocket	=> ref BufChan(Psocket, nil, nil, C.in, array [0] of ref Event),
	};
	modcount := Nmodule;
	if(debug['P'])
		post(ref Event.Eproto(Pmodem, 0, Cplay, "play", 0,0,0));
Evloop:
	for(;;) {
		ev: ref Event = nil;
		post(nil);
		alt {
		# recv message from one of the modules
		ev =<- t.in =>
			if(ev == nil) {			# modules ack Equit with nil
				if(--modcount == 0)
					break Evloop;
				continue;
			}
			pick e := ev {
			Equit =>		# close modules down
				post(ref Event.Equit(Pscreen|Pmodem|Pkeyb|Psocket,0));
				continue;
			}

			eva := protocol(ev);
			while(len eva > 0) {
				post(eva[0]);
				eva = eva[1:];
			}

		# send message to `plumbed' modules
		t.out[Mscreen].ch	<- = t.out[Mscreen].ev	=>
			t.out[Mscreen].ev = nil;
		t.out[Mmodem].ch	<- = t.out[Mmodem].ev	=>
			t.out[Mmodem].ev = nil;
		t.out[Mkeyb].ch		<- = t.out[Mkeyb].ev		=>
			t.out[Mkeyb].ev = nil;
		t.out[Msocket].ch	<- = t.out[Msocket].ev	=>
			t.out[Msocket].ev = nil;

		# recv message from Tk
		cmd := <- t.cmd =>
			(n, word) := sys->tokenize(cmd, " ");
			if(n >0)
				case hd word {
				"resize" =>	;
				"play" => # for testing only
					post(ref Event.Eproto(Pmodem, Mmodem, Cplay, "play", 0,0,0));
				"keyboard" =>
					if (t.kbctl == nil) {
						e: string;
						(e, t.kbctl) = kb(t);
						if (e != nil)
							sys->print("cannot start keyboard: %s\n", e);
					} else
						t.kbctl <- = "click";
				"hangup" =>
					if(T.state == Online || T.state == Connecting)
						post(ref Event.Eproto(Pmodem, 0, Cdisconnect, "",0,0,0));
				"buttonsleft" =>
					tkcmds(t.toplevel, tkip40x25lhs);
					t.buttonsleft = 1;
					if(S.image != nil)
						draw->(S.image.origin)(Point(0,0), Point(44, 0));
					if (t.kbctl != nil)
						t.kbctl <- = "fg";
				"buttonsright" =>
					tkcmds(t.toplevel, tkip40x25rhs);
					t.buttonsleft = 0;
					if(S.image != nil)
						draw->(S.image.origin)(Point(0,0), Point(0, 0));
					if (t.kbctl != nil)
						t.kbctl <- = "fg";
				"debug" =>
					debug['s'] ^= 1;
					debug['m'] ^= 1;
				}
		}

	}
	if (t.kbctl != nil)
		t.kbctl <- = "quit";
	t.kbctl = nil;
	done <-= 0;
}

kb(t: ref Terminal): (string, chan of string)
{
	s := chan of string;
	spawn dokb(t, s);
	e := <- s;
	if (e != nil)
		return (e, nil);
	return (nil, s);
}

Terminal.setkbmode(t: self ref Terminal, tmode: int)
{
	case tmode {
	Videotex =>
		t.kbmode = "minitel";
	Mixed or Ascii =>
		t.kbmode = "standard";
	}
	if(t.kbctl != nil) {
		t.kbctl <-= "mode";
		t.kbctl <-= "fg";
	}
}

include "swkeyb.m";
dokb(t: ref Terminal, c: chan of string)
{
	keyboard := load Keyboard Keyboard->PATH;
	if (keyboard == nil) {
		c <- = "cannot load keyboard";
		return;
	}

	kbctl := chan of string;
	(top, m) := tkclient->toplevel(S.ctxt, "", "Keyboard", 0);
	tk->cmd(top, "pack .Wm_t -fill x");
	tk->cmd(top, "update");
	keyboard->chaninit(top, S.ctxt, ".keys", kbctl);
	tk->cmd(top, "pack .keys");

	kbctl <-= t.kbmode ;

	kbon := 1;
	c <- = nil;	# all ok, we are now ready to accept commands

	for (;;) alt {
	mcmd := <- m =>
		if (mcmd == "exit") {
			if (kbon) {
				tk->cmd(top, ". unmap; update");
				kbon = 0;
			}
		} else
			tkclient->wmctl(top, mcmd);
	kbcmd := <- c =>
		case kbcmd {
		"fg" =>
			if (kbon)
				tk->cmd(top, "raise .;update");
		"click" =>
			if (kbon) {
				tk->cmd(top, ". unmap; update");
				kbon = 0;
			} else {
				tk->cmd(top, ". map; raise .");
				kbon = 1;
			}
		"mode" =>
			kbctl <- = t.kbmode;
		"quit"	=>
			kbctl <- = "kill";
			top = nil;
			# ensure tkclient not blocked on a send to us (probably overkill!)
			alt {
				<- m =>	;
				* =>	;
			}
			return;
		}
	}
}


Terminal.quit(nil: self ref Terminal)
{
}

# a minitel module sends an event to the terminal for routing
send(e: ref Event)
{
	if(debug['e'] && e != nil)
		fprint(stderr, "%s: -> %s\n", Modname[e.from], e.str());
	T.in <- = e;
}

# post an event to one or more modules
post(e: ref Event)
{
	i,l: int;
	for(i=0; i<Nmodule; i++) {
		# `ev' is cleared once sent, reload it from the front of `q'
		b: ref BufChan = T.out[i];
		l = len b.q;
		if(b.ev == nil && l != 0) {
			b.ev = b.q[0];
			na := array [l-1] of ref Event;
			na[0:] = b.q[1:];
			b.q = na;
		}
		if (e != nil) {
			if(e.path & b.path) {
				if(debug['e'] > 0) {
					pick de := e {
					* =>
						fprint(stderr, "[%s<-%s] %s\n", Modname[i], Modname[e.from], e.str());
					}
				}
				if(b.ev == nil)		# nothing queued
					b.ev = e;
				else {				# enqueue it
					l = len b.q;
					na := array [l+1] of ref Event;
					na[0:] = b.q[0:];
					na[l] = e;
					b.q = na;
				}
			}
		}
		# set a dummy channel if nothing to send
		if(b.ev == nil)
			b.ch = chan of ref Event;
		else
			b.ch = b.in;
	}
}

# run the terminal protocol
protocol(ev: ref Event): array of ref Event
{
	# Introduced by the following sequences, the minitel protocol can be
	# embedded in any normal data sequence
	# ESC,0x39,X
	# ESC,0x3a,X,Y
	# ESC,0x3b,X,Y,Z
	# ESC,0x61	- cursor position request

	ea := array [0] of ref Event;	# resulting sequence of Events
	changed := 0;				# if set, results are found in `ea'

	pick e := ev {
	Edata =>
		d0 := 0;				# offset of start of last data sequence
		p := T.proto[e.from];
		for(i:=0; i<len e.data; i++) {
			ch := int e.data[i];
#			if(debug['p'])
#				fprint(stderr, "protocol: [%s] %d %ux (%c)\n", Modname[e.from], p.state, ch, ch);
			if(p.skip > 0) {		# in transparency mode
				if(ch == 0 && e.from == Mmodem)	# 5.0
					continue;
				p.skip--;
				continue;
			}
			case p.state {
			PSstart =>
				if(ch == ESC) {
					p.state = PSesc;
					changed = 1;
					if(i > d0)
						ea = eappend(ea, ref Event.Edata(e.path, e.from, e.data[d0:i]));
					d0 = i+1;
				}
			PSesc =>
				p.state = PSarg;
				p.n = 0;
				d0 = i+1;
				changed = 1;
				if(ch >= 16r39 && ch <= 16r3b)	#PRO1,2,3
					p.nargs = ch - 16r39 + 1;
				else if(ch == 16r61)			# cursor position request
					p.nargs = 0;
				else if(ch == ESC) {
					ea = eappend(ea, ref Event.Edata(e.path, e.from, array [] of { byte ESC }));
					p.state = PSesc;
				} else {
					# false alarm, restore as data
					ea = eappend(ea, ref Event.Edata(e.path, e.from, array [] of { byte ESC, byte ch }));
					p.state = PSstart;
				}
			PSarg =>		# expect `nargs' bytes
				d0 = i+1;
				changed =1;
				if(p.n < p.nargs)
					p.arg[p.n++] = ch;
				if(p.n == p.nargs) {
					# got complete protocol sequence
					pe := proto(e.from, p);
					if(pe != nil)
						ea = eappend(ea, pe);
					p.state = PSstart;
				}
			}
		}
		if(changed) {			# some interpretation, results in `ea'
			if(i > d0)
				ea = eappend(ea, ref Event.Edata(e.path, e.from, e.data[d0:i]));
			return ea;
		}
		ev = e;
		return array [] of {ev};
	}
	return array [] of {ev};
}

# append to an Event array
eappend(ea: array of ref Event, e: ref Event): array of ref Event
{
	l := len ea;
	na := array [l+1] of ref Event;
	na[0:] = ea[0:];
	na[l] = e;
	return na;
}

# act on a received protocol sequence
# some sequences are handled here by the terminal and result in a posted reply
# others are returned `inline' as Eproto events with the normal data stream.
proto(from: int, p: ref PState): ref Event
{
	if(debug['p']) {
		fprint(stderr, "PRO%d: %ux", p.nargs, p.arg[0]);
		if(p.nargs > 1)
			fprint(stderr, " %ux", p.arg[1]);
		if(p.nargs > 2)
			fprint(stderr, " %ux", p.arg[2]);
		fprint(stderr, " (%s)\n", Modname[from]);
	}
	case p.nargs {
	0 =>							# cursor position request ESC 0x61
		reply := array [] of { byte US, byte S.pos.y, byte S.pos.x };
		post(ref Event.Edata(Pmodem, from, reply));
	1 =>
		case p.arg[0] {
		PROTOCOLSTATUS =>	;
		ENQROM =>				# identification request
			post(ref Event.Edata(Pmodem, from, T.terminalid));
			if(T.terminalid == TERMINALID1)
				T.terminalid = TERMINALID2;
		SETRAM1 or SETRAM2 =>	;
		FUNCTIONINGSTATUS =>		# 11.3
			PRO2(Pmodem, from, REPFUNCTIONINGSTATUS, osb());
		CONNECT =>	;
		DISCONNECT =>
			return ref Event.Eproto(Pscreen, from, Cscreenoff, "",0,0,0);
		RESET =>					# reset the minitel terminal
			all := Pscreen|Pmodem|Pkeyb|Psocket;
			post(ref Event.Eproto(all, from, Creset, "",0,0,0));	# check
			T.reset();
			reply := array [] of { byte SEP, byte 16r5E };
			post(ref Event.Edata(Pmodem, from, reply));
		}
	2 =>
		case p.arg[0] {
		TO =>					# request for module status
			PRO3(Pmodem, from, FROM, p.arg[1], psb(p.arg[1]));
		NOBROADCAST =>	;
		BROADCAST =>	;
		TRANSPARENCY =>			# transparency mode - skip bytes
			p.skip = p.arg[1];
			if(p.skip < 1 || p.skip > 127)	# 5.0
				p.skip = 0;
			else {
				reply := array [] of { byte SEP, byte 16r57 };
				post(ref Event.Edata(Pmodem, from, reply));
			}
		KEYBOARDSTATUS =>
			if(p.arg[1] == RxKeyb)
				PRO3(Pmodem, from, REPKEYBOARDSTATUS, RxKeyb, kosb());
		START =>
			x := osb();
			if(p.arg[1] == PROCEDURE)
				x |= 16r04;
			if(p.arg[1] == SCROLLING)
				x |= 16r02;
			PRO2(Pmodem, from, REPFUNCTIONINGSTATUS, x);
			case p.arg[1] {
			PROCEDURE =>			# activate error correction procedure
				sys->print("activate error correction\n");
				return ref Event.Eproto(Pmodem, from, Cstartecp, "",0,0,0);
			SCROLLING =>			# set screen to scroll
				return ref Event.Eproto(Pscreen, from, Cproto, "",START,SCROLLING,0);
			LOWERCASE =>			# set keyb to invert case
				return ref Event.Eproto(Pkeyb, from, Cproto, "",START,LOWERCASE,0);
			}
		STOP =>
			x := osb();	
			if(p.arg[1] == SCROLLING)
				x &= ~16r02;
			PRO2(Pmodem, from, REPFUNCTIONINGSTATUS, osb());
			case p.arg[1] {
			PROCEDURE =>			# deactivate error correction procedure
				sys->print("deactivate error correction\n");
				return ref Event.Eproto(Pmodem, from, Cstopecp, "",0,0,0);
			SCROLLING =>			# set screen to no scroll
				return ref Event.Eproto(Pscreen, from, Cproto, "",STOP,SCROLLING,0);
			LOWERCASE =>			# set keyb to not invert case
				return ref Event.Eproto(Pkeyb, from, Cproto, "",STOP,LOWERCASE,0);
			}
		COPY =>					# copy screen to socket
			# not implemented
			;
		MIXED =>					# change video mode (12.1)
			case p.arg[1] {
			MIXED1 =>			# videotex -> mixed
				reply := array [] of { byte SEP, byte 16r70 };
				return ref Event.Eproto(Pscreen, from, Cproto, "",MIXED,MIXED1,0);
			MIXED2 =>			# mixed -> videotex
				reply := array [] of { byte SEP, byte 16r71 };
				return ref Event.Eproto(Pscreen, from, Cproto, "",MIXED,MIXED2,0);
			}
		ASCII =>					# change video mode (12.2)
			# TODO
			;
		}
	3 =>
		case p.arg[0] {
		OFF or ON =>				# link, unlink, enable, disable
			modcmd(p.arg[0], p.arg[1], p.arg[2]);
			PRO3(Pmodem, from, FROM, p.arg[1], psb(TxCode(p.arg[1])));
		START =>	
			case p.arg[1] {
			RxKeyb =>			# keyboard mode
				case p.arg[2] {
				ETEN =>			# extended keyboard
					K.spec |= Extend;
				C0 =>			# cursor control key coding from col 0
					K.spec |= C0keys;
				}
				PRO3(Pmodem, from, REPKEYBOARDSTATUS, RxKeyb, kosb());
			}
		STOP =>					# keyboard mode
			case p.arg[1] {
			RxKeyb =>			# keyboard mode
				case p.arg[2] {
				ETEN =>			# extended keyboard
					K.spec &= ~Extend;
				C0 =>			# cursor control key coding from col 0
					K.spec &= ~C0keys;
				}
				PRO3(Pmodem, from, REPKEYBOARDSTATUS, RxKeyb, kosb());
			}
		}
	}
	return nil;
}

# post a PRO3 sequence to all modules on `path'
PRO3(path, from, x, y, z: int)
{
	data := array [] of { byte ESC, byte 16r3b, byte x, byte y, byte z};
	post(ref Event.Edata(path, from, data));
}

# post a PRO2 sequence to all modules on `path'
PRO2(path, from, x, y: int)
{
	data := array [] of { byte ESC, byte 16r3a, byte x, byte y};
	post(ref Event.Edata(path, from, data));
}

# post a PRO1 sequence to all modules on `path'
PRO1(path, from, x: int)
{
	data := array [] of { byte ESC, byte 16r39, byte x};
	post(ref Event.Edata(path, from, data));
}

# make or break links between modules, or enable and disable
modcmd(cmd, from, targ: int)
{
	from = RxTx(from);
	targ = RxTx(targ);
	if(from == targ)						# enable or disable module
		if(cmd == ON)
			Modules[from].disabled = 0;
		else
			Modules[from].disabled = 1;
	else 								# modify path
		if(cmd == ON)
			Modules[from].path |= (1<<targ);
		else
			Modules[from].path &= ~(1<<targ);
}

# determine the path status byte (3.4)
# if bit 3 of `code' is set then a receive path status byte is returned
# otherwise a transmit path status byte
psb(code: int): int
{
	this := RxTx(code);
	b := 16r40;			# bit 6 always set
	if(code == RxCode(code)) { 	# want a receive path status byte
		mask := (1<<this);
		if(Modules[Mscreen].path & mask)
			b |= 16r01;
		if(Modules[Mkeyb].path & mask)
			b |= 16r02;
		if(Modules[Mmodem].path & mask)
			b |= 16r04;
		if(Modules[Msocket].path & mask)
			b |= 16r08;
	} else {
		mod := Modules[this];
		if(mod.path & Mscreen)
			b |= 16r01;
		if(mod.path & Mkeyb)
			b |= 16r02;
		if(mod.path & Mmodem)
			b |= 16r04;
		if(mod.path & Msocket)
			b |= 16r08;
	}
#	if(parity(b))
#		b ^= 16r80;
	return b;
}

# convert `code' to a receive code by setting bit 3
RxCode(code: int): int
{
	return (code | 16r08)&16rff;
}

# covert `code' to a send code by clearing bit 3
TxCode(code: int): int
{
	return (code & ~16r08)&16rff;
}

# return 0 on even parity, 1 otherwise
# only the bottom 8 bits are considered
parity(b: int): int
{
	bits := 8;
	p := 0;
	while(bits-- > 0) {
		if(b&1)
			p ^= 1;
		b >>= 1;
	}
	return p;
}

# convert Rx or Tx code to a module code
RxTx(code: int): int
{
	rv := 0;
	case code {
	TxScreen or RxScreen	=> rv = Mscreen;
	TxKeyb or RxKeyb		=> rv = Mkeyb;
	TxModem or RxModem	=> rv = Mmodem;
	TxSocket or RxSocket	=> rv = Msocket;
	* =>
		fatal("invalid module code");
	}
	return rv;
}

# generate an operating status byte (11.2)
osb(): int
{
	b := 16r40;
	if(S.cols == 80)
		b |= 16r01;
	if(S.spec & Scroll)
		b |= 16r02;
	if(M.spec & Ecp)
		b |= 16r04;
	if(K.spec & Invert)
		b |= 16r08;
#	if(parity(b))
#		b ^= 16r80;
	return b;
}

# generate a keyboard operating status byte (9.1.2)
kosb(): int
{
	b := 16r40;
	if(K.spec & Extend)
		b |= 16r01;
	if(K.spec & C0keys)
		b |= 16r04;
#	if(parity(b))
#		b ^= 16r80;
	return b;
}

hex(v, n: int): string
{
	return sprint("%.*ux", n, v);
}

tostr(ch: int): string
{
	str := "";
	str[0] = ch;
	return str;
}

toint(s: string, base: int): (int, string)
{
	if(base < 0 || base > 36)
		return (0, s);

	c := 0;
	for(i := 0; i < len s; i++) {
		c = s[i];
		if(c != ' ' && c != '\t' && c != '\n')
			break;
	}

	neg := 0;
	if(c == '+' || c == '-') {
		if(c == '-')
			neg = 1;
		i++;
	}

	ok := 0;
	n := 0;
	for(; i < len s; i++) {
		c = s[i];
		v := base;
		case c {
		'a' to 'z' =>
			v = c - 'a' + 10;
		'A' to 'Z' =>
			v = c - 'A' + 10;
		'0' to '9' =>
			v = c - '0';
		}
		if(v >= base)
			break;
		ok = 1;
		n = n * base + v;
	}

	if(!ok)
		return (0, s);
	if(neg)
		n = -n;
	return (n, s[i:]);
}

tolower(s: string): string
{
	r := s;
	for(i := 0; i < len r; i++) {
		c := r[i];
		if(c >= int 'A' && c <= int 'Z')
			r[i] = r[i] + (int 'a' - int 'A');
	}
	return r;
}

# duplicate `ch' exactly `n' times
dup(ch, n: int): string
{
	str := "";
	for(i:=0; i<n; i++)
		str[i] = ch;
	return str;
}

fatal(msg: string)
{
	fprint(stderr, "fatal: %s\n", msg);
	exits(msg);
}

exits(s: string)
{
	if(s==nil);
#	raise "fail: miniterm " + s;
	fd := sys->open("#p/" + string pgrp + "/ctl", sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "killgrp");
	exit;
}

# Minitel byte MSB and LSB classification (p.87)
MSB(ch: int): int
{
	return (ch&16r70)>>4;
}
LSB(ch: int): int
{
	return (ch&16r0f);
}

# Minitel character set classification (p.92)
ISC0(ch: int): int
{
	msb := (ch&16r70)>>4;
	return msb == 0 || msb == 1;
}

ISC1(ch: int): int
{
	return ch >= 16r40 && ch <= 16r5f;
}

ISG0(ch: int): int
{
	# 0x20 (space) and 0x7f (DEL) are not in G0
	return ch > 16r20 && ch < 16r7f;
}

tkcmds(t: ref Tk->Toplevel, cmds: array of string)
{
	n := len cmds;
	for (ix := 0; ix < n; ix++)
		tk->cmd(t, cmds[ix]);
}
