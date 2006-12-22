Httpd: module {
	Entity: adt{
		 name : string;
		 value : int;
	};
	
	Internal, TempFail, Unimp, UnkVers, BadCont, BadReq, Syntax, 
	BadSearch, NotFound, NoSearch , OnlySearch, Unauth, OK : con iota;	
	
	SVR_ROOT : con "/services/httpd/root/";
	HTTPLOG : con "/services/httpd/httpd.log";
	DEBUGLOG : con "/services/httpd/httpd.debug";
	HTTP_SUFF : con "/services/httpd/httpd.suff";
	REWRITE   : con "/services/httpd/httpd.rewrite";
	MAGICPATH : con "/dis/svc/httpd/"; # must end in /
	
	Private_info : adt{
		# used in parse and httpd
		bufio: Bufio;
		bin,bout : ref Bufio->Iobuf;
		logfile,dbg_log : ref Sys->FD;
		cache : Cache;
		eof : int;
		getcerr : string;
		version : string;
		okencode, oktype : list of ref Contents->Content;
		host : string; # initialized to mydomain just 	
			       # before parsing header
		remotesys, referer : string;
		modtime : int;
		# used by /magic for reading body
		clength : int;
		ctype : string;
		#only used in parse
		wordval : string;
		tok,parse_eof : int;
		mydomain,client : string;
		entity: array of Entity; 
		oklang : list of ref Contents->Content;
	};
	Request: adt {
		method, version, uri, search: string;
	};
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

Cgi: module{
	init: fn(g: ref Httpd->Private_info, req: Httpd->Request);
};
