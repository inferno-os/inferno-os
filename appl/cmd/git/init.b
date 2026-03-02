implement Gitinit;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "arg.m";
	arg: Arg;

include "git.m";
	git: Git;

Gitinit: module
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
	arg->setusage(arg->progname() + " [-b branch] [dir]");

	branch := "main";
	while((ch := arg->opt()) != 0)
		case ch {
		'b' =>
			branch = arg->earg();
		* =>
			arg->usage();
		}

	argv := arg->argv();
	dir := ".";
	if(len argv >= 1)
		dir = hd argv;

	# Create target directory if it doesn't exist
	sys->create(dir, Sys->OREAD, Sys->DMDIR | 8r755);

	gitdir := dir + "/.git";

	# Check .git doesn't already exist
	(rc, nil) := sys->stat(gitdir);
	if(rc >= 0)
		fail(dir + " is already a git repository");

	(nil, ierr) := git->initrepo(gitdir, 0);
	if(ierr != nil)
		fail("initrepo: " + ierr);

	# Override HEAD if -b specified
	git->writesymref(gitdir, "HEAD", "refs/heads/" + branch);

	sys->print("Initialized empty Git repository in %s\n", gitdir);
}

fail(msg: string)
{
	sys->fprint(stderr, "git/init: %s\n", msg);
	raise "fail:" + msg;
}
