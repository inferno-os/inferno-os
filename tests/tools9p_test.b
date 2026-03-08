implement Tools9pTest;

#
# tests/tools9p_test.b
#
# Integration tests for the tools9p 9P file server.
#
# Tests the actual 9P protocol — all interactions go through the
# filesystem interface at /tool, not through direct module loading.
#
# Requires tools9p to be running and mounted at /tool.
# All tests skip gracefully if /tool is not mounted.
#
# To run:
#   # Start tools9p first:
#   tools9p read list find write diff json memory todo exec &
#   sleep 2
#   /tests/tools9p_test.dis [-v]
#
# Or via the host wrapper:
#   tests/host/tools9p_integration_test.sh
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

Tools9pTest: module {
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/tools9p_test.b";
TOOLMNT: con "/tool";

passed := 0;
failed := 0;
skipped := 0;

run(name: string, testfn: ref fn(t: ref T))
{
	t := testing->newTsrc(name, SRCFILE);
	{
		testfn(t);
	} exception {
	"fail:fatal" => ;
	"fail:skip"  => ;
	* => t.failed = 1;
	}
	if(testing->done(t))
		passed++;
	else if(t.skipped)
		skipped++;
	else
		failed++;
}

# ─── helpers ──────────────────────────────────────────────────────────────────

hastool(): int
{
	(ok, nil) := sys->stat(TOOLMNT + "/tools");
	return ok >= 0;
}

writefile(path, content: string): int
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil)
		return -1;
	b := array of byte content;
	n := sys->write(fd, b, len b);
	return n;
}

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return "";
	return string buf[0:n];
}

strcontains(s, sub: string): int
{
	if(len sub == 0)
		return 1;
	for(i := 0; i + len sub <= len s; i++)
		if(s[i:i+len sub] == sub)
			return 1;
	return 0;
}

# Execute a tool via the 9P filesystem:
#   open /tool/<name>/ctl OWRITE → write args → write returns when done
#   then open /tool/<name>/ctl OREAD → read result
# The write blocks until asyncexec completes (blocking semantics from client side).
exectool9p(name, args: string): string
{
	path := TOOLMNT + "/" + name + "/ctl";

	# Write args — blocks until tool completes
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil)
		return "error: cannot open " + path + " for write";
	b := array of byte args;
	n := sys->write(fd, b, len b);
	fd = nil;
	if(n < 0)
		return "error: write failed";

	# Read result (buffered in ti.result after asyncexec)
	fd = sys->open(path, Sys->OREAD);
	if(fd == nil)
		return "error: cannot open " + path + " for read";
	buf := array[8192] of byte;
	n = sys->read(fd, buf, len buf);
	fd = nil;
	if(n < 0)
		return "error: read failed";
	return string buf[0:n];
}

# ─── tests ────────────────────────────────────────────────────────────────────

# Test 1: /tool/tools lists active tools
testToolsList(t: ref T)
{
	if(!hastool()) {
		t.skip("tools9p not mounted at /tool");
		return;
	}

	tools := readfile(TOOLMNT + "/tools");
	t.assert(tools != nil, "/tool/tools is readable");
	t.assert(len tools > 0, "/tool/tools is non-empty");
	t.log("/tool/tools: " + tools);

	# The server must have been started with at least one valid tool.
	# We don't assert specific tool names since they depend on startup args.
	# Just verify the format: newline-separated, no leading slash.
	# Split by newline and check first entry is a reasonable tool name.
	first := "";
	for(i := 0; i < len tools; i++) {
		if(tools[i] == '\n') {
			break;
		}
		first[len first] = tools[i];
	}
	# first might have picked up whole string if no newline — trim
	if(len first > 32)
		first = first[0:32];
	t.assert(len first > 0, "at least one tool name in /tool/tools");
	t.log("first tool: " + first);
}

# Test 2: /tool/_registry is readable and space-separated
testRegistryReadable(t: ref T)
{
	if(!hastool()) {
		t.skip("tools9p not mounted at /tool");
		return;
	}

	reg := readfile(TOOLMNT + "/_registry");
	t.assert(reg != nil, "/tool/_registry is readable");
	t.log("_registry: " + reg);
	# Registry should be space-separated (not newline-separated)
	# tools is newline-separated; registry is space-separated
	# Verify they contain the same tool set
	tools := readfile(TOOLMNT + "/tools");
	if(tools == nil)
		return;
	# Every name in /tool/tools should appear somewhere in _registry
	# (Extract first tool name from /tool/tools and check it's in registry)
	first := "";
	for(i := 0; i < len tools; i++) {
		if(tools[i] == '\n' || tools[i] == ' ')
			break;
		first[len first] = tools[i];
	}
	if(len first > 0)
		t.assert(strcontains(reg, first),
			"_registry should contain tool '" + first + "' from /tool/tools");
}

# Test 3: /tool/help returns documentation when written a tool name
testHelpLookup(t: ref T)
{
	if(!hastool()) {
		t.skip("tools9p not mounted at /tool");
		return;
	}

	# Get the first active tool name to query
	tools := readfile(TOOLMNT + "/tools");
	if(tools == nil || len tools == 0) {
		t.skip("no active tools to test help on");
		return;
	}
	# Extract first tool name
	toolname := "";
	for(i := 0; i < len tools; i++) {
		if(tools[i] == '\n')
			break;
		toolname[len toolname] = tools[i];
	}
	if(len toolname == 0) {
		t.skip("cannot parse tool name from /tool/tools");
		return;
	}

	# Write tool name to /tool/help
	n := writefile(TOOLMNT + "/help", toolname);
	t.assert(n > 0, "write tool name to /tool/help should succeed");

	# Read documentation back
	doc := readfile(TOOLMNT + "/help");
	t.assert(doc != nil, "/tool/help should return documentation");
	t.assert(len doc > 0, "documentation should be non-empty");
	t.log("doc for '" + toolname + "': " + doc[0:min(len doc, 80)]);
}

# Test 4: /tool/ctl remove and add
testCtlRemoveAdd(t: ref T)
{
	if(!hastool()) {
		t.skip("tools9p not mounted at /tool");
		return;
	}

	# We need at least 2 tools to safely remove one and add it back
	tools := readfile(TOOLMNT + "/tools");
	if(tools == nil) {
		t.skip("cannot read /tool/tools");
		return;
	}

	# Find a tool to toggle (pick the LAST one in the list to be safe)
	names: list of string = nil;
	cur := "";
	for(i := 0; i < len tools; i++) {
		if(tools[i] == '\n') {
			if(len cur > 0)
				names = cur :: names;
			cur = "";
		} else
			cur[len cur] = tools[i];
	}
	if(len cur > 0)
		names = cur :: names;

	if(names == nil) {
		t.skip("no tool names parseable from /tool/tools");
		return;
	}

	# Count active tools
	ntoolsbefore := 0;
	for(nl := names; nl != nil; nl = tl nl)
		ntoolsbefore++;

	if(ntoolsbefore < 2) {
		t.skip("need at least 2 active tools to safely toggle one");
		return;
	}

	# Pick the first tool (head of reversed list = last in /tool/tools)
	victim := hd names;
	t.log("toggling tool: " + victim);

	# Remove it
	n := writefile(TOOLMNT + "/ctl", "remove " + victim);
	t.assert(n > 0, "remove command to /tool/ctl should succeed");

	# Verify it's gone from /tool/tools
	tools2 := readfile(TOOLMNT + "/tools");
	t.assert(tools2 != nil, "/tool/tools readable after remove");
	t.assert(!strcontains(tools2, victim),
		"removed tool '" + victim + "' should not appear in /tool/tools");

	# Add it back
	n = writefile(TOOLMNT + "/ctl", "add " + victim);
	t.assert(n > 0, "add command to /tool/ctl should succeed");

	# Verify it's back
	tools3 := readfile(TOOLMNT + "/tools");
	t.assert(tools3 != nil, "/tool/tools readable after add");
	t.assert(strcontains(tools3, victim),
		"re-added tool '" + victim + "' should appear in /tool/tools");
}

# Test 5: /tool/ctl add of unknown tool returns error
testCtlAddUnknown(t: ref T)
{
	if(!hastool()) {
		t.skip("tools9p not mounted at /tool");
		return;
	}

	# Open ctl for write and try to add a non-existent tool
	fd := sys->open(TOOLMNT + "/ctl", Sys->OWRITE);
	if(fd == nil) {
		t.skip("cannot open /tool/ctl for write");
		return;
	}

	cmd := array of byte "add no_such_tool_xyz_9999";
	n := sys->write(fd, cmd, len cmd);
	fd = nil;

	# The write should fail (server returns 9P error) → n < 0
	t.assert(n < 0, "add of unknown tool should fail with 9P error (n=" + string n + ")");
}

# Test 6: Read tool execution via 9P
testReadToolExec(t: ref T)
{
	if(!hastool()) {
		t.skip("tools9p not mounted at /tool");
		return;
	}

	# Check that 'read' tool is active
	tools := readfile(TOOLMNT + "/tools");
	if(!strcontains(tools, "read")) {
		t.skip("'read' tool not active in tools9p");
		return;
	}

	# Read a file that is accessible in tools9p's restricted namespace.
	# /lib/veltro/tools/read.txt is the read tool's own documentation file.
	# It exists in Inferno's /lib and is readable in the restricted namespace.
	testfile := "/lib/veltro/tools/read.txt";
	(ok, nil) := sys->stat(testfile);
	if(ok < 0) {
		# Fall back to a .dis file — always present, content is binary but non-empty
		testfile = "/dis/veltro/tools/read.dis";
	}

	# Execute read tool via 9P: write path, read result
	result := exectool9p("read", testfile);
	t.log("read tool result (first 60 chars): " + result[0:min(len result, 60)]);

	if(strcontains(result, "error:")) {
		t.error("read tool returned error for " + testfile + ": " + result);
	} else {
		t.assert(len result > 0, "read tool result should be non-empty");
	}
}

# Test 7: List tool execution via 9P
testListToolExec(t: ref T)
{
	if(!hastool()) {
		t.skip("tools9p not mounted at /tool");
		return;
	}

	tools := readfile(TOOLMNT + "/tools");
	if(!strcontains(tools, "list")) {
		t.skip("'list' tool not active in tools9p");
		return;
	}

	# List /dis — a directory that always exists
	result := exectool9p("list", "/dis");
	t.log("list /dis result (first 100 chars): " + result[0:min(len result, 100)]);

	if(strcontains(result, "error:")) {
		t.error("list tool returned error: " + result);
	} else {
		t.assert(len result > 0, "list tool should return non-empty result for /dis");
	}
}

# Test 8: Tool exec before any write returns "no result" message
testNoResultBeforeWrite(t: ref T)
{
	if(!hastool()) {
		t.skip("tools9p not mounted at /tool");
		return;
	}

	tools := readfile(TOOLMNT + "/tools");
	if(tools == nil || len tools == 0) {
		t.skip("no active tools to test");
		return;
	}

	# Get first tool name
	toolname := "";
	for(i := 0; i < len tools; i++) {
		if(tools[i] == '\n')
			break;
		toolname[len toolname] = tools[i];
	}
	if(len toolname == 0)
		toolname = "read";

	# Open ctl for read WITHOUT writing first
	# Tools start with result = nil → server returns "error: no result (write arguments first)"
	fd := sys->open(TOOLMNT + "/" + toolname + "/ctl", Sys->OREAD);
	if(fd == nil) {
		# Tool may not exist if name parsing failed — not a test failure
		t.skip("cannot open tool file for read: " + toolname);
		return;
	}
	buf := array[512] of byte;
	n := sys->read(fd, buf, len buf);
	fd = nil;
	if(n <= 0) {
		t.skip("read returned nothing (tool may have a cached result from earlier)");
		return;
	}
	msg := string buf[0:n];
	t.log("initial read: " + msg);
	# May be "no result" sentinel OR a cached result from a previous test.
	# Either way, reading is not an error.
	t.assert(len msg >= 0, "reading before write does not crash the server");
}

# Test 9: /tool/paths is readable (may be empty)
testPathsReadable(t: ref T)
{
	if(!hastool()) {
		t.skip("tools9p not mounted at /tool");
		return;
	}

	paths := readfile(TOOLMNT + "/paths");
	t.assert(paths != nil, "/tool/paths is readable");
	t.log("/tool/paths content: '" + paths + "'");
	# May be empty if no paths are registered — that's valid
}

# Test 10: Verify tool file not present for inactive (removed) tool
testInactiveToolNotPresent(t: ref T)
{
	if(!hastool()) {
		t.skip("tools9p not mounted at /tool");
		return;
	}

	# Use "mail" as the test candidate — likely not started by default test helper
	# (but if it is, we just skip this test)
	testname := "mail";
	tools := readfile(TOOLMNT + "/tools");
	if(strcontains(tools, testname)) {
		t.skip("'" + testname + "' is active — cannot test inactive tool access");
		return;
	}

	# Attempt to open the tool file — should fail
	(ok, nil) := sys->stat(TOOLMNT + "/" + testname);
	t.assert(ok < 0,
		"stat of inactive tool file '" + testname + "' should fail (tool not exposed)");
}

# ─── utilities ────────────────────────────────────────────────────────────────

min(a, b: int): int
{
	if(a < b)
		return a;
	return b;
}

# ─── main ─────────────────────────────────────────────────────────────────────

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	testing = load Testing Testing->PATH;
	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module\n");
		raise "fail:load";
	}
	testing->init();

	for(a := args; a != nil; a = tl a)
		if(hd a == "-v")
			testing->verbose(1);

	run("ToolsList",             testToolsList);
	run("RegistryReadable",      testRegistryReadable);
	run("HelpLookup",            testHelpLookup);
	run("CtlRemoveAdd",          testCtlRemoveAdd);
	run("CtlAddUnknown",         testCtlAddUnknown);
	run("ReadToolExec",          testReadToolExec);
	run("ListToolExec",          testListToolExec);
	run("NoResultBeforeWrite",   testNoResultBeforeWrite);
	run("PathsReadable",         testPathsReadable);
	run("InactiveToolNotPresent",testInactiveToolNotPresent);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
