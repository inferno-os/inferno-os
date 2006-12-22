implement Genfield;

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;
	IPint: import kr;

Genfield: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Field: con 65537;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;

	f := IPint.inttoip(Field);
	fm2 := f.sub(IPint.inttoip(2));
	for(i := 1; i <= Field; i++){
		x := IPint.inttoip(i);
		y := x.expmod(fm2, f);
#		sys->print("%s\n", x.mul(y).expmod(IPint.inttoip(1), f).iptostr(10));
		sys->print("%d,\n", y.iptoint());
	}
}
