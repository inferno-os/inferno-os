implement Gitclone;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "arg.m";
	arg: Arg;

include "git.m";
	git: Git;
	Hash, Ref, Repo, Commit: import git;

Gitclone: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

stderr: ref Sys->FD;

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
	arg->setusage(arg->progname() + " [-v] url [dir]");

	verbose := 0;
	while((ch := arg->opt()) != 0)
		case ch {
		'v' =>
			verbose = 1;
		* =>
			arg->usage();
		}

	argv := arg->argv();
	if(len argv < 1 || len argv > 2)
		arg->usage();

	remoteurl := hd argv;

	# Determine target directory
	dir: string;
	if(len argv == 2) {
		dir = hd tl argv;
	} else {
		# Extract repo name from URL
		dir = reponame(remoteurl);
	}

	if(verbose)
		sys->fprint(stderr, "cloning %s into %s\n", remoteurl, dir);

	# Create target directory
	dfd := sys->create(dir, Sys->OREAD, Sys->DMDIR | 8r755);
	if(dfd == nil) {
		# Directory may already exist
		(n, nil) := sys->stat(dir);
		if(n < 0)
			fail(sprint("mkdir %s: %r", dir));
	}
	dfd = nil;

	# Init repo
	gitdir := dir + "/.git";
	(nil, ierr) := git->initrepo(gitdir, 0);
	if(ierr != nil)
		fail("initrepo: " + ierr);

	if(verbose)
		sys->fprint(stderr, "discovering refs...\n");

	# Discover remote refs
	(refs, nil, derr) := git->discover(remoteurl);
	if(derr != nil)
		fail("discover: " + derr);

	if(verbose) {
		skipped := 0;
		for(rl := refs; rl != nil; rl = tl rl) {
			r := hd rl;
			if(r.name == "HEAD"
			   || (len r.name > 11 && r.name[:11] == "refs/heads/")
			   || (len r.name > 10 && r.name[:10] == "refs/tags/"))
				sys->fprint(stderr, "  %s %s\n", r.hash.hex(), r.name);
			else
				skipped++;
		}
		if(skipped > 0)
			sys->fprint(stderr, "  (%d additional refs not shown)\n", skipped);
	}

	if(refs == nil)
		fail("no refs found");

	# Collect hashes to fetch (heads, tags, and HEAD only — skip PRs)
	want: list of Hash;
	seen: list of string;
	for(rl := refs; rl != nil; rl = tl rl) {
		r := hd rl;
		if(r.name != "HEAD"
		   && !(len r.name > 11 && r.name[:11] == "refs/heads/")
		   && !(len r.name > 10 && r.name[:10] == "refs/tags/"))
			continue;
		hexstr := r.hash.hex();
		if(!git->inlist(hexstr, seen)) {
			want = r.hash :: want;
			seen = hexstr :: seen;
		}
	}

	if(verbose)
		sys->fprint(stderr, "fetching %d objects...\n", listlen(want));

	# Fetch pack
	packname := "pack-fetch";
	packpath := gitdir + "/objects/pack/" + packname + ".pack";
	ferr := git->fetchpack(remoteurl, want, nil, packpath);
	if(ferr != nil)
		fail("fetchpack: " + ferr);

	if(verbose)
		sys->fprint(stderr, "indexing pack...\n");

	# Index the pack
	xerr := git->indexpack(packpath);
	if(xerr != nil)
		fail("indexpack: " + xerr);

	# Rename pack using its SHA-1 checksum
	git->renamepak(gitdir, packpath, packname);

	if(verbose)
		sys->fprint(stderr, "writing refs...\n");

	# Write refs
	for(rl = refs; rl != nil; rl = tl rl) {
		r := hd rl;
		name := r.name;

		# Skip HEAD (handle separately)
		if(name == "HEAD")
			continue;

		# Write remote tracking ref
		if(len name > 11 && name[:11] == "refs/heads/") {
			branchname := name[11:];
			git->writeref(gitdir, "refs/remotes/origin/" + branchname, r.hash);
		}

		# Write tags
		if(len name > 10 && name[:10] == "refs/tags/")
			git->writeref(gitdir, name, r.hash);
	}

	# Determine default branch and write local HEAD + branch ref
	defaultbranch := "main";
	headhash := git->nullhash();
	for(rl = refs; rl != nil; rl = tl rl) {
		r := hd rl;
		if(r.name == "HEAD") {
			headhash = r.hash;
			break;
		}
	}

	# Find which branch HEAD points to
	if(!headhash.isnil()) {
		for(rl = refs; rl != nil; rl = tl rl) {
			r := hd rl;
			if(r.name != "HEAD" && r.hash.eq(headhash)) {
				if(len r.name > 11 && r.name[:11] == "refs/heads/") {
					defaultbranch = r.name[11:];
					break;
				}
			}
		}
	}

	# Write local branch ref
	if(!headhash.isnil())
		git->writeref(gitdir, "refs/heads/" + defaultbranch, headhash);

	# Write HEAD
	headfd := sys->create(gitdir + "/HEAD", Sys->OWRITE, 8r644);
	if(headfd != nil) {
		data := array of byte ("ref: refs/heads/" + defaultbranch + "\n");
		sys->write(headfd, data, len data);
	}

	# Write remote config
	configfd := sys->open(gitdir + "/config", Sys->OWRITE);
	if(configfd != nil) {
		sys->seek(configfd, big 0, Sys->SEEKEND);
		remote := "[remote \"origin\"]\n";
		remote += "\turl = " + remoteurl + "\n";
		remote += "\tfetch = +refs/heads/*:refs/remotes/origin/*\n";
		rdata := array of byte remote;
		sys->write(configfd, rdata, len rdata);
	}

	# Checkout working tree
	if(!headhash.isnil()) {
		if(verbose)
			sys->fprint(stderr, "checking out working tree...\n");

		(repo, oerr) := git->openrepo(gitdir);
		if(oerr != nil)
			fail("openrepo for checkout: " + oerr);

		(nil, cdata, cerr) := repo.readobj(headhash);
		if(cerr != nil)
			fail("read HEAD commit: " + cerr);

		(commit, cperr) := git->parsecommit(cdata);
		if(cperr != nil)
			fail("parse HEAD commit: " + cperr);

		coerr := repo.checkout(commit.tree, dir);
		if(coerr != nil)
			fail("checkout: " + coerr);
	}

	sys->print("cloned %s into %s\n", remoteurl, dir);
}

reponame(urlstr: string): string
{
	# Extract repository name from URL
	s := urlstr;

	# Strip trailing /
	while(len s > 0 && s[len s - 1] == '/')
		s = s[:len s - 1];

	# Strip .git suffix
	if(len s > 4 && s[len s - 4:] == ".git")
		s = s[:len s - 4];

	# Get last path component
	for(i := len s - 1; i >= 0; i--)
		if(s[i] == '/')
			return s[i+1:];

	return s;
}

listlen(l: list of Hash): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}

fail(msg: string)
{
	sys->fprint(stderr, "git/clone: %s\n", msg);
	raise "fail:" + msg;
}
