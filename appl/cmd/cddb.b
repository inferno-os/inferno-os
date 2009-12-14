implement Cddb;

# this is a near transliteration of Plan 9 source, and subject to the Lucent Public License 1.02

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "string.m";
	str: String;

include "dial.m";
	dial: Dial;

include "arg.m";

Cddb: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

server := "freedb.freedb.org";
debug := 0;
tflag := 0;
Tflag := 0;

Track: adt {
	n:	int;
	title:	string;
};

Toc: adt {
	diskid:	int;
	ntrack:	int;
	title:	string;
	track:	array of Track;
};

DPRINT(fd: int, s: string)
{
	if(debug)
		sys->fprint(sys->fildes(fd), "%s", s);
}

dumpcddb(t: ref Toc)
{
	sys->print("title	%s\n", t.title);
	for(i:=0; i<t.ntrack; i++){
		if(tflag){
			n := t.track[i+1].n;
			if(i == t.ntrack-1)
				n *= 75;
			s := (n - t.track[i].n)/75;
			sys->print("%d\t%s\t%d:%2.2d\n", i+1, t.track[i].title, s/60, s%60);
		}
		else
			sys->print("%d\t%s\n", i+1, t.track[i].title);
	}
	if(Tflag){
		s := t.track[i].n;
		sys->print("Total time: %d:%2.2d\n", s/60, s%60);
	}
}

cddbfilltoc(t: ref Toc): int
{
	conn := dial->dial(dial->netmkaddr(server, "tcp", "888"), nil);
	if(conn == nil){
		sys->fprint(sys->fildes(2), "cddb: cannot dial %s: %r\n", server);
		return -1;
	}
	bin := bufio->fopen(conn.dfd, Bufio->OREAD);

	if((p:=getline(bin)) == nil || atoi(p)/100 != 2)
		return died(p);

	sys->fprint(conn.dfd, "cddb hello gre plan9 9cd 1.0\r\n");
	if((p = getline(bin)) == nil || atoi(p)/100 != 2)
		return died(p);

	#
	#	Protocol level 6 is the same as level 5 except that
	#	the character set is now UTF-8 instead of ISO-8859-1. 
	#
	sys->fprint(conn.dfd, "proto 6\r\n");
	if((p = getline(bin)) == nil || atoi(p)/100 != 2)
		return died(p);
	DPRINT(2, sys->sprint("%s\n", p));

	sys->fprint(conn.dfd, "cddb query %8.8ux %d", t.diskid, t.ntrack);
	DPRINT(2, sys->sprint("cddb query %8.8ux %d", t.diskid, t.ntrack));
	for(i:=0; i<t.ntrack; i++) {
		sys->fprint(conn.dfd, " %d", t.track[i].n);
		DPRINT(2, sys->sprint(" %d", t.track[i].n));
	}
	sys->fprint(conn.dfd, " %d\r\n", t.track[t.ntrack].n);
	DPRINT(2, sys->sprint(" %d\r\n", t.track[t.ntrack].n));

	if((p = getline(bin)) == nil || atoi(p)/100 != 2)
		return died(p);
	DPRINT(2, sys->sprint("cddb: %s\n", p));
	(nf, fl) := sys->tokenize(p, " \t\n\r");
	if(nf < 1)
		return died(p);

	categ, id: string;
	case atoi(hd fl) {
	200 =>	# exact match
		if(nf < 3)
			return died(p);
		categ = hd tl fl;
		id = hd tl tl fl;
	210 or	# exact matches
	211 =>	# close matches
		if((p = getline(bin)) == nil)
			return died(nil);
		if(p[0] == '.')	# no close matches?
			return died(nil);

		# accept first match
		(nsf, f) := sys->tokenize(p, " \t\n\r");
		if(nsf < 2)
			return died(p);
		categ = hd f;
		id = hd tl f;

		# snarf rest of buffer
		while(p[0] != '.') {
			if((p = getline(bin)) == nil)
				return died(p);
			DPRINT(2, sys->sprint("cddb: %s\n", p));
		}
	202 or	# no match
	* =>
		return died(p);
	}

	t.title = "";
	for(i=0; i<t.ntrack; i++)
		t.track[i].title = "";

	# fetch results for this cd
	sys->fprint(conn.dfd, "cddb read %s %s\r\n", categ, id);
	do {
		if((p = getline(bin)) == nil)
			return died(nil);
DPRINT(2, sys->sprint("cddb %s\n", p));
		if(len p >= 7 && p[0:7] == "DTITLE=")
			t.title += p[7:];
		else if(len p >= 7 && p[0:6] == "TTITLE"&& isdigit(p[6])) {
			i = atoi(p[6:]);
			if(i < t.ntrack) {
				p = p[6:];
				while(p != nil && isdigit(p[0]))
					p = p[1:];
				if(p != nil && p[0] == '=')
					p = p[1:];
				t.track[i].title += p;
			}
		} 
	} while(p[0] != '.');

	sys->fprint(conn.dfd, "quit\r\n");

	return 0;
}

getline(f: ref Iobuf): string
{
	p := f.gets('\n');
	while(p != nil && isspace(p[len p-1]))
		p = p[0: len p-1];
	return p;
}

isdigit(c: int): int
{
	return c>='0' && c <= '9';
}

isspace(c: int): int
{
	return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

died(p: string): int
{
	sys->fprint(sys->fildes(2), "cddb: error talking to server\n");
	if(p != nil){
		p = p[0:len p-1];
		sys->fprint(sys->fildes(2), "cddb: server says: %s\n", p);
	}
	return -1;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;
	dial = load Dial Dial->PATH;

	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("cddb [-DTt] [-s server] query diskid n ...");
	while((o := arg->opt()) != 0)
	case o {
	'D' =>	debug = 1;
	's' =>	server = arg->earg();
	'T' =>	Tflag = 1; tflag = 1;
	't' =>	tflag = 1;
	* =>	arg->usage();
	}
	args = arg->argv();
	argc := len args;
	if(argc < 3 || hd args != "query")
		arg->usage();
	arg = nil;

	ntrack := atoi(hd tl tl args);
	toc := ref Toc(str->toint(hd tl args, 16).t0, ntrack, nil, array[ntrack+1] of Track);
	if(argc != 3+toc.ntrack+1){
		sys->fprint(sys->fildes(2), "cddb: argument count does not match given ntrack");
		raise "fail:error";
	}
	args = tl tl tl args;

	for(i:=0; i<=toc.ntrack; i++){	# <=?
		toc.track[i].n = atoi(hd args);
		args = tl args;
	}

	if(cddbfilltoc(toc) < 0)
		raise "fail:whoops";

	dumpcddb(toc);
}

atoi(s: string): int
{
	return int s;
}
