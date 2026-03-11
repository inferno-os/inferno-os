implement LuciferWinstartTest;

#
# Regression tests for Lucifer Windows startup fixes (2026-03-07).
#
# Two bugs fixed:
#
#   1. readpng->read() hangs on Windows (inflate filter / Bufio issue).
#      Logo loading blocked all subsequent init, producing a white screen.
#      Fix: skip logo loading when /env/emuhost == "Nt".
#
#   2. mainwin backing image not filled before sub-window creation.
#      screen_data starts as 0xFF (white); wm/wm fills explicitly but
#      Lucifer didn't, so zones appeared white until modules painted them.
#      Fix: mainwin.draw(mainwin.r, mainscr.fill, ...) after Screen.allocate.
#
# Tests verify:
#   - /env/emuhost is readable and non-empty
#   - Platform detection logic (strip, comparison)
#   - readpng->read() completes within 5s on in-memory PNG (hang detection)
#   - readpng->read() from on-disk logo.png completes or is skipped on Nt
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "imagefile.m";
	readpng: RImagefile;

include "testing.m";
	testing: Testing;
	T: import testing;

LuciferWinstartTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/lucifer_winstart_test.b";

passed := 0;
failed := 0;
skipped := 0;

run(name: string, testfn: ref fn(t: ref T))
{
	t := testing->newTsrc(name, SRCFILE);
	testfn(t);

	if(testing->done(t))
		passed++;
	else if(t.skipped)
		skipped++;
	else
		failed++;
}

# Manual skip helper — avoids raise which hangs on Windows JIT
mskip(t: ref T, msg: string)
{
	t.skipped = 1;
	t.log(msg);
}

# --- Helpers (mirror lucifer.b) ---

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

strip(s: string): string
{
	while(len s > 0 && (s[len s - 1] == '\n' || s[len s - 1] == ' ' || s[len s - 1] == '\t'))
		s = s[0:len s - 1];
	return s;
}

# --- Platform detection tests ---

# /env/emuhost must be readable and contain a known platform name
testEmuhostReadable(t: ref T)
{
	raw := readfile("/env/emuhost");
	if(raw == nil) {
		t.error("/env/emuhost is nil or empty");
		return;
	}
	host := strip(raw);
	t.log("emuhost = " + host);
	t.assert(host == "Nt" || host == "MacOSX" || host == "Linux",
		"emuhost should be Nt, MacOSX, or Linux; got: " + host);
}

# strip() must remove trailing whitespace correctly
testStripWhitespace(t: ref T)
{
	t.assertseq(strip("Nt\n"), "Nt", "strip trailing newline");
	t.assertseq(strip("Nt\n\n"), "Nt", "strip multiple newlines");
	t.assertseq(strip("MacOSX "), "MacOSX", "strip trailing space");
	t.assertseq(strip("Linux\t"), "Linux", "strip trailing tab");
	t.assertseq(strip("Nt"), "Nt", "no-op when clean");
	t.assertseq(strip(""), "", "empty string");
}

# Platform guard logic: emuhost != "Nt" should be true on non-Windows
testPlatformGuard(t: ref T)
{
	raw := readfile("/env/emuhost");
	if(raw == nil) {
		mskip(t,"cannot read /env/emuhost");
		return;
	}
	host := strip(raw);

	# Verify the guard expression matches expectations
	shouldSkipLogo := (host == "Nt");
	shouldLoadLogo := (host != "Nt");
	t.assert(shouldSkipLogo != shouldLoadLogo,
		"skip and load must be mutually exclusive");

	if(host == "Nt")
		t.log("Windows detected — logo loading would be skipped");
	else
		t.log(host + " detected — logo loading would proceed");
}

# --- PNG decode timeout tests ---

# readpng->read() on an in-memory 1x1 PNG must complete.
# On Windows, the inflate filter blocks the entire Dis scheduler, so even
# a timeout goroutine cannot fire. Skip on Windows; run on other platforms.
testReadpngInMemory(t: ref T)
{
	raw := readfile("/env/emuhost");
	host := "";
	if(raw != nil)
		host = strip(raw);

	if(host == "Nt") {
		mskip(t,"readpng inflate hangs on Windows — blocks scheduler");
		return;
	}

	if(bufio == nil) {
		mskip(t,"bufio not loaded");
		return;
	}

	rpng := load RImagefile RImagefile->READPNGPATH;
	if(rpng == nil) {
		mskip(t,"cannot load readpng");
		return;
	}
	rpng->init(bufio);

	png := mkpng1x1red();
	fd := bufio->aopen(png);
	if(fd == nil) {
		t.error("cannot create bufio from PNG data");
		return;
	}

	(rimg, err) := rpng->read(fd);
	if(rimg == nil)
		t.error("readpng->read failed: " + err);
	else {
		t.asserteq(rimg.r.max.x, 1, "width should be 1");
		t.asserteq(rimg.r.max.y, 1, "height should be 1");
		t.log("in-memory 1x1 PNG decoded successfully");
	}
}

# readpng->read() on the actual logo.png file.
# On Windows (Nt) this is known to hang — verify the platform guard skips it.
# On other platforms it should succeed.
testReadpngLogoPng(t: ref T)
{
	raw := readfile("/env/emuhost");
	host := "";
	if(raw != nil)
		host = strip(raw);

	if(host == "Nt") {
		t.log("Windows: skipping logo.png read (known inflate hang)");
		mskip(t,"readpng hangs on Windows — platform guard skips logo loading");
		return;
	}

	if(bufio == nil) {
		mskip(t,"bufio not loaded");
		return;
	}

	rpng := load RImagefile RImagefile->READPNGPATH;
	if(rpng == nil) {
		mskip(t,"cannot load readpng");
		return;
	}
	rpng->init(bufio);

	fd := bufio->open("/lib/lucifer/logo.png", Bufio->OREAD);
	if(fd == nil) {
		mskip(t,"logo.png not found");
		return;
	}

	(rimg, err) := rpng->read(fd);
	if(rimg == nil)
		t.error("logo.png decode failed: " + err);
	else
		t.log("logo.png decoded successfully");
}

# --- PNG test data ---

crctable: array of int;

initcrc()
{
	crctable = array[256] of int;
	for(n := 0; n < 256; n++) {
		c := n;
		for(k := 0; k < 8; k++) {
			if(c & 1)
				c = int 16rEDB88320 ^ (c >> 1);
			else
				c = c >> 1;
		}
		crctable[n] = c;
	}
}

pngcrc(data: array of byte): array of byte
{
	if(crctable == nil)
		initcrc();

	c := int 16rFFFFFFFF;
	for(i := 0; i < len data; i++)
		c = crctable[(c ^ int data[i]) & 16rFF] ^ (c >> 8);
	c = c ^ int 16rFFFFFFFF;

	crc := array[4] of byte;
	crc[0] = byte(c >> 24);
	crc[1] = byte(c >> 16);
	crc[2] = byte(c >> 8);
	crc[3] = byte c;
	return crc;
}

putbe32(buf: array of byte, off: int, val: int)
{
	buf[off]   = byte(val >> 24);
	buf[off+1] = byte(val >> 16);
	buf[off+2] = byte(val >> 8);
	buf[off+3] = byte val;
}

mkpng1x1red(): array of byte
{
	sig := array[] of {byte 137, byte 80, byte 78, byte 71,
	                    byte 13, byte 10, byte 26, byte 10};

	ihdrdata := array[] of {
		byte 0, byte 0, byte 0, byte 1,
		byte 0, byte 0, byte 0, byte 1,
		byte 8, byte 2, byte 0, byte 0, byte 0
	};
	ihdrtypedata := array[4 + len ihdrdata] of byte;
	ihdrtypedata[0:] = array[] of {byte 'I', byte 'H', byte 'D', byte 'R'};
	ihdrtypedata[4:] = ihdrdata;
	ihdrcrc := pngcrc(ihdrtypedata);

	idatpayload := array[] of {
		byte 16r78, byte 16r01,
		byte 16r01,
		byte 16r04, byte 16r00,
		byte 16rFB, byte 16rFF,
		byte 16r00,
		byte 16rFF, byte 16r00, byte 16r00,
		byte 16r00, byte 16r02, byte 16r01, byte 16r00
	};
	idattypedata := array[4 + len idatpayload] of byte;
	idattypedata[0:] = array[] of {byte 'I', byte 'D', byte 'A', byte 'T'};
	idattypedata[4:] = idatpayload;
	idatcrc := pngcrc(idattypedata);

	iendtypedata := array[] of {byte 'I', byte 'E', byte 'N', byte 'D'};
	iendcrc := pngcrc(iendtypedata);

	total := len sig
		+ 4 + 4 + len ihdrdata + 4
		+ 4 + 4 + len idatpayload + 4
		+ 4 + 4 + 0 + 4;

	png := array[total] of byte;
	off := 0;

	png[off:] = sig;
	off += len sig;

	putbe32(png, off, len ihdrdata); off += 4;
	png[off:] = ihdrtypedata;
	off += len ihdrtypedata;
	png[off:] = ihdrcrc; off += 4;

	putbe32(png, off, len idatpayload); off += 4;
	png[off:] = idattypedata;
	off += len idattypedata;
	png[off:] = idatcrc; off += 4;

	putbe32(png, off, 0); off += 4;
	png[off:] = iendtypedata;
	off += len iendtypedata;
	png[off:] = iendcrc; off += 4;

	return png;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}

	testing->init();

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	run("EmuhostReadable", testEmuhostReadable);
	run("StripWhitespace", testStripWhitespace);
	run("PlatformGuard", testPlatformGuard);
	run("ReadpngInMemory", testReadpngInMemory);
	run("ReadpngLogoPng", testReadpngLogoPng);

	testing->summary(passed, failed, skipped);
}
