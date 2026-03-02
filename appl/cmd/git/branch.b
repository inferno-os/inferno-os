implement Gitbranch;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "arg.m";
	arg: Arg;

include "git.m";
	git: Git;
	Hash, Repo: import git;

Gitbranch: module
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
	arg->setusage(arg->progname() + " [-d] [name]");

	delflag := 0;
	while((ch := arg->opt()) != 0)
		case ch {
		'd' =>
			delflag = 1;
		* =>
			arg->usage();
		}

	argv := arg->argv();

	# Determine working directory: first arg may be dir or branch name
	# Convention: git/branch [dir] or git/branch [dir] name or git/branch [dir] -d name
	# Parse: if only one arg and not -d, it could be a dir or branch name
	# Strategy: try first arg as dir, if it has .git, use it as dir
	dir := ".";
	name := "";
	if(argv != nil) {
		candidate := hd argv;
		testdir := git->findgitdir(candidate);
		if(testdir != nil) {
			dir = candidate;
			argv = tl argv;
			if(argv != nil)
				name = hd argv;
		} else {
			name = candidate;
		}
	}

	gitdir := git->findgitdir(dir);
	if(gitdir == nil)
		fail("not a git repository");

	(repo, oerr) := git->openrepo(gitdir);
	if(oerr != nil)
		fail("openrepo: " + oerr);

	if(name == "") {
		# List branches
		listbranches(repo);
		return;
	}

	if(delflag) {
		# Delete branch
		deletebranch(repo, gitdir, name);
	} else {
		# Create branch
		createbranch(repo, gitdir, name);
	}
}

listbranches(repo: ref Repo)
{
	(headref, nil) := repo.head();

	refs := repo.listrefs();
	for(rl := refs; rl != nil; rl = tl rl) {
		(name, nil) := hd rl;
		if(len name > 11 && name[:11] == "refs/heads/") {
			brname := name[11:];
			if(name == headref)
				sys->print("* %s\n", brname);
			else
				sys->print("  %s\n", brname);
		}
	}
}

createbranch(repo: ref Repo, gitdir, name: string)
{
	# Check branch doesn't already exist
	refname := "refs/heads/" + name;
	(nil, rerr) := repo.readref(refname);
	if(rerr == nil)
		fail("branch '" + name + "' already exists");

	# Resolve HEAD to get commit hash
	(headref, herr) := repo.head();
	if(herr != nil)
		fail("HEAD: " + herr);

	(hash, rrerr) := repo.readref(headref);
	if(rrerr != nil)
		fail("resolve HEAD: " + rrerr);

	git->writeref(gitdir, refname, hash);
	sys->print("Created branch '%s' at %s\n", name, hash.hex()[:7]);
}

deletebranch(repo: ref Repo, gitdir, name: string)
{
	refname := "refs/heads/" + name;

	# Refuse to delete current branch
	(headref, nil) := repo.head();
	if(headref == refname)
		fail("cannot delete current branch '" + name + "'");

	# Check branch exists
	(nil, rerr) := repo.readref(refname);
	if(rerr != nil)
		fail("branch '" + name + "' not found");

	if(sys->remove(gitdir + "/" + refname) < 0)
		fail(sprint("remove branch: %r"));

	sys->print("Deleted branch '%s'\n", name);
}

fail(msg: string)
{
	sys->fprint(stderr, "git/branch: %s\n", msg);
	raise "fail:" + msg;
}
