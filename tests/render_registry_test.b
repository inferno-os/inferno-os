implement RenderRegistryTest;

#
# Tests for the Xenith render registry and renderer dispatch.
#
# Validates that:
#   - The Render module loads and initializes
#   - Built-in renderers are registered (img, md, html, pdf, mermaid)
#   - find() returns correct renderers for known extensions
#   - find() returns nil for unknown extensions
#   - canrender() probes work for known magic bytes
#   - iscontent() correctly identifies renderable paths
#   - Renderer info() returns valid metadata
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Font, Image, Rect, Point: import draw;

include "renderer.m";
include "render.m";

include "testing.m";
	testing: Testing;
	T: import testing;

RenderRegistryTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/render_registry_test.b";

passed := 0;
failed := 0;
skipped := 0;

rendermod: Render;
display: ref Display;

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

testRegistryLoads(t: ref T)
{
	t.assert(rendermod != nil, "Render module loaded");
}

testBuiltinRenderers(t: ref T)
{
	if(rendermod == nil) {
		t.skip("Render module not available");
		return;
	}
	entries := rendermod->getall();
	count := 0;
	for(el := entries; el != nil; el = tl el)
		count++;
	t.assert(count >= 4, sys->sprint("at least 4 renderers registered, got %d", count));

	# Check that specific renderers are present
	hasimg := 0;
	hasmd := 0;
	haspdf := 0;
	hashtml := 0;
	for(el = entries; el != nil; el = tl el) {
		e := hd el;
		t.log(sys->sprint("registered: %s (%s) ext=%s", e.name, e.modpath, e.extensions));
		if(e.name == "Image") hasimg = 1;
		if(e.name == "Markdown") hasmd = 1;
		if(e.name == "PDF") haspdf = 1;
		if(e.name == "HTML") hashtml = 1;
	}
	t.assert(hasimg, "Image renderer registered");
	t.assert(hasmd, "Markdown renderer registered");
	t.assert(haspdf, "PDF renderer registered");
	t.assert(hashtml, "HTML renderer registered");
}

testFindByExtension(t: ref T)
{
	if(rendermod == nil) {
		t.skip("Render module not available");
		return;
	}

	# PNG should find the image renderer
	(r1, e1) := rendermod->findbyext("test.png");
	t.assert(r1 != nil, "found renderer for .png");
	if(r1 != nil) {
		ri := r1->info();
		t.assertseq(ri.name, "Image", "png renderer is Image");
	}

	# .md should find markdown renderer
	(r2, e2) := rendermod->findbyext("readme.md");
	t.assert(r2 != nil, "found renderer for .md");
	if(r2 != nil) {
		ri := r2->info();
		t.assertseq(ri.name, "Markdown", "md renderer is Markdown");
	}

	# .pdf should find PDF renderer
	(r3, e3) := rendermod->findbyext("doc.pdf");
	t.assert(r3 != nil, "found renderer for .pdf");
	if(r3 != nil) {
		ri := r3->info();
		t.assertseq(ri.name, "PDF", "pdf renderer is PDF");
	}

	# .html should find HTML renderer
	(r4, e4) := rendermod->findbyext("page.html");
	t.assert(r4 != nil, "found renderer for .html");
	if(r4 != nil) {
		ri := r4->info();
		t.assertseq(ri.name, "HTML", "html renderer is HTML");
	}

	# Unknown extension should return nil
	(r5, nil) := rendermod->findbyext("file.xyz");
	t.assert(r5 == nil, "no renderer for .xyz");

	# Suppress unused variable warnings
	if(e1 != nil || e2 != nil || e3 != nil || e4 != nil)
		;
}

testIsContent(t: ref T)
{
	if(rendermod == nil) {
		t.skip("Render module not available");
		return;
	}

	t.assert(rendermod->iscontent("photo.png") == 1, ".png is content");
	t.assert(rendermod->iscontent("doc.pdf") == 1, ".pdf is content");
	t.assert(rendermod->iscontent("readme.md") == 1, ".md is content");
	t.assert(rendermod->iscontent("page.html") == 1, ".html is content");
	t.assert(rendermod->iscontent("code.b") == 0, ".b is not content");
	t.assert(rendermod->iscontent("notes.txt") == 0, ".txt is not content");
}

testCanrenderPNG(t: ref T)
{
	if(rendermod == nil) {
		t.skip("Render module not available");
		return;
	}

	# PNG magic bytes: 137 80 78 71 13 10 26 10
	pngdata := array[] of {
		byte 137, byte 80, byte 78, byte 71,
		byte 13, byte 10, byte 26, byte 10,
		byte 0, byte 0, byte 0, byte 13
	};
	(r, nil) := rendermod->find(pngdata, "unknown");
	t.assert(r != nil, "PNG magic bytes detected");
	if(r != nil) {
		ri := r->info();
		t.assertseq(ri.name, "Image", "PNG probe finds Image renderer");
	}
}

testCanrenderPDF(t: ref T)
{
	if(rendermod == nil) {
		t.skip("Render module not available");
		return;
	}

	# PDF magic: %PDF-
	pdfdata := array of byte "%PDF-1.4 fake pdf content";
	(r, nil) := rendermod->find(pdfdata, "unknown");
	t.assert(r != nil, "PDF magic bytes detected");
	if(r != nil) {
		ri := r->info();
		t.assertseq(ri.name, "PDF", "PDF probe finds PDF renderer");
	}
}

testRendererInfo(t: ref T)
{
	if(rendermod == nil) {
		t.skip("Render module not available");
		return;
	}

	entries := rendermod->getall();
	for(el := entries; el != nil; el = tl el) {
		e := hd el;
		# Each entry should have a non-empty name and extensions
		t.assert(len e.name > 0, sys->sprint("renderer %s has name", e.modpath));
		t.assert(len e.extensions > 0, sys->sprint("renderer %s has extensions", e.modpath));

		# Load and check info matches
		(mod, err) := rendermod->find(nil, "test" + e.extensions);
		if(mod == nil) {
			t.log(sys->sprint("could not reload %s: %s", e.modpath, err));
			continue;
		}
		ri := mod->info();
		t.assert(ri != nil, sys->sprint("renderer %s returns non-nil info", e.name));
		if(ri != nil)
			t.assertseq(ri.name, e.name, sys->sprint("info name matches for %s", e.name));
	}
}

testMermaidRenderer(t: ref T)
{
	if(rendermod == nil) {
		t.skip("Render module not available");
		return;
	}

	# Check if mermaid renderer is registered
	(r, nil) := rendermod->findbyext("diagram.mermaid");
	if(r == nil) {
		(r, nil) = rendermod->findbyext("diagram.mmd");
	}
	if(r == nil) {
		t.skip("mermaid renderer not registered");
		return;
	}
	ri := r->info();
	t.assertseq(ri.name, "Mermaid", "mermaid renderer name");
	t.asserteq(ri.hastextcontent, 0, "mermaid has no text content");
}

testFindWithDataAndHint(t: ref T)
{
	if(rendermod == nil) {
		t.skip("Render module not available");
		return;
	}

	# Extension match should take priority over canrender probing
	mddata := array of byte "# Hello World\n\nThis is markdown.";
	(r, nil) := rendermod->find(mddata, "test.md");
	t.assert(r != nil, "find with .md hint succeeds");
	if(r != nil) {
		ri := r->info();
		t.assertseq(ri.name, "Markdown", "md hint finds Markdown renderer");
	}
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;

	testing = load Testing Testing->PATH;
	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}
	testing->init();

	for(a := args; a != nil; a = tl a)
		if(hd a == "-v")
			testing->verbose(1);

	# Initialize display for renderer modules
	display = Display.allocate(nil);
	if(display == nil) {
		sys->fprint(sys->fildes(2), "render_registry_test: cannot allocate display: %r\n");
		raise "fail:no display";
	}

	# Load render registry
	rendermod = load Render Render->PATH;
	if(rendermod != nil)
		rendermod->init(display);

	run("RegistryLoads", testRegistryLoads);
	run("BuiltinRenderers", testBuiltinRenderers);
	run("FindByExtension", testFindByExtension);
	run("IsContent", testIsContent);
	run("CanrenderPNG", testCanrenderPNG);
	run("CanrenderPDF", testCanrenderPDF);
	run("RendererInfo", testRendererInfo);
	run("MermaidRenderer", testMermaidRenderer);
	run("FindWithDataAndHint", testFindWithDataAndHint);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
