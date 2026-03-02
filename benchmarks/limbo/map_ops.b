implement BenchMapOps;

include "sys.m";
	sys: Sys;

include "draw.m";

# Limbo doesn't have built-in maps like Go.
# We'll use a sorted array of key-value pairs + binary search.
# This is a fair comparison since Go-on-Dis maps also use sorted arrays.

BenchMapOps: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

KV: adt {
	key: string;
	val: int;
};

# Simple insertion sort to maintain sorted order
insert(kvs: array of KV, n: int, key: string, val: int): int
{
	# Binary search for insertion point
	lo := 0;
	hi := n - 1;
	while(lo <= hi) {
		mid := (lo + hi) / 2;
		if(kvs[mid].key == key) {
			kvs[mid].val = val;
			return n;
		}
		if(kvs[mid].key < key)
			lo = mid + 1;
		else
			hi = mid - 1;
	}
	# Insert at lo
	for(i := n; i > lo; i--)
		kvs[i] = kvs[i-1];
	kvs[lo] = KV(key, val);
	return n + 1;
}

lookup(kvs: array of KV, n: int, key: string): (int, int)
{
	lo := 0;
	hi := n - 1;
	while(lo <= hi) {
		mid := (lo + hi) / 2;
		if(kvs[mid].key == key)
			return (kvs[mid].val, 1);
		if(kvs[mid].key < key)
			lo = mid + 1;
		else
			hi = mid - 1;
	}
	return (0, 0);
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	# Pre-build keys
	nk := 100;
	keys := array[nk] of string;
	for(ki := 0; ki < nk; ki++)
		keys[ki] = sys->sprint("key%d", ki);

	t1 := sys->millisec();
	iterations := 100;
	total := 0;
	for(iter := 0; iter < iterations; iter++) {
		kvs := array[nk] of KV;
		n := 0;
		for(i := 0; i < nk; i++)
			n = insert(kvs, n, keys[i], i);
		sum := 0;
		for(j := 0; j < nk; j++) {
			(v, ok) := lookup(kvs, n, keys[j]);
			if(ok)
				sum += v;
		}
		total += sum;
	}
	t2 := sys->millisec();
	sys->print("BENCH map_ops %d ms %d iters %d\n", t2-t1, iterations, total);
}
