implement Dbmdelete;

include "sys.m";
	sys: Sys;

include "draw.m";

include "dbm.m";
	dbm: Dbm;
	Datum, Dbf: import dbm;

Dbmdelete: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	dbm = load Dbm Dbm->PATH;

	dbm->init();

	args = tl args;
	db := Dbf.open(hd args, Sys->ORDWR);
	if(db == nil){
		sys->fprint(sys->fildes(2), "dbm/delete: %s: %r\n", hd args);
		raise "fail:open";
	}
	args = tl args;
	key := hd args;
	if(db.delete(array of byte key) < 0)
		sys->fprint(sys->fildes(2), "not found\n");
}
