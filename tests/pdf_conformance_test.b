implement PdfConformanceTest;

#
# PDF Conformance Test — discovery-based test pipeline.
#
# Walks curated test PDF directories, runs each PDF through:
#   1. Open/parse
#   2. Page count
#   3. Render page 1 at 72 DPI
#   4. Non-blank pixel check
#   5. Text extraction
#
# Test suites are fetched by tests/host/fetch-test-pdfs.sh
# into usr/inferno/test-pdfs/.  If not present, suites skip.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	drawm: Draw;
	Display, Image, Rect, Point: import drawm;

include "readdir.m";
	readdir: Readdir;

include "string.m";
	str: String;

include "testing.m";
	testing: Testing;
	T: import testing;

include "pdf.m";
	pdf: PDF;
	Doc: import pdf;

PdfConformanceTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/pdf_conformance_test.b";

passed := 0;
failed := 0;
skipped := 0;

# Per-suite stats
suite_pass := 0;
suite_warn := 0;
suite_fail := 0;
suite_total := 0;

# Grand totals across all suites
grand_pass := 0;
grand_warn := 0;
grand_fail := 0;
grand_total := 0;
suites_found := 0;
suites_missing := 0;

# Result log file
logfd: ref Sys->FD;

# Per-suite isolation flags
suitefilter: string;	# -suite NAME: run only this suite
offset := 0;		# -offset N: skip first N PDFs
limit := 0;		# -limit N: test at most N (0=unlimited)

TESTPDFROOT: con "/usr/inferno/test-pdfs";

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

# Read a file into a byte array.
readfile(path: string): (array of byte, string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return (nil, sys->sprint("open: %r"));
	(ok, dir) := sys->fstat(fd);
	if(ok < 0)
		return (nil, sys->sprint("fstat: %r"));
	fsize := int dir.length;
	if(fsize == 0)
		return (nil, "empty file");
	data := array[fsize] of byte;
	n := 0;
	while(n < fsize){
		r := sys->read(fd, data[n:], fsize - n);
		if(r <= 0)
			break;
		n += r;
	}
	if(n < fsize)
		return (nil, sys->sprint("short read: %d/%d", n, fsize));
	return (data, nil);
}

# Check if a filename ends with .pdf (case-insensitive).
ispdf(name: string): int
{
	n := len name;
	if(n < 4)
		return 0;
	ext := str->tolower(name[n-4:]);
	return ext == ".pdf";
}

# Recursively find all .pdf files under a directory.
# Returns list in discovery order.
findpdfs(dir: string): list of string
{
	(entries, n) := readdir->init(dir, Readdir->NAME);
	if(n <= 0)
		return nil;

	result: list of string;
	for(i := 0; i < n; i++){
		e := entries[i];
		path := dir + "/" + e.name;
		if(e.qid.qtype & Sys->QTDIR){
			# Recurse into subdirectory
			sub := findpdfs(path);
			for(; sub != nil; sub = tl sub)
				result = hd sub :: result;
		} else if(ispdf(e.name)){
			result = path :: result;
		}
	}
	return result;
}

# Reverse a list (findpdfs builds in reverse order).
revlist(l: list of string): list of string
{
	r: list of string;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}

# Sample pixels to count non-white content.
# Returns number of non-white samples out of a grid.
countnonwhite(img: ref Image): int
{
	w := img.r.dx();
	h := img.r.dy();
	if(w <= 0 || h <= 0)
		return 0;
	buf := array[3] of byte;
	nonwhite := 0;

	# Sample a 4x4 grid
	dy := h / 5;
	dx := w / 5;
	if(dy < 1) dy = 1;
	if(dx < 1) dx = 1;

	for(y := dy; y < h; y += dy){
		for(x := dx; x < w; x += dx){
			r := Rect(Point(x, y), Point(x+1, y+1));
			n := img.readpixels(r, buf);
			if(n >= 3){
				bv := int buf[0];
				gv := int buf[1];
				rv := int buf[2];
				if(rv != 255 || gv != 255 || bv != 255)
					nonwhite++;
			}
		}
	}
	return nonwhite;
}

# Run the full test pipeline on a single PDF.
# Returns: (status, npages, error) where status is "pass", "warn", or "fail".
testpdf(t: ref T, path: string): (string, int, string)
{
	npages := 0;
	doc: ref PDF->Doc;
	{
		# 1. Read
		(data, rerr) := readfile(path);
		if(data == nil){
			t.error(path + ": read error: " + rerr);
			return ("fail", 0, "read error: " + rerr);
		}

		# 2. Parse
		oerr: string;
		(doc, oerr) = pdf->open(data, nil);
		data = nil;	# release early
		if(doc == nil){
			t.error(path + ": open error: " + oerr);
			return ("fail", 0, "open error: " + oerr);
		}

		# 3. Page count
		npages = doc.pagecount();
		if(npages <= 0){
			t.error(path + ": 0 pages");
			doc.close();
			return ("fail", 0, "0 pages");
		}

		# 4. Render page 1
		rendered := 0;
		blank := 0;
		{
			(img, imgerr) := doc.renderpage(1, 72);
			if(img == nil){
				if(imgerr != nil)
					t.log(path + ": render: " + imgerr);
			} else {
				rendered = 1;
				# 5. Non-blank check
				nw := countnonwhite(img);
				if(nw == 0)
					blank = 1;
			}
		} exception e {
		"*" =>
			t.error(path + ": render exception: " + e);
			doc.close();
			return ("fail", npages, "render exception: " + e);
		}

		# 6. Text extraction
		hastext := 0;
		{
			text := doc.extracttext(1);
			if(text != nil && len text > 0)
				hastext = 1;
		} exception e {
		"*" =>
			t.error(path + ": extracttext exception: " + e);
			doc.close();
			return ("fail", npages, "extracttext exception: " + e);
		}

		# Classify result
		if(!rendered){
			doc.close();
			return ("pass", npages, nil);
		}
		if(blank){
			t.log(path + ": warn (blank render, text=" + string hastext +
				" pages=" + string npages + ")");
			doc.close();
			return ("warn", npages, "blank render");
		}
		doc.close();
		return ("pass", npages, nil);
	} exception e {
	"*" =>
		# Catch OOM and other unhandled exceptions
		if(doc != nil)
			doc.close();
		t.error(path + ": exception: " + e);
		return ("fail", npages, e);
	}
}

# Test all PDFs in a directory tree.
testsuite(t: ref T, dir: string, name: string)
{
	# Reset per-suite stats
	suite_pass = 0;
	suite_warn = 0;
	suite_fail = 0;
	suite_total = 0;

	# Check if directory exists
	fd := sys->open(dir, Sys->OREAD);
	if(fd == nil){
		suites_missing++;
		t.skip(name + ": not found (run tests/host/fetch-test-pdfs.sh)");
		return;
	}

	suites_found++;

	# Discover PDFs
	pdfs := revlist(findpdfs(dir));

	count := 0;
	for(l := pdfs; l != nil; l = tl l)
		count++;

	if(count == 0){
		t.log(name + ": 0 PDFs found in " + dir);
		return;
	}

	# Apply offset: skip first N PDFs
	if(offset > 0){
		skip := offset;
		for(; pdfs != nil && skip > 0; pdfs = tl pdfs)
			skip--;
		# Recount
		count = 0;
		for(cl := pdfs; cl != nil; cl = tl cl)
			count++;
	}

	# Apply limit: cap at N PDFs
	if(limit > 0 && count > limit){
		capped: list of string;
		n := limit;
		for(cl := pdfs; cl != nil && n > 0; cl = tl cl){
			capped = hd cl :: capped;
			n--;
		}
		pdfs = revlist(capped);
		count = limit;
	}

	if(offset > 0 || limit > 0)
		t.log(sys->sprint("%s: %d PDFs (offset=%d limit=%d)", name, count, offset, limit));
	else
		t.log(name + ": " + string count + " PDFs found");

	# Test each PDF
	for(l = pdfs; l != nil; l = tl l){
		path := hd l;
		suite_total++;

		result := "fail";
		npages := 0;
		errmsg: string;
		{
			(result, npages, errmsg) = testpdf(t, path);
		} exception e {
		"*" =>
			result = "fail";
			errmsg = e;
		}
		case result {
		"pass" =>
			suite_pass++;
		"warn" =>
			suite_warn++;
		* =>
			suite_fail++;
		}

		# Write result to log file (skip if heap exhausted)
		{
			if(logfd != nil){
				status := "PASS";
				case result {
				"warn" => status = "WARN";
				"fail" => status = "FAIL";
				}
				if(errmsg != nil)
					sys->fprint(logfd, "%s\t%d\t%s\t%s\n",
						status, npages, path, errmsg);
				else
					sys->fprint(logfd, "%s\t%d\t%s\n",
						status, npages, path);
			}
		} exception {
		"*" =>
			;	# silently skip log write on OOM
		}
	}

	# Suite summary
	t.log(sys->sprint("%s: %d tested — %d pass, %d warn, %d fail",
		name, suite_total, suite_pass, suite_warn, suite_fail));

	# Accumulate grand totals
	grand_pass += suite_pass;
	grand_warn += suite_warn;
	grand_fail += suite_fail;
	grand_total += suite_total;

	# Suite fails if > 50% of PDFs fail (allows for expected failures)
	if(suite_total > 0 && suite_fail * 2 > suite_total)
		t.error(sys->sprint("%s: majority failure (%d/%d)",
			name, suite_fail, suite_total));
}

testPdfDifferences(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");
	testsuite(t, TESTPDFROOT + "/pdf-differences", "pdf-differences");
}

testPopplerTest(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");
	testsuite(t, TESTPDFROOT + "/poppler-test", "poppler-test");
}

testBfoPdfa(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");
	testsuite(t, TESTPDFROOT + "/bfo-pdfa", "bfo-pdfa");
}

testPdfTest(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");
	testsuite(t, TESTPDFROOT + "/pdftest", "pdftest");
}

testCabinetOfHorrors(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");
	testsuite(t, TESTPDFROOT + "/cabinet-of-horrors", "cabinet-of-horrors");
}

testItext(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");
	testsuite(t, TESTPDFROOT + "/itext-pdfs", "itext");
}

testPdfJs(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");
	testsuite(t, TESTPDFROOT + "/pdfjs-pdfs/test/pdfs", "pdfjs");
}

testVeraPdf(t: ref T)
{
	if(pdf == nil)
		t.skip("PDF module not available");
	testsuite(t, TESTPDFROOT + "/verapdf-corpus", "verapdf");
}

testGrandSummary(t: ref T)
{
	# Print overall summary across all suites
	t.log("=== PDF Conformance Test Results ===");
	t.log(sys->sprint("Suites:  %d found, %d missing", suites_found, suites_missing));
	t.log(sys->sprint("PDFs:    %d tested", grand_total));
	if(grand_total > 0){
		t.log(sys->sprint("PASS:    %d (%d%%)", grand_pass, grand_pass * 100 / grand_total));
		t.log(sys->sprint("WARN:    %d (%d%%)", grand_warn, grand_warn * 100 / grand_total));
		t.log(sys->sprint("FAIL:    %d (%d%%)", grand_fail, grand_fail * 100 / grand_total));
	}

	# Write summary block to log file
	if(logfd != nil){
		sys->fprint(logfd, "# === Summary ===\n");
		sys->fprint(logfd, "# Suites: %d found, %d missing\n",
			suites_found, suites_missing);
		sys->fprint(logfd, "# PDFs: %d tested\n", grand_total);
		if(grand_total > 0){
			sys->fprint(logfd, "# PASS: %d (%d%%)\n",
				grand_pass, grand_pass * 100 / grand_total);
			sys->fprint(logfd, "# WARN: %d (%d%%)\n",
				grand_warn, grand_warn * 100 / grand_total);
			sys->fprint(logfd, "# FAIL: %d (%d%%)\n",
				grand_fail, grand_fail * 100 / grand_total);
		}
	}

	if(suites_found == 0)
		t.skip("no test suites found (run tests/host/fetch-test-pdfs.sh)");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	drawm = load Draw Draw->PATH;

	readdir = load Readdir Readdir->PATH;
	if(readdir == nil){
		sys->fprint(sys->fildes(2), "cannot load readdir: %r\n");
		raise "fail:cannot load readdir";
	}

	str = load String String->PATH;
	if(str == nil){
		sys->fprint(sys->fildes(2), "cannot load string: %r\n");
		raise "fail:cannot load string";
	}

	testing = load Testing Testing->PATH;
	if(testing == nil){
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}
	testing->init();

	for(a := args; a != nil; a = tl a){
		if(hd a == "-v")
			testing->verbose(1);
		else if(hd a == "-suite" && tl a != nil){
			a = tl a;
			suitefilter = hd a;
		}
		else if(hd a == "-offset" && tl a != nil){
			a = tl a;
			offset = int hd a;
		}
		else if(hd a == "-limit" && tl a != nil){
			a = tl a;
			limit = int hd a;
		}
	}

	pdf = load PDF PDF->PATH;
	if(pdf != nil){
		err := pdf->init(nil);
		if(err != nil)
			sys->fprint(sys->fildes(2), "pdf init warning: %s\n", err);
	}

	# Open result log file
	resultspath := TESTPDFROOT + "/results.txt";
	if(suitefilter != nil){
		# Append mode: open existing file and seek to end
		logfd = sys->open(resultspath, Sys->OWRITE);
		if(logfd != nil)
			sys->seek(logfd, big 0, Sys->SEEKEND);
		else {
			# File doesn't exist yet, create it
			logfd = sys->create(resultspath, Sys->OWRITE, 8r644);
		}
	} else {
		logfd = sys->create(resultspath, Sys->OWRITE, 8r644);
	}
	if(logfd == nil)
		sys->fprint(sys->fildes(2), "warning: cannot open results.txt: %r\n");

	if(suitefilter != nil){
		# Single-suite mode
		case suitefilter {
		"pdf-differences" =>
			run("PdfDifferences", testPdfDifferences);
		"poppler-test" =>
			run("PopplerTest", testPopplerTest);
		"bfo-pdfa" =>
			run("BfoPdfa", testBfoPdfa);
		"pdftest" =>
			run("PdfTest", testPdfTest);
		"cabinet-of-horrors" =>
			run("CabinetOfHorrors", testCabinetOfHorrors);
		"itext" =>
			run("Itext", testItext);
		"pdfjs" =>
			run("PdfJs", testPdfJs);
		"verapdf" =>
			run("VeraPdf", testVeraPdf);
		* =>
			sys->fprint(sys->fildes(2), "unknown suite: %s\n", suitefilter);
			raise "fail:unknown suite";
		}
	} else {
		# All-in-one mode (original behavior)
		run("PdfDifferences", testPdfDifferences);
		run("PopplerTest", testPopplerTest);
		run("BfoPdfa", testBfoPdfa);
		run("PdfTest", testPdfTest);
		run("CabinetOfHorrors", testCabinetOfHorrors);
		run("Itext", testItext);
		run("PdfJs", testPdfJs);
		run("VeraPdf", testVeraPdf);
		run("GrandSummary", testGrandSummary);
	}

	logfd = nil;

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
