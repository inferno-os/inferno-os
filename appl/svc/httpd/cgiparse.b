implement CgiParse;

include "sys.m";
	sys: Sys;
include "draw.m";
include "string.m";
	str: String;
include "bufio.m";
include "daytime.m";
	daytime : Daytime;
include "parser.m";
	parser : Parser;
include "contents.m";
include "cache.m";
include "httpd.m";
	Private_info: import Httpd;
include "cgiparse.m";

stderr : ref Sys->FD;

cgiparse(g: ref Private_info, req: Httpd->Request): ref CgiData
{
	ret: ref CgiData;
	(ok, err) := loadmodules();
	if(ok == -1) {
		sys->fprint(stderr, "CgiParse: %s\n", err );
		return nil;
	}

	(ok, err, ret) = parse(g, req);

	if(ok < 0){
		sys->fprint( stderr, "CgiParse: %s\n", err );
		return nil;
	}
	return ret;
}

badmod(p: string): (int, string)
{
	return (-1, sys->sprint("cannot load %s: %r", p));
}

loadmodules(): (int, string)
{
	if( sys == nil )
		sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	if(daytime == nil)
		daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		return badmod(Daytime->PATH);
	if(str == nil)
		str = load String String->PATH;
	if(str == nil)
		return badmod(String->PATH);
	if( parser == nil )
		parser = load Parser Parser->PATH;
	if( parser == nil )
		return badmod(Parser->PATH);
	return (0, nil);
}

parse(g: ref Private_info, req: Httpd->Request) : (int, string, ref CgiData)
{
	bufio := g.bufio;
	Iobuf: import bufio;
	
	host, remote, referer, httphd : string;
	form: list of (string, string);
	
	tmstamp := daytime->time();

	(method, version, uri, search) := (req.method, req.version, req.uri, req.search);
	
	if(version != ""){
		if( g.version == nil )
			return (-1, "version unknown.", nil);
		if( g.bout == nil )
			return (-1, "internal error, g.bout is nil.", nil);
		if( g.bin == nil )
			return (-1, "internal error, g.bin is nil.", nil);
		httphd = g.version + " 200 OK\r\n" +
			"Server: Inferno-Httpd\r\n" +
			"MIME-version: 1.0\r\n" +
			"Date: " + tmstamp + "\r\n" +
			"Content-type: text/html\r\n" +
			"\r\n";
	}
	
	hstr := "";
	lastnl := 1;
	eof := 0;
	while((c := g.bin.getc()) != bufio->EOF ) {	
		if (c == '\r' ) {	
			hstr[len hstr] = c;
			c = g.bin.getb();
			if( c == bufio->EOF ){
				eof = 1;
				break;
			}
		}
		hstr[len hstr] = c;
		if(c == '\n' ){	
			if( lastnl )
				break;
			lastnl = 1;
		}
		else
			lastnl = 0;
	}
	host = g.host;
	remote = g.remotesys;
	referer = g.referer;
	(cnt, header) := parseheader( hstr );
	method = str->toupper( method);
	if (method  == "POST") {	
		s := "";
		while(!eof && cnt && (c = g.bin.getc()) != '\n' ) {	
			s[len s] = c;
			cnt--;
			if( c == '\r' )
				eof = 1;
		}
		form = parsequery(s);
	}
	for (ql := parsequery(req.search); ql != nil; ql = tl ql)
		form = hd ql :: form;
	return (0, nil, 
		ref CgiData(method, version, uri, search, tmstamp, host, remote, referer,
		httphd, header, form));
}

parseheader(hstr: string): (int, list of (string, string))
{
	header : list of (string, string);
	cnt := 0;
	if( hstr == nil || len hstr == 0 )
		return (0, nil);
	(n, sl) := sys->tokenize( hstr, "\r\n" );
	if( n <= 0 )
		return (0, nil);
	while( sl != nil ){
		s := hd sl;
		sl = tl sl;
		for( i := 0; i < len s; i++ ){	
				if( s[i] == ':' ){
				tag := s[0:i+1];
				val := s[i+1:];
				if( val[len val - 1] == '\r' )
					val[len val - 1] = ' ';
				if( val[len val - 1] == '\n' )
					val[len val - 1] = ' ';
				header = (tag, val) :: header;
				if(str->tolower( tag ) == "content-length:" ){
					if( val != nil && len val > 0 )
						cnt = int val;
					else
						cnt = 0;
				}
				break;
			}
		}
	}
	return (cnt, listrev( header ));
}

listrev(s: list of (string, string)): list of (string, string)
{
	    tmp : list of (string, string);
	    while( s != nil ) {
		tmp = hd s :: tmp;
		s = tl s;
	    }
	    return tmp;
}

getbaseip() : string
{
	buf : array of byte;
	fd := sys->open( "/net/bootp", Sys->OREAD );
	if( fd != nil ){
		(n, d) := sys->fstat( fd );
		if( n >= 0 ){
			if(int d.length > 0 )
				buf = array [int d.length] of byte;
			else
				buf = array [128] of byte;
			n = sys->read( fd, buf, len buf );
			if( n > 0 ){
				(nil, sl) := sys->tokenize( string buf[0:n], " \t\n" );
				while( sl != nil ){
					if( hd sl == "ipaddr" ){
						sl = tl sl;
						break;
					}
					sl = tl sl;
				}
				if( sl != nil )
					return "http://" + (hd sl);
			}
		}
	}
	return "http://beast2";
}

getbase() : string
{
	fd := sys->open( "/dev/sysname", Sys->OREAD );
	if( fd != nil ){
		buf := array [128] of byte;
		n := sys->read( fd, buf, len buf );
		if( n > 0 )
			return "http://" + string buf[0:n];
	}
	return "http://beast2";
}

gethost() : string
{
	fd := sys->open( "/dev/sysname", Sys->OREAD );
	if(fd != nil) {
		buf := array [128] of byte;
		n := sys->read( fd, buf, len buf );
		if( n > 0 )
			return string buf[0:n];
	}
	return "none";
}

# parse a search string of the form
# tag=val&tag1=val1...
parsequery(search : string): list of (string, string)
{
	q: list of (string, string);
	tag, val : string;
	if (contains(search, '?'))
		(nil,search) = str->splitr(search,"?");
	while(search!=nil){
		(tag,search) = str->splitl(search,"=");
		if (search != nil) {
			search=search[1:];
			(val,search) = str->splitl(search,"&");
			if (search!=nil)
				search=search[1:];
			q = (parser->urlunesc(tag), parser->urlunesc(val)) :: q;
		}
	}
	return q;
}

contains(s: string, c: int): int
{
	for (i := 0; i < len s; i++)
		if (s[i] == c)
			return 1;
	return 0;
}
