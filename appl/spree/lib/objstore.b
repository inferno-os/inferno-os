implement Objstore;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sets.m";
	None: import Sets;
include "../spree.m";
	spree: Spree;
	Object, Clique: import spree;
include "objstore.m";

clique: ref Clique;
archiveobjs: array of list of (string, ref Object);

init(mod: Spree, g: ref Clique)
{
	sys = load Sys Sys->PATH;
	spree = mod;
	clique = g;
}

unarchive()
{
	archiveobjs = array[27] of list of (string, ref Object);
	for (i := 0; i < len clique.objects; i++) {
		obj := clique.objects[i];
		if (obj != nil && (nm := obj.getattr("§")) != nil) {
			(n, toks) := sys->tokenize(nm, " ");
			for (; toks != nil; toks = tl toks) {
				x := strhash(hd toks, len archiveobjs);
				archiveobjs[x] = (hd toks, obj) :: archiveobjs[x];
			}
			obj.setattr("§", nil, None);
		}
	}
}

setname(obj: ref Object, name: string)
{
	nm := obj.getattr("§");
	if (nm != nil)
		nm += " " + name;
	else
		nm = name;
	obj.setattr("§", nm, None);
}

get(name: string): ref Object
{
	for (al := archiveobjs[strhash(name, len archiveobjs)]; al != nil; al = tl al)
		if ((hd al).t0 == name)
			return (hd al).t1;
	return nil;
}

# from Aho Hopcroft Ullman
strhash(s: string, n: int): int
{
	h := 0;
	m := len s;
	for(i := 0; i<m; i++){
		h = 65599 * h + s[i];
	}
	return (h & 16r7fffffff) % n;
}
