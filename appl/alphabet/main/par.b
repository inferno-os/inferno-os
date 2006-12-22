implement Seq, Mainmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
include "alphabet.m";
	alphabet: Alphabet;
		Value: import alphabet;

Seq: module {};

typesig(): string
{
	return "rr*";
}

init()
{
	sys = load Sys Sys->PATH;
	alphabet = load Alphabet Alphabet->PATH;
}

quit()
{
}

run(nil: ref Draw->Context, nil: ref Reports->Report, nil: chan of string,
		nil: list of (int, list of ref Alphabet->Value),
		args: list of ref Alphabet->Value): ref Alphabet->Value
{
	spawn parproc(r := chan of string, args);
	return ref Value.Vr(r);
}

parproc(r: chan of string, args: list of ref Alphabet->Value)
{
	if(<-r != nil){
		for(; args != nil; args = tl args)
			(hd args).r().i <-= "die!";
	}else{
		status := "";
		for(a := args; a != nil; a = tl a)
			(hd a).r().i <-= nil;
		for(; args != nil; args = tl args)
			if((e := <-(hd args).r().i) != nil)
				status = e;
		r <-= status;
	}
}
