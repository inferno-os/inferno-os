implement CowfsTest;

#
# cowfs_test.b - Unit tests for copy-on-write filesystem
#
# Tests the cowfs module's core operations: read-through, write redirect,
# delete+whiteout, directory merge, promote, revert, and diff.
#
# Each test creates isolated base and overlay directories under /tmp/veltro/cowtest/
# and mounts cowfs to verify the overlay semantics.
#
# TODO: This test hangs the runner — the cowfs file2chan server does not shut
#       down after the test completes, blocking the next test from starting.
#       Needs an explicit unmount/teardown or a timeout wrapper.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "readdir.m";
	readdir: Readdir;

include "testing.m";
	testing: Testing;
	T: import testing;

include "cowfs.m";
	cowfs: Cowfs;

CowfsTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/cowfs_test.b";

passed := 0;
failed := 0;
skipped := 0;

TESTBASE: con "/tmp/veltro/cowtest";

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

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	testing = load Testing Testing->PATH;
	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}
	testing->init();

	readdir = load Readdir Readdir->PATH;
	if(readdir == nil) {
		sys->fprint(sys->fildes(2), "cannot load readdir module: %r\n");
		raise "fail:cannot load readdir";
	}

	cowfs = load Cowfs Cowfs->PATH;
	if(cowfs == nil) {
		sys->fprint(sys->fildes(2), "cannot load cowfs module: %r\n");
		raise "fail:cannot load cowfs";
	}

	for(a := args; a != nil; a = tl a)
		if(hd a == "-v")
			testing->verbose(1);

	# Create test root
	mkdirp(TESTBASE);

	run("ReadThrough", testReadThrough);
	run("WriteRedirect", testWriteRedirect);
	run("ReadAfterWrite", testReadAfterWrite);
	run("DeleteWhiteout", testDeleteWhiteout);
	run("NewFileCreation", testNewFileCreation);
	run("DirectoryMerge", testDirectoryMerge);
	run("CopyUpOnWrite", testCopyUpOnWrite);
	run("Promote", testPromote);
	run("Revert", testRevert);
	run("DiffListing", testDiffListing);
	run("PerFilePromote", testPerFilePromote);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}

# --- Test helpers ---

# Create a fresh base + overlay, mount cowfs, return (basedir, overlaydir, mntpoint)
setup(t: ref T, name: string): (string, string, string)
{
	basedir := TESTBASE + "/" + name + "/base";
	overlaydir := TESTBASE + "/" + name + "/overlay";
	mntpoint := TESTBASE + "/" + name + "/mnt";

	# Clean previous run
	removetree(basedir);
	removetree(overlaydir);
	removetree(mntpoint);

	mkdirp(basedir);
	mkdirp(overlaydir);
	mkdirp(mntpoint);

	return (basedir, overlaydir, mntpoint);
}

# Mount cowfs over mntpoint
mountcow(t: ref T, basedir, overlaydir, mntpoint: string)
{
	# Bind base to mntpoint first (so cowfs can read from it)
	if(sys->bind(basedir, mntpoint, Sys->MREPL) < 0)
		t.fatal(sys->sprint("bind base to mnt: %r"));

	(mntfd, err) := cowfs->start(mntpoint, overlaydir);
	if(err != nil)
		t.fatal("cowfs start: " + err);

	if(sys->mount(mntfd, nil, mntpoint, Sys->MREPL, nil) < 0)
		t.fatal(sys->sprint("cowfs mount: %r"));
}

# Write a string to a file
writefile(path, content: string)
{
	fd := sys->create(path, Sys->OWRITE, 8r644);
	if(fd == nil)
		return;
	data := array of byte content;
	sys->write(fd, data, len data);
}

# Read a file's contents
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

# Check if a file exists
fileexists(path: string): int
{
	(ok, nil) := sys->stat(path);
	return ok >= 0;
}

# --- Tests ---

# Test 1: Unmodified file reads from base
testReadThrough(t: ref T)
{
	(basedir, overlaydir, mntpoint) := setup(t, "readthrough");

	# Create a file in base
	writefile(basedir + "/hello.txt", "hello world");

	mountcow(t, basedir, overlaydir, mntpoint);

	# Read through cowfs should return base content
	content := readfile(mntpoint + "/hello.txt");
	t.assertseq(content, "hello world", "read-through returns base content");

	# Overlay should be empty (no modifications)
	t.assert(!fileexists(overlaydir + "/hello.txt"), "overlay file should not exist");
}

# Test 2: Write lands in overlay, base unchanged
testWriteRedirect(t: ref T)
{
	(basedir, overlaydir, mntpoint) := setup(t, "writeredirect");

	writefile(basedir + "/data.txt", "original");
	mountcow(t, basedir, overlaydir, mntpoint);

	# Write through cowfs
	writefile(mntpoint + "/data.txt", "modified");

	# Base should be unchanged
	t.assertseq(readfile(basedir + "/data.txt"), "original", "base unchanged after write");

	# Overlay should have the modified version
	t.assert(fileexists(overlaydir + "/data.txt"), "overlay file should exist");
}

# Test 3: Read modified version from overlay
testReadAfterWrite(t: ref T)
{
	(basedir, overlaydir, mntpoint) := setup(t, "readafterwrite");

	writefile(basedir + "/file.txt", "before");
	mountcow(t, basedir, overlaydir, mntpoint);

	# Write through cowfs
	writefile(mntpoint + "/file.txt", "after");

	# Read should return overlay version
	content := readfile(mntpoint + "/file.txt");
	t.assertseq(content, "after", "read after write returns overlay content");
}

# Test 4: Delete + whiteout (deleted file invisible, base unchanged)
testDeleteWhiteout(t: ref T)
{
	(basedir, overlaydir, mntpoint) := setup(t, "deletewhiteout");

	writefile(basedir + "/removeme.txt", "to be deleted");
	mountcow(t, basedir, overlaydir, mntpoint);

	# Remove through cowfs
	if(sys->remove(mntpoint + "/removeme.txt") < 0)
		t.fatal(sys->sprint("remove through cowfs: %r"));

	# File should be invisible through cowfs
	t.assert(!fileexists(mntpoint + "/removeme.txt"), "deleted file invisible through cowfs");

	# Base should still have the file
	t.assert(fileexists(basedir + "/removeme.txt"), "base file unchanged after delete");
}

# Test 5: New file only in overlay
testNewFileCreation(t: ref T)
{
	(basedir, overlaydir, mntpoint) := setup(t, "newfile");

	mountcow(t, basedir, overlaydir, mntpoint);

	# Create a new file through cowfs
	fd := sys->create(mntpoint + "/newfile.txt", Sys->OWRITE, 8r644);
	if(fd == nil)
		t.fatal(sys->sprint("create through cowfs: %r"));
	data := array of byte "brand new";
	sys->write(fd, data, len data);
	fd = nil;

	# New file should be readable
	content := readfile(mntpoint + "/newfile.txt");
	t.assertseq(content, "brand new", "new file readable through cowfs");

	# Base should not have it
	t.assert(!fileexists(basedir + "/newfile.txt"), "new file not in base");

	# Overlay should have it
	t.assert(fileexists(overlaydir + "/newfile.txt"), "new file in overlay");
}

# Test 6: Directory merge (overlay + base - whiteouts)
testDirectoryMerge(t: ref T)
{
	(basedir, overlaydir, mntpoint) := setup(t, "dirmerge");

	# Base has two files
	writefile(basedir + "/a.txt", "aaa");
	writefile(basedir + "/b.txt", "bbb");

	mountcow(t, basedir, overlaydir, mntpoint);

	# Create a new file through cowfs (will be in overlay only)
	fd := sys->create(mntpoint + "/c.txt", Sys->OWRITE, 8r644);
	if(fd != nil) {
		cdata := array of byte "ccc";
		sys->write(fd, cdata, len cdata);
		fd = nil;
	}

	# Directory listing should show all three
	(dirs, n) := readdir->init(mntpoint, Readdir->NAME);
	t.log(sys->sprint("dir merge: %d entries", n));

	names: list of string;
	for(i := 0; i < n; i++) {
		names = dirs[i].name :: names;
		t.log(sys->sprint("  entry: %s", dirs[i].name));
	}

	t.assert(inlist("a.txt", names), "base file a.txt visible");
	t.assert(inlist("b.txt", names), "base file b.txt visible");
	t.assert(inlist("c.txt", names), "overlay file c.txt visible");
}

# Test 7: Copy-up on first write (base file copied to overlay before edit)
testCopyUpOnWrite(t: ref T)
{
	(basedir, overlaydir, mntpoint) := setup(t, "copyup");

	writefile(basedir + "/existing.txt", "original content here");
	mountcow(t, basedir, overlaydir, mntpoint);

	# Write to existing file through cowfs
	writefile(mntpoint + "/existing.txt", "updated content here");

	# Overlay should have the file (copy-up happened)
	t.assert(fileexists(overlaydir + "/existing.txt"), "overlay has copy-up file");

	# Read through cowfs should return updated version
	content := readfile(mntpoint + "/existing.txt");
	t.assertseq(content, "updated content here", "read returns updated content");

	# Base unchanged
	t.assertseq(readfile(basedir + "/existing.txt"), "original content here", "base unchanged");
}

# Test 8: Promote (overlay → base, overlay cleared)
testPromote(t: ref T)
{
	(basedir, overlaydir, _) := setup(t, "promote");

	writefile(basedir + "/keep.txt", "original");

	# Simulate overlay modification (direct — not via Styx)
	writefile(overlaydir + "/keep.txt", "promoted version");

	mkdirp(overlaydir);
	# Write metadata so diff/promote can find basepath
	metafd := sys->create(overlaydir + "/.cowmeta", Sys->OWRITE, 8r644);
	if(metafd != nil) {
		mdata := array of byte ("basepath=" + basedir + "\n");
		sys->write(metafd, mdata, len mdata);
		metafd = nil;
	}

	(count, err) := cowfs->promote(basedir, overlaydir);
	if(err != nil)
		t.fatal("promote: " + err);

	t.log(sys->sprint("promoted %d files", count));
	t.assert(count > 0, "promote count > 0");

	# Base should now have promoted content
	t.assertseq(readfile(basedir + "/keep.txt"), "promoted version", "base has promoted content");

	# Overlay should be cleared
	t.assert(!fileexists(overlaydir + "/keep.txt"), "overlay cleared after promote");
}

# Test 9: Revert (overlay discarded, base unchanged)
testRevert(t: ref T)
{
	(basedir, overlaydir, _) := setup(t, "revert");

	writefile(basedir + "/safe.txt", "safe content");

	# Simulate overlay modification
	writefile(overlaydir + "/safe.txt", "dangerous change");
	writefile(overlaydir + "/extra.txt", "unwanted file");

	err := cowfs->revert(overlaydir);
	if(err != nil)
		t.fatal("revert: " + err);

	# Base unchanged
	t.assertseq(readfile(basedir + "/safe.txt"), "safe content", "base unchanged after revert");

	# Overlay cleared
	t.assert(!fileexists(overlaydir + "/safe.txt"), "overlay safe.txt cleared");
	t.assert(!fileexists(overlaydir + "/extra.txt"), "overlay extra.txt cleared");
}

# Test 10: Diff listing (M/A/D entries)
testDiffListing(t: ref T)
{
	(basedir, overlaydir, _) := setup(t, "diff");

	writefile(basedir + "/existing.txt", "original");

	# Simulate overlay: modify existing, add new
	writefile(overlaydir + "/existing.txt", "changed");
	writefile(overlaydir + "/added.txt", "new file");

	# Write metadata
	metafd := sys->create(overlaydir + "/.cowmeta", Sys->OWRITE, 8r644);
	if(metafd != nil) {
		mdata := array of byte ("basepath=" + basedir + "\n");
		sys->write(metafd, mdata, len mdata);
		metafd = nil;
	}

	# Add a whiteout entry
	whfd := sys->create(overlaydir + "/.whiteout", Sys->OWRITE, 8r644);
	if(whfd != nil) {
		wdata := array of byte "removed.txt\n";
		sys->write(whfd, wdata, len wdata);
		whfd = nil;
	}

	entries := cowfs->diff(overlaydir);

	t.log(sys->sprint("diff: %d entries", listlen(entries)));
	for(e := entries; e != nil; e = tl e)
		t.log("  " + hd e);

	# Should have M, A, and D entries
	hasM := 0;
	hasA := 0;
	hasD := 0;
	for(e = entries; e != nil; e = tl e) {
		s := hd e;
		if(len s > 2) {
			if(s[0] == 'M')
				hasM = 1;
			if(s[0] == 'A')
				hasA = 1;
			if(s[0] == 'D')
				hasD = 1;
		}
	}

	t.assert(hasM, "diff has M (modified) entry");
	t.assert(hasA, "diff has A (added) entry");
	t.assert(hasD, "diff has D (deleted/whiteout) entry");
}

# Test 11: Per-file promote/revert
testPerFilePromote(t: ref T)
{
	(basedir, overlaydir, _) := setup(t, "perfile");

	writefile(basedir + "/a.txt", "a-original");
	writefile(basedir + "/b.txt", "b-original");

	# Simulate overlay modifications
	writefile(overlaydir + "/a.txt", "a-modified");
	writefile(overlaydir + "/b.txt", "b-modified");

	# Promote only a.txt
	err := cowfs->promotefile(basedir, overlaydir, "a.txt");
	if(err != nil)
		t.fatal("promotefile a.txt: " + err);

	# a.txt should be promoted
	t.assertseq(readfile(basedir + "/a.txt"), "a-modified", "a.txt promoted");
	# b.txt should still be original
	t.assertseq(readfile(basedir + "/b.txt"), "b-original", "b.txt not promoted");

	# a.txt should be removed from overlay
	t.assert(!fileexists(overlaydir + "/a.txt"), "a.txt removed from overlay");

	# Revert b.txt
	err = cowfs->revertfile(overlaydir, "b.txt");
	if(err != nil)
		t.fatal("revertfile b.txt: " + err);

	# b.txt should be removed from overlay
	t.assert(!fileexists(overlaydir + "/b.txt"), "b.txt removed from overlay");
	# b.txt base unchanged
	t.assertseq(readfile(basedir + "/b.txt"), "b-original", "b.txt base unchanged");
}

# --- Utility helpers ---

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

	fd := sys->create(path, Sys->OREAD, 8r755 | Sys->DMDIR);
	if(fd != nil)
		fd = nil;
}

removetree(path: string)
{
	(ok, dir) := sys->stat(path);
	if(ok < 0)
		return;

	if(dir.mode & Sys->DMDIR) {
		(dirs, n) := readdir->init(path, Readdir->NONE);
		for(i := 0; i < n; i++)
			removetree(path + "/" + dirs[i].name);
	}
	sys->remove(path);
}

inlist(s: string, l: list of string): int
{
	for(; l != nil; l = tl l)
		if(hd l == s)
			return 1;
	return 0;
}

listlen(l: list of string): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}
