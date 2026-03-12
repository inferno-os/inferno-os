implement MenuTest;

#
# menu_test - Regression tests for the contextual menu widget
#
# Verifies that the Menu module loads correctly with the current
# Popup adt layout.  A common failure mode is stale callers compiled
# against an older menu.m that has a different Popup field layout;
# the Dis VM rejects the type mismatch on load and returns nil.
#
# These tests verify:
#   - Module loads successfully (adt type descriptors match)
#   - new() creates properly initialised Popups
#   - newgen() creates properly initialised generator Popups
#   - Generator functions are invoked correctly
#   - Submenu (subs) wiring works
#   - Field defaults match expected values
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

include "menu.m";
	menumod: Menu;

MenuTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

# Source file path for clickable error addresses
SRCFILE: con "/tests/menu_test.b";

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

# --- Tests ---

# Verify the Menu module loads at all.  This is the key regression
# test: if the caller was compiled against a stale menu.m with a
# different Popup adt layout, load returns nil.
testModuleLoad(t: ref T)
{
	t.assert(menumod != nil, "Menu module loaded successfully");
}

# Verify new() returns a non-nil Popup with correct field values.
testNewPopup(t: ref T)
{
	if(menumod == nil) {
		t.skip("Menu module not loaded");
		return;
	}

	items := array[] of {"Alpha", "Beta", "Gamma"};
	p := menumod->new(items);
	t.assert(p != nil, "new() returns non-nil Popup");
	t.asserteq(len p.items, 3, "items length");
	t.assertseq(p.items[0], "Alpha", "items[0]");
	t.assertseq(p.items[1], "Beta", "items[1]");
	t.assertseq(p.items[2], "Gamma", "items[2]");
	t.asserteq(p.lasthit, 0, "lasthit default");
	t.assert(p.gen == nil, "gen is nil for static menu");
	t.assert(p.subs == nil, "subs is nil for static menu");
	t.asserteq(p.lastsub, -1, "lastsub default");
}

# Verify new() with a single item.
testNewSingleItem(t: ref T)
{
	if(menumod == nil) {
		t.skip("Menu module not loaded");
		return;
	}

	items := array[] of {"Only"};
	p := menumod->new(items);
	t.assert(p != nil, "single-item Popup created");
	t.asserteq(len p.items, 1, "single item length");
	t.assertseq(p.items[0], "Only", "single item value");
}

# Verify new() with an empty array returns a Popup (show() will
# return -1 early, but new() itself should not fail).
testNewEmptyItems(t: ref T)
{
	if(menumod == nil) {
		t.skip("Menu module not loaded");
		return;
	}

	items := array[0] of string;
	p := menumod->new(items);
	t.assert(p != nil, "empty-items Popup created");
	t.asserteq(len p.items, 0, "empty items length");
}

# Verify newgen() returns a non-nil Popup with generator set.
testNewGen(t: ref T)
{
	if(menumod == nil) {
		t.skip("Menu module not loaded");
		return;
	}

	gen := ref genfunc;
	p := menumod->newgen(gen);
	t.assert(p != nil, "newgen() returns non-nil Popup");
	t.assert(p.items == nil, "items nil before generator runs");
	t.assert(p.gen != nil, "gen is set");
	t.assert(p.subs == nil, "subs is nil");
	t.asserteq(p.lastsub, -1, "lastsub default");
	t.asserteq(p.lasthit, 0, "lasthit default");
}

# Counter for generator invocation tracking
gencalls := 0;

genfunc(m: ref Menu->Popup)
{
	gencalls++;
	m.items = array[] of {"Generated-A", "Generated-B"};
}

# Verify that the generator function populates items when called.
testGeneratorPopulates(t: ref T)
{
	if(menumod == nil) {
		t.skip("Menu module not loaded");
		return;
	}

	gencalls = 0;
	gen := ref genfunc;
	p := menumod->newgen(gen);

	# Simulate what show() does: call the generator
	(*p.gen)(p);

	t.asserteq(gencalls, 1, "generator called once");
	t.assert(p.items != nil, "items populated by generator");
	t.asserteq(len p.items, 2, "generator produced 2 items");
	t.assertseq(p.items[0], "Generated-A", "generator item 0");
	t.assertseq(p.items[1], "Generated-B", "generator item 1");
}

# Verify that a generator can wire up submenus.
testGeneratorWithSubs(t: ref T)
{
	if(menumod == nil) {
		t.skip("Menu module not loaded");
		return;
	}

	gen := ref subgenfunc;
	p := menumod->newgen(gen);

	# Simulate what show() does
	(*p.gen)(p);

	t.asserteq(len p.items, 3, "parent has 3 items");
	t.assert(p.subs != nil, "subs array created");
	t.asserteq(len p.subs, 3, "subs length matches items");
	t.assert(p.subs[0] == nil, "first item has no submenu");
	t.assert(p.subs[1] != nil, "second item has submenu");
	t.assert(p.subs[2] == nil, "third item has no submenu");

	sub := p.subs[1];
	t.asserteq(len sub.items, 2, "submenu has 2 items");
	t.assertseq(sub.items[0], "Sub-X", "submenu item 0");
	t.assertseq(sub.items[1], "Sub-Y", "submenu item 1");
}

subgenfunc(m: ref Menu->Popup)
{
	m.items = array[] of {"Parent-1", "Parent-2 >", "Parent-3"};
	m.subs = array[3] of ref Menu->Popup;
	m.subs[1] = menumod->new(array[] of {"Sub-X", "Sub-Y"});
}

# Verify that new() creates independent copies of the items array
# (modifying one Popup's items doesn't affect another).
testItemsIndependence(t: ref T)
{
	if(menumod == nil) {
		t.skip("Menu module not loaded");
		return;
	}

	items := array[] of {"A", "B"};
	p1 := menumod->new(items);
	p2 := menumod->new(items);

	# Modify original array
	items[0] = "Z";

	t.assertseq(p1.items[0], "A", "p1 items independent of source");
	t.assertseq(p2.items[0], "A", "p2 items independent of source");

	# Modify p1's items
	p1.items[0] = "X";
	t.assertseq(p2.items[0], "A", "p2 items independent of p1");
}

# Verify that the Popup adt has all expected fields accessible.
# This catches binary incompatibility if compiled against wrong menu.m.
testPopupFieldAccess(t: ref T)
{
	if(menumod == nil) {
		t.skip("Menu module not loaded");
		return;
	}

	items := array[] of {"Test"};
	p := menumod->new(items);

	# Verify all fields are accessible without crashing
	_ := p.items;
	_ = nil;
	lh := p.lasthit;
	t.asserteq(lh, 0, "lasthit accessible");

	g := p.gen;
	t.assert(g == nil, "gen accessible and nil");

	s := p.subs;
	t.assert(s == nil, "subs accessible and nil");

	ls := p.lastsub;
	t.asserteq(ls, -1, "lastsub accessible and -1");
}

# Verify multiple Popups can coexist independently.
testMultiplePopups(t: ref T)
{
	if(menumod == nil) {
		t.skip("Menu module not loaded");
		return;
	}

	p1 := menumod->new(array[] of {"Copy", "Paste"});
	p2 := menumod->new(array[] of {"Remove"});
	p3 := menumod->new(array[] of {"Read-only", "Read-write", "Unbind"});

	t.asserteq(len p1.items, 2, "p1 has 2 items");
	t.asserteq(len p2.items, 1, "p2 has 1 item");
	t.asserteq(len p3.items, 3, "p3 has 3 items");

	# Verify they are independent refs
	p1.lasthit = 1;
	t.asserteq(p2.lasthit, 0, "p2 lasthit unaffected by p1 change");
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

	# Load Menu module — this is the critical step.
	# If this test was compiled against a stale menu.m, this load
	# will fail with a type mismatch and menumod will be nil.
	menumod = load Menu Menu->PATH;
	if(menumod == nil)
		sys->fprint(sys->fildes(2), "WARNING: cannot load Menu module: %r\n");

	# Run tests
	run("ModuleLoad", testModuleLoad);
	run("NewPopup", testNewPopup);
	run("NewSingleItem", testNewSingleItem);
	run("NewEmptyItems", testNewEmptyItems);
	run("NewGen", testNewGen);
	run("GeneratorPopulates", testGeneratorPopulates);
	run("GeneratorWithSubs", testGeneratorWithSubs);
	run("ItemsIndependence", testItemsIndependence);
	run("PopupFieldAccess", testPopupFieldAccess);
	run("MultiplePopups", testMultiplePopups);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
