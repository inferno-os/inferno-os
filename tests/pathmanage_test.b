implement PathManageTest;

#
# tests/pathmanage_test.b
#
# Tests for unified dynamic path management:
#   - tools9p /tool/paths file and bindpath/unbindpath ctl commands
#   - lucibridge applypathchanges() logic (namespace bind/unmount)
#
# Requires tools9p to be running (mounted at /tool).
# Run: emu -r$ROOT /tests/pathmanage_test.dis
#

include "sys.m";
	sys: Sys;
include "draw.m";
include "testing.m";
	testing: Testing;
	T: import testing;

PathManageTest: module {
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/pathmanage_test.b";
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

writefile(path, content: string): int
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil)
		return -1;
	b := array of byte content;
	return sys->write(fd, b, len b);
}

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[4096] of byte;
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

# ── tools9p /tool/paths state management ─────────────────────────────────────

testBindpathCtl(t: ref T)
{
	if(sys->stat("/tool/tools").t0 < 0) {
		t.skip("tools9p not mounted at /tool");
		return;
	}

	# Write a bindpath command
	r := writefile("/tool/ctl", "bindpath /tmp/testpath");
	t.assert(r >= 0, "write bindpath to /tool/ctl succeeds");

	# /tool/paths should now contain /tmp/testpath
	paths := readfile("/tool/paths");
	t.assert(paths != nil, "/tool/paths is readable");
	t.assert(strcontains(paths, "/tmp/testpath"), "/tool/paths contains bound path");

	# Idempotent: binding the same path again should not duplicate it
	writefile("/tool/ctl", "bindpath /tmp/testpath");
	paths2 := readfile("/tool/paths");
	count := 0;
	i := 0;
	while(i + len "/tmp/testpath" <= len paths2) {
		if(paths2[i:i+len "/tmp/testpath"] == "/tmp/testpath") {
			count++;
			i += len "/tmp/testpath";
		} else
			i++;
	}
	t.assert(count == 1, "duplicate bindpath does not add duplicate entry");
}

testUnbindpathCtl(t: ref T)
{
	if(sys->stat("/tool/tools").t0 < 0) {
		t.skip("tools9p not mounted at /tool");
		return;
	}

	# Ensure path is bound first
	writefile("/tool/ctl", "bindpath /tmp/rmpath");
	paths := readfile("/tool/paths");
	t.assert(strcontains(paths, "/tmp/rmpath"), "path present before unbind");

	# Unbind it
	r := writefile("/tool/ctl", "unbindpath /tmp/rmpath");
	t.assert(r >= 0, "write unbindpath to /tool/ctl succeeds");

	paths2 := readfile("/tool/paths");
	t.assert(!strcontains(paths2, "/tmp/rmpath"), "/tool/paths no longer contains removed path");
}

testUnbindpathNonexistent(t: ref T)
{
	if(sys->stat("/tool/tools").t0 < 0) {
		t.skip("tools9p not mounted at /tool");
		return;
	}

	# Unbinding a path that was never bound should succeed silently
	r := writefile("/tool/ctl", "unbindpath /tmp/nosuchpath");
	t.assert(r >= 0, "unbind of nonexistent path does not error");

	paths := readfile("/tool/paths");
	t.assert(!strcontains(paths, "/tmp/nosuchpath"), "nonexistent path not in /tool/paths");
}

testMultiplePaths(t: ref T)
{
	if(sys->stat("/tool/tools").t0 < 0) {
		t.skip("tools9p not mounted at /tool");
		return;
	}

	# Bind multiple paths
	writefile("/tool/ctl", "bindpath /tmp/alpha");
	writefile("/tool/ctl", "bindpath /tmp/beta");
	writefile("/tool/ctl", "bindpath /tmp/gamma");

	paths := readfile("/tool/paths");
	t.assert(strcontains(paths, "/tmp/alpha"), "alpha in /tool/paths");
	t.assert(strcontains(paths, "/tmp/beta"),  "beta in /tool/paths");
	t.assert(strcontains(paths, "/tmp/gamma"), "gamma in /tool/paths");

	# Remove one; others remain
	writefile("/tool/ctl", "unbindpath /tmp/beta");
	paths2 := readfile("/tool/paths");
	t.assert(strcontains(paths2, "/tmp/alpha"),  "alpha still present after removing beta");
	t.assert(!strcontains(paths2, "/tmp/beta"),  "beta removed");
	t.assert(strcontains(paths2, "/tmp/gamma"), "gamma still present after removing beta");

	# Cleanup
	writefile("/tool/ctl", "unbindpath /tmp/alpha");
	writefile("/tool/ctl", "unbindpath /tmp/gamma");
}

# ── /n/local/ namespace binding (requires lucibridge process) ─────────────────

testLocalBindVisible(t: ref T)
{
	# This test checks that a path registered in /tool/paths actually
	# becomes visible under /n/local/ in the current namespace.
	# In a real session lucibridge calls applypathchanges(); here we
	# exercise the bind directly to verify the path is accessible.

	# Use /tmp as the test path (guaranteed to exist)
	testpath := "/tmp";
	target := "/n/local/tmp";

	# Bind it
	r := sys->bind(testpath, target, Sys->MBEFORE);
	if(r < 0) {
		t.skip("cannot bind /tmp into /n/local/tmp (namespace may be restricted)");
		return;
	}

	# Verify it is visible
	(ok, nil) := sys->stat(target);
	t.assert(ok >= 0, "/n/local/tmp is stat-able after bind");

	# Cleanup
	sys->unmount(nil, target);

	(ok2, nil) := sys->stat(target);
	t.assert(ok2 < 0, "/n/local/tmp gone after unmount");
}

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

	run("bindpath ctl command",      testBindpathCtl);
	run("unbindpath ctl command",    testUnbindpathCtl);
	run("unbind nonexistent path",   testUnbindpathNonexistent);
	run("multiple paths",            testMultiplePaths);
	run("/n/local/ bind visible",    testLocalBindVisible);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
