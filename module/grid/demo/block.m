Block : module
{
	PATH: con "/dis/grid/demo/block.dis";

	init : fn (pathname: string, ep: Exproc);
	slave : fn ();
	writedata : fn (s: string);
	masterinit : fn (noblocks: int);
	reader : fn (noblocks: int, chanout: chan of string, sync: chan of int);
	makefile : fn (block: int, let: string): string;
	err : fn (s: string);
	cleanfiles : fn (delpath: string);
	isin : fn (l: list of string, s: string): int;
};