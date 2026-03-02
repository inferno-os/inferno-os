implement Gitfetch;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "arg.m";
	arg: Arg;

include "git.m";
	git: Git;
	Hash, Ref, Repo: import git;

Gitfetch: module
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
	arg->setusage(arg->progname() + " [-v] [remote]");

	verbose := 0;
	while((ch := arg->opt()) != 0)
		case ch {
		'v' =>
			verbose = 1;
		* =>
			arg->usage();
		}

	argv := arg->argv();

	# Find .git directory
	gitdir := git->findgitdir(".");
	if(gitdir == nil)
		fail("not a git repository");

	# Get remote URL
	remote := "origin";
	if(len argv >= 1)
		remote = hd argv;

	remoteurl := git->getremoteurl(gitdir, remote);
	if(remoteurl == nil)
		fail("no url for remote: " + remote);

	if(verbose)
		sys->fprint(stderr, "fetching from %s (%s)\n", remote, remoteurl);

	# Open local repo
	(repo, oerr) := git->openrepo(gitdir);
	if(oerr != nil)
		fail("openrepo: " + oerr);

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
				sys->fprint(stderr, "  remote: %s %s\n", r.hash.hex(), r.name);
			else
				skipped++;
		}
		if(skipped > 0)
			sys->fprint(stderr, "  (%d additional refs not shown)\n", skipped);
	}

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

	if(want == nil) {
		if(verbose)
			sys->fprint(stderr, "already up to date\n");
		# Still update refs
		git->updaterefs(gitdir, remote, refs, verbose);
		return;
	}

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
	packname := "pack-fetch";
	packpath := gitdir + "/objects/pack/" + packname + ".pack";
	ferr := git->fetchpack(remoteurl, want, have, packpath);
	if(ferr != nil)
		fail("fetchpack: " + ferr);

	if(verbose)
		sys->fprint(stderr, "indexing pack...\n");

	# Index the pack
	xerr := git->indexpack(packpath);
	if(xerr != nil)
		fail("indexpack: " + xerr);

	# Rename pack using its SHA-1
	git->renamepak(gitdir, packpath, packname);

	# Update refs
	git->updaterefs(gitdir, remote, refs, verbose);

	sys->print("fetch complete\n");
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
	sys->fprint(stderr, "git/fetch: %s\n", msg);
	raise "fail:" + msg;
}
