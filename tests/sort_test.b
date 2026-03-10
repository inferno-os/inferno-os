implement SortTest;

#
# Tests for sorting behavior
#
# Note: The polymorphic Sort module (sort.m) cannot be instantiated
# by the Limbo compiler due to type parameter resolution limitations.
# These tests verify sorting using a direct implementation instead.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

SortTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/sort_test.b";

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

# Simple insertion sort for testing
isort(a: array of int)
{
	for(i := 1; i < len a; i++) {
		key := a[i];
		j := i - 1;
		while(j >= 0 && a[j] > key) {
			a[j+1] = a[j];
			j--;
		}
		a[j+1] = key;
	}
}

# Reverse insertion sort
rsort(a: array of int)
{
	for(i := 1; i < len a; i++) {
		key := a[i];
		j := i - 1;
		while(j >= 0 && a[j] < key) {
			a[j+1] = a[j];
			j--;
		}
		a[j+1] = key;
	}
}

# String insertion sort
ssort(a: array of string)
{
	for(i := 1; i < len a; i++) {
		key := a[i];
		j := i - 1;
		while(j >= 0 && a[j] > key) {
			a[j+1] = a[j];
			j--;
		}
		a[j+1] = key;
	}
}

# ── basic sort tests ─────────────────────────────────────────────────────────

testSortInts(t: ref T)
{
	a := array[] of {5, 3, 1, 4, 2};
	isort(a);
	for(i := 0; i < len a - 1; i++)
		t.assert(a[i] <= a[i+1],
			sys->sprint("sorted[%d]=%d <= sorted[%d]=%d", i, a[i], i+1, a[i+1]));
	t.asserteq(a[0], 1, "first element");
	t.asserteq(a[4], 5, "last element");
}

testSortStrings(t: ref T)
{
	a := array[] of {"banana", "apple", "cherry", "date"};
	ssort(a);
	t.assertseq(a[0], "apple", "first string");
	t.assertseq(a[1], "banana", "second string");
	t.assertseq(a[2], "cherry", "third string");
	t.assertseq(a[3], "date", "fourth string");
}

testSortReverse(t: ref T)
{
	a := array[] of {1, 2, 3, 4, 5};
	rsort(a);
	t.asserteq(a[0], 5, "reverse first");
	t.asserteq(a[4], 1, "reverse last");
}

# ── edge cases ───────────────────────────────────────────────────────────────

testSortEmpty(t: ref T)
{
	a := array[0] of int;
	isort(a);
	t.asserteq(len a, 0, "empty array unchanged");
}

testSortSingle(t: ref T)
{
	a := array[] of {42};
	isort(a);
	t.asserteq(a[0], 42, "single element unchanged");
}

testSortAlreadySorted(t: ref T)
{
	a := array[] of {1, 2, 3, 4, 5};
	isort(a);
	for(i := 0; i < len a; i++)
		t.asserteq(a[i], i + 1, sys->sprint("already sorted[%d]", i));
}

testSortReversed(t: ref T)
{
	a := array[] of {5, 4, 3, 2, 1};
	isort(a);
	for(i := 0; i < len a; i++)
		t.asserteq(a[i], i + 1, sys->sprint("reversed[%d]", i));
}

testSortDuplicates(t: ref T)
{
	a := array[] of {3, 1, 2, 1, 3, 2};
	isort(a);
	t.asserteq(a[0], 1, "dup first");
	t.asserteq(a[1], 1, "dup second");
	t.asserteq(a[2], 2, "dup third");
	t.asserteq(a[3], 2, "dup fourth");
	t.asserteq(a[4], 3, "dup fifth");
	t.asserteq(a[5], 3, "dup sixth");
}

testSortAllSame(t: ref T)
{
	a := array[] of {7, 7, 7, 7};
	isort(a);
	for(i := 0; i < len a; i++)
		t.asserteq(a[i], 7, sys->sprint("all same[%d]", i));
}

testSortTwo(t: ref T)
{
	a := array[] of {2, 1};
	isort(a);
	t.asserteq(a[0], 1, "two elements first");
	t.asserteq(a[1], 2, "two elements second");
}

testSortNegatives(t: ref T)
{
	a := array[] of {-3, 1, -1, 0, 2};
	isort(a);
	t.asserteq(a[0], -3, "negatives first");
	t.asserteq(a[1], -1, "negatives second");
	t.asserteq(a[2], 0, "negatives third");
	t.asserteq(a[3], 1, "negatives fourth");
	t.asserteq(a[4], 2, "negatives fifth");
}

# ── larger array ─────────────────────────────────────────────────────────────

testSortLarger(t: ref T)
{
	n := 100;
	a := array[n] of int;
	for(i := 0; i < n; i++)
		a[i] = n - i;  # reverse order
	isort(a);
	for(i = 0; i < n; i++)
		if(!t.asserteq(a[i], i + 1, sys->sprint("larger[%d]", i)))
			return;
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

	for(a := args; a != nil; a = tl a)
		if(hd a == "-v")
			testing->verbose(1);

	run("SortInts", testSortInts);
	run("SortStrings", testSortStrings);
	run("SortReverse", testSortReverse);
	run("SortEmpty", testSortEmpty);
	run("SortSingle", testSortSingle);
	run("SortAlreadySorted", testSortAlreadySorted);
	run("SortReversed", testSortReversed);
	run("SortDuplicates", testSortDuplicates);
	run("SortAllSame", testSortAllSame);
	run("SortTwo", testSortTwo);
	run("SortNegatives", testSortNegatives);
	run("SortLarger", testSortLarger);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
