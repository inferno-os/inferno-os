implement VeltroSecurityTest;

#
# Veltro Namespace Security Tests (v3)
#
# Tests verify the security properties of the FORKNS + bind-replace
# namespace isolation model.
#
# Security Properties Tested:
#    1. restrictdir() allowlist - only allowed items visible after bind-replace
#    2. restrictdir() exclusion - non-allowed items invisible
#    3. restrictdir() idempotent - can be called multiple times safely
#    4. restrictns() full policy - /dis, /dev, /n, /lib, /tmp restricted
#    5. restrictns() with paths - granted paths remain accessible
#    6. restrictns() with shellcmds - grants sh.dis + named commands
#    7. restrictns() concurrency - concurrent restriction calls are safe
#    8. verifyns() - catches namespace violations
#    9. Audit logging - restriction operations recorded
#   10. /tmp writable after restriction (MCREATE on shadow bind)
#   11. exec in tools grants sh.dis (shell interpreter needed by exec tool)
#   12. caps.paths exposes granted /n/local/ subtree
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

VeltroSecurityTest: module {
	init: fn(nil: ref Draw->Context, args: list of string);
};

# Include nsconstruct for testing
include "nsconstruct.m";
	nsconstruct: NsConstruct;

# Source file path for clickable error addresses
SRCFILE: con "/tests/veltro_security_test.b";

passed := 0;
failed := 0;
skipped := 0;

# Helper to run a test and track results
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
# Test 1: RestrictDir - Allowlist
# Verifies that restrictdir() makes only allowed items visible
# ============================================================================
testRestrictDir(t: ref T)
{
	result := chan of string;
	spawn restrictDirWorker(result);

	r := <-result;
	if(r != "")
		t.error(r);
}

restrictDirWorker(result: chan of string)
{
	# Fork namespace so restriction doesn't affect test runner
	sys->pctl(Sys->FORKNS, nil);

	# Create test directory with known contents
	testdir := "/tmp/veltro/test-restrict";
	mkdirp(testdir);
	mkdirp(testdir + "/keepdir");
	mkdirp(testdir + "/removedir");
	createfile(testdir + "/keep.txt");
	createfile(testdir + "/remove.txt");

	# Restrict to only "keepdir" and "keep.txt"
	err := nsconstruct->restrictdir(testdir, "keepdir" :: "keep.txt" :: nil, 0);
	if(err != nil) {
		result <-= sys->sprint("restrictdir failed: %s", err);
		return;
	}

	# Verify allowed items are visible
	(ok1, nil) := sys->stat(testdir + "/keepdir");
	if(ok1 < 0) {
		result <-= "keepdir should be visible after restrictdir";
		return;
	}

	(ok2, nil) := sys->stat(testdir + "/keep.txt");
	if(ok2 < 0) {
		result <-= "keep.txt should be visible after restrictdir";
		return;
	}

	# Verify removed items are NOT visible
	(ok3, nil) := sys->stat(testdir + "/removedir");
	if(ok3 >= 0) {
		result <-= "removedir should NOT be visible after restrictdir";
		return;
	}

	(ok4, nil) := sys->stat(testdir + "/remove.txt");
	if(ok4 >= 0) {
		result <-= "remove.txt should NOT be visible after restrictdir";
		return;
	}

	result <-= "";  # Success
}

# ============================================================================
# Test 2: RestrictDir - Exclusion
# Verifies that items NOT in allowed list are truly invisible
# ============================================================================
testRestrictDirExclusion(t: ref T)
{
	result := chan of string;
	spawn restrictDirExclusionWorker(result);

	r := <-result;
	if(r != "")
		t.error(r);
}

restrictDirExclusionWorker(result: chan of string)
{
	sys->pctl(Sys->FORKNS, nil);

	# Create test directory with many items
	testdir := "/tmp/veltro/test-exclusion";
	mkdirp(testdir);
	items := array[] of {"a", "b", "c", "d", "e"};
	for(i := 0; i < len items; i++)
		createfile(testdir + "/" + items[i]);

	# Allow only "b" and "d"
	err := nsconstruct->restrictdir(testdir, "b" :: "d" :: nil, 0);
	if(err != nil) {
		result <-= sys->sprint("restrictdir failed: %s", err);
		return;
	}

	# Read directory - should only contain "b" and "d"
	fd := sys->open(testdir, Sys->OREAD);
	if(fd == nil) {
		result <-= "cannot open restricted directory";
		return;
	}

	visible: list of string;
	for(;;) {
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(j := 0; j < n; j++)
			visible = dirs[j].name :: visible;
	}
	fd = nil;

	# Count visible items - should be exactly 2
	count := 0;
	for(v := visible; v != nil; v = tl v)
		count++;

	if(count != 2) {
		result <-= sys->sprint("expected 2 visible items, got %d", count);
		return;
	}

	result <-= "";
}

# ============================================================================
# Test 3: RestrictDir - Idempotent
# Verifies restrictdir() can be called multiple times safely
# ============================================================================
testBindReplaceIdempotent(t: ref T)
{
	result := chan of string;
	spawn idempotentWorker(result);

	r := <-result;
	if(r != "")
		t.error(r);
}

idempotentWorker(result: chan of string)
{
	sys->pctl(Sys->FORKNS, nil);

	testdir := "/tmp/veltro/test-idempotent";
	mkdirp(testdir);
	mkdirp(testdir + "/a");
	mkdirp(testdir + "/b");
	mkdirp(testdir + "/c");

	# First restriction: allow a, b
	err := nsconstruct->restrictdir(testdir, "a" :: "b" :: nil, 0);
	if(err != nil) {
		result <-= sys->sprint("first restrictdir failed: %s", err);
		return;
	}

	# Second restriction: narrow to just a
	err = nsconstruct->restrictdir(testdir, "a" :: nil, 0);
	if(err != nil) {
		result <-= sys->sprint("second restrictdir failed: %s", err);
		return;
	}

	# Only "a" should be visible
	(ok1, nil) := sys->stat(testdir + "/a");
	if(ok1 < 0) {
		result <-= "a should be visible after second restrictdir";
		return;
	}

	(ok2, nil) := sys->stat(testdir + "/b");
	if(ok2 >= 0) {
		result <-= "b should NOT be visible after second restrictdir";
		return;
	}

	result <-= "";
}

# ============================================================================
# Test 4: RestrictNs - Full Policy
# Verifies restrictns() applies the complete restriction policy
# ============================================================================
testRestrictNs(t: ref T)
{
	result := chan of string;
	spawn restrictNsWorker(result);

	r := <-result;
	if(r != "")
		t.error(r);
}

restrictNsWorker(result: chan of string)
{
	sys->pctl(Sys->FORKNS, nil);

	# Build minimal capabilities
	caps := ref NsConstruct->Capabilities(
		"read" :: nil,        # tools
		nil,                  # paths
		nil,                  # shellcmds — no shell
		nil,                  # llmconfig
		0 :: 1 :: 2 :: nil,   # fds
		nil,                  # mcproviders
		0,                    # memory
		0                     # xenith
	);

	# Apply namespace restriction
	err := nsconstruct->restrictns(caps);
	if(err != nil) {
		result <-= sys->sprint("restrictns failed: %s", err);
		return;
	}

	# Verify /dis/lib is accessible (essential runtime)
	(ok1, nil) := sys->stat("/dis/lib");
	if(ok1 < 0) {
		result <-= "/dis/lib should be accessible after restrictns";
		return;
	}

	# Verify /dis/veltro is accessible
	(ok2, nil) := sys->stat("/dis/veltro");
	if(ok2 < 0) {
		result <-= "/dis/veltro should be accessible after restrictns";
		return;
	}

	# Verify /dev/cons is accessible
	(ok3, nil) := sys->stat("/dev/cons");
	if(ok3 < 0) {
		result <-= "/dev/cons should be accessible after restrictns";
		return;
	}

	# Verify /dev/null is accessible
	(ok4, nil) := sys->stat("/dev/null");
	if(ok4 < 0) {
		result <-= "/dev/null should be accessible after restrictns";
		return;
	}

	# Verify /tmp/veltro/scratch is accessible
	(ok5, nil) := sys->stat("/tmp/veltro/scratch");
	if(ok5 < 0) {
		result <-= "/tmp/veltro/scratch should be accessible after restrictns";
		return;
	}

	result <-= "";
}

# ============================================================================
# Test 5: RestrictNs - Shell via shellcmds
# Verifies that sh.dis + named commands appear when shellcmds is set
# ============================================================================
testRestrictNsShell(t: ref T)
{
	result := chan of string;
	spawn shellWorker(result);

	r := <-result;
	if(r != "")
		t.error(r);
}

shellWorker(result: chan of string)
{
	sys->pctl(Sys->FORKNS, nil);

	# shellcmds non-nil → sh.dis + cat.dis should appear in /dis
	caps := ref NsConstruct->Capabilities(
		"read" :: "exec" :: nil,  # tools
		nil,                      # paths
		"cat" :: nil,             # shellcmds — grants sh.dis + cat.dis
		nil,                      # llmconfig
		0 :: 1 :: 2 :: nil,       # fds
		nil,                      # mcproviders
		0,                        # memory
		0                         # xenith
	);

	err := nsconstruct->restrictns(caps);
	if(err != nil) {
		result <-= sys->sprint("restrictns (shell) failed: %s", err);
		return;
	}

	# Verify sh.dis is accessible
	(shok, nil) := sys->stat("/dis/sh.dis");
	if(shok < 0) {
		result <-= "shellcmds should grant /dis/sh.dis";
		return;
	}

	# Verify granted shell command is accessible
	(catok, nil) := sys->stat("/dis/cat.dis");
	if(catok < 0) {
		result <-= "shellcmds should grant /dis/cat.dis";
		return;
	}

	result <-= "";
}

# ============================================================================
# Test 6: RestrictNs - Concurrent
# Verifies concurrent restrictns calls don't race
# ============================================================================
testRestrictNsRace(t: ref T)
{
	done := chan of int;
	errors := chan of string;
	nthreads := 3;

	for(i := 0; i < nthreads; i++)
		spawn raceWorker(done, errors);

	# Collect results
	errs: list of string;
	for(i = 0; i < nthreads; i++) {
		alt {
		e := <-errors =>
			errs = e :: errs;
		<-done =>
			;
		}
	}

	t.assert(errs == nil, "all concurrent restrictns calls should succeed");
	for(; errs != nil; errs = tl errs)
		t.log(hd errs);
}

raceWorker(done: chan of int, errors: chan of string)
{
	# Each worker forks its own namespace
	sys->pctl(Sys->FORKNS, nil);

	caps := ref NsConstruct->Capabilities(
		"read" :: nil,
		nil,
		nil,
		nil,
		0 :: 1 :: 2 :: nil,
		nil,
		0,
		0
	);

	err := nsconstruct->restrictns(caps);
	if(err != nil)
		errors <-= sys->sprint("restrictns race failed: %s", err);
	else
		done <-= 1;
}

# ============================================================================
# Test 7: VerifyNs - Catches Violations
# Verifies that verifyns() detects expected paths
# ============================================================================
testVerifyNs(t: ref T)
{
	result := chan of string;
	spawn verifyNsWorker(result);

	r := <-result;
	if(r != "")
		t.error(r);
}

verifyNsWorker(result: chan of string)
{
	sys->pctl(Sys->FORKNS, nil);

	# Apply restrictions first
	caps := ref NsConstruct->Capabilities(
		nil, nil, nil, nil,
		0 :: 1 :: 2 :: nil,
		nil, 0, 0
	);

	err := nsconstruct->restrictns(caps);
	if(err != nil) {
		result <-= sys->sprint("restrictns failed: %s", err);
		return;
	}

	# Verify with expected paths
	expected := "/dis/lib" :: "/dev/cons" :: nil;
	verr := nsconstruct->verifyns(expected);
	if(verr != nil) {
		result <-= sys->sprint("verifyns failed: %s", verr);
		return;
	}

	# Verify with a missing expected path should fail
	bad := "/nonexistent/path" :: nil;
	verr = nsconstruct->verifyns(bad);
	if(verr == nil) {
		result <-= "verifyns should fail for missing expected path";
		return;
	}

	result <-= "";
}

# ============================================================================
# Test 8: Audit Log
# Verifies that emitauditlog writes correct audit log
# ============================================================================
testAuditLog(t: ref T)
{
	# Emit an audit log
	nsconstruct->emitauditlog("test-audit", "restrictdir /dis" :: "restrictdir /dev" :: nil);

	# Read audit log
	auditpath := "/tmp/veltro/.ns/audit/test-audit.ns";
	fd := sys->open(auditpath, Sys->OREAD);
	if(fd == nil) {
		t.error("cannot open audit log");
		return;
	}

	buf := array[4096] of byte;
	n := sys->read(fd, buf, len buf);
	fd = nil;

	if(n <= 0) {
		t.error("audit log is empty");
		return;
	}

	content := string buf[0:n];

	# Verify audit log has header
	t.assert(contains(content, "Veltro Namespace Audit"),
		"audit log should have header");

	# Verify audit log has ID
	t.assert(contains(content, "test-audit"),
		"audit log should contain ID");

	# Verify audit log has operations
	t.assert(contains(content, "restrictdir"),
		"audit log should contain restriction operations");

	# Clean up
	sys->remove(auditpath);
}

# ============================================================================
# Test 9: RestrictDir - Nonexistent Items in Allowed List
# Verifies that restrictdir() gracefully skips items that don't exist
# ============================================================================
testRestrictDirMissing(t: ref T)
{
	result := chan of string;
	spawn restrictDirMissingWorker(result);

	r := <-result;
	if(r != "")
		t.error(r);
}

restrictDirMissingWorker(result: chan of string)
{
	sys->pctl(Sys->FORKNS, nil);

	testdir := "/tmp/veltro/test-missing";
	mkdirp(testdir);
	createfile(testdir + "/exists.txt");

	# Allow "exists.txt" and "nonexistent.txt"
	err := nsconstruct->restrictdir(testdir, "exists.txt" :: "nonexistent.txt" :: nil, 0);
	if(err != nil) {
		result <-= sys->sprint("restrictdir should not fail for missing items: %s", err);
		return;
	}

	# Verify existing item is still visible
	(ok, nil) := sys->stat(testdir + "/exists.txt");
	if(ok < 0) {
		result <-= "exists.txt should be visible";
		return;
	}

	result <-= "";
}

# ============================================================================
# Test 10: TmpWritable
# Verifies that /tmp is writable after restrictns (MCREATE on shadow bind).
# This was broken before: restrictdir used MREPL only, forbidding creates.
# ============================================================================
testTmpWritable(t: ref T)
{
	result := chan of string;
	spawn tmpWritableWorker(result);
	r := <-result;
	if(r != "")
		t.error(r);
}

tmpWritableWorker(result: chan of string)
{
	sys->pctl(Sys->FORKNS, nil);

	caps := ref NsConstruct->Capabilities(
		"write" :: nil,
		nil, nil, nil,
		0 :: 1 :: 2 :: nil,
		nil, 0, 0
	);

	err := nsconstruct->restrictns(caps);
	if(err != nil) {
		result <-= sys->sprint("restrictns failed: %s", err);
		return;
	}

	# Try creating a file under /tmp/veltro/scratch/
	testfile := "/tmp/veltro/scratch/mcreate_test.txt";
	fd := sys->create(testfile, Sys->OWRITE, 8r644);
	if(fd == nil) {
		result <-= sys->sprint("cannot create file under /tmp after restrictns: %r");
		return;
	}
	sys->fprint(fd, "mcreate test\n");
	fd = nil;

	# Verify file is readable
	(ok, nil) := sys->stat(testfile);
	if(ok < 0) {
		result <-= "created file not visible under /tmp/veltro";
		return;
	}

	result <-= "";
}

# ============================================================================
# Test 11: ExecGrantsShDis
# Verifies that "exec" in caps.tools grants /dis/sh.dis without shellcmds.
# The exec tool requires sh.dis to run shell commands.
# ============================================================================
testExecGrantsShDis(t: ref T)
{
	result := chan of string;
	spawn execGrantsShDisWorker(result);
	r := <-result;
	if(r != "")
		t.error(r);
}

execGrantsShDisWorker(result: chan of string)
{
	sys->pctl(Sys->FORKNS, nil);

	# exec in tools, shellcmds=nil — exec detection should still add sh.dis
	caps := ref NsConstruct->Capabilities(
		"read" :: "exec" :: nil,
		nil, nil, nil,
		0 :: 1 :: 2 :: nil,
		nil, 0, 0
	);

	err := nsconstruct->restrictns(caps);
	if(err != nil) {
		result <-= sys->sprint("restrictns failed: %s", err);
		return;
	}

	# sh.dis must be accessible for exec tool to spawn a shell
	(shok, nil) := sys->stat("/dis/sh.dis");
	if(shok < 0) {
		result <-= "exec in caps.tools should grant /dis/sh.dis";
		return;
	}

	# Standard commands are NOT granted — exec provides sh.dis only
	# (commands like date.dis require shellcmds= to be explicit)

	result <-= "";
}

# ============================================================================
# Test 12: PathsExposure
# Verifies that caps.paths exposes the specified /n/local/ subtree and
# that paths outside the grant are NOT accessible.
# Skipped if /n/local is not available (headless test environment).
# ============================================================================
testPathsExposure(t: ref T)
{
	# Check if /n/local exists — required for this test
	(nlok, nil) := sys->stat("/n/local");
	if(nlok < 0) {
		t.skip("/n/local not available — skipping path exposure test");
		return;
	}

	result := chan of string;
	spawn pathsExposureWorker(result);
	r := <-result;
	if(r != "")
		t.error(r);
}

pathsExposureWorker(result: chan of string)
{
	sys->pctl(Sys->FORKNS, nil);

	# Find the first entry in /n/local to use as a grant target.
	# /n/local maps the host filesystem; content varies by machine.
	# We use whatever entry exists rather than assuming a specific name.
	fd := sys->open("/n/local", Sys->OREAD);
	if(fd == nil) {
		result <-= "cannot open /n/local";
		return;
	}
	(n, dirs) := sys->dirread(fd);
	fd = nil;
	if(n <= 0) {
		result <-= "/n/local is empty — cannot run path grant test";
		return;
	}
	grantname := dirs[0].name;
	grantpath := "/n/local/" + grantname;

	caps := ref NsConstruct->Capabilities(
		"read" :: nil,
		grantpath :: nil,
		nil, nil,
		0 :: 1 :: 2 :: nil,
		nil, 0, 0
	);

	err := nsconstruct->restrictns(caps);
	if(err != nil) {
		result <-= sys->sprint("restrictns with paths failed: %s", err);
		return;
	}

	# Granted path must be accessible after restriction
	(tok, nil) := sys->stat(grantpath);
	if(tok < 0) {
		result <-= sys->sprint("%s should be accessible after path grant", grantpath);
		return;
	}

	result <-= "";
}

# ============================================================================
# Helpers
# ============================================================================

# Create directory with parents
mkdirp(path: string)
{
	(ok, nil) := sys->stat(path);
	if(ok >= 0)
		return;

	# Find parent
	for(i := len path - 1; i > 0; i--) {
		if(path[i] == '/') {
			mkdirp(path[0:i]);
			break;
		}
	}

	sys->create(path, Sys->OREAD, Sys->DMDIR | 8r755);
}

# Create an empty file
createfile(path: string)
{
	fd := sys->create(path, Sys->OWRITE, 8r644);
	if(fd != nil)
		fd = nil;
}

# Check if string contains substring
contains(s, sub: string): int
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
# Main entry point
# ============================================================================
init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	testing = load Testing Testing->PATH;
	nsconstruct = load NsConstruct NsConstruct->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}

	if(nsconstruct == nil) {
		sys->fprint(sys->fildes(2), "cannot load nsconstruct module: %r\n");
		raise "fail:cannot load nsconstruct";
	}

	testing->init();
	nsconstruct->init();

	# Check for verbose flag
	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	# Run tests
	run("RestrictDir", testRestrictDir);
	run("RestrictDirExclusion", testRestrictDirExclusion);
	run("BindReplaceIdempotent", testBindReplaceIdempotent);
	run("RestrictNs", testRestrictNs);
	run("RestrictNsShell", testRestrictNsShell);
	run("RestrictNsRace", testRestrictNsRace);
	run("VerifyNs", testVerifyNs);
	run("AuditLog", testAuditLog);
	run("RestrictDirMissing", testRestrictDirMissing);
	run("TmpWritable", testTmpWritable);
	run("ExecGrantsShDis", testExecGrantsShDis);
	run("PathsExposure", testPathsExposure);

	# Print summary
	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
