implement LucithemeTest;

#
# Regression tests for Lucitheme module (2026-03).
#
# Covers:
#   - Lucitheme->gettheme() renamed from load() (Limbo reserved keyword fix)
#   - Brimstone default colour values used by wmclient and luciedit
#   - wmclient border colour fix: accent (not hardcoded teal 0x448888FF)
#   - wmclient border colour fix: border (not hardcoded cyan 0x9EEEEEFF)
#   - wmclient background fix: bg is not white (no white flash on window close)
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

include "lucitheme.m";
	lucitheme: Lucitheme;

LucithemeTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/lucitheme_test.b";

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

testBrimstoneNotNil(t: ref T)
{
	th := lucitheme->brimstone();
	t.assert(th != nil, "brimstone() returns non-nil");
}

testBrimstoneColors(t: ref T)
{
	th := lucitheme->brimstone();
	if(!t.assert(th != nil, "brimstone() returns non-nil"))
		return;

	# Core UI colours
	t.asserteq(th.bg,     int 16r080808FF, "bg is near-black (0x080808FF)");
	t.asserteq(th.border, int 16r131313FF, "border is near-black (0x131313FF)");
	t.asserteq(th.accent, int 16rE8553AFF, "accent is orange (0xE8553AFF)");
	t.asserteq(th.text,   int 16rCCCCCCFF, "text is light grey (0xCCCCCCFF)");

	# Editor colours (luciedit theme integration)
	t.asserteq(th.editbg,     int 16r0D0D0DFF, "editbg is near-black (0x0D0D0DFF)");
	t.asserteq(th.edittext,   int 16rCCCCCCFF, "edittext is light grey (0xCCCCCCFF)");
	t.asserteq(th.editcursor, int 16rE8553AFF, "editcursor is orange/accent (0xE8553AFF)");
	t.asserteq(th.red,        int 16rAA4444FF, "red is muted red (0xAA4444FF)");

	# wmclient border fix: bdfocused = th.accent, NOT old hardcoded teal
	t.assertne(th.accent, int 16r448888FF, "accent is not old hardcoded teal (0x448888FF)");

	# wmclient border fix: bdunfocused = th.border, NOT old hardcoded cyan
	t.assertne(th.border, int 16r9EEEEEFF, "border is not old hardcoded cyan (0x9EEEEEFF)");

	# wmclient background fix: screenbg = th.bg, must not be white
	t.assertne(th.bg, int 16rFFFFFFFF, "bg is not white — no white flash on window close");
}

testGetThemeNotNil(t: ref T)
{
	# gettheme() was renamed from load() which is a Limbo reserved keyword.
	# If this symbol doesn't exist, the test won't compile — that's the regression.
	th := lucitheme->gettheme();
	t.assert(th != nil, "gettheme() returns non-nil (falls back to brimstone if no theme file)");
}

testGetThemeAlpha(t: ref T)
{
	# All colour fields produced by gettheme() must have full alpha (0xFF low byte).
	# parsehex() in lucitheme.b always ORs 0xFF; this test confirms the invariant holds.
	th := lucitheme->gettheme();
	if(!t.assert(th != nil, "gettheme() returns non-nil"))
		return;

	t.asserteq(th.bg     & 16rFF, 16rFF, "bg has full alpha");
	t.asserteq(th.border & 16rFF, 16rFF, "border has full alpha");
	t.asserteq(th.accent & 16rFF, 16rFF, "accent has full alpha");
	t.asserteq(th.editbg & 16rFF, 16rFF, "editbg has full alpha");
	t.asserteq(th.text   & 16rFF, 16rFF, "text has full alpha");
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

	lucitheme = load Lucitheme Lucitheme->PATH;
	if(lucitheme == nil) {
		sys->fprint(sys->fildes(2), "cannot load lucitheme module: %r\n");
		raise "fail:cannot load lucitheme";
	}

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	run("BrimstoneNotNil",  testBrimstoneNotNil);
	run("BrimstoneColors",  testBrimstoneColors);
	run("GetThemeNotNil",   testGetThemeNotNil);
	run("GetThemeAlpha",    testGetThemeAlpha);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
