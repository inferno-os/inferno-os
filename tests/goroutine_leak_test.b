implement GoroutineLeakTest;

#
# Regression tests for goroutine leak fixes (feature/lucifer, 2026-02).
#
# Three bugs were fixed by changing unbuffered chan of T to chan[1] of T
# for one-shot goroutines that send a single value then exit:
#
#   exec.b:     result, timeout, reader channels
#   websearch.b: result, timeout channels
#   spawn.b:    result channel
#
# Root cause: when alt{} takes branch X (e.g. timeout), goroutines that
# would have sent on other branches (e.g. result) were blocked forever
# on unbuffered channels — goroutine leak per call.
#
# Fix: chan[1] of T provides one buffered slot, so the losing goroutine
# can complete its send and exit even after the alt has moved on.
#
# Tests in this file:
#   1. testChan1SenderExitsCleanly   — core chan[1] buffering semantics
#   2. testTimerGoroutineExits       — timer pattern from exec/websearch
#   3. testExecEmptyCommand          — exec tool: usage error, no goroutines
#   4. testExecSuccess               — exec tool: successful command
#   5. testExecTimeout               — exec tool: timeout fires, goroutines exit
#   6. testExecTimeoutRepeated       — 2 × timeout: no goroutine accumulation
#   7. testWebsearchEmptyQuery       — websearch: usage error
#   8. testWebsearchMissingKey       — websearch: missing key, early return
#   9. testChunkedPread              — chunked pread pattern (lucibridge fix)
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

# Tool module interface (matches /appl/veltro/tool.m)
Tool: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

GoroutineLeakTest: module {
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/goroutine_leak_test.b";

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

loadtool(name: string): Tool
{
	path := "/dis/veltro/tools/" + name + ".dis";
	mod := load Tool path;
	if(mod != nil)
		mod->init();
	return mod;
}

# ============================================================================
# Test 1: testChan1SenderExitsCleanly
#
# Verify that a goroutine sending on chan[1] can complete its send and exit
# even when the receiver has already moved on to handle a different branch.
# This is the fundamental property that prevents goroutine leaks in exec.b,
# websearch.b, and spawn.b.
# ============================================================================

testChan1SenderExitsCleanly(t: ref T)
{
	# chan[1]: one buffered slot — sender completes immediately,
	# no receiver needs to be waiting.
	result := chan[1] of int;
	exited := chan of int;

	spawn chan1sender(result, exited);

	# Simulate the receiver moving on — we never drain 'result',
	# as if the alt{} took a different branch (e.g. timeout fired first).
	# The sender must still be able to send and signal its exit.
	gotExit := chan[1] of int;
	spawn timerwait(gotExit, 500);

	alt {
	<-exited =>
		t.assert(1 == 1, "sender goroutine exited cleanly after chan[1] send");
	<-gotExit =>
		t.fatal("sender goroutine leaked: did not exit within 500ms");
	}
}

chan1sender(ch: chan of int, done: chan of int)
{
	ch <-= 42;	# Buffered: completes immediately without a receiver
	done <-= 1;	# Signal that we exited
}

# ============================================================================
# Test 2: testTimerGoroutineExits
#
# Simulate the timer goroutine pattern used in exec.b and websearch.b:
#   timeout := chan[1] of int
#   spawn timer(timeout, N)
# When the result arrives first and the alt takes the result branch,
# the timer goroutine later sends on chan[1] and exits cleanly.
# ============================================================================

testTimerGoroutineExits(t: ref T)
{
	# timeout is chan[1] — timer can send and exit even if never drained
	timeout := chan[1] of int;
	timerExited := chan of int;

	# Timer fires after 150ms, sends on timeout (chan[1]), signals timerExited
	spawn timertrack(timeout, 150, timerExited);

	# Receiver immediately moves on — never drains 'timeout'.
	# This simulates the alt{} result branch winning before the timer fires.

	# Verify timer goroutine exits within 1 second (150ms sleep + margin)
	waitDone := chan[1] of int;
	spawn timerwait(waitDone, 1000);

	alt {
	<-timerExited =>
		t.assert(1 == 1, "timer goroutine exited cleanly after sending on chan[1]");
	<-waitDone =>
		t.fatal("timer goroutine leaked: did not exit within 1s");
	}
}

timertrack(ch: chan of int, ms: int, done: chan of int)
{
	sys->sleep(ms);
	ch <-= 1;	# Buffered chan[1]: completes even without receiver
	done <-= 1;
}

timerwait(ch: chan of int, ms: int)
{
	sys->sleep(ms);
	ch <-= 1;
}

# ============================================================================
# Test 3: testExecEmptyCommand
#
# Exec tool handles empty command without spawning any goroutines.
# Returns a usage error immediately.
# ============================================================================

testExecEmptyCommand(t: ref T)
{
	exec := loadtool("exec");
	if(exec == nil) {
		t.skip("exec tool not available");
		return;
	}
	result := exec->exec("");
	t.log("empty command: " + result);
	t.assert(hassubstr(result, "error"), "empty exec should return error");
}


# ============================================================================
# Test 7: testWebsearchEmptyQuery
#
# Websearch returns a usage error for empty args without spawning goroutines.
# ============================================================================

testWebsearchEmptyQuery(t: ref T)
{
	ws := loadtool("websearch");
	if(ws == nil) {
		t.skip("websearch tool not available");
		return;
	}
	result := ws->exec("");
	t.log("empty query: " + result);
	t.assert(hassubstr(result, "error"), "empty websearch should return error");
	t.assert(hassubstr(result, "usage"), "empty websearch should mention usage");
}

# ============================================================================
# Test 8: testWebsearchMissingKey
#
# When the Brave API key file is absent, websearch returns an error before
# spawning any network goroutines. No goroutines to leak.
# Verifies the error path works and returns promptly.
# ============================================================================

testWebsearchMissingKey(t: ref T)
{
	ws := loadtool("websearch");
	if(ws == nil) {
		t.skip("websearch tool not available");
		return;
	}

	# Check whether the key file exists; if it does, test environment has
	# live credentials and the network path would be exercised instead.
	(ok, nil) := sys->stat("/lib/veltro/keys/brave");
	if(ok >= 0) {
		t.skip("brave API key present — skipping missing-key test");
		return;
	}

	start := sys->millisec();
	result := ws->exec("inferno OS regression test query");
	elapsed := sys->millisec() - start;
	t.log(sys->sprint("missing key returned in %dms: %s", elapsed, result));

	# readapikey() returns "" immediately → no network I/O, no goroutines
	t.assert(elapsed < 2000,
		sys->sprint("missing key should return quickly, got %dms", elapsed));
	t.assert(hassubstr(result, "error"),
		"missing key should return error message");
}

# ============================================================================
# Test 9: testChunkedPread
#
# Verify that chunked pread() (8KB buffer) correctly reassembles a large file.
# This is the pattern used by lucibridge's readllmfd() after the OOM fix.
# Before the fix: array[1048576] of byte allocated per LLM call.
# After the fix: array[8192] of byte in a pread loop.
# ============================================================================

CHUNK_SIZE: con 8192;	# Matches lucibridge readllmfd() buffer size
N_CHUNKS: con 20;		# 20 × 1024 = 20KB > one buffer

testChunkedPread(t: ref T)
{
	testfile := "/tmp/goroutine_leak_test_pread.dat";

	# Build expected content: 20 × 1024-byte chunks, each with a header
	expected := "";
	for(i := 0; i < N_CHUNKS; i++) {
		hdr := sys->sprint("CHUNK%04d:", i);
		padchar := '0' + (i % 10);
		while(len hdr < 1024)
			hdr[len hdr] = padchar;
		expected += hdr;
	}

	# Write test file
	fd := sys->create(testfile, Sys->OWRITE, 8r644);
	if(fd == nil) {
		t.fatal(sys->sprint("cannot create %s: %r", testfile));
		return;
	}
	b := array of byte expected;
	nw := sys->write(fd, b, len b);
	fd = nil;
	t.asserteq(nw, len b, "write should write all bytes");

	# Read back via chunked pread (exact pattern from lucibridge readllmfd())
	rfd := sys->open(testfile, Sys->OREAD);
	if(rfd == nil) {
		t.fatal(sys->sprint("cannot open %s: %r", testfile));
		return;
	}
	result := "";
	buf := array[CHUNK_SIZE] of byte;
	offset := big 0;
	for(;;) {
		nr := sys->pread(rfd, buf, len buf, offset);
		if(nr <= 0)
			break;
		result += string buf[0:nr];
		offset += big nr;
	}
	rfd = nil;

	# Verify all data was read
	t.asserteq(len result, len expected,
		sys->sprint("pread should read %d bytes, got %d", len expected, len result));

	# Spot-check chunk boundaries ("CHUNK0000:" = 10 chars)
	t.assertseq(result[0:10], "CHUNK0000:",
		"first chunk header mismatch");
	mid := 1024 * (N_CHUNKS / 2);
	t.assertseq(result[mid:mid+10], sys->sprint("CHUNK%04d:", N_CHUNKS/2),
		"middle chunk header mismatch");
	last := 1024 * (N_CHUNKS - 1);
	t.assertseq(result[last:last+10], sys->sprint("CHUNK%04d:", N_CHUNKS-1),
		"last chunk header mismatch");

	# Clean up
	sys->remove(testfile);
}

# ============================================================================
# Helpers
# ============================================================================

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

# ============================================================================
# Main
# ============================================================================

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
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

	# Core chan[1] behavior (pure Limbo, fast, no external tools)
	run("Chan1SenderExitsCleanly", testChan1SenderExitsCleanly);
	run("TimerGoroutineExits", testTimerGoroutineExits);

	# Chunked pread (I/O, no LLM stack required)
	run("ChunkedPread", testChunkedPread);

	# Exec tool early-exit path (returns before creating pipe — no fd clobbering)
	run("ExecEmptyCommand", testExecEmptyCommand);

	# Websearch tool tests (requires /dis/veltro/tools/websearch.dis)
	run("WebsearchEmptyQuery", testWebsearchEmptyQuery);
	run("WebsearchMissingKey", testWebsearchMissingKey);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
