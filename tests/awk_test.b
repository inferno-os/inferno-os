implement AwkTest;

#
# awk_test - Test the awk command
#
# Tests awk by loading it as a module and invoking init()
# with various programs and inputs.
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

AwkTest: module
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

SRCFILE: con "/tests/awk_test.b";

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
	path := sys->sprint("/tmp/awk_test_%s", suffix);
	fd := sys->create(path, Sys->OWRITE, 8r644);
	if(fd == nil)
		return nil;
	data := array of byte content;
	sys->write(fd, data, len data);
	return path;
}

# Helper: run awk command with given args and input, return stdout
runawk(args: list of string, input: string): string
{
	# Write input to temp file
	inpath := writetemp(input, "in");
	if(inpath == nil)
		return nil;

	# Build full args: awk <args> <inpath>
	rargs: list of string;
	for(a := args; a != nil; a = tl a)
		rargs = hd a :: rargs;
	rargs = inpath :: rargs;

	# Reverse
	fargs: list of string;
	for(; rargs != nil; rargs = tl rargs)
		fargs = hd rargs :: fargs;

	# Use pipe to capture output
	p := array[2] of ref Sys->FD;
	if(sys->pipe(p) < 0)
		return nil;

	done := chan of int;
	spawn runawkproc(fargs, p[1], done);

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
	sys->remove(inpath);

	if(total == 0)
		return "";
	return string outbuf[:total];
}

runawkproc(args: list of string, stdout: ref Sys->FD, done: chan of int)
{
	sys->dup(stdout.fd, 1);
	stdout = nil;

	{
		awk := load Cmd "/dis/awk.dis";
		if(awk != nil)
			awk->init(nil, "awk" :: args);
	} exception {
	"*" =>
		;
	}
	# Close the dup'd write end so the parent's read gets EOF
	sys->dup(sys->open("/dev/null", Sys->OWRITE).fd, 1);
	done <-= 1;
}

# Test basic print
testPrintAll(t: ref T)
{
	result := runawk("{print}" :: nil, "hello\nworld\n");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "hello\nworld\n", "print all lines");
}

# Test field extraction
testFieldExtract(t: ref T)
{
	result := runawk("{print $2}" :: nil, "one two three\nfour five six\n");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "two\nfive\n", "print field 2");
}

# Test custom field separator
testFieldSep(t: ref T)
{
	result := runawk("-F" :: ":" :: "{print $2}" :: nil, "a:b:c\nd:e:f\n");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "b\ne\n", "custom field separator");
}

# Test pattern matching
testPattern(t: ref T)
{
	result := runawk("/two/{print}" :: nil, "one\ntwo\nthree\n");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "two\n", "regex pattern match");
}

# Test BEGIN block
testBegin(t: ref T)
{
	result := runawk("BEGIN{print \"hello\"}" :: nil, "");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "hello\n", "BEGIN block");
}

# Test END block with NR
testEndNR(t: ref T)
{
	result := runawk("END{print NR}" :: nil, "a\nb\nc\n");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "3\n", "END block with NR");
}

# Test arithmetic
testArithmetic(t: ref T)
{
	result := runawk("{s+=$1} END{print s}" :: nil, "10\n20\n30\n");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "60\n", "sum of field 1");
}

# Test NF (number of fields)
testNF(t: ref T)
{
	result := runawk("{print NF}" :: nil, "a b c\nd e\nf\n");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "3\n2\n1\n", "NF counts fields");
}

# Test variable assignment with -v
testVarAssign(t: ref T)
{
	result := runawk("-v" :: "x=42" :: "{print x}" :: nil, "line\n");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "42\n", "-v variable assignment");
}

# Test if/else
testIfElse(t: ref T)
{
	result := runawk("{if($1>2) print \"big\"; else print \"small\"}" :: nil, "1\n3\n");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "small\nbig\n", "if/else control flow");
}

# Test for loop
testForLoop(t: ref T)
{
	result := runawk("BEGIN{for(i=1;i<=3;i++) print i}" :: nil, "");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "1\n2\n3\n", "for loop");
}

# Test string concatenation
testStringConcat(t: ref T)
{
	result := runawk("{print $1 \"-\" $2}" :: nil, "hello world\n");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "hello-world\n", "string concatenation");
}

# Test length function
testLength(t: ref T)
{
	result := runawk("{print length($0)}" :: nil, "hello\n");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "5\n", "length function");
}

# Test substr function
testSubstr(t: ref T)
{
	result := runawk("{print substr($0,2,3)}" :: nil, "abcdef\n");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "bcd\n", "substr function");
}

# Test index function
testIndex(t: ref T)
{
	result := runawk("{print index($0,\"cd\")}" :: nil, "abcdef\n");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "3\n", "index function");
}

# Test associative arrays
testArrays(t: ref T)
{
	input := "a 1\nb 2\na 3\nb 4\n";
	result := runawk("{s[$1]+=$2} END{print s[\"a\"], s[\"b\"]}" :: nil, input);
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "4 6\n", "associative arrays");
}

# Test printf
testPrintf(t: ref T)
{
	result := runawk("BEGIN{printf \"%d %s\\n\", 42, \"hello\"}" :: nil, "");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "42 hello\n", "printf formatting");
}

# Test OFS
testOFS(t: ref T)
{
	result := runawk("BEGIN{OFS=\",\"} {print $1,$2}" :: nil, "a b\n");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "a,b\n", "OFS output field separator");
}

# Test comparison expression as pattern
testComparisonPattern(t: ref T)
{
	result := runawk("$1 > 5" :: nil, "3\n7\n1\n9\n");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "7\n9\n", "comparison as pattern");
}

# Test user-defined function
testUserFunction(t: ref T)
{
	prog := "function double(x) { return x*2 } { print double($1) }";
	result := runawk(prog :: nil, "5\n10\n");
	if(result == nil) {
		t.skip("cannot run awk");
		return;
	}
	t.assertseq(result, "10\n20\n", "user-defined function");
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

	# Skip all tests if awk.dis is not available
	{
		awk := load Cmd "/dis/awk.dis";
		if(awk == nil) {
			sys->fprint(sys->fildes(2), "SKIP: awk.dis not found — skipping awk tests\n");
			return;
		}
	} exception {
	"*" =>
		sys->fprint(sys->fildes(2), "SKIP: awk.dis not loadable — skipping awk tests\n");
		return;
	}

	run("PrintAll", testPrintAll);
	run("FieldExtract", testFieldExtract);
	run("FieldSep", testFieldSep);
	run("Pattern", testPattern);
	run("Begin", testBegin);
	run("EndNR", testEndNR);
	run("Arithmetic", testArithmetic);
	run("NF", testNF);
	run("VarAssign", testVarAssign);
	run("IfElse", testIfElse);
	run("ForLoop", testForLoop);
	run("StringConcat", testStringConcat);
	run("Length", testLength);
	run("Substr", testSubstr);
	run("Index", testIndex);
	run("Arrays", testArrays);
	run("Printf", testPrintf);
	run("OFS", testOFS);
	run("ComparisonPattern", testComparisonPattern);
	run("UserFunction", testUserFunction);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
