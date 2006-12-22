
Strmap: module {
	PATH: con "/dis/ebook/strmap.dis";
	Map: adt {
		i2s:	array of string;
		s2i:	array of list of (string, int);
	
		new:	fn(a: array of string): ref Map;
		s:	fn(map: self ref Map, i: int): string;
		i:	fn(map: self ref Map, s: string): int;
	};
};
