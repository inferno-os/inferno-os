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
	return "rr*-a-o";
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
		opts: list of (int, list of ref Alphabet->Value),
		args: list of ref Alphabet->Value): ref Alphabet->Value
{
	stop := -1;
	for(; opts != nil; opts = tl opts){
		case (hd opts).t0 {
		'a' =>
			stop = 0;
		'o' =>
			stop = 1;
		}
	}
	spawn seqproc(r := chan of string, args, stop);
	return ref Value.Vr(r);
}

seqproc(r: chan of string, args: list of ref Alphabet->Value, stop: int)
{
	status := "";
	if(<-r == nil){
pid := sys->pctl(0, nil);
sys->print("%d. seq %d args\n", pid, len args);
		for(; args != nil; args = tl args){
			sr := (hd args).r().i;
sys->print("%d. started\n", pid);
			sr <-= nil;
			status = <-sr;
sys->print("%d. got status\n", pid);
			if((status == nil) == stop)
				break;
		}
	}else
		r = nil;
	for(; args != nil; args = tl args)
		(hd args).r().i <-= "die!";
	if(r != nil)
		r <-= status;
}
