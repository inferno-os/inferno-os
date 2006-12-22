#
# Copyright © 2001 Vita Nuova Limited
#
Btos: module {
	init: fn(arg: string): string;
	btos: fn(s: Convcs->State, b: array of byte, nchars: int) : (Convcs->State, string, int);
};

Stob: module {
	init: fn(arg: string): string;
	stob: fn(s: Convcs->State, str: string): (Convcs->State, array of byte);
};

Convcs: module {
	PATH: con "/dis/lib/convcs/convcs.dis";
	CHARSETS: con "/lib/charsets";

	BTOS, STOB: con 1 << iota;		# enumcs() mode values
	BOTH: con BTOS | STOB;

	State: type string;
	Startstate: con "";

	init: fn(csfile: string): string;
	getbtos: fn(cs: string): (Btos, string);
	getstob: fn(cs: string): (Stob, string);
	enumcs: fn(): list of (string, string, int);		# (cs, description, mode)
	aliases: fn(cs : string): (string, list of string);
};
