implement Dbmfetch;

include "sys.m";
	sys: Sys;

include "draw.m";

include "dbm.m";
	dbm: Dbm;
	Datum, Dbf: import dbm;

Dbmfetch: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	dbm = load Dbm Dbm->PATH;

	dbm->init();

	args = tl args;
	db := Dbf.open(hd args, Sys->OREAD);
	if(db == nil){
		sys->fprint(sys->fildes(2), "dbm/fetch: %s: %r\n", hd args);
		raise "fail:open";
	}
	args = tl args;
	key := hd args;
	data := db.fetch(array of byte key);
	if(data == nil)
		sys->fprint(sys->fildes(2), "not found\n");
	else
		sys->write(sys->fildes(1), data, len data);
}
