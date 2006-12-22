implement Setroot, Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
	Report: import Reports;
include "alphabet/fs.m";
	fs: Fs;
	Value: import fs;
	Fschan, Fsdata, Entrychan, Entry,
	Gatechan, Gatequery, Nilentry, Option,
	Next, Down, Skip, Quit: import Fs;

Setroot: module {};

# set the root 
types(): string
{
	return "xxs-c";
}

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: size: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	fs = load Fs Fs->PATH;
	if(fs == nil)
		badmod(Fs->PATH);
	fs->init();
}

run(nil: ref Draw->Context, nil: ref Report,
			opts: list of Option, args: list of ref Value): ref Value
{
	root := (hd tl args).s().i;
	if(root == nil && opts == nil){
		sys->fprint(sys->fildes(2), "fs: setroot: empty path\n");
		return nil;
	}
	v := ref Value.Vx(chan of (Fsdata, chan of int));
	spawn setroot((hd args).x().i, v.i, root, opts != nil);
	return v;
}

setroot(src, dst: Fschan, root: string, cflag: int)
{
	((d, nil), reply) := <-src;
	if(cflag){
		createroot(src, dst, root, d, reply);
	}else{
		myreply := chan of int;
		rd := ref *d;
		rd.name = root;
		dst <-= ((rd, nil), myreply);
		if(<-myreply == Down){
			reply <-= Down;
			fs->copy(src, dst);
		}
	}
}

createroot(src, dst: Fschan, root: string, d: ref Sys->Dir, reply: chan of int)
{
	if(root == nil)
		root = d.name;
	(n, elems) := sys->tokenize(root, "/");		# XXX should really do a cleanname first
	if(root[0] == '/'){
		elems = "/" :: elems;
		n++;
	}
	myreply := chan of int;
	lev := 0;
	r := -1;
	for(; elems != nil; elems = tl elems){
		rd := ref *d;
		rd.name = hd elems;
		dst <-= ((rd, nil), myreply);
		case r = <-myreply {
		Quit =>
			(<-src).t1 <-= Quit;
			exit;
		Skip =>
			break;
		Next =>
			lev++;
			break;
		}
		lev++;
	}
	if(r == Down){
		reply <-= Down;
		if(fs->copy(src, dst) == Quit)
			exit;
	}else
		reply <-= Quit;
	while(lev-- > 1){
		dst <-= ((nil, nil), myreply);
		if(<-myreply == Quit){
			(<-src).t1 <-= Quit;
			exit;
		}
	}
}
