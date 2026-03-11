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
	clf: import parser;

include "date.m";
	date: Date;

include "redirect.m";
	redir: Redirect;

include "alarms.m";
	alarms: Alarms;
	Alarm: import alarms;

include "cgiparse.m";
	cgiparse: CgiParse;
include "sh.m";
	sh: Sh;
	Context, Listnode: import sh;


# globals 

cache_size: int;
port := "80";
addr: string;
stderr : ref FD;
dbg_log, logfile, accesslog: ref FD;
debug: int;
my_domain: string;

ACCESSLOG: con "/services/httpd/access.log";

UNAUTHED	:con "You are not authorized to see this area.\n";
NOCONTENT	:con "No acceptable type of data is available.\n";
NOENCODE	:con "No acceptable encoding of the contents is available.\n";
UNMATCHED	:con "The entity requested does not match the existing entity.\n";
BADRANGE	:con "No bytes are avaible for the range you requested.\n";

usage()
{
	sys->fprint(stderr, "usage: httpd [-c num] [-D] [-a servaddr]\n");
	raise "fail:usage";
}

atexit(g: ref Private_info)
{
	dprint("At exit from httpd, closing fds. \n");
	g.bin.close();	
	g.bout.close();
	g.bin=nil;
	g.bout=nil;
	exit;
}

dprint(s : string)
{
	if (dbg_log!=nil)
		sys->fprint(dbg_log,"%s",s);
}

# Constant-time string comparison to prevent timing side-channel attacks.
# Always iterates over the full length to avoid leaking length information.
consteq(a, b: string): int
{
	alen := len a;
	blen := len b;
	# Use the longer length so we don't leak which is shorter
	n := alen;
	if(blen > n)
		n = blen;
	result := alen ^ blen;
	for(i := 0; i < n; i++)
		result |= a[i % alen] ^ b[i % blen];
	return result == 0;
}

# Escape HTML special characters to prevent XSS
htmlescape(s: string): string
{
	t := "";
	for(i := 0; i < len s; i++) {
		case s[i] {
		'&' =>
			t += "&amp;";
		'<' =>
			t += "&lt;";
		'>' =>
			t += "&gt;";
		'"' =>
			t += "&quot;";
		'\'' =>
			t += "&#39;";
		* =>
			t[len t] = s[i];
		}
	}
	return t;
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
			"-n" =>
				args = tl args;
				my_domain = hd args;
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

	cgiparse = load CgiParse CgiParse->PATH;
	if(cgiparse == nil) badmod(CgiParse->PATH);

	sh = load Sh Sh->PATH;
	if(sh == nil) badmod(Sh->PATH);

	logfile=sys->create(HTTPLOG,Sys->ORDWR,Sys->DMAPPEND|8r666);
	if (logfile==nil) {
		sys->fprint(stderr, "httpd: cannot open %s: %r\n", HTTPLOG);
		raise "cannot open http log";
	}
	accesslog=sys->open(ACCESSLOG,Sys->ORDWR);
	if (accesslog==nil) {
		sys->fprint(stderr, "httpd: cannot open %s: %r\n", ACCESSLOG);
		raise "cannot open access log";
	}else 
		sys->seek(accesslog, big 0, sys->SEEKEND);
	# parse arguments to httpd.

	cache_size=5000;
	debug = 0;
	parse_args(argv);
	if(debug==1){
		dbg_log=sys->create(DEBUGLOG,Sys->ORDWR,8r666);
		if (dbg_log==nil){
			sys->print("debug log open: %r\n");
			exit;
		}
		sys->fprint(dbg_log,"started at %s \n",daytime->time());
	}

	# initialisation routines
	contents->contentinit(dbg_log);
	cache->cache_init(dbg_log,cache_size);
	redir->redirect_init(REWRITE);
	date->init();
	parser->init();
	if(my_domain == nil)
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
		dolisten(c);
	exit;
}

dolisten(c: Sys->Connection)
{
	(ok, nc) := sys->listen(c);
	if(ok < 0) {
		sys->fprint(stderr, "listen: %r\n");
		exit;
	}
	dprint("spawning connection.\n");
	spawn service_req(nc);
}

zeroprivinfo:  Private_info;

service_req(nc : Sys->Connection)
{
	sys->pctl(Sys->NEWPGRP, nil);#|Sys->FORKFD
	buf := array[64] of byte;
	l := sys->open(nc.dir+"/remote", sys->OREAD);
	if(l == nil)
		return;
	n := sys->read(l, buf, len buf);
	if(n >= 0)
		dprint("New client http: " + nc.dir + " " + string buf[0:n]);
	#  wait for a call (or an error)
	#  start a process for the service
	g := ref zeroprivinfo;
	g.bufio = bufio;
	g.dbg_log = dbg_log;
	g.logfile = logfile;
	g.accesslog = accesslog;
	g.entity = parser->initarray();
	g.mydomain = my_domain;
	g.version = "HTTP/1.1";
	g.cache = cache;
	g.remotesys = getendpoints(nc.dir);
	dprint("opening in for "+ string buf[0:n] + "\n");
	g.bin = bufio->open(nc.dir + "/data", bufio->OREAD);
	if (g.bin == nil){
		sys->print("bin open: %r\n");
		exit;
	}
	dprint("opening out for "+string buf[0:n]+"\n");
	g.bout = bufio->open(nc.dir + "/data", bufio->OWRITE);
	if (g.bout == nil){
		sys->print("bout open: %r\n");
		exit;
	}
	dprint("calling parsereq for "+ string buf[0:n] + "\n");
	nc.dfd = nc.cfd = nil;
	sys->pctl(Sys->NEWFD, g.bin.fd.fd :: g.bout.fd.fd :: accesslog.fd ::  logfile.fd:: nil);
	for(t := 15*60*1000; ; t = 15*1000){
		parsereq(g, t);
		if(g.closeit == 1){
			atexit(g);
		}
	}
}

parsereq(g: ref Private_info, t: int)
{
	meth, v,magic,search,uri,origuri,extra : string;
	# 15 minutes to get request line
	a := Alarm.alarm(t);
	g.eof = 0;
	meth = getword(g);
	if(meth == nil){
		if(g.eof){
			g.closeit = 1;
			a.stop();
			return;
		}
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
		parser->logit(g, sys->sprint("extra header word '%s'%s", extra, g.getcerr));
		parser->fail(g, Syntax,"");
	}
	case v {
	"" =>
		if(meth != "GET"){
			parser->logit(g, sys->sprint("unimplemented method %s%s", meth, g.getcerr));
			parser->fail(g, Unimp, meth);
		}
		g.vermaj = 0;
		g.vermin = 9;
	"HTTP/V1.0" or "HTTP/1.0" =>
		g.vermaj = 1;
		g.vermin = 0;
	"HTTP/1.1" =>
		g.vermaj = 1;
		g.vermin = 1;
	* =>
		parser->logit(g, sys->sprint("method %s uri %s%s", meth, uri, g.getcerr));
		parser->fail(g, UnkVers, v);
	}
	if((meth != "GET")  && (meth != "HEAD") && (meth != "POST")){
		parser->logit(g, sys->sprint("unimplemented method %s", meth));
		parser->fail(g, Unimp, meth);
	}	

	# the fragment is not supposed to be sent
	# strip it because some clients send it

	(uri, extra) = str->splitl(uri, "#");
	if(extra != nil)
		parser->logit(g,sys->sprint("fragment %s", extra));
	
	if(parser->http11(g)){
		(uri, g.urihost) = parseuri(g, uri);
		if(uri == nil)
			parser->fail(g, BadReq, uri);
	}
	g.requri = uri;
	# munge uri for search, protection, and magic	 
	(uri, search) = stripsearch(uri);
	uri = compact_path(parser->urlunesc(uri));
	(uri, magic) = stripmagic(uri);
	dprint("stripmagic=(" + uri + "," + magic + ")\n");

	g.uri = uri;
	g.meth = meth;
	 # normal case is just file transfer
	if(magic == nil || (magic == "httpd")){
		if (meth=="POST")
			parser->fail(g, Unimp, meth);	# /magic does handles POST
		g.host = g.mydomain;
		origuri = uri;
		parser->httpheaders(g, v);
		if(!parser->http11(g) && !g.persist)
			g.closeit = 1;
		uri = redir->redirect(origuri);
		# must change this to implement proxies
		if(uri == nil)
			send(g, meth, v, origuri, search);
		else
			doredirect(g, uri);
		return;
	}

	domagic(g,magic,uri,origuri,Request(meth, v, uri, search));
	g.closeit = 1;
}

domagic(g: ref Private_info,file, uri, origuri: string, req: Request)
{
	found := 0;
	buf := sys->sprint("%s%s.dis", MAGICPATH, file);
	dprint("looking for "+buf+"\n");
	c:= load Cgi buf;
	if (c==nil){
		# Only .dis modules are supported for /magic/ handlers.
		# Shell script fallback removed: it passed unsanitized URI
		# components to the shell, enabling command injection.
		;
	}else {
		{
			found = 1;
			c->init(g, req);
		}exception{
			"fail:*" =>
				return;
		}
	}
	if(!found){
		parser->logit(g,sys->sprint("no magic %s uri %s", file, uri));
		parser->fail(g,NotFound, origuri);
	}
}

newcc(g: ref Private_info, req: Httpd->Request): ref Context
{
	cgidata := cgiparse->cgiparse(g, req);
	g.bout.puts(cgidata.httphd);
	g.bout.flush();
#	sys->dup(g.bin.fd.fd, 0);
	sys->dup(g.bout.fd.fd, 1);
#	sys->dup(g.bout.fd.fd, 2);
	g.bin.fd = nil;
	g.bout.fd = nil;
	sys->pctl(Sys->NEWENV, 0 :: 1 :: 2  :: nil);
	ctxt := Context.new(nil);

	ctxt.set("method", ref Listnode(nil, cgidata.method) :: nil);
	ctxt.set("uri", ref Listnode(nil, cgidata.uri) :: nil);
	ctxt.set("search", ref Listnode(nil, cgidata.search) :: nil);
	ctxt.set("remote", ref Listnode(nil, cgidata.remote) :: nil);
	ctxt.set("tmstamp", ref Listnode(nil, cgidata.tmstamp) :: nil);
	ctxt.set("version", ref Listnode(nil, cgidata.version) :: nil);
	for(l := cgidata.header; l != nil; l = tl l){
		(tag, val) := hd l;
		ctxt.set(tag, ref Listnode(nil, val) :: nil);
	}
	for(l = cgidata.form; l != nil; l = tl l){
		(tag, val) := hd l;
		ctxt.set(tag, ref Listnode(nil, val) :: nil);
	}
	return ctxt;
}

nonexistent(e: string): int
{
	errs := array[] of {"does not exist", "directory entry not found"};
	for (i := 0; i < len errs; i++){
		j := len errs[i];
		if (j <= len e && e[len e-j:] == errs[i])
			return 1;
	}
	return 0;
}


send(g: ref Private_info,name, vers, uri, search : string)
{
	w : string;
	force301: int;
	if(search != nil)
		parser->fail(g, NoSearch, uri);

	s :=  ".httplogin";
	if(len uri >= len s && uri[len uri - len s:] == s){
		notfound(g, uri);
	}
	# figure out the type of file and send headers
	dprint("httpd->send->open(" + uri + ")\n" );
	fd := sys->open(uri, sys->OREAD);
	if(fd == nil){
		dbm := sys->sprint( "open failed: %r\n" );
		dprint(dbm);
		notfound(g, uri);
	}
	(i,dir) := sys->fstat(fd);
	if(i< 0)
		parser->fail(g, Internal, "");
	if(dir.mode & Sys->DMDIR){
		(nil, p) := str->splitr(uri, "/");
		if(p == nil){
			w = sys->sprint("%sindex.html", uri);
			force301 = 0;
		}else{
			w = sys->sprint("%s/index.html", uri);
			force301 = 1; 
		}
		fd1 := sys->open(w, sys->OREAD);
		if(fd1 == nil){
			parser->logit(g,sys->sprint("%s directory %s", name, uri));
			if(g.ifmodsince >= dir.mtime)
				parser->notmodified(g);
			senddir(g,vers, uri, fd, ref dir);
		} else if(force301 != 0 && vers != ""){
			(nil, reluri) := str->splitstrr(parser->urlconv(w), SVR_ROOT);
			doredirect(g, sys->sprint("http://%s/%s", parser->urlconv(g.host), reluri));
			atexit(g);
		}
		fd = fd1;
		uri = w;
		g.uri = w;
		(i,dir)=sys->fstat(fd);
		if(i < 0)
			parser->fail(g,Internal,"");
	}

	if(authorize(g, uri)){
		parser->logit(g,sys->sprint("%s %s %d", name, uri, int dir.length));
		sendfd(g, fd, dir);
	}
}

BufSize: con 32*1024;
sendfd(g: ref Private_info, fd: ref Sys->FD, dir:  Sys->Dir): int
{
	typ,enc : ref Content;
	bad: int;
	qid := dir.qid;
	length := int dir.length;
	mtime := dir.mtime;
	n := -1;
	multir := 0;
	r: list of Range;
	boundary: string;
	xferbuf := array[BufSize] of byte;

	if(g.ifmodsince >= dir.mtime)
		parser->notmodified(g);
	n = -1;
	if(g.vermaj){
		(typ, enc) = contents->uriclass(g.uri);
		if(typ == nil)
			typ = contents->mkcontent("application", "octet-stream");
		bad = 0;
		etag := sys->sprint("\"%bux%ux\"", qid.path, qid.vers);
		ok := checkreq(g, typ, enc, mtime, etag);
		if(ok <= 0)
			atexit(g);

		# check for if-range requests
		if(g.range == nil
		|| g.ifrangeetag != nil && !etagmatch(1, g.ifrangeetag, etag)
		|| g.ifrangedate != 0 && g.ifrangedate != mtime){
			g.range = nil;
			g.ifrangeetag = nil;
			g.ifrangedate = 0;
		}

		if(g.range != nil){
			g.range = fixrange(g.range, length);
			if(g.range == nil){
				if(g.ifrangeetag == nil && g.ifrangedate == 0){
					g.bout.puts(g.version + " 416 Request range not satisfiable\r\n");
					g.bout.puts("Server: Charon\r\n");
					g.bout.puts("Date: " + daytime->time() + "\r\n");
					g.bout.puts(sys->sprint("Content-Range: bytes */%d\r\n", length));
					g.bout.puts("Content-Type: text/html\r\n");
					g.bout.puts(sys->sprint("Content-Length: %d\r\n", len BADRANGE));
					g.bout.puts("Content-Type: text/html\r\n");
					if(g.closeit)
						g.bout.puts("Connection: close\r\n");
					else if(!parser->http11(g))
						g.bout.puts("Connection: Keep-Alive\r\n");
					g.bout.puts("\r\n");
					if(g.meth != "HEAD")
						g.bout.puts(BADRANGE);
					g.bout.flush();
					clf(g, 416, 0);
					return 1;
				}
				g.ifrangeetag = nil;
				g.ifrangedate = 0;
			}
		}
		if(g.range == nil){
			g.bout.puts(g.version + " 200 OK\r\n");
			clf(g, 200, length);
		}else{
			g.bout.puts(g.version + " 206 Partial Content\r\n");
			clf(g, 206, length);
		}
		g.bout.puts("Server: Charon\r\n");
		g.bout.puts("Date: " + daytime->time() + "\r\n");
		g.bout.puts("ETag: " + etag + "\r\n");

		r = g.range;
		if(r == nil)
			g.bout.puts(sys->sprint("Content-Length: %d\r\n", int dir.length));
		else if(tl r == nil)
			g.bout.puts(sys->sprint("Content-Range: bytes %d-%d/%d\r\n", (hd r).start, (hd r).stop, length));
		else{
			multir = 1;
			boundary = parser->mimeboundary(g);
			g.bout.puts("Content-Type: multipart/byteranges; boundary=" + boundary + "\r\n");
		}
		if(g.ifrangeetag == nil){
			g.bout.puts("Last-Modified: " + daytime->text(daytime->local(mtime)) + "\r\n");
			if(!multir)
				printtype(g, typ, enc);
			if(g.fresh_thresh)
				; # TODO Skip doing hints for now
		}

		if(g.closeit)
			g.bout.puts("Connection: close\r\n");
		else if(!parser->http11(g))
			g.bout.puts("Connection: Keep-Alive\r\n");
		g.bout.puts("\r\n");
	}
	if(g.meth == "HEAD"){
		atexit(g);
	}

	# send the file if it's a normal file
	if(r == nil){
		g.bout.flush();
		wrote := 0;
		if(n > 0)
			wrote = g.bout.write(xferbuf, n);
		if(n <=0 || wrote == n){
			while((n = sys->read(fd, xferbuf, len xferbuf)) > 0){
				nw := sys->write(g.bout.fd, xferbuf, n);
				if(nw != n){
					if(nw > 0)
						wrote += nw;
					break;
				}
				wrote += nw;
			}
		}
		if(length == wrote)
			return 1;
		else
			atexit(g);
		return -1;
	}

	wrote := 0;
	ok := 1;
	breakout: for(; r != nil; r = tl r){
		if(multir){
			g.bout.puts("\r\n--" + boundary + "\r\n");
			printtype(g, typ, enc);
			g.bout.puts(sys->sprint("Content-Range: bytes %d-%d/%d\r\n", (hd r).start, (hd r).stop, length));
			g.bout.puts("\r\n");
		}
		g.bout.flush();

		if(sys->seek(fd, big (hd r).start,  0) != big (hd r).start){
			ok = -1;
			break;
		}
		for(tr := (hd r).stop - (hd r).start + 1; tr != 0; tr -= n){
			n = tr;
			if(n>BufSize)
				n = BufSize;
			if(sys->read(fd, xferbuf, n) != n){
				ok = -1;
				break breakout;
			}
			nw := sys->write(g.bout.fd, xferbuf, n);
			if(nw != n){
				if(nw > 0)
					wrote += nw;
				ok = -1;
				break breakout;
			}
			wrote += nw;
		}

	}
	if(r == nil){
		if(multir){
			g.bout.puts("--" + boundary + "--\r\n");
			g.bout.flush();
		}
		parser->logit(g,sys->sprint("Reply: 206 partial content %d %d\n", length, wrote));
	}else
		parser->logit(g, sys->sprint("Reply: 206 partial content, early termination %d %d\n", length, wrote));
	return ok;
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
	offset := len SVR_ROOT;
	if (myname[len myname-1]!='/')
		myname[len myname]='/';
	(a, n) := readdir->readall(fd, Readdir->NAME);
	if(vers != ""){
		parser->okheaders(g);
		g.bout.puts("Content-Type: text/html\r\n");
		g.bout.puts(sys->sprint("Date: %s\r\n", daytime->time()));
		g.bout.puts(sys->sprint("Last-Modified: %d\r\n", mydir.mtime));
		g.bout.puts(sys->sprint("Message-Id: <%d%d@%s>\r\n",
			int mydir.qid.path, mydir.qid.vers, g.mydomain));
		g.bout.puts(sys->sprint("Version: %d\r\n", mydir.qid.vers));
		g.bout.puts("\r\n");
	}
	escuri := htmlescape(uri[offset:]);
	g.bout.puts(sys->sprint("<head><title>Contents of directory %s.</title></head>\n",
		escuri));
	g.bout.puts(sys->sprint("<body><h1>Contents of directory %s.</h1>\n",
		escuri));
	g.bout.puts("<table>\n");
	for(i := 0; i < n; i++){
		(typ, enc) := classify(a[i]);
		escname := htmlescape(a[i].name);
		g.bout.puts(sys->sprint("<tr><td><a href=\"/%s%s\">%s</A></td>",
			myname[offset:], escname, escname));
		if(typ != nil){
			if(typ.generic != nil)
				g.bout.puts(sys->sprint("<td>%s", typ.generic));
			if(typ.specific != nil)
				g.bout.puts(sys->sprint("/%s", typ.specific));
			typ = nil;
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
	clf(g, 200, 0);
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

stripsearch(uri : string): (string, string)
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
	MAXWORD: con 16384;
	for(;;){
		case c{
		' ' or '\t' or '\r' or '\n' =>
			return buf;
		}
		if(len buf >= MAXWORD)
			return buf;
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
		dprint("eof is set in httpd\n");
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
#	(lsys, lserv) := getendpoint(dir, "local");
	(rsys, nil) := getendpoint(dir, "remote");
	return rsys;
}

doredirect(g : ref Private_info, uri: string)
{
	g.bout.puts(g.version + " 301 Moved Permanently\r\n");
	g.bout.puts("Date: " + daytime->time() + "\r\n");
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

okheaders(g : ref Private_info)
{
	g.bout.puts(g.version + " 200 OK\r\n");
	g.bout.puts("Server: Charon\r\n");
	g.bout.puts("Date: " + daytime->time() + "\r\n");
}

# WARNING: .httplogin stores passwords in plaintext.
# This httpd should only be deployed behind a TLS-terminating reverse proxy.
# Future improvement: hash passwords with a key derivation function.
authorize(g: ref Private_info, file: string): int
{
	(p, nil) := str->splitr(file, "/");
	if(p == nil)
		parser->fail(g,Internal, "");
	p +=  ".httplogin";
	buf := readfile(p);
	if(buf == nil)
		return 1;
	(n, flds) := sys->tokenize(buf, "\n\r\t ");
	if(n == 0)
		return 1;
	realm := hd flds;
	flds = tl flds;
	if(g.authuser != nil && g.authpass != nil){
		for(; flds != nil; flds = tl flds){
			user := hd flds;
			flds = tl flds;
			if(flds != nil && consteq(user, g.authuser) && consteq(hd flds, g.authpass)){
				# Zero password from memory after successful auth
				for(zi := 0; zi < len g.authpass; zi++)
					g.authpass[zi] = '\0';
				g.authpass = nil;
				return 1;
			}
		}
	}
	# Zero password from memory after failed auth
	if(g.authpass != nil) {
		for(zi := 0; zi < len g.authpass; zi++)
			g.authpass[zi] = '\0';
		g.authpass = nil;
	}
	unauthorized(g, realm);
	return 0;
}

unauthorized(g: ref Private_info, realm: string)
{
	g.bout.puts(g.version + " 401 Unauthorized\r\n");
	g.bout.puts("Server: Charon\r\n");
	g.bout.puts("Date: " + daytime->time() + "\r\n");
	g.bout.puts("WWW-Authenticate: Basic realm=\"" + realm + "\"\r\n");
	g.bout.puts("Content-type: text/html\r\n");
	g.bout.puts(sys->sprint("Content-Length: %d\r\n", len UNAUTHED));
	if(g.closeit)	
		g.bout.puts("Connection: close\r\n");
#	else if(!parser->http11(g))
#		g.bout.puts("Connection: Keep-Alive\r\n");
	g.bout.puts("\r\n");
	g.bout.puts(UNAUTHED);
	g.bout.flush();
}

readfile(file: string): string
{
	fd := sys->open(file, Sys->OREAD);
	if(fd == nil)
		return nil;
	(n, d) := sys->fstat(fd);
	if(n < 0)
		return nil;
	l := int d.length;

	buf := array[l] of byte;
	n = sys->read(fd, buf, l);
	if(n <=0)
		return nil;
	return string buf;
}


# sendfd.c

fixrange(h: list of Range, length: int): list of Range
{
	if(length == 0)
		return nil;

	rl : list of Range;
	for(l:=h; l != nil; l = tl l){
		r := hd l;
		if(r.suffix){
			r.start = length - r.stop;
			if(r.start >= length)
				r.start = 0;
			r.stop = length - 1;
			r.suffix = 0;
		}
		if(r.stop >= length)
			r.stop = length - 1;
		if(r.start > r.stop)
				;
		else
			rl = r :: rl;
	}

	if(rl == nil)
		return nil;
	l = rl;
	r := hd l;
	rl = nil;
	while(tl l != nil){
		l = tl l;
		rr := hd l;
		if(r.start <= rr.start && r.stop + 1 >= rr.start){
			if(r.stop < rr.stop)
				r.stop = rr.stop;
		} else {
			rl = r :: rl;
			r = rr;
		}
	}
	rl = r :: rl;
	return rl;
}

etagmatch(strong: int, tags: list of Etag, e: string): int
{
	for( ; tags != nil; tags = tl tags){
		tag := hd tags;
		if(strong && tag.weak)
			continue;
		s := tag.etag;
		if(s == "*")
			return 1;
		if(s == e[1:len e - 2]) #  e is "tag"
			return 1;
	}
	return 0;
}

checkreq(g: ref Private_info, typ, enc: ref Content, mtime: int, etag: string): int
{
	ret := 1;
	if(g.vermaj >= 1 && g.vermin >= 1 && !contents->checkcontent(typ, g.oktype, "Content-Type")){
		g.bout.puts(sys->sprint("%s 406 None Acceptable\r\n", g.version));
		parser->logit(g,"no content-type ok");
		return 0;
	}
	if(g.vermaj >= 1 && g.vermin >= 1 && !contents->checkcontent(enc, g.okencode, "Content-Encoding")){
		g.bout.puts(sys->sprint("%s 406 None Acceptable\r\n", g.version));
		parser->logit(g,"no content-encoding ok");
		return 0;
	}

	m := etagmatch(1, g.ifnomatch, etag);
	if(m && g.meth != "GET" && g.meth != "HEAD"
	|| g.ifunmodsince && g.ifunmodsince < mtime
	|| g.ifmatch != nil && !etagmatch(1, g.ifmatch, etag)){
		g.bout.puts(g.version + " 412 Precondition Failed\r\n");
		g.bout.puts("Server: Charon\r\n");
		g.bout.puts("Date: " + daytime->time() + "\r\n");
		g.bout.puts("Content-Type: text/html\r\n");
		g.bout.puts(sys->sprint("Content-Length: %d\r\n", len UNMATCHED));
		if(g.closeit)
			g.bout.puts("Connection: close\r\n");
		else if(!parser->http11(g))
			g.bout.puts("Connection: Keep-Alive\r\n");
		g.bout.puts("\r\n");
		if(g.meth != "HEAD")
			g.bout.puts(UNMATCHED);
		g.bout.flush();
		return 0;
	}

	if(g.ifmodsince >= mtime
	&& (m || g.ifnomatch == nil)){
		g.bout.puts(g.version + " 304 Not Modified\r\n");
		g.bout.puts("Server: Charon\r\n");
		g.bout.puts("Date: " + daytime->time() + "\r\n");
		g.bout.puts("ETag: " + etag + "\r\n");
		if(g.closeit)
			g.bout.puts("Connection: close\r\n");
		else if(!parser->http11(g))
			g.bout.puts("Connection: Keep-Alive\r\n");
		g.bout.puts("\r\n");
		g.bout.flush();
		return 0;
	}
	return ret;
}

parseuri(nil: ref Private_info, uri: string): (string, string)
{
	urihost := "";
	if(len uri == 0)
		return (nil, nil);
	if(uri[0] != '/'){
		if(len uri >= 7 && uri[0:7] == "http://")
			return (nil, nil);
		if(len uri < 6)
			return (nil, nil);
		uri  = uri[5:];
	}
	if(len uri > 2 && uri[0] == '/' && uri[1] == '/'){
		(urihost, uri) = str->splitl(uri[2:], "/");
		if(uri == nil)
			uri = "/";
		(urihost, nil) = str->splitl(urihost, ":");
	}
	if(uri[0] != '/' || (len uri > 2 && uri[1] == '/'))
		return  (nil, nil);
	return (uri, str->tolower(urihost));
}

printtype(g: ref Private_info, typ, enc: ref Content)
{
	g.bout.puts("Content-Type: " + typ.generic + "/" + typ.specific + "\r\n");
	if(enc != nil)
		g.bout.puts("Content-Encoding: " + enc.generic + "\r\n");
}
