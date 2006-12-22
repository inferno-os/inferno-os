Watchvars: module {
	PATH: con "/dis/lib/watchvars.dis";
	Watchvar: adt[T] {
		c: chan of (T, chan of T);

		new:	fn(v: T): Watchvar[T];
		get:	fn(e: self Watchvar[T]): T;
		set:	fn(e: self Watchvar[T], v: T);
		wait:	fn(e: self Watchvar[T]): T;
		waitc:	fn(e: self Watchvar[T]): (T, chan of T);
		waited:	fn(e: self Watchvar[T], ic: chan of T, v: T);
	};
};
