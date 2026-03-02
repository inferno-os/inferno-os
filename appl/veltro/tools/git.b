implement ToolGit;

#
# git - Git repository access for Veltro agents
#
# Read operations go through git/fs mounted at /n/git.
# Write operations go through a worker thread that retains
# the unrestricted namespace (spawned before restriction).
#

include "sys.m";
	sys: Sys;
	sprint: import sys;

include "draw.m";

include "string.m";
	str: String;

include "daytime.m";
	daytime: Daytime;

include "git.m";
	git: Git;
	Hash, Repo, Commit, TreeEntry, IndexEntry, Ref, RefUpdate: import git;

include "../tool.m";

ToolGit: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

Gitfs: module {
	init: fn(nil: ref Draw->Context, args: list of string);
};

gitavail := 0;
workeravail := 0;
workcmd: chan of (string, chan of string);

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	str = load String String->PATH;
	if(str == nil)
		return "cannot load String";

	# Check for git repo
	(ok, nil) := sys->stat("/.git");
	if(ok < 0)
		return nil;  # No repo; exec() will return errors

	# Mount git/fs at /n/git before namespace restriction
	ready := chan of int;
	spawn mountgitfs(ready);
	result := <-ready;
	if(result > 0)
		gitavail = 1;

	# Start worker thread for write operations (before restriction)
	workcmd = chan of (string, chan of string);
	wready := chan of int;
	spawn gitworker(wready);
	wresult := <-wready;
	if(wresult > 0)
		workeravail = 1;

	return nil;
}

mountgitfs(ready: chan of int)
{
	gitfs := load Gitfs "/dis/cmd/git/fs.dis";
	if(gitfs == nil) {
		ready <-= 0;
		return;
	}

	{
		gitfs->init(nil, "git/fs" :: "-m" :: "/n/git" :: "/.git" :: nil);
		ready <-= 1;
	} exception {
	"*" =>
		ready <-= 0;
	}
}

# Worker thread runs before namespace restriction.
# It retains access to /.git and can perform write operations.
gitworker(ready: chan of int)
{
	wgit := load Git Git->PATH;
	if(wgit == nil) {
		ready <-= 0;
		return;
	}
	werr := wgit->init();
	if(werr != nil) {
		ready <-= 0;
		return;
	}

	wdaytime := load Daytime Daytime->PATH;
	if(wdaytime == nil) {
		ready <-= 0;
		return;
	}

	gitdir := wgit->findgitdir(".");
	if(gitdir == nil) {
		ready <-= 0;
		return;
	}

	(repo, oerr) := wgit->openrepo(gitdir);
	if(oerr != nil) {
		ready <-= 0;
		return;
	}

	reporoot := ".";
	if(len gitdir > 5 && gitdir[len gitdir - 5:] == "/.git")
		reporoot = gitdir[:len gitdir - 5];

	ready <-= 1;

	# Dispatch loop
	for(;;) {
		(cmdline, reply) := <-workcmd;
		(cmd, rest) := splitword(cmdline);
		rest = strip(rest);

		r := "";
		{
			case cmd {
			"add" =>
				r = workadd(wgit, gitdir, reporoot, rest);
			"commit" =>
				r = workcommit(wgit, wdaytime, repo, gitdir, rest);
			"push" =>
				r = workpush(wgit, repo, gitdir, rest);
			"fetch" =>
				r = workfetch(wgit, repo, gitdir, rest);
			"branch-create" =>
				r = workbranchcreate(wgit, repo, gitdir, rest);
			"branch-delete" =>
				r = workbranchdelete(wgit, gitdir, rest);
			"checkout" =>
				r = workcheckout(wgit, repo, gitdir, reporoot, rest);
			"merge" =>
				r = workmerge(wgit, repo, gitdir, reporoot, rest);
			"rm" =>
				r = workrm(wgit, gitdir, reporoot, rest);
			* =>
				r = "error: unknown worker command: " + cmd;
			}
		} exception e {
		"fail:*" =>
			r = "error: " + e[5:];
		"*" =>
			r = "error: " + e;
		}

		reply <-= r;
	}
}

name(): string
{
	return "git";
}

doc(): string
{
	return "Git - Repository access and management\n\n" +
		"Read commands:\n" +
		"  git status              Current branch and HEAD commit\n" +
		"  git log [n]             Last n commits (default 10, max 50)\n" +
		"  git show <hash>         Show commit details by hash or branch\n" +
		"  git branch              List branches\n" +
		"  git tag                 List tags\n" +
		"  git cat <path> [ref]    Show file content at HEAD or ref\n\n" +
		"Write commands:\n" +
		"  git add <path> [path..] Stage files for commit\n" +
		"  git commit <message>    Commit staged changes\n" +
		"  git push [remote]       Push current branch to remote\n" +
		"  git fetch [remote]      Fetch from remote\n" +
		"  git branch-create <n>   Create new branch at HEAD\n" +
		"  git branch-delete <n>   Delete a branch\n" +
		"  git checkout <branch>   Switch to branch\n" +
		"  git merge <branch>      Fast-forward merge branch into current\n" +
		"  git rm <path> [path..]  Remove files from index and working tree\n";
}

exec(args: string): string
{
	if(sys == nil)
		init();
	if(!gitavail)
		return "error: no git repository available";

	args = strip(args);
	if(args == "")
		return "error: usage: git <subcommand> [args]";

	(cmd, rest) := splitword(args);
	rest = strip(rest);

	# Read operations — go through git/fs
	case cmd {
	"status" =>
		return gitstatus();
	"log" =>
		n := 10;
		if(rest != "")
			n = int rest;
		if(n < 1)
			n = 1;
		if(n > 50)
			n = 50;
		return gitlog(n);
	"show" =>
		if(rest == "")
			return "error: usage: git show <hash|branch>";
		return gitshow(rest);
	"branch" or "branches" =>
		if(rest == "")
			return gitbranch();
		# branch with args is a write op
		return workercall("branch-create " + rest);
	"branch-create" =>
		return workercall("branch-create " + rest);
	"branch-delete" =>
		return workercall("branch-delete " + rest);
	"tag" or "tags" =>
		return gittag();
	"cat" =>
		return gitcat(rest);
	}

	# Write operations — go through worker thread
	case cmd {
	"add" or "commit" or "push" or "fetch" or
	"checkout" or "merge" or "rm" =>
		return workercall(cmd + " " + rest);
	}

	return "error: unknown subcommand: " + cmd +
		"\nAvailable: status, log, show, branch, tag, cat, " +
		"add, commit, push, fetch, checkout, merge, rm";
}

workercall(cmdline: string): string
{
	if(!workeravail)
		return "error: git write operations not available";

	reply := chan of string;
	workcmd <-= (cmdline, reply);
	return <-reply;
}

# --- Read operations (git/fs) ---

gitstatus(): string
{
	branch := strip(readfile("/n/git/ctl"));
	if(branch == "")
		branch = "(unknown)";

	headhash := strip(readfile("/n/git/HEAD/hash"));
	if(headhash == "")
		return "On branch " + branch + "\n(no commits)";

	headmsg := strip(readfile("/n/git/HEAD/msg"));
	(firstline, nil) := splitline(headmsg);

	return "On branch " + branch + "\n" +
		"HEAD " + shorthash(headhash) + " " + firstline;
}

gitlog(n: int): string
{
	result := "";

	hash := strip(readfile("/n/git/HEAD/hash"));
	if(hash == "")
		return "(no commits)";

	author := strip(readfile("/n/git/HEAD/author"));
	msg := strip(readfile("/n/git/HEAD/msg"));
	(firstline, nil) := splitline(msg);
	result = shorthash(hash) + " " + firstline + "\n";
	result += "  Author: " + author + "\n";

	parent := strip(readfile("/n/git/HEAD/parent"));

	for(i := 1; i < n && parent != "" && parent != "nil"; i++) {
		objdir := "/n/git/object/" + parent;

		author = strip(readfile(objdir + "/author"));
		msg = strip(readfile(objdir + "/msg"));
		(firstline, nil) = splitline(msg);

		result += "\n" + shorthash(parent) + " " + firstline + "\n";
		result += "  Author: " + author + "\n";

		parent = strip(readfile(objdir + "/parent"));
	}

	return result;
}

gitshow(gitref: string): string
{
	objdir: string;

	if(len gitref == 40) {
		objdir = "/n/git/object/" + gitref;
	} else {
		hash := strip(readfile("/n/git/branch/heads/" + gitref + "/hash"));
		if(hash != "") {
			objdir = "/n/git/object/" + hash;
			gitref = hash;
		} else {
			hash = strip(readfile("/n/git/tag/" + gitref + "/hash"));
			if(hash != "") {
				objdir = "/n/git/object/" + hash;
				gitref = hash;
			} else
				return "error: cannot find ref: " + gitref;
		}
	}

	otype := strip(readfile(objdir + "/type"));
	if(otype == "")
		return "error: object not found: " + gitref;

	case otype {
	"commit" =>
		chash := strip(readfile(objdir + "/hash"));
		cauthor := strip(readfile(objdir + "/author"));
		ccommitter := strip(readfile(objdir + "/committer"));
		cmsg := strip(readfile(objdir + "/msg"));
		cparent := strip(readfile(objdir + "/parent"));

		cresult := "commit " + chash + "\n";
		cresult += "Author: " + cauthor + "\n";
		cresult += "Committer: " + ccommitter + "\n";
		if(cparent != "" && cparent != "nil")
			cresult += "Parent: " + cparent + "\n";
		cresult += "\n" + cmsg;
		return cresult;

	"blob" =>
		bdata := readfile(objdir + "/data");
		if(bdata == "")
			return "(empty blob)";
		return bdata;

	"tree" =>
		return "tree " + gitref + "\n(use 'git cat <path>' to view files)";

	"tag" =>
		ttagger := strip(readfile(objdir + "/tagger"));
		tmsg := strip(readfile(objdir + "/msg"));
		tresult := "tag " + gitref + "\n";
		if(ttagger != "")
			tresult += "Tagger: " + ttagger + "\n";
		if(tmsg != "")
			tresult += "\n" + tmsg;
		return tresult;

	* =>
		return "object " + gitref + " type=" + otype;
	}
}

gitbranch(): string
{
	current := strip(readfile("/n/git/ctl"));

	entries := listdir("/n/git/branch/heads");
	if(entries == nil)
		return "(no branches)";

	result := "";
	for(; entries != nil; entries = tl entries) {
		bname := hd entries;
		if(bname == current)
			result += "* " + bname + "\n";
		else
			result += "  " + bname + "\n";
	}

	remotes := listdir("/n/git/branch/remotes");
	for(; remotes != nil; remotes = tl remotes) {
		remote := hd remotes;
		rbranches := listdir("/n/git/branch/remotes/" + remote);
		for(; rbranches != nil; rbranches = tl rbranches)
			result += "  remotes/" + remote + "/" + hd rbranches + "\n";
	}

	return result;
}

gittag(): string
{
	entries := listdir("/n/git/tag");
	if(entries == nil)
		return "(no tags)";

	result := "";
	for(; entries != nil; entries = tl entries)
		result += hd entries + "\n";

	return result;
}

gitcat(args: string): string
{
	if(args == "")
		return "error: usage: git cat <path> [ref]";

	(fpath, gitref) := splitword(args);
	gitref = strip(gitref);

	treepath: string;
	if(gitref == "") {
		treepath = "/n/git/HEAD/tree/" + fpath;
	} else {
		hash := strip(readfile("/n/git/branch/heads/" + gitref + "/hash"));
		if(hash == "") {
			if(len gitref == 40)
				hash = gitref;
			else
				return "error: cannot find ref: " + gitref;
		}
		treepath = "/n/git/object/" + hash + "/tree/" + fpath;
	}

	content := readfile(treepath);
	if(content == "")
		return "error: file not found: " + fpath;

	return content;
}

# --- Write operations (worker thread) ---

workadd(wgit: Git, gitdir, reporoot, args: string): string
{
	if(args == "")
		return "error: usage: git add <path> [path ...]";

	paths := splitargs(args);

	# Load existing index
	(entries, lerr) := wgit->loadindex(gitdir);
	if(lerr != nil)
		return "error: loadindex: " + lerr;

	added := 0;
	for(; paths != nil; paths = tl paths) {
		path := hd paths;
		(rc, dir) := sys->stat(path);
		if(rc < 0)
			return sprint("error: stat %s: %r", path);

		if(dir.qid.qtype & Sys->QTDIR)
			(entries, added) = adddir(wgit, gitdir, reporoot, path, entries, added);
		else
			(entries, added) = addfile(wgit, gitdir, reporoot, path, entries, added);
	}

	serr := wgit->saveindex(gitdir, entries);
	if(serr != nil)
		return "error: saveindex: " + serr;

	return sprint("added %d file(s)", added);
}

adddir(wgit: Git, gitdir, reporoot, dirpath: string, entries: list of IndexEntry, added: int): (list of IndexEntry, int)
{
	fd := sys->open(dirpath, Sys->OREAD);
	if(fd == nil)
		return (entries, added);

	for(;;) {
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++) {
			dname := dirs[i].name;
			if(dname == ".git")
				continue;
			fullpath := dirpath + "/" + dname;
			if(dirs[i].qid.qtype & Sys->QTDIR)
				(entries, added) = adddir(wgit, gitdir, reporoot, fullpath, entries, added);
			else
				(entries, added) = addfile(wgit, gitdir, reporoot, fullpath, entries, added);
		}
	}
	return (entries, added);
}

addfile(wgit: Git, gitdir, reporoot, filepath: string, entries: list of IndexEntry, added: int): (list of IndexEntry, int)
{
	fd := sys->open(filepath, Sys->OREAD);
	if(fd == nil)
		return (entries, added);  # skip unreadable
	(rc, dir) := sys->fstat(fd);
	if(rc < 0)
		return (entries, added);

	size := int dir.length;
	data := array[size] of byte;
	total := 0;
	while(total < size) {
		n := sys->read(fd, data[total:], size - total);
		if(n <= 0)
			break;
		total += n;
	}
	data = data[:total];

	(h, werr) := wgit->writelooseobj(gitdir, wgit->OBJ_BLOB, data);
	if(werr != nil)
		return (entries, added);  # skip on error

	mode := 8r100644;
	if(dir.mode & 8r111)
		mode = 8r100755;

	relpath := relativepath(reporoot, filepath);

	e: IndexEntry;
	e.mode = mode;
	e.hash = h;
	e.path = relpath;

	# Replace existing or append
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

	entries = revlist(result);
	return (entries, added + 1);
}

workcommit(wgit: Git, wdaytime: Daytime, repo: ref Repo, gitdir, msg: string): string
{
	if(msg == "")
		return "error: usage: git commit <message>";

	(entries, lerr) := wgit->loadindex(gitdir);
	if(lerr != nil)
		return "error: loadindex: " + lerr;
	if(entries == nil)
		return "error: nothing to commit (use git add first)";

	roothash := buildtree(wgit, gitdir, entries);

	(headref, herr) := repo.head();
	if(herr != nil)
		return "error: HEAD: " + herr;

	parenthash := wgit->nullhash();
	(ph, prerr) := repo.readref(headref);
	if(prerr == nil)
		parenthash = ph;

	identity := getidentity(wgit, gitdir);
	now := wdaytime->now();
	timestamp := sprint("%s %d +0000", identity, now);

	committext := "tree " + roothash.hex() + "\n";
	if(!parenthash.isnil())
		committext += "parent " + parenthash.hex() + "\n";
	committext += "author " + timestamp + "\n";
	committext += "committer " + timestamp + "\n";
	committext += "\n";
	committext += msg + "\n";

	(commithash, werr) := wgit->writelooseobj(gitdir, wgit->OBJ_COMMIT, array of byte committext);
	if(werr != nil)
		return "error: write commit: " + werr;

	wgit->writeref(gitdir, headref, commithash);
	wgit->clearindex(gitdir);

	nfiles := 0;
	for(el := entries; el != nil; el = tl el)
		nfiles++;

	branch := headref;
	if(len headref > 11 && headref[:11] == "refs/heads/")
		branch = headref[11:];

	return sprint("[%s %s] %s\n %d file(s) changed",
		branch, commithash.hex()[:7], msg, nfiles);
}

workpush(wgit: Git, repo: ref Repo, gitdir, args: string): string
{
	remote := "origin";
	if(args != "")
		remote = args;

	remoteurl := wgit->getremoteurl(gitdir, remote);
	if(remoteurl == nil)
		return "error: no url for remote: " + remote;

	(headref, herr) := repo.head();
	if(herr != nil)
		return "error: HEAD: " + herr;

	branch := "";
	if(len headref > 11 && headref[:11] == "refs/heads/")
		branch = headref[11:];
	else
		return "error: HEAD is not on a branch";

	(localhash, lrerr) := repo.readref(headref);
	if(lrerr != nil)
		return "error: resolve HEAD: " + lrerr;

	dstrefname := "refs/heads/" + branch;

	(refs, nil, derr) := wgit->discover_receive(remoteurl);
	if(derr != nil)
		return "error: discover: " + derr;

	oldhash := wgit->nullhash();
	for(rl := refs; rl != nil; rl = tl rl) {
		r := hd rl;
		if(r.name == dstrefname) {
			oldhash = r.hash;
			break;
		}
	}

	if(localhash.eq(oldhash))
		return "Everything up-to-date";

	# Collect remote hashes as have set
	have: list of Hash;
	for(rl = refs; rl != nil; rl = tl rl)
		have = (hd rl).hash :: have;

	want := localhash :: nil;
	(objects, eerr) := wgit->enumobjects(repo, want, have);
	if(eerr != nil)
		return "error: enumobjects: " + eerr;

	nobj := 0;
	for(ol := objects; ol != nil; ol = tl ol)
		nobj++;

	(packdata, perr) := wgit->writepack(objects);
	if(perr != nil)
		return "error: writepack: " + perr;

	creds := wgit->readcredentials(gitdir);
	if(creds == nil)
		return "error: no credentials found; create .git/credentials with user:token";

	upd := ref RefUpdate(oldhash, localhash, dstrefname);
	updates := upd :: nil;

	serr := wgit->sendpack(remoteurl, updates, packdata, creds);
	if(serr != nil)
		return "error: push: " + serr;

	return sprint("To %s\n   %s..%s  %s -> %s",
		remoteurl, oldhash.hex()[:7], localhash.hex()[:7], branch, branch);
}

workfetch(wgit: Git, repo: ref Repo, gitdir, args: string): string
{
	remote := "origin";
	if(args != "")
		remote = args;

	remoteurl := wgit->getremoteurl(gitdir, remote);
	if(remoteurl == nil)
		return "error: no url for remote: " + remote;

	# Discover remote refs
	(refs, nil, derr) := wgit->discover(remoteurl);
	if(derr != nil)
		return "error: discover: " + derr;

	# Build want/have lists
	want: list of Hash;
	for(rl := refs; rl != nil; rl = tl rl) {
		r := hd rl;
		if(!repo.hasobj(r.hash))
			want = r.hash :: want;
	}

	if(want == nil)
		return "Already up to date.";

	# Count wants
	nwant := 0;
	for(wl := want; wl != nil; wl = tl wl)
		nwant++;

	# Get local objects as have
	have: list of Hash;
	localrefs := repo.listrefs();
	for(lr := localrefs; lr != nil; lr = tl lr) {
		(nil, lh) := hd lr;
		have = lh :: have;
	}

	# Fetch pack
	tmppack := gitdir + "/tmp-fetchpack.pack";
	ferr := wgit->fetchpack(remoteurl, want, have, tmppack);
	if(ferr != nil)
		return "error: fetchpack: " + ferr;

	# Index the pack
	ierr := wgit->indexpack(tmppack);
	if(ierr != nil)
		return "error: indexpack: " + ierr;

	# Compute pack name and rename
	fd := sys->open(tmppack, Sys->OREAD);
	if(fd != nil) {
		(rc, dir) := sys->fstat(fd);
		if(rc >= 0) {
			packdata := array[int dir.length] of byte;
			total := 0;
			while(total < len packdata) {
				n := sys->read(fd, packdata[total:], len packdata - total);
				if(n <= 0)
					break;
				total += n;
			}
			packhash := wgit->hashobj(wgit->OBJ_BLOB, packdata[:total]);
			packname := "pack-" + packhash.hex();
			wgit->renamepak(gitdir, tmppack, packname);
		}
	}

	# Update remote tracking refs
	wgit->updaterefs(gitdir, remote, refs, 0);

	return sprint("From %s\n %d new object(s) fetched", remoteurl, nwant);
}

workbranchcreate(wgit: Git, repo: ref Repo, gitdir, bname: string): string
{
	if(bname == "")
		return "error: usage: git branch-create <name>";

	# Check if already exists
	(nil, terr) := repo.readref("refs/heads/" + bname);
	if(terr == nil)
		return "error: branch '" + bname + "' already exists";

	# Get current HEAD hash
	(headref, herr) := repo.head();
	if(herr != nil)
		return "error: HEAD: " + herr;
	(h, rerr) := repo.readref(headref);
	if(rerr != nil)
		return "error: resolve HEAD: " + rerr;

	wgit->writeref(gitdir, "refs/heads/" + bname, h);
	return "Created branch '" + bname + "' at " + h.hex()[:7];
}

workbranchdelete(nil: Git, gitdir, bname: string): string
{
	if(bname == "")
		return "error: usage: git branch-delete <name>";

	refpath := gitdir + "/refs/heads/" + bname;
	(ok, nil) := sys->stat(refpath);
	if(ok < 0)
		return "error: branch '" + bname + "' not found";

	rc := sys->remove(refpath);
	if(rc < 0)
		return sprint("error: remove %s: %r", refpath);

	return "Deleted branch '" + bname + "'";
}

workcheckout(wgit: Git, repo: ref Repo, gitdir, reporoot, bname: string): string
{
	if(bname == "")
		return "error: usage: git checkout <branch>";

	(targethash, terr) := repo.readref("refs/heads/" + bname);
	if(terr != nil)
		return "error: branch '" + bname + "' not found";

	# Check for dirty working tree
	(headref, herr) := repo.head();
	if(herr != nil)
		return "error: HEAD: " + herr;
	(currenthash, rerr) := repo.readref(headref);
	if(rerr == nil) {
		(nil, cdata, cerr) := repo.readobj(currenthash);
		if(cerr == nil) {
			(commit, cperr) := wgit->parsecommit(cdata);
			if(cperr == nil) {
				(clean, cmsg) := wgit->isclean(repo, commit.tree, reporoot);
				if(!clean)
					return "error: working tree has uncommitted changes: " + cmsg;
			}
		}
	}

	# Read target commit to get tree
	(nil, tdata, trerr) := repo.readobj(targethash);
	if(trerr != nil)
		return "error: read commit: " + trerr;
	(tcommit, tcperr) := wgit->parsecommit(tdata);
	if(tcperr != nil)
		return "error: parse commit: " + tcperr;

	# Update HEAD symref
	wgit->writesymref(gitdir, "HEAD", "refs/heads/" + bname);

	# Checkout tree
	coerr := repo.checkout(tcommit.tree, reporoot);
	if(coerr != nil)
		return "error: checkout: " + coerr;

	return "Switched to branch '" + bname + "'";
}

workmerge(wgit: Git, repo: ref Repo, gitdir, reporoot, target: string): string
{
	if(target == "")
		return "error: usage: git merge <branch>";

	(headref, herr) := repo.head();
	if(herr != nil)
		return "error: HEAD: " + herr;

	branch := "";
	if(len headref > 11 && headref[:11] == "refs/heads/")
		branch = headref[11:];
	else
		return "error: HEAD is not on a branch";

	(localhash, lrerr) := repo.readref(headref);
	if(lrerr != nil)
		return "error: resolve HEAD: " + lrerr;

	# Resolve target
	targethash := wgit->nullhash();
	(th, terr) := repo.readref("refs/heads/" + target);
	if(terr == nil) {
		targethash = th;
	} else {
		(th2, terr2) := repo.readref("refs/remotes/origin/" + target);
		if(terr2 == nil)
			targethash = th2;
		else
			return "error: branch '" + target + "' not found";
	}

	if(localhash.eq(targethash))
		return "Already up to date.";

	if(!wgit->isancestor(repo, localhash, targethash))
		return "error: cannot fast-forward (three-way merge not supported)";

	wgit->writeref(gitdir, headref, targethash);

	(nil, cdata, cerr) := repo.readobj(targethash);
	if(cerr != nil)
		return "error: read commit: " + cerr;
	(commit, cperr) := wgit->parsecommit(cdata);
	if(cperr != nil)
		return "error: parse commit: " + cperr;

	coerr := repo.checkout(commit.tree, reporoot);
	if(coerr != nil)
		return "error: checkout: " + coerr;

	return sprint("Updated %s: %s..%s (fast-forward)",
		branch, localhash.hex()[:7], targethash.hex()[:7]);
}

workrm(wgit: Git, gitdir, reporoot, args: string): string
{
	if(args == "")
		return "error: usage: git rm <path> [path ...]";

	paths := splitargs(args);

	(entries, lerr) := wgit->loadindex(gitdir);
	if(lerr != nil)
		return "error: loadindex: " + lerr;

	removed := 0;
	for(; paths != nil; paths = tl paths) {
		path := hd paths;
		relpath := relativepath(reporoot, path);

		newentries: list of IndexEntry;
		for(el := entries; el != nil; el = tl el) {
			e := hd el;
			if(e.path == relpath || hasprefix(e.path, relpath + "/")) {
				removed++;
				sys->remove(path);
			} else
				newentries = e :: newentries;
		}
		entries = revlist(newentries);
	}

	if(removed == 0)
		return "error: no files matched";

	serr := wgit->saveindex(gitdir, entries);
	if(serr != nil)
		return "error: saveindex: " + serr;

	return sprint("removed %d file(s)", removed);
}

# --- Tree building (for commit) ---

buildtree(wgit: Git, gitdir: string, entries: list of IndexEntry): Hash
{
	files: list of TreeEntry;
	subdirs: list of (string, list of IndexEntry);

	for(el := entries; el != nil; el = tl el) {
		e := hd el;
		(first, rest) := splitpath(e.path);
		if(rest == nil) {
			te: TreeEntry;
			te.mode = e.mode;
			te.name = first;
			te.hash = e.hash;
			files = te :: files;
		} else {
			sube: IndexEntry;
			sube.mode = e.mode;
			sube.hash = e.hash;
			sube.path = rest;
			subdirs = addtogroup(first, sube, subdirs);
		}
	}

	dirents: list of TreeEntry;
	for(sl := subdirs; sl != nil; sl = tl sl) {
		(dirname, subentries) := hd sl;
		subhash := buildtree(wgit, gitdir, subentries);
		te: TreeEntry;
		te.mode = 8r40000;
		te.name = dirname;
		te.hash = subhash;
		dirents = te :: dirents;
	}

	nfiles := 0;
	ndirs := 0;
	for(fl := files; fl != nil; fl = tl fl) nfiles++;
	for(dl := dirents; dl != nil; dl = tl dl) ndirs++;

	all := array[nfiles + ndirs] of TreeEntry;
	i := 0;
	for(fl = files; fl != nil; fl = tl fl)
		all[i++] = hd fl;
	for(dl = dirents; dl != nil; dl = tl dl)
		all[i++] = hd dl;

	wgit->sorttreeentries(all);

	treedata := wgit->encodetree(all);
	(h, werr) := wgit->writelooseobj(gitdir, wgit->OBJ_TREE, treedata);
	if(werr != nil)
		raise "fail:write tree: " + werr;

	return h;
}

splitpath(path: string): (string, string)
{
	for(i := 0; i < len path; i++)
		if(path[i] == '/')
			return (path[:i], path[i+1:]);
	return (path, nil);
}

addtogroup(gname: string, e: IndexEntry, groups: list of (string, list of IndexEntry)): list of (string, list of IndexEntry)
{
	result: list of (string, list of IndexEntry);
	found := 0;
	for(gl := groups; gl != nil; gl = tl gl) {
		(n, ents) := hd gl;
		if(n == gname) {
			result = (n, e :: ents) :: result;
			found = 1;
		} else
			result = (n, ents) :: result;
	}
	if(!found)
		result = (gname, e :: nil) :: result;

	# Reverse
	groups = nil;
	for(; result != nil; result = tl result)
		groups = (hd result) :: groups;
	return groups;
}

getidentity(wgit: Git, gitdir: string): string
{
	uname := readcfg(wgit, gitdir, "user", "name");
	email := readcfg(wgit, gitdir, "user", "email");

	if(uname == nil) {
		fd := sys->open("/dev/user", Sys->OREAD);
		if(fd != nil) {
			buf := array[256] of byte;
			n := sys->read(fd, buf, len buf);
			if(n > 0)
				uname = string buf[:n];
		}
		if(uname == nil)
			uname = "unknown";
	}
	if(email == nil)
		email = uname + "@infernode";

	return uname + " <" + email + ">";
}

readcfg(wgit: Git, gitdir, section, key: string): string
{
	fd := sys->open(gitdir + "/config", Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;

	config := string buf[:n];
	target := "[" + section + "]";
	insection := 0;

	s := config;
	for(;;) {
		(line, rest) := wgit->splitline(s);
		if(line == nil && rest == "")
			break;
		s = rest;

		line = wgit->strtrim(line);

		if(len line > 0 && line[0] == '[') {
			insection = (line == target);
			continue;
		}

		if(insection) {
			(k, val) := wgit->splitfirst(line, '=');
			k = wgit->strtrim(k);
			val = wgit->strtrim(val);
			if(k == key)
				return val;
		}
	}
	return nil;
}

# --- Helpers ---

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return "";
	result := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}
	return result;
}

listdir(path: string): list of string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;

	result: list of string;
	for(;;) {
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++)
			result = dirs[i].name :: result;
	}

	return revstrlist(result);
}

relativepath(reporoot, filepath: string): string
{
	prefix := reporoot + "/";
	if(len filepath > len prefix && filepath[:len prefix] == prefix)
		return filepath[len prefix:];
	if(len filepath >= 2 && filepath[:2] == "./")
		return filepath[2:];
	return filepath;
}

splitargs(s: string): list of string
{
	result: list of string;
	for(;;) {
		s = strip(s);
		if(len s == 0)
			break;
		(word, rest) := splitword(s);
		result = word :: result;
		s = rest;
	}
	return revstrlist(result);
}

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[:len prefix] == prefix;
}

revlist(l: list of IndexEntry): list of IndexEntry
{
	r: list of IndexEntry;
	for(; l != nil; l = tl l)
		r = (hd l) :: r;
	return r;
}

revstrlist(l: list of string): list of string
{
	r: list of string;
	for(; l != nil; l = tl l)
		r = (hd l) :: r;
	return r;
}

strip(s: string): string
{
	if(len s == 0)
		return "";
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r'))
		i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\n' || s[j-1] == '\r'))
		j--;
	if(i >= j)
		return "";
	return s[i:j];
}

splitword(s: string): (string, string)
{
	for(i := 0; i < len s; i++) {
		if(s[i] == ' ' || s[i] == '\t')
			return (s[0:i], s[i+1:]);
	}
	return (s, "");
}

splitline(s: string): (string, string)
{
	for(i := 0; i < len s; i++) {
		if(s[i] == '\n')
			return (s[0:i], s[i+1:]);
	}
	return (s, "");
}

shorthash(h: string): string
{
	if(len h >= 8)
		return h[0:8];
	return h;
}
