Pedit: module
{
	PATH: con "/dis/disk/pedit.dis";

	Part: adt {
		name:	string;
		ctlname:	string;
		start:		big;
		end:		big;
		ctlstart:	big;
		ctlend:	big;
		changed:	int;
		tag:		int;
	};

	Maxpart: con 32;

	Edit: adt {
		disk:	ref Disks->Disk;

		ctlpart:	array of ref Part;
		part:	array of ref Part;

		# to do: replace by channels
		add:	ref fn(e: ref Edit, s: string, a, b: big): string;
		del:	ref fn(e: ref Edit, p: ref Part): string;
		ext:	ref fn(e: ref Edit, f: array of string): string;
		help:	ref fn(e: ref Edit): string;
		okname:	ref fn(e: ref Edit, s: string): string;
		sum:	ref fn(e: ref Edit, p: ref Part, a, b: big);
		write:	ref fn(e: ref Edit): string;
		printctl:	ref fn(e: ref Edit, x: ref Sys->FD);

		unit:	string;
		dot:	big;
		end:	big;

		# do not use fields below this line
		changed:	int;
		warned:	int;
		lastcmd:	int;

		mk:	fn(unit: string): ref Edit;
		getline:	fn(e: self ref Edit): string;
		runcmd:	fn(e: self ref Edit, c: string);
		findpart:	fn(e: self ref Edit, n: string): ref Part;
		addpart:	fn(e: self ref Edit, p: ref Part): string;
		delpart:	fn(e: self ref Edit, p: ref Part): string;
		ctldiff:	fn(e: self ref Edit, ctlfd: ref Sys->FD): int;
	};

	init:	fn();
};
