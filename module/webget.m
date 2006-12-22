Webget: module
{
	PATH: con "/dis/svc/webget/webget.dis";

	init: fn(ctxt: ref Draw->Context, argv: list of string);
	start: fn(ctl: chan of int);
};
