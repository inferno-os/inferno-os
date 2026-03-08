implement RegexTest;

#
# Tests for the Regex module (regex.m)
#
# Covers: compile, execute, character classes, anchors,
#         alternation, quantifiers, grouping, edge cases
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "regex.m";
	regex: Regex;

include "testing.m";
	testing: Testing;
	T: import testing;

RegexTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/regex_test.b";

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

# Helper: check if pattern matches string
matches(pat, s: string): int
{
	(re, err) := regex->compile(pat, 0);
	if(err != nil)
		return -1;  # compile error
	result := regex->execute(re, s);
	if(result == nil)
		return 0;
	return 1;
}

# Helper: get match bounds
matchbounds(pat, s: string): (int, int)
{
	(re, nil) := regex->compile(pat, 0);
	result := regex->execute(re, s);
	if(result == nil)
		return (-1, -1);
	return result[0];
}

# ── Compile tests ────────────────────────────────────────────────────────────

testCompileValid(t: ref T)
{
	(re, err) := regex->compile("hello", 0);
	t.assert(re != nil, "compile valid pattern");
	t.assertnil(err, "compile valid no error");
}

testCompileEmpty(t: ref T)
{
	(re, err) := regex->compile("", 0);
	t.assert(re != nil, "compile empty pattern");
	t.assertnil(err, "compile empty no error");
}

testCompileInvalid(t: ref T)
{
	# Unmatched bracket
	(nil, err) := regex->compile("[abc", 0);
	t.assertnotnil(err, "compile invalid bracket error");
}

testCompileInvalidParen(t: ref T)
{
	(nil, err) := regex->compile("(abc", 0);
	t.assertnotnil(err, "compile invalid paren error");
}

# ── Literal matching ────────────────────────────────────────────────────────

testMatchLiteral(t: ref T)
{
	t.assert(matches("hello", "hello") == 1, "match exact");
	t.assert(matches("hello", "hello world") == 1, "match prefix");
	t.assert(matches("world", "hello world") == 1, "match suffix");
	t.assert(matches("lo wo", "hello world") == 1, "match middle");
	t.assert(matches("xyz", "hello") == 0, "no match");
}

# ── Dot (any char) ──────────────────────────────────────────────────────────

testMatchDot(t: ref T)
{
	t.assert(matches("h.llo", "hello") == 1, "dot matches e");
	t.assert(matches("h.llo", "hallo") == 1, "dot matches a");
	t.assert(matches(".", "x") == 1, "dot matches single char");
	t.assert(matches(".", "") == 0, "dot no match empty");
}

# ── Character classes ────────────────────────────────────────────────────────

testMatchCharClass(t: ref T)
{
	t.assert(matches("[abc]", "a") == 1, "class matches a");
	t.assert(matches("[abc]", "b") == 1, "class matches b");
	t.assert(matches("[abc]", "d") == 0, "class no match d");
}

testMatchCharRange(t: ref T)
{
	t.assert(matches("[a-z]", "m") == 1, "range matches m");
	t.assert(matches("[a-z]", "A") == 0, "range no match A");
	t.assert(matches("[0-9]", "5") == 1, "digit range matches 5");
	t.assert(matches("[0-9]", "a") == 0, "digit range no match a");
}

testMatchNegatedClass(t: ref T)
{
	t.assert(matches("[^abc]", "d") == 1, "negated class matches d");
	t.assert(matches("[^abc]", "a") == 0, "negated class no match a");
	t.assert(matches("[^0-9]", "x") == 1, "negated digit matches x");
}

# ── Anchors ──────────────────────────────────────────────────────────────────

testMatchAnchors(t: ref T)
{
	t.assert(matches("^hello", "hello world") == 1, "anchor start match");
	t.assert(matches("^world", "hello world") == 0, "anchor start no match");
	t.assert(matches("world$", "hello world") == 1, "anchor end match");
	t.assert(matches("hello$", "hello world") == 0, "anchor end no match");
	t.assert(matches("^hello$", "hello") == 1, "both anchors match");
	t.assert(matches("^hello$", "hello world") == 0, "both anchors no match");
}

# ── Quantifiers ──────────────────────────────────────────────────────────────

testMatchStar(t: ref T)
{
	t.assert(matches("ab*c", "ac") == 1, "star zero");
	t.assert(matches("ab*c", "abc") == 1, "star one");
	t.assert(matches("ab*c", "abbc") == 1, "star two");
	t.assert(matches("ab*c", "abbbc") == 1, "star three");
	t.assert(matches("a.*c", "axyzc") == 1, "dot star");
}

testMatchPlus(t: ref T)
{
	t.assert(matches("ab+c", "ac") == 0, "plus zero no match");
	t.assert(matches("ab+c", "abc") == 1, "plus one");
	t.assert(matches("ab+c", "abbc") == 1, "plus two");
}

testMatchQuestion(t: ref T)
{
	t.assert(matches("ab?c", "ac") == 1, "question zero");
	t.assert(matches("ab?c", "abc") == 1, "question one");
	t.assert(matches("ab?c", "abbc") == 0, "question two no match");
}

# ── Alternation ──────────────────────────────────────────────────────────────

testMatchAlternation(t: ref T)
{
	t.assert(matches("cat|dog", "cat") == 1, "alt matches cat");
	t.assert(matches("cat|dog", "dog") == 1, "alt matches dog");
	t.assert(matches("cat|dog", "bird") == 0, "alt no match bird");
}

# ── Grouping ─────────────────────────────────────────────────────────────────

testMatchGroups(t: ref T)
{
	t.assert(matches("(ab)+", "ababab") == 1, "group repeat");
	t.assert(matches("(ab)+", "cd") == 0, "group no match");
}

# ── Match positions ──────────────────────────────────────────────────────────

testMatchPositions(t: ref T)
{
	(start, end) := matchbounds("world", "hello world");
	t.asserteq(start, 6, "match start position");
	t.asserteq(end, 11, "match end position");
}

testMatchPositionStart(t: ref T)
{
	(start, end) := matchbounds("hello", "hello world");
	t.asserteq(start, 0, "match at start position");
	t.asserteq(end, 5, "match at start end");
}

# ── Edge cases ───────────────────────────────────────────────────────────────

testEmptyPattern(t: ref T)
{
	# Empty pattern should match anything
	t.assert(matches("", "hello") == 1, "empty pattern matches");
	t.assert(matches("", "") == 1, "empty pattern matches empty");
}

testEmptyString(t: ref T)
{
	t.assert(matches("a", "") == 0, "literal no match empty");
	t.assert(matches("a*", "") == 1, "star matches empty");
	t.assert(matches("^$", "") == 1, "anchors match empty");
}

testSpecialChars(t: ref T)
{
	# Backslash escapes
	t.assert(matches("a\\.b", "a.b") == 1, "escaped dot matches literal");
	t.assert(matches("a\\.b", "axb") == 0, "escaped dot no match");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	regex = load Regex Regex->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}
	if(regex == nil) {
		sys->fprint(sys->fildes(2), "cannot load regex module: %r\n");
		raise "fail:cannot load regex";
	}

	testing->init();

	for(a := args; a != nil; a = tl a)
		if(hd a == "-v")
			testing->verbose(1);

	run("CompileValid", testCompileValid);
	run("CompileEmpty", testCompileEmpty);
	run("CompileInvalid", testCompileInvalid);
	run("CompileInvalidParen", testCompileInvalidParen);
	run("MatchLiteral", testMatchLiteral);
	run("MatchDot", testMatchDot);
	run("MatchCharClass", testMatchCharClass);
	run("MatchCharRange", testMatchCharRange);
	run("MatchNegatedClass", testMatchNegatedClass);
	run("MatchAnchors", testMatchAnchors);
	run("MatchStar", testMatchStar);
	run("MatchPlus", testMatchPlus);
	run("MatchQuestion", testMatchQuestion);
	run("MatchAlternation", testMatchAlternation);
	run("MatchGroups", testMatchGroups);
	run("MatchPositions", testMatchPositions);
	run("MatchPositionStart", testMatchPositionStart);
	run("EmptyPattern", testEmptyPattern);
	run("EmptyString", testEmptyString);
	run("SpecialChars", testSpecialChars);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
