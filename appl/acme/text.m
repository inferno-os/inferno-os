Textm : module {
	PATH : con "/dis/acme/text.dis";

	init : fn(mods : ref Dat->Mods);

	# Text.what
	Columntag, Rowtag, Tag, Body : con iota;

	newtext : fn() : ref Text;

	Text : adt {
		file : cyclic ref Filem->File;
		frame : ref Framem->Frame;
		reffont : ref Dat->Reffont;
		org : int;
		q0 : int;
		q1 : int;
		what : int;
		tabstop : int;
		w : cyclic ref Windowm->Window;
		scrollr : Draw->Rect;
		lastsr : Draw->Rect;
		all : Draw->Rect;
		row : cyclic ref Rowm->Row;
		col : cyclic ref Columnm->Column;
		eq0 : int;		# start of typing for ESC
		cq0 : int;		# cache position
		ncache : int;	# storage for insert
		ncachealloc : int;
		cache : string;
		nofill : int;

		init : fn(t : self ref Text, f : ref Filem->File, r : Draw->Rect, rf : ref Dat->Reffont, cols : array of ref Draw->Image);
		redraw : fn(t : self ref Text, r : Draw->Rect, f : ref Draw->Font, b : ref Draw->Image, n : int);
		insert : fn(t : self ref Text, n : int, s : string, p : int, q : int, r : int);
		bsinsert : fn(t : self ref Text, n : int, s : string, p : int, q : int) : (int, int);
		delete : fn(t : self ref Text, n : int, p : int, q : int);
		loadx : fn(t : self ref Text, n : int, b : string, q : int) : int;
		typex : fn(t : self ref Text, r : int, echomode : int);
		select : fn(t : self ref Text, d : int);
		select2 : fn(t : self ref Text, p : int, q : int) : (int, ref Text, int, int);
		select3 : fn(t : self ref Text, p: int, q : int) : (int, int, int);
		setselect : fn(t : self ref Text, p : int, q : int);
		setselect0 : fn(t : self ref Text, p : int, q : int);
		show : fn(t : self ref Text, p : int, q : int);
		fill : fn(t : self ref Text);
		commit : fn(t : self ref Text, n : int);
		setorigin : fn(t : self ref Text, p : int, q : int);
		readc : fn(t : self ref Text, n : int) : int;
		reset : fn(t : self ref Text);
		reshape : fn(t : self ref Text, r : Draw->Rect) : int;
		close : fn(t : self ref Text);
		framescroll : fn(t : self ref Text, n : int);
		select23 : fn(t : self ref Text, p : int, q : int, i, it : ref Draw->Image, n : int) : (int, int, int);
		forwnl : fn(t : self ref Text, p : int, q : int) : int;
		backnl : fn(t : self ref Text, p : int, q : int) : int;
		bswidth : fn(t : self ref Text, r : int) : int;
		doubleclick : fn(t : self ref Text, p : int, q : int) : (int, int);
		clickmatch : fn(t : self ref Text, p : int, q : int, r : int, n : int) : (int, int);
		columnate : fn(t : self ref Text, d : array of ref Dat->Dirlist, n : int);
	};

	framescroll : fn(f : ref Framem->Frame, dl : int);
	setalphabet: fn(s: string);
};