Styxaux : module {
	PATH : con "/dis/acme/styxaux.dis";

	init : fn();

	msize: fn(m: ref Styx->Tmsg): int;
	version: fn(m: ref Styx->Tmsg): string;
	fid: fn(m: ref Styx->Tmsg): int;
	uname: fn(m: ref Styx->Tmsg): string;
	aname: fn(m: ref Styx->Tmsg): string;
	newfid: fn(m: ref Styx->Tmsg): int;
	name: fn(m: ref Styx->Tmsg): string;
	names: fn(m: ref Styx->Tmsg): array of string;
	mode: fn(m: ref Styx->Tmsg): int;
	offset: fn(m: ref Styx->Tmsg): big;
	count: fn(m: ref Styx->Tmsg): int;
	oldtag: fn(m: ref Styx->Tmsg): int;
	data: fn(m: ref Styx->Tmsg): array of byte;

	setmode: fn(m: ref Styx->Tmsg, mode: int);
	setcount: fn(m: ref Styx->Tmsg, count: int);
	setdata: fn(m: ref Styx->Tmsg, data: array of byte);

};
