implement Du;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "string.m";
	strmod: String;
include "readdir.m";
	readdir: Readdir;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "arg.m";

aflag := 0;	# all files, not just directories
nflag := 0;	# names only (but see -t); implies -a
sflag := 0;	# summary of top level names
tflag := 0;	# use modification time, not size; netlib format if -n also given
uflag := 0;	# use last use (access) time, not size
blocksize := big 1024;	# quantise length to this block size (still displayed in kb)
bout: ref Iobuf;

Du: module
{
	init:	fn(nil: ref Draw->Context, arg: list of string);
};

kb(b: big): big
{
	return (((b + blocksize - big 1)/blocksize)*blocksize)/big 1024;
}

report(name: string, mtime: int, atime: int, l: big, chksum: int)
{
	t := mtime;
	if(uflag)
		t = atime;
	if(nflag){
		if(tflag)
			bout.puts(sprint("%q %ud %bd %d\n", name, t, l, chksum));
		else
			bout.puts(sprint("%q\n", name));
	}else{
		if(tflag)
			bout.puts(sprint("%ud %q\n", t, name));
		else
			bout.puts(sprint("%-4bd %q\n", kb(l), name));
	}
}

# Avoid loops in tangled namespaces.
NCACHE: con 1024; # must be power of two
cache := array[NCACHE] of list of ref sys->Dir;

seen(dir: ref sys->Dir): int
{
	h := int dir.qid.path & (NCACHE-1);
	for(c := cache[h]; c!=nil; c = tl c){
		t := hd c;
		if(dir.qid.path==t.qid.path && dir.dtype==t.dtype && dir.dev==t.dev)
			return 1;
	}
	cache[h] = dir :: cache[h];
	return 0;
}

dir(dirname: string): big
{
	prefix := dirname+"/";
	if(dirname==".")
		prefix = nil;
	sum := big 0;
	(de, nde) := readdir->init(dirname, readdir->NAME);
	if(nde < 0)
		warn("can't read", dirname);
	for(i := 0; i < nde; i++) {
		s := prefix+de[i].name;
		if(de[i].mode & Sys->DMDIR){
			if(!seen(de[i])){	# arguably should apply to files as well
				size := dir(s);
				sum += size;
				if(!sflag && !nflag)
					report(s, de[i].mtime, de[i].atime, size, 0);
			}
		}else{
			l := de[i].length;
			sum += l;
			if(aflag)
				report(s, de[i].mtime, de[i].atime, l, 0);
		}
	}
	return sum;
}

du(name: string)
{
	(rc, d) := sys->stat(name);
	if(rc < 0){
		warn("can't stat", name);
		return;
	}
	if(d.mode & Sys->DMDIR){
		d.length = dir(name);
		if(nflag && !sflag)
			return;
	}
	report(name, d.mtime, d.atime, d.length, 0);
}

warn(why: string, f: string)
{
	sys->fprint(sys->fildes(2), "du: %s %q: %r\n", why, f);
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	strmod = load String String->PATH;
	readdir = load Readdir Readdir->PATH;
	arg := load Arg Arg->PATH;
	if(arg == nil || bufio==nil || arg==nil || readdir==nil || readdir==nil){
		sys->fprint(sys->fildes(2), "du: load Error: %r\n");
		raise "fail:can't load";
	}
	sys->pctl(Sys->FORKFD, nil);
	bout = bufio->fopen(sys->fildes(1), bufio->OWRITE);
	arg->init(args);
	arg->setusage("du [-anstu] [-b bsize] [file ...]");
	while((o := arg->opt()) != 0)
		case o {
		'a' =>
			aflag = 1;
		'b' =>
			s := arg->earg();
			blocksize = big s;
			if(len s > 0 && s[len s-1] == 'k')
				blocksize *= big 1024;
			if(blocksize <= big 0)
				blocksize = big 1;
		'n' =>
			nflag = 1;
			aflag = 1;
		's' =>
			sflag = 1;
		't' =>
			tflag = 1;
		'u' =>
			uflag = 1;
			tflag = 1;
		* =>
			arg->usage();
		}
	args = arg->argv();
	arg = nil;

	if(args==nil)
		args = "." :: nil;
	for(; args!=nil; args = tl args)
		du(hd args);
	bout.close();
}
