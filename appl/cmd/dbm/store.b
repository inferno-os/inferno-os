implement Dbmstore;

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "dbm.m";
	dbm: Dbm;
	Datum, Dbf: import dbm;

Dbmstore: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	dbm = load Dbm Dbm->PATH;
	bufio = load Bufio Bufio->PATH;

	dbm->init();

	args = tl args;
	db := Dbf.open(hd args, Sys->ORDWR);
	if(db == nil){
		sys->fprint(sys->fildes(2), "dbm/store: %s: %r\n", hd args);
		raise "fail:open";
	}
	args = tl args;
	if(args == nil){
		err := 0;
		f := bufio->fopen(sys->fildes(0), Bufio->OREAD);
		while((s := f.gets('\n')) != nil){
			s = s[0:len s-1];
			key: string;
			for(i :=0; i < len s; i++)
				if(s[i] == ' ' || s[i] == '\t'){
					key = s[0:i];
					s = s[i+1:];
					break;
				}
			if(key == nil){
				sys->fprint(sys->fildes(2), "dbm/store: bad input\n");
				raise "fail:error";
			}
			if(store(db, key, s))
				err = 1;
		}
		if(err)
			raise "fail:store";
	}else if(store(db, hd args, hd tl args))
		raise "fail:store";
}

store(db: ref Dbf, key: string, dat: string): int
{
	r := db.store(array of byte key, array of byte dat, 0);
	if(r < 0)
		sys->fprint(sys->fildes(2), "bad store\n");
	else if(r)
		sys->fprint(sys->fildes(2), "%q exists\n", key);
	return r;
}
