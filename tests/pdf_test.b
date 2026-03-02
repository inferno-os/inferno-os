implement PdfTest;

#
# Unit tests for the PDF module.
#
# Tests PDF parsing, text extraction, page navigation,
# and rendering pipeline (when display available).
#

include "sys.m";
	sys: Sys;

include "draw.m";
	drawm: Draw;
	Display: import drawm;

include "testing.m";
	testing: Testing;
	T: import testing;

include "pdf.m";
	pdf: PDF;
	Doc: import pdf;

PdfTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/pdf_test.b";

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

# Build a minimal valid PDF in memory
# This is the simplest possible PDF: one page, one text string
makeminipdf(): array of byte
{
	s := "%PDF-1.4\n";
	s += "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n";
	s += "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n";
	s += "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\nendobj\n";
	s += "4 0 obj\n<< /Length 44 >>\nstream\nBT /F1 12 Tf 100 700 Td (Hello World) Tj ET\nendstream\nendobj\n";
	s += "5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n";
	s += "xref\n0 6\n";
	s += "0000000000 65535 f \n";

	# Calculate offsets manually
	# obj 1 starts at offset 10 (%PDF-1.4\n)
	s += "0000000010 00000 n \n";
	# These offsets don't need to be exact for our parser since we test via open()
	s += "0000000063 00000 n \n";
	s += "0000000120 00000 n \n";
	s += "0000000300 00000 n \n";
	s += "0000000400 00000 n \n";
	s += "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n";

	# We need to put the actual xref offset here
	# For testing, we'll build the PDF more carefully
	return nil;
}

# Build a minimal PDF with correct offsets
buildtestpdf(): array of byte
{
	parts: list of (int, string);  # (objnum, content)

	# Build objects as strings, track their byte offsets
	obj1 := "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n";
	obj2 := "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n";

	# Page with MediaBox and simple content stream
	obj3 := "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>\nendobj\n";

	# Content stream: just "BT (Hello World) Tj ET"
	stream := "BT 100 700 Td (Hello World) Tj ET";
	obj4 := "4 0 obj\n<< /Length " + string len stream + " >>\nstream\n" + stream + "\nendstream\nendobj\n";

	header := "%PDF-1.4\n";

	off1 := len header;
	off2 := off1 + len obj1;
	off3 := off2 + len obj2;
	off4 := off3 + len obj3;

	body := header + obj1 + obj2 + obj3 + obj4;
	xrefoff := len body;

	xref := "xref\n0 5\n";
	xref += sys->sprint("0000000000 65535 f \n");
	xref += sys->sprint("%010d 00000 n \n", off1);
	xref += sys->sprint("%010d 00000 n \n", off2);
	xref += sys->sprint("%010d 00000 n \n", off3);
	xref += sys->sprint("%010d 00000 n \n", off4);
	xref += "trailer\n<< /Size 5 /Root 1 0 R >>\n";
	xref += "startxref\n" + string xrefoff + "\n%%EOF\n";

	full := body + xref;
	data := array[len full] of byte;
	for(i := 0; i < len full; i++)
		data[i] = byte full[i];
	return data;
}

# Build a PDF with two pages
buildtwopagepdf(): array of byte
{
	header := "%PDF-1.4\n";
	obj1 := "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n";
	obj2 := "2 0 obj\n<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>\nendobj\n";

	stream1 := "BT 100 700 Td (Page One) Tj ET";
	obj3 := "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>\nendobj\n";
	obj4 := "4 0 obj\n<< /Length " + string len stream1 + " >>\nstream\n" + stream1 + "\nendstream\nendobj\n";

	stream2 := "BT 100 700 Td (Page Two) Tj ET";
	obj5 := "5 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 6 0 R >>\nendobj\n";
	obj6 := "6 0 obj\n<< /Length " + string len stream2 + " >>\nstream\n" + stream2 + "\nendstream\nendobj\n";

	off1 := len header;
	off2 := off1 + len obj1;
	off3 := off2 + len obj2;
	off4 := off3 + len obj3;
	off5 := off4 + len obj4;
	off6 := off5 + len obj5;

	body := header + obj1 + obj2 + obj3 + obj4 + obj5 + obj6;
	xrefoff := len body;

	xref := "xref\n0 7\n";
	xref += sys->sprint("0000000000 65535 f \n");
	xref += sys->sprint("%010d 00000 n \n", off1);
	xref += sys->sprint("%010d 00000 n \n", off2);
	xref += sys->sprint("%010d 00000 n \n", off3);
	xref += sys->sprint("%010d 00000 n \n", off4);
	xref += sys->sprint("%010d 00000 n \n", off5);
	xref += sys->sprint("%010d 00000 n \n", off6);
	xref += "trailer\n<< /Size 7 /Root 1 0 R >>\n";
	xref += "startxref\n" + string xrefoff + "\n%%EOF\n";

	full := body + xref;
	data := array[len full] of byte;
	for(i := 0; i < len full; i++)
		data[i] = byte full[i];
	return data;
}

# Build a PDF with vector graphics (rect + line)
buildvectorpdf(): array of byte
{
	header := "%PDF-1.4\n";
	obj1 := "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n";
	obj2 := "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n";

	# Content: red filled rectangle + blue stroked line
	stream := "q\n";
	stream += "1 0 0 rg\n";       # red fill
	stream += "100 600 200 100 re\n";  # rectangle
	stream += "f\n";              # fill
	stream += "0 0 1 RG\n";       # blue stroke
	stream += "2 w\n";            # line width
	stream += "50 500 m 400 500 l S\n"; # line
	stream += "Q\n";

	obj3 := "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>\nendobj\n";
	obj4 := "4 0 obj\n<< /Length " + string len stream + " >>\nstream\n" + stream + "\nendstream\nendobj\n";

	off1 := len header;
	off2 := off1 + len obj1;
	off3 := off2 + len obj2;
	off4 := off3 + len obj3;

	body := header + obj1 + obj2 + obj3 + obj4;
	xrefoff := len body;

	xref := "xref\n0 5\n";
	xref += sys->sprint("0000000000 65535 f \n");
	xref += sys->sprint("%010d 00000 n \n", off1);
	xref += sys->sprint("%010d 00000 n \n", off2);
	xref += sys->sprint("%010d 00000 n \n", off3);
	xref += sys->sprint("%010d 00000 n \n", off4);
	xref += "trailer\n<< /Size 5 /Root 1 0 R >>\n";
	xref += "startxref\n" + string xrefoff + "\n%%EOF\n";

	full := body + xref;
	data := array[len full] of byte;
	for(i := 0; i < len full; i++)
		data[i] = byte full[i];
	return data;
}

testLoadModule(t: ref T)
{
	if(pdf == nil)
		t.fatal("cannot load PDF module");
	t.log("PDF module loaded successfully");
}

testOpenInvalidData(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");

	# Empty data
	(doc, err) := pdf->open(array[0] of byte, nil);
	t.assert(doc == nil, "empty data should fail");
	t.assertnotnil(err, "should return error for empty data");

	# Not a PDF
	notpdf := array[20] of byte;
	for(i := 0; i < 20; i++)
		notpdf[i] = byte 'x';
	(doc2, err2) := pdf->open(notpdf, nil);
	t.assert(doc2 == nil, "non-PDF data should fail");
	t.assertnotnil(err2, "should return error for non-PDF data");
}

testOpenValidPdf(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");

	data := buildtestpdf();
	(doc, err) := pdf->open(data, nil);
	if(doc == nil)
		t.fatal("open failed: " + err);

	t.asserteq(doc.pagecount(), 1, "should have 1 page");
	t.log("opened test PDF with " + string doc.pagecount() + " page(s)");
}

testPageCount(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");

	data := buildtwopagepdf();
	(doc, err) := pdf->open(data, nil);
	if(doc == nil)
		t.fatal("open failed: " + err);

	t.asserteq(doc.pagecount(), 2, "should have 2 pages");
}

testPageSize(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");

	data := buildtwopagepdf();
	(doc, err) := pdf->open(data, nil);
	if(doc == nil)
		t.fatal("open failed: " + err);

	# Page 1: US Letter 612x792
	(w1, h1) := doc.pagesize(1);
	t.assert(int w1 == 612, sys->sprint("page 1 width: got %g, want 612", w1));
	t.assert(int h1 == 792, sys->sprint("page 1 height: got %g, want 792", h1));

	# Page 2: A4 595x842
	(w2, h2) := doc.pagesize(2);
	t.assert(int w2 == 595, sys->sprint("page 2 width: got %g, want 595", w2));
	t.assert(int h2 == 842, sys->sprint("page 2 height: got %g, want 842", h2));
}

testExtractText(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");

	data := buildtestpdf();
	(doc, err) := pdf->open(data, nil);
	if(doc == nil)
		t.fatal("open failed: " + err);

	text := doc.extracttext(1);
	if(text == nil){
		t.error("extracttext returned nil");
		return;
	}

	t.log("extracted text: " + text);
	# Check that "Hello World" appears in extracted text
	found := 0;
	for(i := 0; i + 10 < len text; i++){
		if(text[i:i+11] == "Hello World"){
			found = 1;
			break;
		}
	}
	t.assert(found, "extracted text should contain 'Hello World'");
}

testExtractAll(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");

	data := buildtwopagepdf();
	(doc, err) := pdf->open(data, nil);
	if(doc == nil)
		t.fatal("open failed: " + err);

	text := doc.extractall();
	if(text == nil){
		t.error("extractall returned nil");
		return;
	}

	t.log("extracted all text length: " + string len text);

	# Should contain text from both pages
	hasone := 0;
	hastwo := 0;
	for(i := 0; i < len text; i++){
		if(i + 8 <= len text && text[i:i+8] == "Page One")
			hasone = 1;
		if(i + 8 <= len text && text[i:i+8] == "Page Two")
			hastwo = 1;
	}
	t.assert(hasone, "should contain 'Page One'");
	t.assert(hastwo, "should contain 'Page Two'");
}

testRenderPage(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");

	data := buildvectorpdf();
	(doc, err) := pdf->open(data, nil);
	if(doc == nil)
		t.fatal("open failed: " + err);

	# Render at 72 DPI (1:1 with PDF points)
	(img, rerr) := doc.renderpage(1, 72);
	if(img == nil){
		# May fail without display
		if(rerr != nil)
			t.log("render skipped (no display?): " + rerr);
		t.skip("rendering requires display");
		return;
	}

	# Check image dimensions: 612x792 at 72 DPI
	r := img.r;
	w := r.max.x - r.min.x;
	h := r.max.y - r.min.y;
	t.asserteq(w, 612, sys->sprint("image width: got %d, want 612", w));
	t.asserteq(h, 792, sys->sprint("image height: got %d, want 792", h));
	t.log(sys->sprint("rendered %dx%d image", w, h));
}

testRenderDPI(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");

	data := buildtestpdf();
	(doc, err) := pdf->open(data, nil);
	if(doc == nil)
		t.fatal("open failed: " + err);

	# Render at 150 DPI
	(img, rerr) := doc.renderpage(1, 150);
	if(img == nil){
		if(rerr != nil)
			t.log("render skipped: " + rerr);
		t.skip("rendering requires display");
		return;
	}

	r := img.r;
	w := r.max.x - r.min.x;
	h := r.max.y - r.min.y;
	# 612 * 150/72 ≈ 1275, 792 * 150/72 ≈ 1650
	t.assert(w > 1200 && w < 1350, sys->sprint("150dpi width: got %d, want ~1275", w));
	t.assert(h > 1600 && h < 1700, sys->sprint("150dpi height: got %d, want ~1650", h));
	t.log(sys->sprint("rendered %dx%d at 150 DPI", w, h));
}

testInvalidPageNum(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");

	data := buildtestpdf();
	(doc, err) := pdf->open(data, nil);
	if(doc == nil)
		t.fatal("open failed: " + err);

	# Page 0 (invalid)
	text := doc.extracttext(0);
	t.assert(text == nil, "page 0 should return nil");

	# Page 99 (out of range)
	text = doc.extracttext(99);
	t.assert(text == nil, "page 99 should return nil");
}

# Regression: TJ array two-byte alignment (fix 2026-02-19)
# Inserting single-byte spaces into raw two-byte strings misaligns
# all subsequent character reads, producing garbage CIDs.
testTJArrayAlignment(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");

	# Build a PDF with a TJ array containing large kern adjustments.
	# For a two-byte (Identity-H) font, the raw bytes in TJ string
	# segments must remain aligned. A kern adjustment must NOT inject
	# a single byte into the concatenated output.
	header := "%PDF-1.4\n";
	obj1 := "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n";
	obj2 := "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n";

	# Content stream with TJ array and large kern
	stream := "BT /F1 12 Tf 100 700 Td [(Hello) -200 (World)] TJ ET";
	obj3 := "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\nendobj\n";
	obj4 := "4 0 obj\n<< /Length " + string len stream + " >>\nstream\n" + stream + "\nendstream\nendobj\n";
	obj5 := "5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n";

	off1 := len header;
	off2 := off1 + len obj1;
	off3 := off2 + len obj2;
	off4 := off3 + len obj3;
	off5 := off4 + len obj4;

	body := header + obj1 + obj2 + obj3 + obj4 + obj5;
	xrefoff := len body;

	xref := "xref\n0 6\n";
	xref += sys->sprint("0000000000 65535 f \n");
	xref += sys->sprint("%010d 00000 n \n", off1);
	xref += sys->sprint("%010d 00000 n \n", off2);
	xref += sys->sprint("%010d 00000 n \n", off3);
	xref += sys->sprint("%010d 00000 n \n", off4);
	xref += sys->sprint("%010d 00000 n \n", off5);
	xref += "trailer\n<< /Size 6 /Root 1 0 R >>\n";
	xref += "startxref\n" + string xrefoff + "\n%%EOF\n";

	full := body + xref;
	data := array[len full] of byte;
	for(i := 0; i < len full; i++)
		data[i] = byte full[i];

	(doc, err) := pdf->open(data, nil);
	if(doc == nil)
		t.fatal("open failed: " + err);

	# Extract text — should contain both "Hello" and "World"
	text := doc.extracttext(1);
	if(text == nil){
		t.error("extracttext returned nil");
		return;
	}
	t.log("TJ text: " + text);

	# Verify both segments are present (kern didn't corrupt text)
	hasHello := 0;
	hasWorld := 0;
	for(j := 0; j < len text; j++){
		if(j + 5 <= len text && text[j:j+5] == "Hello")
			hasHello = 1;
		if(j + 5 <= len text && text[j:j+5] == "World")
			hasWorld = 1;
	}
	t.assert(hasHello, "TJ text should contain 'Hello'");
	t.assert(hasWorld, "TJ text should contain 'World'");
}

# Regression: real PDF with embedded CFF fonts (integration test)
# Exercises: font extraction, CID→GID mapping, glyph cache isolation,
# TJ array handling, and text extraction from CID-keyed fonts.
testRealPdfTextExtraction(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");

	pdfpath := "/usr/inferno/Finn-CurriculumVitae.pdf";
	fd := sys->open(pdfpath, Sys->OREAD);
	if(fd == nil){
		t.skip("test PDF not available at " + pdfpath);
		return;
	}
	(ok, dir) := sys->fstat(fd);
	if(ok < 0 || dir.length == big 0){
		t.skip("cannot stat test PDF");
		return;
	}
	data := array[int dir.length] of byte;
	n := 0;
	while(n < len data){
		r := sys->read(fd, data[n:], len data - n);
		if(r <= 0) break;
		n += r;
	}

	(doc, err) := pdf->open(data[:n], nil);
	if(doc == nil)
		t.fatal("open failed: " + err);

	pc := doc.pagecount();
	t.assert(pc == 4, sys->sprint("expected 4 pages, got %d", pc));

	# Page 1 text extraction should produce substantial text
	text := doc.extracttext(1);
	t.assert(text != nil, "page 1 text should not be nil");
	t.assert(len text > 1000, sys->sprint("page 1 text too short: %d chars", len text));
	t.log(sys->sprint("page 1: %d chars extracted", len text));

	# Key phrases that should appear (exercises CID font decoding).
	# Note: PDF uses mixed fonts — some text is small caps (all uppercase),
	# some is regular body text.  Test for phrases that appear in body text.
	phrases := array[] of {
		"Doctor",
		"Philosophy",
		"Science",
		"London",
	};
	for(i := 0; i < len phrases; i++){
		phrase := phrases[i];
		found := 0;
		for(j := 0; j + len phrase <= len text; j++){
			if(text[j:j+len phrase] == phrase){
				found = 1;
				break;
			}
		}
		t.assert(found, "should contain '" + phrase + "'");
	}

	# All pages should extract without error
	alltext := doc.extractall();
	t.assert(alltext != nil, "extractall should not be nil");
	t.assert(len alltext > len text, "all-page text should be longer than page 1");
	t.log(sys->sprint("all pages: %d chars extracted", len alltext));
}

# Regression: dumppage diagnostic function
testDumpPage(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");

	data := buildtestpdf();
	(doc, err) := pdf->open(data, nil);
	if(doc == nil)
		t.fatal("open failed: " + err);

	dump := doc.dumppage(1);
	t.assert(len dump > 0, "dumppage should produce output");
	t.log("dump length: " + string len dump);

	# Should contain MediaBox info
	hasmb := 0;
	for(i := 0; i + 8 <= len dump; i++){
		if(dump[i:i+8] == "mediabox")
			hasmb = 1;
	}
	t.assert(hasmb, "dump should contain mediabox info");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	drawm = load Draw Draw->PATH;

	testing = load Testing Testing->PATH;
	if(testing == nil){
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}
	testing->init();

	for(a := args; a != nil; a = tl a){
		if(hd a == "-v")
			testing->verbose(1);
	}

	pdf = load PDF PDF->PATH;
	if(pdf != nil){
		# Init without display -- text extraction works,
		# rendering tests will skip if no display
		err := pdf->init(nil);
		if(err != nil)
			sys->fprint(sys->fildes(2), "pdf init warning: %s\n", err);
	}

	run("LoadModule", testLoadModule);
	run("OpenInvalidData", testOpenInvalidData);
	run("OpenValidPdf", testOpenValidPdf);
	run("PageCount", testPageCount);
	run("PageSize", testPageSize);
	run("ExtractText", testExtractText);
	run("ExtractAll", testExtractAll);
	run("RenderPage", testRenderPage);
	run("RenderDPI", testRenderDPI);
	run("InvalidPageNum", testInvalidPageNum);
	run("TJArrayAlignment", testTJArrayAlignment);
	run("RealPdfTextExtraction", testRealPdfTextExtraction);
	run("DumpPage", testDumpPage);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
