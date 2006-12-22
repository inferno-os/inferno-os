implement Updatelog;

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "daytime.m";
	daytime: Daytime;

include "string.m";
	str: String;

include "keyring.m";
	kr: Keyring;

include "logs.m";
	logs: Logs;
	Db, Entry, Byname, Byseq: import logs;
	S, mkpath: import logs;
	Log: type Entry;

include "fsproto.m";
	fsproto: FSproto;
	Direntry: import fsproto;

include "arg.m";

Updatelog: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

now: int;
gen := 0;
changesonly := 0;
uid: string;
gid: string;
debug := 0;
state: ref Db;
rootdir := ".";
scanonly: list of string;
exclude: list of string;
sums := 0;
stderr: ref Sys->FD;
Seen: con 1<<31;
bout: ref Iobuf;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	ensure(bufio, Bufio->PATH);
	fsproto = load FSproto FSproto->PATH;
	ensure(fsproto, FSproto->PATH);
	daytime = load Daytime Daytime->PATH;
	ensure(daytime, Daytime->PATH);
	str = load String String->PATH;
	ensure(str, String->PATH);
	logs = load Logs Logs->PATH;
	ensure(logs, Logs->PATH);
	kr = load Keyring Keyring->PATH;
	ensure(kr, Keyring->PATH);

	arg := load Arg Arg->PATH;
	if(arg == nil)
		error(sys->sprint("can't load %s: %r", Arg->PATH));

	protofile := "/lib/proto/all";
	arg->init(args);
	arg->setusage("updatelog [-p proto] [-r root] [-t now gen] [-c] [-x path] x.log [path ...]");
	while((o := arg->opt()) != 0)
		case o {
		'D' =>
			debug = 1;
		'p' =>
			protofile = arg->earg();
		'r' =>
			rootdir = arg->earg();
		'c' =>
			changesonly = 1;
		'u' =>
			uid = arg->earg();
		'g' =>
			gid = arg->earg();
		's' =>
			sums = 1;
		't' =>
			now = int arg->earg();
			gen = int arg->earg();
		'x' =>
			s := arg->earg();
			exclude = trimpath(s) :: exclude;
		* =>
			arg->usage();
		}
	args = arg->argv();
	if(args == nil)
		arg->usage();
	arg = nil;

	stderr = sys->fildes(2);
	bout = bufio->fopen(sys->fildes(1), Bufio->OWRITE);

	fsproto->init();
	logs->init(bufio);

	logfile := hd args;
	while((args = tl args) != nil)
		scanonly = trimpath(hd args) :: scanonly;
	checkroot(rootdir, "replica root");

	state = Db.new("server state");

	#
	# replay log to rebuild server state
	#
	logfd := sys->open(logfile, Sys->OREAD);
	if(logfd == nil)
		error(sys->sprint("can't open %s: %r", logfile));
	f := bufio->fopen(logfd, Sys->OREAD);
	if(f == nil)
		error(sys->sprint("can't open %s: %r", logfile));
	while((log := readlog(f)) != nil)
		replaylog(state, log);

	#
	# walk the set of names produced by the proto file, comparing against the server state
	#
	now = daytime->now();
	doproto(rootdir, protofile);

	if(changesonly){
		bout.flush();
		exit;
	}

	#
	# names in the original state that we didn't see in the walk must have been removed:
	# print 'd' log entries for them, in reverse lexicographic order (children before parents)
	#
	state.sort(Logs->Byname);
	for(i := state.nstate; --i >= 0;){
		e := state.state[i];
		if((e.x & Seen) == 0 && considered(e.path)){
			change('d', e, e.seq, e.d, e.path, e.serverpath, e.contents);	# TO DO: content
			if(debug)
				sys->fprint(sys->fildes(2), "remove %q\n", e.path);
		}
	}
	bout.flush();
}

ensure[T](m: T, path: string)
{
	if(m == nil)
		error(sys->sprint("can't load %s: %r", path));
}

checkroot(dir: string, what: string)
{
	(ok, d) := sys->stat(dir);
	if(ok < 0)
		error(sys->sprint("can't stat %s %q: %r", what, dir));
	if((d.mode & Sys->DMDIR) == 0)
		error(sys->sprint("%s %q: not a directory", what, dir));
}

considered(s: string): int
{
	if(scanonly != nil && !islisted(s, scanonly))
		return 0;
	return exclude == nil || !islisted(s, exclude);
}

readlog(in: ref Iobuf): ref Log
{
	(e, err) := Entry.read(in);
	if(err != nil)
		error(err);
	return e;
}

#
# replay a log to reach the state wrt files previously taken from the server
#
replaylog(db: ref Db, log: ref Log)
{
	e := db.look(log.path);
	indb := e != nil && !e.removed();
	case log.action {
	'a' =>	# add new file
		if(indb){
			note(sys->sprint("%q duplicate create", log.path));
			return;
		}
	'c' =>	# contents
		if(!indb){
			note(sys->sprint("%q contents but no entry", log.path));
			return;
		}
	'd' =>	# delete
		if(!indb){
			note(sys->sprint("%q deleted but no entry", log.path));
			return;
		}
		if(e.d.mtime > log.d.mtime){
			note(sys->sprint("%q deleted but it's newer", log.path));
			return;
		}
	'm' =>	# metadata
		if(!indb){
			note(sys->sprint("%q metadata but no entry", log.path));
			return;
		}
	* =>
		error(sys->sprint("bad log entry: %bd %bd", log.seq>>32, log.seq & big 16rFFFFFFFF));
	}
	update(db, e, log);
}

#
# update file state e to reflect the effect of the log,
# creating a new entry if necessary
#
update(db: ref Db, e: ref Entry, log: ref Entry)
{
	if(e == nil)
		e = db.entry(log.seq, log.path, log.d);
	e.update(log);
}

doproto(tree: string, protofile: string)
{
	entries := chan of Direntry;
	warnings := chan of (string, string);
	err := fsproto->readprotofile(protofile, tree, entries, warnings);
	if(err != nil)
		error(sys->sprint("can't read %s: %s", protofile, err));
	for(;;)alt{
	(old, new, d) := <-entries =>
		if(d == nil)
			return;
		if(debug)
			sys->fprint(stderr, "old=%q new=%q length=%bd\n", old, new, d.length);
		while(new != nil && new[0] == '/')
			new = new[1:];
		if(!considered(new))
			continue;
		if(sums && (d.mode & Sys->DMDIR) == 0)
			digests := md5sum(old) :: nil;
		if(uid != nil)
			d.uid = uid;
		if(gid != nil)
			d.gid = gid;
		old = relative(old, rootdir);
		db := state.look(new);
		if(db == nil){
			if(!changesonly){
				db = state.entry(nextseq(), new, *d);
				change('a', db, db.seq, db.d, db.path, old, digests);
			}
		}else{
			if(!samestat(db.d, *d))
				change('c', db, nextseq(), *d, new, old, digests);
			if(!samemeta(db.d, *d))
				change('m', db, nextseq(), *d, new, old, nil);	# need digest?
		}
		if(db != nil)
			db.x |= Seen;
	(old, msg) := <-warnings =>
		#if(contains(msg, "entry not found") || contains(msg, "not exist"))
		#	break;
		sys->fprint(sys->fildes(2), "updatelog: warning[old=%s]: %s\n", old, msg);
	}
}

change(action: int, e: ref Entry, seq: big, d: Sys->Dir, path: string, serverpath: string, digests: list of string)
{
	log := ref Entry;
	log.seq = seq;
	log.action = action;
	log.d = d;
	log.path = path;
	log.serverpath = serverpath;
	log.contents = digests;
	e.update(log);
	bout.puts(log.logtext()+"\n");
}

samestat(a: Sys->Dir, b: Sys->Dir): int
{
	# doesn't check permission/ownership, does check QTDIR/QTFILE
	if(a.mode & Sys->DMDIR)
		return (b.mode & Sys->DMDIR) != 0;
	return a.length == b.length && a.mtime == b.mtime && a.qid.qtype == b.qid.qtype;	# TO DO: a.name==b.name?
}

samemeta(a: Sys->Dir, b: Sys->Dir): int
{
	return a.mode == b.mode && (uid == nil || a.uid == b.uid) && (gid == nil || a.gid == b.gid) && samestat(a, b);
}

nextseq(): big
{
	return (big now << 32) | big gen++;
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "updatelog: %s\n", s);
	raise "fail:error";
}

note(s: string)
{
	sys->fprint(sys->fildes(2), "updatelog: note: %s\n", s);
}

contains(s: string, sub: string): int
{
	return str->splitstrl(s, sub).t1 != nil;
}

isprefix(a, b: string): int
{
	la := len a;
	lb := len b;
	if(la > lb)
		return 0;
	if(la == lb)
		return a == b;
	return a == b[0:la] && b[la] == '/';
}

trimpath(s: string): string
{
	while(len s > 1 && s[len s-1] == '/')
		s = s[0:len s-1];
	while(s != nil && s[0] == '/')
		s = s[1:];
	return s;
}

relative(name: string, root: string): string
{
	if(root == nil || name == nil)
		return name;
	if(isprefix(root, name)){
		name = name[len root:];
		while(name != nil && name[0] == '/')
			name = name[1:];
	}
	return name;
}

islisted(s: string, l: list of string): int
{
	for(; l != nil; l = tl l)
		if(isprefix(hd l, s))
			return 1;
	return 0;
}

md5sum(file: string): string
{
	fd := sys->open(file, Sys->OREAD);
	if(fd == nil)
		error(sys->sprint("can't open %s: %r", file));
	ds: ref Keyring->DigestState;
	buf := array[Sys->ATOMICIO] of byte;
	while((n := sys->read(fd, buf, len buf)) > 0)
		ds = kr->md5(buf, n, nil, ds);
	if(n < 0)
		error(sys->sprint("error reading %s: %r", file));
	digest := array[Keyring->MD5dlen] of byte;
	kr->md5(nil, 0, digest, ds);
	s: string;
	for(i := 0; i < len digest; i++)
		s += sys->sprint("%.2ux", int digest[i]);
	return s;
}
