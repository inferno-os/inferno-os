Tcl_Core: module {

	PATH : con "/dis/lib/tcl_core.dis";
	TclData : adt {
		context : ref Draw->Context;
		top : ref Tk->Toplevel;
		lines : chan of string;
		debug : int;
	};

	init:	fn(ctxt: ref Draw->Context, argv: list of string);
	grab_lines : fn(new_inp,unfin : string, lines: chan of string);
	prepass :  fn(line : string) : string;
	evalcmd : fn(line : string,termchar : int) : string;
	clear_error : fn();
	set_top : fn(win:ref Tk->Toplevel);
	finished : fn(s : string,termchar : int) : int;
	notify : fn(num : int, s: string) : string;
};
