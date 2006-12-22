Exproc : module
{
	getslavedata : fn (lst: list of string);
	doblock : fn (block: int, bpath: string);
	readblock : fn (block: int, dir: string, chanout: chan of string): int;
	finish : fn (waittime: int, tkchan: chan of string);
};