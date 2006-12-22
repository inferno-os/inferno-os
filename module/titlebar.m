Titlebar: module{
	PATH: con "/dis/lib/titlebar.dis";

	Resize,
	Hide,
	Help,
	OK,
	Popup,
	Plain:		con 1 << iota;
	Appl:		con Resize | Hide;

	init:	fn();
	new:		fn(top: ref Tk->Toplevel, buts: int): chan of string;
	minsize:	fn(top: ref Tk->Toplevel): Draw->Point;
	title:		fn(top: ref Tk->Toplevel): string;
	settitle:	fn(top: ref Tk->Toplevel, title: string): string;
	sendctl:	fn(top: ref Tk->Toplevel, c: string);
};
