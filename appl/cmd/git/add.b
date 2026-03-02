implement Gitadd;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "arg.m";
	arg: Arg;

include "git.m";
	git: Git;
	Hash, IndexEntry: import git;

Gitadd: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

stderr: ref Sys->FD;
gitdir: string;
reporoot: string;   # directory containing .git

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	arg = load Arg Arg->PATH;
	git = load Git Git->PATH;
	if(git == nil)
		fail(sprint("load Git: %r"));

	err := git->init();
	if(err != nil)
		fail("git init: " + err);

	arg->init(args);
	arg->setusage(arg->progname() + " [-v] path [path ...]");

	verbose := 0;
	while((ch := arg->opt()) != 0)
		case ch {
		'v' =>
			verbose = 1;
		* =>
			arg->usage();
		}

	argv := arg->argv();
	if(argv == nil)
		arg->usage();

	# Find .git by walking up from the first argument's directory
	firstpath := hd argv;
	startdir := dirof(firstpath);
	gitdir = git->findgitdir(startdir);
	if(gitdir == nil)
		fail("not a git repository");

	# Repo root is gitdir without "/.git" suffix
	if(len gitdir > 5 && gitdir[len gitdir - 5:] == "/.git")
		reporoot = gitdir[:len gitdir - 5];
	else
		reporoot = ".";

	# Load existing index
	(entries, lerr) := git->loadindex(gitdir);
	if(lerr != nil)
		fail("loadindex: " + lerr);

	# Process each path argument
	for(; argv != nil; argv = tl argv) {
		path := hd argv;
		entries = addpath(path, entries, verbose);
	}

	# Save updated index
	serr := git->saveindex(gitdir, entries);
	if(serr != nil)
		fail("saveindex: " + serr);
}

# Return the directory part of a path, or "." if no directory.
dirof(path: string): string
{
	# Check if it's a directory itself
	(rc, dir) := sys->stat(path);
	if(rc >= 0 && (dir.qid.qtype & Sys->QTDIR))
		return path;

	# Find last /
	for(i := len path - 1; i >= 0; i--)
		if(path[i] == '/')
			return path[:i];
	return ".";
}

addpath(path: string, entries: list of IndexEntry, verbose: int): list of IndexEntry
{
	(rc, dir) := sys->stat(path);
	if(rc < 0)
		fail(sprint("stat %s: %r", path));

	if(dir.qid.qtype & Sys->QTDIR)
		return adddir(path, entries, verbose);

	return addfile(path, entries, verbose);
}

adddir(dirpath: string, entries: list of IndexEntry, verbose: int): list of IndexEntry
{
	fd := sys->open(dirpath, Sys->OREAD);
	if(fd == nil)
		return entries;

	for(;;) {
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++) {
			name := dirs[i].name;
			if(name == ".git")
				continue;

			fullpath := dirpath + "/" + name;
			if(dirs[i].qid.qtype & Sys->QTDIR)
				entries = adddir(fullpath, entries, verbose);
			else
				entries = addfile(fullpath, entries, verbose);
		}
	}
	return entries;
}

addfile(filepath: string, entries: list of IndexEntry, verbose: int): list of IndexEntry
{
	# Read file
	fd := sys->open(filepath, Sys->OREAD);
	if(fd == nil)
		fail(sprint("open %s: %r", filepath));
	(rc, dir) := sys->fstat(fd);
	if(rc < 0)
		fail(sprint("fstat %s: %r", filepath));

	size := int dir.length;
	data := array [size] of byte;
	total := 0;
	while(total < size) {
		n := sys->read(fd, data[total:], size - total);
		if(n <= 0)
			break;
		total += n;
	}
	data = data[:total];

	# Write loose blob object
	(h, werr) := git->writelooseobj(gitdir, git->OBJ_BLOB, data);
	if(werr != nil)
		fail("writelooseobj " + filepath + ": " + werr);

	# Determine mode
	mode := 8r100644;
	if(dir.mode & 8r111)
		mode = 8r100755;

	# Compute path relative to repo root
	relpath := relativepath(filepath);

	if(verbose)
		sys->fprint(stderr, "add %s (%s)\n", relpath, h.hex()[:7]);

	# Update index: replace existing entry or add new one
	e: IndexEntry;
	e.mode = mode;
	e.hash = h;
	e.path = relpath;

	result: list of IndexEntry;
	replaced := 0;
	for(el := entries; el != nil; el = tl el) {
		existing := hd el;
		if(existing.path == relpath) {
			result = e :: result;
			replaced = 1;
		} else
			result = existing :: result;
	}
	if(!replaced)
		result = e :: result;

	# Reverse to maintain order
	entries = nil;
	for(; result != nil; result = tl result)
		entries = (hd result) :: entries;

	return entries;
}

# Compute path relative to repo root.
# E.g. reporoot="/tmp/hw", filepath="/tmp/hw/README" → "README"
relativepath(filepath: string): string
{
	prefix := reporoot + "/";
	if(len filepath > len prefix && filepath[:len prefix] == prefix)
		return filepath[len prefix:];

	# Fallback: strip leading "./"
	if(len filepath >= 2 && filepath[:2] == "./")
		return filepath[2:];
	return filepath;
}

fail(msg: string)
{
	sys->fprint(stderr, "git/add: %s\n", msg);
	raise "fail:" + msg;
}
