#	
# Copyright © 2001 Vita Nuova (Holdings) Limited.  All rights reserved.	
#

implement Proto2list;

# make a version list suitable for SDS from a series of proto files

include "sys.m";
	sys : Sys;
include "draw.m";
include "bufio.m";
	bufio : Bufio;
	Iobuf : import bufio;
include "crc.m";
	crcm : Crc;
include "proto.m";
	proto : Proto;
include "protocaller.m";
	protocaller : Protocaller;

WARN, ERROR, FATAL : import Protocaller;

Proto2list: module
{
	init : fn(ctxt: ref Draw->Context, argv: list of string);
	protofile: fn(new : string, old : string, d : ref Sys->Dir);
	protoerr: fn(lev : int, line : int, err : string);
};

stderr: ref Sys->FD;
protof: string;

Element: type (string, string);

List: adt{
	as: array of Element;
	n: int;
	init: fn(l: self ref List);
	add: fn(l: self ref List, e: Element);
	end: fn(l: self ref List): array of Element;
};

flist: ref List;

List.init(l: self ref List)
{
	l.as = array[1024] of Element;
	l.n = 0;
}

List.add(l: self ref List, e: Element)
{
	if(l.n == len l.as)
		l.as = (array[2*l.n] of Element)[0:] = l.as;
	l.as[l.n++] = e;
}

List.end(l: self ref List): array of Element
{
	return l.as[0: l.n];
}

usage()
{
	sys->fprint(stderr, "Usage: proto2list protofile ...\n");
	exit;
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	crcm = load Crc Crc->PATH;
	proto = load Proto Proto->PATH;
	protocaller = load Protocaller "$self";
	stderr = sys->fildes(2);
	root := "/";
	flist = ref List;
	flist.init();
	for(argv = tl argv; argv != nil; argv = tl argv){
		protof = hd argv;
		proto->rdproto(hd argv, root, protocaller);
	}
	fs := flist.end();
	sort(fs);
	fs = uniq(fs);
	out(fs);
}

protofile(new : string, old : string, nil : ref Sys->Dir)
{
	if(new == old)
		new = "-";
	flist.add((old, new));
}

out(fs: array of Element)
{
	nf := len fs;
	for(i := 0; i < nf; i++){
		(f, g) := fs[i];
		(ok, d) := sys->stat(f);
		if (ok < 0) {
			sys->fprint(stderr, "cannot open %s\n", f);
			continue;
		}
		if (d.mode & Sys->DMDIR)
			d.length = big 0;
		sys->print("%s	%s	%d	%d	%d	%d	%d\n", f, g, int d.length, d.mode, d.mtime, crc(f, d), 0);
	}
}

protoerr(lev : int, line : int, err : string)
{
	s := "line " + string line + " : " + err;
	case lev {
		WARN => warn(s);
		ERROR => error(s);
		FATAL => fatal(s);
	}
}

crc(f : string, d: Sys->Dir) : int
{
	crcs := crcm->init(0, int 16rffffffff);
	if (d.mode & Sys->DMDIR)
		return 0;
	fd := sys->open(f, Sys->OREAD);
	if (fd == nil) {
		sys->fprint(stderr, "cannot open %s\n", f);
		return 0;
	}
	crc := 0;
	buf := array[Sys->ATOMICIO] of byte;
	for (;;) {
		nr := sys->read(fd, buf, len buf);
		if (nr < 0) {
			sys->fprint(stderr, "bad read on %s : %r\n", f);
			return 0;
		}
		if (nr <= 0)
			break;
		crc = crcm->crc(crcs, buf, nr);
	}
	crcm->reset(crcs);
	return crc;
}

sort(a: array of Element)
{
	mergesort(a, array[len a] of Element);
}
	
mergesort(a, b: array of Element)
{
	r := len a;
	if (r > 1) {
		m := (r-1)/2 + 1;
		mergesort(a[0:m], b[0:m]);
		mergesort(a[m:], b[m:]);
		b[0:] = a;
		for ((i, j, k) := (0, m, 0); i < m && j < r; k++) {
			if (b[i].t0 > b[j].t0)
				a[k] = b[j++];
			else
				a[k] = b[i++];
		}
		if (i < m)
			a[k:] = b[i:m];
		else if (j < r)
			a[k:] = b[j:r];
	}
}


uniq(a: array of Element): array of Element
{
	m := n := len a;
	for(i := 0; i < n-1; ){
		if(a[i].t0 == a[i+1].t0){
			if(a[i].t1 != a[i+1].t1)
				warn(sys->sprint("duplicate %s(%s %s)", a[i].t0, a[i].t1, a[i+1].t1));
			a[i+1:] = a[i+2: n--];
		}
		else
			i++;
	}
	if(n == m)
		return a;
	return a[0: n];
}
		
error(s: string)
{
	sys->fprint(stderr, "%s: %s\n", protof, s);
	exit;
}

fatal(s: string)
{
	sys->fprint(stderr, "fatal: %s\n", s);
	exit;
}
 
warn(s: string)
{
	sys->fprint(stderr, "%s: %s\n", protof, s);
}
