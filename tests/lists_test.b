implement ListsTest;

#
# Tests for the Lists module (lists.m)
#
# Covers: reverse, append, concat, last, map, filter,
#         partition, allsat, anysat, pair, unpair, combine
#
# Note: Lists module operates on reference types and strings only.
# Tests use list of string since int is not a reference type.
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

# Helper: string list length
slen(l: list of string): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}

# Helper: nth element of string list
snth(l: list of string, n: int): string
{
	for(i := 0; i < n; i++)
		l = tl l;
	return hd l;
}

# Helper functions for map/filter
toupper(x: string): string
{
	# Simple uppercase for single char strings
	if(len x == 1 && x[0] >= 'a' && x[0] <= 'z')
		return sys->sprint("%c", x[0] - 32);
	return x;
}

startswitha(x: string): int { return len x > 0 && x[0] == 'a'; }
notempty(x: string): int { return len x > 0; }
islong(x: string): int { return len x > 3; }

# ── reverse tests ────────────────────────────────────────────────────────────

testReverse(t: ref T)
{
	l := "c" :: "b" :: "a" :: nil;
	r := lists->reverse(l);
	t.asserteq(slen(r), 3, "reverse length");
	t.assertseq(snth(r, 0), "a", "reverse first");
	t.assertseq(snth(r, 1), "b", "reverse second");
	t.assertseq(snth(r, 2), "c", "reverse third");
}

testReverseEmpty(t: ref T)
{
	l: list of string;
	r := lists->reverse(l);
	t.asserteq(slen(r), 0, "reverse empty");
}

testReverseSingle(t: ref T)
{
	l := "hello" :: nil;
	r := lists->reverse(l);
	t.asserteq(slen(r), 1, "reverse single length");
	t.assertseq(hd r, "hello", "reverse single value");
}

# ── append tests ─────────────────────────────────────────────────────────────

testAppend(t: ref T)
{
	l := "b" :: "a" :: nil;
	r := lists->append(l, "c");
	t.asserteq(slen(r), 3, "append length");
	t.assertseq(snth(r, 2), "c", "append last element");
}

testAppendEmpty(t: ref T)
{
	l: list of string;
	r := lists->append(l, "x");
	t.asserteq(slen(r), 1, "append to empty length");
	t.assertseq(hd r, "x", "append to empty value");
}

# ── concat tests ─────────────────────────────────────────────────────────────

testConcat(t: ref T)
{
	l1 := "b" :: "a" :: nil;
	l2 := "d" :: "c" :: nil;
	r := lists->concat(l1, l2);
	t.asserteq(slen(r), 4, "concat length");
	t.assertseq(snth(r, 0), "a", "concat first");
	t.assertseq(snth(r, 1), "b", "concat second");
	t.assertseq(snth(r, 2), "c", "concat third");
	t.assertseq(snth(r, 3), "d", "concat fourth");
}

testConcatEmpty(t: ref T)
{
	l1 := "b" :: "a" :: nil;
	l2: list of string;
	r := lists->concat(l1, l2);
	t.asserteq(slen(r), 2, "concat with empty");
}

# ── last tests ───────────────────────────────────────────────────────────────

testLast(t: ref T)
{
	l := "c" :: "b" :: "a" :: nil;
	t.assertseq(lists->last(l), "c", "last of 3-element list");

	l2 := "only" :: nil;
	t.assertseq(lists->last(l2), "only", "last of single element");
}

# ── map tests ────────────────────────────────────────────────────────────────

testMap(t: ref T)
{
	l := "c" :: "b" :: "a" :: nil;
	r := lists->map(toupper, l);
	t.asserteq(slen(r), 3, "map length");
	t.assertseq(snth(r, 0), "A", "map first uppercased");
	t.assertseq(snth(r, 1), "B", "map second uppercased");
	t.assertseq(snth(r, 2), "C", "map third uppercased");
}

testMapEmpty(t: ref T)
{
	l: list of string;
	r := lists->map(toupper, l);
	t.asserteq(slen(r), 0, "map empty");
}

# ── filter tests ─────────────────────────────────────────────────────────────

testFilter(t: ref T)
{
	l := "banana" :: "avocado" :: "cherry" :: "apple" :: "date" :: nil;
	r := lists->filter(startswitha, l);
	t.asserteq(slen(r), 2, "filter starts-with-a count");
	t.assertseq(snth(r, 0), "apple", "filter first match");
	t.assertseq(snth(r, 1), "avocado", "filter second match");
}

testFilterNone(t: ref T)
{
	l := "x" :: "y" :: "z" :: nil;
	r := lists->filter(startswitha, l);
	t.asserteq(slen(r), 0, "filter none match");
}

testFilterAll(t: ref T)
{
	l := "abc" :: "ab" :: nil;
	r := lists->filter(startswitha, l);
	t.asserteq(slen(r), 2, "filter all match");
}

# ── partition tests ──────────────────────────────────────────────────────────

testPartition(t: ref T)
{
	l := "banana" :: "avocado" :: "cherry" :: "apple" :: "date" :: nil;
	(yes, no) := lists->partition(startswitha, l);
	t.asserteq(slen(yes), 2, "partition yes count");
	t.asserteq(slen(no), 3, "partition no count");
}

# ── allsat / anysat tests ────────────────────────────────────────────────────

testAllsat(t: ref T)
{
	l := "hello" :: "world" :: nil;
	t.assert(lists->allsat(notempty, l) != 0, "allsat all notempty");

	l2 := "" :: "hello" :: nil;
	t.assert(lists->allsat(notempty, l2) == 0, "allsat not all notempty");

	l3: list of string;
	t.assert(lists->allsat(notempty, l3) != 0, "allsat empty list");
}

testAnysat(t: ref T)
{
	l := "" :: "hello" :: "" :: nil;
	t.assert(lists->anysat(notempty, l) != 0, "anysat has notempty");

	l2 := "" :: "" :: nil;
	t.assert(lists->anysat(notempty, l2) == 0, "anysat no notempty");

	l3: list of string;
	t.assert(lists->anysat(notempty, l3) == 0, "anysat empty list");
}

# ── pair / unpair tests ──────────────────────────────────────────────────────

testPair(t: ref T)
{
	l1 := "b" :: "a" :: nil;
	l2 := "y" :: "x" :: nil;
	pairs := lists->pair(l1, l2);
	count := 0;
	for(p := pairs; p != nil; p = tl p) {
		(s1, s2) := hd p;
		if(count == 0) {
			t.assertseq(s1, "a", "pair first left");
			t.assertseq(s2, "x", "pair first right");
		} else {
			t.assertseq(s1, "b", "pair second left");
			t.assertseq(s2, "y", "pair second right");
		}
		count++;
	}
	t.asserteq(count, 2, "pair count");
}

testUnpair(t: ref T)
{
	pairs := ("b", "y") :: ("a", "x") :: nil;
	(lefts, rights) := lists->unpair(pairs);
	t.asserteq(slen(lefts), 2, "unpair lefts count");
	t.asserteq(slen(rights), 2, "unpair rights count");
}

# ── combine tests ────────────────────────────────────────────────────────────

testCombine(t: ref T)
{
	l1 := "b" :: "a" :: nil;
	l2 := "d" :: "c" :: nil;
	r := lists->combine(l1, l2);
	t.asserteq(slen(r), 4, "combine length");
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
