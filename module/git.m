Git: module
{
	PATH: con "/dis/lib/git/git.dis";
	init: fn(): string;

	# --- Constants ---

	SHA1SIZE: con 20;
	HEXSIZE:  con 40;

	OBJ_COMMIT:    con 1;
	OBJ_TREE:      con 2;
	OBJ_BLOB:      con 3;
	OBJ_TAG:       con 4;
	OBJ_OFS_DELTA: con 6;
	OBJ_REF_DELTA: con 7;

	# --- Core Types ---

	Hash: adt {
		a: array of byte;		# 20 bytes

		eq:    fn(h: self Hash, o: Hash): int;
		hex:   fn(h: self Hash): string;
		isnil: fn(h: self Hash): int;
	};
	parsehash:  fn(s: string): (Hash, string);
	nullhash:   fn(): Hash;
	hashobj:    fn(otype: int, data: array of byte): Hash;
	typename:   fn(otype: int): string;
	typenum:    fn(name: string): int;

	# --- Repository ---

	Repo: adt {
		path:  string;			# .git/ directory path
		packs: list of ref Pack;

		readobj:  fn(r: self ref Repo, h: Hash): (int, array of byte, string);
		hasobj:   fn(r: self ref Repo, h: Hash): int;
		readref:  fn(r: self ref Repo, name: string): (Hash, string);
		listrefs: fn(r: self ref Repo): list of (string, Hash);
		head:     fn(r: self ref Repo): (string, string);
		checkout: fn(r: self ref Repo, treehash: Hash, destpath: string): string;
	};
	openrepo: fn(path: string): (ref Repo, string);
	initrepo: fn(path: string, bare: int): (ref Repo, string);

	# --- Pack Files ---

	Pack: adt {
		path: string;
		idx:  ref PackIdx;

		lookup: fn(p: self ref Pack, h: Hash): (int, array of byte, string);
	};
	PackIdx: adt {
		fanout:  array of int;		# 256 entries
		hashes:  array of byte;		# sorted, 20 bytes each
		offsets: array of int;		# 4-byte offsets
		largeoffsets: array of big;
		nobj:    int;

		find: fn(idx: self ref PackIdx, h: Hash): (big, int);
	};
	openpack:  fn(packpath: string): (ref Pack, string);
	indexpack: fn(packpath: string): string;

	# --- Object Parsing ---

	Commit: adt {
		tree:      Hash;
		parents:   list of Hash;
		author:    string;
		committer: string;
		msg:       string;
	};
	parsecommit: fn(data: array of byte): (ref Commit, string);

	TreeEntry: adt {
		mode: int;
		name: string;
		hash: Hash;
	};
	parsetree: fn(data: array of byte): (array of TreeEntry, string);

	Tag: adt {
		obj:    Hash;
		otype:  int;
		name:   string;
		tagger: string;
		msg:    string;
	};
	parsetag: fn(data: array of byte): (ref Tag, string);

	# --- Pkt-line Protocol ---

	pktread:  fn(fd: ref Sys->FD): (array of byte, string);
	pktwrite: fn(fd: ref Sys->FD, data: array of byte): string;
	pktflush: fn(fd: ref Sys->FD): string;

	# --- Transport ---

	Ref: adt {
		name: string;
		hash: Hash;
	};

	ObjRef: adt {
		hash: Hash;
		otype: int;
		data: array of byte;
	};

	RefUpdate: adt {
		oldhash: Hash;
		newhash: Hash;
		name: string;
	};

	discover:  fn(url: string): (list of Ref, list of string, string);
	fetchpack: fn(url: string, want: list of Hash,
		       have: list of Hash, outpath: string): string;
	discover_receive: fn(url: string): (list of Ref, list of string, string);
	enumobjects: fn(repo: ref Repo, want, have: list of Hash): (list of ref ObjRef, string);
	writepack: fn(objects: list of ref ObjRef): (array of byte, string);
	sendpack: fn(url: string, updates: list of ref RefUpdate,
		     packdata: array of byte, creds: string): string;
	readcredentials: fn(gitdir: string): string;

	# --- Delta ---

	applydelta: fn(base, delta: array of byte): (array of byte, string);

	# --- Shared Helpers ---

	splitline:    fn(s: string): (string, string);
	splitfirst:   fn(s: string, sep: int): (string, string);
	findgitdir:   fn(dir: string): string;
	getremoteurl: fn(gitdir, remote: string): string;
	writeref:     fn(gitdir, name: string, h: Hash);
	writesymref:  fn(gitdir, name, target: string);
	mkdirp:       fn(filepath: string);
	copyfile:     fn(src, dst: string);
	strtrim:      fn(s: string): string;
	inlist:       fn(s: string, l: list of string): int;
	renamepak:    fn(gitdir, packpath, packname: string);
	updaterefs:   fn(gitdir, remote: string, refs: list of Ref, verbose: int);
	isancestor:   fn(repo: ref Repo, ancestor, descendant: Hash): int;
	isclean:      fn(repo: ref Repo, treehash: Hash, workdir: string): (int, string);

	# --- Write Path ---

	zcompress:       fn(data: array of byte): (array of byte, string);
	writelooseobj:   fn(repopath: string, otype: int, data: array of byte): (Hash, string);
	encodetree:      fn(entries: array of TreeEntry): array of byte;
	sorttreeentries: fn(entries: array of TreeEntry);

	# --- Index ---

	IndexEntry: adt {
		mode: int;
		hash: Hash;
		path: string;
	};
	loadindex:  fn(repopath: string): (list of IndexEntry, string);
	saveindex:  fn(repopath: string, entries: list of IndexEntry): string;
	clearindex: fn(repopath: string): string;
};
