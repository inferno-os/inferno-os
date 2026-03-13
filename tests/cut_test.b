implement CutTest;

#
# cut_test - Test the cut command
#
# Tests cut by loading it as a module and invoking init()
# with various argument combinations and temp file inputs.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "testing.m";
	testing: Testing;
	T: import testing;

CutTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

Cmd: module
{
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

passed := 0;
failed := 0;
skipped := 0;

SRCFILE: con "/tests/cut_test.b";

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

# Helper: write content to a temp file and return path
writetemp(content: string, suffix: string): string
{
	path := sys->sprint("/tmp/cut_test_%s", suffix);
	fd := sys->create(path, Sys->OWRITE, 8r644);
	if(fd == nil)
		return nil;
	data := array of byte content;
	sys->write(fd, data, len data);
	return path;
}

# Helper: read file content
readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return "";
	return string buf[:n];
}

# Helper: run cut command, capturing output
# Creates input file, redirects stdout to output file,
# runs cut, returns output
runcut(args: list of string, input: string): string
{
	# Write input to temp file
	inpath := writetemp(input, "in");
	if(inpath == nil)
		return nil;

	# Add input file to args
	rargs: list of string;
	for(a := args; a != nil; a = tl a)
		rargs = hd a :: rargs;
	rargs = inpath :: rargs;

	# Reverse to get correct order
	fargs: list of string;
	for(; rargs != nil; rargs = tl rargs)
		fargs = hd rargs :: fargs;

	# Use pipe to capture output
	p := array[2] of ref Sys->FD;
	if(sys->pipe(p) < 0)
		return nil;

	# Spawn cut in a separate process
	done := chan of int;
	spawn runcutproc(fargs, p[1], done);

	# Read output from pipe
	p[1] = nil;
	outbuf := array[8192] of byte;
	total := 0;
	for(;;) {
		n := sys->read(p[0], outbuf[total:], len outbuf - total);
		if(n <= 0)
			break;
		total += n;
	}
	p[0] = nil;

	<-done;

	# Clean up temp file
	sys->remove(inpath);

	if(total == 0)
		return "";
	return string outbuf[:total];
}

runcutproc(args: list of string, stdout: ref Sys->FD, done: chan of int)
{
	# Redirect stdout
	sys->dup(stdout.fd, 1);
	stdout = nil;

	{
		cut := load Cmd "/dis/cut.dis";
		if(cut != nil)
			cut->init(nil, "cut" :: args);
	} exception {
	"*" =>
		;
	}
	done <-= 1;
}

# Test basic field extraction with tab delimiter
testFieldsTab(t: ref T)
{
	result := runcut("-f" :: "2" :: nil, "a\tb\tc\n");
	if(result == nil) {
		t.skip("cannot run cut");
		return;
	}
	t.assertseq(result, "b\n", "field 2 with tab delimiter");
}

# Test field extraction with custom delimiter
testFieldsDelim(t: ref T)
{
	result := runcut("-d" :: ":" :: "-f" :: "1,3" :: nil, "a:b:c:d\n");
	if(result == nil) {
		t.skip("cannot run cut");
		return;
	}
	t.assertseq(result, "a:c\n", "fields 1,3 with colon delimiter");
}

# Test field range
testFieldRange(t: ref T)
{
	result := runcut("-d" :: ":" :: "-f" :: "2-4" :: nil, "a:b:c:d:e\n");
	if(result == nil) {
		t.skip("cannot run cut");
		return;
	}
	t.assertseq(result, "b:c:d\n", "field range 2-4");
}

# Test open-ended range N-
testFieldOpenEnd(t: ref T)
{
	result := runcut("-d" :: ":" :: "-f" :: "3-" :: nil, "a:b:c:d:e\n");
	if(result == nil) {
		t.skip("cannot run cut");
		return;
	}
	t.assertseq(result, "c:d:e\n", "field range 3-");
}

# Test open-ended range -M
testFieldOpenStart(t: ref T)
{
	result := runcut("-d" :: ":" :: "-f" :: "-2" :: nil, "a:b:c:d:e\n");
	if(result == nil) {
		t.skip("cannot run cut");
		return;
	}
	t.assertseq(result, "a:b\n", "field range -2");
}

# Test character extraction
testChars(t: ref T)
{
	result := runcut("-c" :: "2-4" :: nil, "abcdefgh\n");
	if(result == nil) {
		t.skip("cannot run cut");
		return;
	}
	t.assertseq(result, "bcd\n", "characters 2-4");
}

# Test suppress flag
testSuppressNoDelim(t: ref T)
{
	result := runcut("-d" :: ":" :: "-f" :: "1" :: "-s" :: nil, "no-colon\nhas:colon\n");
	if(result == nil) {
		t.skip("cannot run cut");
		return;
	}
	t.assertseq(result, "has\n", "suppress lines without delimiter");
}

# Test no suppress (default) - lines without delimiter passed through
testNoSuppressDefault(t: ref T)
{
	result := runcut("-d" :: ":" :: "-f" :: "1" :: nil, "no-colon\nhas:colon\n");
	if(result == nil) {
		t.skip("cannot run cut");
		return;
	}
	t.assertseq(result, "no-colon\nhas\n", "no suppress passes through lines without delim");
}

# Test empty fields (adjacent delimiters)
testEmptyFields(t: ref T)
{
	result := runcut("-d" :: ":" :: "-f" :: "1,2,3" :: nil, "a::c\n");
	if(result == nil) {
		t.skip("cannot run cut");
		return;
	}
	t.assertseq(result, "a::c\n", "preserves empty fields");
}

# Test multiple lines
testMultipleLines(t: ref T)
{
	input := "a:b:c\nd:e:f\ng:h:i\n";
	result := runcut("-d" :: ":" :: "-f" :: "2" :: nil, input);
	if(result == nil) {
		t.skip("cannot run cut");
		return;
	}
	t.assertseq(result, "b\ne\nh\n", "multiple lines field 2");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}

	testing->init();

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	run("FieldsTab", testFieldsTab);
	run("FieldsDelim", testFieldsDelim);
	run("FieldRange", testFieldRange);
	run("FieldOpenEnd", testFieldOpenEnd);
	run("FieldOpenStart", testFieldOpenStart);
	run("Chars", testChars);
	run("SuppressNoDelim", testSuppressNoDelim);
	run("NoSuppressDefault", testNoSuppressDefault);
	run("EmptyFields", testEmptyFields);
	run("MultipleLines", testMultipleLines);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
