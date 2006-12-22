implement Tclsh;

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufmod : Bufio;
Iobuf : import bufmod;

include "tk.m";

include "../lib/tcl.m";
	tcl : Tcl_Core;

Tclsh: module {
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(ctxt: ref Draw->Context, argv : list of string){
	sys=load Sys Sys->PATH;
	tcl=load Tcl_Core Tcl_Core->PATH;
	if (tcl==nil){
		sys->print("Cannot load Tcl (%r)\n");
		exit;
	}	
	bufmod=load Bufio Bufio->PATH;
	if (bufmod==nil){
		sys->print("Cannot load Bufio (%r)\n");
		exit;
	}	
	lines:=chan of string;
	tcl->init(ctxt,argv);
	new_inp := "tcl%";
	spawn tcl->grab_lines(nil,nil,lines);
	for(;;){
		alt{
			line := <-lines =>
				line = tcl->prepass(line);
				msg:= tcl->evalcmd(line,0);
				if (msg!=nil)
					sys->print("%s\n",msg);
				sys->print("%s ", new_inp);
				tcl->clear_error();
		}
	}
}
