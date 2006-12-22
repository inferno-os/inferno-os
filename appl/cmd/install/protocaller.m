Protocaller : module{
	init: fn(ctxt : ref Draw->Context, args : list of string);
	protofile: fn(new : string, old : string, d : ref Sys->Dir);

	WARN, ERROR, FATAL : con iota;

	protoerr: fn(lev : int, line : int, err : string);
};