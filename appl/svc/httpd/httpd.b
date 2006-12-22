implement Httpd;

include "sys.m";
	sys: Sys;

Dir: import sys;
FD : import sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "string.m";
	str: String;

include "readdir.m";
	readdir: Readdir;

include "daytime.m";
	daytime : Daytime;

include "cache.m";
	cache : Cache;

include "contents.m";
	contents: Contents;
	Content: import contents;

include "httpd.m";

include "parser.m";
	parser : Parser;

include "date.m";
	date: Date;

include "redirect.m";
	redir: Redirect;

include "alarms.m";
	alarms: Alarms;
	Alarm: import alarms;

# globals 

cache_size: int;
port := "80";
addr: string;
stderr : ref FD;
dbg_log, logfile: ref FD;
debug: int;
my_domain: string;

usage()
{
	sys->fprint(stderr, "usage: httpd [-c num] [-D] [-a servaddr]\n");
	raise "fail:usage";
}

atexit(g: ref Private_info)
{
	debug_print(g,"At exit from httpd, closing fds. \n");
	g.bin.close();	
	g.bout.close();
	g.bin=nil;
	g.bout=nil;
	exit;
}

debug_print(g : ref Private_info,message : string)
{
	if (g.dbg_log!=nil)
		sys->fprint(g.dbg_log,"%s",message);
}

parse_args(args : list of string)
{
	while(args!=nil){
		case (hd args){
			"-c" =>
				args = tl args;
				cache_size = int hd args;
			"-D" =>
				debug=1;
			"-p" =>
				args = tl args;
				port = hd args;
			"-a" =>
				args = tl args;
				addr = hd args;
		}
		args = tl args;
	}
}

badmod(m: string)
{
	sys->fprint(stderr, "httpd: cannot load %s: %r\n", m);
	raise "fail:bad module";
}

init(nil: ref Draw->Context, argv: list of string)
{	
	# Load global modules.
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	bufio = load Bufio Bufio->PATH;	
	if (bufio==nil) badmod(Bufio->PATH);

	str = load String String->PATH;
	if (str == nil) badmod(String->PATH);

	date = load Date Date->PATH;
	if(date == nil) badmod(Date->PATH);

	readdir = load Readdir Readdir->PATH;
	if(readdir == nil) badmod(Readdir->PATH);

	daytime = load Daytime Daytime->PATH;
	if(daytime == nil) badmod(Daytime->PATH);

	contents = load Contents Contents->PATH;
	if(contents == nil) badmod(Contents->PATH);

	cache = load Cache Cache->PATH;
	if(cache == nil) badmod(Cache->PATH);

	alarms = load Alarms Alarms->PATH;
	if(alarms == nil) badmod(Alarms->PATH);

	redir = load Redirect Redirect->PATH;
	if(redir == nil) badmod(Redirect->PATH);

	parser = load Parser Parser->PATH;
	if(parser == nil) badmod(Parser->PATH);

	logfile=sys->create(HTTPLOG,Sys->ORDWR,8r666);
	if (logfile==nil) {
		sys->fprint(stderr, "httpd: cannot open %s: %r\n", HTTPLOG);
		raise "cannot open http log";
	}

	# parse arguments to httpd.

	cache_size=5000;
	debug = 0;
	parse_args(argv);
	if (debug==1){
		dbg_log=sys->create(DEBUGLOG,Sys->ORDWR,8r666);
		if (dbg_log==nil){
			sys->print("debug log open: %r\n");
			exit;
		}
	}else 
		dbg_log=nil;
	sys->fprint(dbg_log,"started at %s \n",daytime->time());

	# initialisation routines
	contents->contentinit(dbg_log);
	cache->cache_init(dbg_log,cache_size);
	redir->redirect_init(REWRITE);
	date->init();
	parser->init();
	my_domain=sysname();
	if(addr == nil){
		if(port != nil)
			addr = "tcp!*!"+port;
		else
			addr = "tcp!*!80";
	}
	(ok, c) := sys->announce(addr);
	if(ok < 0) {
		sys->fprint(stderr, "can't announce %s: %r\n", addr);
		exit;
	}
	sys->fprint(logfile,"************ Charon Awakened at %s\n",
			daytime->time());
	for(;;)
		doit(c);
	exit;
}


doit(c: Sys->Connection)
{
	(ok, nc) := sys->listen(c);
	if(ok < 0) {
		sys->fprint(stderr, "listen: %r\n");
		exit;
	}
	if (dbg_log!=nil)
		sys->fprint(dbg_log,"spawning connection.\n");
	spawn service_req(nc);
}

service_req(nc : Sys->Connection)
{
	buf := array[64] of byte;
	l := sys->open(nc.dir+"/remote", sys->OREAD);
	n := sys->read(l, buf, len buf);
	if(n >= 0)
		if (dbg_log!=nil)
			sys->fprint(dbg_log,"New client http: %s %s", nc.dir, 
							string buf[0:n]);
	#  wait for a call (or an error)
	#  start a process for the service
	g:= ref Private_info;
	g.bufio = bufio;
	g.dbg_log=dbg_log;
	g.logfile = logfile;
	g.modtime=0;
	g.entity = parser->initarray();
	g.mydomain = my_domain;
	g.version = "HTTP/1.0";
	g.cache = cache;
	g.okencode=nil;
	g.oktype=nil;
	g.getcerr="";
	g.parse_eof=0;
	g.eof=0;
	g.remotesys=getendpoints(nc.dir);
	debug_print(g,"opening in for "+string buf[0:n]+"\n");
	g.bin= bufio->open(nc.dir+"/data",bufio->OREAD);
	if (g.bin==nil){
		sys->print("bin open: %r\n");
		exit;
	}
	debug_print(g,"opening out for "+string buf[0:n]+"\n");
	g.bout= bufio->open(nc.dir+"/data",bufio->OWRITE);
	if (g.bout==nil){
		sys->print("bout open: %r\n");
		exit;
	}
	debug_print(g,"calling parsereq for "+string buf[0:n]+"\n");
	parsereq(g);
	atexit(g);
}

parsereq(g: ref Private_info)
{
	meth, v,magic,search,uri,origuri,extra : string;
	# 15 minutes to get request line
	a := Alarm.alarm(15*1000*60);
	meth = getword(g);
	if(meth == nil){
		parser->logit(g,sys->sprint("no method%s", g.getcerr));
		a.stop();
		parser->fail(g,Syntax,"");
	}
	uri = getword(g);
	if(uri == nil || len uri == 0){
		parser->logit(g,sys->sprint("no uri: %s%s", meth, g.getcerr));
		a.stop();
		parser->fail(g,Syntax,"");
	}
	v = getword(g);
	extra = getword(g);
	a.stop();
	if(extra != nil){
			parser->logit(g,sys->sprint(
				"extra header word '%s'%s", 
					extra, g.getcerr));
			parser->fail(g,Syntax,"");
	}
	case v {
		"" =>
			if(meth!="GET"){
				parser->logit(g,sys->sprint("unimplemented method %s%s", meth, g.getcerr));
				parser->fail(g,Unimp, meth);
			}
	
		"HTTP/V1.0" or "HTTP/1.0" or "HTTP/1.1" =>
			if((meth != "GET")  && (meth!= "HEAD") && (meth!="POST")){
				parser->logit(g,sys->sprint("unimplemented method %s", meth));
				parser->fail(g,Unimp, meth);
			}	
		* =>
			parser->logit(g,sys->sprint("method %s uri %s%s", meth, uri, g.getcerr));
			parser->fail(g,UnkVers, v);
	}

	# the fragment is not supposed to be sent
	# strip it because some clients send it

	(uri,extra) = str->splitl(uri, "#");
	if(extra != nil)
		parser->logit(g,sys->sprint("fragment %s", extra));
	
	 # munge uri for search, protection, and magic	 
	(uri, search) = stripsearch(uri);
	uri = compact_path(parser->urlunesc(uri));
#	if(uri == SVR_ROOT)
#		parser->fail(g,NotFound, "no object specified");
	(uri, magic) = stripmagic(uri);
	debug_print(g,"stripmagic=("+uri+","+magic+")\n");

	 # normal case is just file transfer
	if(magic == nil || (magic == "httpd")){
		if (meth=="POST")
			parser->fail(g,Unimp,meth);	# /magic does handles POST
		g.host = g.mydomain;
		origuri = uri;
		parser->httpheaders(g,v);
		uri = redir->redirect(origuri);
		# must change this to implement proxies
		if(uri==nil){
			send(g,meth, v, origuri, search);
		}else{
			g.bout.puts(sys->sprint("%s 301 Moved Permanently\r\n", g.version));
			g.bout.puts(sys->sprint("Date: %s\r\n", daytime->time()));
			g.bout.puts("Server: Charon\r\n");
			g.bout.puts("MIME-version: 1.0\r\n");
			g.bout.puts("Content-type: text/html\r\n");
			g.bout.puts(sys->sprint("URI: <%s>\r\n",parser->urlconv(uri)));
			g.bout.puts(sys->sprint("Location: %s\r\n",parser->urlconv(uri)));
			g.bout.puts("\r\n");
			g.bout.puts("<head><title>Object Moved</title></head>\r\n");
			g.bout.puts("<body><h1>Object Moved</h1>\r\n");
			g.bout.puts(sys->sprint(
				"Your selection moved to <a href=\"%s\"> here</a>.<p></body>\r\n",
							 parser->urlconv(uri)));
			g.bout.flush();
		}
		atexit(g);
	}

	# for magic we init a new program
	do_magic(g,magic,uri,origuri,Request(meth, v, uri, search));
}

do_magic(g: ref Private_info,file, uri, origuri: string, req: Request)
{
	buf := sys->sprint("%s%s.dis", MAGICPATH, file);
	debug_print(g,"looking for "+buf+"\n");
	c:= load Cgi buf;
	if (c==nil){
		parser->logit(g,sys->sprint("no magic %s uri %s", file, uri));
		parser->fail(g,NotFound, origuri);
	}
	{
		c->init(g, req);
	}
	exception{
		"fail:*" =>
			return;
	}
}

send(g: ref Private_info,name, vers, uri, search : string)
{
	typ,enc : ref Content;
	w : string;
	n, bad, force301: int;
	if(search!=nil)
		parser->fail(g,NoSearch, uri);

	# figure out the type of file and send headers
	debug_print( g, "httpd->send->open(" + uri + ")\n" );
	fd := sys->open(uri, sys->OREAD);
	if(fd == nil){
		dbm := sys->sprint( "open failed: %r\n" );
		debug_print( g, dbm );
		notfound(g,uri);
	}
	(i,dir):=sys->fstat(fd);
	if(i< 0)
		parser->fail(g,Internal,"");
	if(dir.mode & Sys->DMDIR){
		(nil,p) := str->splitr(uri, "/");
		if(p == nil){
			w=sys->sprint("%sindex.html", uri);
			force301 = 0;
		}else{
			w=sys->sprint("%s/index.html", uri);
			force301 = 1; 
		}
		fd1 := sys->open(w, sys->OREAD);
		if(fd1 == nil){
			parser->logit(g,sys->sprint("%s directory %s", name, uri));
			if(g.modtime >= dir.mtime)
				parser->notmodified(g);
			senddir(g,vers, uri, fd, ref dir);
		} else if(force301 != 0 && vers != ""){
			g.bout.puts(sys->sprint("%s 301 Moved Permanently\r\n", g.version));
			g.bout.puts(sys->sprint("Date: %s\r\n", daytime->time()));
			g.bout.puts("Server: Charon\r\n");
			g.bout.puts("MIME-version: 1.0\r\n");
			g.bout.puts("Content-type: text/html\r\n");
			(nil, reluri) := str->splitstrr(parser->urlconv(w), SVR_ROOT);
			g.bout.puts(sys->sprint("URI: </%s>\r\n", reluri));
			g.bout.puts(sys->sprint("Location: http://%s/%s\r\n", 
				parser->urlconv(g.host), reluri));
			g.bout.puts("\r\n");
			g.bout.puts("<head><title>Object Moved</title></head>\r\n");
			g.bout.puts("<body><h1>Object Moved</h1>\r\n");
			g.bout.puts(sys->sprint(
				"Your selection moved to <a href=\"/%s\"> here</a>.<p></body>\r\n",
					reluri));
			atexit(g);
		}
		fd = fd1;
		uri = w;
		(i,dir)=sys->fstat(fd);
		if(i < 0)
			parser->fail(g,Internal,"");
	}
	parser->logit(g,sys->sprint("%s %s %d", name, uri, int dir.length));
	if(g.modtime >= dir.mtime)
		parser->notmodified(g);
	n = -1;
	if(vers != ""){
		(typ, enc) = contents->uriclass(uri);
		if(typ == nil)
			typ = contents->mkcontent("application", "octet-stream");
		bad = 0;
		if(!contents->checkcontent(typ, g.oktype, "Content-Type")){
			bad = 1;
			g.bout.puts(sys->sprint("%s 406 None Acceptable\r\n", g.version));
			parser->logit(g,"no content-type ok");
		}else if(!contents->checkcontent(enc, g.okencode, "Content-Encoding")){
			bad = 1;
			g.bout.puts(sys->sprint("%s 406 None Acceptable\r\n", g.version));
			parser->logit(g,"no content-encoding ok");
		}else
			g.bout.puts(sys->sprint("%s 200 OK\r\n", g.version));
		g.bout.puts("Server: Charon\r\n");
		g.bout.puts(sys->sprint("Last-Modified: %s\r\n", date->dateconv(dir.mtime)));
		g.bout.puts(sys->sprint("Version: %uxv%ux\r\n", int dir.qid.path, dir.qid.vers));
		g.bout.puts(sys->sprint("Message-Id: <%uxv%ux@%s>\r\n",
			int dir.qid.path, dir.qid.vers, g.mydomain));
		g.bout.puts(sys->sprint("Content-Type: %s/%s", typ.generic, typ.specific));

#		if(typ.generic== "text")
#			g.bout.puts(";charset=unicode-1-1-utf-8");

		g.bout.puts("\r\n");
		if(enc != nil){
			g.bout.puts(sys->sprint("Content-Encoding: %s", enc.generic));
			g.bout.puts("\r\n");
		}
		g.bout.puts(sys->sprint("Content-Length: %d\r\n", int dir.length));
		g.bout.puts(sys->sprint("Date: %s\r\n", daytime->time()));
		g.bout.puts("MIME-version: 1.0\r\n");
		g.bout.puts("\r\n");
		if(bad)
			atexit(g);
	}
	if(name == "HEAD")
		atexit(g);
	# send the file if it's a normal file
	g.bout.flush();
	# find if its in hash....
	# if so, retrieve, if not add..
	conts : array of byte;
	(i,conts) = cache->find(uri, dir.qid);
	if (i==0){
		# add to cache...
		conts = array[int dir.length] of byte;
		sys->seek(fd,big 0,0);
		n = sys->read(fd, conts, len conts);
		cache->insert(uri,conts, len conts, dir.qid);
	}
	sys->write(g.bout.fd, conts, len conts);
}



# classify a file
classify(d: ref Dir): (ref Content, ref Content)
{
	typ, enc: ref Content;
	
	if(d.qid.qtype&sys->QTDIR)
		return (contents->mkcontent("directory", nil),nil);
	(typ, enc) = contents->uriclass(d.name);
	if(typ == nil)
		typ = contents->mkcontent("unknown ", nil);
	return (typ, enc);
}

# read in a directory, format it in html, and send it back
senddir(g: ref Private_info,vers,uri: string, fd: ref FD, mydir: ref Dir)
{
	myname: string;
	myname = uri;
	if (myname[len myname-1]!='/')
		myname[len myname]='/';
	(a, n) := readdir->readall(fd, Readdir->NAME);
	if(vers != ""){
		parser->okheaders(g);
		g.bout.puts("Content-Type: text/html\r\n");
		g.bout.puts(sys->sprint("Date: %s\r\n", daytime->time()));
		g.bout.puts(sys->sprint("Last-Modified: %d\r\n", 
				mydir.mtime));
		g.bout.puts(sys->sprint("Message-Id: <%d%d@%s>\r\n",
			int mydir.qid.path, mydir.qid.vers, g.mydomain));
		g.bout.puts(sys->sprint("Version: %d\r\n", mydir.qid.vers));
		g.bout.puts("\r\n");
	}
	g.bout.puts(sys->sprint("<head><title>Contents of directory %s.</title></head>\n",
		uri));
	g.bout.puts(sys->sprint("<body><h1>Contents of directory %s.</h1>\n",
		uri));
	g.bout.puts("<table>\n");
	for(i := 0; i < n; i++){
		(typ, enc) := classify(a[i]);
		g.bout.puts(sys->sprint("<tr><td><a href=\"%s%s\">%s</A></td>",
			myname, a[i].name, a[i].name));
		if(typ != nil){
			if(typ.generic!=nil)
				g.bout.puts(sys->sprint("<td>%s", typ.generic));
			if(typ.specific!=nil)
				g.bout.puts(sys->sprint("/%s", 
						typ.specific));
			typ=nil;
		}
		if(enc != nil){
			g.bout.puts(sys->sprint(" %s", enc.generic));
			enc=nil;
		}
		g.bout.puts("</td></tr>\n");
	}
	if(n == 0)
		g.bout.puts("<td>This directory is empty</td>\n");
	g.bout.puts("</table></body>\n");
	g.bout.flush();
	atexit(g);
}

stripmagic(uri : string): (string, string)
{
	prog,newuri : string;
	prefix := SVR_ROOT+"magic/";
	if (!str->prefix(prefix,uri) || len newuri == len prefix)
		return(uri,nil);
	uri=uri[len prefix:];
	(prog,newuri)=str->splitl(uri,"/");
	return (newuri,prog);
}

stripsearch(uri : string): (string,string)
{
	search : string;
	(uri,search) = str->splitl(uri, "?");
	if (search!=nil)
		search=search[1:];
	return (uri, search);
}

# get rid of "." and ".." path components; make absolute
compact_path(origpath:string): string
{
	if(origpath == nil)
		origpath = "";
	(origpath,nil) = str->splitl(origpath, "`;| "); # remove specials
	(nil,olpath) := sys->tokenize(origpath, "/");
	rlpath : list of string;
	for(p := olpath; p != nil; p = tl p) {
		if(hd p == "..") {
			if(rlpath != nil)
				rlpath = tl rlpath;
		} else if(hd p != ".")
			rlpath = (hd p) :: rlpath;
	}
	cpath := "";
	if(rlpath!=nil){		
		cpath = hd rlpath;
		rlpath = tl rlpath;
		while( rlpath != nil ) {
			cpath = (hd rlpath) + "/" +  cpath;
			rlpath = tl rlpath;
		}
	}
	return SVR_ROOT + cpath;
}

getword(g: ref Private_info): string
{
	c: int;
	while((c = getc(g)) == ' ' || c == '\t' || c == '\r')
		;
	if(c == '\n')
		return nil;
	buf := "";
	for(;;){
		case c{
		' ' or '\t' or '\r' or '\n' =>
			return buf;
		}
		buf[len buf] = c;
		c = getc(g);
	}
}

getc(g : ref Private_info): int
{
	# do we read buffered or unbuffered?
	# buf : array of byte;
	n : int;
	if(g.eof){
		debug_print(g,"eof is set in httpd\n");
		return '\n';
	}
	n = g.bin.getc();
	if (n<=0) { 
		if(n == 0)
			g.getcerr=": eof";
		else
			g.getcerr=sys->sprint(": n == -1: %r");
		g.eof = 1;
		return '\n';
	}
	n &= 16r7f;
	if(n == '\n')
		g.eof = 1;
	return n;
}

# couldn't open a file
# figure out why and return and error message
notfound(g : ref Private_info,url : string)
{
	buf := sys->sprint("%r!");
	(nil,chk):=str->splitstrl(buf, "file does not exist");
	if (chk!=nil) 
		parser->fail(g,NotFound, url);
	(nil,chk)=str->splitstrl(buf,"permission denied");
	if(chk != nil)
		parser->fail(g,Unauth, url);
	parser->fail(g,NotFound, url);
}

sysname(): string
{
	n : int;
	fd : ref FD;
	buf := array[128] of byte;
	
	fd = sys->open("#c/sysname", sys->OREAD);
	if(fd == nil)
		return "";
	n = sys->read(fd, buf , len buf);
	if(n <= 0)
		return "";
	
	return string buf[0:n];
}

sysdom(): string
{
	dn : string;
	dn = csquery("sys" , sysname(), "dom");
	if(dn == nil)
		dn = "who cares";
	return dn; 
}

#  query the connection server
csquery(attr, val, rattr : string): string
{
	token : string;
	buf := array[4096] of byte;
	fd : ref FD;
	n: int;
	if(val == "" ){
		return nil;
	}
	fd = sys->open("/net/cs", sys->ORDWR);
	if(fd == nil)
		return nil;
	sys->fprint(fd, "!%s=%s", attr, val);
	sys->seek(fd, big 0, 0);
	token = sys->sprint("%s=", rattr);
	for(;;){
		n = sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		name:=string buf[0:n];
		(nil,p) := str->splitstrl(name, token);
		if(p != nil){	
			(p,nil) = str->splitl(p, " \n");
			if(p == nil)
				return nil;
			return p[4:];
		}
	}
	return nil;
}

getendpoint(dir, file: string): (string, string)
{
	sysf := serv := "";
	fto := sys->sprint("%s/%s", dir, file);
	fd := sys->open(fto, sys->OREAD);

	if(fd !=nil) {
		buf := array[128] of byte;
		n := sys->read(fd, buf, len buf);
		if(n>0) {
			buf = buf[0:n-1];
			(sysf, serv) = str->splitl(string buf, "!");
			if (serv != nil)
				serv = serv[1:];
		}
	}
	if(serv == nil)
		serv = "unknown";
	if(sysf == nil)
		sysf = "unknown";
	return (sysf, serv);
}

getendpoints(dir: string): string
{
	(lsys, lserv) := getendpoint(dir, "local");
	(rsys, rserv) := getendpoint(dir, "remote");
	return rsys;
}
