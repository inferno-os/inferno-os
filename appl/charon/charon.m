Charon : module
{
	PATH: con "/dis/charon.dis";

	Context: adt {
		ctxt: ref Draw->Context;
		args: list of string;
		c: chan of string;
		cksrv: Cookiesrv;
		ckclient: ref Cookiesrv->Client;
	};

	init: fn(ctxt: ref Draw->Context, argv: list of string);
	initc: fn(ctxt: ref Context);
	histinfo: fn(): (int, string, string, string);
	startcharon: fn(url: string, c: chan of string);
	hasopener: fn(): int;
	sendopener: fn(s: string);
	gettop: fn(): ref Layout->Frame;
};
