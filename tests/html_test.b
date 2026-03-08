implement HtmlTest;

#
# Tests for the HTML module (html.m)
#
# Covers: lex, attrvalue, globalattr, isbreak, lex2string,
#         tag constants, character set handling
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "html.m";
	html: HTML;

include "testing.m";
	testing: Testing;
	T: import testing;

HtmlTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/html_test.b";

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

# ── Basic lexing ─────────────────────────────────────────────────────────────

testLexSimple(t: ref T)
{
	data := array of byte "<html><body>hello</body></html>";
	tokens := html->lex(data, HTML->UTF8, 0);
	t.assert(tokens != nil, "lex returned tokens");
	t.assert(len tokens > 0, "lex non-empty");
	t.log(sys->sprint("token count: %d", len tokens));
}

testLexParagraph(t: ref T)
{
	data := array of byte "<p>Hello World</p>";
	tokens := html->lex(data, HTML->UTF8, 0);
	t.assert(tokens != nil, "lex paragraph not nil");

	# Should have: <p>, text, </p>
	foundP := 0;
	foundText := 0;
	for(i := 0; i < len tokens; i++) {
		if(tokens[i].tag == HTML->Tp)
			foundP++;
		if(tokens[i].tag == HTML->Data)
			foundText++;
	}
	t.assert(foundP > 0, "found <p> tag");
	t.assert(foundText > 0, "found text data");
}

testLexEmpty(t: ref T)
{
	data := array of byte "";
	tokens := html->lex(data, HTML->UTF8, 0);
	t.assert(tokens == nil || len tokens == 0, "lex empty input");
}

# ── Attribute parsing ────────────────────────────────────────────────────────

testLexAttributes(t: ref T)
{
	data := array of byte "<a href=\"http://example.com\" class=\"link\">click</a>";
	tokens := html->lex(data, HTML->UTF8, 0);
	t.assert(tokens != nil, "lex with attrs not nil");

	# Find the <a> tag and check attributes
	for(i := 0; i < len tokens; i++) {
		if(tokens[i].tag == HTML->Ta) {
			(found, val) := html->attrvalue(tokens[i].attr, "href");
			t.assert(found != 0, "href attribute found");
			t.assertseq(val, "http://example.com", "href value");

			(found, val) = html->attrvalue(tokens[i].attr, "class");
			t.assert(found != 0, "class attribute found");
			t.assertseq(val, "link", "class value");

			(found, nil) = html->attrvalue(tokens[i].attr, "missing");
			t.assert(found == 0, "missing attribute not found");
			return;
		}
	}
	t.error("no <a> tag found");
}

# ── globalattr ───────────────────────────────────────────────────────────────

testGlobalattr(t: ref T)
{
	data := array of byte "<html><body id=\"main\"><p>text</p></body></html>";
	tokens := html->lex(data, HTML->UTF8, 0);
	t.assert(tokens != nil, "lex for globalattr not nil");

	(found, val) := html->globalattr(tokens, HTML->Tbody, "id");
	t.assert(found != 0, "globalattr found body id");
	t.assertseq(val, "main", "globalattr body id value");
}

# ── isbreak ──────────────────────────────────────────────────────────────────

testIsbreak(t: ref T)
{
	data := array of byte "<p>text</p><br><hr>";
	tokens := html->lex(data, HTML->UTF8, 0);
	t.assert(tokens != nil, "lex for isbreak not nil");

	# Find <br> and check isbreak
	for(i := 0; i < len tokens; i++) {
		if(tokens[i].tag == HTML->Tbr) {
			t.assert(html->isbreak(tokens, i) != 0, "br is break");
			return;
		}
	}
	t.log("no <br> tag found (may be parser-dependent)");
}

# ── lex2string ───────────────────────────────────────────────────────────────

testLex2string(t: ref T)
{
	data := array of byte "<b>bold</b>";
	tokens := html->lex(data, HTML->UTF8, 0);
	t.assert(tokens != nil, "lex for lex2string not nil");

	for(i := 0; i < len tokens; i++) {
		s := html->lex2string(tokens[i]);
		t.assertnotnil(s, sys->sprint("lex2string token %d", i));
		t.log(sys->sprint("token[%d]: %s", i, s));
	}
}

# ── Tag constants ────────────────────────────────────────────────────────────

testTagConstants(t: ref T)
{
	# Verify key tag constants are distinct
	t.assert(HTML->Ta != HTML->Tb, "Ta != Tb");
	t.assert(HTML->Tp != HTML->Tdiv, "Tp != Tdiv");
	t.assert(HTML->Thtml != HTML->Tbody, "Thtml != Tbody");
	t.assert(HTML->Data != HTML->Notfound, "Data != Notfound");
	t.assert(HTML->RBRA != HTML->Data, "RBRA != Data");
}

# ── Character set handling ───────────────────────────────────────────────────

testUTF8(t: ref T)
{
	data := array of byte "<p>Hello</p>";
	tokens := html->lex(data, HTML->UTF8, 0);
	t.assert(tokens != nil, "UTF8 lex not nil");

	# Check text content
	for(i := 0; i < len tokens; i++) {
		if(tokens[i].tag == HTML->Data) {
			t.assertnotnil(tokens[i].text, "UTF8 text content");
			return;
		}
	}
}

testLatin1(t: ref T)
{
	data := array of byte "<p>test</p>";
	tokens := html->lex(data, HTML->Latin1, 0);
	t.assert(tokens != nil, "Latin1 lex not nil");
}

# ── Nested tags ──────────────────────────────────────────────────────────────

testNestedTags(t: ref T)
{
	data := array of byte "<div><p><b>bold text</b></p></div>";
	tokens := html->lex(data, HTML->UTF8, 0);
	t.assert(tokens != nil, "nested lex not nil");
	t.assert(len tokens >= 5, sys->sprint("nested enough tokens: %d", len tokens));
}

# ── Multiple attributes ─────────────────────────────────────────────────────

testMultipleAttributes(t: ref T)
{
	data := array of byte "<img src=\"test.png\" width=\"100\" height=\"200\">";
	tokens := html->lex(data, HTML->UTF8, 0);
	t.assert(tokens != nil, "multi-attr lex not nil");

	for(i := 0; i < len tokens; i++) {
		if(tokens[i].tag == HTML->Timg) {
			(f1, v1) := html->attrvalue(tokens[i].attr, "src");
			t.assert(f1 != 0, "img src found");
			t.assertseq(v1, "test.png", "img src value");

			(f2, v2) := html->attrvalue(tokens[i].attr, "width");
			t.assert(f2 != 0, "img width found");
			t.assertseq(v2, "100", "img width value");

			(f3, v3) := html->attrvalue(tokens[i].attr, "height");
			t.assert(f3 != 0, "img height found");
			t.assertseq(v3, "200", "img height value");
			return;
		}
	}
	t.error("no <img> tag found");
}

# ── Keepnls flag ─────────────────────────────────────────────────────────────

testKeepNewlines(t: ref T)
{
	data := array of byte "<pre>line1\nline2\n</pre>";
	tokens := html->lex(data, HTML->UTF8, 1);  # keepnls=1
	t.assert(tokens != nil, "keepnls lex not nil");
	t.log(sys->sprint("keepnls tokens: %d", len tokens));
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	html = load HTML HTML->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}
	if(html == nil) {
		sys->fprint(sys->fildes(2), "cannot load html module: %r\n");
		raise "fail:cannot load html";
	}

	testing->init();

	for(a := args; a != nil; a = tl a)
		if(hd a == "-v")
			testing->verbose(1);

	run("LexSimple", testLexSimple);
	run("LexParagraph", testLexParagraph);
	run("LexEmpty", testLexEmpty);
	run("LexAttributes", testLexAttributes);
	run("Globalattr", testGlobalattr);
	run("Isbreak", testIsbreak);
	run("Lex2string", testLex2string);
	run("TagConstants", testTagConstants);
	run("UTF8", testUTF8);
	run("Latin1", testLatin1);
	run("NestedTags", testNestedTags);
	run("MultipleAttributes", testMultipleAttributes);
	run("KeepNewlines", testKeepNewlines);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
