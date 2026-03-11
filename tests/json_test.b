implement JsonTest;

#
# Tests for the JSON module (json.m)
#
# Covers: readjson, writejson, JValue constructors, type checks,
#         equality, copy, get/set, text representation
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "json.m";
	json: JSON;
	JValue: import json;

include "testing.m";
	testing: Testing;
	T: import testing;

JsonTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/json_test.b";

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

# Helper: parse JSON from string
parse(s: string): (ref JValue, string)
{
	b := bufio->sopen(s);
	return json->readjson(b);
}

# Helper: serialize JValue to string
serialize(v: ref JValue): string
{
	return v.text();
}

# ── Constructor and type check tests ─────────────────────────────────────────

testConstructors(t: ref T)
{
	# String
	s := json->jvstring("hello");
	t.assert(s.isstring(), "jvstring isstring");
	t.assert(!s.isint(), "jvstring not isint");
	t.assert(!s.isnull(), "jvstring not isnull");

	# Int
	i := json->jvint(42);
	t.assert(i.isint(), "jvint isint");
	t.assert(i.isnumber(), "jvint isnumber");
	t.assert(!i.isstring(), "jvint not isstring");

	# Big int
	bi := json->jvbig(big 9999999999);
	t.assert(bi.isint(), "jvbig isint");
	t.assert(bi.isnumber(), "jvbig isnumber");

	# Real
	r := json->jvreal(3.14);
	t.assert(r.isreal(), "jvreal isreal");
	t.assert(r.isnumber(), "jvreal isnumber");

	# Boolean
	tr := json->jvtrue();
	t.assert(tr.istrue(), "jvtrue istrue");
	t.assert(!tr.isfalse(), "jvtrue not isfalse");

	fa := json->jvfalse();
	t.assert(fa.isfalse(), "jvfalse isfalse");
	t.assert(!fa.istrue(), "jvfalse not istrue");

	# Null
	n := json->jvnull();
	t.assert(n.isnull(), "jvnull isnull");
	t.assert(!n.isstring(), "jvnull not isstring");
}

# ── Array tests ──────────────────────────────────────────────────────────────

testArray(t: ref T)
{
	elems := array[3] of ref JValue;
	elems[0] = json->jvint(1);
	elems[1] = json->jvint(2);
	elems[2] = json->jvint(3);
	a := json->jvarray(elems);
	t.assert(a.isarray(), "jvarray isarray");
	t.assert(!a.isobject(), "jvarray not isobject");
}

# ── Object tests ─────────────────────────────────────────────────────────────

testObject(t: ref T)
{
	members: list of (string, ref JValue);
	members = ("name", json->jvstring("Alice")) :: members;
	members = ("age", json->jvint(30)) :: members;
	obj := json->jvobject(members);
	t.assert(obj.isobject(), "jvobject isobject");

	# get
	name := obj.get("name");
	t.assert(name != nil, "get name not nil");
	t.assert(name.isstring(), "get name is string");

	age := obj.get("age");
	t.assert(age != nil, "get age not nil");
	t.assert(age.isint(), "get age is int");

	# get nonexistent
	missing := obj.get("missing");
	t.assert(missing == nil, "get missing is nil");
}

testObjectSet(t: ref T)
{
	obj := json->jvobject(nil);
	obj.set("key", json->jvstring("value"));
	v := obj.get("key");
	t.assert(v != nil, "set then get not nil");
	t.assert(v.isstring(), "set then get is string");
}

# ── Equality tests ───────────────────────────────────────────────────────────

testEquality(t: ref T)
{
	# Same values
	t.assert(json->jvint(42).eq(json->jvint(42)), "int equality");
	t.assert(json->jvstring("hi").eq(json->jvstring("hi")), "string equality");
	t.assert(json->jvtrue().eq(json->jvtrue()), "true equality");
	t.assert(json->jvfalse().eq(json->jvfalse()), "false equality");
	t.assert(json->jvnull().eq(json->jvnull()), "null equality");

	# Different values
	t.assert(!json->jvint(1).eq(json->jvint(2)), "int inequality");
	t.assert(!json->jvstring("a").eq(json->jvstring("b")), "string inequality");
	t.assert(!json->jvtrue().eq(json->jvfalse()), "bool inequality");

	# Different types
	t.assert(!json->jvint(1).eq(json->jvstring("1")), "type inequality");
	t.assert(!json->jvnull().eq(json->jvfalse()), "null != false");
}

# ── Copy tests ───────────────────────────────────────────────────────────────

testCopy(t: ref T)
{
	orig := json->jvstring("test");
	cp := orig.copy();
	t.assert(orig.eq(cp), "copy equals original");

	# Copy of object
	obj := json->jvobject(nil);
	obj.set("k", json->jvint(1));
	cp = obj.copy();
	t.assert(obj.eq(cp), "object copy equals original");
}

# ── Parse tests ──────────────────────────────────────────────────────────────

testParseString(t: ref T)
{
	(v, err) := parse("\"hello world\"");
	if(err != nil) {
		t.fatal("parse string error: " + err);
		return;
	}
	t.assert(v != nil, "parse string not nil");
	t.assert(v.isstring(), "parse string is string");
	t.assertseq(serialize(v), "\"hello world\"", "parse string text");
}

testParseInt(t: ref T)
{
	(v, err) := parse("42");
	if(err != nil) {
		t.fatal("parse int error: " + err);
		return;
	}
	t.assert(v != nil, "parse int not nil");
	t.assert(v.isint(), "parse int is int");
}

testParseNegative(t: ref T)
{
	(v, err) := parse("-17");
	if(err != nil) {
		t.fatal("parse negative error: " + err);
		return;
	}
	t.assert(v != nil, "parse negative not nil");
	t.assert(v.isint(), "parse negative is int");
}

testParseTrue(t: ref T)
{
	(v, err) := parse("true");
	if(err != nil) {
		t.fatal("parse true error: " + err);
		return;
	}
	t.assert(v.istrue(), "parse true");
}

testParseFalse(t: ref T)
{
	(v, err) := parse("false");
	if(err != nil) {
		t.fatal("parse false error: " + err);
		return;
	}
	t.assert(v.isfalse(), "parse false");
}

testParseNull(t: ref T)
{
	(v, err) := parse("null");
	if(err != nil) {
		t.fatal("parse null error: " + err);
		return;
	}
	t.assert(v.isnull(), "parse null");
}

testParseArray(t: ref T)
{
	(v, err) := parse("[1, 2, 3]");
	if(err != nil) {
		t.fatal("parse array error: " + err);
		return;
	}
	t.assert(v != nil, "parse array not nil");
	t.assert(v.isarray(), "parse array is array");
}

testParseObject(t: ref T)
{
	(v, err) := parse("{\"key\": \"value\", \"num\": 42}");
	if(err != nil) {
		t.fatal("parse object error: " + err);
		return;
	}
	t.assert(v != nil, "parse object not nil");
	t.assert(v.isobject(), "parse object is object");

	kv := v.get("key");
	t.assert(kv != nil, "parsed object has key");
	t.assert(kv.isstring(), "parsed key is string");

	nv := v.get("num");
	t.assert(nv != nil, "parsed object has num");
	t.assert(nv.isint(), "parsed num is int");
}

testParseNested(t: ref T)
{
	(v, err) := parse("{\"a\": [1, {\"b\": true}]}");
	if(err != nil) {
		t.fatal("parse nested error: " + err);
		return;
	}
	t.assert(v != nil, "parse nested not nil");
	t.assert(v.isobject(), "parse nested is object");
}

testParseEmpty(t: ref T)
{
	# Empty object
	(v, err) := parse("{}");
	if(err != nil) {
		t.fatal("parse empty object error: " + err);
		return;
	}
	t.assert(v.isobject(), "parse empty object");

	# Empty array
	(v, err) = parse("[]");
	if(err != nil) {
		t.fatal("parse empty array error: " + err);
		return;
	}
	t.assert(v.isarray(), "parse empty array");
}

testParseEscapes(t: ref T)
{
	(v, err) := parse("\"hello\\nworld\"");
	if(err != nil) {
		t.fatal("parse escape error: " + err);
		return;
	}
	t.assert(v.isstring(), "parse escape is string");
}

# ── Round trip tests ─────────────────────────────────────────────────────────

testRoundTrip(t: ref T)
{
	inputs := array[] of {
		"42",
		"\"hello\"",
		"true",
		"false",
		"null",
		"[1,2,3]",
	};
	for(i := 0; i < len inputs; i++) {
		(v, err) := parse(inputs[i]);
		if(err != nil) {
			t.error(sys->sprint("round trip parse %d error: %s", i, err));
			continue;
		}
		text := serialize(v);
		(v2, err2) := parse(text);
		if(err2 != nil) {
			t.error(sys->sprint("round trip reparse %d error: %s", i, err2));
			continue;
		}
		t.assert(v.eq(v2), sys->sprint("round trip %d", i));
	}
}

# ── Error handling tests ─────────────────────────────────────────────────────

testParseInvalid(t: ref T)
{
	# Invalid JSON
	(v, err) := parse("{invalid}");
	t.assert(v == nil || err != nil, "invalid JSON produces error");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	json = load JSON JSON->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}
	if(bufio == nil) {
		sys->fprint(sys->fildes(2), "cannot load bufio module: %r\n");
		raise "fail:cannot load bufio";
	}
	if(json == nil) {
		sys->fprint(sys->fildes(2), "cannot load json module: %r\n");
		raise "fail:cannot load json";
	}

	json->init(bufio);

	testing->init();

	for(a := args; a != nil; a = tl a)
		if(hd a == "-v")
			testing->verbose(1);

	run("Constructors", testConstructors);
	run("Array", testArray);
	run("Object", testObject);
	run("ObjectSet", testObjectSet);
	run("Equality", testEquality);
	run("Copy", testCopy);
	run("ParseString", testParseString);
	run("ParseInt", testParseInt);
	run("ParseNegative", testParseNegative);
	run("ParseTrue", testParseTrue);
	run("ParseFalse", testParseFalse);
	run("ParseNull", testParseNull);
	run("ParseArray", testParseArray);
	run("ParseObject", testParseObject);
	run("ParseNested", testParseNested);
	run("ParseEmpty", testParseEmpty);
	run("ParseEscapes", testParseEscapes);
	run("RoundTrip", testRoundTrip);
	run("ParseInvalid", testParseInvalid);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
