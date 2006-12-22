Srvbrowse: module
{
	PATH:	con "/dis/grid/lib/srvbrowse.dis";

	services : list of ref Registries->Service;

	init : fn ();
	refreshservices : fn (filter: list of list of (string, string));
	servicepath2Service : fn (path, qid: string): list of ref Registries->Service;
	servicepath2Dir : fn (path: string, qid: int): (array of ref sys->Dir, int);
	getresname : fn (srvc: ref Registries->Service): (string, string);
	getqid : fn (srvc: ref Registries->Service): string;
	find : fn (filter: list of list of (string, string)): list of ref Registries->Service;
	addservice: fn (srvc: ref Registries->Service);
	searchwin: fn (ctxt: ref Draw->Context, chanout: chan of string, filter: list of list of (string, string));
};