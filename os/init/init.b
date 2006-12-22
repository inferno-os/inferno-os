implement Init;

include "sys.m";
sys: Sys;
FD, Connection, sprint, Dir: import sys;
print, fprint, open, bind, mount, dial, sleep, read: import sys;

include "draw.m";
draw: Draw;
Context, Display, Font, Rect, Point, Image, Screen: import draw;

include "prefab.m";
prefab: Prefab;
Environ, Element, Compound, Style: import prefab;

include "mpeg.m";

include "ir.m";
tirc: chan of int;	# translated remote input (from irslave)
irstopc: chan of int;	# channel to irslave

include "keyring.m";
kr: Keyring;
IPint: import kr;

Init: module
{
	init:	fn();
};

Shell: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

Signon: con "Dialing Local Service Provider\nWait a moment ...";
Login:  con "Connected to Service Provider";
Intro:	con "/mpeg/youwill2";
Garden:	con "The Garden of Delights\nHieronymus Bosch";

rootfs(server: string): int
{
	ok, n: int;
	c: Connection;
	err: string;

	(ok, c) = dial("tcp!" + server + "!6666", nil);
	if(ok < 0)
		return -1;

	if(kr != nil){
		ai := kr->readauthinfo("/nvfs/default");
		if(ai == nil){
			(ai, err) = register(server);
			if(err != nil){
				status("registration failed: "+err+"\nPress a key on your remote\ncontrol to continue.");
				# register() may have failed before Ir loaded.
				if(tirc!=nil){
					<-tirc;
					irstopc <-= 1;
				}
			}
			statusbox = nil;
		}
		(id_or_err, secret) := kr->auth(c.dfd, ai, 0);
		if(secret == nil){
			status("authentication failed: "+err);
			sys->sleep(2000);
			statusbox = nil;
			(ai, err) = register(server);
			if(err != nil){
				status("registration failed: "+err+"\nPress a key on your remote\ncontrol to continue.");
				# register() may have failed before Ir loaded.
				if(tirc!=nil){
					<-tirc;
					irstopc <-= 1;
				}
			}
			statusbox = nil;
		} else {
			# no line encryption
			algbuf := array of byte "none";
			kr->sendmsg(c.dfd, algbuf, len algbuf);
		}
	}

	c.cfd = nil;
	n = mount(c.dfd, nil, "/", sys->MREPL, "");
	if(n > 0)
		return 0;
	return -1;
}

ones: ref Image;
screen: ref Screen;
menuenv, tvenv: ref Environ;
Bootpreadlen: con 128;
textfont: ref Font;
disp: ref Display;
env: ref Environ;
statusbox: ref Compound;

init()
{
	shell: Shell;
	nr, ntok: int;
	c: ref Compound;
	ls: list of string;
	le, te, xe: ref Element;
	spec: string;

	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	prefab = load Prefab Prefab->PATH;
	kr = load Keyring Keyring->PATH;
	
	disp = Display.allocate(nil);
	ones = disp.ones;

	textfont = Font.open(disp, "*default*");
	screencolor := disp.rgb(161, 195, 209);

	menustyle := ref Style(
			textfont,			# titlefont
			textfont,			# textfont
			disp.color(16r55),		# elemcolor
			disp.color(draw->Black),	# edgecolor
			disp.color(draw->Yellow),	# titlecolor	
			disp.color(draw->Black),	# textcolor
			disp.color(draw->White));	# highlightcolor

	screen = Screen.allocate(disp.image, screencolor, 0);
	screen.image.draw(screen.image.r, screencolor, ones, (0, 0));
	menuenv = ref Environ(screen, menustyle);

	logo := disp.open("/lucent");
	phone := disp.open("/phone");
	if(phone == nil  || logo == nil) {
		print("open: /phone or /lucent: %r\n");
		exit;
	}

	#
	# Setup what we need to call a server and
	# Authenticate
	#
	bind("#l", "/net", sys->MREPL);
	bind("#I", "/net", sys->MAFTER);
	bind("#c", "/dev", sys->MAFTER);
	bind("#H", "/dev", sys->MAFTER);
	nvramfd := sys->open("#H/hd0nvram", sys->ORDWR);
	if(nvramfd != nil){
		spec = sys->sprint("#Fhd0nvram", nvramfd.fd);
		if(bind(spec, "/nvfs", sys->MAFTER|sys->MCREATE) < 0)
			print("init: bind %s: %r\n", spec);
	}

	setsysname();	# set up system name

	fd := open("/net/ipifc", sys->OWRITE);
	if(fd == nil) {
		print("init: open /net/ipifc: %r");
		exit;
	}
	fprint(fd, "bootp /net/ether0");

	fd = open("/net/bootp", sys->OREAD);
	if(fd == nil) {
		print("init: open /net/bootp: %r");
		exit;
	}

	buf := array[Bootpreadlen] of byte;
	nr = read(fd, buf, len buf);
	fd = nil;
	if(nr <= 0) {
		print("init: read /net/bootp: %r");
		exit;
	}

	(ntok, ls) = sys->tokenize(string buf, " \t\n");
	while(ls != nil) {
		if(hd ls == "fsip"){
			ls = tl ls;
			break;
		}
		ls = tl ls;
	}
	if(ls == nil) {
		print("init: server address not in bootp read");
		exit;
	}

	zr := Rect((0,0), (0,0));

	le = Element.icon(menuenv, logo.r, logo, ones);
	le = Element.elist(menuenv, le, Prefab->EVertical);
	xe = Element.icon(menuenv, phone.r, phone, ones);
	xe = Element.elist(menuenv, xe, Prefab->EHorizontal);
	te = Element.text(menuenv, Signon, zr, Prefab->EText);
	xe.append(te);
	xe.adjust(Prefab->Adjpack, Prefab->Adjleft);
	le.append(xe);
	le.adjust(Prefab->Adjpack, Prefab->Adjup);
	c = Compound.box(menuenv, (150, 100),
	Element.text(menuenv, "Inferno", zr, Prefab->ETitle), le);
	c.draw();

	while(rootfs(hd ls) < 0)
		sleep(1000);

	#
	# default namespace
	#
	bind("#c", "/dev", sys->MBEFORE);		# console
	bind("#H", "/dev", sys->MAFTER);
	if(spec != nil)
		bind(spec, "/nvfs", sys->MBEFORE|sys->MCREATE);	# our keys
	bind("#E", "/dev", sys->MBEFORE);		# mpeg
	bind("#l", "/net", sys->MBEFORE);		# ethernet
	bind("#I", "/net", sys->MBEFORE);		# TCP/IP
	bind("#V", "/dev", sys->MAFTER);		# hauppauge TV
	bind("#p", "/prog", sys->MREPL);		# prog device
	sys->bind("#d", "/fd", Sys->MREPL);

	setclock();

	le = Element.icon(menuenv, logo.r, logo, ones);
	le = Element.elist(menuenv, le, Prefab->EVertical);
	xe = Element.text(menuenv, Login, zr, Prefab->EText);
	le.append(xe);

	i := disp.newimage(Rect((0, 0), (320, 240)), 3, 0, 0);
	i.draw(i.r, menustyle.elemcolor, ones, i.r.min);
	xe = Element.icon(menuenv, i.r, i, ones);
	le.append(xe);

	le.adjust(Prefab->Adjpack, Prefab->Adjup);
	c = Compound.box(menuenv, (160, 50),
	Element.text(menuenv, "Inferno", zr, Prefab->ETitle), le);
	c.draw();

	xc: chan of string;
	mpeg := load Mpeg Mpeg->PATH;
	if(mpeg != nil) {
		xc = chan of string;
		r := (hd tl tl c.contents.kids).r;
		s := mpeg->play(disp, c.image, 1, r, Intro, xc);
		if(s != "") {
			print("mpeg: %s\n", s);
			xc = nil;
		}
	}

	i2 := disp.open("/icons/delight.bit");
	i.draw(i.r, i2, ones, i2.r.min);
	i2 = nil;
	if(xc != nil)
		<-xc;

	le.append(Element.text(menuenv, Garden, le.r, Prefab->EText));
	le.adjust(Prefab->Adjpack, Prefab->Adjup);
	c = Compound.box(menuenv, (160, 50),
	Element.text(menuenv, "Inferno", zr, Prefab->ETitle), le);
	c.draw();

	sleep(5000);

	# Do a bind to force applications to use IR module built
	# into the kernel.
	if(bind("#/./ir", Ir->PATH, sys->MREPL) < 0)
		print("init: bind ir: %r\n");
	# Uncomment the next line to load sh.dis.
#	shell = load Shell "/dis/sh.dis";
	dc : ref Context;
	# Comment the next 2 lines to load sh.dis.
	shell = load Shell "/dis/mux/mux.dis";
	dc = ref Context(screen, disp, nil, nil, nil, nil, nil);
	if(shell == nil) {
		print("init: load /dis/sh.dis: %r");
		exit;
	}
	shell->init(dc, nil);
}

setclock()
{
	(ok, dir) := sys->stat("/");
	if (ok < 0) {
		print("init: stat /: %r");
		return;
	}

	fd := sys->open("/dev/time", sys->OWRITE);
	if (fd == nil) {
		print("init: open /dev/time: %r");
		return;
	}

	# Time is kept as microsecs, atime is in secs
	b := array of byte sprint("%d000000", dir.atime);
	if (sys->write(fd, b, len b) != len b)
		print("init: write /dev/time: %r");
}

register(signer: string): (ref Keyring->Authinfo, string)
{

	# get box id
	fd := sys->open("/nvfs/ID", sys->OREAD);
	if(fd == nil){
		fd = sys->create("/nvfs/ID", sys->OWRITE, 8r664);
		if(fd == nil)
			return  (nil, "can't create /nvfs/ID");
		if(sys->fprint(fd, "LT%d", randomint()) < 0)
			return  (nil, "can't write /nvfs/ID");
		fd = sys->open("/nvfs/ID", sys->OREAD);
	}
	if(fd == nil)
		return  (nil, "can't open /nvfs/ID");

	buf := array[64] of byte;
	n := sys->read(fd, buf, (len buf) - 1);
	if(n <= 0)
		return (nil, "can't read /nvfs/ID");

	boxid := string buf[0:n];
	fd = nil;
	buf = nil;

	# Set-up for user input via remote control.
	tirc = chan of int;
	irstopc = chan of int;
	spawn irslave(tirc, irstopc);
	case dialogue("Register with your service provider?", "yes\nno") {
	0 =>
		;
	* =>
		return (nil, "registration not desired");
	}

	# a holder
	info := ref Keyring->Authinfo;

	# contact signer
#	status("looking for signer");
#	signer := virgil->virgil("$SIGNER");
#	if(signer == nil)
#		return (nil, "can't find signer");
	status("dialing tcp!"+signer+"!6671");
	(ok, c) := sys->dial("tcp!"+signer+"!6671", nil);
	if(!ok)
		return (nil, "can't contact signer");

	# get signer's public key and diffie helman parameters
	status("getting signer's key");
	spkbuf := kr->getmsg(c.dfd);
	if(spkbuf == nil)
		return (nil, "can't read signer's key");
	info.spk = kr->strtopk(string spkbuf);
	if(info.spk == nil)
		return (nil, "bad key from signer");
	alphabuf := kr->getmsg(c.dfd);
	if(alphabuf == nil)
		return (nil, "can't read dh alpha");
	info.alpha = IPint.b64toip(string alphabuf);
	pbuf := kr->getmsg(c.dfd);
	if(pbuf == nil)
		return (nil, "can't read dh mod");
	info.p = IPint.b64toip(string pbuf);

	# generate our key from system parameters
	status("generating our key");
	info.mysk = kr->genSKfromPK(info.spk, boxid);
	if(info.mysk == nil)
		return (nil, "can't generate our own key");
	info.mypk = kr->sktopk(info.mysk);

	# send signer our public key
	mypkbuf := array of byte kr->pktostr(info.mypk);
	kr->sendmsg(c.dfd, mypkbuf, len mypkbuf);

	# get blind certificate
	status("getting blinded certificate");
	certbuf := kr->getmsg(c.dfd);
	if(certbuf == nil)
		return (nil, "can't read signed key");

	# verify we've got the right stuff
	if(!verify(boxid, spkbuf, mypkbuf, certbuf))
		return (nil, "verification failed, try again");

	# contact counter signer
	status("dialing tcp!"+signer+"!6672");
	(ok, c) = sys->dial("tcp!"+signer+"!6672", nil);
	if(!ok)
		return (nil, "can't contact countersigner");

	# send boxid
	buf = array of byte boxid;
	kr->sendmsg(c.dfd, buf, len buf);

	# get blinding mask
	status("unblinding certificate");
	mask := kr->getmsg(c.dfd);
	if(len mask != len certbuf)
		return (nil, "bad mask length");
	for(i := 0; i < len mask; i++)
		certbuf[i] = certbuf[i] ^ mask[i];
	info.cert = kr->strtocert(string certbuf);

	status("verifying certificate");
	state := kr->sha(mypkbuf, len mypkbuf, nil, nil);
	if(kr->verify(info.spk, info.cert, state) == 0)
		return (nil, "bad certificate");

	status("storing keys");
	kr->writeauthinfo("/nvfs/default", info);
	
	status("Congratulations, you are registered.\nPress a key to continue.");
	<-tirc;
	irstopc <-= 1;

	return (info, nil);
}

dialogue(expl: string, selection: string): int
{
	c := Compound.textbox(menuenv, ((100, 100), (100, 100)), expl, selection);
	c.draw();
	for(;;){
		(key, index, nil) := c.select(c.contents, 0, tirc);
		case key {
		Ir->Select =>
			return index;
		Ir->Enter =>
			return -1;
		}
	}
}

status(expl: string)
{
#	title := Element.text(menuenv, "registration\nstatus", ((0,0),(0,0)), Prefab->ETitle);
#	msg := Element.text(menuenv, expl, ((0,0),(0,0)), Prefab->EText);
#	c := Compound.box(menuenv, (100, 100), title, msg);

	c := Compound.textbox(menuenv, ((100, 100),(100,100)), "Registration status", expl);
	c.draw();
	statusbox = c;
}

pro:= array[] of {
	"alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf",
	"hotel", "india", "juliet", "kilo", "lima", "mike", "nancy", "oscar",
	"poppa", "quebec", "romeo", "sierra", "tango", "uniform",
	"victor", "whiskey", "xray", "yankee", "zulu"
};

#
#  prompt for acceptance
#
verify(boxid: string, hispk, mypk, cert: array of byte): int
{
	s: string;

	# hash the string
	state := kr->md5(hispk, len hispk, nil, nil);
	kr->md5(mypk, len mypk, nil, state);
	digest := array[Keyring->MD5dlen] of byte;
	kr->md5(cert, len cert, digest, state);

	title := Element.elist(menuenv, nil, Prefab->EVertical);
	subtitle := Element.text(menuenv, "Telephone your service provider\n to register.  You will need\nthe following:\n", ((0,0),(0,0)), Prefab->ETitle);
	title.append(subtitle);

	line := Element.text(menuenv, "boxid is '"+boxid+"'.", ((0,0),(0,0)), Prefab->ETitle);
	title.append(line);
	for(i := 0; i < len digest; i++){
		line = Element.elist(menuenv, nil, Prefab->EHorizontal);
		s = (string (2*i)) + ": " + pro[((int digest[i])>>4)%len pro];
		line.append(Element.text(menuenv, s, ((0,0),(0,0)), Prefab->ETitle));

		s = (string (2*i+1)) + ": " + pro[(int digest[i])%len pro] + "\n";
		line.append(Element.text(menuenv, s, ((0,0),(200,0)), Prefab->ETitle));

		line.adjust(Prefab->Adjequal, Prefab->Adjleft);
		title.append(line);
	}
	title.adjust(Prefab->Adjpack, Prefab->Adjleft);

	le := Element.elist(menuenv, nil, Prefab->EHorizontal);
	le.append(Element.text(menuenv, " accept ", ((0, 0), (0, 0)), Prefab->EText));
	le.append(Element.text(menuenv, " reject ", ((0, 0), (0, 0)), Prefab->EText));
	le.adjust(Prefab->Adjpack, Prefab->Adjleft);

	c := Compound.box(menuenv, (50, 50), title, le);
	c.draw();

	for(;;){
		(key, index, nil) := c.select(c.contents, 0, tirc);
		case key {
		Ir->Select =>
			if(index == 0)
				return 1;
			return 0;
		Ir->Enter =>
			return 0;
		}
	}

	return 0;
}

randomint(): int
{
	fd := sys->open("/dev/random", sys->OREAD);
	if(fd == nil)
		return 0;
	buf := array[4] of byte;
	sys->read(fd, buf, 4);
	rand := 0;
	for(i := 0; i < 4; i++)
		rand = (rand<<8) | int buf[i];
	return rand;
}

# Reads real (if possible) or simulated remote, returns Ir events on irc.
# Must be a separate thread to be able to 1) read raw Ir input channel
# and 2) write translated Ir input data on output channel.
irslave(irc, stopc: chan of int)
{
	in, irpid: int;
	buf: list of int;
	outc: chan of int;

	irchan := chan of int;	# Untranslated Ir input channel.
	irpidch := chan of int;	# Ir reader pid channel.
	irmod := load Ir "#/./ir";	# Module built into kernel.

	if(irmod==nil){
		print("irslave: failed to load #/./ir");
		return;
	}
	if(irmod->init(irchan, irpidch)<0){
		print("irslave: failed to initialize ir");
		return;
	}
	irpid =<-irpidch;

	hdbuf := 0;
	dummy := chan of int;
	for(;;){
		if(buf == nil){
			outc = dummy;
		}else{
			outc = irc;
			hdbuf = hd buf;
		}
		alt{
		in = <-irchan =>
			buf = append(buf, in);
		outc <-= irmod->translate(hdbuf) =>
			buf = tl buf;
		<-stopc =>{
			killir(irpid);
			return;
			}
		}
	}
}

append(l: list of int, i: int): list of int
{
	if(l == nil)
		return i :: nil;
	return hd l :: append(tl l, i);
}

killir(irpid: int)
{
        pid := sys->sprint("%d", irpid);
        fd := sys->open("#p/"+pid+"/ctl", sys->OWRITE);
        if(fd==nil) {
                print("init: process %s: %r\n", pid);
                return;
        }
 
        msg := array of byte "kill";
        n := sys->write(fd, msg, len msg);
        if(n < 0) {
                print("init: message for %s: %r\n", pid);
                return;
        }
}

#
# Set system name from nvram
#
setsysname()
{
	fd := open("/nvfs/ID", sys->OREAD);
	if(fd == nil)
		return;
	fds := open("/dev/sysname", sys->OWRITE);
	if(fds == nil)
		return;
	buf := array[128] of byte;
	nr := sys->read(fd, buf, len buf);
	if(nr <= 0)
		return;
	sys->write(fds, buf, nr);
}
