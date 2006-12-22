implement Tables;
include "tables.m";

Table[T].new(nslots: int, nilval: T): ref Table[T]
{
	if(nslots == 0)
		nslots = 13;
	return ref Table[T](array[nslots] of list of (int, T), nilval);
}

Table[T].add(t: self ref Table[T], id: int, x: T): int
{
	slot := id % len t.items;
	for(q := t.items[slot]; q != nil; q = tl q)
		if((hd q).t0 == id)
			return 0;
	t.items[slot] = (id, x) :: t.items[slot];
	return 1;
}

Table[T].del(t: self ref Table[T], id: int): int
{
	slot := id % len t.items;
	
	p: list of (int, T);
	r := 0;
	for(q := t.items[slot]; q != nil; q = tl q){
		if((hd q).t0 == id){
			p = joinip(p, tl q);
			r = 1;
			break;
		}
		p = hd q :: p;
	}
	t.items[slot] = p;
	return r;
}

Table[T].find(t: self ref Table[T], id: int): T
{
	for(p := t.items[id % len t.items]; p != nil; p = tl p)
		if((hd p).t0 == id)
			return (hd p).t1;
	return t.nilval;
}

Strhash[T].new(nslots: int, nilval: T): ref Strhash[T]
{
	if(nslots == 0)
		nslots = 13;
	return ref Strhash[T](array[nslots] of list of (string, T), nilval);
}

Strhash[T].add(t: self ref Strhash, id: string, x: T)
{
	slot := hash(id, len t.items);
	t.items[slot] = (id, x) :: t.items[slot];
}

Strhash[T].del(t: self ref Strhash, id: string)
{
	slot := hash(id, len t.items);

	p: list of (string, T);
	for(q := t.items[slot]; q != nil; q = tl q)
		if((hd q).t0 != id)
			p = hd q :: p;
	t.items[slot] = p;
}

Strhash[T].find(t: self ref Strhash, id: string): T
{
	for(p := t.items[hash(id, len t.items)]; p != nil; p = tl p)
		if((hd p).t0 == id)
			return (hd p).t1;
	return t.nilval;
}

hash(s: string, n: int): int
{
	h := 0;
	m := len s;
	for(i:=0; i<m; i++){
		h = 65599*h+s[i];
	}
	return (h & 16r7fffffff) % n;
}

rev[T](x: list of T): list of T
{
	l: list of T;
	for(; x != nil; x = tl x)
		l = hd x :: l;
	return l;
}

# join x to y, leaving result in arbitrary order.
joinip[T](x, y: list of (int, T)): list of (int, T)
{
	if(len x > len y)
		(x, y) = (y, x);
	for(; x != nil; x = tl x)
		y = hd x :: y;
	return y;
}
