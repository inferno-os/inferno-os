implement Gitcommit;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "arg.m";
	arg: Arg;
include "daytime.m";
	daytime: Daytime;

include "git.m";
	git: Git;
	Hash, Repo, Commit, TreeEntry, IndexEntry: import git;

Gitcommit: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

stderr: ref Sys->FD;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	arg = load Arg Arg->PATH;
	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		fail(sprint("load Daytime: %r"));

	git = load Git Git->PATH;
	if(git == nil)
		fail(sprint("load Git: %r"));

	err := git->init();
	if(err != nil)
		fail("git init: " + err);

	arg->init(args);
	arg->setusage(arg->progname() + " -m 'message' [dir]");

	msg: string;
	verbose := 0;
	while((ch := arg->opt()) != 0)
		case ch {
		'm' =>
			msg = arg->earg();
		'v' =>
			verbose = 1;
		* =>
			arg->usage();
		}

	if(msg == nil)
		fail("commit message required (-m)");

	argv := arg->argv();
	dir := ".";
	if(len argv >= 1)
		dir = hd argv;

	gitdir := git->findgitdir(dir);
	if(gitdir == nil)
		fail("not a git repository");

	(repo, oerr) := git->openrepo(gitdir);
	if(oerr != nil)
		fail("openrepo: " + oerr);

	# Load index
	(entries, lerr) := git->loadindex(gitdir);
	if(lerr != nil)
		fail("loadindex: " + lerr);

	if(entries == nil)
		fail("nothing to commit (empty index; use git/add first)");

	# Build tree hierarchy from index entries
	roothash := buildtree(gitdir, entries, verbose);

	# Get parent commit (current HEAD)
	(headref, herr) := repo.head();
	if(herr != nil)
		fail("HEAD: " + herr);

	parenthash := git->nullhash();
	(ph, prerr) := repo.readref(headref);
	if(prerr == nil)
		parenthash = ph;

	# Build author/committer identity
	identity := getidentity(gitdir);
	now := daytime->now();
	timestamp := sprint("%s %d +0000", identity, now);

	# Build commit object data
	committext := "tree " + roothash.hex() + "\n";
	if(!parenthash.isnil())
		committext += "parent " + parenthash.hex() + "\n";
	committext += "author " + timestamp + "\n";
	committext += "committer " + timestamp + "\n";
	committext += "\n";
	committext += msg + "\n";

	(commithash, werr) := git->writelooseobj(gitdir, git->OBJ_COMMIT, array of byte committext);
	if(werr != nil)
		fail("write commit: " + werr);

	# Update branch ref
	git->writeref(gitdir, headref, commithash);

	# Clear index
	git->clearindex(gitdir);

	if(verbose)
		sys->fprint(stderr, "commit %s\n", commithash.hex());

	short := commithash.hex()[:7];
	# Count files in index
	nfiles := 0;
	for(el := entries; el != nil; el = tl el)
		nfiles++;
	sys->print("[%s %s] %s\n", branchname(headref), short, msg);
	sys->print(" %d file(s) changed\n", nfiles);
}

# Build tree objects from flat index entries.
# Groups entries by top-level directory, recursively creates subtrees.
buildtree(gitdir: string, entries: list of IndexEntry, verbose: int): Hash
{
	# Separate entries into files at this level and subdirectory groups
	files: list of TreeEntry;
	subdirs: list of (string, list of IndexEntry);

	for(el := entries; el != nil; el = tl el) {
		e := hd el;
		# Split path into first component and rest
		(first, rest) := splitpath(e.path);
		if(rest == nil) {
			# File at this level
			te: TreeEntry;
			te.mode = e.mode;
			te.name = first;
			te.hash = e.hash;
			files = te :: files;
		} else {
			# Entry in a subdirectory
			sube: IndexEntry;
			sube.mode = e.mode;
			sube.hash = e.hash;
			sube.path = rest;
			subdirs = addtogroup(first, sube, subdirs);
		}
	}

	# Recursively build subtree objects
	dirents: list of TreeEntry;
	for(sl := subdirs; sl != nil; sl = tl sl) {
		(dirname, subentries) := hd sl;
		subhash := buildtree(gitdir, subentries, verbose);
		te: TreeEntry;
		te.mode = 8r40000;
		te.name = dirname;
		te.hash = subhash;
		dirents = te :: dirents;
	}

	# Combine file and directory entries into a single array
	nfiles := 0;
	ndirs := 0;
	for(fl := files; fl != nil; fl = tl fl) nfiles++;
	for(dl := dirents; dl != nil; dl = tl dl) ndirs++;

	all := array [nfiles + ndirs] of TreeEntry;
	i := 0;
	for(fl = files; fl != nil; fl = tl fl)
		all[i++] = hd fl;
	for(dl = dirents; dl != nil; dl = tl dl)
		all[i++] = hd dl;

	# Sort by name (git requirement)
	git->sorttreeentries(all);

	# Encode and write tree object
	treedata := git->encodetree(all);
	(h, werr) := git->writelooseobj(gitdir, git->OBJ_TREE, treedata);
	if(werr != nil)
		fail("write tree: " + werr);

	if(verbose)
		sys->fprint(stderr, "tree %s (%d entries)\n", h.hex()[:7], len all);

	return h;
}

# Split "dir/rest/of/path" into ("dir", "rest/of/path").
# If no /, returns (path, nil).
splitpath(path: string): (string, string)
{
	for(i := 0; i < len path; i++)
		if(path[i] == '/')
			return (path[:i], path[i+1:]);
	return (path, nil);
}

# Add an entry to a named group in the list of groups.
addtogroup(name: string, e: IndexEntry, groups: list of (string, list of IndexEntry)): list of (string, list of IndexEntry)
{
	result: list of (string, list of IndexEntry);
	found := 0;
	for(gl := groups; gl != nil; gl = tl gl) {
		(gname, gents) := hd gl;
		if(gname == name) {
			result = (gname, e :: gents) :: result;
			found = 1;
		} else
			result = (gname, gents) :: result;
	}
	if(!found)
		result = (name, e :: nil) :: result;

	# Reverse to maintain order
	groups = nil;
	for(; result != nil; result = tl result)
		groups = (hd result) :: groups;
	return groups;
}

# Read author identity from .git/config [user] section, or fall back to /dev/user.
getidentity(gitdir: string): string
{
	name := readconfig(gitdir, "user", "name");
	email := readconfig(gitdir, "user", "email");

	if(name == nil) {
		fd := sys->open("/dev/user", Sys->OREAD);
		if(fd != nil) {
			buf := array [256] of byte;
			n := sys->read(fd, buf, len buf);
			if(n > 0)
				name = string buf[:n];
		}
		if(name == nil)
			name = "unknown";
	}
	if(email == nil)
		email = name + "@infernode";

	return name + " <" + email + ">";
}

readconfig(gitdir, section, key: string): string
{
	fd := sys->open(gitdir + "/config", Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array [8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;

	config := string buf[:n];
	target := "[" + section + "]";
	insection := 0;

	s := config;
	for(;;) {
		(line, rest) := git->splitline(s);
		if(line == nil && rest == "")
			break;
		s = rest;

		line = git->strtrim(line);

		if(len line > 0 && line[0] == '[') {
			insection = (line == target);
			continue;
		}

		if(insection) {
			(k, val) := git->splitfirst(line, '=');
			k = git->strtrim(k);
			val = git->strtrim(val);
			if(k == key)
				return val;
		}
	}
	return nil;
}

branchname(headref: string): string
{
	if(len headref > 11 && headref[:11] == "refs/heads/")
		return headref[11:];
	return headref;
}

fail(msg: string)
{
	sys->fprint(stderr, "git/commit: %s\n", msg);
	raise "fail:" + msg;
}
