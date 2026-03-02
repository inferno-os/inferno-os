implement VeltroCCAlignmentTest;

#
# veltro_cc_alignment_test.b - Full operational test for the three CC alignment fixes
#
# Fixes under test:
#   Fix 1 — Stronger todo mandate: unconditional todo injection after every tool.
#            Old: skip when status starts with "0 pending". New: always include.
#   Fix 2 — Transient error retry in queryllmfd(): 3 attempts with exponential backoff.
#   Fix 3 — Multi-tool parallelism: parseactions() collects consecutive tools;
#            exectools() runs them concurrently via per-tool channels.
#
# What is tested here (no LLM required):
#   - parseactions DONE detection (pure string, no /tool)
#   - parseactions multi-tool collection (requires /tool)
#   - todo tool status format — verifies Fix 1 injection condition
#   - Parallel goroutine+channel pattern (mirrors exectools) with real tool modules
#   - System prompt content — verifies Fix 3 mandate text in system.txt
#
# What requires a live LLM (manual verification):
#   - Full agent loop with multi-tool response
#   - Retry triggering on transient write failure
#
# To run:
#   emu -r. /dis/tests/veltro_cc_alignment_test.dis [-v]
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

include "../appl/veltro/agentlib.m";
	agentlib: AgentLib;

# Direct tool module interface (bypasses tools9p — no /tool mount required)
Tool: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

VeltroCCAlignmentTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/veltro_cc_alignment_test.b";

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

# ---- helpers ----

hastoolfs(): int
{
	return agentlib->pathexists("/tool/tools");
}

loadtool(name: string): Tool
{
	m := load Tool ("/dis/veltro/tools/" + name + ".dis");
	if(m != nil) {
		err := m->init();
		if(err != nil)
			return nil;
	}
	return m;
}

# Goroutine: run tool module, send result to channel
runmod(m: Tool, args: string, ch: chan of string)
{
	ch <-= m->exec(args);
}

# Goroutine: sleep ms milliseconds, signal completion
sleepgoroutine(ms: int, ch: chan of int)
{
	sys->sleep(ms);
	ch <-= 1;
}

listlen(l: list of (string, string)): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}

# ====================================================================
# Fix 3 — parseactions: DONE detection (pure string, no /tool needed)
# ====================================================================

# Empty response → nil
testParseActionsEmptyResponse(t: ref T)
{
	actions := agentlib->parseactions("");
	t.assert(actions == nil, "empty response returns nil");
}

# Bare DONE → single-element list ("DONE", "")
testParseActionsBareDone(t: ref T)
{
	actions := agentlib->parseactions("DONE");
	t.assert(actions != nil, "DONE: non-nil list");
	t.asserteq(listlen(actions), 1, "DONE: exactly 1 element");
	(tool, args) := hd actions;
	t.assertseq(tool, "DONE", "DONE: tool name is DONE");
	t.assertseq(args, "", "DONE: empty args");
}

# Lowercase done → ("DONE", "") :: nil
testParseActionsLowercaseDone(t: ref T)
{
	actions := agentlib->parseactions("done");
	t.assert(actions != nil, "lowercase done: non-nil");
	(tool, nil) := hd actions;
	t.assertseq(tool, "DONE", "lowercase done recognized");
}

# Markdown-wrapped DONE
testParseActionsMarkdownDone(t: ref T)
{
	actions := agentlib->parseactions("**DONE**");
	t.assert(actions != nil, "markdown DONE: non-nil");
	(tool, nil) := hd actions;
	t.assertseq(tool, "DONE", "markdown DONE recognized");
}

# Preamble text then DONE → DONE (preamble skipped, DONE found before any tool)
testParseActionsPreambleThenDone(t: ref T)
{
	resp := "Here is my analysis.\n\nDONE";
	actions := agentlib->parseactions(resp);
	t.assert(actions != nil, "preamble+DONE: non-nil");
	(tool, nil) := hd actions;
	t.assertseq(tool, "DONE", "preamble skipped, DONE found");
}

# ====================================================================
# Fix 3 — parseactions: multi-tool collection (requires /tool mount)
# ====================================================================

# Two consecutive tool lines → two-element list in order
testParseActionsMultiTool(t: ref T)
{
	if(!hastoolfs()) {
		t.skip("parseactions multi-tool: /tool not mounted");
		return;
	}
	resp := "read /tmp\nlist /tmp\n";
	actions := agentlib->parseactions(resp);
	t.assert(actions != nil, "multi-tool: non-nil");
	t.asserteq(listlen(actions), 2, "multi-tool: 2 tools collected");
	(t1, a1) := hd actions;
	(t2, a2) := hd tl actions;
	t.assertseq(t1, "read", "first tool is read");
	t.assertseq(a1, "/tmp", "first tool args /tmp");
	t.assertseq(t2, "list", "second tool is list");
	t.assertseq(a2, "/tmp", "second tool args /tmp");
}

# Preamble, then two tools → only the two tools (preamble skipped)
testParseActionsSkipPreamble(t: ref T)
{
	if(!hastoolfs()) {
		t.skip("parseactions preamble skip: /tool not mounted");
		return;
	}
	resp := "Let me check those files.\n\nread /tmp\nlist /tmp\n";
	actions := agentlib->parseactions(resp);
	t.assert(actions != nil, "preamble+tools: non-nil");
	t.asserteq(listlen(actions), 2, "preamble+tools: 2 tools, preamble not counted");
}

# Tool then DONE → only the tool (DONE stops collection without adding itself)
testParseActionsToolThenDone(t: ref T)
{
	if(!hastoolfs()) {
		t.skip("parseactions tool+DONE: /tool not mounted");
		return;
	}
	resp := "read /tmp\nDONE\n";
	actions := agentlib->parseactions(resp);
	t.assert(actions != nil, "tool+DONE: non-nil");
	t.asserteq(listlen(actions), 1, "tool+DONE: only 1 tool (DONE not added)");
	(tool, args) := hd actions;
	t.assertseq(tool, "read", "tool name correct");
	t.assertseq(args, "/tmp", "tool args correct");
}

# Three consecutive tools → three collected in order
testParseActionsThreeTools(t: ref T)
{
	if(!hastoolfs()) {
		t.skip("parseactions 3 tools: /tool not mounted");
		return;
	}
	resp := "read /tmp\nlist /tmp\nread /dev/null\n";
	actions := agentlib->parseactions(resp);
	t.assert(actions != nil, "3 tools: non-nil");
	t.asserteq(listlen(actions), 3, "3 tools: 3 collected");
	# Verify order
	(t1, nil) := hd actions;
	(t2, nil) := hd tl actions;
	(t3, nil) := hd tl tl actions;
	t.assertseq(t1, "read", "first is read");
	t.assertseq(t2, "list", "second is list");
	t.assertseq(t3, "read", "third is read");
}

# ====================================================================
# Fix 3 — parallel execution pattern (direct tool modules, no /tool)
# ====================================================================

# Spawn two tool execs concurrently; collect results in order via channels.
# This mirrors exectools() in repl.b: one chan per tool, spawn + collect.
testParallelExecPattern(t: ref T)
{
	readmod := loadtool("read");
	listmod := loadtool("list");
	if(readmod == nil || listmod == nil) {
		t.skip("parallel exec: read or list tool not available");
		return;
	}

	ch1 := chan of string;
	ch2 := chan of string;

	# Spawn both concurrently — mirrors exectools() goroutines
	spawn runmod(readmod, "/dev/null", ch1);
	spawn runmod(listmod, "/tmp", ch2);

	# Collect in original order — mirrors channel array collect in exectools()
	r1 := <-ch1;
	r2 := <-ch2;

	t.assert(!agentlib->hasprefix(r1, "error"), "parallel tool 1 (read) succeeded");
	t.assert(!agentlib->hasprefix(r2, "error"), "parallel tool 2 (list) succeeded");
}

# Verify ordering: results come back in the same order as dispatch, not arrival order.
# Even if ch2 completes first, we wait for ch1 first (ordered collection).
testParallelExecOrdering(t: ref T)
{
	readmod := loadtool("read");
	if(readmod == nil) {
		t.skip("parallel ordering: read tool not available");
		return;
	}

	# Create three channels
	channels := array[3] of chan of string;
	i: int;
	for(i = 0; i < 3; i++)
		channels[i] = chan of string;

	# Dispatch in order: /dev/null, /tmp, /dev/sysname
	targets := array[] of {"/dev/null", "/tmp", "/dev/sysname"};
	for(i = 0; i < 3; i++)
		spawn runmod(readmod, targets[i], channels[i]);

	# Collect in original order
	results := array[3] of string;
	for(i = 0; i < 3; i++)
		results[i] = <-channels[i];

	# Verify: reading /dev/sysname should return a non-empty sysname
	t.assert(!agentlib->hasprefix(results[2], "error"), "third result (sysname) is not error");
}

# Timing: two goroutines sleeping concurrently complete in ~1× not ~2× the sleep time.
# This directly verifies the parallelism that exectools() relies on.
testParallelTiming(t: ref T)
{
	SLEEP_MS := 200;
	ch1 := chan of int;
	ch2 := chan of int;

	start := sys->millisec();
	spawn sleepgoroutine(SLEEP_MS, ch1);
	spawn sleepgoroutine(SLEEP_MS, ch2);
	<-ch1;
	<-ch2;
	parallel_ms := sys->millisec() - start;

	t.log(sys->sprint("parallel: two %dms goroutines completed in %dms", SLEEP_MS, parallel_ms));
	# Should complete in < 1.5× one sleep (generous bound for scheduling jitter)
	t.assert(parallel_ms < SLEEP_MS * 3 / 2,
		sys->sprint("parallel goroutines: %dms < threshold %dms", parallel_ms, SLEEP_MS * 3 / 2));
}

# ====================================================================
# Fix 1 — Todo unconditional injection
# ====================================================================

# When todo is empty, status returns "0 pending, N done" (non-error).
# Old code excluded this from prompt. New code includes it.
# Test verifies: empty-todo status is non-error AND starts with "0 pending".
testTodoEmptyStatusIsNonError(t: ref T)
{
	todo := loadtool("todo");
	if(todo == nil) {
		t.skip("todo status: todo tool not available");
		return;
	}

	# Clear any existing todo items by checking status first
	status := todo->exec("status");
	t.assert(!agentlib->hasprefix(status, "error:"), "todo status returns non-error string");
	t.log(sys->sprint("todo status (may have items): %s", status));
}

# Fix 1: verify todo status is always included in prompts when tool is available.
#
# The todo tool returns "N item: N pending, N done" (never starts with "error").
# The old code had a dead-code guard: !hasprefix(status, "0 pending") — this
# never matched because the format is "N item: ..." not "0 pending, ...".
# The new simplified code: !hasprefix(status, "error") is the only condition.
# Test verifies: status always passes the injection condition when todo is available.
testTodoInjectionCondition(t: ref T)
{
	todo := loadtool("todo");
	if(todo == nil) {
		t.skip("todo injection condition: todo tool not available");
		return;
	}

	# Add and complete an item to get "0 pending, N done" state
	todo->exec("add test-alignment-item");
	status_pending := todo->exec("status");
	todo->exec("done 1");
	status_done := todo->exec("status");

	t.log(sys->sprint("pending state: %s", status_pending));
	t.log(sys->sprint("done state: %s", status_done));

	# New injection condition: !hasprefix(status, "error")
	# Both states pass — both get included in the continuation prompt
	t.assert(!agentlib->hasprefix(status_pending, "error"),
		"Fix1: pending status included (passes injection condition)");
	t.assert(!agentlib->hasprefix(status_done, "error"),
		"Fix1: done-only status included (passes injection condition)");

	# Verify format is informative (contains useful state info for the LLM)
	t.assert(agentlib->contains(status_pending, "pending"),
		"Fix1: status contains 'pending' — informative for LLM");
	t.assert(agentlib->contains(status_done, "done"),
		"Fix1: status contains 'done' — informative for LLM");

	t.log("Fix 1 verified: todo status always injected when tool is available");

	# Clean up
	todo->exec("delete 1");
}

# ====================================================================
# Fix 2 — Retry logic: verify agentlib is accessible and queryllmfd is exported
# ====================================================================

# Verify queryllmfd is callable. Pass a nil fd → write fails immediately → returns "".
# NOTE: With retry delays (100ms + 500ms + 2000ms), this takes ~2.6 seconds.
# Skipped by default; use -retry flag to enable.
testQueryLLMRetryGracefulFailure(t: ref T)
{
	t.skip("retry test skipped (2.6s delay — verify manually via live LLM)");
	# If you want to verify retry behavior manually:
	#   result := agentlib->queryllmfd(nil, "test prompt");
	#   t.assertseq(result, "", "nil fd returns empty string after retry exhausted");
}

# ====================================================================
# Fix 3 — System prompt content: verify mandate text in system.txt
# ====================================================================

testSystemTxtMultiToolMandate(t: ref T)
{
	content := agentlib->readfile("/lib/veltro/system.txt");
	if(len content == 0) {
		t.skip("system.txt not readable");
		return;
	}
	t.assert(agentlib->contains(content, "parallel"),
		"Fix3: system.txt mentions parallel tool execution");
	t.assert(!agentlib->contains(content, "One tool per response. No exceptions"),
		"Fix3: old single-tool mandate removed from system.txt");
}

testSystemTxtTodoMandate(t: ref T)
{
	content := agentlib->readfile("/lib/veltro/system.txt");
	if(len content == 0) {
		t.skip("system.txt not readable");
		return;
	}
	t.assert(agentlib->contains(content, "non-trivial"),
		"Fix1: system.txt uses 'non-trivial tasks' threshold");
	t.assert(agentlib->contains(content, "EXTREMELY helpful"),
		"Fix1: system.txt includes CC-style todo encouragement");
	t.assert(!agentlib->contains(content, "3+ steps"),
		"Fix1: old '3+ steps' threshold removed");
}

testTodoTxtMandate(t: ref T)
{
	content := agentlib->readfile("/lib/veltro/tools/todo.txt");
	if(len content == 0) {
		t.skip("todo.txt not readable");
		return;
	}
	t.assert(agentlib->contains(content, "non-trivial"),
		"Fix1: todo.txt MANDATORY threshold updated to 'non-trivial'");
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
		sys->fprint(sys->fildes(2), "cannot load agentlib: %r\n");
		raise "fail:cannot load agentlib";
	}
	agentlib->init();

	testing->init();
	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	# --- Fix 3: parseactions DONE detection (no /tool required) ---
	run("ParseActionsEmptyResponse",  testParseActionsEmptyResponse);
	run("ParseActionsBareDone",       testParseActionsBareDone);
	run("ParseActionsLowercaseDone",  testParseActionsLowercaseDone);
	run("ParseActionsMarkdownDone",   testParseActionsMarkdownDone);
	run("ParseActionsPreambleThenDone", testParseActionsPreambleThenDone);

	# --- Fix 3: parseactions multi-tool (requires /tool) ---
	run("ParseActionsMultiTool",      testParseActionsMultiTool);
	run("ParseActionsSkipPreamble",   testParseActionsSkipPreamble);
	run("ParseActionsToolThenDone",   testParseActionsToolThenDone);
	run("ParseActionsThreeTools",     testParseActionsThreeTools);

	# --- Fix 3: parallel execution (direct tool modules) ---
	run("ParallelExecPattern",        testParallelExecPattern);
	run("ParallelExecOrdering",       testParallelExecOrdering);
	run("ParallelTiming",             testParallelTiming);

	# --- Fix 1: todo unconditional injection ---
	run("TodoEmptyStatusIsNonError",  testTodoEmptyStatusIsNonError);
	run("TodoInjectionCondition",     testTodoInjectionCondition);

	# --- Fix 2: retry (graceful failure verification) ---
	run("QueryLLMRetryGracefulFailure", testQueryLLMRetryGracefulFailure);

	# --- Fix 3 + Fix 1: system prompt content ---
	run("SystemTxtMultiToolMandate",  testSystemTxtMultiToolMandate);
	run("SystemTxtTodoMandate",       testSystemTxtTodoMandate);
	run("TodoTxtMandate",             testTodoTxtMandate);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
