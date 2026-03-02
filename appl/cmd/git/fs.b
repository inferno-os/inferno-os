implement Gitfs;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "arg.m";
	arg: Arg;
include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;
include "styxservers.m";
	styxservers: Styxservers;
	Styxserver, Fid, Navigator, Navop, Enotfound: import styxservers;
include "git.m";
	git: Git;
	Hash, Repo, Pack, Commit, TreeEntry, Tag, Ref: import git;

Gitfs: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

# Qid path encoding:
# The high 4 bits encode the node type.
# The low 28 bits encode an index into the object/node cache.
QSHIFT: con 28;
QMASK:  con 16r0FFFFFFF;

# Node types
Qt_ROOT:      con 0;
Qt_CTL:       con 1;
Qt_COMMITDIR: con 2;
Qt_CHASH:     con 3;
Qt_CAUTHOR:   con 4;
Qt_CCOMMIT:   con 5;
Qt_CMSG:      con 6;
Qt_CPARENT:   con 7;
Qt_TREEDIR:   con 8;
Qt_BLOB:      con 9;
Qt_BRANCHDIR: con 10;
Qt_HEADSDIR:  con 11;
Qt_REMOTEDIR: con 12;
Qt_TAGDIR:    con 13;
Qt_OBJECTDIR: con 14;

# Cached objects
CEntry: adt {
	hash:  git->Hash;
	otype: int;
	data:  array of byte;
};

repo: ref git->Repo;
gitdir: string;
dflag := 0;
ss: ref Styxserver;

# Object cache: index -> CEntry
cache: array of ref CEntry;
ncache := 0;
MAXCACHE: con 4096;

# Qid path -> node info
Qnode: adt {
	qpath:   big;
	name:    string;
	parent:  big;    # parent qid path
	hash:    git->Hash;
	otype:   int;    # Qt_ type
	isdir:   int;
};

nodes: array of ref Qnode;
nnodes := 0;
MAXNODES: con 16384;

stderr: ref Sys->FD;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	arg = load Arg Arg->PATH;
	styx = load Styx Styx->PATH;
	styxservers = load Styxservers Styxservers->PATH;
	git = load Git Git->PATH;
	if(git == nil)
		fail(sprint("load Git: %r"));

	err := git->init();
	if(err != nil)
		fail("git init: " + err);

	styx->init();
	styxservers->init(styx);

	sys->pctl(sys->NEWPGRP, nil);

	arg->init(args);
	arg->setusage(arg->progname() + " [-D] [-m mtpt] gitdir");

	mtpt: string;
	while((ch := arg->opt()) != 0)
		case ch {
		'D' =>
			styxservers->traceset(1);
			dflag = 1;
		'm' =>
			mtpt = arg->earg();
		* =>
			arg->usage();
		}

	argv := arg->argv();
	if(len argv != 1)
		arg->usage();

	gitdir = hd argv;

	# Open repository
	(r, oerr) := git->openrepo(gitdir);
	if(oerr != nil)
		fail("openrepo " + gitdir + ": " + oerr);
	repo = r;

	# Initialize caches
	cache = array [MAXCACHE] of ref CEntry;
	nodes = array [MAXNODES] of ref Qnode;

	# Create root node
	rootqid := allocnode("", big 0, git->nullhash(), Qt_ROOT, 1);

	# Set up mount point
	if(mtpt == nil)
		mtpt = gitdir + "/fs";

	# Create mount point directory
	sys->create(mtpt, Sys->OREAD, Sys->DMDIR | 8r755);

	# Create pipe for styx
	fds := array [2] of ref Sys->FD;
	if(sys->pipe(fds) < 0)
		fail(sprint("pipe: %r"));

	navchan := chan of ref Navop;
	nav := Navigator.new(navchan);
	spawn navigator(navchan);

	msgc: chan of ref Tmsg;
	(msgc, ss) = Styxserver.new(fds[0], nav, big rootqid);
	fds[0] = nil;

	# Spawn serve loop BEFORE mount — mount sends Tversion which the
	# serve loop must process (via ss.default) before mount can return.
	pidc := chan of int;
	spawn serveloop(msgc, pidc);
	<-pidc;

	if(sys->mount(fds[1], nil, mtpt, Sys->MREPL, nil) < 0)
		fail(sprint("mount %s: %r", mtpt));

	sys->print("git/fs mounted on %s\n", mtpt);
}

serveloop(msgc: chan of ref Tmsg, pidc: chan of int)
{
	pidc <-= sys->pctl(Sys->NEWFD, 0 :: 1 :: 2 :: ss.fd.fd :: nil);

Serve:
	for(;;) {
		mm := <-msgc;
		if(mm == nil) {
			say("eof");
			break Serve;
		}

		pick m := mm {
		Readerror =>
			say("read error: " + m.error);
			break Serve;

		Read =>
			(c, rerr) := ss.canread(m);
			if(c == nil) {
				ss.reply(ref Rmsg.Error(m.tag, rerr));
				continue;
			}
			if(c.qtype & Sys->QTDIR) {
				ss.default(m);
				continue;
			}

			# Read file content
			data := readfile(c.path);
			if(data == nil)
				data = array [0] of byte;
			ss.reply(styxservers->readbytes(m, data));

		* =>
			ss.default(m);
		}
	}
}

# =====================================================================
# Node Management
# =====================================================================

allocnode(name: string, parent: big, hash: git->Hash, otype, isdir: int): int
{
	idx := nnodes;
	if(idx >= MAXNODES) {
		say("node table full");
		return 0;
	}
	qpath := big ((otype << QSHIFT) | idx);
	n := ref Qnode(qpath, name, parent, hash, otype, isdir);
	nodes[idx] = n;
	nnodes++;
	return idx;
}

getnode(qpath: big): ref Qnode
{
	idx := int (qpath & big QMASK);
	if(idx < 0 || idx >= nnodes)
		return nil;
	return nodes[idx];
}

# Find child node by name under parent
findchild(parentpath: big, name: string): ref Qnode
{
	for(i := 0; i < nnodes; i++) {
		n := nodes[i];
		if(n != nil && n.parent == parentpath && n.name == name)
			return n;
	}
	return nil;
}

# =====================================================================
# Object Cache
# =====================================================================

getobj(h: git->Hash): ref CEntry
{
	hexstr := h.hex();
	for(i := 0; i < ncache; i++)
		if(cache[i] != nil && cache[i].hash.hex() == hexstr)
			return cache[i];

	# Load from repo
	(otype, data, err) := repo.readobj(h);
	if(err != nil)
		return nil;

	ce := ref CEntry(h, otype, data);
	if(ncache < MAXCACHE) {
		cache[ncache++] = ce;
	}
	return ce;
}

# =====================================================================
# Navigator
# =====================================================================

navigator(c: chan of ref Navop)
{
	for(;;) {
		navop := <-c;
		if(dflag) say(sprint("navop path=%bd", navop.path));

		pick n := navop {
		Stat =>
			d := nodestat(navop.path);
			if(d == nil)
				n.reply <-= (nil, Enotfound);
			else
				n.reply <-= (d, nil);

		Walk =>
			if(dflag) say(sprint("walk parent=%bd name=%q", n.path, n.name));
			d := walknode(n.path, n.name);
			if(d == nil)
				n.reply <-= (nil, Enotfound);
			else
				n.reply <-= (d, nil);

		Readdir =>
			if(dflag) say(sprint("readdir path=%bd off=%d count=%d", n.path, n.offset, n.count));
			children := listchildren(n.path);
			sent := 0;
			idx := 0;
			for(cl := children; cl != nil; cl = tl cl) {
				if(idx >= n.offset && sent < n.count) {
					n.reply <-= (hd cl, nil);
					sent++;
				}
				idx++;
			}
			n.reply <-= (nil, nil);
		}
	}
}

nodestat(qpath: big): ref Sys->Dir
{
	node := getnode(qpath);
	if(node == nil)
		return nil;

	d := ref Sys->Dir;
	d.name = node.name;
	if(d.name == nil || d.name == "")
		d.name = "/";
	d.uid = "git";
	d.gid = "git";
	d.muid = "git";
	d.qid.path = qpath;
	d.qid.vers = 0;
	d.atime = 0;
	d.mtime = 0;
	d.dtype = 0;
	d.dev = 0;

	if(node.isdir) {
		d.qid.qtype = Sys->QTDIR;
		d.mode = Sys->DMDIR | 8r555;
		d.length = big 0;
	} else {
		d.qid.qtype = Sys->QTFILE;
		d.mode = 8r444;
		data := readfile(qpath);
		if(data != nil)
			d.length = big len data;
		else
			d.length = big 0;
	}

	return d;
}

walknode(parentpath: big, name: string): ref Sys->Dir
{
	if(name == "..") {
		parent := getnode(parentpath);
		if(parent != nil)
			return nodestat(parent.parent);
		return nodestat(big 0);
	}

	# Check if child already exists
	child := findchild(parentpath, name);
	if(child != nil)
		return nodestat(child.qpath);

	# Create child on demand
	parent := getnode(parentpath);
	if(parent == nil)
		return nil;

	nqpath := createchild(parent, name);
	if(nqpath < big 0)
		return nil;

	return nodestat(nqpath);
}

createchild(parent: ref Qnode, name: string): big
{
	case parent.otype {
	Qt_ROOT =>
		return createrootchild(parent, name);
	Qt_COMMITDIR =>
		return createcommitchild(parent, name);
	Qt_TREEDIR =>
		return createtreechild(parent, name);
	Qt_BRANCHDIR =>
		return createbranchchild(parent, name);
	Qt_HEADSDIR =>
		return createheadschild(parent, name);
	Qt_REMOTEDIR =>
		return createremotechild(parent, name);
	Qt_TAGDIR =>
		return createtagchild(parent, name);
	Qt_OBJECTDIR =>
		return createobjectchild(parent, name);
	}
	return big -1;
}

createrootchild(parent: ref Qnode, name: string): big
{
	case name {
	"ctl" =>
		idx := allocnode("ctl", parent.qpath, git->nullhash(), Qt_CTL, 0);
		return nodes[idx].qpath;
	"HEAD" =>
		# Resolve HEAD to a commit
		(refname, err) := repo.head();
		if(err != nil)
			return big -1;
		(h, herr) := repo.readref(refname);
		if(herr != nil)
			return big -1;
		idx := allocnode("HEAD", parent.qpath, h, Qt_COMMITDIR, 1);
		return nodes[idx].qpath;
	"branch" =>
		idx := allocnode("branch", parent.qpath, git->nullhash(), Qt_BRANCHDIR, 1);
		return nodes[idx].qpath;
	"tag" =>
		idx := allocnode("tag", parent.qpath, git->nullhash(), Qt_TAGDIR, 1);
		return nodes[idx].qpath;
	"object" =>
		idx := allocnode("object", parent.qpath, git->nullhash(), Qt_OBJECTDIR, 1);
		return nodes[idx].qpath;
	}
	return big -1;
}

createcommitchild(parent: ref Qnode, name: string): big
{
	ce := getobj(parent.hash);
	if(ce == nil || ce.otype != git->OBJ_COMMIT)
		return big -1;

	(commit, err) := git->parsecommit(ce.data);
	if(err != nil)
		return big -1;

	case name {
	"hash" =>
		idx := allocnode("hash", parent.qpath, parent.hash, Qt_CHASH, 0);
		return nodes[idx].qpath;
	"author" =>
		idx := allocnode("author", parent.qpath, parent.hash, Qt_CAUTHOR, 0);
		return nodes[idx].qpath;
	"committer" =>
		idx := allocnode("committer", parent.qpath, parent.hash, Qt_CCOMMIT, 0);
		return nodes[idx].qpath;
	"msg" =>
		idx := allocnode("msg", parent.qpath, parent.hash, Qt_CMSG, 0);
		return nodes[idx].qpath;
	"parent" =>
		idx := allocnode("parent", parent.qpath, parent.hash, Qt_CPARENT, 0);
		return nodes[idx].qpath;
	"tree" =>
		idx := allocnode("tree", parent.qpath, commit.tree, Qt_TREEDIR, 1);
		return nodes[idx].qpath;
	}
	return big -1;
}

createtreechild(parent: ref Qnode, name: string): big
{
	ce := getobj(parent.hash);
	if(ce == nil || ce.otype != git->OBJ_TREE)
		return big -1;

	(entries, err) := git->parsetree(ce.data);
	if(err != nil)
		return big -1;

	for(i := 0; i < len entries; i++) {
		if(entries[i].name == name) {
			e := entries[i];
			# Look up the object to determine if it's a tree or blob
			obj := getobj(e.hash);
			if(obj == nil)
				return big -1;

			if(obj.otype == git->OBJ_TREE) {
				idx := allocnode(name, parent.qpath, e.hash, Qt_TREEDIR, 1);
				return nodes[idx].qpath;
			} else {
				idx := allocnode(name, parent.qpath, e.hash, Qt_BLOB, 0);
				return nodes[idx].qpath;
			}
		}
	}
	return big -1;
}

createbranchchild(parent: ref Qnode, name: string): big
{
	case name {
	"heads" =>
		idx := allocnode("heads", parent.qpath, git->nullhash(), Qt_HEADSDIR, 1);
		return nodes[idx].qpath;
	"remotes" =>
		idx := allocnode("remotes", parent.qpath, git->nullhash(), Qt_REMOTEDIR, 1);
		return nodes[idx].qpath;
	}
	return big -1;
}

createheadschild(parent: ref Qnode, name: string): big
{
	(h, err) := repo.readref("refs/heads/" + name);
	if(err != nil)
		return big -1;
	idx := allocnode(name, parent.qpath, h, Qt_COMMITDIR, 1);
	return nodes[idx].qpath;
}

createremotechild(parent: ref Qnode, name: string): big
{
	# List remotes or remote branches
	# Walk refs/remotes/<name>/...
	# First check if this is a remote name (directory of branches)
	refs := repo.listrefs();
	prefix := "refs/remotes/" + name + "/";
	for(rl := refs; rl != nil; rl = tl rl) {
		(refname, nil) := hd rl;
		if(len refname >= len prefix && refname[:len prefix] == prefix) {
			# This is a remote name, create a directory
			idx := allocnode(name, parent.qpath, git->nullhash(), Qt_REMOTEDIR, 1);
			return nodes[idx].qpath;
		}
	}

	# Check if it's a branch name under a remote
	# Parent chain: remotes/<remote>/<branch>
	# Try reading directly as a ref
	pnode := getnode(parent.parent);
	if(pnode != nil && pnode.otype == Qt_REMOTEDIR) {
		# parent.name is the remote, name is the branch
		refname := "refs/remotes/" + parent.name + "/" + name;
		(h, err) := repo.readref(refname);
		if(err == nil) {
			idx := allocnode(name, parent.qpath, h, Qt_COMMITDIR, 1);
			return nodes[idx].qpath;
		}
	}

	return big -1;
}

createtagchild(parent: ref Qnode, name: string): big
{
	(h, err) := repo.readref("refs/tags/" + name);
	if(err != nil)
		return big -1;

	# Tags may point to tag objects or directly to commits
	ce := getobj(h);
	if(ce == nil)
		return big -1;

	if(ce.otype == git->OBJ_TAG) {
		(tag, terr) := git->parsetag(ce.data);
		if(terr != nil)
			return big -1;
		# Follow to the commit
		idx := allocnode(name, parent.qpath, tag.obj, Qt_COMMITDIR, 1);
		return nodes[idx].qpath;
	}

	# Direct commit
	idx := allocnode(name, parent.qpath, h, Qt_COMMITDIR, 1);
	return nodes[idx].qpath;
}

createobjectchild(parent: ref Qnode, name: string): big
{
	# name should be a 40-char hex hash
	if(len name != git->HEXSIZE)
		return big -1;

	(h, err) := git->parsehash(name);
	if(err != nil)
		return big -1;

	ce := getobj(h);
	if(ce == nil)
		return big -1;

	case ce.otype {
	git->OBJ_COMMIT =>
		idx := allocnode(name, parent.qpath, h, Qt_COMMITDIR, 1);
		return nodes[idx].qpath;
	git->OBJ_TREE =>
		idx := allocnode(name, parent.qpath, h, Qt_TREEDIR, 1);
		return nodes[idx].qpath;
	git->OBJ_BLOB =>
		idx := allocnode(name, parent.qpath, h, Qt_BLOB, 0);
		return nodes[idx].qpath;
	git->OBJ_TAG =>
		(tag, terr) := git->parsetag(ce.data);
		if(terr == nil) {
			idx := allocnode(name, parent.qpath, tag.obj, Qt_COMMITDIR, 1);
			return nodes[idx].qpath;
		}
	}
	return big -1;
}

# =====================================================================
# List Children
# =====================================================================

listchildren(qpath: big): list of ref Sys->Dir
{
	node := getnode(qpath);
	if(node == nil)
		return nil;

	# First return any existing children
	result: list of ref Sys->Dir;

	case node.otype {
	Qt_ROOT =>
		result = ensuredir(node, "ctl") :: nil;
		result = ensuredir(node, "HEAD") :: result;
		result = ensuredir(node, "branch") :: result;
		result = ensuredir(node, "tag") :: result;
		result = ensuredir(node, "object") :: result;

	Qt_COMMITDIR =>
		result = ensuredir(node, "hash") :: nil;
		result = ensuredir(node, "author") :: result;
		result = ensuredir(node, "committer") :: result;
		result = ensuredir(node, "msg") :: result;
		result = ensuredir(node, "parent") :: result;
		result = ensuredir(node, "tree") :: result;

	Qt_TREEDIR =>
		ce := getobj(node.hash);
		if(ce != nil && ce.otype == git->OBJ_TREE) {
			(entries, err) := git->parsetree(ce.data);
			if(err == nil) {
				for(i := 0; i < len entries; i++)
					result = ensuredir(node, entries[i].name) :: result;
			}
		}

	Qt_BRANCHDIR =>
		result = ensuredir(node, "heads") :: nil;
		result = ensuredir(node, "remotes") :: result;

	Qt_HEADSDIR =>
		refs := repo.listrefs();
		for(rl := refs; rl != nil; rl = tl rl) {
			(refname, nil) := hd rl;
			if(len refname > 11 && refname[:11] == "refs/heads/") {
				name := refname[11:];
				result = ensuredir(node, name) :: result;
			}
		}

	Qt_REMOTEDIR =>
		refs := repo.listrefs();
		# If this is the top-level remotes dir
		if(node.name == "remotes") {
			# List unique remote names
			seen: list of string;
			for(rl := refs; rl != nil; rl = tl rl) {
				(refname, nil) := hd rl;
				if(len refname > 13 && refname[:13] == "refs/remotes/") {
					rest := refname[13:];
					# Get first component
					for(i := 0; i < len rest; i++) {
						if(rest[i] == '/') {
							rname := rest[:i];
							if(!inlist(rname, seen)) {
								seen = rname :: seen;
								result = ensuredir(node, rname) :: result;
							}
							break;
						}
					}
				}
			}
		} else {
			# List branches under this remote
			prefix := "refs/remotes/" + node.name + "/";
			for(rl := refs; rl != nil; rl = tl rl) {
				(refname, nil) := hd rl;
				if(len refname > len prefix && refname[:len prefix] == prefix) {
					name := refname[len prefix:];
					# Only direct children (no nested /)
					nested := 0;
					for(i := 0; i < len name; i++)
						if(name[i] == '/') {
							nested = 1;
							break;
						}
					if(!nested)
						result = ensuredir(node, name) :: result;
				}
			}
		}

	Qt_TAGDIR =>
		refs := repo.listrefs();
		for(rl := refs; rl != nil; rl = tl rl) {
			(refname, nil) := hd rl;
			if(len refname > 10 && refname[:10] == "refs/tags/") {
				name := refname[10:];
				result = ensuredir(node, name) :: result;
			}
		}

	Qt_OBJECTDIR =>
		# Don't enumerate all objects (too many)
		;
	}

	# Reverse to preserve order
	return revdirs(result);
}

ensuredir(parent: ref Qnode, name: string): ref Sys->Dir
{
	# Find or create child node
	child := findchild(parent.qpath, name);
	if(child == nil) {
		nqpath := createchild(parent, name);
		if(nqpath >= big 0)
			child = getnode(nqpath);
	}
	if(child != nil)
		return nodestat(child.qpath);

	# Fallback: return a placeholder
	d := ref Sys->Dir;
	d.name = name;
	d.uid = "git";
	d.gid = "git";
	d.muid = "git";
	d.qid.path = big 0;
	d.qid.vers = 0;
	d.qid.qtype = Sys->QTFILE;
	d.mode = 8r444;
	d.length = big 0;
	d.atime = 0;
	d.mtime = 0;
	d.dtype = 0;
	d.dev = 0;
	return d;
}

# =====================================================================
# Read File Content
# =====================================================================

readfile(qpath: big): array of byte
{
	node := getnode(qpath);
	if(node == nil)
		return nil;

	case node.otype {
	Qt_CTL =>
		(refname, err) := repo.head();
		if(err != nil)
			return nil;
		# Strip refs/heads/ prefix
		if(len refname > 11 && refname[:11] == "refs/heads/")
			refname = refname[11:];
		return array of byte (refname + "\n");

	Qt_CHASH =>
		return array of byte (node.hash.hex() + "\n");

	Qt_CAUTHOR =>
		ce := getobj(node.hash);
		if(ce == nil)
			return nil;
		(commit, err) := git->parsecommit(ce.data);
		if(err != nil)
			return nil;
		return array of byte (commit.author + "\n");

	Qt_CCOMMIT =>
		ce := getobj(node.hash);
		if(ce == nil)
			return nil;
		(commit, err) := git->parsecommit(ce.data);
		if(err != nil)
			return nil;
		return array of byte (commit.committer + "\n");

	Qt_CMSG =>
		ce := getobj(node.hash);
		if(ce == nil)
			return nil;
		(commit, err) := git->parsecommit(ce.data);
		if(err != nil)
			return nil;
		return array of byte commit.msg;

	Qt_CPARENT =>
		ce := getobj(node.hash);
		if(ce == nil)
			return nil;
		(commit, err) := git->parsecommit(ce.data);
		if(err != nil)
			return nil;
		s := "";
		for(pl := commit.parents; pl != nil; pl = tl pl)
			s += (hd pl).hex() + "\n";
		return array of byte s;

	Qt_BLOB =>
		ce := getobj(node.hash);
		if(ce == nil)
			return nil;
		return ce.data;
	}

	return nil;
}

# =====================================================================
# Helpers
# =====================================================================

inlist(s: string, l: list of string): int
{
	return git->inlist(s, l);
}

revdirs(l: list of ref Sys->Dir): list of ref Sys->Dir
{
	r: list of ref Sys->Dir;
	for(; l != nil; l = tl l)
		r = (hd l) :: r;
	return r;
}

pid(): int
{
	return sys->pctl(0, nil);
}

killgrp(pid: int)
{
	sys->fprint(sys->open(sprint("/prog/%d/ctl", pid), sys->OWRITE), "killgrp");
}

say(s: string)
{
	if(dflag)
		sys->fprint(stderr, "git/fs: %s\n", s);
}

fail(s: string)
{
	sys->fprint(stderr, "git/fs: %s\n", s);
	raise "fail:" + s;
}
