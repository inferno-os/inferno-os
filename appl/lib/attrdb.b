implement Attrdb;

#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "attrdb.m";

init(): string
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		return sys->sprint("can't load Bufio: %r");
	return nil;
}

parseentry(s: string, lno: int): (ref Dbentry, int, string)
{
	(nil, flds) := sys->tokenize(s, "\n");
	lines: list of ref Tuples;
	errs: string;
	for(; flds != nil; flds = tl flds){
		(ts, err) := parseline(hd flds, lno);
		if(ts != nil)
			lines = ts :: lines;
		else if(err != nil && errs == nil)
			errs = err;
		lno++;
	}
	return (ref Dbentry(0, lines), lno, errs);
}

parseline(s: string, lno: int): (ref Tuples, string)
{
	attrs: list of ref Attr;
	quote := 0;
	word := "";
	lastword := "";
	name := "";

Line:
	for(i := 0; i < len s; i++) {
		if(quote) {
			if(s[i] == quote) {
				if(i+1 >= len s || s[i+1] != quote){
					quote = 0;
					continue;
				}
				i++;
			}
			word[len word] = s[i];
			continue;
		}
		case s[i] {
		'\'' or '\"' =>
			quote = s[i];
		'#' =>
			break Line;
		' ' or '\t' or '\n' =>
			if(word == nil)
				continue;
			if(lastword != nil) {
				# lastword space word space
				attrs = ref Attr(lastword, nil, 0) :: attrs;
			}
			lastword = word;
			word = nil;

			if(name != nil) {
				# name = lastword space
				attrs = ref Attr(name, lastword, 0) :: attrs;
				name = lastword = nil;
			}
		'=' =>
			if(lastword == nil) {
				# word=
				lastword = word;
				word = nil;
			}
			if(word != nil) {
				# lastword word=
				attrs = ref Attr(lastword, nil, 0) :: attrs;
				lastword = word;
				word = nil;
			}
			if(lastword == nil)
				return (nil, "empty name");
			name = lastword;
			lastword = nil;
		* =>
			word[len word] = s[i];
		}
	}
	if(quote)
		return (nil, "missing quote");

	if(lastword == nil) {
		lastword = word;
		word = nil;
	}

	if(name == nil) {
		name = lastword;
		lastword = nil;
	}

	if(name != nil)
		attrs = ref Attr(name, lastword, 0) :: attrs;

	if(attrs == nil)
		return (nil, nil);

	return (ref Tuples(lno, rev(attrs)), nil);

}

Tuples.hasattr(ts: self ref Tuples, attr: string): int
{
	for(pl := ts.pairs; pl != nil; pl = tl pl){
		a := hd pl;
		if(a.attr == attr)
			return 1;
	}
	return 0;
}

Tuples.haspair(ts: self ref Tuples, attr: string, value: string): int
{
	for(pl := ts.pairs; pl != nil; pl = tl pl){
		a := hd pl;
		if(a.attr == attr && a.val == value)
			return 1;
	}
	return 0;
}

Tuples.find(ts: self ref Tuples, attr: string): list of ref Attr
{
	ra: list of ref Attr;
	for(pl := ts.pairs; pl != nil; pl = tl pl){
		a := hd pl;
		if(a.attr == attr)
			ra = a :: ra;
	}
	return rev(ra);
}

Tuples.findbyattr(ts: self ref Tuples, attr: string, value: string, rattr: string): list of ref Attr
{
	if(ts.haspair(attr, value))
		return ts.find(rattr);
	return nil;
}

Dbentry.find(e: self ref Dbentry, attr: string): list of (ref Tuples, list of ref Attr)
{
	rrt: list of (ref Tuples, list of ref Attr);
	for(lines := e.lines; lines != nil; lines = tl lines){
		l := hd lines;
		if((ra := l.find(attr)) != nil)
			rrt = (l, rev(ra)) :: rrt;
	}
	rt: list of (ref Tuples, list of ref Attr);
	for(; rrt != nil; rrt = tl rrt)
		rt = hd rrt :: rt;
	return rt;
}

Dbentry.findfirst(e: self ref Dbentry, attr: string): string
{
	for(lines := e.lines; lines != nil; lines = tl lines){
		l := hd lines;
		for(pl := l.pairs; pl != nil; pl = tl pl)
			if((hd pl).attr == attr)
				return (hd pl).val;
	}
	return nil;
}

Dbentry.findpair(e: self ref Dbentry, attr: string, value: string): list of ref Tuples
{
	rts: list of ref Tuples;
	for(lines := e.lines; lines != nil; lines = tl lines){
		l := hd lines;
		if(l.haspair(attr, value))
			rts = l :: rts;
	}
	for(; rts != nil; rts = tl rts)
		lines = hd rts :: lines;
	return lines;
}

Dbentry.findbyattr(e: self ref Dbentry, attr: string, value: string, rattr: string): list of (ref Tuples, list of ref Attr)
{
	rm: list of (ref Tuples, list of ref Attr);	# lines with attr=value and rattr
	rnm: list of (ref Tuples, list of ref Attr);	# lines with rattr alone
	for(lines := e.lines; lines != nil; lines = tl lines){
		l := hd lines;
		ra: list of ref Attr = nil;
		match := 0;
		for(pl := l.pairs; pl != nil; pl = tl pl){
			a := hd pl;
			if(a.attr == attr && a.val == value)
				match = 1;
			if(a.attr == rattr)
				ra = a :: ra;
		}
		if(ra != nil){
			if(match)
				rm = (l, rev(ra)) :: rm;
			else
				rnm = (l, rev(ra)) :: rnm;
		}
	}
	rt: list of (ref Tuples, list of ref Attr);
	for(; rnm != nil; rnm = tl rnm)
		rt = hd rnm :: rt;
	for(; rm != nil; rm = tl rm)
		rt = hd rm :: rt;
	return rt;
}

Dbf.open(path: string): ref Dbf
{
	df := ref Dbf;
	df.lockc = chan[1] of int;
	df.fd = bufio->open(path, Bufio->OREAD);
	if(df.fd == nil)
		return nil;
	df.name = path;
	(ok, d) := sys->fstat(df.fd.fd);
	if(ok >= 0)
		df.dir = ref d;
	# TO DO: indices
	return df;
}

Dbf.sopen(data: string): ref Dbf
{
	df := ref Dbf;
	df.lockc = chan[1] of int;
	df.fd = bufio->sopen(data);
	if(df.fd == nil)
		return nil;
	df.name = nil;
	df.dir = nil;
	return df;
}

Dbf.reopen(df: self ref Dbf): int
{
	lock(df);
	if(df.name == nil){
		unlock(df);
		return 0;
	}
	fd := bufio->open(df.name, Bufio->OREAD);
	if(fd == nil){
		unlock(df);
		return -1;
	}
	df.fd = fd;
	df.dir = nil;
	(ok, d) := sys->fstat(fd.fd);
	if(ok >= 0)
		df.dir = ref d;
	# TO DO: cache, hash tables
	unlock(df);
	return 0;
}

Dbf.changed(df: self ref Dbf): int
{
	r: int;

	lock(df);
	if(df.name == nil){
		unlock(df);
		return 0;
	}
	(ok, d) := sys->stat(df.name);
	if(ok < 0)
		r = df.fd != nil || df.dir == nil;
	else
		r = df.dir == nil || !samefile(*df.dir, d);
	unlock(df);
	return r;
}

samefile(d1, d2: Sys->Dir): int
{
	# ``it was black ... it was white!  it was dark ...  it was light! ah yes, i remember it well...''
	return d1.dev==d2.dev && d1.dtype==d2.dtype &&
			d1.qid.path==d2.qid.path && d1.qid.vers==d2.qid.vers &&
			d1.mtime == d2.mtime;
}

flatten(ts: list of (ref Tuples, list of ref Attr), attr: string): list of ref Attr
{
	l: list of ref Attr;
	for(; ts != nil; ts = tl ts){
		(line, a) := hd ts;
		t := line.find(attr);
		for(; t != nil; t = tl t)
			l = hd t :: l;
	}
	return rev(l);
}

Db.open(path: string): ref Db
{
	df := Dbf.open(path);
	if(df == nil)
		return nil;
	db := ref Db(df :: nil);
	(e, nil) := db.findpair(nil, "database", "");
	if(e != nil){
		files := flatten(e.find("file"), "file");
		if(files != nil){
			dbs: list of ref Dbf;
			for(; files != nil; files = tl files){
				name := (hd files).val;
				if(name == path && df != nil){
					dbs = df :: dbs;
					df = nil;
				}else if((tf := Dbf.open(name)) != nil)
					dbs = tf :: dbs;
			}
			db.dbs = rev(dbs);
			if(df != nil)
				db.dbs = df :: db.dbs;
		}
	}
	return db;
}

Db.sopen(data: string): ref Db
{
	df := Dbf.sopen(data);
	if(df == nil)
		return nil;
	return ref Db(df :: nil);
}

Db.append(db1: self ref Db, db2: ref Db): ref Db
{
	if(db1 == nil)
		return db2;
	if(db2 == nil)
		return db1;
	dbs := db2.dbs;
	for(rl := rev(db1.dbs); rl != nil; rl = tl rl)
		dbs = hd rl :: dbs;
	return ref Db(dbs);
}

Db.reopen(db: self ref Db): int
{
	f := 0;
	for(dbs := db.dbs; dbs != nil; dbs = tl dbs)
		if((hd dbs).reopen() < 0)
			f = -1;
	return f;
}

Db.changed(db: self ref Db): int
{
	f := 0;
	for(dbs := db.dbs; dbs != nil; dbs = tl dbs)
		f |= (hd dbs).changed();
	return f;
}

isentry(l: string): int
{
	return l!=nil && l[0]!='\t' && l[0]!='\n' && l[0]!=' ' && l[0]!='#';
}

Dbf.readentry(dbf: self ref Dbf, offset: int, attr: string, value: string, useval: int): (ref Dbentry, int, int)
{
	lock(dbf);
	fd := dbf.fd;
	fd.seek(big offset, 0);
	lines: list of ref Tuples;
	match := attr == nil;
	while((l := fd.gets('\n')) != nil){
		while(isentry(l)){
			lines = nil;
			do{
				offset = int fd.offset();
				(t, nil) := parseline(l, 0);
				if(t != nil){
					lines = t :: lines;
					if(!match){
						if(useval)
							match = t.haspair(attr, value);
						else
							match = t.hasattr(attr);
					}
				}
				l = fd.gets('\n');
			}while(l != nil && !isentry(l));
			if(match && lines != nil){
				rl := lines;
				for(lines = nil; rl != nil; rl = tl rl)
					lines = hd rl :: lines;
				unlock(dbf);
				return (ref Dbentry(0, lines), 1, offset);
			}
		}
	}
	unlock(dbf);
	return (nil, 0, int fd.offset());
}

nextentry(db: ref Db, ptr: ref Dbptr, attr: string, value: string, useval: int): (ref Dbentry, ref Dbptr)
{
	if(ptr == nil){
		ptr = ref Dbptr.Direct(db.dbs, nil, 0);
		# TO DO: index
	}
	while(ptr.dbs != nil){
		offset: int;
		dbf := hd ptr.dbs;
		pick p := ptr {
		Direct =>
			offset = p.offset;
		Hash =>
			raise "not done yet";
		}
		(e, match, next) := dbf.readentry(offset, attr, value, useval);
		if(match)
			return (e, ref Dbptr.Direct(ptr.dbs, nil, next));
		if(e == nil)
			ptr = ref Dbptr.Direct(tl ptr.dbs, nil, 0);
		else
			ptr = ref Dbptr.Direct(ptr.dbs, nil, next);
	}
	return (nil, ptr);
}

Db.find(db: self ref Db, ptr: ref Dbptr, attr: string): (ref Dbentry, ref Dbptr)
{
	return nextentry(db, ptr, attr, nil, 0);
}

Db.findpair(db: self ref Db, ptr: ref Dbptr, attr: string, value: string): (ref Dbentry, ref Dbptr)
{
	return nextentry(db, ptr, attr, value, 1);
}

Db.findbyattr(db: self ref Db, ptr: ref Dbptr, attr: string, value: string, rattr: string): (ref Dbentry, ref Dbptr)
{
	for(;;){
		e: ref Dbentry;
		(e, ptr) = nextentry(db, ptr, attr, value, 1);
		if(e == nil || e.find(rattr) != nil)
			return (e, ptr);
	}
}

rev[T](l: list of T): list of T
{
	rl: list of T;
	for(; l != nil; l = tl l)
		rl = hd l :: rl;
	return rl;
}

lock(dbf: ref Dbf)
{
	dbf.lockc <-= 1;
}

unlock(dbf: ref Dbf)
{
	<-dbf.lockc;
}
