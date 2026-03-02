implement Gitrm;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "arg.m";
	arg: Arg;

include "git.m";
	git: Git;
	IndexEntry: import git;

Gitrm: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

stderr: ref Sys->FD;
gitdir: string;
reporoot: string;

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
	arg->setusage(arg->progname() + " [-c] path [path ...]");

	cached := 0;
	while((ch := arg->opt()) != 0)
		case ch {
		'c' =>
			cached = 1;
		* =>
			arg->usage();
		}

	argv := arg->argv();
	if(argv == nil)
		arg->usage();

	# Find .git by walking up from first argument
	firstpath := hd argv;
	startdir := dirof(firstpath);
	gitdir = git->findgitdir(startdir);
	if(gitdir == nil)
		fail("not a git repository");

	if(len gitdir > 5 && gitdir[len gitdir - 5:] == "/.git")
		reporoot = gitdir[:len gitdir - 5];
	else
		reporoot = ".";

	# Load existing index
	(entries, lerr) := git->loadindex(gitdir);
	if(lerr != nil)
		fail("loadindex: " + lerr);

	# Process each path
	removed := 0;
	for(; argv != nil; argv = tl argv) {
		path := hd argv;
		relpath := relativepath(path);

		# Filter out matching entries (exact + prefix for dirs)
		newentries: list of IndexEntry;
		found := 0;
		for(el := entries; el != nil; el = tl el) {
			e := hd el;
			if(e.path == relpath || hasprefix(e.path, relpath + "/")) {
				found = 1;
				removed++;
				if(!cached)
					sys->remove(path);
			} else {
				newentries = e :: newentries;
			}
		}

		if(!found)
			sys->fprint(stderr, "git/rm: not in index: %s\n", relpath);

		# Reverse to maintain order
		entries = nil;
		for(; newentries != nil; newentries = tl newentries)
			entries = (hd newentries) :: entries;
	}

	if(removed == 0)
		fail("no files removed");

	# Save updated index
	serr := git->saveindex(gitdir, entries);
	if(serr != nil)
		fail("saveindex: " + serr);

	sys->print("rm %d file(s)\n", removed);
}

dirof(path: string): string
{
	(rc, dir) := sys->stat(path);
	if(rc >= 0 && (dir.qid.qtype & Sys->QTDIR))
		return path;
	for(i := len path - 1; i >= 0; i--)
		if(path[i] == '/')
			return path[:i];
	return ".";
}

relativepath(filepath: string): string
{
	prefix := reporoot + "/";
	if(len filepath > len prefix && filepath[:len prefix] == prefix)
		return filepath[len prefix:];
	if(len filepath >= 2 && filepath[:2] == "./")
		return filepath[2:];
	return filepath;
}

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[:len prefix] == prefix;
}

fail(msg: string)
{
	sys->fprint(stderr, "git/rm: %s\n", msg);
	raise "fail:" + msg;
}
