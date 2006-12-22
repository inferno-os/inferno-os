Diss: module {};

DebSrc: module
{
	PATH:	con "/dis/wm/debsrc.dis";

	Mod: adt
	{
		src:	string;		# .b path
		tk:	string;		# text widget
		dis:	string;		# .dis path
		sym:	ref Sym;	# debugger symbol table
		srcask:	int;		# look for src file?
		symask:	int;		# look for symbol file?
	};

	loadsrc:	fn(src: string, addpath: int): ref Mod;
	showstrsrc:	fn(src: string);
	search:		fn(s: string): int;
	snarf:		fn(): string;
	getsel:		fn(): (ref Mod, int);
	attachdis:	fn(m: ref Mod): int;
	attachsym:	fn(m: ref Mod);
	showmodsrc:	fn(m: ref Mod, src: ref Src);
	findmod:	fn(m: ref Module): ref Mod;

	init:		fn(ctxt: ref Draw->Context, t: ref Tk->Toplevel,
				tkclient: Tkclient, selectfile: Selectfile, dialog: Dialog,
				str: String, debug: Debug, xscroll: int, remcr: int);
	reinit:	fn(xscroll: int, remcr: int);

	packed:		ref Mod;
	searchpath:	array of string;
	opendir:	string;
};

DebData: module
{
	PATH:	con "/dis/wm/debdata.dis";

	Datum: adt
	{
		tkid:		string;
		parent:		string;				# tkid of parent
		vtk:		string;				# root tk name
		e:		ref Exp;
		val:		string;				# value displayed on screen
		canwalk:	int;				# can the variable be expanded?
		kids:		cyclic array of ref Datum;	# list of expanded kids

		expand:		fn(d: self ref Datum, okids: array of ref Datum, who: string): ref Datum;
		contract:	fn(d: self ref Datum, who: string): ref Datum;
		destroy:	fn(d: self ref Datum);
		showsrc:	fn(d: self ref Datum);
	};

	Vars: adt
	{
		tk:		string;				# root tk widget
		xbar:		int;				# x coord of var/val dividing line
		d:		array of ref Datum;		# displayed variables

		create:		fn(): ref Vars;
		delete:		fn(v: self ref Vars);
		show:		fn(v: self ref Vars);
		refresh:	fn(v: self ref Vars, e: array of ref Debug->Exp);

		expand:		fn(v: self ref Vars, kid: string);
		contract:	fn(v: self ref Vars, kid: string);
		showsrc:	fn(v: self ref Vars, kid: string);
		update:		fn(v: self ref Vars);
		scrolly:	fn(v: self ref Vars, s: string);
	};

	ctl:		fn(s: string);
	wmctl:	fn(s: string);
	init:		fn(ctxt: ref Draw->Context, geom: string,
				debsrc: DebSrc,
				str: String, debug: Debug):
			(ref Tk->Toplevel, chan of string, chan of string);
	raisex:	fn();
};
