implement Extvalues;
include "sys.m";
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
include "alphabet.m";

Values[V].new(): ref Values[V]
{
	v: V;
	return ref Values[V](chan[1] of int, array[4] of {* => (0, v)}, 0::1::2::3::nil);
}

Values[V].add(vals: self ref Values, v: V): int
{
	vals.lock <-= 1;
	if(vals.freeids == nil){
		n := len vals.v;
		vals.v = (array[len vals.v * 3 / 2] of (int, V))[0:] = vals.v;
		for(; n < len vals.v; n++)
			vals.freeids = n :: vals.freeids;
	}
	id := hd vals.freeids;
	vals.freeids = tl vals.freeids;
	vals.v[id] = (1, v);
#(load Sys Sys->PATH)->print("add %d\n", id);
	<-vals.lock;
	return id;
}

Values[V].inc(vals: self ref Values, id: int)
{
	vals.lock <-= 1;
	vals.v[id].t0++;
#(load Sys Sys->PATH)->print("inc %d -> %d\n", id, vals.v[id].t0);
	<-vals.lock;
}

Values[V].del(vals: self ref Values, id: int)
{
	vals.lock <-= 1;
	if(--vals.v[id].t0 == 0){
		vals.v[id].t1 = nil;
		vals.freeids = id :: vals.freeids;
	}
#(load Sys Sys->PATH)->print("del %d -> %d\n", id, vals.v[id].t0);
	<-vals.lock;
}

