implement TextwidgetTest;

#
# Tests for the Textwidget module: Tabulator, wrapend, drawselection
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

include "textwidget.m";
	textwidget: Textwidget;
	Tabulator: import textwidget;

TextwidgetTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/textwidget_test.b";

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

# ── Tabulator.expand tests ───────────────────────────────────

testExpandNoTabs(t: ref T)
{
	tab := Tabulator.new(4);
	t.assertseq(tab.expand("hello"), "hello", "no tabs unchanged");
	t.assertseq(tab.expand(""), "", "empty string unchanged");
	t.assertseq(tab.expand("abc def"), "abc def", "spaces unchanged");
}

testExpandSingleTab(t: ref T)
{
	tab := Tabulator.new(4);
	# Tab at column 0 should expand to 4 spaces
	result := tab.expand("\t");
	t.asserteq(len result, 4, "tab at col 0 expands to 4 spaces");
	t.assertseq(result, "    ", "tab at col 0 is 4 spaces");
}

testExpandTabAfterText(t: ref T)
{
	tab := Tabulator.new(4);
	# "ab\t" — 'a' at 0, 'b' at 1, tab at col 2 → 2 spaces to reach col 4
	result := tab.expand("ab\t");
	t.assertseq(result, "ab  ", "tab after 2 chars pads to next stop");
	t.asserteq(len result, 4, "result length is 4");
}

testExpandTabAtStop(t: ref T)
{
	tab := Tabulator.new(4);
	# "abcd\t" — tab at col 4 → full 4 spaces to reach col 8
	result := tab.expand("abcd\t");
	t.asserteq(len result, 8, "tab at tabstop boundary expands to full tabstop");
}

testExpandMultipleTabs(t: ref T)
{
	tab := Tabulator.new(4);
	result := tab.expand("\t\t");
	t.asserteq(len result, 8, "two tabs at start = 8 spaces");

	result = tab.expand("a\tb\t");
	# 'a' at 0, tab→col 4, 'b' at 4, tab→col 8
	t.asserteq(len result, 8, "a<tab>b<tab> = 8 chars");
}

testExpandTabstop8(t: ref T)
{
	tab := Tabulator.new(8);
	result := tab.expand("\t");
	t.asserteq(len result, 8, "tabstop 8: tab at col 0 = 8 spaces");

	result = tab.expand("abc\t");
	t.asserteq(len result, 8, "tabstop 8: tab after 3 chars pads to 8");
}

# ── Tabulator.unexpandcol tests ──────────────────────────────

testUnexpandcolNoTabs(t: ref T)
{
	tab := Tabulator.new(4);
	t.asserteq(tab.unexpandcol("hello", 3), 3, "no tabs: expcol 3 → offset 3");
	t.asserteq(tab.unexpandcol("hello", 5), 5, "no tabs: expcol 5 → offset 5");
	t.asserteq(tab.unexpandcol("hello", 0), 0, "no tabs: expcol 0 → offset 0");
}

testUnexpandcolWithTab(t: ref T)
{
	tab := Tabulator.new(4);
	# "\thello" — tab expands cols 0-3, 'h' at col 4
	# expcol 4 should map to offset 1 (just past the tab)
	t.asserteq(tab.unexpandcol("\thello", 4), 1, "expcol 4 past tab → offset 1");
	# expcol 5 → 'e' at offset 2
	t.asserteq(tab.unexpandcol("\thello", 5), 2, "expcol 5 → offset 2");
}

testUnexpandcolMidTab(t: ref T)
{
	tab := Tabulator.new(4);
	# "ab\tcd" — tab at col 2 expands to 2 spaces (cols 2-3)
	# expcol 3 is inside the tab → should snap to end of tab (offset 3, the 'c')
	result := tab.unexpandcol("ab\tcd", 4);
	t.asserteq(result, 3, "expcol at tab end → offset past tab");
}

testUnexpandcolBeyondEnd(t: ref T)
{
	tab := Tabulator.new(4);
	t.asserteq(tab.unexpandcol("abc", 10), 3, "expcol beyond string → string length");
}

# ── Tabulator.expandedcol tests ──────────────────────────────

testExpandedcolNoTabs(t: ref T)
{
	tab := Tabulator.new(4);
	t.asserteq(tab.expandedcol("hello", 0), 0, "col 0 → ecol 0");
	t.asserteq(tab.expandedcol("hello", 3), 3, "col 3 → ecol 3 (no tabs)");
	t.asserteq(tab.expandedcol("hello", 5), 5, "col 5 → ecol 5 (no tabs)");
}

testExpandedcolWithTab(t: ref T)
{
	tab := Tabulator.new(4);
	# "\thello" — col 0 → ecol 0, col 1 → ecol 4 (tab expanded)
	t.asserteq(tab.expandedcol("\thello", 1), 4, "col 1 past tab → ecol 4");
	t.asserteq(tab.expandedcol("\thello", 2), 5, "col 2 → ecol 5");
}

testExpandedcolTabAfterText(t: ref T)
{
	tab := Tabulator.new(4);
	# "ab\tcd" — col 2 is 'b', ecol 2; col 3 is past tab, ecol 4
	t.asserteq(tab.expandedcol("ab\tcd", 2), 2, "col 2 before tab → ecol 2");
	t.asserteq(tab.expandedcol("ab\tcd", 3), 4, "col 3 past tab → ecol 4");
	t.asserteq(tab.expandedcol("ab\tcd", 4), 5, "col 4 → ecol 5");
}

# ── Roundtrip tests ──────────────────────────────────────────

testExpandUnexpandRoundtrip(t: ref T)
{
	tab := Tabulator.new(4);
	cases := array[] of {
		"hello",
		"\thello",
		"ab\tcd",
		"\t\t",
		"abcd\tefgh\t",
	};
	for(i := 0; i < len cases; i++) {
		s := cases[i];
		# For each original offset, expand then unexpand should roundtrip
		for(col := 0; col <= len s; col++) {
			ecol := tab.expandedcol(s, col);
			back := tab.unexpandcol(s, ecol);
			t.asserteq(back, col,
				sys->sprint("roundtrip '%s' col %d → ecol %d → %d",
					s, col, ecol, back));
		}
	}
}

# ── Tabulator.new edge cases ────────────────────────────────

testNewZeroTabstop(t: ref T)
{
	# tabstop <= 0 should default to 8
	tab := Tabulator.new(0);
	result := tab.expand("\t");
	t.asserteq(len result, 8, "tabstop 0 defaults to 8");

	tab = Tabulator.new(-1);
	result = tab.expand("\t");
	t.asserteq(len result, 8, "tabstop -1 defaults to 8");
}

# ── wrapend tests ────────────────────────────────────────────

# We can't test wrapend without a font (it needs pixel widths).
# Skip these tests when no display is available.

testWrapendEmptyString(t: ref T)
{
	# wrapend with empty string or start >= len should return len
	# This doesn't need a font since it returns early
	t.asserteq(textwidget->wrapend(nil, "", 0, 100), 0,
		"wrapend empty string returns 0");
	t.asserteq(textwidget->wrapend(nil, "hello", 5, 100), 5,
		"wrapend start at end returns len");
	t.asserteq(textwidget->wrapend(nil, "hello", 10, 100), 5,
		"wrapend start beyond end returns len");
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

	textwidget = load Textwidget Textwidget->PATH;
	if(textwidget == nil) {
		sys->fprint(sys->fildes(2), "cannot load Textwidget: %r\n");
		raise "fail:cannot load Textwidget";
	}
	textwidget->init();

	# Tabulator.expand
	run("ExpandNoTabs", testExpandNoTabs);
	run("ExpandSingleTab", testExpandSingleTab);
	run("ExpandTabAfterText", testExpandTabAfterText);
	run("ExpandTabAtStop", testExpandTabAtStop);
	run("ExpandMultipleTabs", testExpandMultipleTabs);
	run("ExpandTabstop8", testExpandTabstop8);

	# Tabulator.unexpandcol
	run("UnexpandcolNoTabs", testUnexpandcolNoTabs);
	run("UnexpandcolWithTab", testUnexpandcolWithTab);
	run("UnexpandcolMidTab", testUnexpandcolMidTab);
	run("UnexpandcolBeyondEnd", testUnexpandcolBeyondEnd);

	# Tabulator.expandedcol
	run("ExpandedcolNoTabs", testExpandedcolNoTabs);
	run("ExpandedcolWithTab", testExpandedcolWithTab);
	run("ExpandedcolTabAfterText", testExpandedcolTabAfterText);

	# Roundtrip
	run("ExpandUnexpandRoundtrip", testExpandUnexpandRoundtrip);

	# Edge cases
	run("NewZeroTabstop", testNewZeroTabstop);

	# wrapend (limited — no font available)
	run("WrapendEmptyString", testWrapendEmptyString);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
