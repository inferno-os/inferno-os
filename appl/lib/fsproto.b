implement FSproto;

include "sys.m";
	sys: Sys;
	Dir: import Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "string.m";
	str: String;
include "readdir.m";
	readdir: Readdir;
include "fsproto.m";

File: adt {
	new:	string;
	elem:	string;
	old:	string;
	uid:	string;
	gid:	string;
	mode:	int;
};

Proto: adt {
	b:	ref Iobuf;
	doquote:	int;
	indent:	int;
	lineno:	int;
	newfile:	string;
	oldfile:	string;
	oldroot:	string;
	ec:	chan of Direntry;
	wc:	chan of (string, string);

	walk:	fn(w: self ref Proto, f: ref File, level: int);
	entry:	fn(w: self ref Proto, old: string, new: string, d: ref Sys->Dir);
	warn:	fn(w: self ref Proto, s: string);
	fatal:	fn(w: self ref Proto, s: string);
};

init(): string
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		return sys->sprint("%r");
	str = load String String->PATH;
	if(str == nil)
		return sys->sprint("%r");
	readdir = load Readdir Readdir->PATH;
	if(readdir == nil)
		return sys->sprint("%r");
	return nil;
}

readprotofile(proto: string, root: string, entries: chan of Direntry, warnings: chan of (string, string)): string
{
	b := bufio->open(proto, Sys->OREAD);
	if(b == nil)
		return sys->sprint("%r");
	rdproto(b, root, entries, warnings);
	return nil;
}

readprotostring(proto: string, root: string, entries: chan of Direntry, warnings: chan of (string, string))
{
	rdproto(bufio->sopen(proto), root, entries, warnings);
}

rdproto(b: ref Iobuf, root: string, entries: chan of Direntry, warnings: chan of (string, string)): string
{
	w := ref Proto;
	w.b = b;
	w.doquote = 1;
	w.ec = entries;
	w.wc = warnings;
	w.oldroot = root;
	w.lineno = 0;
	w.indent = 0;
	file := ref File;
	file.mode = 0;
	spawn walker(w, file);
	return nil;
}

walker(w: ref Proto, file: ref File)
{
	w.walk(file, -1);
	w.entry(nil, nil, nil);
}

Proto.entry(w: self ref Proto, old: string, new: string, d: ref Sys->Dir)
{
	if(w.ec != nil)
		w.ec <-= (old, new, d);
}

Proto.warn(w: self ref Proto, s: string)
{
	if(w.wc != nil)
		w.wc <-= (w.oldfile, s);
	else
		sys->fprint(sys->fildes(2), "warning: %s\n", s);
}

Proto.fatal(w: self ref Proto, s: string)
{
	if(w.wc != nil)
		w.wc <-= (w.oldfile, s);
	else
		sys->fprint(sys->fildes(2), "fatal error: %s\n", s);
	w.ec <-= (nil, nil, nil);
	exit;
}

Proto.walk(w: self ref Proto, me: ref File, level: int)
{
	(child, fp) := getfile(w, me);
	if(child == nil)
		return;
	if(child.elem == "+" || child.elem == "*" || child.elem == "%"){
		rec := child.elem[0] == '+';
		filesonly := child.elem[0] == '%';
		child.new = me.new;
		setnames(w, child);
		mktree(w, child, rec, filesonly);
		(child, fp) = getfile(w, me);
	}
	while(child != nil && w.indent > level){
		if(mkfile(w, child))
			w.walk(child, w.indent);
		(child, fp) = getfile(w, me);
	}
	if(child != nil){
		w.b.seek(big fp, 0);
		w.lineno--;
	}
}

mktree(w: ref Proto, me: ref File, rec: int, filesonly: int)
{
	fd := sys->open(w.oldfile, Sys->OREAD);
	if(fd == nil){
		w.warn(sys->sprint("can't open %s: %r", w.oldfile));
		return;
	}
	child := ref *me;
	(d, n) := readdir->init(w.oldfile, Readdir->NAME|Readdir->COMPACT);
	for(i := 0; i < n; i++) {
		if(filesonly && (d[i].mode & Sys->DMDIR))
			continue;
		child.new = mkpath(me.new, d[i].name);
		if(me.old != nil)
			child.old = mkpath(me.old, d[i].name);
		child.elem = d[i].name;
		setnames(w, child);
		if(copyfile(w, child, d[i]) && rec)
			mktree(w, child, rec, filesonly);
	}
}

mkfile(w: ref Proto, f: ref File): int
{
	(i, dir) := sys->stat(w.oldfile);
	if(i < 0){
		w.warn(sys->sprint("can't stat file %s: %r", w.oldfile));
		skipdir(w);
		return 0;
	}
	return copyfile(w, f, ref dir);
}

copyfile(w: ref Proto, f: ref File, d: ref Dir): int
{
	d.name = f.elem;
	if(f.mode != ~0){
		if((d.mode&Sys->DMDIR) != (f.mode&Sys->DMDIR))
			w.warn(sys->sprint("inconsistent mode for %s", f.new));
		else
			d.mode = f.mode;
	}
	w.entry(w.oldfile, w.newfile, d);
	return (d.mode & Sys->DMDIR) != 0;
}

setnames(w: ref Proto, f: ref File)
{
	w.newfile = f.new;
	if(f.old != nil){
		if(f.old[0] == '/')
			w.oldfile = mkpath(w.oldroot, f.old);
		else
			w.oldfile = f.old;
	}else
		w.oldfile = mkpath(w.oldroot, f.new);
}

#
# skip all files in the proto that
# could be in the current dir
#
skipdir(w: ref Proto)
{
	if(w.indent < 0)
		return;
	b := w.b;
	level := w.indent;
	for(;;){
		w.indent = 0;
		fp := b.offset();
		p := b.gets('\n');
		if(p != nil && p[len p - 1] != '\n')
			p += "\n";
		w.lineno++;
		if(p == nil){
			w.indent = -1;
			return;
		}
		for(j := 0; (c := p[j++]) != '\n';)
			if(c == ' ')
				w.indent++;
			else if(c == '\t')
				w.indent += 8;
			else
				break;
		if(w.indent <= level){
			b.seek(fp, 0);
			w.lineno--;
			return;
		}
	}
}

getfile(w: ref Proto, old: ref File): (ref File, int)
{
	p, elem: string;
	c: int;

	if(w.indent < 0)
		return (nil, 0);
	b := w.b;
	fp := int b.offset();
	do {
		w.indent = 0;
		p = b.gets('\n');
		if(p != nil && p[len p - 1] != '\n')
			p += "\n";
		w.lineno++;
		if(p == nil){
			w.indent = -1;
			return (nil, 0);
		}
		for(; (c = p[0]) != '\n'; p = p[1:])
			if(c == ' ')
				w.indent++;
			else if(c == '\t')
				w.indent += 8;
			else
				break;
	} while(c == '\n' || c == '#');
	(elem, p) = getname(w, p);
	if(p == nil)
		return (nil, 0);
	f := ref File;
	f.new = mkpath(old.new, elem);
	(nil, f.elem) = str->splitr(f.new, "/");
	if(f.elem == nil)
		w.fatal(sys->sprint("can't find file name component of %s", f.new));
	(f.mode, p) = getmode(w, p);
	if(p == nil)
		return (nil, 0);
	(f.uid, p) = getname(w, p);
	if(p == nil)
		return (nil, 0);
	if(f.uid == nil)
		f.uid = "-";
	(f.gid, p) = getname(w, p);
	if(p == nil)
		return (nil, 0);
	if(f.gid == nil)
		f.gid = "-";
	f.old = getpath(p);
	if(f.old == "-")
		f.old = nil;
	if(f.old == nil && old.old != nil)
		f.old = mkpath(old.old, elem);
	setnames(w, f);
	return (f, fp);
}

getpath(p: string): string
{
	for(; (c := p[0]) == ' ' || c == '\t'; p = p[1:])
		;
	for(n := 0; (c = p[n]) != '\n' && c != ' ' && c != '\t'; n++)
		;
	return p[0:n];
}

getname(w: ref Proto, p: string): (string, string)
{
	for(; (c := p[0]) == ' ' || c == '\t'; p = p[1:])
		;
	i := 0;
	s := "";
	quoted := 0;
	for(; (c = p[0]) != '\n' && (c != ' ' && c != '\t' || quoted); p = p[1:]){
		if(quoted && c == '\'' && p[1] == '\'')
			p = p[1:];
		else if(c == '\'' && w.doquote){
			quoted = !quoted;
			continue;
		}
		s[i++] = c;
	}
	if(len s > 0 && s[0] == '$'){
		s = getenv(s[1:]);
		if(s == nil)
			w.warn(sys->sprint("can't read environment variable %s", s));
	}
	return (s, p);
}

getenv(s: string): string
{
	if(s == "user")
		return readfile("/dev/user");	# more accurate?
	return readfile("/env/"+s);
}

readfile(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if(fd != nil){
		a := array[256] of byte;
		n := sys->read(fd, a, len a);
		if(n > 0)
			return string a[0:n];
	}
	return nil;
}

getmode(w: ref Proto, p: string): (int, string)
{
	s: string;

	(s, p) = getname(w, p);
	if(s == nil || s == "-")
		return (~0, p);
	m := 0;
	if(s[0] == 'd'){
		m |= Sys->DMDIR;
		s = s[1:];
	}
	if(s[0] == 'a'){
		m |= Sys->DMAPPEND;
		s = s[1:];
	}
	if(s[0] == 'l'){
		m |= Sys->DMEXCL;
		s = s[1:];
	}
	for(i:=0; i<len s || i < 3; i++)
		if(i >= len s || !(s[i]>='0' && s[i]<='7')){
			w.warn(sys->sprint("bad mode specification %s", s));
			return (~0, p);
		}
	(v, nil) := str->toint(s, 8);
	return (m|v, p);
}

mkpath(prefix, elem: string): string
{
	slash1 := slash2 := 0;
	if(len prefix > 0)
		slash1 = prefix[len prefix - 1] == '/';
	if(len elem > 0)
		slash2 = elem[0] == '/';
	if(slash1 && slash2)
		return prefix+elem[1:];
	if(!slash1 && !slash2)
		return prefix+"/"+elem;
	return prefix+elem;
}
