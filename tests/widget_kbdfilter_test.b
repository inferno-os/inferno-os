implement WidgetKbdfilterTest;

#
# Tests for Widget.Kbdfilter — ANSI escape sequence decoder
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Font: import draw;

include "testing.m";
	testing: Testing;
	T: import testing;

include "widget.m";
	widgetmod: Widget;
	Kbdfilter: import widgetmod;

WidgetKbdfilterTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/widget_kbdfilter_test.b";

passed := 0;
failed := 0;
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

# Key constants for assertions
Khome:   con 16rFF61;
Kend:    con 16rFF57;
Kup:     con 16rFF52;
Kdown:   con 16rFF54;
Kleft:   con 16rFF51;
Kright:  con 16rFF53;
Kpgup:   con 16rFF55;
Kpgdown: con 16rFF56;

# ── Passthrough tests ────────────────────────────────────────

testPassthroughPrintable(t: ref T)
{
	kf := Kbdfilter.new();
	# Regular printable characters pass through unchanged
	t.asserteq(kf.filter('a'), 'a', "lowercase a");
	t.asserteq(kf.filter('Z'), 'Z', "uppercase Z");
	t.asserteq(kf.filter(' '), ' ', "space");
	t.asserteq(kf.filter('0'), '0', "digit 0");
	t.asserteq(kf.filter('\n'), '\n', "newline");
	t.asserteq(kf.filter('\t'), '\t', "tab");
}

testPassthroughInfernoKeys(t: ref T)
{
	kf := Kbdfilter.new();
	# Inferno key codes >= 0xFF00 pass through unchanged
	t.asserteq(kf.filter(Kup), Kup, "Inferno Kup passthrough");
	t.asserteq(kf.filter(Kdown), Kdown, "Inferno Kdown passthrough");
	t.asserteq(kf.filter(Khome), Khome, "Inferno Khome passthrough");
}

# ── Arrow key sequences ─────────────────────────────────────

testArrowUp(t: ref T)
{
	kf := Kbdfilter.new();
	t.asserteq(kf.filter(27), -1, "ESC consumed");
	t.asserteq(kf.filter('['), -1, "[ consumed");
	t.asserteq(kf.filter('A'), Kup, "A → Kup");
}

testArrowDown(t: ref T)
{
	kf := Kbdfilter.new();
	t.asserteq(kf.filter(27), -1, "ESC");
	t.asserteq(kf.filter('['), -1, "[");
	t.asserteq(kf.filter('B'), Kdown, "B → Kdown");
}

testArrowRight(t: ref T)
{
	kf := Kbdfilter.new();
	t.asserteq(kf.filter(27), -1, "ESC");
	t.asserteq(kf.filter('['), -1, "[");
	t.asserteq(kf.filter('C'), Kright, "C → Kright");
}

testArrowLeft(t: ref T)
{
	kf := Kbdfilter.new();
	t.asserteq(kf.filter(27), -1, "ESC");
	t.asserteq(kf.filter('['), -1, "[");
	t.asserteq(kf.filter('D'), Kleft, "D → Kleft");
}

# ── Home/End sequences ───────────────────────────────────────

testHomeShort(t: ref T)
{
	kf := Kbdfilter.new();
	# ESC [ H → Home
	t.asserteq(kf.filter(27), -1, "ESC");
	t.asserteq(kf.filter('['), -1, "[");
	t.asserteq(kf.filter('H'), Khome, "H → Khome");
}

testEndShort(t: ref T)
{
	kf := Kbdfilter.new();
	# ESC [ F → End
	t.asserteq(kf.filter(27), -1, "ESC");
	t.asserteq(kf.filter('['), -1, "[");
	t.asserteq(kf.filter('F'), Kend, "F → Kend");
}

testHomeLong(t: ref T)
{
	kf := Kbdfilter.new();
	# ESC [ 1 ~ → Home
	t.asserteq(kf.filter(27), -1, "ESC");
	t.asserteq(kf.filter('['), -1, "[");
	t.asserteq(kf.filter('1'), -1, "1 consumed");
	t.asserteq(kf.filter('~'), Khome, "1~ → Khome");
}

testEndLong(t: ref T)
{
	kf := Kbdfilter.new();
	# ESC [ 4 ~ → End
	t.asserteq(kf.filter(27), -1, "ESC");
	t.asserteq(kf.filter('['), -1, "[");
	t.asserteq(kf.filter('4'), -1, "4 consumed");
	t.asserteq(kf.filter('~'), Kend, "4~ → Kend");
}

testHome7(t: ref T)
{
	kf := Kbdfilter.new();
	# ESC [ 7 ~ → Home (rxvt)
	t.asserteq(kf.filter(27), -1, "ESC");
	t.asserteq(kf.filter('['), -1, "[");
	t.asserteq(kf.filter('7'), -1, "7 consumed");
	t.asserteq(kf.filter('~'), Khome, "7~ → Khome");
}

testEnd8(t: ref T)
{
	kf := Kbdfilter.new();
	# ESC [ 8 ~ → End (rxvt)
	t.asserteq(kf.filter(27), -1, "ESC");
	t.asserteq(kf.filter('['), -1, "[");
	t.asserteq(kf.filter('8'), -1, "8 consumed");
	t.asserteq(kf.filter('~'), Kend, "8~ → Kend");
}

# ── Page Up/Down ─────────────────────────────────────────────

testPageUp(t: ref T)
{
	kf := Kbdfilter.new();
	# ESC [ 5 ~ → PgUp
	t.asserteq(kf.filter(27), -1, "ESC");
	t.asserteq(kf.filter('['), -1, "[");
	t.asserteq(kf.filter('5'), -1, "5 consumed");
	t.asserteq(kf.filter('~'), Kpgup, "5~ → Kpgup");
}

testPageDown(t: ref T)
{
	kf := Kbdfilter.new();
	# ESC [ 6 ~ → PgDn
	t.asserteq(kf.filter(27), -1, "ESC");
	t.asserteq(kf.filter('['), -1, "[");
	t.asserteq(kf.filter('6'), -1, "6 consumed");
	t.asserteq(kf.filter('~'), Kpgdown, "6~ → Kpgdown");
}

# ── State machine recovery ──────────────────────────────────

testBareEsc(t: ref T)
{
	kf := Kbdfilter.new();
	# ESC followed by non-[ should deliver the char
	t.asserteq(kf.filter(27), -1, "ESC consumed");
	t.asserteq(kf.filter('x'), 'x', "bare ESC + x → x");
}

testResetAfterSequence(t: ref T)
{
	kf := Kbdfilter.new();
	# After a complete sequence, normal keys should work
	t.asserteq(kf.filter(27), -1, "ESC");
	t.asserteq(kf.filter('['), -1, "[");
	t.asserteq(kf.filter('A'), Kup, "A → Kup");
	# Now a regular key
	t.asserteq(kf.filter('h'), 'h', "h after sequence");
}

testMultipleSequences(t: ref T)
{
	kf := Kbdfilter.new();
	# Two arrow sequences back to back
	t.asserteq(kf.filter(27), -1, "ESC 1");
	t.asserteq(kf.filter('['), -1, "[ 1");
	t.asserteq(kf.filter('A'), Kup, "up 1");

	t.asserteq(kf.filter(27), -1, "ESC 2");
	t.asserteq(kf.filter('['), -1, "[ 2");
	t.asserteq(kf.filter('B'), Kdown, "down 2");
}

testUnknownSequenceRecovery(t: ref T)
{
	kf := Kbdfilter.new();
	# ESC [ followed by unknown letter
	t.asserteq(kf.filter(27), -1, "ESC");
	t.asserteq(kf.filter('['), -1, "[");
	t.asserteq(kf.filter('Z'), -1, "unknown Z discarded");
	# Should be back in ground state
	t.asserteq(kf.filter('a'), 'a', "a after unknown sequence");
}

# ── Independent instances ────────────────────────────────────

testIndependentInstances(t: ref T)
{
	kf1 := Kbdfilter.new();
	kf2 := Kbdfilter.new();

	# Start a sequence on kf1
	t.asserteq(kf1.filter(27), -1, "kf1 ESC");
	# kf2 should be unaffected
	t.asserteq(kf2.filter('x'), 'x', "kf2 independent");
	# Continue kf1
	t.asserteq(kf1.filter('['), -1, "kf1 [");
	t.asserteq(kf1.filter('A'), Kup, "kf1 up");
	# kf2 still clean
	t.asserteq(kf2.filter('y'), 'y', "kf2 still independent");
}

# ── Multi-digit argument ────────────────────────────────────

testMultiDigitArg(t: ref T)
{
	kf := Kbdfilter.new();
	# ESC [ 1 5 ~ — multi-digit unknown arg, should discard
	t.asserteq(kf.filter(27), -1, "ESC");
	t.asserteq(kf.filter('['), -1, "[");
	t.asserteq(kf.filter('1'), -1, "1");
	t.asserteq(kf.filter('5'), -1, "5 (multi-digit)");
	t.asserteq(kf.filter('~'), -1, "15~ unknown → discard");
	# Back in ground state
	t.asserteq(kf.filter('a'), 'a', "a after multi-digit");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
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

	widgetmod = load Widget Widget->PATH;
	if(widgetmod == nil) {
		sys->fprint(sys->fildes(2), "cannot load Widget: %r\n");
		raise "fail:cannot load Widget";
	}
	# Widget.init needs a display and font — but Kbdfilter doesn't
	# use any display resources.  We need to call init() to satisfy
	# module loading, but we can pass nils for a headless test since
	# we're only testing Kbdfilter.
	widgetmod->init(nil, nil);

	# Passthrough
	run("PassthroughPrintable", testPassthroughPrintable);
	run("PassthroughInfernoKeys", testPassthroughInfernoKeys);

	# Arrow keys
	run("ArrowUp", testArrowUp);
	run("ArrowDown", testArrowDown);
	run("ArrowRight", testArrowRight);
	run("ArrowLeft", testArrowLeft);

	# Home/End
	run("HomeShort", testHomeShort);
	run("EndShort", testEndShort);
	run("HomeLong", testHomeLong);
	run("EndLong", testEndLong);
	run("Home7", testHome7);
	run("End8", testEnd8);

	# Page Up/Down
	run("PageUp", testPageUp);
	run("PageDown", testPageDown);

	# State machine recovery
	run("BareEsc", testBareEsc);
	run("ResetAfterSequence", testResetAfterSequence);
	run("MultipleSequences", testMultipleSequences);
	run("UnknownSequenceRecovery", testUnknownSequenceRecovery);

	# Independent instances
	run("IndependentInstances", testIndependentInstances);

	# Multi-digit
	run("MultiDigitArg", testMultiDigitArg);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
