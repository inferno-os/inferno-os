implement TooldocTest;

#
# Tests for agentlib's tool-doc helpers (readtooldoc, tooldocsummary).
#
# Exercises against the live /lib/veltro/tools/*.txt files. These tests
# verify that the JSON-description path that lucibridge feeds to the
# LLM gives a useful summary rather than the previous fallback
# "Run the X tool with the given arguments".
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "agentlib.m";
	agentlib: AgentLib;

include "testing.m";
	testing: Testing;
	T: import testing;

TooldocTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/tooldoc_test.b";

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
	* =>
		t.failed = 1;
	}
	if(testing->done(t))
		passed++;
	else if(t.skipped)
		skipped++;
	else
		failed++;
}

contains(s, sub: string): int
{
	if(len sub == 0)
		return 1;
	if(len s < len sub)
		return 0;
	for(i := 0; i <= len s - len sub; i++)
		if(s[i:i+len sub] == sub)
			return 1;
	return 0;
}

testReadtooldoc(t: ref T)
{
	# Known-present file should return non-empty content.
	doc := agentlib->readtooldoc("shell");
	t.assert(len doc > 0, "shell.txt is readable");
	t.assert(contains(doc, "Read-only"), "shell.txt mentions Read-only");

	# Missing file should return empty string.
	missing := agentlib->readtooldoc("definitely-not-a-real-tool");
	t.assertseq(missing, "", "missing tool returns empty string");
}

testShellSummary(t: ref T)
{
	# This is the regression case. Pre-fix, the JSON description for
	# "shell" was "Run the shell tool with the given arguments" — no
	# disambiguating signal. After the fix, it must actually describe
	# the tool (read-only) and steer away from launching.
	s := agentlib->tooldocsummary("shell");
	t.assert(len s > 0, "shell summary is non-empty");
	t.assert(contains(s, "Read-only") || contains(s, "read-only"),
		"shell summary mentions read-only");
	t.assert(contains(s, "launch") || contains(s, "Launch"),
		"shell summary cross-references the launch tool");
}

testLaunchSummary(t: ref T)
{
	s := agentlib->tooldocsummary("launch");
	t.assert(len s > 0, "launch summary is non-empty");
	t.assert(contains(s, "GUI") || contains(s, "app"),
		"launch summary mentions GUI/app");
}

testHeaderStripping(t: ref T)
{
	# websearch.txt starts with "== websearch — Web Search ==" — that
	# header-style line must be skipped by the summary extractor in
	# favour of the substantive paragraph that follows.
	s := agentlib->tooldocsummary("websearch");
	t.assert(len s > 0, "websearch summary is non-empty");
	t.assert(s[0:2] != "==", "websearch summary does not start with == header");
	t.assert(contains(s, "Search") || contains(s, "search"),
		"websearch summary mentions search");
}

testMissingTool(t: ref T)
{
	s := agentlib->tooldocsummary("definitely-not-a-real-tool");
	t.assertseq(s, "", "missing tool yields empty summary");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	testing = load Testing Testing->PATH;
	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}

	agentlib = load AgentLib AgentLib->PATH;
	if(agentlib == nil) {
		sys->fprint(sys->fildes(2), "cannot load agentlib module: %r\n");
		raise "fail:cannot load agentlib";
	}
	agentlib->init();

	testing->init();

	for(a := args; a != nil; a = tl a)
		if(hd a == "-v")
			testing->verbose(1);

	run("Readtooldoc", testReadtooldoc);
	run("ShellSummary", testShellSummary);
	run("LaunchSummary", testLaunchSummary);
	run("HeaderStripping", testHeaderStripping);
	run("MissingTool", testMissingTool);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
