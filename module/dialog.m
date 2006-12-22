Dialog: module
{
	PATH:		con "/dis/lib/dialog.dis";
	init:		fn(): string;

	prompt:		fn(ctxt: ref Draw->Context, parent: ref Draw->Image, ico, title, msg: string,
				dflt: int, labs: list of string): int;
	getstring:	fn(ctxt: ref Draw->Context, parent: ref Draw->Image, msg: string): string;
};
