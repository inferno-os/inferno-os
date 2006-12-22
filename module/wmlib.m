Wmlib: module
{
	PATH:		con "/dis/lib/wmlib.dis";

	init:		fn();
	makedrawcontext: fn(): ref Draw->Context;
	importdrawcontext: fn(devdraw, mntwm: string): (ref Draw->Context, string);
	connect:	fn(ctxt: ref Draw->Context): ref Draw->Wmcontext;
	reshape:	fn(w: ref Draw->Wmcontext, name: string, r: Draw->Rect, i: ref Draw->Image, how: string): ref Draw->Image;
	startinput:	fn(w: ref Draw->Wmcontext, devs: list of string): string;	# could be part of connect?
	wmctl:	fn(w: ref Draw->Wmcontext, request: string): (string, ref Draw->Image, string);
#	wmtoken:	fn(w: ref Draw->Wmcontext): string;
	snarfput:	fn(buf: string);
	snarfget:	fn(): string;

	# XXX these don't really belong here, but where should they go?
	splitqword:	fn(s: string, e: int): ((int, int), int);
	qslice:		fn(s: string, r: (int, int)): string;
	qword:		fn(s: string, e: int): (string, int);
	s2r:			fn(s: string, e: int): (Draw->Rect, int);
};
