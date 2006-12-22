Selectfile: module
{
	PATH:	con "/dis/lib/selectfile.dis";

	init:	fn(): string;
	filename:	fn(ctxt: ref Draw->Context, parent: ref Draw->Image,
				title: string,
				pat: list of string,
				dir: string): string;
#	select: fn(top: ref Tk->Toplevel, w: string,
#			root, dir: string,
#			pats: list of string, action: string): chan of (int, string);
};
