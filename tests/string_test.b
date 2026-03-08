implement StringTest;

#
# Tests for the String module (string.m)
#
# Covers: splitl, splitr, drop, take, in, splitstrl, splitstrr,
#         prefix, tolower, toupper, toint, tobig, toreal,
#         append, quoted, unquoted
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "testing.m";
	testing: Testing;
	T: import testing;

StringTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/string_test.b";

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

# ── splitl tests ──────────────────────────────────────────────────────────────

testSplitl(t: ref T)
{
	# Split before first char in class
	(l, r) := str->splitl("hello world", " ");
	t.assertseq(l, "hello", "splitl left of space");
	t.assertseq(r, " world", "splitl right of space");

	# No match: entire string in left
	(l, r) = str->splitl("hello", " ");
	t.assertseq(l, "hello", "splitl no match left");
	t.assertseq(r, "", "splitl no match right");

	# Match at start
	(l, r) = str->splitl(" hello", " ");
	t.assertseq(l, "", "splitl match at start left");
	t.assertseq(r, " hello", "splitl match at start right");

	# Character range
	(l, r) = str->splitl("abc123def", "0-9");
	t.assertseq(l, "abc", "splitl digits left");
	t.assertseq(r, "123def", "splitl digits right");

	# Empty string
	(l, r) = str->splitl("", "abc");
	t.assertseq(l, "", "splitl empty left");
	t.assertseq(r, "", "splitl empty right");
}

# ── splitr tests ──────────────────────────────────────────────────────────────

testSplitr(t: ref T)
{
	# Split after last char in class
	(l, r) := str->splitr("hello world foo", " ");
	t.assertseq(l, "hello world ", "splitr last space left");
	t.assertseq(r, "foo", "splitr last space right");

	# No match
	(l, r) = str->splitr("hello", " ");
	t.assertseq(l, "", "splitr no match left");
	t.assertseq(r, "hello", "splitr no match right");

	# All match
	(l, r) = str->splitr("   ", " ");
	t.assertseq(l, "   ", "splitr all spaces left");
	t.assertseq(r, "", "splitr all spaces right");
}

# ── drop and take tests ──────────────────────────────────────────────────────

testDrop(t: ref T)
{
	t.assertseq(str->drop("   hello", " "), "hello", "drop leading spaces");
	t.assertseq(str->drop("hello", " "), "hello", "drop no match");
	t.assertseq(str->drop("", " "), "", "drop empty");
	t.assertseq(str->drop("   ", " "), "", "drop all spaces");
	t.assertseq(str->drop("abc123", "a-z"), "123", "drop lowercase prefix");
}

testTake(t: ref T)
{
	t.assertseq(str->take("hello world", "a-z"), "hello", "take lowercase");
	t.assertseq(str->take("123abc", "0-9"), "123", "take digits");
	t.assertseq(str->take(" hello", "a-z"), "", "take no match at start");
	t.assertseq(str->take("", "a-z"), "", "take empty");
}

# ── in tests ──────────────────────────────────────────────────────────────────

testIn(t: ref T)
{
	t.assert(str->in('a', "a-z") != 0, "a in a-z");
	t.assert(str->in('z', "a-z") != 0, "z in a-z");
	t.assert(str->in('A', "a-z") == 0, "A not in a-z");
	t.assert(str->in('5', "0-9") != 0, "5 in 0-9");
	t.assert(str->in(' ', "^ \t\n") == 0, "space not in ^space-tab-nl");
	t.assert(str->in('a', "^ \t\n") != 0, "a in ^space-tab-nl");
}

# ── splitstrl / splitstrr tests ──────────────────────────────────────────────

testSplitstrl(t: ref T)
{
	# Split before first occurrence of substring
	(l, r) := str->splitstrl("hello::world::foo", "::");
	t.assertseq(l, "hello", "splitstrl left");
	t.assertseq(r, "::world::foo", "splitstrl right");

	# No match
	(l, r) = str->splitstrl("hello world", "::");
	t.assertseq(l, "hello world", "splitstrl no match left");
	t.assertseq(r, "", "splitstrl no match right");

	# Match at start
	(l, r) = str->splitstrl("::hello", "::");
	t.assertseq(l, "", "splitstrl match at start left");
	t.assertseq(r, "::hello", "splitstrl match at start right");
}

testSplitstrl_single(t: ref T)
{
	# Single char substring
	(l, r) := str->splitstrl("a/b/c", "/");
	t.assertseq(l, "a", "splitstrl single char left");
	t.assertseq(r, "/b/c", "splitstrl single char right");
}

testSplitstrl_empty(t: ref T)
{
	# Empty input
	(l, r) := str->splitstrl("", "abc");
	t.assertseq(l, "", "splitstrl empty input left");
	t.assertseq(r, "", "splitstrl empty input right");
}

testSplitstrl_emptysep(t: ref T)
{
	# Empty separator
	(l, r) := str->splitstrl("hello", "");
	t.assertseq(l, "", "splitstrl empty sep left");
	t.assertseq(r, "hello", "splitstrl empty sep right");
}

testSplitstrl_notfound(t: ref T)
{
	(l, r) := str->splitstrl("abcdef", "xyz");
	t.assertseq(l, "abcdef", "splitstrl not found left");
	t.assertseq(r, "", "splitstrl not found right");
}

testSplitstrl_overlap(t: ref T)
{
	# Overlapping patterns - should find first
	(l, r) := str->splitstrl("aab", "ab");
	t.assertseq(l, "a", "splitstrl overlap left");
	t.assertseq(r, "ab", "splitstrl overlap right");
}

testSplitstrl_matchend(t: ref T)
{
	(l, r) := str->splitstrl("hello world", "world");
	t.assertseq(l, "hello ", "splitstrl match at end left");
	t.assertseq(r, "world", "splitstrl match at end right");
}

testSplitstrl_repeated(t: ref T)
{
	(l, r) := str->splitstrl("xxxyyyxxx", "yyy");
	t.assertseq(l, "xxx", "splitstrl repeated left");
	t.assertseq(r, "yyyxxx", "splitstrl repeated right");
}

testSplitstrl_fullmatch(t: ref T)
{
	(l, r) := str->splitstrl("abc", "abc");
	t.assertseq(l, "", "splitstrl full match left");
	t.assertseq(r, "abc", "splitstrl full match right");
}

testSplitstrr(t: ref T)
{
	# Split after last occurrence of substring
	(l, r) := str->splitstrr("hello::world::foo", "::");
	t.assertseq(l, "hello::world::", "splitstrr left");
	t.assertseq(r, "foo", "splitstrr right");

	# No match
	(l, r) = str->splitstrr("hello world", "::");
	t.assertseq(l, "", "splitstrr no match left");
	t.assertseq(r, "hello world", "splitstrr no match right");
}

# ── prefix tests ─────────────────────────────────────────────────────────────

testPrefix(t: ref T)
{
	t.assert(str->prefix("hel", "hello") != 0, "hel is prefix of hello");
	t.assert(str->prefix("hello", "hello") != 0, "hello is prefix of hello");
	t.assert(str->prefix("", "hello") != 0, "empty is prefix of hello");
	t.assert(str->prefix("world", "hello") == 0, "world not prefix of hello");
	t.assert(str->prefix("helloo", "hello") == 0, "helloo not prefix of hello");
}

# ── case conversion tests ────────────────────────────────────────────────────

testTolower(t: ref T)
{
	t.assertseq(str->tolower("HELLO"), "hello", "tolower HELLO");
	t.assertseq(str->tolower("Hello World"), "hello world", "tolower mixed");
	t.assertseq(str->tolower("hello"), "hello", "tolower already lower");
	t.assertseq(str->tolower(""), "", "tolower empty");
	t.assertseq(str->tolower("123ABC"), "123abc", "tolower with digits");
}

testToupper(t: ref T)
{
	t.assertseq(str->toupper("hello"), "HELLO", "toupper hello");
	t.assertseq(str->toupper("Hello World"), "HELLO WORLD", "toupper mixed");
	t.assertseq(str->toupper("HELLO"), "HELLO", "toupper already upper");
	t.assertseq(str->toupper(""), "", "toupper empty");
	t.assertseq(str->toupper("123abc"), "123ABC", "toupper with digits");
}

# ── toint tests ──────────────────────────────────────────────────────────────

testToint(t: ref T)
{
	# Decimal
	(v, rem) := str->toint("42abc", 10);
	t.asserteq(v, 42, "toint decimal value");
	t.assertseq(rem, "abc", "toint decimal remainder");

	# Hex
	(v, rem) = str->toint("ff", 16);
	t.asserteq(v, 255, "toint hex ff");

	# Octal
	(v, rem) = str->toint("77", 8);
	t.asserteq(v, 63, "toint octal 77");

	# Base 0 auto-detect with 0x prefix
	(v, rem) = str->toint("0xff", 0);
	t.asserteq(v, 255, "toint auto hex");

	# Negative
	(v, rem) = str->toint("-10", 10);
	t.asserteq(v, -10, "toint negative");

	# Zero
	(v, rem) = str->toint("0", 10);
	t.asserteq(v, 0, "toint zero");

	# No digits
	(v, rem) = str->toint("abc", 10);
	t.asserteq(v, 0, "toint no digits");
	t.assertseq(rem, "abc", "toint no digits remainder");
}

# ── append / quoted / unquoted tests ─────────────────────────────────────────

testAppend(t: ref T)
{
	l: list of string;
	l = str->append("c", l);
	l = str->append("b", l);
	l = str->append("a", l);
	# append adds to the end of the list
	# Result should have all three elements
	count := 0;
	for(tmp := l; tmp != nil; tmp = tl tmp)
		count++;
	t.asserteq(count, 3, "append list length");
}

testQuotedUnquoted(t: ref T)
{
	# Simple case
	args: list of string;
	args = "world" :: args;
	args = "hello" :: args;
	q := str->quoted(args);
	t.assertnotnil(q, "quoted non-empty");
	t.log(sys->sprint("quoted: %s", q));

	# Round trip: quote then unquote
	result := str->unquoted(q);
	count := 0;
	for(tmp := result; tmp != nil; tmp = tl tmp)
		count++;
	t.asserteq(count, 2, "unquoted count");

	# Simple single word
	single: list of string;
	single = "hello" :: single;
	q = str->quoted(single);
	result = str->unquoted(q);
	t.assertseq(hd result, "hello", "round trip single word");
}

testQuotedSpecialChars(t: ref T)
{
	# Quoting a string with spaces
	args: list of string;
	args = "hello world" :: args;
	q := str->quoted(args);
	result := str->unquoted(q);
	t.assertseq(hd result, "hello world", "round trip with spaces");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}
	if(str == nil) {
		sys->fprint(sys->fildes(2), "cannot load string module: %r\n");
		raise "fail:cannot load string";
	}

	testing->init();

	for(a := args; a != nil; a = tl a)
		if(hd a == "-v")
			testing->verbose(1);

	run("Splitl", testSplitl);
	run("Splitr", testSplitr);
	run("Drop", testDrop);
	run("Take", testTake);
	run("In", testIn);
	run("Splitstrl", testSplitstrl);
	run("Splitstrl_single", testSplitstrl_single);
	run("Splitstrl_empty", testSplitstrl_empty);
	run("Splitstrl_emptysep", testSplitstrl_emptysep);
	run("Splitstrl_notfound", testSplitstrl_notfound);
	run("Splitstrl_overlap", testSplitstrl_overlap);
	run("Splitstrl_matchend", testSplitstrl_matchend);
	run("Splitstrl_repeated", testSplitstrl_repeated);
	run("Splitstrl_fullmatch", testSplitstrl_fullmatch);
	run("Splitstrr", testSplitstrr);
	run("Prefix", testPrefix);
	run("Tolower", testTolower);
	run("Toupper", testToupper);
	run("Toint", testToint);
	run("Append", testAppend);
	run("QuotedUnquoted", testQuotedUnquoted);
	run("QuotedSpecialChars", testQuotedSpecialChars);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
