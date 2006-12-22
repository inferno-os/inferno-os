FSproto: module
{
	PATH: con "/dis/lib/fsproto.dis";

	Direntry: type (string, string, ref Sys->Dir);

	init:	fn(): string;
	readprotofile: fn(proto: string, root: string, entries: chan of Direntry, warnings: chan of (string, string)): string;
	readprotostring: fn(proto: string, root: string, entries: chan of Direntry, warnings: chan of (string, string));
};
