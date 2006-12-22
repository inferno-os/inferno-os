Dividers: module {
	init: fn();
	Divider: adt {
		new: fn(win: ref Tk->Toplevel, w: string, wl: list of string, dir: int): (ref Divider, chan of string);
		event: fn(d: self ref Divider, e: string);

		# private from here.
		win: ref Tk->Toplevel;
		w: string;
		state: ref DState;
		
		dir: int;			# NS or EW
		widgets: array of ref DWidget;
		canvsize: Draw->Point;
	};

	EW, NS: con iota;
	PATH: con "/dis/lib/dividers.dis";

	# private from here
	DWidget: adt {
		w: string;
		r: Draw->Rect;
		size: Draw->Point;
	};
	
	DState: adt {
		dragdiv: int;
		dy: int;
		maxy, miny: int;
	};
	
};
