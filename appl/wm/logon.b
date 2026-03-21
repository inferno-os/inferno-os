implement WmLogon;

#
# InferNode Login Screen / Secstore Unlock
#
# Fullscreen login displayed at boot before the window manager starts.
# Uses raw Draw (no wmclient/wmsrv needed) so it can run before lucifer.
#
# Shows brand image, password field, version info.
# On Enter: unlocks secstore and loads keys into factotum.
# On Escape: skip (start with empty factotum).
# Exits after unlock, allowing boot to continue.
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

WmLogon: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

ZP := Point(0, 0);

IMGPATH:  con "/lib/lucifer/login-screen.png";
IMGW:     con 600;
IMGH:     con 411;
PADDING:  con 16;

display_g: ref Display;
screen: ref Image;
bodyfont: ref Font;
smallfont: ref Font;

# Password state
passbuf: string;
cursor: int;
statusmsg: string;
setupmode: int;

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

	passbuf = "";
	cursor = 0;
	setupmode = !secstoreacctexists();
	if(setupmode)
		statusmsg = "First boot \u2014 choose a secstore password";
	else
		statusmsg = "Enter password to unlock";

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
				dounlock();
				return;
			27 =>	# Escape — skip
				statusmsg = "Skipped";
				redraw();
				sys->sleep(300);
				return;
			'\b' =>
				if(len passbuf > 0) {
					passbuf = passbuf[0:len passbuf - 1];
					redraw();
				}
			* =>
				if(k >= 16r20) {
					passbuf[len passbuf] = k;
					redraw();
				}
			}
		}
	}
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

	# Load and draw brand image (centered)
	logo := loadpng(IMGPATH);
	y := r.min.y + PADDING * 3;
	if(logo != nil) {
		lw := logo.r.dx();
		lh := logo.r.dy();
		lx := cx - lw / 2;
		screen.draw(Rect((lx, y), (lx + lw, y + lh)), logo, nil, logo.r.min);
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

	# Prompt label above field (centered)
	prompt := "Password:";
	if(setupmode)
		prompt = "New password:";
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

dounlock()
{
	if(passbuf == nil || passbuf == "") {
		statusmsg = "Password required";
		redraw();
		return;
	}

	if(setupmode) {
		statusmsg = "Creating secstore account...";
		redraw();
		err := createsecstoreacct(passbuf);
		if(err != nil) {
			statusmsg = "Setup failed: " + err;
			redraw();
			return;
		}
	}

	statusmsg = "Unlocking...";
	redraw();

	err := connectfactotum(passbuf);

	# Establish secstore save-back path so future keys persist
	if(err == nil)
		enablesecstoresave(passbuf);

	passbuf = "";	# zero password

	if(err != nil) {
		statusmsg = err;
		redraw();
		return;
	}

	statusmsg = "Unlocked";
	redraw();
	sys->sleep(500);
	# Exit — boot continues
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
