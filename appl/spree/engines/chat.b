implement Engine;

include "sys.m";
	sys: Sys;
include "draw.m";
include "../spree.m";
	spree: Spree;
	Attributes, Range, Object, Clique, Member: import spree;

clique: ref Clique;

clienttype(): string
{
	return "chat";
}

init(g: ref Clique, srvmod: Spree): string
{
	sys = load Sys Sys->PATH;
	clique = g;
	spree = srvmod;
	return nil;
}

join(nil: ref Member): string
{
	return nil;
}

leave(nil: ref Member)
{
}

Eusage: con "bad command usage";

command(member: ref Member, cmd: string): string
{
	e := ref Sys->Exception;
	if (sys->rescue("parse:*", e) == Sys->EXCEPTION) {
		sys->rescued(Sys->ONCE, nil);
		return e.name[6:];
	}
	(n, toks) := sys->tokenize(cmd, " \n");
	assert(n > 0, "unknown command");
	case hd toks {
	"say" =>
		# say something
		assert(n == 2, Eusage);
		clique.action("say " + string member.id + " " + hd tl toks, nil, nil, ~0);
	* =>
		assert(0, "bad command");
	}
	return nil;
}

assert(b: int, err: string)
{
	if (b == 0)
		sys->raise("parse:" + err);
}
