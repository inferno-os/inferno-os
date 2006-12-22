implement Fsfilter;
include "sys.m";
include "draw.m";
include "sh.m";
include "fslib.m";
	Fschan, Next, Quit, Skip, Down: import Fslib;

filter[T](t: T, src, dst: Fschan)
	for{
	T =>
		query: fn(t: self T, d: ref Sys->Dir, name: string, depth: int): int;
	}
{
	names: list of string;
	name: string;
	indent := 0;
	myreply := chan of int;
loop:
	for(;;){
		(d, reply) := <-src;
		if(d.dir != nil){
			p := name;
			if(indent > 0){
				if(p != nil && p[len p - 1] != '/')
					p[len p] = '/';
			}
			if(t.query(d.dir, p + d.dir.name, indent) == 0 && indent > 0){
				reply <-= Next;
				continue;
			}
		}
		dst <-= (d, myreply);
		case reply <-= <-myreply {
		Quit =>
			break loop;
		Next =>
			if(d.dir == nil && d.data == nil){
				if(--indent == 0)
					break loop;
				(name, names) = (hd names, tl names);
			}
		Skip =>
			if(--indent == 0)
				break loop;
			(name, names) = (hd names, tl names);
		Down =>
			if(d.dir != nil){
				names = name :: names;
				if(d.dir.mode & Sys->DMDIR){
					if(indent == 0)
						name = d.dir.name;
					else{
						if(name[len name - 1] != '/')
							name[len name] = '/';
						name += d.dir.name;
					}
				}
				indent++;
			}
		}
	}
}
