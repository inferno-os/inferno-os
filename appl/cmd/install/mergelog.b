implement Mergelog;

#
# combine old and new log sections into one with the most recent data
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "string.m";
	str: String;

include "keyring.m";
	kr: Keyring;

include "daytime.m";
	daytime: Daytime;

include "logs.m";
	logs: Logs;
	Db, Entry, Byname, Byseq: import logs;
	S: import logs;

include "arg.m";

Mergelog: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Apply, Applydb, Install, Asis, Skip: con iota;

client:	ref Db;	# client current state from client log
updates:	ref Db;	# state delta from new section of server log

nerror := 0;
nconflict := 0;
debug := 0;
verbose := 0;
resolve := 0;
setuid := 0;
setgid := 0;
nflag := 0;
timefile: string;
clientroot: string;
srvroot: string;
logfd: ref Sys->FD;
now := 0;
gen := 0;
noerr := 0;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	bufio = load Bufio Bufio->PATH;
	ensure(bufio, Bufio->PATH);
	str = load String String->PATH;
	ensure(str, String->PATH);
	kr = load Keyring Keyring->PATH;
	ensure(kr, Keyring->PATH);
	daytime = load Daytime Daytime->PATH;
	ensure(daytime, Daytime->PATH);
	logs = load Logs Logs->PATH;
	ensure(logs, Logs->PATH);
	logs->init(bufio);

	arg := load Arg Arg->PATH;
	ensure(arg, Arg->PATH);
	arg->init(args);
	arg->setusage("mergelog [-vd] oldlog [path ... ] <newlog");
	dump := 0;
	while((o := arg->opt()) != 0)
		case o {
		'd' =>	dump = 1; debug = 1;
		'v' =>	verbose = 1;
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args < 3)
		arg->usage();
	arg = nil;

	now = daytime->now();
	client = Db.new("existing log");
	updates = Db.new("update log");
	clientlog := hd args; args = tl args;
	if(args != nil)
		error("restriction by path not yet done");

	# replay the client log to build last installation state of files taken from server
	logfd = sys->open(clientlog, Sys->OREAD);
	if(logfd == nil)
		error(sys->sprint("can't open %s: %r", clientlog));
	f := bufio->fopen(logfd, Sys->OREAD);
	if(f == nil)
		error(sys->sprint("can't open %s: %r", clientlog));
	while((log := readlog(f)) != nil)
		replaylog(client, log);
	f = nil;

	# read new log entries and use the new section to build a sequence of update actions
	f = bufio->fopen(sys->fildes(0), Sys->OREAD);
	while((log = readlog(f)) != nil)
		replaylog(client, log);
	client.sort(Byseq);
	dumpdb(client);
	if(nerror)
		raise sys->sprint("fail:%d errors", nerror);
}

readlog(in: ref Iobuf): ref Entry
{
	(e, err) := Entry.read(in);
	if(err != nil)
		error(err);
	return e;
}

#
# replay a log to reach the state wrt files previously taken from the server
#
replaylog(db: ref Db, log: ref Entry)
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

rev[T](l: list of T): list of T
{
	rl: list of T;
	for(; l != nil; l = tl l)
		rl = hd l :: rl;
	return rl;
}

ensure[T](m: T, path: string)
{
	if(m == nil)
		error(sys->sprint("can't load %s: %r", path));
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "applylog: %s\n", s);
	raise "fail:error";
}

note(s: string)
{
	sys->fprint(sys->fildes(2), "applylog: note: %s\n", s);
}

warn(s: string)
{
	sys->fprint(sys->fildes(2), "applylog: warning: %s\n", s);
	nerror++;
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
	return a.mode == b.mode && (!setuid || a.uid == b.uid) && (!setgid || a.gid == b.gid) && samestat(a, b);
}

bigof(s: string, base: int): big
{
	(b, r) := str->tobig(s, base);
	if(r != nil)
		error("cruft in integer field in log entry: "+s);
	return b;
}

intof(s: string, base: int): int
{
	return int bigof(s, base);
}

dumpdb(db: ref Db)
{
	for(i := 0; i < db.nstate; i++){
		s := db.state[i].text();
		if(s != nil)
			sys->print("%s\n", s);
	}
}
