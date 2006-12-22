implement Strmap;
include "strmap.m";

Map.new(a: array of string): ref Map
{
	map := ref Map(a, array[31] of list of (string, int));
	# enter all style names in hash table for reverse lookup
	s2i := map.s2i;
	for (i := 0; i < len a; i++) {
		if (a[i] != nil) {
			v := hashfn(a[i], len s2i);
			s2i[v] = (a[i], i) :: s2i[v];
		}
	}
	return map;
}

Map.s(map: self ref Map, i: int): string
{
	return map.i2s[i];
}

Map.i(map: self ref Map, s: string): int
{
	v := hashfn(s, len map.s2i);
	for (l := map.s2i[v]; l != nil; l = tl l)
		if ((hd l).t0 == s)
			return (hd l).t1;
	return -1;
}

hashfn(s: string, n: int): int
{
	h := 0;
	m := len s;
	for(i:=0; i<m; i++){
		h = 65599*h+s[i];
	}
	return (h & 16r7fffffff) % n;
}
