Sort: module {
	PATH: con "/dis/lib/sort.dis";
	sort: fn[S, T](s: S, a: array of T)
		for{
		S =>
			gt: fn(s: self S, x, y: T): int;
		};
};
