
Joinsession: module {
	PATH: con "/dis/spree/joinsession.dis";
	join: fn(ctxt: ref Draw->Context, mnt: string, dir: string, join: string): string;
	init:   fn(ctxt: ref Draw->Context, argv: list of string);
};

