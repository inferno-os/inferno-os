implement Gitpull;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "arg.m";
	arg: Arg;

include "git.m";
	git: Git;
	Hash, Ref, Repo, Commit: import git;

Gitpull: module
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
	arg->setusage(arg->progname() + " [-v] [dir]");

	verbose := 0;
	while((ch := arg->opt()) != 0)
		case ch {
		'v' =>
			verbose = 1;
		* =>
			arg->usage();
		}

	argv := arg->argv();
	dir := ".";
	if(len argv >= 1)
		dir = hd argv;

	gitdir := git->findgitdir(dir);
	if(gitdir == nil)
		fail("not a git repository");

	remoteurl := git->getremoteurl(gitdir, "origin");
	if(remoteurl == nil)
		fail("no url for remote: origin");

	if(verbose)
		sys->fprint(stderr, "pulling from %s\n", remoteurl);

	(repo, oerr) := git->openrepo(gitdir);
	if(oerr != nil)
		fail("openrepo: " + oerr);

	# Discover remote refs
	(refs, nil, derr) := git->discover(remoteurl);
	if(derr != nil)
		fail("discover: " + derr);

	# Determine what we need
	want: list of Hash;
	seen: list of string;
	for(rl := refs; rl != nil; rl = tl rl) {
		r := hd rl;
		hexstr := r.hash.hex();
		if(!git->inlist(hexstr, seen) && !repo.hasobj(r.hash)) {
			want = r.hash :: want;
			seen = hexstr :: seen;
		}
	}

	if(want != nil) {
		# Collect hashes we have for negotiation
		have: list of Hash;
		localrefs := repo.listrefs();
		for(lr := localrefs; lr != nil; lr = tl lr) {
			(nil, h) := hd lr;
			have = h :: have;
		}

		if(verbose)
			sys->fprint(stderr, "fetching %d new objects...\n", listlen(want));

		# Fetch pack
		packname := "pack-pull";
		packpath := gitdir + "/objects/pack/" + packname + ".pack";
		ferr := git->fetchpack(remoteurl, want, have, packpath);
		if(ferr != nil)
			fail("fetchpack: " + ferr);

		if(verbose)
			sys->fprint(stderr, "indexing pack...\n");

		xerr := git->indexpack(packpath);
		if(xerr != nil)
			fail("indexpack: " + xerr);

		git->renamepak(gitdir, packpath, packname);

		# Update remote tracking refs
		git->updaterefs(gitdir, "origin", refs, verbose);

		# Reopen repo to pick up new packs
		(repo, oerr) = git->openrepo(gitdir);
		if(oerr != nil)
			fail("reopen repo: " + oerr);
	} else {
		if(verbose)
			sys->fprint(stderr, "no new objects\n");
		# Still update tracking refs
		git->updaterefs(gitdir, "origin", refs, verbose);
	}

	# Determine current branch
	(headref, herr) := repo.head();
	if(herr != nil)
		fail("HEAD: " + herr);

	branch := "";
	if(len headref > 11 && headref[:11] == "refs/heads/")
		branch = headref[11:];
	else
		fail("HEAD is not on a branch");

	# Read current local hash
	(localhash, lrerr) := repo.readref(headref);
	if(lrerr != nil)
		fail("read local ref: " + lrerr);

	# Find remote hash for this branch
	remotehash := git->nullhash();
	for(rl = refs; rl != nil; rl = tl rl) {
		r := hd rl;
		if(r.name == "refs/heads/" + branch) {
			remotehash = r.hash;
			break;
		}
	}

	if(remotehash.isnil())
		fail("branch " + branch + " not found on remote");

	if(localhash.eq(remotehash)) {
		sys->print("Already up to date.\n");
		return;
	}

	# Verify fast-forward: local must be ancestor of remote
	if(!git->isancestor(repo, localhash, remotehash))
		fail("cannot fast-forward: local " + branch + " is not an ancestor of remote");

	if(verbose)
		sys->fprint(stderr, "fast-forwarding %s: %s -> %s\n",
			branch, localhash.hex()[:7], remotehash.hex()[:7]);

	# Update local branch ref
	git->writeref(gitdir, headref, remotehash);

	# Checkout new tree
	(nil, cdata, cerr) := repo.readobj(remotehash);
	if(cerr != nil)
		fail("read commit: " + cerr);
	(commit, cperr) := git->parsecommit(cdata);
	if(cperr != nil)
		fail("parse commit: " + cperr);

	coerr := repo.checkout(commit.tree, dir);
	if(coerr != nil)
		fail("checkout: " + coerr);

	sys->print("Updated %s: %s..%s\n", branch, localhash.hex()[:7], remotehash.hex()[:7]);
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
	sys->fprint(stderr, "git/pull: %s\n", msg);
	raise "fail:" + msg;
}
