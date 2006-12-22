Prefab: module
{
	PATH:	con	"$Prefab";

	# types of Elements
	EIcon:		con 0;
	EText:		con 1;
	ETitle:		con 2;
	EHorizontal:	con 3;
	EVertical:	con 4;
	ESeparator:	con 5;

	# first arg to Element.adjust: size of elements
	Adjpack:	con 10;	# leave alone, pack tightly
	Adjequal:	con 11;	# make equal
	Adjfill:	con 12;	# make equal, filling available space

	# second arg: position of element within space
	Adjleft:	con 20;
	Adjup:		con 20;
	Adjcenter:	con 21;
	Adjright:	con 22;
	Adjdown:	con 22;

	# default fonts and colors for objects
	Style: adt
	{
		titlefont:	ref Draw->Font;
		textfont:	ref Draw->Font;
		elemcolor:	ref Draw->Image;
		edgecolor:	ref Draw->Image;
		titlecolor:	ref Draw->Image;
		textcolor:	ref Draw->Image;
		highlightcolor:	ref Draw->Image;
	};

	# drawing environment for objects
	Environ: adt
	{
		screen:	ref Draw->Screen;
		style:	ref Style;
	};

	# operand for layout operators; set either (font, color, text) or (icon, mask)
	Layout: adt
	{
		font:		ref Draw->Font;
		color:		ref Draw->Image;
		text:		string;
		icon:		ref Draw->Image;
		mask:		ref Draw->Image;
		tag:		string;
	};

	# graphical objects in the interface, recursively defined for making lists
	Element: adt
	{
		# part of Ell elements
		kind:		int;			# type: EIcon, EText, etc.
		r:		Draw->Rect;		# rectangle on screen
		environ:	ref Environ;		# graphics screen, style
		tag:		string;			# identifier for selection

		# different fields defined for different kinds of Elements
		kids:		list of ref Element;	# children of EHorizontal, EVertical
		str:		string;			# text in an EText element
		mask:		ref Draw->Image;	# part of Eicon, ESeparator
		image:		ref Draw->Image;	# part of Eicon, ESeparator, EText, Etitle
		font:		ref Draw->Font;		# part of EText, Etitle

		# constructors
		icon:		fn(env: ref Environ, r: Draw->Rect, icon, mask: ref Draw->Image): ref Element;
		text:		fn(env: ref Environ, text: string, r: Draw->Rect, kind: int): ref Element;
		layout:	fn(env: ref Environ, lay: list of Layout, r: Draw->Rect, kind: int): ref Element;
		elist:		fn(env: ref Environ, elem: ref Element, kind: int): ref Element;
		separator:	fn(env: ref Environ, r: Draw->Rect, icon, mask: ref Draw->Image): ref Element;

		# editing and geometry
		append:	fn(elist: self ref Element, elem: ref Element): int;
		adjust:	fn(elem: self ref Element, equal: int, dir: int);
		clip:		fn(elem: self ref Element, r: Draw->Rect);
		scroll:	fn(elem: self ref Element, d: Draw->Point);
		translate:	fn(elem: self ref Element, d: Draw->Point);
		show:	fn(elist: self ref Element, elem: ref Element): int;
	};

	# connects an element to a window for display
	Compound: adt
	{
		image:		ref Draw->Image;	# window on which contents are drawn
		environ:	ref Environ;		# graphics screen, style
		r:		Draw->Rect;		# rectangle on screen
		title:		ref Element;		# above the line (may be nil)
		contents:	ref Element;		# below the line

		# constructors
		iconbox:	fn(env: ref Environ, p: Draw->Point, title: string, icon, mask: ref Draw->Image): ref Compound;
		textbox:	fn(env: ref Environ, r: Draw->Rect, title, text: string): ref Compound;
		layoutbox:fn(env: ref Environ, r: Draw->Rect, title: string, lay: list of Layout): ref Compound;
		box:		fn(env: ref Environ, p: Draw->Point, title, elist: ref Element): ref Compound;

		# display
		draw:	fn(comp: self ref Compound);
		redraw:	fn(comp: self ref Compound, r: Draw->Rect);
		scroll:	fn(comp: self ref Compound, elem: ref Element, d: Draw->Point);
		show:	fn(comp: self ref Compound, elem: ref Element): int;

		# support for using EHorizontal and EVertical as menus
		select:	fn(comp: self ref Compound, elem: ref Element, i: int, c: chan of int): (int, int, ref Element);
		tagselect:	fn(comp: self ref Compound, elem: ref Element, i: int, c: chan of int): (int, int, ref Element);
		highlight:	fn(comp: self ref Compound, elem: ref Element, on: int);
	};
};
