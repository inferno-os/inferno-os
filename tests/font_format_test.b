implement FontFormatTest;

#
# Regression tests for combined font file format (2026-03).
#
# Covers:
#   - No # comment lines: buildfont.c skip() does not handle '#'; if present,
#     buildfont() returns NULL → Font.open() returns nil → fallback to
#     *default* bitmap font → SDL3 bilinear upscaling on Retina = smeared text.
#   - Correct "16\t12" header (height=16, ascent=12).
#   - All data lines: 3 tab-separated fields, startcode <= endcode.
#   - Arabic range: 0621-063A (old broken range 0621-0652 had wrong endpoint).
#   - Thai range: split into 0E01-0E3A and 0E3F-0E5B (0E3B-0E3E are unassigned).
#   - unicode.14.font uses DejaVuSansMono (not DejaVuSans).
#   - unicode.sans.14.font uses DejaVuSans (not DejaVuSansMono).
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

FontFormatTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/font_format_test.b";

passed  := 0;
failed  := 0;
skipped := 0;

run(name: string, testfn: ref fn(t: ref T))
{
	t := testing->newTsrc(name, SRCFILE);
	{
		testfn(t);
	} exception {
	"fail:fatal" =>
		;
	"fail:skip" =>
		;
	"*" =>
		t.failed = 1;
	}

	if(testing->done(t))
		passed++;
	else if(t.skipped)
		skipped++;
	else
		failed++;
}

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[2*1024*1024] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	return string buf[0:n];
}

# Return 1 if needle is a substring of haystack, 0 otherwise.
contains(haystack, needle: string): int
{
	hn := len needle;
	hh := len haystack;
	if(hn == 0)
		return 1;
	if(hn > hh)
		return 0;
	for(i := 0; i <= hh - hn; i++) {
		if(haystack[i:i+hn] == needle)
			return 1;
	}
	return 0;
}

# Parse a 0x-prefixed hex string.  Returns -1 on error.
hexparse(s: string): int
{
	if(len s < 2 || s[0] != '0' || (s[1] != 'x' && s[1] != 'X'))
		return -1;
	v := 0;
	for(i := 2; i < len s; i++) {
		c := s[i];
		if(c >= '0' && c <= '9')
			v = v * 16 + (c - '0');
		else if(c >= 'a' && c <= 'f')
			v = v * 16 + (c - 'a' + 10);
		else if(c >= 'A' && c <= 'F')
			v = v * 16 + (c - 'A' + 10);
		else
			return -1;
	}
	return v;
}

# Structural validator: no comment lines, correct header, valid ranges.
checkfontfile(t: ref T, path: string)
{
	data := readfile(path);
	if(!t.assert(data != nil, "can read " + path))
		return;

	(nlines, lines) := sys->tokenize(data, "\n");
	if(!t.assert(nlines > 1, path + " has multiple lines"))
		return;

	# Regression: # comment lines cause buildfont() to fail silently.
	ll: list of string;
	ncomments := 0;
	for(ll = lines; ll != nil; ll = tl ll) {
		line := hd ll;
		if(len line > 0 && line[0] == '#')
			ncomments++;
	}
	t.asserteq(ncomments, 0, path + ": no # comment lines (buildfont.c cannot parse them)");

	# Header must be "16<tab>12"
	firstline := hd lines;
	t.assertseq(firstline, "16\t12", path + ": header is '16<tab>12'");

	# Every data line must have exactly 3 tab-separated fields with 0x codes
	# and startcode <= endcode.
	badformat := 0;
	badorder  := 0;
	for(ll = tl lines; ll != nil; ll = tl ll) {
		line := hd ll;
		if(len line == 0)
			continue;
		(ntoks, toks) := sys->tokenize(line, "\t");
		if(ntoks != 3) {
			badformat++;
			t.log("bad format (not 3 fields): " + line);
			continue;
		}
		s := hd toks;
		e := hd tl toks;
		sv := hexparse(s);
		ev := hexparse(e);
		if(sv < 0 || ev < 0) {
			badformat++;
			t.log("bad hex codes: " + s + " " + e);
			continue;
		}
		if(sv > ev) {
			badorder++;
			t.log("inverted range: " + s + " > " + e);
		}
	}
	t.asserteq(badformat, 0, path + ": all data lines have 3 tab-separated fields with 0x codes");
	t.asserteq(badorder,  0, path + ": all data lines have startcode <= endcode");
}

testMonoFontFormat(t: ref T)
{
	checkfontfile(t, "/fonts/combined/unicode.14.font");
}

testSansFontFormat(t: ref T)
{
	checkfontfile(t, "/fonts/combined/unicode.sans.14.font");
}

# Entry-level checks for unicode.14.font (monospace).
testMonoFontEntries(t: ref T)
{
	data := readfile("/fonts/combined/unicode.14.font");
	if(!t.assert(data != nil, "unicode.14.font readable"))
		return;

	# Arabic base block: regression — was broken as 0621-0652; fixed to 0621-063A
	t.assert(contains(data, "0x0621\t0x063A"), "Arabic base range is 0621-063A");
	t.assert(!contains(data, "0x0621\t0x0652"), "no old broken Arabic range 0621-0652");

	# Thai: must be split into two ranges (gap at 0E3B-0E3E which are unassigned)
	t.assert(contains(data, "0x0E01\t0x0E3A"), "Thai first range 0E01-0E3A");
	t.assert(contains(data, "0x0E3F\t0x0E5B"), "Thai second range 0E3F-0E5B");
	t.assert(!contains(data, "0x0E01\t0x0E5B"), "no monolithic Thai range 0E01-0E5B");

	# Must use DejaVuSansMono for the monospace UI font
	t.assert(contains(data, "DejaVuSansMono"), "monospace font uses DejaVuSansMono subfonts");
	# DejaVuSans/ (non-mono) must not appear — it would break fixed-width layout
	t.assert(!contains(data, "DejaVuSans/"), "no DejaVuSans/ references in monospace font");
}

# Entry-level checks for unicode.sans.14.font (proportional/sans).
testSansFontEntries(t: ref T)
{
	data := readfile("/fonts/combined/unicode.sans.14.font");
	if(!t.assert(data != nil, "unicode.sans.14.font readable"))
		return;

	# Arabic base block: same fix applies
	t.assert(contains(data, "0x0621\t0x063A"), "Arabic base range is 0621-063A");
	t.assert(!contains(data, "0x0621\t0x0652"), "no old broken Arabic range 0621-0652");

	# Thai split
	t.assert(contains(data, "0x0E01\t0x0E3A"), "Thai first range 0E01-0E3A");
	t.assert(contains(data, "0x0E3F\t0x0E5B"), "Thai second range 0E3F-0E5B");
	t.assert(!contains(data, "0x0E01\t0x0E5B"), "no monolithic Thai range 0E01-0E5B");

	# Must use DejaVuSans (proportional), not DejaVuSansMono
	t.assert(contains(data, "DejaVuSans/"), "sans font uses DejaVuSans/ subfonts");
	t.assert(!contains(data, "DejaVuSansMono"), "sans font does not reference DejaVuSansMono");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
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

	run("MonoFontFormat",  testMonoFontFormat);
	run("SansFontFormat",  testSansFontFormat);
	run("MonoFontEntries", testMonoFontEntries);
	run("SansFontEntries", testSansFontEntries);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
