implement Transport;

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	S: String;

include "bufio.m";
	B : Bufio;
	Iobuf: import B;

include "date.m";
	D: Date;

include "message.m";
	M: Message;
	Msg, Nameval: import M;

include "url.m";
	U: Url;
	ParsedUrl: import U;

include "webget.m";

include "wgutils.m";
	W: WebgetUtils;
	Fid, Req: import WebgetUtils;

include "keyring.m";
include "asn1.m";
include "pkcs.m";
include "sslsession.m";
include "ssl3.m";
	ssl3: SSL3;
	Context: import ssl3;
# Inferno supported cipher suites: RSA_EXPORT_RC4_40_MD5
ssl_suites := array [] of {byte 0, byte 16r03};
ssl_comprs := array [] of {byte 0};

include "transport.m";

HTTPD:		con "80";		# Default IP port
HTTPSD:		con "443";	# Default IP port for HTTPS
Version:	con "1.0";	# Client ID
MAXREDIR:	con 10;

HTTPheader: adt
{
	vers:		string;
	code:		int;
	length:		int;
	content:	string;
};

Resp: adt
{
	code:		int;
	action:		int;
	cacheable:	int;
	name:		string;
};

DODATA, ERROR, REDIR, UNAUTH, HTMLERR: con iota;

usecache := 1;
cachedir: con "/services/webget/cache";

httpproxy: ref ParsedUrl;
agent := "Inferno-webget/" + Version;

responses := array[] of {
	(Resp)(100, DODATA, 0,	"Continue" ),
	(Resp)(101, ERROR, 0,	"Switching Protocols" ),
	(Resp)(200, DODATA, 1,	"Ok" ),
	(Resp)(201, DODATA, 0,	"Created" ),
	(Resp)(202, DODATA, 0,	"Accepted" ),
	(Resp)(203, DODATA, 1,	"Non-Authoratative Information" ),
	(Resp)(204, DODATA, 0,	"No content" ),
	(Resp)(205, DODATA, 0,	"Reset content" ),
	(Resp)(206, DODATA, 0,	"Partial content" ),
	(Resp)(300, ERROR, 1,	"Multiple choices" ),
	(Resp)(301, REDIR, 1,	"Moved permanently" ),
	(Resp)(302, REDIR, 0,	"Moved temporarily" ),
	(Resp)(303, ERROR, 0,	"See other" ),
	(Resp)(304, ERROR, 0,	"Not modified" ),
	(Resp)(305, ERROR, 0,	"Use proxy" ),
	(Resp)(400, HTMLERR, 0,	"Bad request" ),
	(Resp)(401, UNAUTH, 0,	"Unauthorized" ),
	(Resp)(402, HTMLERR, 0,	"Payment required" ),
	(Resp)(403, HTMLERR, 0,	"Forbidden" ),
	(Resp)(404, HTMLERR, 0,	"Not found" ),
	(Resp)(405, HTMLERR, 0,	"Method not allowed" ),
	(Resp)(406, HTMLERR, 0,	"Not Acceptable" ),
	(Resp)(407, HTMLERR, 0,	"Proxy authentication required" ),
	(Resp)(408, HTMLERR, 0,	"Request timed-out" ),
	(Resp)(409, HTMLERR, 0,	"Conflict" ),
	(Resp)(410, HTMLERR, 1,	"Gone" ),
	(Resp)(411, HTMLERR, 0,	"Length required" ),
	(Resp)(412, HTMLERR, 0,	"Precondition failed" ),
	(Resp)(413, HTMLERR, 0,	"Request entity too large" ),
	(Resp)(414, HTMLERR, 0,	"Request-URI too large" ),
	(Resp)(415, HTMLERR, 0,	"Unsupported media type" ),
	(Resp)(500, ERROR, 0,	"Internal server error"),
	(Resp)(501, ERROR, 0,	"Not implemented"),
	(Resp)(502, ERROR, 0,	"Bad gateway"),
	(Resp)(503, ERROR, 0,	"Service unavailable"),
	(Resp)(504, ERROR, 0,	"Gateway time-out"),
	(Resp)(505, ERROR, 0,	"HTTP version not supported"),
};

init(w: WebgetUtils)
{
	sys = load Sys Sys->PATH;
	D = load Date Date->PATH;
	D->init();
	W = w;
	M = W->M;
	S = W->S;
	B = W->B;
	U = W->U;
	ssl3 = nil;	# load on demand
	readconfig();
}

readconfig()
{
	cfgio := B->open("/services/webget/config", sys->OREAD);
	if(cfgio != nil) {
		for(;;) {
			line := B->cfgio.gets('\n');
			if(line == "") {
				B->cfgio.close();
				break;
			}
			if(line[0]=='#')
				continue;
			(key, val) := S->splitl(line, " \t");
			val = S->take(S->drop(val, " \t"), "^\r\n");
			if(val == "")
				continue;
			if(key == "httpproxy" && val != "none") {
				# val should be host or host:port
				httpproxy = U->makeurl("http://" + val);
				W->log(nil, "Using http proxy " + httpproxy.tostring());
				usecache = 0;
			}
			if(key == "agent") {
				agent = val;
				W->log(nil, sys->sprint("User agent specfied as '%s'\n", agent));
			}
		}
	}
}

connect(c: ref Fid, r: ref Req, donec: chan of ref Fid)
{
	method := r.method;
	u := r.url;
	accept := W->fixaccept(r.types);
	mrep, cachemrep: ref Msg = nil;
	validate : string;
	io: ref Iobuf = nil;
	redir := 1;
	usessl := 0;
	sslx : ref Context;

    redirloop:
	for(nredir := 0; redir && nredir < MAXREDIR; nredir++) {
		redir = 0;
		mrep = nil;
		cachemrep = nil;
		io = nil;
		validate = "";
		if(u.scheme == Url->HTTPS) {
			usessl = 1;
			if(ssl3 == nil) {
				ssl3 = load SSL3 SSL3->PATH;
				ssl3->init();
				sslx = ssl3->Context.new();
			}
		}
		cacheit := usecache;
		if(r.cachectl == "no-cache" || usessl)
			cacheit = 0;
		resptime := 0;
		#
		# Perhaps try the cache
		#
		if(usecache && method == "GET") {
			(cachemrep, validate) = cacheread(c, u, r);
			if(cachemrep != nil && validate == "")
				cacheit = 0;
		}
		else
			cacheit = 0;

		if(cachemrep == nil || validate != "") {
			#
			# Find the port and dial the network
			#
			dialu := u;
			if(httpproxy != nil)
				dialu = httpproxy;
			port := dialu.port;
			if(port == "") {
				if(usessl)
					port = HTTPSD;
				else
					port = HTTPD;
			}
			addr := "tcp!" + dialu.host + "!" + port;

			W->log(c, sys->sprint("http: dialing %s", addr));
			(ok, net) := sys->dial(addr, nil);
			if(ok < 0) {
				mrep = W->usererr(r, sys->sprint("%r"));
				break redirloop;
			}
			W->log(c, "http: connected");
			e: string;
			if(usessl) {
				vers := 3;
				info := ref SSL3->Authinfo(ssl_suites, ssl_comprs, nil, 0, nil, nil, nil);
				(e, vers) = sslx.client(net.dfd, addr, vers, info);
				if(e != "") {
					mrep = W->usererr(r, e);
					break redirloop;
				}
				W->log(c, "https: ssl handshake complete");
			}

			#
			# Issue the request
			#
			m := Msg.newmsg();
			requ: string;
			if(httpproxy != nil)
				requ = u.tostring();
			else {
				requ = u.pstart + u.path;
				if(u.query != "")
					requ += "?" + u.query;
			}
			m.prefixline = method + " " +  requ + " HTTP/1.0";
			hdrs := Nameval("Host", u.host) ::
				Nameval("User-agent", agent) ::
				Nameval("Accept", accept) :: nil;
			m.addhdrs(hdrs);
			if(validate != "")
				m.addhdrs(Nameval("If-Modified_Since", validate) :: nil);
			if(r.auth != "") {
				m.addhdrs(Nameval("Authorization", "Basic " + r.auth) :: nil);
				cacheit = 0;
			}
			if(method == "POST") {
				m.body = r.body;
				m.bodylen = len m.body;
				m.addhdrs(Nameval("Content-Length", string (len r.body)) :: 
						Nameval("Content-type", "application/x-www-form-urlencoded") ::
						nil);
			}
			io = B->fopen(net.dfd, sys->ORDWR);
			if(io == nil) {
				mrep = W->usererr(r, "cannot open network via bufio");
				break redirloop;
			}
			e = m.writemsg(io);
			if(e != "") {
				mrep = W->usererr(r, e);
				break redirloop;
			}
			(mrep, e) = Msg.readhdr(io, 1);
			if(e!= "") {
				mrep = W->usererr(r, e);
				break redirloop;
			}
			resptime = D->now();
		}
		else
			mrep = cachemrep;
		status := mrep.prefixline;
		W->log(c, "http:  response from network or cache: " + status
				+ "\n" + mrep.header()
				);
	
		if(!S->prefix("HTTP/", status)) {
			mrep = W->usererr(r, "expected http got something else");
			break redirloop;
		}
		code := getcode(status);

		if(validate != "" && code == 304) {
			# response: "Not Modified", so use cached response
			mrep = cachemrep;
			B->io.close();
			io = nil;

			# let caching happen with new response time
			# (so age will be small next time)
			status = mrep.prefixline;
			W->log(c, "http: validate ok, using cache: " + status);
			code = getcode(status);
		}

		for(i := 0; i < len responses; i++) {
			if(responses[i].code == code)
				break;
		}

		if(i >= len responses) {
			mrep = W->usererr(r, "Unrecognized HTTP response code");
			break redirloop;
		}

		(nil, conttype) := mrep.fieldval("content-type");
		cacheit = cacheit && responses[i].cacheable;
		case responses[i].action {
		DODATA =>
			e := W->getdata(io, mrep, accept, u);
			if(e != "")
				mrep = W->usererr(r, e);
			else {
				if(cacheit)
					cachewrite(c, mrep, u, resptime);
				W->okprefix(r, mrep);
			}
		ERROR =>
			mrep = W->usererr(r, responses[i].name);
		UNAUTH =>
			(cok, chal) := mrep.fieldval("www-authenticate");
			if(cok && r.auth == "")
				mrep = W->usererr(r, "Unauthorized: " + chal);
			else {
				if(conttype == "text/html" && htmlok(accept)) {
					e := W->getdata(io, mrep, accept, u);
					if(e != "")
						mrep = W->usererr(r, "Authorization needed");
					else
						W->okprefix(r, mrep);
				}
				else
					mrep = W->usererr(r, "Authorization needed");
			}
		REDIR =>
			(nil, newloc) := mrep.fieldval("location");
			if(newloc == "") {
				e := W->getdata(io, mrep, accept, u);
				if(e != "")
					mrep = W->usererr(r, e);
				else
					W->okprefix(r, mrep);
			}
			else {
				if(cacheit)
					cachewrite(c, mrep, u, resptime);
				if(method == "POST") {
					# this is called "erroneous behavior of some
					# HTTP 1.0 clients" in the HTTP 1.1 spec,
					# but servers out there rely on this...
					method = "GET";
				}
				oldu := u;
				u = U->makeurl(newloc);
				u.frag = "";
				u.makeabsolute(oldu);
				W->log(c, "http: redirect to " + u.tostring());
				if(io != nil) {
					B->io.close();
					io = nil;
				}
				redir = 1;
			}
		HTMLERR =>
			if(cacheit)
				cachewrite(c, mrep, u, resptime);
			if(conttype == "text/html" && htmlok(accept)) {
				e := W->getdata(io, mrep, accept, u);
				if(e != "")
					mrep = W->usererr(r, responses[i].name);
				else
					W->okprefix(r, mrep);
			}
			else
				mrep = W->usererr(r, responses[i].name);
		}
	}
	if(io != nil)
		B->io.close();
	if(nredir == MAXREDIR)
		mrep = W->usererr(r, "redirect loop");
	if(mrep != nil) {
		W->log(c, "http: reply ready for " + r.reqid + ": " + mrep.prefixline);
		r.reply = mrep;
		donec <-= c;
	}
}

getcode(status: string) : int
{
	(vers, scode) := S->splitl(status, " ");
	scode = S->drop(scode, " ");
	return int scode;
}

htmlok(accept: string) : int
{
	(nil,y) := S->splitstrl(accept, "text/html");
	return (y != "");
}

mkhtml(msg: string) : ref Msg
{
	m := Msg.newmsg();
	m.body = array of byte sys->sprint("<HTML>\n"+
			"<BODY>\n"+
			"<H1>HTTP Reported Error</H1>\n"+
			"<P>\n"+
			"The server reported an error: %s\n"+
			"</BODY>\n"+
			"</HTML>\n", msg);
	m.bodylen = len m.body;
	m.update("content-type", "text/html");
	m.update("content-location", "webget-internal-message");
	return m;
}

cacheread(c: ref Fid, u: ref Url->ParsedUrl, r: ref Req) : (ref Msg, string)
{
	ctl := r.cachectl;
	if(ctl == "no-cache")
		return (nil, "");
	uname := u.tostring();
	hname := hashname(uname);
	io := B->open(hname, sys->OREAD);
	if(io == nil)
		return (nil, "");
	(mrep, e) := Msg.readhdr(io, 1);
	if(e != "") {
		B->io.close();
		return (nil, "");
	}

	# see if cache validation is necessary
	validate := "";
	cmaxstale := 0;
	cmaxage := -1;
	(nl, l) := sys->tokenize(ctl, ",");
	for(i := 0; i < nl; i++) {
		s := hd l;
		if(S->prefix("max-stale=", s))
			cmaxstale = int s[10:];
		else if (S->prefix("max-age=", s))
			cmaxage = int s[8:];
		l = tl l;
	}
	# we wrote x-resp-time and x-url, so they should be there
	(srst, sresptime) := mrep.fieldval("x-resp-time");
	(su, surl) := mrep.fieldval("x-url");
	if(!srst || !su) {
		cacheremove(hname);
		B->io.close();
		return (nil, "");
	}
	if(surl != uname) {
		B->io.close();
		return (nil, "");
	}
	(se, sexpires) := mrep.fieldval("expires");
	(sd, sdate) := mrep.fieldval("date");
	(slm, slastmod) := mrep.fieldval("last-modified");
	(sa, sage) := mrep.fieldval("age");

	# calculate response age (in seconds), as of time received
	respt := int sresptime;
	datet := D->date2sec(sdate);
	nowt := D->now();

	age := nowt - respt;
	if(sa)
		age += (int sage);
	freshness_lifetime := 0;
	(sma, smaxage) := mrep.fieldval("max-age");
	if(sma)
		freshness_lifetime = int smaxage;
	else if(sd && se) {
		exp := D->date2sec(sexpires);
		freshness_lifetime = exp - datet;
	}
	else if(slm){
		# use heuristic: 10% of time since last modified
		lastmod := D->date2sec(slastmod);
		if(lastmod == 0)
			lastmod = respt;
		freshness_lifetime = (nowt - lastmod) / 10;
	}
	if(age - freshness_lifetime > cmaxstale ||
	   (cmaxage != -1 && age >= cmaxage)) {
		W->log(c, sys->sprint("must revalidate, age=%d, lifetime=%d, cmaxstale=%d, cmaxage=%d\n",
				age, freshness_lifetime, cmaxstale, cmaxage));
		if(slm)
			validate = slastmod;
		else
			return (nil, "");
	}
	e = mrep.readbody(io);
	B->io.close();
	if(e != "") {
		cacheremove(hname);
		return (nil, "");
	}
	if(validate == "")
		W->log(c, "cache hit " + hname);
	else
		W->log(c, "cache hit " + hname + " if not modified after " + validate);
	return (mrep, validate);
}

cachewrite(c: ref Fid, m: ref Msg, u: ref Url->ParsedUrl, respt: int)
{
	(sp, spragma) := m.fieldval("pragma");
	if(sp && spragma == "no-cache")
		return;
	(scc, scachectl) := m.fieldval("cache-control");
	if(scc) {
		(snc, nil) := attrval(scachectl, "no-cache");
		(sns, nil) := attrval(scachectl, "no-store");
		(smv, nil) := attrval(scachectl, "must-revalidate");
		if(snc || sns || smv)
			return;
	}
	uname := u.tostring();
	hname := hashname(uname);
	m.update("x-resp-time", string respt);
	m.update("x-url", uname);
	m.update("content-length", string m.bodylen);
	io := B->create(hname, sys->OWRITE, 8r666);
	if(io != nil) {
		W->log(c, "cache writeback to " + hname);
		m.writemsg(io);
		B->io.close();
	}
}

cacheremove(hname: string)
{
	sys->remove(hname);
}

attrval(avs, aname: string) : (int, string)
{
	(nl, l) := sys->tokenize(avs, ",");
	for(i := 0; i < nl; i++) {
		s := hd l;
		(lh, rh) := S->splitl(s, "=");
		lh = trim(lh);
		if(lh == aname) {
			if(rh != "")
				rh = trim(rh[1:]);
			return (1, rh);
		}
		l = tl l;
	}
	return (0, "");
}

trim(s: string) : string
{
	is := 0;
	ie := len s;
	while(is < ie) {
		if(!S->in(s[is], " \t\n\r"))
			break;
		is++;
	}
	if(is == ie)
		return "";
	if(s[is] == '"')
		is++;
	while(ie > is) {
		if(!S->in(s[ie-1], " \t\n\r"))
			break;
		ie--;
	}
	if(is >= ie)
		return "";
	return s[is:ie];
}

hashname(uname: string) : string
{
	hash := 0;
	prime: con 8388617;
	# start after "http:"
	for(i := 5; i < len uname; i++) {
		hash = hash % prime;
		hash = (hash << 7) + uname[i];
	}
	return sys->sprint(cachedir + "/%.8ux", hash); 
}
