implement Ckproto;

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "arg.m";
	arg: Arg;
include "readdir.m";
	readdir : Readdir;
include "proto.m";
	proto : Proto;
include "protocaller.m";
	protocaller : Protocaller;

WARN, ERROR, FATAL : import Protocaller;

Ckproto: module{
	init:	fn(nil: ref Draw->Context, nil: list of string);
	protofile: fn(new : string, old : string, d : ref Sys->Dir);
	protoerr: fn(lev : int, line : int, err : string);
};

Dir : adt {
	name : string;
	proto : string;
	parent : cyclic ref Dir;
	child : cyclic ref Dir;
	sibling : cyclic ref Dir;
};

root := "/";
droot : ref Dir;
protof : string;
stderr : ref Sys->FD;
omitgen := 0;			# forget generated files
verbose : int;
ckmode: int;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	arg = load Arg Arg->PATH;
	readdir = load Readdir Readdir->PATH;
	proto = load Proto Proto->PATH;
	protocaller = load Protocaller "$self";

	stderr = sys->fildes(2);
	sys->pctl(Sys->NEWPGRP|Sys->FORKNS|Sys->FORKFD, nil);
	arg->init(args);
	while ((c := arg->opt()) != 0) {
		case c {
			'r' =>
				root = arg->arg();
				if (root == nil)
					fatal("missing argument to -r");
			'o' =>
				omitgen = 1;
			'v' =>
				verbose = 1;
			'm' =>
				ckmode = 1;
			* =>
				fatal("usage: install/ckproto [-o] [-v] [-m] [-r root] protofile ....");
		}
	}
	droot = ref Dir("/", nil, nil, nil, nil);
	droot.parent = droot;
	args = arg->argv();
	while (args != nil) {
		protof = hd args;
		proto->rdproto(hd args, root, protocaller);
		args = tl args;
	}
	if (verbose)
		prtree(droot, -1);
	ckdir(root, droot);
}

protofile(new : string, old : string, nil : ref Sys->Dir)
{
	if (verbose) {
		if (old == new)
			sys->print("%s\n", new);
		else
	 		sys->print("%s %s\n", new, old);
	}
	addfile(droot, old);
	if (new != old)
		addfile(droot, new);
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

ckdir(d : string, dird : ref Dir)
{
	(dir, n) := readdir->init(d, Readdir->NAME|Readdir->COMPACT);
	for (i := 0; i < n; i++) {
		dire := lookup(dird, dir[i].name);
		if(omitgen && generated(dir[i].name))
			continue;
		if (dire == nil){
			sys->print("%s missing\n", mkpath(d, dir[i].name));
			continue;
		}
		if(ckmode){
			if(dir[i].mode & Sys->DMDIR){
				if((dir[i].mode & 8r775) != 8r775)
					sys->print("directory %s not 775 at least\n", mkpath(d, dir[i].name));
			}
			else{
				if((dir[i].mode & 8r664) != 8r664)
					sys->print("file %s not 664 at least\n", mkpath(d, dir[i].name));
			}
		}
		if (dir[i].mode & Sys->DMDIR)
			ckdir(mkpath(d, dir[i].name), dire);
	}
}

addfile(root : ref Dir, path : string)
{
	elem : string;

	# ckexists(path);
	
	curd := root;
	opath := path;
	while (path != nil) {
		(elem, path) = split(path);
		d := lookup(curd, elem);
		if (d == nil) {
			d = ref Dir(elem, protof, curd, nil, nil);
			if (curd.child == nil)
				curd.child = d;
			else {
				prev, this : ref Dir;

				for (this = curd.child; this != nil; this = this.sibling) {
					if (elem < this.name) {
						d.sibling = this;
						if (prev == nil)
							curd.child = d;
						else
							prev.sibling = d;
						break;
					}
					prev = this;
				}
				if (this == nil)
					prev.sibling = d;
			}
		}
		else if (path == nil && d.proto == protof)
			sys->print("%s repeated in proto %s\n", opath, protof);
		curd = d;
	}
}

lookup(p : ref Dir, f : string) : ref Dir
{
	if (f == ".")
		return p;
	if (f == "..")
		return p.parent;
	for (d := p.child; d != nil; d = d.sibling) {
		if (d.name == f)
			return d;
		if (d.name > f)
			return nil;
	}
	return nil;
}

prtree(root : ref Dir, indent : int)
{
	if (indent >= 0)
		sys->print("%s%s\n", string array[indent] of { * => byte '\t' }, root.name);
	for (s := root.child; s != nil; s = s.sibling)
		prtree(s, indent+1);
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

split(p : string) : (string, string)
{
	if (p == nil)
		fatal("nil string in split");
	if (p[0] != '/')
		fatal("p0 notg / in split");
	while (p[0] == '/')
		p = p[1:];
	i := 0;
	while (i < len p && p[i] != '/')
		i++;
	if (i == len p)
		return (p, nil);
	else
		return (p[0:i], p[i:]);
}


gens := array[] of {
	"dis", "sbl", "out", "0", "1", "2", "5", "8", "k", "q", "v", "t"
};

generated(f : string) : int
{
	for (i := len f -1; i >= 0; i--)
		if (f[i] == '.')
			break;
	if (i < 0)
		return 0;
	suff := f[i+1:];
	for (i = 0; i < len gens; i++)
		if (suff == gens[i])
			return 1;
	return 0;
}

warn(s: string)
{
	sys->print("%s: %s\n", protof, s);
}

error(s: string)
{
	sys->fprint(stderr, "%s: %s\n", protof, s);
	exit;;
}

fatal(s: string)
{
	sys->fprint(stderr, "fatal: %s\n", s);
	exit;
}

ckexists(path: string)
{
	s := mkpath(root, path);
	(ok, nil) := sys->stat(s);
	if(ok < 0)
		sys->print("%s does not exist\n", s);
}
