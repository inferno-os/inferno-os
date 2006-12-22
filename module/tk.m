Tk: module
{
	PATH:	con	"$Tk";

	Toplevel: adt
	{
		display:	ref Draw->Display;
		wreq:	chan of string;
		image:	ref Draw->Image;
		ctxt:		ref Draw->Wmcontext;	# placeholder, not used by tk
		screenr:	Draw->Rect;			# writable
	};
	Border, Required, Local: con 1<<iota;
	rect:			fn(t: ref Toplevel, name: string, flags: int): Draw->Rect;

	toplevel:		fn(d: ref Draw->Display, arg: string): ref Toplevel;
	namechan:	fn(t: ref Toplevel, c: chan of string, n: string): string;
	cmd:			fn(t: ref Toplevel, arg: string): string;
	pointer:		fn(t: ref Toplevel, p: Draw->Pointer);
	keyboard:		fn(t: ref Toplevel, key: int);
	putimage:		fn(t: ref Toplevel, name: string, i, m: ref Draw->Image): string;
	getimage:		fn(t: ref Toplevel, name: string): (ref Draw->Image, ref Draw->Image, string);
	quote:		fn(s: string): string;
	color:		fn(col: string): int;
};
