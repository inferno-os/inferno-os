implement MathCalc;

include "sys.m";
	sys: Sys;

include "draw.m";

include "tk.m";
	tk: Tk;

include "bufio.m";
	bufmod : Bufio;
Iobuf : import bufmod;

include "../lib/tcl.m";

include "tcllib.m";


MathCalc : module 
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

CALCPATH: con "/dis/lib/tcl_calc.dis";

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	cal := load TclLib CALCPATH;
	if (cal==nil){
		sys->print("mathcalc: can't load %s: %r\n", CALCPATH);
		exit;
	}
	bufmod = load Bufio Bufio->PATH;
	if (bufmod==nil){
		sys->print("bufmod load %r\n");
		exit;
	}
	iob := bufmod->fopen(sys->fildes(0),bufmod->OREAD);
	if (iob==nil){
		sys->print("mathcalc: cannot open stdin for reading: %r\n");
		return;
	}
	input : string;
	new_inp := "calc%";
	sys->print("%s ", new_inp);
	while((input=iob.gets('\n'))!=nil){
		input=input[0:len input -1];
		if (input=="quit")
			exit;
		arr:=array[] of {input};
		(i,msg):=cal->exec(nil,arr);
		if (msg!=nil)
			sys->print("%s\n",msg);
		sys->print("%s ", new_inp);
	}
	
}


# expr0 : expr1
#	| expr0 '+' expr0
#	| expr0 '-' expr0
#	;
#
# expr1 : expr2
#	| expr1 '*' expr1
#	| expr1 '/' expr1
#	;
#
# expr2 : '-' expr2
#	| '+' expr2
#	| expr3
#	;
#
# expr3 : INT
#	| REAL
#	;
