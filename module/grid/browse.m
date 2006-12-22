Browse: module
{
	PATH: con "/dis/grid/lib/browse.dis";
	
	# panetype
	SINGLEPANE: con 1; # does not work yet
	SPLITPANE: con 2;
	# filetype
	DIRSONLY: con 3;
	FILESONLY: con 4;
	FILESORDIRS: con 5;
	# selecttype
	SINGLE: con 1;
	MULTI: con 2;
	SELECT: con 1;
	TOGGLE: con 2;
	NONE: con 3;
	opened : list of string;
	init : fn (top: ref Tk->Toplevel, rlabel, root: string, ptype, ftype, stype: int, pathrd : PathReader);
	getselectedpath : fn (pane: int): string;
	refresh : fn (top: ref Tk->Toplevel);
	gotofile : fn (top: ref Tk->Toplevel, path:string, pnum: int);
	opendir : fn (top: ref Tk->Toplevel, path, tkpath: string);
	changepane : fn (top: ref Tk->Toplevel, ptype: int);
	resizewin : fn (top: ref Tk->Toplevel, width, height: int);
	selectfile : fn (top: ref Tk->Toplevel, pane, action: int, path, tkpath: string);
	setscrollr : fn (top: ref Tk->Toplevel);
	getpnum : fn (tkpath: string): int;
	pane1see : fn (top: ref Tk->Toplevel);
	gotopath : fn (top: ref Tk->Toplevel, dir: string, openfinal, pnum: int): string;
	getpath : fn (top: ref Tk->Toplevel, f: string): string;
	prevpath : fn (path: string): string;
	setcentre : fn (top1, top2: ref Tk->Toplevel);
	addselection : fn (top: ref Tk->Toplevel, file: string, val, args, dups: int, sval, sargs: string): string;
	delselection : fn (top: ref Tk->Toplevel, n: string): string;
	newfl : fn (top: ref Tk->Toplevel, rlabel, root: string);
	setc3frame : fn (top: ref Tk->Toplevel, frame: string);
	doargs : fn (top: ref Tk->Toplevel, lst: list of string);
	getselected : fn (top: ref Tk->Toplevel, frame: string): list of (string, string, string);
	movdiv : fn (top: ref Tk->Toplevel, x: int);
	dialog : fn (ctxt: ref draw->Context, oldtop: ref Tk->Toplevel, butlist: list of string, title, msg: string): int;
	getc3frame : fn (): string;
};