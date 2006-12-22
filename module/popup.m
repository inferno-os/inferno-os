# pop-up menus.
# use choicebuttons instead - it's difficult to get these right.
Popup: module {
	PATH: con "/dis/lib/popup.dis";
	init: fn();
#	mkbutton: fn(win: ref Tk->Toplevel, w: string, a: array of string, n: int): chan of string;
#	changebutton: fn(win: ref Tk->Toplevel, w: string, a: array of string, n: int);
#	event: fn(win: ref Tk->Toplevel, e: string, a: array of string): int;
#	add: fn(a: array of string, s: string): (array of string, int);
	post: fn(win: ref Tk->Toplevel, p: Draw->Point, a: array of string, n: int): chan of int;
};
