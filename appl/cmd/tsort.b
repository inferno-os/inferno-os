implement Tsort;

#
# tsort -- topological sort
#
# convert a partial ordering into a linear ordering
#
# Copyright © 2004 Vita Nuova Holdings Limited
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

Tsort: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Item: adt {
	name:	string;
	mark:	int;
	succ:	cyclic list of ref Item;	# node's successors

	precede:	fn(a: self ref Item, b: ref Item);
};

Q: adt {
	item:	ref Item;
	next:	cyclic ref Q;
};

items, itemt: ref Q;	# use a Q not a list only to keep input order
nitem := 0;
bout: ref Iobuf;

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;

	bout = bufio->fopen(sys->fildes(1), Sys->OWRITE);
	input();
	output();
	bout.flush();
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "tsort: %s\n", s);
	raise "fail:error";
}

input()
{
	b := bufio->fopen(sys->fildes(0), Sys->OREAD);
	while((line := b.gets('\n')) != nil){
		(nf, fld) := sys->tokenize(line, " \t\n");
		if(fld != nil){
			a := finditem(hd fld);
			while((fld = tl fld) != nil)
				a.precede(finditem(hd fld));
		}
	}
}

Item.precede(a: self ref Item, b: ref Item)
{
	if(a != b){
		for(l := a.succ; l != nil; l = tl l)
			if((hd l) == b)
				return;
		a.succ = b :: a.succ;
	}
}

finditem(s: string): ref Item
{
	# would use a hash table for large sets
	for(il := items; il != nil; il = il.next)
		if(il.item.name == s)
			return il.item;
	i := ref Item;
	i.name = s;
	i.mark = 0;
	if(items != nil)
		itemt = itemt.next = ref Q(i, nil);
	else
		itemt = items = ref Q(i, nil);
	nitem++;
	return i;
}

dep: list of ref Item;

output()
{
	for(k := items; k != nil; k = k.next)
		if((q := k.item).mark == 0)
			visit(q, nil);
	for(; dep != nil; dep = tl dep)
		bout.puts((hd dep).name+"\n");
}

# visit q's successors depth first
# parents is only used to print any cycles, and since it matches
# the stack, the recursion could be eliminated
visit(q: ref Item, parents: list of ref Item)
{
	q.mark = 2;
	parents = q :: parents;
	for(sl := q.succ; sl != nil; sl = tl sl)
		if((s := hd sl).mark == 0)
			visit(s, parents);
		else if(s.mark == 2){
			sys->fprint(sys->fildes(2), "tsort: cycle in input\n");
			rl: list of ref Item;
			for(l := parents;; l = tl l){	# reverse to be closer to input order
				rl = hd l :: rl;
				if(hd l == s)
					break;
			}
			for(l = rl; l != nil; l = tl l)
				sys->fprint(sys->fildes(2), "tsort: %s\n", (hd l).name);
		}
	q.mark = 1;
	dep = q :: dep;
}
