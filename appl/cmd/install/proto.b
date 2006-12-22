implement Proto;

include "sys.m";
	sys: Sys;
	Dir : import Sys;
include "draw.m";
include "bufio.m";
	bufio : Bufio;
	Iobuf : import bufio;
include "string.m";
	str: String;
include "readdir.m";
	readdir : Readdir;
include "proto.m";
include "protocaller.m";

NAMELEN: con	8192;

WARN, ERROR, FATAL : import Protocaller;

File: adt {
	new:	string;
	elem:	string;
	old:	string;
	uid:	string;
	gid:	string;
	mode:	int;
};

indent: int;
lineno := 0;
newfile: string;
oldfile: string;
oldroot : string;
b: ref Iobuf;
cmod : Protocaller;

rdproto(proto : string, root : string, pcmod : Protocaller) : int
{
	if (sys == nil) {
		sys = load Sys Sys->PATH;
		bufio = load Bufio Bufio->PATH;
		str = load String String->PATH;
		readdir = load Readdir Readdir->PATH;
	}
	cmod = pcmod;
	oldroot = root;
	b = bufio->open(proto, Sys->OREAD);
	if(b == nil){
		cmod->protoerr(FATAL, lineno, sys->sprint("can't open %s: %r: skipping\n", proto));
		b.close();
		return -1;
	}
	lineno = 0;
	indent = 0;
	file := ref File;
	file.mode = 0;
	mkfs(file, -1);
	b.close();
	return 0;
}

mkfs(me: ref File, level: int)
{
	(child, fp) := getfile(me);
	if(child == nil)
		return;
	if(child.elem == "+" || child.elem == "*" || child.elem == "%"){
		rec := child.elem[0] == '+';
		filesonly := child.elem[0] == '%';
		child.new = me.new;
		setnames(child);
		mktree(child, rec, filesonly);
		(child, fp) = getfile(me);
	}
	while(child != nil && indent > level){
		if(mkfile(child))
			mkfs(child, indent);
		(child, fp) = getfile(me);
	}
	if(child != nil){
		b.seek(big fp, 0);
		lineno--;
	}
}

mktree(me: ref File, rec: int, filesonly: int)
{
	fd := sys->open(oldfile, Sys->OREAD);
	if(fd == nil){
		cmod->protoerr(WARN, lineno, sys->sprint("can't open %s: %r", oldfile));
		return;
	}
	child := ref *me;
	(d, n) := readdir->init(oldfile, Readdir->NAME|Readdir->COMPACT);
	for (i := 0; i < n; i++) {
		if (filesonly && (d[i].mode & Sys->DMDIR))
			continue;
		child.new = mkpath(me.new, d[i].name);
		if(me.old != nil)
			child.old = mkpath(me.old, d[i].name);
		child.elem = d[i].name;
		setnames(child);
		if(copyfile(child, d[i]) && rec)
			mktree(child, rec, filesonly);
	}
}

mkfile(f: ref File): int
{
	(i, dir) := sys->stat(oldfile);
	if(i < 0){
		cmod->protoerr(WARN, lineno, sys->sprint("can't stat file %s: %r", oldfile));
		skipdir();
		return 0;
	}
	return copyfile(f, ref dir);
}

copyfile(f: ref File, d: ref Dir): int
{
	d.name = f.elem;
	if(f.mode != ~0){
		if((d.mode&Sys->DMDIR) != (f.mode&Sys->DMDIR))
			cmod->protoerr(WARN, lineno, sys->sprint("inconsistent mode for %s", f.new));
		else
			d.mode = f.mode;
	}
	cmod->protofile(newfile, oldfile, d);
	return (d.mode & Sys->DMDIR) != 0;
}

setnames(f: ref File)
{
	newfile = f.new;
	if(f.old != nil){
		if(f.old[0] == '/')
			oldfile = mkpath(oldroot, f.old);
		else
			oldfile = f.old;
	}else
		oldfile = mkpath(oldroot, f.new);
}

#
# skip all files in the proto that
# could be in the current dir
#
skipdir()
{
	if(indent < 0)
		return;
	level := indent;
	for(;;){
		indent = 0;
		fp := b.offset();
		p := b.gets('\n');
		if (p != nil && p[len p - 1] != '\n')
			p += "\n";
		lineno++;
		if(p == nil){
			indent = -1;
			return;
		}
		for(j := 0; (c := p[j++]) != '\n';)
			if(c == ' ')
				indent++;
			else if(c == '\t')
				indent += 8;
			else
				break;
		if(indent <= level){
			b.seek(fp, 0);
			lineno--;
			return;
		}
	}
}

getfile(old: ref File): (ref File, int)
{
	f: ref File;
	p, elem: string;
	c: int;

	if(indent < 0)
		return (nil, 0);
	fp := int b.offset();
	do {
		indent = 0;
		p = b.gets('\n');
		if (p != nil && p[len p - 1] != '\n')
			p += "\n";
		lineno++;
		if(p == nil){
			indent = -1;
			return (nil, 0);
		}
		for(; (c = p[0]) != '\n'; p = p[1:])
			if(c == ' ')
				indent++;
			else if(c == '\t')
				indent += 8;
			else
				break;
	} while(c == '\n' || c == '#');
	f = ref File;
	(elem, p) = getname(p, NAMELEN);
	f.new = mkpath(old.new, elem);
	(nil, f.elem) = str->splitr(f.new, "/");
	if(f.elem == nil)
		cmod->protoerr(ERROR, lineno, sys->sprint("can't find file name component of %s", f.new));
	(f.mode, p) = getmode(p);
	(f.uid, p) = getname(p, NAMELEN);
	if(f.uid == nil)
		f.uid = "-";
	(f.gid, p) = getname(p, NAMELEN);
	if(f.gid == nil)
		f.gid = "-";
	f.old = getpath(p);
	if(f.old == "-")
		f.old = nil;
	if(f.old == nil && old.old != nil)
		f.old = mkpath(old.old, elem);
	setnames(f);
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

getname(p: string, lim: int): (string, string)
{
	for(; (c := p[0]) == ' ' || c == '\t'; p = p[1:])
		;
	i := 0;
	s := "";
	for(; (c = p[0]) != '\n' && c != ' ' && c != '\t'; p = p[1:])
		s[i++] = c;
	if(len s >= lim){
		cmod->protoerr(WARN, lineno, sys->sprint("name %s too long; truncated", s));
		s = s[0:lim-1];
	}
	if(len s > 0 && s[0] == '$'){
		s = getenv(s[1:]);
		if(s == nil)
			cmod->protoerr(ERROR, lineno, sys->sprint("can't read environment variable %s", s));
		if(len s >= NAMELEN)
			s = s[0:NAMELEN-1];
	}
	return (s, p);
}

getenv(s: string): string
{
	if(s == "user")
		return getuser();
	return nil;
}

getuser(): string
{
	fd := sys->open("/dev/user", Sys->OREAD);
	if(fd != nil){
		u := array [100] of byte;
		n := sys->read(fd, u, len u);
		if(n > 0)
			return string u[0:n];
	}
	return nil;
}

getmode(p: string): (int, string)
{
	s: string;

	(s, p) = getname(p, 7);
	if(s == nil || s == "-")
		return (~0, p);
	m := 0;
	if(s[0] == 'd'){
		m |= Sys->DMDIR;
		s = s[1:];
	}
	if(s[0] == 'a'){
		#m |= CHAPPEND;
		s = s[1:];
	}
	if(s[0] == 'l'){
		#m |= CHEXCL;
		s = s[1:];
	}
	for(i:=0; i<len s || i < 3; i++)
		if(i >= len s || !(s[i]>='0' && s[i]<='7')){
		cmod->protoerr(WARN, lineno, sys->sprint("bad mode specification %s", s));
		return (~0, p);
	}
	(v, nil) := str->toint(s, 8);
	return (m|v, p);
}

mkpath(prefix, elem: string): string
{
	slash1 := slash2 := 0;
	if (len prefix > 0)
		slash1 = prefix[len prefix - 1] == '/';
	if (len elem > 0)
		slash2 = elem[0] == '/';
	if (slash1 && slash2)
		return prefix+elem[1:];
	if (!slash1 && !slash2)
		return prefix+"/"+elem;
	return prefix+elem;
}
