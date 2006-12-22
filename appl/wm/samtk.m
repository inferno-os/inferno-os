Samtk: module
{

	PATH:		con "/dis/wm/samtk.dis";

	Cut,
	Paste,
	Snarf,
	Look,
#	Exch,
	Send,
	NMENU2: con iota;
	Search: con Send;

	New,
	Zerox,
	Close,
	Write,
	NMENU3: con iota;

	None,
	Some,
	All: con iota;	# visibility in flayer (`some' may not be used)

	init:		fn(ctxt: ref Context);

	allflayers:	fn(s: string);
	append:		fn(fls: list of ref Flayer, fl: ref Flayer):
				list of ref Flayer;
	buttonselect:	fn(fl: ref Flayer, s: string): int;
	chanadd:	fn(): int;
	chandel:	fn(n: int);
	coord2pos:	fn(t: ref Text, fl: ref Flayer, s: string): int;
	flclear:	fn(fl: ref Flayer);
	fldelete:	fn(fl: ref Flayer, l1, l2: int);
	fldelexcess:	fn(fl: ref Flayer);
	flinsert:	fn(fl: ref Flayer, l: int, s: string);
	flraise:	fn(t: ref Text, fl: ref Flayer);
	focus:		fn(fl: ref Flayer);
	hsetpat:	fn(s: string);
	menudel:	fn(pos: int);
	menuins:	fn(pos: int, s: string);
	newcur:		fn(t: ref Text, fl: ref Flayer);
	newflayer:	fn(tag, tp: int): ref Flayer;
	panic:		fn(s: string);
	resize:		fn(fl: ref Flayer);
	scroll:		fn(fl: ref Flayer, s: string): (int, int);
	setdot:		fn(fl: ref Flayer, l1, l2: int);
	setscrollbar:	fn(t: ref Text, fl: ref Flayer);
	settitle:	fn(t: ref Text, s: string);
	titlectl:	fn(win: int, menu: string);
	whichmenu:	fn(tag: int): int;
	whichtext:	fn(tag: int): int;
};
