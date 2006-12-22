implement Query;

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";

include "attrdb.m";
	attrdb: Attrdb;
	Attr, Tuples, Dbentry, Db: import attrdb;

include "arg.m";

Query: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

usage()
{
	sys->fprint(sys->fildes(2), "usage: query attr [value [rattr]]\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	dbfile := "/lib/ndb/local";
	arg := load Arg Arg->PATH;
	if(arg == nil)
		badload(Arg->PATH);
	arg->init(args);
	arg->setusage("query [-a] [-f dbfile] attr [value [rattr]]");
	all := 0;
	while((o := arg->opt()) != 0)
		case o {
		'f' =>	dbfile = arg->earg();
		'a' => all = 1;
		* =>	arg->usage();
		}
	args = arg->argv();
	if(args == nil)
		arg->usage();
	attr := hd args;
	args = tl args;
	value, rattr: string;
	vflag := 0;
	if(args != nil){
		vflag = 1;
		value = hd args;
		args = tl args;
		if(args != nil)
			rattr = hd args;
	}
	arg = nil;

	attrdb = load Attrdb Attrdb->PATH;
	if(attrdb == nil)
		badload(Attrdb->PATH);
	err := attrdb->init();
	if(err != nil)
		error(sys->sprint("can't init Attrdb: %s", err));

	db := Db.open(dbfile);
	if(db == nil)
		error(sys->sprint("can't open %s: %r", dbfile));
	ptr: ref Attrdb->Dbptr;
	for(;;){
		e: ref Dbentry;
		if(rattr != nil)
			(e, ptr) = db.findbyattr(ptr, attr, value, rattr);
		else if(vflag)
			(e, ptr) = db.findpair(ptr, attr, value);
		else
			(e, ptr) = db.find(ptr, attr);
		if(e == nil)
			break;
		if(rattr != nil){
			matches: list of (ref Tuples, list of ref Attr);
			if(rattr != nil)
				matches = e.findbyattr(attr, value, rattr);
			else
				matches = e.find(attr);
			for(; matches != nil; matches = tl matches){
				(line, attrs) := hd matches;
				if(attrs != nil)
					printvals(attrs, all);
				if(!all)
					exit;
			}
		}else
			printentry(e);
		if(!all)
			exit;
	}
}

badload(s: string)
{
	error(sys->sprint("can't load %s: %r", s));
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "query: %s\n", s);
	raise "fail:error";
}

printentry(e: ref Dbentry)
{
	s := "";
	for(lines := e.lines; lines != nil; lines = tl lines){
		line := hd lines;
		for(al := line.pairs; al != nil; al = tl al){
			a := hd al;
			s += sys->sprint(" %q=%q", a.attr, a.val);
		}
	}
	if(s != "")
		s = s[1:];
	sys->print("%s\n", s);
}

printvals(al: list of ref Attr, all: int)
{
	for(; al != nil; al = tl al){
		a := hd al;
		sys->print("%q\n", a.val);
		if(!all)
			break;
	}
}
