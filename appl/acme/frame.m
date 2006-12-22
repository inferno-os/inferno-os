Framem : module {
	PATH : con "/dis/acme/frame.dis";

	BACK, HIGH, BORD, TEXT, HTEXT, NCOL : con iota;

	FRTICKW : con 3;

	init : fn(mods : ref Dat->Mods);

	newframe : fn() : ref Frame;

	Frbox : adt {
		wid : int;					# in pixels
		nrune : int;				# <0 ==> negate and treat as break char
		ptr : string;
		bc : int;		# break char
		minwid : int;
	};

	Frame : adt {
		font : ref Draw->Font;		# of chars in the frame
		b : ref Draw->Image;		# on which frame appears
		cols : array of ref Draw->Image;	# colours
		r : Draw->Rect;				# in which text appears
		entire : Draw->Rect;			# of full frame
		box : array of ref Frbox;
		scroll : int;				# call framescroll function
		p0 : int;
		p1 : int;					# selection
		nbox, nalloc : int;
		maxtab : int;				# max size of tab, in pixels
		nchars : int;				# runes in frame
		nlines : int;				# lines with text
		maxlines : int;				# total # lines in frame
		lastlinefull : int;				# last line fills frame
		modified : int;				# changed since frselect()
		noglyph : int;				# char to use when a char has 0 width glyph
		tick : ref Draw->Image;		# typing tick
		tickback : ref Draw->Image;	# saved image under tick
		ticked : int;				# is tick on screen ?
	};

	frcharofpt : fn(f : ref Frame, p : Draw->Point) : int;
	frptofchar : fn(f : ref Frame, c : int) : Draw->Point;
	frdelete : fn(f : ref Frame, c1 : int, c2 : int) : int;
	frinsert : fn(f : ref Frame, s : string, l : int, i : int);
	frselect : fn(f : ref Frame, m : ref Draw->Pointer);
	frinit : fn(f : ref Frame, r : Draw->Rect, f : ref Draw->Font, b : ref Draw->Image, cols : array of ref Draw->Image);
	frsetrects : fn(f : ref Frame, r : Draw->Rect, b : ref Draw->Image);
	frclear : fn(f : ref Frame, x : int);
	frdrawsel : fn(f : ref Frame, p : Draw->Point, p0 : int, p1 : int, n : int);
	frdrawsel0 : fn(f : ref Frame, p : Draw->Point, p0 : int, p1 : int, i1 : ref Draw->Image, i2 : ref Draw->Image);
	frtick : fn(f : ref Frame, p : Draw->Point, n : int);
};
