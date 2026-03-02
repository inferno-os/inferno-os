implement Gitmerge;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "arg.m";
	arg: Arg;

include "git.m";
	git: Git;
	Hash, Repo, Commit: import git;

Gitmerge: module
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
	arg->setusage(arg->progname() + " [-v] <branch>");

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

	# Parse: [dir] branch
	dir := ".";
	target := "";
	candidate := hd argv;
	testdir := git->findgitdir(candidate);
	if(testdir != nil) {
		dir = candidate;
		argv = tl argv;
	}
	if(argv == nil)
		arg->usage();
	target = hd argv;

	gitdir := git->findgitdir(dir);
	if(gitdir == nil)
		fail("not a git repository");

	reporoot := dir;
	if(len gitdir > 5 && gitdir[len gitdir - 5:] == "/.git")
		reporoot = gitdir[:len gitdir - 5];

	(repo, oerr) := git->openrepo(gitdir);
	if(oerr != nil)
		fail("openrepo: " + oerr);

	# Resolve current HEAD branch and hash
	(headref, herr) := repo.head();
	if(herr != nil)
		fail("HEAD: " + herr);

	branch := "";
	if(len headref > 11 && headref[:11] == "refs/heads/")
		branch = headref[11:];
	else
		fail("HEAD is not on a branch");

	(localhash, lrerr) := repo.readref(headref);
	if(lrerr != nil)
		fail("resolve HEAD: " + lrerr);

	# Resolve target: try refs/heads/<target>, then refs/remotes/origin/<target>
	targethash := git->nullhash();
	(th, terr) := repo.readref("refs/heads/" + target);
	if(terr == nil) {
		targethash = th;
	} else {
		(th2, terr2) := repo.readref("refs/remotes/origin/" + target);
		if(terr2 == nil)
			targethash = th2;
		else
			fail("branch '" + target + "' not found");
	}

	# Already up to date?
	if(localhash.eq(targethash)) {
		sys->print("Already up to date.\n");
		return;
	}

	# Fast-forward check
	if(!git->isancestor(repo, localhash, targethash))
		fail("cannot fast-forward (three-way merge not supported)");

	if(verbose)
		sys->fprint(stderr, "fast-forwarding %s: %s -> %s\n",
			branch, localhash.hex()[:7], targethash.hex()[:7]);

	# Update branch ref
	git->writeref(gitdir, headref, targethash);

	# Checkout new tree
	(nil, cdata, cerr) := repo.readobj(targethash);
	if(cerr != nil)
		fail("read commit: " + cerr);
	(commit, cperr) := git->parsecommit(cdata);
	if(cperr != nil)
		fail("parse commit: " + cperr);

	coerr := repo.checkout(commit.tree, reporoot);
	if(coerr != nil)
		fail("checkout: " + coerr);

	sys->print("Updated %s: %s..%s (fast-forward)\n",
		branch, localhash.hex()[:7], targethash.hex()[:7]);
}

fail(msg: string)
{
	sys->fprint(stderr, "git/merge: %s\n", msg);
	raise "fail:" + msg;
}
