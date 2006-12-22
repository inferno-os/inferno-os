implement Logs;

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "string.m";
	str: String;

include "logs.m";

Hashsize: con 1024;
Incr: con 500;

init(bio: Bufio): string
{
	sys = load Sys Sys->PATH;
	bufio = bio;
	str = load String String->PATH;
	if(str == nil)
		return sys->sprint("can't load %s: %r", String->PATH);
	return nil;
}

Entry.read(in: ref Iobuf): (ref Entry, string)
{
	if((s := in.gets('\n')) == nil)
		return (nil, nil);
	if(s[len s-1] == '\n')
		s = s[0:len s-1];

	e := ref Entry;
	e.x = -1;

	l := str->unquoted(s);
	fields := array[11] of string;
	for(i := 0; l != nil; l = tl l)
		fields[i++] = S(hd l);

	#  time gen verb path serverpath mode uid gid mtime length
	# 1064889121 4 a sys/src/cmd/ip/httpd/webls.denied - 664 sys sys 1064887847 3
	# time[0] gen[1] op[2] path[3] (serverpath|"-")[4] mode[5] uid[6] gid[7] mtime[8] length[9]

	if(i < 10 || len fields[2] != 1)
		return (nil, sys->sprint("bad log entry: %q", s));
	e.action = fields[2][0];
	case e.action {
	'a' or 'c' or 'd' or 'm' =>
		;
	* =>
		return (nil, sys->sprint("bad log entry: %q", s));
	}

	time := bigof(fields[0], 10);
	sgen := bigof(fields[1], 10);
	e.seq = (time << 32) | sgen;	# for easier comparison

	# time/gen check
	# name check

	if(fields[4] == "-")	# undocumented
		fields[4] = fields[3];
	e.path = fields[3];
	e.serverpath = fields[4];
	e.d = sys->nulldir;
	{
		e.d.mode = intof(fields[5], 8);
		e.d.qid.qtype = e.d.mode>>24;
		e.d.uid = fields[6];
		if(e.d.uid == "-")
			e.d.uid = "";
		e.d.gid = fields[7];
		if(e.d.gid == "-")
			e.d.gid = "";
		e.d.mtime = intof(fields[8], 10);
		e.d.length = bigof(fields[9], 10);
	}exception ex {
	"log format:*" =>
		return (nil, sys->sprint("%s in log entry %q", ex, s));
	}
	e.contents = fields[10] :: nil;	# optional
	return (e, nil);
}

rev[T](l: list of T): list of T
{
	rl: list of T;
	for(; l != nil; l = tl l)
		rl = hd l :: rl;
	return rl;
}

bigof(s: string, base: int): big
{
	(b, r) := str->tobig(s, base);
	if(r != nil)
		raise "invalid integer field";
	return b;
}

intof(s: string, base: int): int
{
	return int bigof(s, base);
}

mkpath(root: string, name: string): string
{
	if(len root > 0 && root[len root-1] != '/' && (len name == 0 || name[0] != '/'))
		return root+"/"+name;
	return root+name;
}

contents(e: ref Entry): string
{
	if(e.contents == nil)
		return "";
	s := "";
	for(cl := e.contents; cl != nil; cl = tl cl)
		s += " " + hd cl;
	return s[1:];
}

Entry.text(e: self ref Entry): string
{
	a := e.action;
	if(a == 0)
		a = '?';
	return sys->sprint("%bd %bd %q [%d] %c m=%uo l=%bd t=%ud c=%q", e.seq>>32, e.seq & 16rFFFFFFFF, e.path, e.x, a, e.d.mode, e.d.length, e.d.mtime, contents(e));
}

Entry.sumtext(e: self ref Entry): string
{
	case e.action {
	'a' or 'm' =>
		return sys->sprint("%c %q %uo %q %q %ud", e.action, e.path, e.d.mode, e.d.uid, e.d.gid, e.d.mtime);
	'd' or 'c' =>
		return sys->sprint("%c %q", e.action, e.path);
	* =>
		return sys->sprint("? %q", e.path);
	}
}

Entry.dbtext(e: self ref Entry): string
{
	#   path dpath|"-" mode uid gid mtime length
	return sys->sprint("%bd %bd %q - %uo %q %q %ud %bd%s", e.seq>>32, e.seq & 16rFFFFFFFF, e.path, e.d.mode, e.d.uid, e.d.gid, e.d.mtime, e.d.length, contents(e));
}

Entry.logtext(e: self ref Entry): string
{
	#   gen n act path spath|"-" dpath|"-" mode uid gid mtime length
	a := e.action;
	if(a == 0)
		a = '?';
	sf := e.serverpath;
	if(sf == nil || sf == e.path)
		sf = "-";
	return sys->sprint("%bd %bd %c %q %q %uo %q %q %ud %bd%s", e.seq>>32, e.seq & 16rFFFFFFFF, a, e.path, sf, e.d.mode, e.d.uid, e.d.gid, e.d.mtime, e.d.length, contents(e));
}

Entry.remove(e: self ref Entry)
{
	e.action = 'd';
}

Entry.removed(e: self ref Entry): int
{
	return e.action == 'd';
}

Entry.update(e: self ref Entry, n: ref Entry)
{
	if(n == nil)
		return;
	if(n.action == 'd')
		e.contents = nil;
	else
		e.d = n.d;
	if(n.action != 'm' || e.action == 'd')
		e.action = n.action;
	e.serverpath = S(n.serverpath);
	for(nl := rev(n.contents); nl != nil; nl = tl nl)
		e.contents = hd nl :: e.contents;
	if(n.seq > e.seq)
		e.seq = n.seq;
}

Db.new(name: string): ref Db
{
	db := ref Db;
	db.name = name;
	db.stateht = array[Hashsize] of list of ref Entry;
	db.nstate = 0;
	db.state = array[50] of ref Entry;
	return db;
}

Db.look(db: self ref Db, name: string): ref Entry
{
	(b, nil) := hash(name, len db.stateht);
	for(l := db.stateht[b]; l != nil; l = tl l)
		if((hd l).path == name)
			return hd l;
	return nil;
}

Db.entry(db: self ref Db, seq: big, name: string, d: Sys->Dir): ref Entry
{
	e := ref Entry;
	e.action = 'a';
	e.seq = seq;
	e.path = name;
	e.d = d;
	e.x = db.nstate++;
	if(e.x >= len db.state){
		a := array[len db.state + Incr] of ref Entry;
		a[0:]  = db.state;
		db.state = a;
	}
	db.state[e.x] = e;
	(b, nil) := hash(name, len db.stateht);
	db.stateht[b] = e :: db.stateht[b];
	return e;
}

Db.sort(db: self ref Db, key: int)
{
	sortentries(db.state[0:db.nstate], key);
}

sortentries(a: array of ref Entry, key: int): (array of ref Entry, int)
{
	mergesort(a, array[len a] of ref Entry, key);
	return (a, len a);
}
	
mergesort(a, b: array of ref Entry, key: int)
{
	r := len a;
	if(r > 1) {
		m := (r-1)/2 + 1;
		mergesort(a[0:m], b[0:m], key);
		mergesort(a[m:], b[m:], key);
		b[0:] = a;
		for((i, j, k) := (0, m, 0); i < m && j < r; k++) {
			if(key==Byname && b[i].path > b[j].path || key==Byseq && b[i].seq > b[j].seq)
				a[k] = b[j++];
			else
				a[k] = b[i++];
		}
		if(i < m)
			a[k:] = b[i:m];
		else if(j < r)
			a[k:] = b[j:r];
	}
}

strings:	array of list of string;

S(s: string): string
{
	if(strings == nil)
		strings = array[257] of list of string;
	h := hash(s, len strings).t0;
	for(sl := strings[h]; sl != nil; sl = tl sl)
		if(hd sl == s)
			return hd sl;
	strings[h] = s :: strings[h];
	return s;
}

hash(s: string, n: int): (int, int)
{
	# hashpjw
	h := 0;
	for(i:=0; i<len s; i++){
		h = (h<<4) + s[i];
		if((g := h & int 16rF0000000) != 0)
			h ^= ((g>>24) & 16rFF) | g;
	}
	return ((h&~(1<<31))%n, h);
}
