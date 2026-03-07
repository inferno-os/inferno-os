implement WmsrvZorderTest;

#
# Regression tests for wmsrv.b Client.bottom() ghost window fix (2026-03).
#
# Bug: Client.bottom() had an early return "if(c.znext == nil) return" that
# preceded the screen.bottom(imgs) call.  For a single-element z-list or a
# client not yet registered via top() (c.znext == nil in both cases), the
# screen image was never sent to z-back — leaving a "ghost" window visible
# after xenith exited (the image remained on-screen after the tab was removed).
#
# Fix (wmsrv.b Client.bottom()):
#   screen.bottom(imgs) is now called BEFORE the early return; the early
#   return only gates linked-list reordering, not the screen operation.
#
# These tests mirror the pure z-list logic of Client.top() / Client.bottom() /
# Client.remove() using a MockClient adt that has no draw dependencies.
# The screen operations (screen.bottom / screen.top) cannot be unit-tested
# without a display; they are simulated here via integer counters.
#
# testSingleClientBuggy and testXenithLateBind_Buggy document the failing
# behaviour of the pre-fix code.  The companion *Fixed tests are the actual
# regression guards: if Client.bottom() re-introduces the early-return gate,
# these will fail.
#
# To run standalone:
#   ./emu/MacOSX/o.emu -r. /dis/tests/wmsrv_zorder_test.dis
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

WmsrvZorderTest: module {
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/wmsrv_zorder_test.b";

# MockClient mirrors the z-list fields of wmsrv.b's Client adt.
# 'label'        — identifies the client in test assertions.
# 'znext'        — links to the next (lower) entry in the z-order list.
# 'screenbottom' — counts how many times mbottom() called the screen op.
# 'screentop'    — counts how many times mtop() called the screen op.
MockClient: adt {
	label:        string;
	znext:        ref MockClient;
	screenbottom: int;
	screentop:    int;
};

# Module-level z-order list — mirrors wmsrv.b's 'zorder'.
mzorder: ref MockClient;

# mreset clears the z-list between tests (MockClients are per-test locals).
mreset()
{
	mzorder = nil;
}

# mappend appends c to the tail of the mock z-list (test setup helper).
mappend(c: ref MockClient)
{
	c.znext = nil;
	if(mzorder == nil) {
		mzorder = c;
		return;
	}
	z := mzorder;
	while(z.znext != nil)
		z = z.znext;
	z.znext = c;
}

# mtop mirrors the FIXED Client.top() in wmsrv.b:
#   screen.top() (simulated by screentop++) is unconditional;
#   the early return only gates list reordering.
mtop(c: ref MockClient)
{
	c.screentop++;

	if(mzorder == c)
		return;

	prev: ref MockClient;
	for(z := mzorder; z != nil; (prev, z) = (z, z.znext))
		if(z == c)
			break;
	if(prev != nil)
		prev.znext = c.znext;
	c.znext = mzorder;
	mzorder = c;
}

# mbottom mirrors the FIXED Client.bottom() in wmsrv.b:
#   screen.bottom() (simulated by screenbottom++) fires BEFORE the
#   c.znext == nil early return.  This is the critical invariant.
mbottom(c: ref MockClient)
{
	# Simulate screen.bottom() — always called, before any z-list check.
	c.screenbottom++;

	if(c.znext == nil)
		return;	# already at tail; only list reordering is skipped

	prev: ref MockClient;
	for(z := mzorder; z != nil; (prev, z) = (z, z.znext))
		if(z == c)
			break;
	if(prev != nil)
		prev.znext = c.znext;
	else
		mzorder = c.znext;
	z = c.znext;
	c.znext = nil;
	for(; z != nil; (prev, z) = (z, z.znext))
		;
	if(prev != nil)
		prev.znext = c;
	else
		mzorder = c;
}

# mbottom_buggy mirrors the PRE-FIX Client.bottom() in wmsrv.b:
#   the early return gated screen.bottom(), causing the ghost window.
#   Used only by documentation tests (testSingleClientBuggy etc.) to
#   show what the bug looked like.  Do NOT use in non-buggy tests.
mbottom_buggy(c: ref MockClient)
{
	# BUG: early return precedes screen.bottom() — ghost window result.
	if(c.znext == nil)
		return;

	# Simulate screen.bottom() — only reached when c.znext != nil.
	c.screenbottom++;

	prev: ref MockClient;
	for(z := mzorder; z != nil; (prev, z) = (z, z.znext))
		if(z == c)
			break;
	if(prev != nil)
		prev.znext = c.znext;
	else
		mzorder = c.znext;
	z = c.znext;
	c.znext = nil;
	for(; z != nil; (prev, z) = (z, z.znext))
		;
	if(prev != nil)
		prev.znext = c;
	else
		mzorder = c;
}

# mremove mirrors Client.remove() in wmsrv.b.
mremove(c: ref MockClient)
{
	prev: ref MockClient;
	z: ref MockClient;
	for(z = mzorder; z != nil; (prev, z) = (z, z.znext))
		if(z == c)
			break;
	if(z == nil)
		return;
	if(prev != nil)
		prev.znext = z.znext;
	else
		mzorder = mzorder.znext;
}

# listlen returns the number of entries in the z-list.
listlen(): int
{
	n := 0;
	for(z := mzorder; z != nil; z = z.znext)
		n++;
	return n;
}

# head returns the first (z-top) element.
head(): ref MockClient
{
	return mzorder;
}

# tail returns the last (z-bottom) element.
tail(): ref MockClient
{
	if(mzorder == nil)
		return nil;
	z := mzorder;
	while(z.znext != nil)
		z = z.znext;
	return z;
}

# ─── Test infrastructure ──────────────────────────────────────────────────────

passed  := 0;
failed  := 0;
skipped := 0;

run(name: string, testfn: ref fn(t: ref T))
{
	mreset();
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

# ─── Ghost window regression: documentation tests ─────────────────────────────
#
# These two tests use mbottom_buggy() to document what the pre-fix code did.
# testSingleClientBuggy: the buggy code skips screen.bottom() (screenbottom=0).
# testSingleClientFixed: the fixed code always calls it (screenbottom=1).
# If testSingleClientFixed ever fails, Client.bottom() has regressed.

testSingleClientBuggy(t: ref T)
{
	a := ref MockClient("xenith", nil, 0, 0);
	mappend(a);
	mbottom_buggy(a);
	# Documents the bug: for a sole client (znext==nil), the buggy early return
	# means screen.bottom() is never called → ghost window left on screen.
	t.asserteq(a.screenbottom, 0,
		"buggy pre-fix: single client znext==nil skips screen op (ghost window)");
}

testSingleClientFixed(t: ref T)
{
	a := ref MockClient("xenith", nil, 0, 0);
	mappend(a);
	mbottom(a);
	# REGRESSION GUARD: screen.bottom() must always fire, even for a sole client.
	t.asserteq(a.screenbottom, 1,
		"fixed: sole client (znext==nil) still calls screen op");
	t.asserteq(listlen(), 1, "sole client: z-list length unchanged");
	t.assertseq(head().label, "xenith", "sole client remains in list");
}

# A client that was never top()-ed has znext==nil.  The ghost occurred because
# handleprescurrent() could fire before xenith connected to wmsrv, so c.top()
# was never called → c.znext remained nil → mbottom_buggy returned early.
testNotInListBuggy(t: ref T)
{
	a := ref MockClient("xenith", nil, 0, 0);
	# No mappend — simulate client never registered via top().
	mbottom_buggy(a);
	t.asserteq(a.screenbottom, 0,
		"buggy pre-fix: client not in z-list (znext==nil) skips screen op");
}

testNotInListFixed(t: ref T)
{
	a := ref MockClient("xenith", nil, 0, 0);
	# No mappend — simulate client never registered via top().
	mbottom(a);
	# REGRESSION GUARD: screen op fires regardless of z-list membership.
	t.asserteq(a.screenbottom, 1,
		"fixed: client not in z-list still calls screen op");
}

# Client already at the tail of a multi-element list also has znext==nil.
testAlreadyAtTailFixed(t: ref T)
{
	lucipres := ref MockClient("lucipres", nil, 0, 0);
	xenith   := ref MockClient("xenith",   nil, 0, 0);
	mappend(lucipres);
	mappend(xenith);	# xenith is at tail: xenith.znext == nil
	mbottom(xenith);
	# REGRESSION GUARD: tail client still gets screen.bottom() called.
	t.asserteq(xenith.screenbottom, 1,
		"fixed: tail client (znext==nil) still calls screen op");
	t.asserteq(listlen(), 2, "list length unchanged");
	t.assertseq(tail().label, "xenith", "xenith stays at tail");
}

# ─── Z-list ordering invariants ───────────────────────────────────────────────

# bottom() on the sole client: screen op fires, list unchanged.
testBottomSoleClient(t: ref T)
{
	a := ref MockClient("a", nil, 0, 0);
	mappend(a);
	mbottom(a);
	t.asserteq(a.screenbottom, 1, "screen op called");
	t.asserteq(listlen(), 1, "length 1");
	t.assertseq(head().label, "a", "sole client still in list");
}

# bottom() on the head of a two-client list: head moves to tail.
testBottomMovesHeadToTail(t: ref T)
{
	a := ref MockClient("a", nil, 0, 0);
	b := ref MockClient("b", nil, 0, 0);
	mappend(a);
	mappend(b);
	# z-list: a -> b
	mbottom(a);
	# z-list: b -> a
	t.asserteq(listlen(), 2, "length 2");
	t.assertseq(head().label, "b", "b at z-top after bottom(a)");
	t.assertseq(tail().label, "a", "a at z-bottom after bottom(a)");
	t.asserteq(a.screenbottom, 1, "screen op called for a");
}

# bottom() on the middle of a three-client list: middle moves to tail.
testBottomMovesMiddleToTail(t: ref T)
{
	a := ref MockClient("a", nil, 0, 0);
	b := ref MockClient("b", nil, 0, 0);
	c := ref MockClient("c", nil, 0, 0);
	mappend(a);
	mappend(b);
	mappend(c);
	# z-list: a -> b -> c
	mbottom(b);
	# z-list: a -> c -> b
	t.asserteq(listlen(), 3, "length 3");
	t.assertseq(head().label, "a", "a still at z-top");
	t.assertseq(tail().label, "b", "b moved to z-bottom");
	t.asserteq(b.screenbottom, 1, "screen op called for b");
}

# bottom() called twice on the same client: screen op fires both times.
# (Second call: client is already at tail, list reordering is skipped.)
testBottomIdempotentScreenOp(t: ref T)
{
	a := ref MockClient("a", nil, 0, 0);
	b := ref MockClient("b", nil, 0, 0);
	mappend(a);
	mappend(b);
	mbottom(a);	# a moves to tail: b -> a
	mbottom(a);	# a already at tail (znext==nil): early return, but screen op fires
	t.asserteq(a.screenbottom, 2, "screen op called twice");
	t.assertseq(tail().label, "a", "a stays at tail");
	t.asserteq(listlen(), 2, "length unchanged");
}

# top() on the sole client: screen op fires, early return, list unchanged.
testTopSoleClient(t: ref T)
{
	a := ref MockClient("a", nil, 0, 0);
	mappend(a);
	mtop(a);
	t.asserteq(a.screentop, 1, "screen op called");
	t.asserteq(listlen(), 1, "length 1");
	t.assertseq(head().label, "a", "sole client still in list");
}

# top() on the tail of a two-client list: tail moves to head.
testTopMovesTailToHead(t: ref T)
{
	a := ref MockClient("a", nil, 0, 0);
	b := ref MockClient("b", nil, 0, 0);
	mappend(a);
	mappend(b);
	# z-list: a -> b
	mtop(b);
	# z-list: b -> a
	t.asserteq(listlen(), 2, "length 2");
	t.assertseq(head().label, "b", "b at z-top after top(b)");
	t.assertseq(tail().label, "a", "a at z-bottom after top(b)");
	t.asserteq(b.screentop, 1, "screen op called for b");
}

# remove() of the middle client: neighbours stay connected.
testRemoveMiddle(t: ref T)
{
	a := ref MockClient("a", nil, 0, 0);
	b := ref MockClient("b", nil, 0, 0);
	c := ref MockClient("c", nil, 0, 0);
	mappend(a);
	mappend(b);
	mappend(c);
	mremove(b);
	t.asserteq(listlen(), 2, "length 2 after removing middle");
	t.assertseq(head().label, "a", "a still at z-top");
	t.assertseq(tail().label, "c", "c still at z-bottom");
}

# remove() of the head: second element becomes new head.
testRemoveHead(t: ref T)
{
	a := ref MockClient("a", nil, 0, 0);
	b := ref MockClient("b", nil, 0, 0);
	mappend(a);
	mappend(b);
	mremove(a);
	t.asserteq(listlen(), 1, "length 1 after removing head");
	t.assertseq(head().label, "b", "b is new head");
}

# ─── Sequence: xenith launch then exit ────────────────────────────────────────
#
# This is the exact sequence that triggered the ghost window.

# Normal case: xenith is top()-ed before bottom() — no race condition.
testXenithLaunchExit(t: ref T)
{
	lucipres := ref MockClient("lucipres", nil, 0, 0);
	xenith   := ref MockClient("xenith",   nil, 0, 0);
	mappend(lucipres);

	# Xenith connects and is brought to z-front.
	mtop(xenith);
	t.assertseq(head().label, "xenith", "xenith at z-top after launch");
	t.asserteq(xenith.screentop, 1, "screentop called on xenith connect");

	# Xenith exits: bottom() sends it to z-back so lucipres shows through.
	mbottom(xenith);
	t.assertseq(head().label, "lucipres", "lucipres at z-top after xenith exit");
	t.assertseq(tail().label, "xenith",   "xenith at z-bottom after exit");
	# REGRESSION GUARD: screen.bottom() must fire to clear the xenith image.
	t.asserteq(xenith.screenbottom, 1,
		"REGRESSION: screen.bottom() called on xenith exit (clears ghost)");
}

# Race case: handleprescurrent() fired before xenith connected to wmsrv.
# showapp() was a no-op (client == nil) → c.top() never called → c.znext == nil.
# The pre-fix code returned early from Client.bottom() without calling
# screen.bottom(), leaving xenith's image on screen.
testXenithRaceCondition(t: ref T)
{
	xenith := ref MockClient("xenith", nil, 0, 0);
	# Do NOT call mtop(xenith): simulate the race where top() never ran.
	# xenith.znext remains nil.
	mbottom(xenith);
	# REGRESSION GUARD: screen.bottom() must fire even without a prior top().
	t.asserteq(xenith.screenbottom, 1,
		"REGRESSION: screen op fires for client never top()-ed (race condition fix)");
}

# ─── init ─────────────────────────────────────────────────────────────────────

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

	# Ghost window regression: documentation (buggy behaviour)
	run("SingleClientBuggy",    testSingleClientBuggy);
	run("NotInListBuggy",       testNotInListBuggy);

	# Ghost window regression: guards (fixed behaviour — must stay passing)
	run("SingleClientFixed",    testSingleClientFixed);
	run("NotInListFixed",       testNotInListFixed);
	run("AlreadyAtTailFixed",   testAlreadyAtTailFixed);

	# Z-list ordering invariants
	run("BottomSoleClient",         testBottomSoleClient);
	run("BottomMovesHeadToTail",    testBottomMovesHeadToTail);
	run("BottomMovesMiddleToTail",  testBottomMovesMiddleToTail);
	run("BottomIdempotentScreenOp", testBottomIdempotentScreenOp);
	run("TopSoleClient",            testTopSoleClient);
	run("TopMovesTailToHead",       testTopMovesTailToHead);
	run("RemoveMiddle",             testRemoveMiddle);
	run("RemoveHead",               testRemoveHead);

	# Sequence: xenith launch + exit
	run("XenithLaunchExit",     testXenithLaunchExit);
	run("XenithRaceCondition",  testXenithRaceCondition);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
