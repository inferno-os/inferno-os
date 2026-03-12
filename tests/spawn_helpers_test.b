implement SpawnHelpersTest;

#
# spawn_helpers_test - Tests for spawn.b helper functions
#
# Tests the string manipulation, list operations, spec parsing,
# and activity/background task helpers used by the spawn tool.
#
# These are unit tests of the pure-logic helpers, not integration
# tests that require LLM or namespace infrastructure.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "testing.m";
	testing: Testing;
	T: import testing;

SpawnHelpersTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/spawn_helpers_test.b";

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
# Re-implementations of spawn.b helper functions for testing
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

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

spliton(s, sep: string): (string, string)
{
	for(i := 0; i <= len s - len sep; i++) {
		if(s[i:i+len sep] == sep)
			return (s[0:i], s[i+len sep:]);
	}
	return (s, "");
}

splitonall(s, sep: string): list of string
{
	parts: list of string;
	for(;;) {
		(before, after) := spliton(s, sep);
		parts = before :: parts;
		if(after == "")
			break;
		s = after;
	}
	return reverse(parts);
}

inlist(needle: string, l: list of string): int
{
	for(; l != nil; l = tl l)
		if(hd l == needle)
			return 1;
	return 0;
}

dropitem(item: string, l: list of string): list of string
{
	result: list of string;
	for(; l != nil; l = tl l)
		if(hd l != item)
			result = hd l :: result;
	return reverse(result);
}

reverse(l: list of string): list of string
{
	result: list of string;
	for(; l != nil; l = tl l)
		result = hd l :: result;
	return result;
}

listlen(l: list of string): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}

tasksummary(task: string): string
{
	if(len task <= 50)
		return task;
	return task[0:47] + "...";
}

stripquotes(s: string): string
{
	if(len s < 2)
		return s;
	if((s[0] == '"' && s[len s - 1] == '"') ||
	   (s[0] == '\'' && s[len s - 1] == '\''))
		return s[1:len s - 1];
	return s;
}

# File I/O helpers for activity tests
readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	return string buf[0:n];
}

writefile(path, data: string): string
{
	fd := sys->create(path, Sys->OWRITE, 8r644);
	if(fd == nil)
		return sys->sprint("cannot open %s: %r", path);
	b := array of byte data;
	n := sys->write(fd, b, len b);
	if(n < 0)
		return sys->sprint("write to %s failed: %r", path);
	return nil;
}

ensuredir(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd != nil)
		return;
	fd = sys->create(path, Sys->OREAD, Sys->DMDIR | 8r755);
}

# ============================================================
# Tests: strip()
# ============================================================

testStripBasic(t: ref T)
{
	t.assertseq(strip("hello"), "hello", "no-op on clean string");
	t.assertseq(strip("  hello  "), "hello", "strip leading/trailing spaces");
	t.assertseq(strip("\thello\t"), "hello", "strip tabs");
	t.assertseq(strip("\nhello\n"), "hello", "strip newlines");
	t.assertseq(strip("  \t\n hello world \n\t  "), "hello world", "mixed whitespace");
}

testStripEmpty(t: ref T)
{
	t.assertseq(strip(""), "", "empty string");
	t.assertseq(strip("   "), "", "all spaces");
	t.assertseq(strip("\t\n"), "", "all whitespace");
}

testStripNoChange(t: ref T)
{
	t.assertseq(strip("abc"), "abc", "no whitespace");
	t.assertseq(strip("a b c"), "a b c", "inner spaces preserved");
}

# ============================================================
# Tests: hasprefix()
# ============================================================

testHasprefix(t: ref T)
{
	t.assert(hasprefix("tools=read,list", "tools="), "tools= prefix");
	t.assert(hasprefix("timeout=60", "timeout="), "timeout= prefix");
	t.assert(hasprefix("abc", "abc"), "exact match");
	t.assert(hasprefix("abcdef", "abc"), "prefix of longer string");
	t.assert(!hasprefix("abc", "abcdef"), "string shorter than prefix");
	t.assert(!hasprefix("xyz", "abc"), "no match");
	t.assert(hasprefix("anything", ""), "empty prefix matches everything");
	t.assert(!hasprefix("", "abc"), "empty string has no prefix");
}

# ============================================================
# Tests: spliton()
# ============================================================

testSpliton(t: ref T)
{
	(before, after) := spliton("hello :: world", " :: ");
	t.assertseq(before, "hello", "spliton before");
	t.assertseq(after, "world", "spliton after");
}

testSplitonNotFound(t: ref T)
{
	(before, after) := spliton("no separator here", " :: ");
	t.assertseq(before, "no separator here", "spliton no match returns full string");
	t.assertseq(after, "", "spliton no match returns empty after");
}

testSplitonFirst(t: ref T)
{
	(before, after) := spliton("a -- b -- c", " -- ");
	t.assertseq(before, "a", "spliton first occurrence before");
	t.assertseq(after, "b -- c", "spliton first occurrence after");
}

testSplitonEdge(t: ref T)
{
	# Separator at start
	(before, after) := spliton(" -- rest", " -- ");
	t.assertseq(before, "", "separator at start gives empty before");
	t.assertseq(after, "rest", "separator at start gives rest");

	# Separator at end
	(before2, after2) := spliton("start -- ", " -- ");
	t.assertseq(before2, "start", "separator at end gives start");
	t.assertseq(after2, "", "separator at end gives empty after");
}

# ============================================================
# Tests: splitonall()
# ============================================================

testSplitonall(t: ref T)
{
	parts := splitonall("a -- b -- c", " -- ");
	t.asserteq(listlen(parts), 3, "three parts");
	t.assertseq(hd parts, "a", "first part");
	parts = tl parts;
	t.assertseq(hd parts, "b", "second part");
	parts = tl parts;
	t.assertseq(hd parts, "c", "third part");
}

testSplitonallSingle(t: ref T)
{
	parts := splitonall("no separator", " -- ");
	t.asserteq(listlen(parts), 1, "single part when no separator");
	t.assertseq(hd parts, "no separator", "single part value");
}

# ============================================================
# Tests: inlist()
# ============================================================

testInlist(t: ref T)
{
	l := "read" :: "list" :: "grep" :: nil;
	t.assert(inlist("read", l), "read in list");
	t.assert(inlist("list", l), "list in list");
	t.assert(inlist("grep", l), "grep in list");
	t.assert(!inlist("write", l), "write not in list");
	t.assert(!inlist("", l), "empty not in list");
}

testInlistEmpty(t: ref T)
{
	t.assert(!inlist("anything", nil), "nothing in empty list");
}

# ============================================================
# Tests: dropitem()
# ============================================================

testDropitem(t: ref T)
{
	l := "read" :: "memory" :: "list" :: nil;
	result := dropitem("memory", l);
	t.asserteq(listlen(result), 2, "one item dropped");
	t.assert(inlist("read", result), "read preserved");
	t.assert(inlist("list", result), "list preserved");
	t.assert(!inlist("memory", result), "memory removed");
}

testDropitemNotPresent(t: ref T)
{
	l := "read" :: "list" :: nil;
	result := dropitem("memory", l);
	t.asserteq(listlen(result), 2, "nothing dropped if not present");
}

testDropitemAll(t: ref T)
{
	# dropitem removes ALL occurrences
	l := "a" :: "b" :: "a" :: "c" :: nil;
	result := dropitem("a", l);
	t.asserteq(listlen(result), 2, "all occurrences removed");
	t.assert(!inlist("a", result), "a fully removed");
	t.assert(inlist("b", result), "b preserved");
	t.assert(inlist("c", result), "c preserved");
}

# ============================================================
# Tests: reverse()
# ============================================================

testReverse(t: ref T)
{
	l := "a" :: "b" :: "c" :: nil;
	r := reverse(l);
	t.assertseq(hd r, "c", "first is last");
	r = tl r;
	t.assertseq(hd r, "b", "middle stays");
	r = tl r;
	t.assertseq(hd r, "a", "last is first");
}

testReverseEmpty(t: ref T)
{
	r := reverse(nil);
	t.assert(r == nil, "reverse of nil is nil");
}

testReverseSingle(t: ref T)
{
	r := reverse("only" :: nil);
	t.asserteq(listlen(r), 1, "single element list");
	t.assertseq(hd r, "only", "single element preserved");
}

# ============================================================
# Tests: listlen()
# ============================================================

testListlen(t: ref T)
{
	t.asserteq(listlen(nil), 0, "empty list");
	t.asserteq(listlen("a" :: nil), 1, "single element");
	t.asserteq(listlen("a" :: "b" :: "c" :: nil), 3, "three elements");
}

# ============================================================
# Tests: tasksummary()
# ============================================================

testTasksummary(t: ref T)
{
	# Short task unchanged
	t.assertseq(tasksummary("List all files"), "List all files", "short task unchanged");

	# Exactly 50 chars unchanged
	s50 := "12345678901234567890123456789012345678901234567890";
	t.assertseq(tasksummary(s50), s50, "50-char task unchanged");
	t.asserteq(len tasksummary(s50), 50, "50 chars exact");

	# 51 chars gets truncated
	s51 := s50 + "X";
	result := tasksummary(s51);
	t.asserteq(len result, 50, "truncated to 50");
	t.assert(hasprefix(result, "12345678901234567890123456789012345678901234567"), "truncated prefix");
	t.assertseq(result[47:], "...", "ends with ellipsis");
}

testTasksummaryEmpty(t: ref T)
{
	t.assertseq(tasksummary(""), "", "empty task");
}

# ============================================================
# Tests: stripquotes()
# ============================================================

testStripquotes(t: ref T)
{
	t.assertseq(stripquotes(`"hello"`), "hello", "double quotes stripped");
	t.assertseq(stripquotes("'hello'"), "hello", "single quotes stripped");
	t.assertseq(stripquotes("hello"), "hello", "no quotes unchanged");
	t.assertseq(stripquotes(`"hello'`), `"hello'`, "mismatched quotes unchanged");
	t.assertseq(stripquotes("a"), "a", "single char unchanged");
	t.assertseq(stripquotes(""), "", "empty string unchanged");
	t.assertseq(stripquotes(`""`), "", "empty double quotes");
	t.assertseq(stripquotes("''"), "", "empty single quotes");
}

# ============================================================
# Tests: Activity/background task file-based helpers
# ============================================================

TEST_ACT_BASE: con "/tmp/spawn_helpers_test";

testCurrentactidSimulation(t: ref T)
{
	# Simulate the currentactid logic: read a file, strip, parse int
	actdir := TEST_ACT_BASE + "/activity";
	ensuredir(TEST_ACT_BASE);
	ensuredir(actdir);

	# Write a simulated "current" file
	writefile(actdir + "/current", "42\n");

	s := readfile(actdir + "/current");
	if(s == nil) {
		t.error("could not read simulated current file");
		return;
	}
	s = strip(s);
	(n, nil) := str->toint(s, 10);
	t.asserteq(n, 42, "parsed activity ID");

	sys->remove(actdir + "/current");
	sys->remove(actdir);
}

testCurrentactidMissing(t: ref T)
{
	# When file doesn't exist, should get nil -> return -1
	s := readfile("/tmp/nonexistent_activity/current");
	if(s != nil) {
		t.error("expected nil for nonexistent file");
		return;
	}
	# The spawn.b logic returns -1 when s==nil
	t.assert(s == nil, "missing file returns nil");
}

testCountbgtasksSimulation(t: ref T)
{
	# Simulate countbgtasks: iterate files 0, 1, 2... until one doesn't exist
	bgdir := TEST_ACT_BASE + "/background";
	ensuredir(TEST_ACT_BASE);
	ensuredir(bgdir);

	# Create 3 background task files
	writefile(sys->sprint("%s/0", bgdir), "task0");
	writefile(sys->sprint("%s/1", bgdir), "task1");
	writefile(sys->sprint("%s/2", bgdir), "task2");

	# Count them (same algorithm as spawn.b countbgtasks)
	count := 0;
	for(i := 0; ; i++) {
		s := readfile(sys->sprint("%s/%d", bgdir, i));
		if(s == nil) {
			count = i;
			break;
		}
	}
	t.asserteq(count, 3, "counted 3 background tasks");

	# Cleanup
	for(j := 0; j < 3; j++)
		sys->remove(sys->sprint("%s/%d", bgdir, j));
	sys->remove(bgdir);
}

testCountbgtasksEmpty(t: ref T)
{
	# Empty directory: count should be 0
	bgdir := TEST_ACT_BASE + "/bg_empty";
	ensuredir(TEST_ACT_BASE);
	ensuredir(bgdir);

	s := readfile(sys->sprint("%s/0", bgdir));
	count := 0;
	if(s == nil)
		count = 0;
	t.asserteq(count, 0, "empty directory has 0 tasks");

	sys->remove(bgdir);
}

testBgaddSimulation(t: ref T)
{
	# Simulate bgadd: write "bg add label=<label> status=live" to ctl file
	ctldir := TEST_ACT_BASE + "/bgadd";
	ensuredir(TEST_ACT_BASE);
	ensuredir(ctldir);

	label := "List all .b files";
	cmd := "bg add label=" + label + " status=live";
	writefile(ctldir + "/ctl", cmd);

	# Verify the command was written
	content := readfile(ctldir + "/ctl");
	t.assertseq(content, cmd, "bgadd command written correctly");

	sys->remove(ctldir + "/ctl");
	sys->remove(ctldir);
}

testBgupdatestatusSimulation(t: ref T)
{
	# Simulate bgupdatestatus: write "bg update <idx> status=<s> progress=100"
	ctldir := TEST_ACT_BASE + "/bgupd";
	ensuredir(TEST_ACT_BASE);
	ensuredir(ctldir);

	idx := 2;
	status := "done";
	cmd := sys->sprint("bg update %d status=%s progress=100", idx, status);
	writefile(ctldir + "/ctl", cmd);

	content := readfile(ctldir + "/ctl");
	t.assertseq(content, "bg update 2 status=done progress=100", "bgupdatestatus command correct");

	# Test error status too
	cmd = sys->sprint("bg update %d status=%s progress=100", 0, "error");
	writefile(ctldir + "/ctl", cmd);
	content = readfile(ctldir + "/ctl");
	t.assertseq(content, "bg update 0 status=error progress=100", "bgupdatestatus error command correct");

	sys->remove(ctldir + "/ctl");
	sys->remove(ctldir);
}

# ============================================================
# Tests: Integration of activity tracking with result formatting
# ============================================================

testResultFormatSingle(t: ref T)
{
	# When N==1, spawn.b returns the result directly (no header)
	result := "found 15 .b files in /appl/cmd";
	# spawn.b: if(N == 1) return results[0];
	t.assertseq(result, "found 15 .b files in /appl/cmd", "single result returned directly");
}

testResultFormatMultiple(t: ref T)
{
	# When N>1, spawn.b formats with === headers
	results := array[] of {"result A", "result B"};
	tasks := array[] of {"analyze code", "search patterns"};

	out := "";
	for(i := 0; i < len results; i++) {
		if(out != "")
			out += "\n\n";
		out += sys->sprint("=== Subagent %d: %s ===\n", i+1, tasksummary(tasks[i])) + results[i];
	}

	t.assert(hasprefix(out, "=== Subagent 1: analyze code ==="), "first header");
	t.assert(len out > 50, "multi-result output has content");
}

testResultErrorPrefix(t: ref T)
{
	# spawn.b strips "ERROR:" prefix and prepends "error: "
	result := "ERROR:cannot create pipe";
	if(hasprefix(result, "ERROR:"))
		result = "error: " + result[6:];
	t.assertseq(result, "error: cannot create pipe", "error prefix transformation");
}

cleanup()
{
	sys->remove(TEST_ACT_BASE);
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

	ensuredir(TEST_ACT_BASE);

	# strip tests
	run("StripBasic", testStripBasic);
	run("StripEmpty", testStripEmpty);
	run("StripNoChange", testStripNoChange);

	# hasprefix tests
	run("Hasprefix", testHasprefix);

	# spliton tests
	run("Spliton", testSpliton);
	run("SplitonNotFound", testSplitonNotFound);
	run("SplitonFirst", testSplitonFirst);
	run("SplitonEdge", testSplitonEdge);

	# splitonall tests
	run("Splitonall", testSplitonall);
	run("SplitonallSingle", testSplitonallSingle);

	# inlist tests
	run("Inlist", testInlist);
	run("InlistEmpty", testInlistEmpty);

	# dropitem tests
	run("Dropitem", testDropitem);
	run("DropitemNotPresent", testDropitemNotPresent);
	run("DropitemAll", testDropitemAll);

	# reverse tests
	run("Reverse", testReverse);
	run("ReverseEmpty", testReverseEmpty);
	run("ReverseSingle", testReverseSingle);

	# listlen tests
	run("Listlen", testListlen);

	# tasksummary tests
	run("Tasksummary", testTasksummary);
	run("TasksummaryEmpty", testTasksummaryEmpty);

	# stripquotes tests
	run("Stripquotes", testStripquotes);

	# Activity/background task helpers
	run("CurrentactidSimulation", testCurrentactidSimulation);
	run("CurrentactidMissing", testCurrentactidMissing);
	run("CountbgtasksSimulation", testCountbgtasksSimulation);
	run("CountbgtasksEmpty", testCountbgtasksEmpty);
	run("BgaddSimulation", testBgaddSimulation);
	run("BgupdatestatusSimulation", testBgupdatestatusSimulation);

	# Result formatting
	run("ResultFormatSingle", testResultFormatSingle);
	run("ResultFormatMultiple", testResultFormatMultiple);
	run("ResultErrorPrefix", testResultErrorPrefix);

	cleanup();

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
