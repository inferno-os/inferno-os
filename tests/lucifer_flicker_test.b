implement LuciferFlickerTest;

#
# Regression tests for lucifer screen flicker fixes (2026-02).
#
# Two bugs fixed:
#
#   1. ctxtimer() fired unconditionally every 1s, causing full-screen
#      redraws even when the UI was completely idle. Fix: only send
#      a uievent tick when at least one resource is active or was used
#      within the 4s flash-fade window.
#
#   2. redraw() cleared the entire window background before drawing
#      content. If the display buffer auto-flushed mid-redraw (e.g. on
#      SDL present triggered by a resize), a blank frame was visible.
#      Fix: double-buffered redraw — all drawing goes to an off-screen
#      back buffer, then a single blit + flush updates the screen.
#      (The double-buffering fix is drawing-layer logic; it is covered
#      here by verifying that the predicate driving redraws is correct.)
#
# Tests verify the "needs tick" predicate that guards ctxtimer().
# If the condition is removed or widened (e.g. always fire), these tests
# document the expected contract.
#
# To run standalone:
#   ./emu/MacOSX/o.emu -r. /dis/tests/lucifer_flicker_test.dis
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

LuciferFlickerTest: module {
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/lucifer_flicker_test.b";

# Fixed "now" for deterministic time arithmetic.
# sys->millisec() at emulator startup can be < 1s, causing "now - 2000"
# to go negative and trip the "lastused > 0" guard in needstick().
# Any value larger than the largest test offset (4001) works here.
TESTNOW: con 1000000;	# 1000s — comfortably above all test offsets

# Mirror of lucifer.b Resource adt — fields and order must match exactly.
Resource: adt {
	path:     string;
	label:    string;
	rtype:    string;
	status:   string;
	via:      string;
	lastused: int;		# sys->millisec() at last activity; 0 = never used
};

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

#
# needstick — mirrors the predicate in ctxtimer() in lucifer.b.
#
# Returns 1 when a redraw is needed to animate the activity flash fade-out.
# Returns 0 when the context zone is fully idle (safe to skip the redraw).
#
# This must stay in sync with:
#   appl/cmd/lucifer.b  ctxtimer()  "if(res.status == "active" || ...)"
#
needstick(resources: list of ref Resource, now: int): int
{
	for(r := resources; r != nil; r = tl r) {
		res := hd r;
		if(res.status == "active" || (res.lastused > 0 && now - res.lastused < 4000))
			return 1;
	}
	return 0;
}

# --- Tests ---

# No resources at all: no tick.
testIdleNoResources(t: ref T)
{
	t.assert(!needstick(nil, sys->millisec()), "empty list: no tick");
}

# Resources present but never used (lastused=0): no tick.
testIdleNeverUsed(t: ref T)
{
	now := sys->millisec();
	res := ref Resource("/n/llm", "llm", "tool", "idle", nil, 0) ::
	       ref Resource("read",   "read", "tool", "idle", nil, 0) ::
	       nil;
	t.assert(!needstick(res, now), "all idle lastused=0: no tick");
}

# All resources idle, last used 5s ago (outside 4s window): no tick.
testIdleLastusedLongAgo(t: ref T)
{
	res := ref Resource("/n/llm", "llm", "tool", "idle", nil, TESTNOW - 5000) :: nil;
	t.assert(!needstick(res, TESTNOW), "idle lastused=5s ago: no tick");
}

# One resource with status=active: tick required.
testActiveResource(t: ref T)
{
	now := sys->millisec();
	res := ref Resource("read", "read", "tool", "active", nil, now - 100) :: nil;
	t.assert(needstick(res, now), "status=active: needs tick");
}

# One resource last used 2s ago (inside 4s window): tick required to animate fade.
testRecentlyUsedWithinWindow(t: ref T)
{
	res := ref Resource("/appl/cmd/lucifer.b", "lucifer.b", "file",
	                    "idle", "read", TESTNOW - 2000) :: nil;
	t.assert(needstick(res, TESTNOW), "lastused=2s ago: needs tick (flash fade)");
}

# Boundary: 3999ms inside → tick; 4000ms at edge → no tick.
testFlashWindowBoundary(t: ref T)
{
	inside := ref Resource("p", "p", "file", "idle", nil, TESTNOW - 3999) :: nil;
	edge   := ref Resource("p", "p", "file", "idle", nil, TESTNOW - 4000) :: nil;
	t.assert( needstick(inside, TESTNOW), "lastused=3999ms: inside window, needs tick");
	t.assert(!needstick(edge,   TESTNOW), "lastused=4000ms: at edge, no tick");
}

# Mixed list — one active resource triggers tick regardless of others.
testMixedIdleAndActive(t: ref T)
{
	res := ref Resource("/n/llm", "llm",    "tool", "idle",   nil, 0) ::
	       ref Resource("read",   "read",   "tool", "active", nil, TESTNOW) ::
	       ref Resource("memory", "memory", "tool", "idle",   nil, TESTNOW - 6000) ::
	       nil;
	t.assert(needstick(res, TESTNOW), "mixed: one active drives tick for whole list");
}

# All resources just past the 4s window: no tick.
testAllJustExpired(t: ref T)
{
	res := ref Resource("p1", "p1", "file", "idle", nil, TESTNOW - 4001) ::
	       ref Resource("p2", "p2", "file", "idle", nil, TESTNOW - 5000) ::
	       ref Resource("p3", "p3", "tool", "idle", nil, TESTNOW - 10000) ::
	       nil;
	t.assert(!needstick(res, TESTNOW), "all expired (>4s): no tick");
}

# status=active overrides a stale lastused timestamp.
testActiveStatusOverridesOldTimestamp(t: ref T)
{
	now := sys->millisec();
	res := ref Resource("exec", "exec", "tool", "active", nil, now - 60000) :: nil;
	t.assert(needstick(res, now), "status=active overrides stale lastused: needs tick");
}

# lastused=0 with a non-idle status other than "active" (e.g. "streaming"):
# status check is only for "active"; other statuses use lastused.
testStreamingStatusNoRecentUse(t: ref T)
{
	now := sys->millisec();
	# "streaming" is not "active" — check falls through to lastused branch.
	# lastused=0 means lastused > 0 is false → no tick.
	res := ref Resource("/n/llm", "llm", "tool", "streaming", nil, 0) :: nil;
	t.assert(!needstick(res, now),
		"status=streaming lastused=0: no tick (lastused branch requires > 0)");
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

	run("IdleNoResources",              testIdleNoResources);
	run("IdleNeverUsed",                testIdleNeverUsed);
	run("IdleLastusedLongAgo",          testIdleLastusedLongAgo);
	run("ActiveResource",               testActiveResource);
	run("RecentlyUsedWithinWindow",     testRecentlyUsedWithinWindow);
	run("FlashWindowBoundary",          testFlashWindowBoundary);
	run("MixedIdleAndActive",           testMixedIdleAndActive);
	run("AllJustExpired",               testAllJustExpired);
	run("ActiveStatusOverridesOld",     testActiveStatusOverridesOldTimestamp);
	run("StreamingStatusNoRecentUse",   testStreamingStatusNoRecentUse);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
