#	
# Copyright © 2001 Vita Nuova (Holdings) Limited.  All rights reserved.	
#

implement Wrap2list;

# make a version list suitable for SDS from /wrap

include "sys.m";
	sys : Sys;
include "draw.m";
include "bufio.m";
	bufio : Bufio;
	Iobuf : import bufio;
include "crc.m";
	crcm : Crc;
include "wrap.m";
	wrap: Wrap;

Wrap2list: module
{
	init : fn(ctxt: ref Draw->Context, argv: list of string);
};

stderr: ref Sys->FD;

HASHSZ: con 64;

Element: type string;

Hash: adt{
	elems: array of Element;
	nelems: int;
};

List: adt{
	tabs: array of ref Hash;
	init: fn(l: self ref List);
	add: fn(l: self ref List, e: Element);
	subtract: fn(l: self ref List, e: Element);
	end: fn(l: self ref List): array of Element;
};

flist: ref List;

hash(s: string): int
{
	h := 0;
	n := len s;
	for(i := 0; i < n; i++)
		h += s[i];
	if(h < 0)
		h = -h;
	return h%HASHSZ;
}

List.init(l: self ref List)
{
	ts := l.tabs = array[HASHSZ] of ref Hash;
	for(i := 0; i < HASHSZ; i++){
		t := ts[i] = ref Hash;
		t.elems = array[HASHSZ] of Element;
		t.nelems = 0;
	}
}

List.add(l: self ref List, e: Element)
{
	h := hash(e);
	t := l.tabs[h];
	n := t.nelems;
	es := t.elems;
	for(i := 0; i < n; i++){
		if(e == es[i])
			return;
	}
	if(n == len es)
		es = t.elems = (array[2*n] of Element)[0:] = es;
	es[t.nelems++] = e;
# sys->print("+ %s\n", e);
}

List.subtract(l: self ref List, e: Element)
{
	h := hash(e);
	t := l.tabs[h];
	n := t.nelems;
	es := t.elems;
	for(i := 0; i < n; i++){
		if(e == es[i]){
			es[i] = nil;
			break;
		}
	}
# sys->print("- %s\n", e);
}

List.end(l: self ref List): array of Element
{
	tot := 0;
	ts := l.tabs;
	for(i := 0; i < HASHSZ; i++)
		tot += ts[i].nelems;
	a := array[tot] of Element;
	m := 0;
	for(i = 0; i < HASHSZ; i++){
		t := ts[i];
		n := t.nelems;
		es := t.elems;
		a[m:] = es[0: n];
		m += n;
	}
	return a;
}

usage()
{
	sys->fprint(stderr, "Usage: wrap2list [ file ... ]\n");
	exit;
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	crcm = load Crc Crc->PATH;
	wrap = load Wrap Wrap->PATH;
	wrap->init(bufio);
	if(argv != nil)
		argv = tl argv;
	init := 0;
	if(argv != nil && hd argv == "-i"){
		init = 1;
		argv = tl argv;
	}
	stderr = sys->fildes(2);
	# root := "/";
	flist = ref List;
	flist.init();
	fd := sys->open("/wrap", Sys->OREAD);
	for(;;){
		(nd, d) := sys->dirread(fd);
		if(nd <= 0)
			break;
		for(i:=0; i<nd; i++){
			if((d[0].mode & Sys->DMDIR) && (w := wrap->openwrap(d[i].name, "/", 1)) != nil){
				# sys->fprint(stderr, "%s %s %d %d\n", w.name, w.root, w.tfull, w.nu);
				for(j := 0; j < w.nu; j++){
					addfiles(w.u[j].bmd5);
					if((b := bufio->open(w.u[j].dir+"/remove", Bufio->OREAD)) != nil)
						subtractfiles(b);
					# sys->fprint(stderr, "%d: %s %s %d %d %d\n", i, w.u[j].desc, w.u[j].dir, w.u[j].time, w.u[j].utime, w.u[j].typ);
				}
			}
		}
	}
	for( ; argv != nil; argv = tl argv){
		if((b := bufio->open(hd argv, Bufio->OREAD)) != nil)
			addfiles(b);
	}
	out(uniq(rmnil(sort(flist.end()))), init);
}

addfiles(b: ref Bufio->Iobuf)
{
	b.seek(big 0, Bufio->SEEKSTART);
	while((s := b.gets('\n')) != nil){
		(n, l) := sys->tokenize(s, " \n");
		if(n > 0)
			flist.add(hd l);
	}
}

subtractfiles(b: ref Bufio->Iobuf)
{
	b.seek(big 0, Bufio->SEEKSTART);
	while((s := b.gets('\n')) != nil){
		(n, l) := sys->tokenize(s, " \n");
		if(n > 0)
			flist.subtract(hd l);
	}
}

out(fs: array of Element, init: int)
{
	nf := len fs;
	for(i := 0; i < nf; i++){
		f := fs[i];
		outl(f, nil, init);
		l := len f;
		if(l >= 7 && f[l-7:] == "emu.new"){
			g := f;
			f[l-3] = 'e';
			f[l-2] = 'x';
			f[l-1] = 'e';
			outl(f, g, init);		# try emu.exe
			outl(f[0: l-4], g, init);	# try emu
# sys->fprint(sys->fildes(2), "%s %s\n", f, g);
		}
	}
}

outl(f: string, g: string, init: int)
{
	(ok, d) := sys->stat(f);
	if(ok < 0){
		# sys->fprint(stderr, "cannot open %s\n", f);
		return;
	}
	if(g == nil)
		g = "-";
	if(d.mode & Sys->DMDIR)
		d.length = big 0;
	if(init)
		mtime := 0;
	else
		mtime = d.mtime;
	sys->print("%s	%s	%d	%d	%d	%d	%d\n", f, g, int d.length, d.mode, mtime, crc(f, d), 0);
}

crc(f: string, d: Sys->Dir): int
{
	crcs := crcm->init(0, int 16rffffffff);
	if(d.mode & Sys->DMDIR)
		return 0;
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil){
		sys->fprint(stderr, "cannot open %s\n", f);
		return 0;
	}
	crc := 0;
	buf := array[Sys->ATOMICIO] of byte;
	for(;;){
		nr := sys->read(fd, buf, len buf);
		if(nr < 0){
			sys->fprint(stderr, "bad read on %s : %r\n", f);
			return 0;
		}
		if(nr <= 0)
			break;
		crc = crcm->crc(crcs, buf, nr);
	}
	crcm->reset(crcs);
	return crc;
}

sort(a: array of Element): array of Element
{
	qsort(a, len a);
	return a;
}

rmnil(a: array of Element): array of Element
{
	n := len a;
	for(i := 0; i < n; i++)
		if(a[i] != nil)
			break;
	return a[i: n];
}

uniq(a: array of Element): array of Element
{
	n := len a;
	for(i := 0; i < n-1; ){
		if(a[i] == a[i+1])
			a[i+1:] = a[i+2: n--];
		else
			i++;
	}
	return a[0: n];
}

qsort(a: array of Element, n: int)
{
	i, j: int;
	t: Element;

	while(n > 1){
		i = n>>1;
		t = a[0]; a[0] = a[i]; a[i] = t;
		i = 0;
		j = n;
		for(;;){
			do
				i++;
			while(i < n && a[i] < a[0]);
			do
				j--;
			while(j > 0 && a[j] > a[0]);
			if(j < i)
				break;
			t = a[i]; a[i] = a[j]; a[j] = t;
		}
		t = a[0]; a[0] = a[j]; a[j] = t;
		n = n-j-1;
		if(j >= n){
			qsort(a, j);
			a = a[j+1:];
		}else{
			qsort(a[j+1:], n);
			n = j;
		}
	}
}
