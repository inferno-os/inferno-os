Extvalues: module {
	PATH: con "/dis/alphabet/extvalues.dis";
	Values: adt[V] {
		lock: chan of int;
		v: array of (int, V);
		freeids: list of int;
		new: fn(): ref Values[V];
		add: fn(vals: self ref Values, v: V): int;
		inc: fn(vals: self ref Values, id: int);
		del: fn(vals: self ref Values, id: int);
	};
};
