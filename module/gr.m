GR: module{
	PATH:	con "/dis/math/gr.dis";

	OP: adt{
		code, n: int;
		x, y: array of real;
		t: string;
	};

	open:	fn(ctxt: ref Draw->Context, title: string): ref Plot;

	Plot: adt{
		bye:	fn(p: self ref Plot);
		equalxy:fn(p: self ref Plot);
		graph:	fn(p: self ref Plot, x, y: array of real);
		paint: 	fn(p: self ref Plot, xlabel, xunit, ylabel, yunit: string);
		pen:	fn(p: self ref Plot, nib: int);
		text:	fn(p: self ref Plot, justify: int, s: string, x, y: real);

		op: list of OP;
		xmin, xmax, ymin, ymax: real;
		textsize: real;
		t: ref Tk->Toplevel;		# window containing .fc.c canvas
		titlechan: chan of string;	# Wm titlebar
		canvaschan: chan of string;	# button clicks for measurements
	};

	# op code
	GRAPH:		con 1;
	TEXT:		con 2;
	PEN:		con 3;

	# pen
	CIRCLE:		con 101;
	CROSS:		con 102;
	SOLID:		con 103;
	DASHED:		con 104;
	INVIS:		con 105;
	REFERENCE:	con 106;
	DOTTED:		con 107;

	# text justify
	LJUST:		con 8r00;
	CENTER:		con 8r01;
	RJUST:		con 8r02;
	HIGH:		con 8r00;
	MED:		con 8r10;
	BASE:		con 8r20;
	LOW:		con 8r30;
	UP:		con 8r100;
};
