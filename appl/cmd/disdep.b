implement Disdep;

#
# Copyright  © 2000 Vita Nuova Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;
	print, sprint: import sys;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "draw.m";

include "string.m";
	str: String;

include "arg.m";
	arg: Arg;

include "dis.m";
	dis: Dis;
	Mod: import dis;

include "hash.m";
	hash: Hash;
	HashTable, HashVal: import hash;

Disdep: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Item: adt {
	name:	string;
	needs:	cyclic list of ref Item;
	visited:	int;

	find:		fn(s: string): ref Item;
};

bout: ref Iobuf;
pending: list of ref Item;
roots: list of ref Item;
tab: ref HashTable;
aflag := 0;		# display all non-recursive dependencies
oflag := 0;		# only list the immediate (outer) dependencies
sflag := 0;		# include $system modules
pflag := 0;		# show dependency sets as pairs, one per line
showdepth := 0;	# indent to show the dependency structure

noload(mod: string)
{
	sys->fprint(sys->fildes(2), "disdep: can't load %s: %r\n", mod);
	raise "fail:load";
}

usage()
{
	sys->fprint(sys->fildes(2), "Usage: disdep [-a] [-d] [-o] [-p] [-s] file.dis ...\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		noload(Bufio->PATH);

	str = load String String->PATH;
	if(str == nil)
		noload(String->PATH);

	hash = load Hash Hash->PATH;
	if(hash == nil)
		noload(Hash->PATH);

	arg = load Arg Arg->PATH;
	if(arg == nil)
		noload(Arg->PATH);

	dis = load Dis Dis->PATH;
	if(dis == nil)
		noload(Dis->PATH);
	dis->init();

	arg->init(argv);
	while((opt := arg->opt()) != 0)
		case opt {
		'a' => aflag = 1; showdepth = 1;
		'o' => oflag = 1;
		's' => sflag = 1;
		'd' => showdepth = 1;
		'p' => pflag = 1;
		* => usage();
		}

	argv = arg->argv();
	if(argv == nil)
		usage();

	tab = hash->new(521);

	bout = bufio->fopen(sys->fildes(1), Sys->OWRITE);
	for(l := rev(argv); l != nil; l = tl l)
		roots = Item.find(hd l) :: roots;
	pending = roots;
	while(pending != nil){
		f := hd pending;
		pending = tl pending;
		(m, s) := dis->loadobj(f.name);
		if(s != nil){
			sys->fprint(sys->fildes(2), "disdep: can't open %s: %s\n", f.name, s);
			continue;
		}
		f.needs = disfind(m);
		for(nl := f.needs; nl != nil; nl = tl nl){
			n := hd nl;
			if(!n.visited){
				n.visited = 1;
				if(!oflag && !isdol(n.name))
					pending = n :: pending;
			}
		}
	}

	if(pflag){
		for(i := 0; i < nextitem; i++){
			f := items[i];
			if(f.needs != nil){
				for(nl := f.needs; nl != nil; nl = tl nl){
					bout.puts(f.name);
					bout.putc(' ');
					bout.puts((hd nl).name);
					bout.putc('\n');
				}
			}else{
				bout.puts(f.name);
				bout.putc('\n');
			}
		}
	}else{
		unvisited();
		for(; roots != nil; roots = tl roots){
			if(aflag)
				unvisited();
			f := hd roots;
			depth := 0;
			if(showdepth){
				bout.puts(f.name);
				bout.putc('\n');
				depth = 1;
			}
			prdep(hd roots, depth);
		}
	}
	bout.flush();
}

disfind(m: ref Mod): list of ref Item
{
	needs: list of ref Item;
	for(d := m.data; d != nil; d = tl d) {
		pick dat := hd d {
		String =>
			if(isdisfile(dat.str) || sflag && isdol(dat.str))
				needs = Item.find(dat.str) :: needs;
		}
	}
	return rev(needs);
}

prdep(f: ref Item, depth: int)
{
	f.visited = 1;	# short-circuit self-reference
	for(nl := f.needs; nl != nil; nl = tl nl){
		n := hd nl;
		if(!n.visited){
			n.visited = 1;
			name(n.name, depth);
			prdep(n, depth+1);
		}else if(aflag)
			name(n.name, depth);
	}
}
			
items := array[100] of ref Item;
nextitem := 0;

Item.find(name: string): ref Item
{
	k := tab.find(name);
	if(k != nil)
		return items[k.i];
	if(nextitem >= len items){
		a := array[len items + 100] of ref Item;
		a[0:] = items;
		items = a;
	}
	f := ref Item;
	f.name = name;
	f.visited = 0;
	items[nextitem] = f;
	tab.insert(name, HashVal(nextitem, 0.0, nil));
	nextitem++;
	return f;
}

unvisited()
{
	for(i := 0; i < nextitem; i++)
		items[i].visited = 0;
}

name(s: string, depth: int)
{
	if(showdepth)
		for(i:=0; i<depth; i++)
			bout.putc('\t');
	bout.puts(s);
	bout.putc('\n');
}

isdisfile(s: string): int
{
	if(len s > 4 && s[len s-4:]==".dis"){	# worth a look
		for(i := 0; i < len s; i++)
			if(s[i] <= ' ' || s[i] == '%')
				return 0;
		return 1;
	}
	return 0;
}

isdol(s: string): int
{
	return len s > 1 && s[0] == '$' && s[1]>='A' && s[1]<='Z';	# reasonable guess
}

rev[T](l: list of T): list of T
{
	t: list of T;
	for(; l != nil; l = tl l)
		t = hd l :: t;
	return t;
}

