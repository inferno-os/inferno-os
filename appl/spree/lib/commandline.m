Commandline: module {
	init:			fn();

	PATH:		con "/dis/spree/lib/commandline.dis";
	Cmdline: adt {
		new:			fn(win: ref Tk->Toplevel, w, textopts: string): (ref Cmdline, chan of string);
		event:		fn(cmdl: self ref Cmdline, e: string): list of string;
		tagaddtext:	fn(cmdl: self ref Cmdline, t: list of (string, string));
		addtext:		fn(cmdl: self ref Cmdline, txt: string);
		focus:		fn(cmdl: self ref Cmdline);
		maketag:		fn(cmdl: self ref Cmdline, name, options: string);

		w: string;
		top: ref Tk->Toplevel;
	};
};
