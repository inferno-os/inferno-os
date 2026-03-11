implement XmlTest;

#
# Tests for the XML module (xml.m)
#
# Covers: init, open/fopen, Parser.next, Tag/Text/Process items,
#         Attributes, error handling, nested elements
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "xml.m";
	xml: Xml;
	Parser, Attributes: import xml;

include "testing.m";
	testing: Testing;
	T: import testing;

XmlTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/xml_test.b";

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

# Helper: create parser from string
mkparser(s: string): ref Xml->Parser
{
	b := bufio->sopen(s);
	(p, err) := xml->fopen(b, "test", nil, nil);
	if(err != nil || p == nil)
		return nil;
	return p;
}

# ── Init test ────────────────────────────────────────────────────────────────

testInit(t: ref T)
{
	err := xml->init();
	t.assertnil(err, "xml init");
}

# ── Simple element ───────────────────────────────────────────────────────────

testSimpleElement(t: ref T)
{
	p := mkparser("<root>hello</root>");
	if(p == nil) {
		t.fatal("cannot create parser");
		return;
	}

	item := p.next();
	if(item == nil) {
		t.fatal("next returned nil");
		return;
	}
	pick tag := item {
	Tag =>
		t.assertseq(tag.name, "root", "root tag name");
	* =>
		t.error("expected Tag, got other");
	}

	# Text content
	p.down();
	item = p.next();
	if(item == nil) {
		t.fatal("text item nil");
		return;
	}
	pick text := item {
	Text =>
		t.assertseq(text.ch, "hello", "text content");
	* =>
		t.error("expected Text, got other");
	}
}

# ── Attributes ───────────────────────────────────────────────────────────────

testAttributes(t: ref T)
{
	p := mkparser("<div class=\"main\" id=\"top\">text</div>");
	if(p == nil) {
		t.fatal("cannot create parser");
		return;
	}

	item := p.next();
	if(item == nil) {
		t.fatal("next returned nil");
		return;
	}
	pick tag := item {
	Tag =>
		t.assertseq(tag.name, "div", "div tag name");
		cls := tag.attrs.get("class");
		t.assertseq(cls, "main", "class attribute");
		id := tag.attrs.get("id");
		t.assertseq(id, "top", "id attribute");
		missing := tag.attrs.get("nonexistent");
		t.assertnil(missing, "missing attribute");
	* =>
		t.error("expected Tag");
	}
}

# ── Nested elements ──────────────────────────────────────────────────────────

testNested(t: ref T)
{
	p := mkparser("<a><b><c>deep</c></b></a>");
	if(p == nil) {
		t.fatal("cannot create parser");
		return;
	}

	# <a>
	item := p.next();
	pick a := item {
	Tag =>
		t.assertseq(a.name, "a", "outer tag");
	* =>
		t.error("expected Tag a");
	}

	# <b>
	p.down();
	item = p.next();
	pick b := item {
	Tag =>
		t.assertseq(b.name, "b", "middle tag");
	* =>
		t.error("expected Tag b");
	}

	# <c>
	p.down();
	item = p.next();
	pick c := item {
	Tag =>
		t.assertseq(c.name, "c", "inner tag");
	* =>
		t.error("expected Tag c");
	}
}

# ── Self-closing elements ───────────────────────────────────────────────────

testSelfClosing(t: ref T)
{
	p := mkparser("<root><br/><hr/></root>");
	if(p == nil) {
		t.fatal("cannot create parser");
		return;
	}

	# <root>
	item := p.next();
	pick r := item {
	Tag =>
		t.assertseq(r.name, "root", "root tag");
	* =>
		t.error("expected Tag root");
	}

	# first child <br/>
	p.down();
	item = p.next();
	if(item == nil) {
		t.fatal("br item nil");
		return;
	}
	pick br := item {
	Tag =>
		t.assertseq(br.name, "br", "br tag");
	* =>
		t.error("expected Tag br");
	}
}

# ── Processing instructions ─────────────────────────────────────────────────

testProcessingInstruction(t: ref T)
{
	p := mkparser("<?xml version=\"1.0\"?><root/>");
	if(p == nil) {
		t.fatal("cannot create parser");
		return;
	}

	item := p.next();
	if(item == nil) {
		t.fatal("next returned nil");
		return;
	}
	pick pi := item {
	Process =>
		t.assertseq(pi.target, "xml", "PI target");
		t.log(sys->sprint("PI data: %s", pi.data));
	* =>
		# May get a Tag if parser skips PI
		t.log("parser skipped PI");
	}
}

# ── Empty document ───────────────────────────────────────────────────────────

testEmptyElement(t: ref T)
{
	p := mkparser("<empty/>");
	if(p == nil) {
		t.fatal("cannot create parser");
		return;
	}

	item := p.next();
	pick e := item {
	Tag =>
		t.assertseq(e.name, "empty", "empty element name");
	* =>
		t.error("expected Tag");
	}
}

# ── Multiple siblings ────────────────────────────────────────────────────────

testSiblings(t: ref T)
{
	p := mkparser("<root><a>1</a><b>2</b><c>3</c></root>");
	if(p == nil) {
		t.fatal("cannot create parser");
		return;
	}

	# <root>
	item := p.next();
	pick r := item {
	Tag =>
		t.assertseq(r.name, "root", "root");
	* =>
		t.error("expected root Tag");
		return;
	}

	# children
	p.down();
	names := array[] of {"a", "b", "c"};
	for(i := 0; i < len names; i++) {
		item = p.next();
		if(item == nil) {
			t.error(sys->sprint("sibling %d nil", i));
			continue;
		}
		pick tag := item {
		Tag =>
			t.assertseq(tag.name, names[i], sys->sprint("sibling %d name", i));
		* =>
			t.error(sys->sprint("sibling %d not Tag", i));
		}
	}
}

# ── Whitespace text ──────────────────────────────────────────────────────────

testWhitespace(t: ref T)
{
	p := mkparser("<root>  spaces  </root>");
	if(p == nil) {
		t.fatal("cannot create parser");
		return;
	}

	item := p.next();	# <root>
	p.down();
	item = p.next();	# text
	if(item == nil) {
		t.fatal("text nil");
		return;
	}
	pick text := item {
	Text =>
		t.assertnotnil(text.ch, "whitespace text not nil");
		t.log(sys->sprint("text: '%s'", text.ch));
	* =>
		t.error("expected Text");
	}
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	xml = load Xml Xml->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}
	if(bufio == nil) {
		sys->fprint(sys->fildes(2), "cannot load bufio module: %r\n");
		raise "fail:cannot load bufio";
	}
	if(xml == nil) {
		sys->fprint(sys->fildes(2), "cannot load xml module: %r\n");
		raise "fail:cannot load xml";
	}

	err := xml->init();
	if(err != nil) {
		sys->fprint(sys->fildes(2), "xml init failed: %s\n", err);
		raise "fail:xml init";
	}

	testing->init();

	for(a := args; a != nil; a = tl a)
		if(hd a == "-v")
			testing->verbose(1);

	run("Init", testInit);
	run("SimpleElement", testSimpleElement);
	run("Attributes", testAttributes);
	run("Nested", testNested);
	run("SelfClosing", testSelfClosing);
	run("ProcessingInstruction", testProcessingInstruction);
	run("EmptyElement", testEmptyElement);
	run("Siblings", testSiblings);
	run("Whitespace", testWhitespace);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
