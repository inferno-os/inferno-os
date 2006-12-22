implement Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "fslib.m";
	fslib: Fslib;
	Report, Value, type2s, quit: import fslib;
	Fschan, Fsdata, Entrychan, Entry,
	Gatechan, Gatequery, Nilentry, Option,
	Next, Down, Skip, Quit: import Fslib;

# set the root 
types(): string
{
	return "xsx-c";
}

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: size: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	fslib = load Fslib Fslib->PATH;
	if(fslib == nil)
		badmod(Fslib->PATH);
}

run(nil: ref Draw->Context, nil: ref Report,
			opts: list of Option, args: list of ref Value): ref Value
{
	root := (hd args).s().i;
	if(root == nil && opts == nil){
		sys->fprint(sys->fildes(2), "fs: setroot: empty path\n");
		return nil;
	}
	v := ref Value.X(chan of (Fsdata, chan of int));
	spawn setroot((hd tl args).x().i, v.i, root, opts != nil);
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
			fslib->copy(src, dst);
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
		if(fslib->copy(src, dst) == Quit)
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
