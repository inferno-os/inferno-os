implement LuciuisrvTest;

#
# Regression tests for luciuisrv — the Lucifer UI 9P server.
#
# Tests all critical ctl commands and behaviors that have caused regressions:
#   - Activity creation and directory structure
#   - Conversation message write + readback
#   - Conversation message in-place update (streaming fix)
#   - Event delivery for conversation, presentation, context
#   - Presentation artifact create/update/append/center
#   - Context resource/gap/background task management
#   - Activity label + status read/write
#   - "conversation update N" event (used by lucibridge for streaming tokens)
#
# luciuisrv is loaded as a module and mounted at TESTMNT.
# No external processes required — the server runs in background goroutines.
#
# To run standalone:
#   ./emu/MacOSX/o.emu -r. /dis/tests/luciuisrv_test.dis
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

# luciuisrv is loaded as a standard Inferno command module
LuciuiSrv: module {
	init: fn(nil: ref Draw->Context, args: list of string);
};

LuciuisrvTest: module {
	init: fn(nil: ref Draw->Context, args: list of string);
	_marker: fn();	# prevents joiniface() type conflation with LuciuiSrv
};

SRCFILE:	con "/tests/luciuisrv_test.b";
TESTMNT:	con "/tmp/luciuisrv_test";
SRVPATH:	con "/dis/luciuisrv.dis";

passed := 0;
failed := 0;
skipped := 0;

# Activity created in testSetup; used by all subsequent tests.
actid := -1;

# Required by LuciuisrvTest module declaration to prevent joiniface() type conflation.
_marker() {}

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

# ============================================================================
# Helpers
# ============================================================================

actbase(): string
{
	return TESTMNT + "/activity/" + string actid;
}

writefile(path, data: string): int
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil)
		return -1;
	b := array of byte data;
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
	if(n < 0)
		return nil;
	return string buf[0:n];
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

# Read one event from path (blocking); send on ch.
# Sends "error:..." if open/read fails.
eventreader(path: string, ch: chan of string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil) {
		ch <-= "error:open:" + path;
		return;
	}
	buf := array[512] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0) {
		ch <-= "error:read:" + path;
		return;
	}
	ch <-= string buf[0:n];
}

# Send 1 on ch after ms milliseconds.
timerwait(ch: chan of int, ms: int)
{
	sys->sleep(ms);
	ch <-= 1;
}

# Wait for an event on path, with a 3-second timeout.
# Returns the event string or "error:..." / "error:timeout".
readevent(path: string): string
{
	evch := chan[1] of string;
	spawn eventreader(path, evch);

	toch := chan[1] of int;
	spawn timerwait(toch, 3000);

	ev := "";
	alt {
	ev = <-evch =>
		;
	<-toch =>
		ev = "error:timeout";
	}
	return ev;
}

# Server startup goroutine
startserver(done: chan of int, mountpt: string)
{
	srv := load LuciuiSrv SRVPATH;
	if(srv == nil) {
		done <-= 0;
		return;
	}
	{
		srv->init(nil, "luciuisrv" :: "-m" :: mountpt :: nil);
		done <-= 1;
	} exception {
	* =>
		done <-= 0;
	}
}

# ============================================================================
# Test 1: testSetup
#
# Load and start luciuisrv at TESTMNT, create the test activity.
# Sets the global actid used by all subsequent tests.
# ============================================================================

testSetup(t: ref T)
{
	# Start luciuisrv in background; it mounts at TESTMNT and returns.
	done := chan[1] of int;
	spawn startserver(done, TESTMNT);

	toch := chan[1] of int;
	spawn timerwait(toch, 5000);

	ok := 0;
	alt {
	ok = <-done =>
		;
	<-toch =>
		t.fatal("luciuisrv did not start within 5 seconds");
	}

	if(ok == 0) {
		t.fatal("luciuisrv failed to load or mount (is " + SRVPATH + " present?)");
		return;
	}

	# Verify mount succeeded
	(st, nil) := sys->stat(TESTMNT + "/ctl");
	t.assert(st >= 0, "TESTMNT/ctl should exist after mount");
	(st2, nil) := sys->stat(TESTMNT + "/event");
	t.assert(st2 >= 0, "TESTMNT/event should exist after mount");
	(st3, nil) := sys->stat(TESTMNT + "/activity");
	t.assert(st3 >= 0, "TESTMNT/activity/ should exist after mount");

	# Create test activity
	n := writefile(TESTMNT + "/ctl", "activity create LuciuisrvTest");
	t.assert(n > 0, "activity create should write successfully");

	# Read current activity ID from activity/current (synchronous, no event race).
	# The global /event file is not buffered — events are dropped if no reader
	# is waiting when they fire, so we cannot rely on it here.
	idraw := readfile(TESTMNT + "/activity/current");
	t.assertnotnil(idraw, "activity/current should be readable after create");
	id := strtoint(strip(idraw));
	t.assert(id >= 0, "activity ID should be non-negative");
	actid = id;
	t.log(sys->sprint("test activity ID: %d", actid));

	# Verify activity directory exists
	(st4, nil) := sys->stat(actbase());
	t.assert(st4 >= 0, "activity directory should exist");
	(st5, nil) := sys->stat(actbase() + "/conversation/ctl");
	t.assert(st5 >= 0, "conversation/ctl should exist");
	(st6, nil) := sys->stat(actbase() + "/presentation/ctl");
	t.assert(st6 >= 0, "presentation/ctl should exist");
	(st7, nil) := sys->stat(actbase() + "/context/ctl");
	t.assert(st7 >= 0, "context/ctl should exist");
}

# ============================================================================
# Test 2: testConvMessageWrite
#
# Write a conversation message to conv/ctl and read it back from conv/0.
# Regression: broken QID encoding caused wrong file to be accessed.
# ============================================================================

testConvMessageWrite(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity (testSetup failed)");
		return;
	}

	convctl := actbase() + "/conversation/ctl";
	n := writefile(convctl, "role=human text=Hello from regression test");
	t.assert(n > 0, "write to conversation/ctl should succeed");

	# Read back from conversation/0
	msg := readfile(actbase() + "/conversation/0");
	t.assert(msg != nil, "conversation/0 should exist after message write");
	t.log("conv/0: " + msg);
	t.assert(hassubstr(msg, "role=human"), "message should have role=human");
	t.assert(hassubstr(msg, "Hello from regression test"),
		"message should contain the written text");
}

# ============================================================================
# Test 3: testConvMessageUpdate
#
# Write a message, then update it in-place with "update idx=0 text=..."
# Regression: streaming token delivery (lucibridge live updates) requires
# this path to work; broken = static placeholder cursor stuck on screen.
# ============================================================================

testConvMessageUpdate(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	convctl := actbase() + "/conversation/ctl";

	# Write a placeholder (streaming start)
	writefile(convctl, "role=veltro text=▌");

	# Find the index of the message we just wrote
	# It might be 0 if this is the first, or higher if previous tests wrote messages
	# Read the most recent message by checking how many exist
	msgidx := 0;
	for(i := 0; i < 20; i++) {
		(ok, nil) := sys->stat(actbase() + "/conversation/" + string i);
		if(ok < 0)
			break;
		msgidx = i;
	}
	t.log(sys->sprint("veltro placeholder at idx %d", msgidx));

	# Update in-place (simulates streaming token delivery)
	updatecmd := sys->sprint("update idx=%d text=Updated streaming content", msgidx);
	n := writefile(convctl, updatecmd);
	t.assert(n > 0, "update write to conversation/ctl should succeed");

	# Read back and verify updated content
	updated := readfile(actbase() + "/conversation/" + string msgidx);
	t.assert(updated != nil, "updated message file should exist");
	t.log("after update: " + updated);
	t.assert(hassubstr(updated, "Updated streaming content"),
		"message should contain updated text");
	t.assert(!hassubstr(updated, "▌"),
		"cursor placeholder should be replaced by update");
}

# ============================================================================
# Test 3b: testConvTextEmbeddedEquals
#
# Write a message whose text contains embedded "word=value" patterns and
# verify the full text is stored and returned.
#
# Regression: parseattrs() scanned the entire string for key= patterns.
# LLM responses often contain patterns like "access=read", "type=markdown",
# "path=/foo", "x=5 y=3" in explanations, causing text= to be truncated
# at the first such pattern found after the text= attribute.
# Fix: text= and data= are treated as terminal attributes (always extend to
# end-of-string) so embedded = signs never truncate the value.
# ============================================================================

testConvTextEmbeddedEquals(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	convctl := actbase() + "/conversation/ctl";

	# Text with embedded key=value patterns (common in LLM explanations).
	# Without the fix, parsing would stop at "access=" or "type=" etc.
	text := "Each subagent uses access=read for readonly ops, type=text for plain output. " +
		"The path=/n/tools mount provides namespace=isolated sandboxing. " +
		"Settings like max_tokens=4096 and temperature=0.7 control generation.";

	n := writefile(convctl, "role=veltro text=" + text);
	t.assert(n > 0, "write message with embedded = should succeed");

	# Find the index (last written message)
	msgidx := 0;
	for(i := 0; i < 50; i++) {
		(ok, nil) := sys->stat(actbase() + "/conversation/" + string i);
		if(ok < 0)
			break;
		msgidx = i;
	}

	# Read back — must contain the complete text, not just the part before "access="
	raw := readfile(actbase() + "/conversation/" + string msgidx);
	t.assert(raw != nil, "message should be readable");

	t.assert(hassubstr(raw, "access=read"),
		"message should contain 'access=read' without truncation");
	t.assert(hassubstr(raw, "type=text"),
		"message should contain 'type=text' without truncation");
	t.assert(hassubstr(raw, "namespace=isolated"),
		"message should contain 'namespace=isolated' without truncation");
	t.assert(hassubstr(raw, "max_tokens=4096"),
		"message should contain 'max_tokens=4096' without truncation");
	t.assert(hassubstr(raw, "temperature=0.7"),
		"message should contain 'temperature=0.7' — last embedded = pattern");
}

# ============================================================================
# Test 4: testConvEventDelivery
#
# Write a message and verify the activity event fires.
# Regression: broken event buffering (pendingevent) caused lucifer to miss
# updates when the nslistener was between reads.
# ============================================================================

testConvEventDelivery(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	# Write a message — this should trigger "conversation <idx>" event
	writefile(actbase() + "/conversation/ctl", "role=human text=event-test-message");

	# Read from per-activity event file
	ev := readevent(actbase() + "/event");
	t.log("conversation event: " + ev);
	t.assert(!hassubstr(ev, "error:"), "event read should not return error: " + ev);
	t.assert(hassubstr(ev, "conversation"),
		"event should contain 'conversation' after message write");
}

# ============================================================================
# Test 5: testConvUpdateEvent
#
# Update a message and verify "conversation update <idx>" event fires.
# Regression: the "update" command path needed its own event emission;
# without it lucifer's nslistener never received the streaming event.
# ============================================================================

testConvUpdateEvent(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	convctl := actbase() + "/conversation/ctl";

	# Write a message to update
	writefile(convctl, "role=veltro text=initial");

	# Drain the "conversation N" event from writing
	readevent(actbase() + "/event");

	# Find the index of this message
	msgidx := 0;
	for(i := 0; i < 50; i++) {
		(ok, nil) := sys->stat(actbase() + "/conversation/" + string i);
		if(ok < 0)
			break;
		msgidx = i;
	}

	# Now update — should fire "conversation update <idx>" event
	writefile(convctl, sys->sprint("update idx=%d text=updated-for-event-test", msgidx));

	ev := readevent(actbase() + "/event");
	t.log("update event: " + ev);
	t.assert(!hassubstr(ev, "error:"), "event should not be an error: " + ev);
	t.assert(hassubstr(ev, "conversation update"),
		"event should say 'conversation update'");
	t.assert(hassubstr(ev, string msgidx),
		sys->sprint("event should reference idx %d", msgidx));
}

# ============================================================================
# Test 6: testPresentationCreate
#
# Create an artifact and verify its directory structure.
# Regression: broken QID sub-id encoding caused wrong artifact to be returned.
# ============================================================================

testPresentationCreate(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	presctl := actbase() + "/presentation/ctl";

	n := writefile(presctl, "create id=regtest-art type=markdown label=RegressionArtifact");
	t.assert(n > 0, "create artifact should succeed");

	# Verify artifact subdirectory structure
	artbase := actbase() + "/presentation/regtest-art";
	(ok1, nil) := sys->stat(artbase + "/type");
	t.assert(ok1 >= 0, "artifact/type should exist");
	(ok2, nil) := sys->stat(artbase + "/label");
	t.assert(ok2 >= 0, "artifact/label should exist");
	(ok3, nil) := sys->stat(artbase + "/data");
	t.assert(ok3 >= 0, "artifact/data should exist");

	# Verify type and label are readable and correct
	atype := strip(readfile(artbase + "/type"));
	t.assertseq(atype, "markdown", "artifact type should be 'markdown'");
	alabel := strip(readfile(artbase + "/label"));
	t.assertseq(alabel, "RegressionArtifact", "artifact label should match");
}

# ============================================================================
# Test 7: testPresentationDataWrite
#
# Write data to an artifact's data file and read it back.
# Regression: data writes going to wrong artifact (sub-id ordering bug).
# ============================================================================

testPresentationDataWrite(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	# Ensure artifact exists (depends on testPresentationCreate)
	presctl := actbase() + "/presentation/ctl";
	writefile(presctl, "create id=datatest-art type=text label=DataTest");

	artdata := actbase() + "/presentation/datatest-art/data";
	content := "# Test Content\n\nThis is regression test data for the presentation zone.";

	n := writefile(artdata, content);
	t.assert(n > 0, "write to artifact data should succeed");

	# Read back and verify
	readback := readfile(artdata);
	t.assert(readback != nil, "artifact data should be readable after write");
	t.assertseq(readback, content, "artifact data should match written content");
}

# ============================================================================
# Test 8: testPresentationUpdate
#
# Update an artifact via presentation/ctl "update id=... data=..." command.
# Regression: update command parsed wrong field (label vs data mismatch).
# ============================================================================

testPresentationUpdate(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	presctl := actbase() + "/presentation/ctl";
	writefile(presctl, "create id=updatetest type=text label=UpdateTest");

	# Update the artifact data via ctl
	n := writefile(presctl, "update id=updatetest data=new-content-via-update");
	t.assert(n > 0, "update artifact via ctl should succeed");

	# Verify data changed
	data := readfile(actbase() + "/presentation/updatetest/data");
	t.assert(data != nil, "artifact data should be readable");
	t.assert(hassubstr(data, "new-content-via-update"),
		"artifact data should contain updated content");
}

# ============================================================================
# Test 9: testPresentationAppend
#
# Append data to an artifact using "append id=... data=..." command.
# Regression: append command was added for streaming artifacts; if missing,
# progressive artifact generation doesn't work in the presentation zone.
# ============================================================================

testPresentationAppend(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	presctl := actbase() + "/presentation/ctl";
	writefile(presctl, "create id=appendtest type=markdown label=AppendTest");

	# Write initial content
	artdata := actbase() + "/presentation/appendtest/data";
	writefile(artdata, "Initial content.");

	# Append via ctl
	writefile(presctl, "append id=appendtest data= More appended content.");

	# Read and verify data grew
	data := readfile(artdata);
	t.assert(data != nil, "artifact data should be readable after append");
	t.log("after append: " + data);
	t.assert(hassubstr(data, "Initial content."),
		"original content should be preserved");
	t.assert(hassubstr(data, "More appended content."),
		"appended content should be present");
}

# ============================================================================
# Test 10: testPresentationCenter
#
# Center an artifact and verify the presentation/current file updates.
# Regression: center command was added for tab click support; broken = tabs
# don't switch when clicked in the Lucifer UI.
# ============================================================================

testPresentationCenter(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	presctl := actbase() + "/presentation/ctl";
	writefile(presctl, "create id=center-a type=text label=CenterA");
	writefile(presctl, "create id=center-b type=text label=CenterB");

	# Center artifact A
	n := writefile(presctl, "center id=center-a");
	t.assert(n > 0, "center command should succeed");

	current := strip(readfile(actbase() + "/presentation/current"));
	t.assert(current != nil, "presentation/current should be readable");
	t.assertseq(current, "center-a", "presentation/current should be 'center-a'");

	# Switch to artifact B
	writefile(presctl, "center id=center-b");
	current = strip(readfile(actbase() + "/presentation/current"));
	t.assertseq(current, "center-b", "presentation/current should switch to 'center-b'");
}

# ============================================================================
# Test 11: testPresentationEvent
#
# Create an artifact and verify "presentation new <id>" event fires.
# Regression: missing event emission caused lucifer to not load new artifacts.
# ============================================================================

testPresentationEvent(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	# Drain any pending event first (from previous tests)
	# by sleeping briefly so pending reads can settle
	sys->sleep(50);

	# Read any buffered event (non-blocking style: try with 100ms timeout)
	drainch := chan[1] of string;
	spawn eventreader(actbase() + "/event", drainch);
	drained := chan[1] of int;
	spawn timerwait(drained, 100);
	alt {
	<-drainch =>
		;  # consumed buffered event
	<-drained =>
		;  # no pending event, continue
	}

	# Now trigger a known event
	writefile(actbase() + "/presentation/ctl",
		"create id=event-art type=text label=EventArt");

	ev := readevent(actbase() + "/event");
	t.log("presentation event: " + ev);
	t.assert(!hassubstr(ev, "error:"), "should not get error: " + ev);
	t.assert(hassubstr(ev, "presentation"),
		"event should mention 'presentation' after artifact create");
}

# ============================================================================
# Test 12: testContextResourceAdd
#
# Add a resource to the context zone and read it back.
# Regression: context ctl parser broke resource tracking used in context zone.
# ============================================================================

testContextResourceAdd(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	ctxctl := actbase() + "/context/ctl";
	n := writefile(ctxctl,
		"resource add path=/api/test label=TestAPI type=api status=streaming");
	t.assert(n > 0, "resource add should succeed");

	# Read back from resources/0
	res := readfile(actbase() + "/context/resources/0");
	t.assert(res != nil, "context/resources/0 should exist after resource add");
	t.log("resource/0: " + res);
	t.assert(hassubstr(res, "path=/api/test"),
		"resource should contain path=/api/test");
	t.assert(hassubstr(res, "status=streaming"),
		"resource should contain status=streaming");
}

# ============================================================================
# Test 13: testContextGapAdd
#
# Add a knowledge gap and read it back.
# ============================================================================

testContextGapAdd(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	ctxctl := actbase() + "/context/ctl";
	n := writefile(ctxctl, "gap add desc=missing_weather_data relevance=high");
	t.assert(n > 0, "gap add should succeed");

	# Read back from gaps/0
	gap := readfile(actbase() + "/context/gaps/0");
	t.assert(gap != nil, "context/gaps/0 should exist after gap add");
	t.log("gaps/0: " + gap);
	t.assert(hassubstr(gap, "missing_weather_data"),
		"gap should contain the description");
	t.assert(hassubstr(gap, "high"),
		"gap should contain relevance=high");
}

# ============================================================================
# Test 14: testContextBgTaskAdd
#
# Add a background task and read it back.
# ============================================================================

testContextBgTaskAdd(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	ctxctl := actbase() + "/context/ctl";
	n := writefile(ctxctl, "bg add label=web-search status=live");
	t.assert(n > 0, "bg add should succeed");

	# Read back from background/0
	bg := readfile(actbase() + "/context/background/0");
	t.assert(bg != nil, "context/background/0 should exist after bg add");
	t.log("background/0: " + bg);
	t.assert(hassubstr(bg, "web-search"),
		"background task should contain label");
	t.assert(hassubstr(bg, "live"),
		"background task should contain status=live");
}

# ============================================================================
# Test 15: testActivityLabel
#
# Read and write the activity label file.
# ============================================================================

testActivityLabel(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	labelfile := actbase() + "/label";

	# Read initial label (set at creation time)
	initial := readfile(labelfile);
	t.assert(initial != nil, "label file should be readable");
	t.log("initial label: " + initial);

	# Write new label
	n := writefile(labelfile, "UpdatedLabel");
	t.assert(n > 0, "write to label should succeed");

	# Read back and verify
	updated := strip(readfile(labelfile));
	t.assert(updated != nil, "updated label should be readable");
	t.assertseq(updated, "UpdatedLabel", "label should match written value");
}

# ============================================================================
# Test 16: testActivityStatus
#
# Read and write the activity status file.
# ============================================================================

testActivityStatus(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	statusfile := actbase() + "/status";

	# Read initial status
	initial := readfile(statusfile);
	t.assert(initial != nil, "status file should be readable");
	t.log("initial status: " + initial);

	# Write "working" status (used by lucibridge while LLM is thinking)
	n := writefile(statusfile, "working");
	t.assert(n > 0, "write to status should succeed");
	s := strip(readfile(statusfile));
	t.assertseq(s, "working", "status should be 'working'");

	# Write back to idle
	writefile(statusfile, "idle");
	s = strip(readfile(statusfile));
	t.assertseq(s, "idle", "status should return to 'idle'");
}

# ============================================================================
# Test 17: testMultipleArtifacts
#
# Create multiple artifacts and verify each is independently accessible.
# Regression: QID sub-id overflow or index collision caused wrong artifact
# data returned when multiple artifacts existed simultaneously (tab switching).
# ============================================================================

testMultipleArtifacts(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	presctl := actbase() + "/presentation/ctl";

	# Create 5 artifacts with distinct content
	for(i := 0; i < 5; i++) {
		id := "multi-art-" + string i;
		writefile(presctl, "create id=" + id + " type=text label=Art" + string i);
		writefile(actbase() + "/presentation/" + id + "/data",
			"Content for artifact " + string i + " only.");
	}

	# Verify each artifact has its own distinct data (no cross-contamination)
	for(i = 0; i < 5; i++) {
		id := "multi-art-" + string i;
		data := readfile(actbase() + "/presentation/" + id + "/data");
		t.assert(data != nil, "artifact " + id + " data should be readable");
		t.assert(hassubstr(data, "Content for artifact " + string i + " only."),
			sys->sprint("artifact %d should have its own content", i));
		# Verify it does NOT contain other artifacts' content
		for(j := 0; j < 5; j++) {
			if(j != i)
				t.assert(!hassubstr(data, "artifact " + string j + " only."),
					sys->sprint("artifact %d should not contain artifact %d content",
						i, j));
		}
	}
}

# ============================================================================
# Test 18: testMultipleMessages
#
# Write multiple messages and verify each is independently accessible.
# Regression: message index counter not incremented (all messages at idx 0).
# ============================================================================

testMultipleMessages(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	convctl := actbase() + "/conversation/ctl";

	# Find starting index (how many messages exist already)
	startidx := 0;
	for(i := 0; i < 100; i++) {
		(ok, nil) := sys->stat(actbase() + "/conversation/" + string i);
		if(ok < 0) {
			startidx = i;
			break;
		}
	}

	# Write 5 messages
	nmsgs := 5;
	for(i = 0; i < nmsgs; i++) {
		role := "human";
		if(i % 2 == 1)
			role = "veltro";
		writefile(convctl,
			"role=" + role + " text=MultiMsg-" + string (startidx + i));
	}

	# Verify each message exists with correct content
	for(i = 0; i < nmsgs; i++) {
		idx := startidx + i;
		msg := readfile(actbase() + "/conversation/" + string idx);
		t.assert(msg != nil,
			sys->sprint("conversation/%d should exist", idx));
		t.assert(hassubstr(msg, "MultiMsg-" + string idx),
			sys->sprint("message %d should contain its unique marker", idx));
	}
}

# ============================================================================
# Test 19: testConvInput
#
# Verify the conversation/input file exists and is openable.
# This is the file lucibridge reads from (blocking) to get user messages.
# Regression: input file missing caused lucibridge to fail silently at startup.
# ============================================================================

testConvInput(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	inputfile := actbase() + "/conversation/input";
	(ok, nil) := sys->stat(inputfile);
	t.assert(ok >= 0, "conversation/input should exist");

	# Opening it should succeed (it's a blocking read; we just check open)
	fd := sys->open(inputfile, Sys->OREAD);
	t.assert(fd != nil, "conversation/input should be openable");
	fd = nil;
}

# ============================================================================
# Test 20: testContextResourceUpdate
#
# Update a resource's status and verify the change persists.
# Regression: resource update command parsed wrong attributes.
# ============================================================================

testContextResourceUpdate(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	ctxctl := actbase() + "/context/ctl";

	# Add a resource first
	writefile(ctxctl,
		"resource add path=/api/updatable label=Updatable type=api status=streaming");

	# Update its status to stale
	n := writefile(ctxctl, "resource update path=/api/updatable status=stale");
	t.assert(n > 0, "resource update should succeed");

	# Read back and verify status changed
	# Find the resource (might not be resources/0 if others exist)
	found := 0;
	for(i := 0; i < 20; i++) {
		res := readfile(actbase() + "/context/resources/" + string i);
		if(res == nil)
			break;
		if(hassubstr(res, "path=/api/updatable")) {
			t.log("updated resource: " + res);
			t.assert(hassubstr(res, "status=stale"),
				"resource status should be updated to stale");
			found = 1;
			break;
		}
	}
	t.assert(found == 1, "updated resource should be findable in resources/");
}

# ============================================================================
# Test 21: testGapUpsert
#
# Verify gap upsert is idempotent by description: adding the same desc twice
# should yield a single entry with the updated relevance.
# ============================================================================

testGapUpsert(t: ref T)
{
	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	ctxctl := actbase() + "/context/ctl";
	i: int;

	# Count gaps before test
	startcount := 0;
	for(i = 0; i < 50; i++) {
		(ok, nil) := sys->stat(actbase() + "/context/gaps/" + string i);
		if(ok < 0) {
			startcount = i;
			break;
		}
	}

	# Upsert a new gap with relevance=high
	n := writefile(ctxctl, "gap upsert desc=test_upsert_idempotency relevance=high");
	t.assert(n > 0, "gap upsert should succeed");

	# Find and verify the gap was created
	found := "";
	for(i = startcount; i < startcount + 20; i++) {
		g := readfile(actbase() + "/context/gaps/" + string i);
		if(g == nil)
			break;
		if(hassubstr(g, "test_upsert_idempotency")) {
			found = g;
			break;
		}
	}
	t.assert(found != "", "gap should exist after upsert");
	t.log("gap after first upsert: " + found);
	t.assert(hassubstr(found, "relevance=high"), "gap relevance should be high");

	# Upsert again with same desc, different relevance — should NOT create duplicate
	n = writefile(ctxctl, "gap upsert desc=test_upsert_idempotency relevance=low");
	t.assert(n > 0, "second gap upsert should succeed");

	# Count gaps after second upsert — should be same as after first
	countafter := 0;
	for(i = 0; i < 100; i++) {
		(ok, nil) := sys->stat(actbase() + "/context/gaps/" + string i);
		if(ok < 0) {
			countafter = i;
			break;
		}
	}
	# Count with test gap included = startcount + 1
	t.assert(countafter == startcount + 1,
		sys->sprint("gap count should be %d, got %d (no duplicate created)",
			startcount + 1, countafter));

	# Verify relevance was updated
	updated := "";
	for(i = startcount; i < startcount + 20; i++) {
		g := readfile(actbase() + "/context/gaps/" + string i);
		if(g == nil)
			break;
		if(hassubstr(g, "test_upsert_idempotency")) {
			updated = g;
			break;
		}
	}
	t.assert(updated != "", "gap should still exist after second upsert");
	t.log("gap after second upsert: " + updated);
	t.assert(hassubstr(updated, "relevance=low"), "gap relevance should be updated to low");
	t.assert(!hassubstr(updated, "relevance=high"), "old relevance should be gone");
}

# ============================================================================
# Test 22: testGapResolve
#
# Verify gap resolve removes a gap by description match.
# ============================================================================

testGapResolve(t: ref T)
{
	i: int;

	if(actid < 0) {
		t.skip("no activity");
		return;
	}

	ctxctl := actbase() + "/context/ctl";

	# Add a gap to resolve
	n := writefile(ctxctl, "gap upsert desc=test_resolve_target relevance=medium");
	t.assert(n > 0, "gap upsert for resolve test should succeed");

	# Count gaps (to verify count decreases after resolve)
	countbefore := 0;
	for(i = 0; i < 100; i++) {
		(ok, nil) := sys->stat(actbase() + "/context/gaps/" + string i);
		if(ok < 0) {
			countbefore = i;
			break;
		}
	}

	# Resolve by desc
	n = writefile(ctxctl, "gap resolve desc=test_resolve_target");
	t.assert(n > 0, "gap resolve should succeed");

	# Count after resolve — should have decreased by 1
	countafter := 0;
	for(i = 0; i < 100; i++) {
		(ok, nil) := sys->stat(actbase() + "/context/gaps/" + string i);
		if(ok < 0) {
			countafter = i;
			break;
		}
	}
	t.assert(countafter == countbefore - 1,
		sys->sprint("gap count should decrease from %d to %d, got %d",
			countbefore, countbefore - 1, countafter));

	# Verify the resolved gap is no longer findable
	found := 0;
	for(i = 0; i < countafter; i++) {
		g := readfile(actbase() + "/context/gaps/" + string i);
		if(g == nil)
			break;
		if(hassubstr(g, "test_resolve_target")) {
			found = 1;
			break;
		}
	}
	t.assert(found == 0, "resolved gap should not be findable in gaps/");

	# Resolve of non-existent gap should return error (n < 0)
	fd := sys->open(ctxctl, Sys->OWRITE);
	if(fd != nil) {
		cmd := array of byte "gap resolve desc=nonexistent_gap_xyz";
		sys->write(fd, cmd, len cmd);
		# The write should fail (server returns error)
		# We can't easily check the error string, but we verify gaps count unchanged
		fd = nil;
	}
	countfinal := 0;
	for(i = 0; i < 100; i++) {
		(ok, nil) := sys->stat(actbase() + "/context/gaps/" + string i);
		if(ok < 0) {
			countfinal = i;
			break;
		}
	}
	t.assert(countfinal == countafter, "failed resolve should not change gap count");
}

# ============================================================================
# Test 23: testCatalogRead
#
# Verify catalog/ directory is served and entries are readable.
# The catalog is populated from /lib/veltro/resources/*.resource files.
# If the directory has no files, the test skips (non-fatal).
# ============================================================================

testCatalogRead(t: ref T)
{
	# Verify catalog/ directory exists in the 9P namespace
	(st, nil) := sys->stat(TESTMNT + "/catalog");
	t.assert(st >= 0, "catalog/ directory should exist in /n/ui namespace");

	# Try to read first catalog entry
	s := readfile(TESTMNT + "/catalog/0");
	if(s == nil) {
		t.skip("no catalog entries (no *.resource files in /lib/veltro/resources/)");
		return;
	}

	t.log("catalog/0: " + s);
	# Entry should have name= field
	t.assert(hassubstr(s, "name="), "catalog entry should have name= field");
	# Entry should have type= field
	t.assert(hassubstr(s, "type="), "catalog entry should have type= field");
	# mount= field should NOT be present (it's internal)
	t.assert(!hassubstr(s, "mount="), "catalog entry should NOT expose mount= field");
}

# ============================================================================
# Helpers: strtoint (local copy, no dep on luciuisrv internals)
# ============================================================================

strtoint(s: string): int
{
	n := 0;
	if(len s == 0)
		return -1;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c < '0' || c > '9')
			return -1;
		n = n * 10 + (c - '0');
	}
	return n;
}

# Strip trailing whitespace/newlines (server appends \n to most file reads).
strip(s: string): string
{
	j := len s;
	while(j > 0 && s[j-1] <= ' ')
		j--;
	return s[0:j];
}

# ============================================================================
# Teardown: unmount the test server
# ============================================================================

teardown()
{
	sys->unmount(nil, TESTMNT);
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

	# Start server and create activity (must run first)
	run("Setup", testSetup);

	# Conversation tests
	run("ConvMessageWrite", testConvMessageWrite);
	run("ConvMessageUpdate", testConvMessageUpdate);
	run("ConvTextEmbeddedEquals", testConvTextEmbeddedEquals);
	run("ConvEventDelivery", testConvEventDelivery);
	run("ConvUpdateEvent", testConvUpdateEvent);
	run("ConvMultipleMessages", testMultipleMessages);
	run("ConvInput", testConvInput);

	# Presentation tests
	run("PresCreate", testPresentationCreate);
	run("PresDataWrite", testPresentationDataWrite);
	run("PresUpdate", testPresentationUpdate);
	run("PresAppend", testPresentationAppend);
	run("PresCenter", testPresentationCenter);
	run("PresEvent", testPresentationEvent);
	run("PresMultipleArtifacts", testMultipleArtifacts);

	# Context tests
	run("ContextResourceAdd", testContextResourceAdd);
	run("ContextGapAdd", testContextGapAdd);
	run("ContextBgTaskAdd", testContextBgTaskAdd);
	run("ContextResourceUpdate", testContextResourceUpdate);
	run("GapUpsert", testGapUpsert);
	run("GapResolve", testGapResolve);
	run("CatalogRead", testCatalogRead);

	# Activity metadata tests
	run("ActivityLabel", testActivityLabel);
	run("ActivityStatus", testActivityStatus);

	teardown();

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
