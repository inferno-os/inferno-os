Polyfill: module
{
	PATH: con "/dis/math/polyfill.dis";

	Zstate: adt{
		r: Draw->Rect;
		zbuf0, zbuf1: array of int;
		xlen: int;
		ylen: int;
		xylen: int;
	};

	init: fn();
	initzbuf: fn(r: Draw->Rect): ref Zstate;
	clearzbuf: fn(s: ref Zstate);
	setzbuf: fn(s: ref Zstate, zd: int);
	fillpoly: fn(d: ref Image, v: array of Point, w: int, s: ref Image, p: Point, zstate: ref Zstate, dc, dx, dy: int);
};