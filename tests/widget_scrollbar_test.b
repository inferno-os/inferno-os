implement WidgetScrollbarTest;

#
# Regression tests for Widget.Scrollbar tracking state machine.
#
# Bug fixed in 4002de25: Scrollbar.event() entering drag mode via
# Listbox.click() left activesb set permanently because the button-release
# event was filtered before reaching track().  These tests verify:
#   - event() on thumb sets activesb (isactive)
#   - track() with button released clears activesb
#   - isactive() is false for unrelated scrollbars
#   - page-up/down via event() does NOT enter tracking mode
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Font, Point, Rect, Pointer: import draw;

include "testing.m";
	testing: Testing;
	T: import testing;

include "widget.m";
	widgetmod: Widget;
	Scrollbar: import widgetmod;

WidgetScrollbarTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/widget_scrollbar_test.b";

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

# Create a vertical scrollbar with known dimensions and content.
# Rect (0,0)-(20,200), total=100, visible=20, origin=0.
# Thumb covers top 20% of the 200px track = 40px (y=0..40).
mksb(): ref Scrollbar
{
	sb := Scrollbar.new(Rect((0, 0), (20, 200)), 1);
	sb.total = 100;
	sb.visible = 20;
	sb.origin = 0;
	return sb;
}

# ── Tests ──────────────────────────────────────────────────────

# Scrollbar should not be active after creation.
testInitInactive(t: ref T)
{
	sb := mksb();
	t.assert(sb.isactive() == 0, "new scrollbar should not be active");
}

# B1 click on the thumb should enter tracking mode.
testEventThumbStartsTracking(t: ref T)
{
	sb := mksb();
	# Click in the middle of the thumb (y=20, within 0..40 thumb range)
	p := ref Pointer(1, Point(10, 20), 0);
	sb.event(p);
	t.assert(sb.isactive() != 0, "B1 on thumb should activate tracking");
}

# track() with B1 released should clear tracking mode.
testTrackReleaseClears(t: ref T)
{
	sb := mksb();
	# Start drag on thumb
	p := ref Pointer(1, Point(10, 20), 0);
	sb.event(p);
	t.assert(sb.isactive() != 0, "precondition: tracking active");

	# Release B1
	release := ref Pointer(0, Point(10, 30), 0);
	result := sb.track(release);
	t.asserteq(result, -1, "track with release should return -1");
	t.assert(sb.isactive() == 0, "tracking should be cleared after release");
}

# B1 click above thumb should page up, NOT enter tracking.
testEventPageUpNoTracking(t: ref T)
{
	sb := mksb();
	# Move origin so thumb is in the middle
	sb.origin = 50;
	# Click above thumb (y=10, which is above the thumb at ~100..140)
	p := ref Pointer(1, Point(10, 10), 0);
	result := sb.event(p);
	# Page-up returns new origin (should be < 50)
	t.assert(result >= 0, "page-up should return a valid origin");
	t.assert(sb.isactive() == 0, "page-up should NOT enter tracking mode");
}

# B1 click below thumb should page down, NOT enter tracking.
testEventPageDownNoTracking(t: ref T)
{
	sb := mksb();
	# origin=0, thumb at top (0..40), click below thumb at y=180
	p := ref Pointer(1, Point(10, 180), 0);
	result := sb.event(p);
	t.assert(result >= 0, "page-down should return a valid origin");
	t.assert(sb.isactive() == 0, "page-down should NOT enter tracking mode");
}

# isactive() should return false for a different scrollbar.
testIsactiveIsolation(t: ref T)
{
	sb1 := mksb();
	sb2 := mksb();
	# Start drag on sb1
	p := ref Pointer(1, Point(10, 20), 0);
	sb1.event(p);
	t.assert(sb1.isactive() != 0, "sb1 should be active");
	t.assert(sb2.isactive() == 0, "sb2 should NOT be active");

	# Clean up: release
	release := ref Pointer(0, Point(10, 20), 0);
	sb1.track(release);
}

# Regression: track() on wrong scrollbar should return -1 and
# NOT clear the active scrollbar's tracking state.
testTrackWrongScrollbar(t: ref T)
{
	sb1 := mksb();
	sb2 := mksb();
	# Start drag on sb1
	p := ref Pointer(1, Point(10, 20), 0);
	sb1.event(p);

	# Call track on sb2 — should be no-op
	result := sb2.track(ref Pointer(1, Point(10, 30), 0));
	t.asserteq(result, -1, "track on wrong sb should return -1");
	t.assert(sb1.isactive() != 0, "sb1 should still be active after sb2.track");

	# Clean up
	sb1.track(ref Pointer(0, Point(10, 20), 0));
}

# B2 click should enter tracking mode (absolute position jump).
testB2EntersTracking(t: ref T)
{
	sb := mksb();
	p := ref Pointer(2, Point(10, 100), 0);
	sb.event(p);
	t.assert(sb.isactive() != 0, "B2 should activate tracking");

	# Release B2
	release := ref Pointer(0, Point(10, 100), 0);
	sb.track(release);
	t.assert(sb.isactive() == 0, "tracking should clear after B2 release");
}

# Regression: the exact bug scenario — Listbox.click() calls event()
# with a synthetic B1 Pointer.  If it hits the thumb, activesb is set.
# Then a button-release must reach track() to clear it.
testListboxClickThumbRegression(t: ref T)
{
	sb := mksb();
	# Simulate Listbox.click calling event with synthetic B1 on thumb
	synth := ref Pointer(1, Point(10, 20), 0);
	sb.event(synth);
	t.assert(sb.isactive() != 0, "synthetic B1 on thumb should activate");

	# Simulate the NEXT real pointer event being a button-release.
	# Before the fix, handleptr() filtered this out before reaching track().
	# After the fix, track() sees it and clears activesb.
	release := ref Pointer(0, Point(10, 20), 0);
	sb.track(release);
	t.assert(sb.isactive() == 0,
		"release after synthetic-B1 thumb click must clear tracking");
}

# After clearing tracking, normal clicks should work.
testClickAfterTrackClear(t: ref T)
{
	sb := mksb();
	# Enter and exit tracking
	sb.event(ref Pointer(1, Point(10, 20), 0));
	sb.track(ref Pointer(0, Point(10, 20), 0));
	t.assert(sb.isactive() == 0, "precondition: not active");

	# Page-down click should work normally
	result := sb.event(ref Pointer(1, Point(10, 180), 0));
	t.assert(result >= 0, "page-down should work after clearing tracking");
	t.assert(sb.isactive() == 0, "page-down should not re-enter tracking");
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
		sys->fprint(sys->fildes(2), "cannot load widget module: %r\n");
		raise "fail:cannot load widget";
	}
	widgetmod->init(nil, nil);

	run("InitInactive", testInitInactive);
	run("EventThumbStartsTracking", testEventThumbStartsTracking);
	run("TrackReleaseClears", testTrackReleaseClears);
	run("EventPageUpNoTracking", testEventPageUpNoTracking);
	run("EventPageDownNoTracking", testEventPageDownNoTracking);
	run("IsactiveIsolation", testIsactiveIsolation);
	run("TrackWrongScrollbar", testTrackWrongScrollbar);
	run("B2EntersTracking", testB2EntersTracking);
	run("ListboxClickThumbRegression", testListboxClickThumbRegression);
	run("ClickAfterTrackClear", testClickAfterTrackClear);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
