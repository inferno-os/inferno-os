implement Gitcheckout;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "arg.m";
	arg: Arg;

include "git.m";
	git: Git;
	Hash, Repo, Commit: import git;

Gitcheckout: module
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
	arg->setusage(arg->progname() + " [-f] [-b name] <branch>");

	force := 0;
	newbranch := "";
	while((ch := arg->opt()) != 0)
		case ch {
		'f' =>
			force = 1;
		'b' =>
			newbranch = arg->earg();
		* =>
			arg->usage();
		}

	argv := arg->argv();

	# Parse: [dir] branch or just branch
	dir := ".";
	branch := "";
	if(argv != nil) {
		candidate := hd argv;
		testdir := git->findgitdir(candidate);
		if(testdir != nil) {
			dir = candidate;
			argv = tl argv;
		}
	}
	if(argv != nil)
		branch = hd argv;

	if(branch == "" && newbranch == "")
		arg->usage();

	gitdir := git->findgitdir(dir);
	if(gitdir == nil)
		fail("not a git repository");

	# Repo root is gitdir without "/.git"
	reporoot := dir;
	if(len gitdir > 5 && gitdir[len gitdir - 5:] == "/.git")
		reporoot = gitdir[:len gitdir - 5];

	(repo, oerr) := git->openrepo(gitdir);
	if(oerr != nil)
		fail("openrepo: " + oerr);

	if(newbranch != "") {
		# Create and switch: git/checkout -b name [startpoint]
		createandswitch(repo, gitdir, reporoot, newbranch, force);
		return;
	}

	switchbranch(repo, gitdir, reporoot, branch, force);
}

switchbranch(repo: ref Repo, gitdir, reporoot, branch: string, force: int)
{
	# Resolve refs/heads/<branch> to commit hash
	refname := "refs/heads/" + branch;
	(hash, rerr) := repo.readref(refname);
	if(rerr != nil)
		fail("branch '" + branch + "' not found");

	# Check if already on this branch
	(headref, nil) := repo.head();
	if(headref == refname) {
		sys->print("Already on '%s'\n", branch);
		return;
	}

	# Check for dirty working tree unless -f
	if(!force) {
		(curhash, cherr) := repo.readref(headref);
		if(cherr == nil) {
			(nil, cdata, cerr) := repo.readobj(curhash);
			if(cerr == nil) {
				(commit, cperr) := git->parsecommit(cdata);
				if(cperr == nil) {
					(clean, reason) := git->isclean(repo, commit.tree, reporoot);
					if(!clean)
						fail("working tree is dirty (" + reason + "); use -f to force");
				}
			}
		}
	}

	# Update HEAD symref
	git->writesymref(gitdir, "HEAD", refname);

	# Parse target commit and checkout tree
	(nil, cdata, cerr) := repo.readobj(hash);
	if(cerr != nil)
		fail("read commit: " + cerr);
	(commit, cperr) := git->parsecommit(cdata);
	if(cperr != nil)
		fail("parse commit: " + cperr);

	coerr := repo.checkout(commit.tree, reporoot);
	if(coerr != nil)
		fail("checkout: " + coerr);

	sys->print("Switched to branch '%s'\n", branch);
}

createandswitch(repo: ref Repo, gitdir, nil: string, name: string, nil: int)
{
	# Get current HEAD commit hash
	(headref, herr) := repo.head();
	if(herr != nil)
		fail("HEAD: " + herr);

	(hash, rrerr) := repo.readref(headref);
	if(rrerr != nil)
		fail("resolve HEAD: " + rrerr);

	# Check new branch doesn't already exist
	newref := "refs/heads/" + name;
	(nil, rerr) := repo.readref(newref);
	if(rerr == nil)
		fail("branch '" + name + "' already exists");

	# Create branch at current HEAD
	git->writeref(gitdir, newref, hash);

	# Switch HEAD
	git->writesymref(gitdir, "HEAD", newref);

	sys->print("Switched to a new branch '%s'\n", name);
}

fail(msg: string)
{
	sys->fprint(stderr, "git/checkout: %s\n", msg);
	raise "fail:" + msg;
}
