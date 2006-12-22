Browser: module {

	PATH: con "/dis/grid/lib/browser.dis";

	DESELECT: con 0;
	SELECT: con 1;
	TOGGLE: con 2;
	OPEN: con 3;
	CLOSE: con 4;

	init: fn ();
	dialog: fn (ctxt: ref draw->Context, oldtop: ref Tk->Toplevel, butlist: list of string, title, msg: string): int;
	prevpath: fn (path: string): string;
	setcentre: fn (top1, top2: ref Tk->Toplevel);

	Browse: adt {
		new: fn (top: ref Tk->Toplevel, tkchanname, root, rlabel: string, nopanes: int, reader: PathReader): ref Browse;
		refresh: fn (b: self ref Browse);
		defaultaction: fn (b: self ref Browse, lst: list of string, f: ref File);
		getpath: fn (b: self ref Browse, tkpath: string): ref File;
		opendir: fn (b: self ref Browse, file: File, tkpath: string, action: int): int;
		newroot: fn (b: self ref Browse, root, rlabel: string);
		changeview: fn (b: self ref Browse, nopanes: int);
		selectfile: fn (b: self ref Browse, pane, action: int, file: File, tkpath: string);
		gotoselectfile: fn (b: self ref Browse, file: File): string;
		gotopath: fn (b: self ref Browse, dir: File, openfinal: int): (File, string);
		getselected: fn (b: self ref Browse, pane: int): File;
		addopened: fn (b: self ref Browse, file: File, add: int);
		showpath: fn (b: self ref Browse, on: int);
		resize: fn (b: self ref Browse);
		top: ref Tk->Toplevel;
		tkchan: string;
		bgnorm, bgselect: string;
		nopanes: int;
		selected: array of Selected;
		opened: list of File;
		root, rlabel: string;
		reader: PathReader;
		pane1: File;
		pane0width: string;
		width: int;
		showpathlabel: int;
		released: int;
	};

	SELECTED: con 0;
	UNSELECTED: con 1;
	ALL: con 2;

	Select: adt {
		new: fn (top: ref Tk->Toplevel, tkchanname: string): ref Select;
		addframe: fn (s: self ref Select, fname, title: string);
		showframe: fn (s: self ref Select, fname: string);
		delframe: fn (s: self ref Select, fname: string);
		addselection: fn (s: self ref Select, fname, text: string, lp: list of ref Parameter, allowdups: int): string;
		delselection: fn (s: self ref Select, fname, tkpath: string);
		getselection: fn (s: self ref Select, fname: string): list of (string, list of ref Parameter);
		getselected: fn (s: self ref Select, fname: string): string;
		select: fn (s: self ref Select, fname, tkpath: string, action: int);
		defaultaction: fn (s: self ref Select, lst: list of string);
		resize: fn (s: self ref Select, width, height: int);
		setscrollr: fn (s: self ref Select, fname: string);
		top: ref Tk->Toplevel;
		tkchan: string;
		currfname, currfid: string;
		frames: list of ref Frame;
	};

	Frame: adt {
		name: string;
		path: string;
		selected: string;
	};

	Parameter: adt {
		pick {
		ArgIn =>
			name, initval: string;
		ArgOut =>
			name, val: string;
		IntIn =>
			min, max, initval: int;
		IntOut =>
			val: int;
		}
	};

	File: adt {
		eq: fn (a,b: File): int;
		path, qid: string;
	};

	Selected: adt {
		file: File;
		tkpath: string;
	};
};