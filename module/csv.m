CSV: module
{
	PATH:	con "/dis/lib/csv.dis";

	init:	fn(b: Bufio);
	getline:	fn(fd: ref Bufio->Iobuf): list of string;
	quote:	fn(s: string): string;
};
