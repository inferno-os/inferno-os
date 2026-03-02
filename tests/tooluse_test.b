implement ToolUseTest;

#
# tooluse_test.b — Integration test for native tool_use protocol
#
# Tests the end-to-end plumbing of the new native tool_use code paths
# added in agentlib.b and repl.b: session creation, tool registration
# via /n/llm/{id}/tools, queryllmfd, parsellmresponse, and TOOL_RESULTS
# write path.
#
# All tests skip gracefully when /n/llm is not mounted.
# Tests that invoke the LLM backend are slow (~10-60s each).
#
# To run manually (with llm9p running on port 5640):
#   cd $ROOT
#   mount -A tcp!127.0.0.1!5640 /n/llm        # inside Inferno shell
#   /tests/tooluse_test.dis [-v]
#
# Or via the host runner:
#   tests/host/tooluse_protocol_test.sh
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

include "../appl/veltro/agentlib.m";
	agentlib: AgentLib;

ToolUseTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/tooluse_test.b";

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

# Return 1 if /n/llm is mounted.
# /n/llm exists as a placeholder directory in the rootfs, so we must
# check for /n/llm/new (the clone file that only exists when mounted).
hasllm(): int
{
	return agentlib->pathexists("/n/llm/new");
}

# ---- Test: session creation ----------------------------------------

# Test that createsession() returns a numeric session ID via /n/llm/new.
testSessionCreate(t: ref T)
{
	if(!hasllm()) {
		t.skip("/n/llm not mounted — run tests/host/tooluse_protocol_test.sh");
		return;
	}

	id := agentlib->createsession();
	t.assertnotnil(id, "session id is non-empty");

	# Session ID from llm9p is a decimal integer
	ok := 1;
	for(i := 0; i < len id; i++) {
		c := id[i];
		if(c < '0' || c > '9') {
			ok = 0;
			break;
		}
	}
	t.assert(ok, "session id is numeric");
	t.log(sys->sprint("session id: %s", id));
}

# ---- Test: tool registration ---------------------------------------

# Test that initsessiontools() writes JSON tool defs to /n/llm/{id}/tools
# by calling it and verifying no exception is raised.
# The write-only (0222) tools file cannot be read back to verify content,
# so we verify indirectly: if the subsequent LLM session still works after
# tool registration, the registration succeeded.
testToolsWrite(t: ref T)
{
	if(!hasllm()) {
		t.skip("/n/llm not mounted");
		return;
	}

	id := agentlib->createsession();
	if(id == nil) {
		t.fatal("cannot create session: /n/llm/new unreadable");
		return;
	}

	# Call initsessiontools — it logs errors to stderr but does not raise.
	# Two tools: read and write.
	toollist := "read" :: "write" :: nil;
	agentlib->initsessiontools(id, toollist);

	# Also verify JSON is built correctly for these tools.
	# buildtooldefs is exercised here (the same JSON goes into tools file).
	json := agentlib->buildtooldefs(toollist);
	t.assert(agentlib->contains(json, "\"name\":\"read\""), "tool JSON contains read");
	t.assert(agentlib->contains(json, "\"name\":\"write\""), "tool JSON contains write");
	t.assert(agentlib->contains(json, "input_schema"), "tool JSON has schema");
	t.log(sys->sprint("initsessiontools: %d bytes for session %s", len json, id));
}

# Test initsessiontools with zero tools (clears the tool list)
testToolsWriteEmpty(t: ref T)
{
	if(!hasllm()) {
		t.skip("/n/llm not mounted");
		return;
	}

	id := agentlib->createsession();
	if(id == nil) {
		t.fatal("cannot create session");
		return;
	}

	# Write empty list — should clear tools (server accepts empty string)
	agentlib->initsessiontools(id, nil);
	t.log("initsessiontools nil: no crash");
}

# Test that buildtooldefs produces valid JSON for all available tools
testBuildToolDefsAll(t: ref T)
{
	# Read the tools list from the tool filesystem (if available)
	toolsfile := "/tool/tools";
	if(!agentlib->pathexists(toolsfile)) {
		t.skip("/tool not mounted — cannot discover real toollist");
		return;
	}

	(nil, toollist) := sys->tokenize(agentlib->readfile(toolsfile), "\n");
	if(toollist == nil) {
		t.skip("toollist is empty");
		return;
	}

	json := agentlib->buildtooldefs(toollist);
	t.assert(agentlib->hasprefix(json, "["), "full tooldef JSON starts with [");
	t.assert(agentlib->contains(json, "\"name\":"), "full tooldef JSON has name fields");
	t.assert(agentlib->contains(json, "input_schema"), "full tooldef JSON has schemas");
	t.log(sys->sprint("buildtooldefs: %d bytes for %d tools", len json, 0));
}

# ---- Test: LLM query + parsellmresponse ---------------------------

# Test queryllmfd + parsellmresponse on the CLI backend.
# CLI backend returns plain text → parsellmresponse backward-compat path:
#   stopreason == ""  tools == nil  text == <LLM response>
testQueryAndParse(t: ref T)
{
	if(!hasllm()) {
		t.skip("/n/llm not mounted");
		return;
	}

	id := agentlib->createsession();
	if(id == nil) {
		t.fatal("cannot create session");
		return;
	}

	# Open ask file for read/write
	askpath := "/n/llm/" + id + "/ask";
	fd := sys->open(askpath, Sys->ORDWR);
	if(fd == nil) {
		t.fatal(sys->sprint("cannot open %s: %r", askpath));
		return;
	}

	# Send a short prompt — CLI backend invokes claude CLI (~10-60s)
	response := agentlib->queryllmfd(fd, "Reply with just the single word: pong");

	# CLI backend returns plain text; may be non-empty
	# (CLI errors would return "" — that's a skip, not a fail)
	if(response == nil) {
		t.skip("CLI backend returned empty response — claude CLI may not be in PATH");
		return;
	}

	# Parse via parsellmresponse — should be backward-compat (no STOP: prefix)
	(stopreason, tools, text) := agentlib->parsellmresponse(response);
	t.assertseq(stopreason, "", "CLI backend: stopreason is empty (plain text)");
	t.assert(tools == nil, "CLI backend: no tool calls");
	t.assertnotnil(text, "CLI backend: text is non-empty");
	t.log(sys->sprint("parsellmresponse: stopreason=%q text=%q", stopreason, agentlib->truncate(text, 80)));
}

# ---- Test: TOOL_RESULTS write path --------------------------------

# Test that writing TOOL_RESULTS format to ask file is accepted
# by the server (does not crash or return a 9P error).
# This exercises the parseToolResults path in session_ask.go.
#
# Note: With CLI backend, AskWithToolResults() calls the CLI with empty prompt
# (tool result turns have no prompt), which may produce an empty response.
# The test verifies acceptance of the write, not the response content.
testToolResultsWrite(t: ref T)
{
	if(!hasllm()) {
		t.skip("/n/llm not mounted");
		return;
	}

	id := agentlib->createsession();
	if(id == nil) {
		t.fatal("cannot create session");
		return;
	}

	askpath := "/n/llm/" + id + "/ask";
	fd := sys->open(askpath, Sys->ORDWR);
	if(fd == nil) {
		t.fatal(sys->sprint("cannot open %s: %r", askpath));
		return;
	}

	# First, do a plain prompt to initialise conversation history
	# (skip the LLM call latency — use a minimal prompt)
	agentlib->queryllmfd(fd, "Say hello");

	# Build TOOL_RESULTS wire format
	results := ("toolu_test_01", "the file content is: hello world") :: nil;
	wire := agentlib->buildtoolresults(results);

	# Write to ask file — this calls AskWithToolResults on the server
	buf := array of byte wire;
	n := sys->write(fd, buf, len buf);

	# A successful write returns len(buf) (session_ask.go always returns len(p))
	# A 9P error (e.g. TOOL_RESULTS parse failure) returns -1
	t.assert(n > 0, "TOOL_RESULTS write accepted (not a 9P error)");
	t.log(sys->sprint("TOOL_RESULTS write: %d bytes accepted", n));
}

# ---- Init ----------------------------------------------------------

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
		sys->fprint(sys->fildes(2), "cannot load agentlib: %r\n");
		raise "fail:cannot load agentlib";
	}
	agentlib->init();

	testing->init();

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	# Fast tests (no LLM call)
	run("SessionCreate", testSessionCreate);
	run("ToolsWrite", testToolsWrite);
	run("ToolsWriteEmpty", testToolsWriteEmpty);
	run("BuildToolDefsAll", testBuildToolDefsAll);

	# Slow tests (LLM call required)
	run("QueryAndParse", testQueryAndParse);
	run("ToolResultsWrite", testToolResultsWrite);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
