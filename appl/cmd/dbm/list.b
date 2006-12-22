implement Dbmlist;

include "sys.m";
	sys: Sys;

include "draw.m";

include "dbm.m";
	dbm: Dbm;
	Datum, Dbf: import dbm;

Dbmlist: module
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
		sys->fprint(sys->fildes(2), "dbm/list: %s: %r\n", hd args);
		raise "fail:open";
	}
	for(key := db.firstkey(); key != nil; key = db.nextkey(key)){
		d := db.fetch(key);
		sys->print("%s	%s\n", string key, string d);
	}
}
