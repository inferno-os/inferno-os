implement WmLogon;

#
# InferNode Login Screen / Secstore Unlock
#
# Fullscreen login displayed at boot before the window manager starts.
# Uses raw Draw (no wmclient/wmsrv needed) so it can run before lucifer.
#
# Shows brand image, password field, version info.
# On Enter: unlocks secstore and loads keys into factotum.
# On Escape (double-press): skip with warning (keys won't persist).
# Exits after unlock, allowing boot to continue.
#
# First boot: prompts for new password + confirmation, creates secstore account.
# Subsequent boots: prompts for password, unlocks secstore, loads keys.
#
# For headless: profile detects no display and falls back to console prompt.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Font, Screen, Image, Point, Rect, Pointer: import draw;

include "bufio.m";
	bufio: Bufio;

include "imagefile.m";

include "dial.m";

include "secstore.m";
	secstore: Secstore;

include "keyring.m";
	kr: Keyring;
	IPint: import kr;

include "factotum.m";
	factotum: Factotum;

include "sh.m";

WmLogon: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

ZP := Point(0, 0);

IMGPATH:  con "/lib/lucifer/login-screen.png";
IMGW:     con 300;
IMGH:     con 205;
PADDING:  con 16;

# Login states
STATE_LOGIN:		con 0;
STATE_SETUP_PASS:	con 1;
STATE_SETUP_CONFIRM:	con 2;
STATE_LOGIN_FAILED:	con 3;

display_g: ref Display;
screen: ref Image;
bodyfont: ref Font;
smallfont: ref Font;
logo_g: ref Image;	# cached brand image

# Password state
passbuf: string;
confirmbuf: string;
savedpass: string;
cursor: int;
statusmsg: string;
state: int;
escpending: int;

stderr: ref Sys->FD;

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	draw = load Draw Draw->PATH;
	bufio = load Bufio Bufio->PATH;
	kr = load Keyring Keyring->PATH;
	secstore = load Secstore Secstore->PATH;
	factotum = load Factotum Factotum->PATH;

	# Open display directly (no wmclient)
	if(ctxt != nil && ctxt.display != nil)
		display_g = ctxt.display;
	if(display_g == nil) {
		display_g = Display.allocate(nil);
		if(display_g == nil) {
			# No display — headless fallback
			headlessprompt();
			return;
		}
	}
	screen = display_g.image;

	bodyfont = Font.open(display_g, "/fonts/combined/unicode.sans.14.font");
	if(bodyfont == nil)
		bodyfont = Font.open(display_g, "*default*");
	smallfont = Font.open(display_g, "/fonts/combined/unicode.sans.10.font");
	if(smallfont == nil)
		smallfont = bodyfont;

	# If factotum was already started with secstore backing (e.g. headless
	# mode with $SECSTORE_PASSWORD), skip the login screen entirely.
	if(factotumhaskeys()) {
		createsecstoresentinel();
		return;
	}

	passbuf = "";
	confirmbuf = "";
	savedpass = "";
	cursor = 0;
	escpending = 0;

	# Load brand image once (reloading per-redraw can fail under resource pressure)
	logo_g = loadpng(IMGPATH);

	# Brief delay for display to settle (prevents blank-screen glitch
	# when the display is still initializing on fast startup)
	sys->sleep(200);

	if(!secstoreacctexists()) {
		state = STATE_SETUP_PASS;
		statusmsg = "First boot \u2014 choose a secstore password";
	} else {
		state = STATE_LOGIN;
		statusmsg = "Enter password to unlock";
	}

	redraw();

	# Read keyboard input directly from /dev/keyboard
	kbdfd := sys->open("/dev/keyboard", Sys->OREAD);
	if(kbdfd == nil) {
		sys->fprint(stderr, "logon: cannot open /dev/keyboard: %r\n");
		headlessprompt();
		return;
	}

	kbdbuf := array[12] of byte;
	for(;;) {
		n := sys->read(kbdfd, kbdbuf, len kbdbuf);
		if(n <= 0)
			break;

		s := string kbdbuf[0:n];
		for(j := 0; j < len s; j++) {
			k := s[j];
			case k {
			'\n' or '\r' =>
				escpending = 0;
				if(handleenter())
					return;
			27 =>	# Escape
				if(handleescape())
					return;
			'\b' =>
				escpending = 0;
				handlebackspace();
			* =>
				if(k >= 16r20) {
					escpending = 0;
					handlechar(k);
				}
			}
		}
	}
}

# Returns 1 if login screen should exit
handleenter(): int
{
	case state {
	STATE_SETUP_PASS =>
		if(passbuf == nil || passbuf == "") {
			statusmsg = "Password required";
			redraw();
			return 0;
		}
		savedpass = passbuf;
		passbuf = "";
		state = STATE_SETUP_CONFIRM;
		statusmsg = "Confirm your password";
		redraw();
		return 0;

	STATE_SETUP_CONFIRM =>
		if(passbuf != savedpass) {
			statusmsg = "Passwords don't match \u2014 try again";
			passbuf = "";
			savedpass = "";
			state = STATE_SETUP_PASS;
			redraw();
			return 0;
		}
		# Passwords match — create account and unlock
		dosetupandunlock(passbuf);
		passbuf = "";
		savedpass = "";
		return 1;

	STATE_LOGIN =>
		if(dounlock())
			return 1;
		# Unlock failed — let user retry or skip
		state = STATE_LOGIN_FAILED;
		statusmsg += "\nEnter: try again  |  Escape: continue without secstore";
		redraw();
		return 0;

	STATE_LOGIN_FAILED =>
		# Enter from failed state — go back to password entry
		passbuf = "";
		state = STATE_LOGIN;
		statusmsg = "Enter password to unlock";
		redraw();
		return 0;
	}
	return 0;
}

# Returns 1 if login screen should exit
handleescape(): int
{
	case state {
	STATE_SETUP_CONFIRM =>
		# Go back to password entry
		passbuf = "";
		savedpass = "";
		state = STATE_SETUP_PASS;
		statusmsg = "Choose a secstore password";
		redraw();
		return 0;

	STATE_LOGIN_FAILED =>
		# User chose to continue without secstore after failed unlock
		statusmsg = "Continuing without secstore";
		redraw();
		sys->sleep(500);
		return 1;

	* =>
		# Double-press escape to skip
		if(escpending) {
			statusmsg = "Skipped";
			redraw();
			sys->sleep(300);
			return 1;
		}
		escpending = 1;
		statusmsg = "Keys won't persist. Press Escape again to skip.";
		redraw();
		return 0;
	}
}

handlebackspace()
{
	if(len passbuf > 0) {
		passbuf = passbuf[0:len passbuf - 1];
		redraw();
	}
}

handlechar(k: int)
{
	passbuf[len passbuf] = k;
	redraw();
}

redraw()
{
	if(screen == nil)
		return;

	r := screen.r;
	cx := (r.min.x + r.max.x) / 2;

	# Black background
	black := display_g.rgb(16r1a, 16r1a, 16r1a);
	screen.draw(r, black, nil, ZP);

	# Draw cached brand image (centered)
	y := r.min.y + PADDING * 3;
	if(logo_g != nil) {
		lw := logo_g.r.dx();
		lh := logo_g.r.dy();
		lx := cx - lw / 2;
		screen.draw(Rect((lx, y), (lx + lw, y + lh)), logo_g, nil, logo_g.r.min);
		y += lh + PADDING * 2;
	} else
		y += PADDING * 4;

	# Password field (manual draw — centered on screen)
	fh := bodyfont.height + 12;
	fw := 300;
	orange := display_g.rgb(16rff, 16r55, 16r00);
	dimgrey := display_g.rgb(16r66, 16r66, 16r66);
	fieldbg := display_g.rgb(16r2a, 16r2a, 16r2a);
	white := display_g.rgb(16rff, 16rff, 16rff);

	if(state == STATE_LOGIN_FAILED) {
		# Failed state: show error and choices, no password field
		red := display_g.rgb(16rff, 16r44, 16r44);

		# Error message
		errline := statusmsg;
		# Split on \n — first line is the error, second is the choices
		nl := -1;
		for(si := 0; si < len errline; si++)
			if(errline[si] == '\n') { nl = si; break; }
		if(nl >= 0) {
			ew := bodyfont.width(errline[0:nl]);
			screen.text(Point(cx - ew / 2, y), red, ZP, bodyfont, errline[0:nl]);
			y += bodyfont.height + PADDING;
			choiceline := errline[nl+1:];
			cw2 := bodyfont.width(choiceline);
			screen.text(Point(cx - cw2 / 2, y), white, ZP, bodyfont, choiceline);
			y += bodyfont.height + PADDING;
		} else {
			ew := bodyfont.width(errline);
			screen.text(Point(cx - ew / 2, y), red, ZP, bodyfont, errline);
			y += bodyfont.height + PADDING;
		}

		# Warning about consequences
		warn := "Keys and secrets will not be available.";
		ww := smallfont.width(warn);
		screen.text(Point(cx - ww / 2, y), dimgrey, ZP, smallfont, warn);
		y += smallfont.height;
		warn2 := "AI integration may not work.";
		ww2 := smallfont.width(warn2);
		screen.text(Point(cx - ww2 / 2, y), dimgrey, ZP, smallfont, warn2);
	} else {
		# Normal states: show prompt + password field
		prompt := "Password:";
		case state {
		STATE_SETUP_PASS =>
			prompt = "New password:";
		STATE_SETUP_CONFIRM =>
			prompt = "Confirm password:";
		}
		pw := bodyfont.width(prompt);
		screen.text(Point(cx - pw / 2, y), dimgrey, ZP, bodyfont, prompt);
		y += bodyfont.height + 4;

		# Field background (centered)
		fx := cx - fw / 2;
		fieldr := Rect((fx, y), (fx + fw, y + fh));
		screen.draw(fieldr, fieldbg, nil, ZP);
		screen.border(fieldr, 1, orange, ZP);

		# Masked password (dots)
		dots := "";
		for(i := 0; i < len passbuf; i++)
			dots += "\u2022";
		screen.text(Point(fx + 6, y + 6), white, ZP, bodyfont, dots);

		y += fh + PADDING;

		# Status message (centered)
		if(statusmsg != nil && statusmsg != "") {
			sw := bodyfont.width(statusmsg);
			screen.text(Point(cx - sw / 2, y), dimgrey, ZP, bodyfont, statusmsg);
		}
	}

	# Build info at bottom (dim, small)
	by := r.max.y - smallfont.height * 2 - PADDING;

	version := rf("/dev/sysctl");
	if(version == nil)
		version = "InferNode";
	vw := smallfont.width(version);
	screen.text(Point(cx - vw / 2, by), dimgrey, ZP, smallfont, version);
	by += smallfont.height + 2;

	ctext := "\u00A9 2026 InferNode.io";
	cw := smallfont.width(ctext);
	screen.text(Point(cx - cw / 2, by), dimgrey, ZP, smallfont, ctext);

	screen.flush(Draw->Flushnow);
}

# First boot: create secstore account, then unlock
dosetupandunlock(pass: string)
{
	statusmsg = "Creating secstore account...";
	redraw();
	err := createsecstoreacct(pass);
	if(err != nil) {
		statusmsg = "Setup failed: " + err;
		redraw();
		sys->sleep(2000);
		return;
	}

	statusmsg = "Unlocking (this may take a moment)...";
	redraw();

	err = connectfactotum(pass);
	if(err == nil) {
		enablesecstoresave(pass);
		createsecstoresentinel();
	}

	pass = "";

	if(err != nil) {
		statusmsg = err;
		redraw();
		sys->sleep(2000);
		return;
	}

	statusmsg = "Unlocked";
	redraw();
	ensurellmsrv();
	sys->sleep(500);
}

# Normal boot: unlock secstore and load keys.
# Returns 1 on success, 0 on failure.
dounlock(): int
{
	if(passbuf == nil || passbuf == "") {
		statusmsg = "Password required";
		redraw();
		return 0;
	}

	statusmsg = "Unlocking (this may take a moment)...";
	redraw();

	err := connectfactotum(passbuf);

	# Establish secstore save-back path so future keys persist
	if(err == nil) {
		enablesecstoresave(passbuf);
		createsecstoresentinel();
	}

	passbuf = "";	# zero password

	if(err != nil) {
		statusmsg = err;
		redraw();
		return 0;
	}

	statusmsg = "Unlocked";
	redraw();
	ensurellmsrv();
	sys->sleep(500);
	return 1;
}

# Create sentinel so other apps can detect secstore is active
createsecstoresentinel()
{
	fd := sys->create("/tmp/.secstore-unlocked", Sys->OWRITE, 8r644);
	if(fd != nil)
		sys->fprint(fd, "1");
}

# Start llmsrv if not already running.
# llmsrv may have failed during profile because the API key
# was only in secstore (not yet loaded at profile time).
ensurellmsrv()
{
	(ok, nil) := sys->stat("/n/llm");
	if(ok >= 0)
		return;	# already running

	sys->fprint(stderr, "logon: /n/llm not mounted, starting llmsrv\n");
	spawn startllmsrv();
	sys->sleep(1000);	# give it time to mount
}

startllmsrv()
{
	mod := load Command "/dis/llmsrv.dis";
	if(mod == nil) {
		sys->fprint(stderr, "logon: cannot load llmsrv: %r\n");
		return;
	}
	mod->init(nil, "llmsrv" :: nil);
}

connectfactotum(pass: string): string
{
	if(secstore == nil)
		return "secstore module not loaded";
	secstore->init();
	if(factotum == nil)
		return "factotum module not loaded";
	factotum->init();

	user := rf("/dev/user");
	if(user == nil)
		user = "inferno";

	pwhash := secstore->mkseckey(pass);
	filekey := secstore->mkfilekey2(pass);
	legacykey := secstore->mkfilekey(pass);

	(conn, nil, diag) := secstore->connect("tcp!localhost!5356", user, pwhash);
	if(conn == nil) {
		if(diag != nil)
			return "secstore: " + diag;
		return sys->sprint("secstore: %r");
	}

	file := secstore->getfile(conn, "factotum", 0);
	secstore->bye(conn);

	if(file == nil)
		return nil;	# new account, no keys yet

	plaintext := secstore->decrypt2(file, filekey, legacykey);
	if(plaintext == nil)
		return "wrong password";

	# Parse key lines and add to running factotum
	lines := string plaintext;
	secstore->erasekey(plaintext);

	fd := sys->open("/mnt/factotum/ctl", Sys->OWRITE);
	if(fd == nil)
		return sys->sprint("cannot open factotum: %r");

	nloaded := 0;
	line := "";
	for(i := 0; i < len lines; i++) {
		if(lines[i] == '\n') {
			if(len line > 4 && line[0:4] == "key ") {
				b := array of byte line;
				sys->write(fd, b, len b);
				nloaded++;
			}
			line = "";
		} else
			line[len line] = lines[i];
	}
	if(len line > 4 && line[0:4] == "key ") {
		b := array of byte line;
		sys->write(fd, b, len b);
		nloaded++;
	}

	sys->fprint(stderr, "logon: loaded %d keys from secstore\n", nloaded);
	return nil;
}

createsecstoreacct(pass: string): string
{
	if(secstore == nil)
		return "secstore module not loaded";
	secstore->init();

	user := rf("/dev/user");
	if(user == nil)
		user = "inferno";

	storedir := "/usr/inferno/secstore";
	userdir := storedir + "/" + user;

	sys->create(storedir, Sys->OREAD, Sys->DMDIR | 8r700);
	fd := sys->create(userdir, Sys->OREAD, Sys->DMDIR | 8r700);
	if(fd == nil)
		return sys->sprint("can't create %s: %r", userdir);
	fd = nil;

	pwhash := secstore->mkseckey(pass);
	p := IPint.strtoip("C41CFBE4D4846F67A3DF7DE9921A49D3B42DC33728427AB159CEC8CBB"+
		"DB12B5F0C244F1A734AEB9840804EA3C25036AD1B61AFF3ABBC247CD4B384224567A86"+
		"3A6F020E7EE9795554BCD08ABAD7321AF27E1E92E3DB1C6E7E94FAAE590AE9C48F96D9"+
		"3D178E809401ABE8A534A1EC44359733475A36A70C7B425125062B1142D", 16);
	r := IPint.strtoip("DF310F4E54A5FEC5D86D3E14863921E834113E060F90052AD332B3241"+
		"CEF2497EFA0303D6344F7C819691A0F9C4A773815AF8EAECFB7EC1D98F039F17A32A7E"+
		"887D97251A927D093F44A55577F4D70444AEBD06B9B45695EC23962B175F266895C67D"+
		"21C4656848614D888A4", 16);

	aver := array of byte "secstore";
	aC := array of byte user;
	Cp := array[len aver + len aC + len pwhash] of byte;
	Cp[0:] = aver;
	Cp[len aver:] = aC;
	Cp[len aver + len aC:] = pwhash;

	buf := array[7 * Keyring->SHA1dlen] of byte;
	for(i := 0; i < 7; i++) {
		hmackey := array[] of { byte ('A' + i) };
		kr->hmac_sha1(Cp, len Cp, hmackey, buf[i * Keyring->SHA1dlen:], nil);
	}
	for(i = 0; i < len Cp; i++)
		Cp[i] = byte 0;

	H := IPint.bebytestoip(buf);
	Hmod := H.div(p).t1;
	Hexp := Hmod.expmod(r, p);
	Hi := Hexp.invert(p);
	hexHi := Hi.iptostr(64);

	pakpath := userdir + "/PAK";
	fd = sys->create(pakpath, Sys->OWRITE, 8r600);
	if(fd == nil)
		return sys->sprint("can't create %s: %r", pakpath);
	b := array of byte hexHi;
	sys->write(fd, b, len b);
	fd = nil;

	sys->fprint(stderr, "logon: secstore account created for %s\n", user);
	return nil;
}

#
# Tell running factotum to use secstore for persistence.
# This enables the save-back path so new keys are persisted.
#
enablesecstoresave(pass: string)
{
	user := rf("/dev/user");
	if(user == nil)
		user = "inferno";

	cmd := "secstore tcp!localhost!5356 " + user + " " + pass;
	fd := sys->open("/mnt/factotum/ctl", Sys->OWRITE);
	if(fd == nil)
		return;
	b := array of byte cmd;
	sys->write(fd, b, len b);
	sys->fprint(stderr, "logon: secstore save-back enabled\n");
}

# Check if factotum already has keys (e.g. loaded via -S -P in profile)
factotumhaskeys(): int
{
	fd := sys->open("/mnt/factotum/ctl", Sys->OREAD);
	if(fd == nil)
		return 0;
	buf := array[64] of byte;
	n := sys->read(fd, buf, len buf);
	return n > 0;
}

secstoreacctexists(): int
{
	user := rf("/dev/user");
	if(user == nil)
		user = "inferno";
	(ok, nil) := sys->stat("/usr/inferno/secstore/" + user + "/PAK");
	return ok >= 0;
}

headlessprompt()
{
	# Fallback for headless: use factotum's built-in console prompt
	sys->fprint(stderr, "logon: no display, using console\n");
	# Nothing to do — factotum -S will prompt on its own if needed,
	# or the user can manually run:
	#   auth/factotum -S tcp!localhost!5356
}

loadpng(path: string): ref Image
{
	if(bufio == nil || display_g == nil)
		return nil;
	readpng := load RImagefile RImagefile->READPNGPATH;
	remap := load Imageremap Imageremap->PATH;
	if(readpng == nil || remap == nil)
		return nil;
	readpng->init(bufio);
	remap->init(display_g);
	fd := bufio->open(path, Bufio->OREAD);
	if(fd == nil)
		return nil;
	(raw, nil) := readpng->read(fd);
	if(raw == nil)
		return nil;
	(img, nil) := remap->remap(raw, display_g, 0);
	return img;
}

rf(name: string): string
{
	fd := sys->open(name, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	while(n > 0 && (buf[n-1] == byte '\n' || buf[n-1] == byte ' '))
		n--;
	if(n == 0)
		return nil;
	return string buf[0:n];
}
