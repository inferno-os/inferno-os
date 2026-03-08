implement FactotumTest;

#
# Tests for the Factotum module (factotum.m)
#
# Covers: parseattrs, copyattrs, delattr, takeattrs,
#         findattr, findattrval, publicattrs, attrtext,
#         Attr construction, Authinfo.unpack
#
# Note: Tests that require a running factotum service (open, rpc,
# mount, proxy, getuserpasswd, challenge/response) are skipped
# if the service is not available.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";

include "factotum.m";
	factotum: Factotum;
	Attr: import factotum;
	Authinfo: import factotum;

include "testing.m";
	testing: Testing;
	T: import testing;

FactotumTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/factotum_test.b";

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

# Helper: count list length
attrlen(l: list of ref Attr): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}

# ── parseattrs tests ─────────────────────────────────────────────────────────

testParseAttrsSimple(t: ref T)
{
	attrs := factotum->parseattrs("proto=p9sk1 dom=example.com user=alice");
	t.assert(attrs != nil, "parseattrs non-nil");
	t.assert(attrlen(attrs) >= 3, sys->sprint("parseattrs count: %d", attrlen(attrs)));

	# Check individual values
	proto := factotum->findattrval(attrs, "proto");
	t.assertseq(proto, "p9sk1", "proto value");

	dom := factotum->findattrval(attrs, "dom");
	t.assertseq(dom, "example.com", "dom value");

	user := factotum->findattrval(attrs, "user");
	t.assertseq(user, "alice", "user value");
}

testParseAttrsEmpty(t: ref T)
{
	attrs := factotum->parseattrs("");
	t.asserteq(attrlen(attrs), 0, "parseattrs empty");
}

testParseAttrsSingleAttr(t: ref T)
{
	attrs := factotum->parseattrs("key=value");
	t.asserteq(attrlen(attrs), 1, "parseattrs single count");
	val := factotum->findattrval(attrs, "key");
	t.assertseq(val, "value", "parseattrs single value");
}

testParseAttrsQuery(t: ref T)
{
	attrs := factotum->parseattrs("proto=p9sk1 ?user");
	t.assert(attrs != nil, "parseattrs query non-nil");

	# Find the query attr
	for(l := attrs; l != nil; l = tl l) {
		a := hd l;
		if(a.name == "user") {
			t.asserteq(a.tag, Factotum->Aquery, "query tag");
			return;
		}
	}
	t.error("query attr not found");
}

# ── findattr / findattrval tests ─────────────────────────────────────────────

testFindattr(t: ref T)
{
	attrs := factotum->parseattrs("proto=p9sk1 dom=example.com");

	a := factotum->findattr(attrs, "proto");
	t.assert(a != nil, "findattr proto");
	t.assertseq(a.name, "proto", "findattr name");
	t.assertseq(a.val, "p9sk1", "findattr val");

	missing := factotum->findattr(attrs, "nonexistent");
	t.assert(missing == nil, "findattr nonexistent");
}

testFindattrval(t: ref T)
{
	attrs := factotum->parseattrs("name=value");
	val := factotum->findattrval(attrs, "name");
	t.assertseq(val, "value", "findattrval found");

	val = factotum->findattrval(attrs, "missing");
	t.assertnil(val, "findattrval missing");
}

# ── copyattrs tests ──────────────────────────────────────────────────────────

testCopyattrs(t: ref T)
{
	orig := factotum->parseattrs("a=1 b=2 c=3");
	cp := factotum->copyattrs(orig);
	t.asserteq(attrlen(cp), attrlen(orig), "copy length");

	# Verify values
	t.assertseq(factotum->findattrval(cp, "a"), "1", "copy a");
	t.assertseq(factotum->findattrval(cp, "b"), "2", "copy b");
	t.assertseq(factotum->findattrval(cp, "c"), "3", "copy c");
}

# ── delattr tests ────────────────────────────────────────────────────────────

testDelattr(t: ref T)
{
	attrs := factotum->parseattrs("a=1 b=2 c=3");
	result := factotum->delattr(attrs, "b");
	t.asserteq(attrlen(result), 2, "delattr removes one");
	t.assertseq(factotum->findattrval(result, "a"), "1", "delattr keeps a");
	t.assertseq(factotum->findattrval(result, "c"), "3", "delattr keeps c");
	t.assertnil(factotum->findattrval(result, "b"), "delattr removed b");
}

testDelattrNotFound(t: ref T)
{
	attrs := factotum->parseattrs("a=1 b=2");
	result := factotum->delattr(attrs, "z");
	t.asserteq(attrlen(result), 2, "delattr not found keeps all");
}

# ── takeattrs tests ──────────────────────────────────────────────────────────

testTakeattrs(t: ref T)
{
	attrs := factotum->parseattrs("a=1 b=2 c=3 d=4");
	names := "b" :: "d" :: nil;
	result := factotum->takeattrs(attrs, names);
	t.asserteq(attrlen(result), 2, "takeattrs count");
	t.assertseq(factotum->findattrval(result, "b"), "2", "takeattrs b");
	t.assertseq(factotum->findattrval(result, "d"), "4", "takeattrs d");
}

# ── publicattrs tests ────────────────────────────────────────────────────────

testPublicattrs(t: ref T)
{
	attrs := factotum->parseattrs("proto=p9sk1 !password=secret dom=example.com");
	pub := factotum->publicattrs(attrs);
	# Public attrs should exclude those starting with !
	for(l := pub; l != nil; l = tl l) {
		a := hd l;
		t.assert(a.name != "password" && a.name != "!password",
			sys->sprint("public should not contain secret: %s", a.name));
	}
}

# ── attrtext tests ───────────────────────────────────────────────────────────

testAttrtext(t: ref T)
{
	attrs := factotum->parseattrs("proto=p9sk1 dom=example.com");
	text := factotum->attrtext(attrs);
	t.assertnotnil(text, "attrtext non-empty");
	t.log(sys->sprint("attrtext: %s", text));

	# Should be parseable back
	attrs2 := factotum->parseattrs(text);
	t.assert(attrlen(attrs2) >= 2, "attrtext roundtrip count");
}

# ── Attr.text() method ──────────────────────────────────────────────────────

testAttrTextMethod(t: ref T)
{
	attrs := factotum->parseattrs("key=value");
	if(attrs == nil) {
		t.fatal("parseattrs returned nil");
		return;
	}
	a := hd attrs;
	text := a.text();
	t.assertnotnil(text, "Attr.text() non-empty");
	t.log(sys->sprint("Attr.text(): %s", text));
}

# ── Service availability ────────────────────────────────────────────────────

testFactotumOpen(t: ref T)
{
	fd := factotum->open();
	if(fd == nil) {
		t.skip("factotum service not available");
		return;
	}
	t.log("factotum service is available");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	factotum = load Factotum Factotum->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}
	if(factotum == nil) {
		sys->fprint(sys->fildes(2), "cannot load factotum module: %r\n");
		raise "fail:cannot load factotum";
	}

	factotum->init();

	testing->init();

	for(a := args; a != nil; a = tl a)
		if(hd a == "-v")
			testing->verbose(1);

	# Attribute parsing/manipulation (no service required)
	run("ParseAttrsSimple", testParseAttrsSimple);
	run("ParseAttrsEmpty", testParseAttrsEmpty);
	run("ParseAttrsSingleAttr", testParseAttrsSingleAttr);
	run("ParseAttrsQuery", testParseAttrsQuery);
	run("Findattr", testFindattr);
	run("Findattrval", testFindattrval);
	run("Copyattrs", testCopyattrs);
	run("Delattr", testDelattr);
	run("DelattrNotFound", testDelattrNotFound);
	run("Takeattrs", testTakeattrs);
	run("Publicattrs", testPublicattrs);
	run("Attrtext", testAttrtext);
	run("AttrTextMethod", testAttrTextMethod);

	# Service-dependent tests
	run("FactotumOpen", testFactotumOpen);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
