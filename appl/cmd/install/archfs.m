Archfs : module
{
	PATH : con "/dis/install/archfs.dis";

	init : fn(ctxt : ref Draw->Context, args : list of string);
	initc : fn(args : list of string, c : chan of int);
};
