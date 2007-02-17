Lists: module
{
	map:	fn[T](f: ref fn(x: T): T, l: list of T): list of T;
	allsat:	fn[T](p: ref fn(x: T): int, l: list of T): int;
	anysat:	fn[T](p: ref fn(x: T): int, l: list of T): int;
	filter:	fn[T](p: ref fn(x: T): int, l: list of T): list of T;
	partition:	fn[T](p: ref fn(x: T): int, l: list of T): (list of T, list of T);

	append:	fn[T](l: list of T, x: T): list of T;
	concat:	fn[T](l: list of T, l2: list of T): list of T;
	combine:	fn[T](l: list of T, l2: list of T): list of T;
	reverse:	fn[T](l: list of T): list of T;
	last:	fn[T](l: list of T): T;
	delete:	fn[T](x: T, l: list of T): list of T
		for { T => eq:	fn(a, b: T): int; };
	pair:	fn[T1, T2](l1: list of T1, l2: list of T2): list of (T1, T2);
	unpair:	fn[T1, T2](l: list of (T1, T2)): (list of T1, list of T2);
	ismember:	fn[T](x: T, l: list of T): int
		for { T =>	eq:	fn(a, b: T): int; };
};

#sort?
#join
#split
