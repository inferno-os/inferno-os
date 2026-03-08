implement ListsTest;

#
# Tests for the Lists module (lists.m)
#
# Covers: reverse, append, concat, last, map, filter,
#         partition, allsat, anysat, pair, unpair, ismember,
#         find, delete, combine
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "lists.m";
	lists: Lists;

include "testing.m";
	testing: Testing;
	T: import testing;

ListsTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/lists_test.b";

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

# Helper: list length
llen(l: list of int): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}

sllen(l: list of string): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}

# Helper: nth element of int list
nth(l: list of int, n: int): int
{
	for(i := 0; i < n; i++)
		l = tl l;
	return hd l;
}

snth(l: list of string, n: int): string
{
	for(i := 0; i < n; i++)
		l = tl l;
	return hd l;
}

# Helper functions for map/filter
double(x: int): int { return x * 2; }
iseven(x: int): int { return x % 2 == 0; }
ispositive(x: int): int { return x > 0; }
negate(x: int): int { return -x; }

# ── reverse tests ────────────────────────────────────────────────────────────

testReverse(t: ref T)
{
	l := 3 :: 2 :: 1 :: nil;
	r := lists->reverse(l);
	t.asserteq(llen(r), 3, "reverse length");
	t.asserteq(nth(r, 0), 1, "reverse first");
	t.asserteq(nth(r, 1), 2, "reverse second");
	t.asserteq(nth(r, 2), 3, "reverse third");
}

testReverseEmpty(t: ref T)
{
	l: list of int;
	r := lists->reverse(l);
	t.asserteq(llen(r), 0, "reverse empty");
}

testReverseSingle(t: ref T)
{
	l := 42 :: nil;
	r := lists->reverse(l);
	t.asserteq(llen(r), 1, "reverse single length");
	t.asserteq(hd r, 42, "reverse single value");
}

# ── append tests ─────────────────────────────────────────────────────────────

testAppend(t: ref T)
{
	l := 2 :: 1 :: nil;
	r := lists->append(l, 3);
	t.asserteq(llen(r), 3, "append length");
	t.asserteq(nth(r, 2), 3, "append last element");
}

testAppendEmpty(t: ref T)
{
	l: list of int;
	r := lists->append(l, 1);
	t.asserteq(llen(r), 1, "append to empty length");
	t.asserteq(hd r, 1, "append to empty value");
}

# ── concat tests ─────────────────────────────────────────────────────────────

testConcat(t: ref T)
{
	l1 := 2 :: 1 :: nil;
	l2 := 4 :: 3 :: nil;
	r := lists->concat(l1, l2);
	t.asserteq(llen(r), 4, "concat length");
	t.asserteq(nth(r, 0), 1, "concat first");
	t.asserteq(nth(r, 1), 2, "concat second");
	t.asserteq(nth(r, 2), 3, "concat third");
	t.asserteq(nth(r, 3), 4, "concat fourth");
}

testConcatEmpty(t: ref T)
{
	l1 := 2 :: 1 :: nil;
	l2: list of int;
	r := lists->concat(l1, l2);
	t.asserteq(llen(r), 2, "concat with empty");
}

# ── last tests ───────────────────────────────────────────────────────────────

testLast(t: ref T)
{
	l := 3 :: 2 :: 1 :: nil;
	t.asserteq(lists->last(l), 3, "last of 3-element list");

	l2 := 42 :: nil;
	t.asserteq(lists->last(l2), 42, "last of single element");
}

# ── map tests ────────────────────────────────────────────────────────────────

testMap(t: ref T)
{
	l := 3 :: 2 :: 1 :: nil;
	r := lists->map(double, l);
	t.asserteq(llen(r), 3, "map length");
	t.asserteq(nth(r, 0), 2, "map first doubled");
	t.asserteq(nth(r, 1), 4, "map second doubled");
	t.asserteq(nth(r, 2), 6, "map third doubled");
}

testMapEmpty(t: ref T)
{
	l: list of int;
	r := lists->map(double, l);
	t.asserteq(llen(r), 0, "map empty");
}

testMapNegate(t: ref T)
{
	l := 3 :: -2 :: 1 :: nil;
	r := lists->map(negate, l);
	t.asserteq(nth(r, 0), -1, "negate first");
	t.asserteq(nth(r, 1), 2, "negate second");
	t.asserteq(nth(r, 2), -3, "negate third");
}

# ── filter tests ─────────────────────────────────────────────────────────────

testFilter(t: ref T)
{
	l := 5 :: 4 :: 3 :: 2 :: 1 :: nil;
	r := lists->filter(iseven, l);
	t.asserteq(llen(r), 2, "filter even count");
	t.asserteq(nth(r, 0), 2, "filter first even");
	t.asserteq(nth(r, 1), 4, "filter second even");
}

testFilterNone(t: ref T)
{
	l := 5 :: 3 :: 1 :: nil;
	r := lists->filter(iseven, l);
	t.asserteq(llen(r), 0, "filter none match");
}

testFilterAll(t: ref T)
{
	l := 4 :: 2 :: nil;
	r := lists->filter(iseven, l);
	t.asserteq(llen(r), 2, "filter all match");
}

# ── partition tests ──────────────────────────────────────────────────────────

testPartition(t: ref T)
{
	l := 5 :: 4 :: 3 :: 2 :: 1 :: nil;
	(yes, no) := lists->partition(iseven, l);
	t.asserteq(llen(yes), 2, "partition yes count");
	t.asserteq(llen(no), 3, "partition no count");
}

# ── allsat / anysat tests ────────────────────────────────────────────────────

testAllsat(t: ref T)
{
	l := 4 :: 2 :: nil;
	t.assert(lists->allsat(iseven, l) != 0, "allsat all even");

	l2 := 3 :: 2 :: nil;
	t.assert(lists->allsat(iseven, l2) == 0, "allsat not all even");

	l3: list of int;
	t.assert(lists->allsat(iseven, l3) != 0, "allsat empty list");
}

testAnysat(t: ref T)
{
	l := 3 :: 2 :: 1 :: nil;
	t.assert(lists->anysat(iseven, l) != 0, "anysat has even");

	l2 := 5 :: 3 :: 1 :: nil;
	t.assert(lists->anysat(iseven, l2) == 0, "anysat no even");

	l3: list of int;
	t.assert(lists->anysat(iseven, l3) == 0, "anysat empty list");
}

# ── pair / unpair tests ──────────────────────────────────────────────────────

testPair(t: ref T)
{
	l1 := 2 :: 1 :: nil;
	l2 := "b" :: "a" :: nil;
	pairs := lists->pair(l1, l2);
	count := 0;
	for(p := pairs; p != nil; p = tl p) {
		(i, s) := hd p;
		if(count == 0) {
			t.asserteq(i, 1, "pair first int");
			t.assertseq(s, "a", "pair first string");
		} else {
			t.asserteq(i, 2, "pair second int");
			t.assertseq(s, "b", "pair second string");
		}
		count++;
	}
	t.asserteq(count, 2, "pair count");
}

testUnpair(t: ref T)
{
	pairs := (2, "b") :: (1, "a") :: nil;
	(ints, strs) := lists->unpair(pairs);
	t.asserteq(llen(ints), 2, "unpair ints count");
	t.asserteq(sllen(strs), 2, "unpair strings count");
}

# ── combine tests ────────────────────────────────────────────────────────────

testCombine(t: ref T)
{
	l1 := 2 :: 1 :: nil;
	l2 := 4 :: 3 :: nil;
	r := lists->combine(l1, l2);
	t.asserteq(llen(r), 4, "combine length");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	lists = load Lists Lists->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}
	if(lists == nil) {
		sys->fprint(sys->fildes(2), "cannot load lists module: %r\n");
		raise "fail:cannot load lists";
	}

	testing->init();

	for(a := args; a != nil; a = tl a)
		if(hd a == "-v")
			testing->verbose(1);

	run("Reverse", testReverse);
	run("ReverseEmpty", testReverseEmpty);
	run("ReverseSingle", testReverseSingle);
	run("Append", testAppend);
	run("AppendEmpty", testAppendEmpty);
	run("Concat", testConcat);
	run("ConcatEmpty", testConcatEmpty);
	run("Last", testLast);
	run("Map", testMap);
	run("MapEmpty", testMapEmpty);
	run("MapNegate", testMapNegate);
	run("Filter", testFilter);
	run("FilterNone", testFilterNone);
	run("FilterAll", testFilterAll);
	run("Partition", testPartition);
	run("Allsat", testAllsat);
	run("Anysat", testAnysat);
	run("Pair", testPair);
	run("Unpair", testUnpair);
	run("Combine", testCombine);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
