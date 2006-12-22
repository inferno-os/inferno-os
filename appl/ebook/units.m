Units: module {
	PATH: con "/dis/ebook/units.dis";
	init:	fn();
	length: fn(s: string, emsize, exsize: int, relative: string): (int, string);
	isrelative: fn(s: string): int;
};
