implement Lists;

include "lists.m";

# these will be more useful when p is a closure
allsat[T](p: ref fn(x: T): int, l: list of T): int
{
	for(; l != nil; l = tl l)
		if(!p(hd l))
			return 0;
	return 1;
}

anysat[T](p: ref fn(x: T): int, l: list of T): int
{
	for(; l != nil; l = tl l)
		if(p(hd l))
			return 1;
	return 0;
}

map[T](f: ref fn(x: T): T, l: list of T): list of T
{
	if(l == nil)
		return nil;
	return f(hd l) :: map(f, tl l);
}

filter[T](p: ref fn(x: T): int, l: list of T): list of T
{
	if(l == nil)
		return nil;
	if(p(hd l))
		return hd l :: filter(p, tl l);
	return filter(p, tl l);
}

partition[T](p: ref fn(x: T): int, l: list of T): (list of T, list of T)
{
	l1: list of T;
	l2: list of T;
	for(; l != nil; l = tl l)
		if(p(hd l))
			l1 = hd l :: l1;
		else
			l2 = hd l :: l2;
	return (reverse(l1), reverse(l2));
}

append[T](l: list of T, x: T): list of T
{
	# could use the reversing loops instead if this is ever a bottleneck
	if(l == nil)
		return x :: nil;
	return hd l :: append(tl l, x);
}

concat[T](l: list of T, l2: list of T): list of T
{
	if(l2 == nil)
		return l;
	for(l = reverse(l); l2 != nil; l2 = tl l2)
		l = hd l2 :: l;
	return reverse(l);
}

combine[T](l: list of T, l2: list of T): list of T
{
	for(; l != nil; l = tl l)
		l2 = hd l :: l2;
	return l2;
}

reverse[T](l: list of T): list of T
{
	rl: list of T;
	for(; l != nil; l = tl l)
		rl = hd l :: rl;
	return rl;
}

last[T](l: list of T): T
{
	# l must not be nil
	while(tl l != nil)
		l = tl l;
	return hd l;
}

# delete the first instance of x in l
delete[T](x: T, l: list of T): list of T
	for { T =>	eq:	fn(a, b: T): int; }
{
	o: list of T;
	for(; l != nil; l = tl l)
		if(T.eq(x, hd l)){
			l = tl l;
			for(; o != nil; o = tl o)
				l = hd o :: l;
			break;
		}
	return l;
}

pair[T1, T2](l1: list of T1, l2: list of T2): list of (T1, T2)
{
	if(l1 == nil && l2 == nil)
		return nil;
	return (hd l1, hd l2) :: pair(tl l1, tl l2);
}

unpair[T1, T2](l: list of (T1, T2)): (list of T1, list of T2)
{
	l1: list of T1;
	l2: list of T2;
	for(; l != nil; l = tl l){
		(v1, v2) := hd l;
		l1 = v1 :: l1;
		l2 = v2 :: l2;
	}
	return (reverse(l1), reverse(l2));
}

ismember[T](x: T, l: list of T): int
	for { T =>	eq:	fn(a, b: T): int; }
{
	for(; l != nil; l = tl l)
		if(T.eq(x, hd l))
			return 1;
	return 0;
}
