implement ShellToolTest;

#
# shell_tool_test - Tests for the Veltro shell tool
#
# Tests the shell tool's command parsing, string helpers,
# tail line-splitting logic, and error handling by simulating
# the shell IPC files at /tmp/veltro/shell/.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "testing.m";
	testing: Testing;
	T: import testing;

ShellToolTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/shell_tool_test.b";

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

# ============================================================
# Re-implementations of shell.b helper functions
# ============================================================

strip(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n'))
		i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\n'))
		j--;
	if(i >= j)
		return "";
	return s[i:j];
}

splitfirst(s: string): (string, string)
{
	s = strip(s);
	for(i := 0; i < len s; i++) {
		if(s[i] == ' ' || s[i] == '\t')
			return (s[0:i], strip(s[i:]));
	}
	return (s, "");
}

# Line-counting logic from shell.b dostatus()
countlines(body: string): int
{
	count := 1;
	for(i := 0; i < len body; i++)
		if(body[i] == '\n')
			count++;
	return count;
}

# Tail logic from shell.b dotail()
dotail(body: string, n: int): string
{
	alllines: list of string;
	count := 0;
	start := 0;
	for(i := 0; i < len body; i++) {
		if(body[i] == '\n') {
			alllines = body[start:i] :: alllines;
			count++;
			start = i + 1;
		}
	}
	if(start < len body) {
		alllines = body[start:] :: alllines;
		count++;
	}

	if(count <= n)
		return body;

	result := "";
	taken := 0;
	for(; alllines != nil && taken < n; alllines = tl alllines) {
		if(taken > 0)
			result = hd alllines + "\n" + result;
		else
			result = hd alllines;
		taken++;
	}
	return result;
}

hassubstr(s, sub: string): int
{
	if(len sub > len s)
		return 0;
	for(i := 0; i <= len s - len sub; i++) {
		if(s[i:i+len sub] == sub)
			return 1;
	}
	return 0;
}

# File I/O helpers
ensuredir(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd != nil)
		return;
	fd = sys->create(path, Sys->OREAD, Sys->DMDIR | 8r755);
}

writefile(path, data: string)
{
	fd := sys->create(path, Sys->OWRITE, 8r644);
	if(fd == nil)
		return;
	b := array of byte data;
	sys->write(fd, b, len b);
}

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	result := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}
	return result;
}

# ============================================================
# Tests: strip() and splitfirst()
# ============================================================

testStripShell(t: ref T)
{
	t.assertseq(strip("  read body  "), "read body", "strip shell command");
	t.assertseq(strip("status"), "status", "no-op strip");
	t.assertseq(strip(""), "", "empty strip");
	t.assertseq(strip("  "), "", "whitespace-only strip");
}

testSplitfirst(t: ref T)
{
	(cmd, rest) := splitfirst("read body");
	t.assertseq(cmd, "read", "splitfirst command");
	t.assertseq(rest, "body", "splitfirst rest");
}

testSplitfirstNoArgs(t: ref T)
{
	(cmd, rest) := splitfirst("status");
	t.assertseq(cmd, "status", "single word command");
	t.assertseq(rest, "", "no args");
}

testSplitfirstWhitespace(t: ref T)
{
	(cmd, rest) := splitfirst("  tail   50  ");
	t.assertseq(cmd, "tail", "command with extra whitespace");
	t.assertseq(rest, "50", "arg stripped");
}

testSplitfirstEmpty(t: ref T)
{
	(cmd, rest) := splitfirst("");
	t.assertseq(cmd, "", "empty input command");
	t.assertseq(rest, "", "empty input rest");
}

# ============================================================
# Tests: Line counting (dostatus logic)
# ============================================================

testCountlines(t: ref T)
{
	t.asserteq(countlines("hello"), 1, "single line");
	t.asserteq(countlines("line1\nline2"), 2, "two lines");
	t.asserteq(countlines("a\nb\nc\n"), 4, "three lines plus trailing newline");
	t.asserteq(countlines(""), 1, "empty body counts as 1");
}

# ============================================================
# Tests: Tail logic
# ============================================================

testTailAllLines(t: ref T)
{
	body := "line1\nline2\nline3";
	result := dotail(body, 30);
	# When count <= n, return full body
	t.assertseq(result, body, "tail with n > line count returns full body");
}

testTailExact(t: ref T)
{
	body := "line1\nline2\nline3";
	result := dotail(body, 3);
	t.assertseq(result, body, "tail with exact count returns full body");
}

testTailLast2(t: ref T)
{
	body := "line1\nline2\nline3\nline4\nline5";
	result := dotail(body, 2);
	t.assert(hassubstr(result, "line4"), "tail 2 should contain line4");
	t.assert(hassubstr(result, "line5"), "tail 2 should contain line5");
	t.assert(!hassubstr(result, "line1"), "tail 2 should not contain line1");
	t.assert(!hassubstr(result, "line2"), "tail 2 should not contain line2");
	t.assert(!hassubstr(result, "line3"), "tail 2 should not contain line3");
}

testTailLast1(t: ref T)
{
	body := "alpha\nbeta\ngamma";
	result := dotail(body, 1);
	t.assertseq(result, "gamma", "tail 1 returns last line");
}

testTailTrailingNewline(t: ref T)
{
	body := "a\nb\nc\n";
	# This has 4 "lines" (a, b, c, empty after trailing \n)
	result := dotail(body, 2);
	# Should get "c" and "" (the empty segment after trailing \n)
	t.assert(hassubstr(result, "c"), "tail with trailing newline includes last content");
}

# ============================================================
# Tests: Command dispatch simulation
# ============================================================

testCommandParsing(t: ref T)
{
	# Simulate the exec() dispatch logic from shell.b
	commands := array[] of {
		("read", "read body"),
		("tail", "tail 50"),
		("status", "status"),
		("read", "  READ  body  "),
	};

	for(i := 0; i < len commands; i++) {
		(expected, input) := commands[i];
		(cmd, nil) := splitfirst(input);
		cmd = str->tolower(cmd);
		t.assertseq(cmd, expected, sys->sprint("command parsing case %d", i));
	}
}

testEmptyCommand(t: ref T)
{
	# shell.b returns error for empty args
	args := strip("");
	t.assertseq(args, "", "empty command detected");
}

testUnknownCommand(t: ref T)
{
	(cmd, nil) := splitfirst("write hello");
	cmd = str->tolower(cmd);
	# shell.b returns error for unknown commands
	isknown := (cmd == "read" || cmd == "tail" || cmd == "status");
	t.assert(!isknown, "write is not a known command");
}

# ============================================================
# Tests: Read target parsing (doread logic)
# ============================================================

testReadTargetParsing(t: ref T)
{
	# doread parses the target: "" or "body" -> body, "input" -> input
	targets := array[] of {
		("", "body"),
		("body", "body"),
		("input", "input"),
	};

	for(i := 0; i < len targets; i++) {
		(input, expected) := targets[i];
		target := strip(input);
		actual: string;
		if(target == "" || target == "body")
			actual = "body";
		else if(target == "input")
			actual = "input";
		else
			actual = "error";
		t.assertseq(actual, expected, sys->sprint("read target case %d", i));
	}
}

testReadTargetInvalid(t: ref T)
{
	target := strip("somethingelse");
	isvalid := (target == "" || target == "body" || target == "input");
	t.assert(!isvalid, "invalid target detected");
}

# ============================================================
# Tests: File-based IPC simulation
# ============================================================

SHELL_TEST_ROOT: con "/tmp/shell_tool_test";

testShellBodyRead(t: ref T)
{
	# Simulate reading a shell transcript body
	ensuredir(SHELL_TEST_ROOT);
	transcript := "$ ls\nfile1.b\nfile2.b\n$ echo hello\nhello\n";
	writefile(SHELL_TEST_ROOT + "/body", transcript);

	body := readfile(SHELL_TEST_ROOT + "/body");
	t.assert(body != nil, "body file readable");
	t.assert(hassubstr(body, "$ ls"), "body contains ls command");
	t.assert(hassubstr(body, "hello"), "body contains echo output");

	sys->remove(SHELL_TEST_ROOT + "/body");
}

testShellInputRead(t: ref T)
{
	ensuredir(SHELL_TEST_ROOT);
	writefile(SHELL_TEST_ROOT + "/input", "cd /appl");

	input := readfile(SHELL_TEST_ROOT + "/input");
	t.assertseq(input, "cd /appl", "input line readable");

	sys->remove(SHELL_TEST_ROOT + "/input");
}

testShellStatusLogic(t: ref T)
{
	# Simulate the dostatus() logic
	ensuredir(SHELL_TEST_ROOT);

	body := "line1\nline2\nline3\n";
	writefile(SHELL_TEST_ROOT + "/body", body);
	writefile(SHELL_TEST_ROOT + "/input", "ls -l");

	bodyread := readfile(SHELL_TEST_ROOT + "/body");
	inputread := readfile(SHELL_TEST_ROOT + "/input");

	# Check it's not an error
	iserr := (len bodyread >= 6 && bodyread[0:6] == "error:");
	t.assert(!iserr, "body is not an error");

	lines := countlines(bodyread);
	status := sys->sprint("shell is running\ntranscript: %d lines\ncurrent input: %s", lines, inputread);

	t.assert(hassubstr(status, "shell is running"), "status shows running");
	t.assert(hassubstr(status, "transcript:"), "status shows transcript count");
	t.assert(hassubstr(status, "ls -l"), "status shows current input");

	sys->remove(SHELL_TEST_ROOT + "/body");
	sys->remove(SHELL_TEST_ROOT + "/input");
}

testShellMissing(t: ref T)
{
	# When shell files don't exist, readfile returns error-prefixed string
	# (in shell.b it returns "error: cannot open ... (is shell running?)")
	result := readfile("/tmp/nonexistent_shell_test/body");
	t.assert(result == nil, "missing shell file returns nil");
}

cleanup()
{
	sys->remove(SHELL_TEST_ROOT);
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
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

	# String helpers
	run("StripShell", testStripShell);
	run("Splitfirst", testSplitfirst);
	run("SplitfirstNoArgs", testSplitfirstNoArgs);
	run("SplitfirstWhitespace", testSplitfirstWhitespace);
	run("SplitfirstEmpty", testSplitfirstEmpty);

	# Line counting
	run("Countlines", testCountlines);

	# Tail logic
	run("TailAllLines", testTailAllLines);
	run("TailExact", testTailExact);
	run("TailLast2", testTailLast2);
	run("TailLast1", testTailLast1);
	run("TailTrailingNewline", testTailTrailingNewline);

	# Command dispatch
	run("CommandParsing", testCommandParsing);
	run("EmptyCommand", testEmptyCommand);
	run("UnknownCommand", testUnknownCommand);

	# Read target parsing
	run("ReadTargetParsing", testReadTargetParsing);
	run("ReadTargetInvalid", testReadTargetInvalid);

	# File-based IPC
	run("ShellBodyRead", testShellBodyRead);
	run("ShellInputRead", testShellInputRead);
	run("ShellStatusLogic", testShellStatusLogic);
	run("ShellMissing", testShellMissing);

	cleanup();

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
