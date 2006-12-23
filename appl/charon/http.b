implement Transport;

include "common.m";
include "transport.m";
include "date.m";

#D: Date;
# sslhs: SSLHS;
ssl3: SSL3;
Context: import ssl3;
# Inferno supported cipher suites:
ssl_suites := array [] of {
	byte 0, byte 16r03,	# RSA_EXPORT_WITH_RC4_40_MD5
	byte 0, byte 16r04,	# RSA_WITH_RC4_128_MD5
	byte 0, byte 16r05,	# RSA_WITH_RC4_128_SHA
	byte 0, byte 16r06,	# RSA_EXPORT_WITH_RC2_CBC_40_MD5
	byte 0, byte 16r07,	# RSA_WITH_IDEA_CBC_SHA
	byte 0, byte 16r08,	# RSA_EXPORT_WITH_DES40_CBC_SHA
	byte 0, byte 16r09,	# RSA_WITH_DES_CBC_SHA
	byte 0, byte 16r0A,	# RSA_WITH_3DES_EDE_CBC_SHA
	
	byte 0, byte 16r0B,	# DH_DSS_EXPORT_WITH_DES40_CBC_SHA
	byte 0, byte 16r0C,	# DH_DSS_WITH_DES_CBC_SHA
	byte 0, byte 16r0D,	# DH_DSS_WITH_3DES_EDE_CBC_SHA
	byte 0, byte 16r0E,	# DH_RSA_EXPORT_WITH_DES40_CBC_SHA
	byte 0, byte 16r0F,	# DH_RSA_WITH_DES_CBC_SHA
	byte 0, byte 16r10,	# DH_RSA_WITH_3DES_EDE_CBC_SHA
	byte 0, byte 16r11,	# DHE_DSS_EXPORT_WITH_DES40_CBC_SHA
	byte 0, byte 16r12,	# DHE_DSS_WITH_DES_CBC_SHA
	byte 0, byte 16r13,	# DHE_DSS_WITH_3DES_EDE_CBC_SHA
	byte 0, byte 16r14,	# DHE_RSA_EXPORT_WITH_DES40_CBC_SHA
	byte 0, byte 16r15,	# DHE_RSA_WITH_DES_CBC_SHA
	byte 0, byte 16r16,	# DHE_RSA_WITH_3DES_EDE_CBC_SHA
	
	byte 0, byte 16r17,	# DH_anon_EXPORT_WITH_RC4_40_MD5
	byte 0, byte 16r18,	# DH_anon_WITH_RC4_128_MD5
	byte 0, byte 16r19,	# DH_anon_EXPORT_WITH_DES40_CBC_SHA
	byte 0, byte 16r1A,	# DH_anon_WITH_DES_CBC_SHA
	byte 0, byte 16r1B,	# DH_anon_WITH_3DES_EDE_CBC_SHA
	
	byte 0, byte 16r1C,	# FORTEZZA_KEA_WITH_NULL_SHA
	byte 0, byte 16r1D,	# FORTEZZA_KEA_WITH_FORTEZZA_CBC_SHA
	byte 0, byte 16r1E,	# FORTEZZA_KEA_WITH_RC4_128_SHA
};

ssl_comprs := array [] of {byte 0};

# local copies from CU
sys: Sys;
U: Url;
	Parsedurl: import U;
S: String;
C: Ctype;
T: StringIntTab;
CU: CharonUtils;
	Netconn, ByteSource, Header, config, Nameval : import CU;

ctype: array of byte;	# local copy of C->ctype

HTTPD:		con 80;		# Default IP port
HTTPSD:		con 443;	# Default IP port for HTTPS

# For Inferno, won't be able to read more than this at one go anyway
BLOCKSIZE:	con 1460;

# HTTP/1.1 Spec says 5, but we've seen more than that in non-looping redirs
# MAXREDIR:	con 10;

# tstate bits
THTTP_1_0, TPersist, TProxy, TSSL: con (1<<iota);

# Header fields (in order: general, request, response, entity)
HCacheControl, HConnection, HDate, HPragma, HTransferEncoding,
	HUpgrade, HVia,
	HKeepAlive, # extension
HAccept, HAcceptCharset, HAcceptEncoding, HAcceptLanguage,
	HAuthorization, HExpect, HFrom, HHost, HIfModifiedSince,
	HIfMatch, HIfNoneMatch, HIfRange, HIfUnmodifiedSince,
	HMaxForwards, HProxyAuthorization, HRange, HReferer,
	HUserAgent,
	HCookie, # extension
HAcceptRanges, HAge, HLocation, HProxyAuthenticate, HPublic,
	HRetryAfter, HServer, HSetProxy, HVary, HWarning,
	HWWWAuthenticate,
	HContentDisposition, HSetCookie, HRefresh, # extensions
	HWindowTarget, HPICSLabel, # more extensions
HAllow, HContentBase, HContentEncoding, HContentLanguage,
	HContentLength, HContentLocation, HContentMD5,
	HContentRange, HContentType, HETag, HExpires,
	HLastModified,
	HXReqTime, HXRespTime, HXUrl, # our extensions, for cached entities
	NumHfields: con iota;

# (track above enumeration)
hdrnames := array[] of {
	"Cache-Control",
	"Connection",
	"Date",
	"Pragma",
	"Transfer-Encoding",
	"Upgrade",
	"Via",
	"Keep-Alive",
	"Accept",
	"Accept-Charset",
	"Accept-Encoding",
	"Accept-Language",
	"Authorization",
	"Expect",
	"From",
	"Host", 
	"If-Modified-Since",
	"If-Match",
	"If-None-Match",
	"If-Range",
	"If-Unmodified-Since",
	"Max-Forwards",
	"Proxy-Authorization",
	"Range",
	"Refererer",
	"User-Agent",
	"Cookie",
	"Accept-Ranges",
	"Age", 
	"Location",
	"Proxy-Authenticate",
	"Public",
	"Retry-After",
	"Server",
	"Set-Proxy",
	"Vary",
	"Warning",
	"WWW-Authenticate",
	"Content-Disposition",
	"Set-Cookie",
	"Refresh",
	"Window-Target",
	"PICS-Label",
	"Allow", 
	"Content-Base", 
	"Content-Encoding",
	"Content-Language",
	"Content-Length",
	"Content-Location",
	"Content-MD5",
	"Content-Range",
	"Content-Type",
	"ETag",
	"Expires",
	"Last-Modified",
	"X-Req-Time",
	"X-Resp-Time",
	"X-Url"
};

# For fast lookup; track above, and keep sorted and lowercase
hdrtable := array[] of { T->StringInt
	("accept", HAccept),
	("accept-charset", HAcceptCharset),
	("accept-encoding", HAcceptEncoding),
	("accept-language", HAcceptLanguage),
	("accept-ranges", HAcceptRanges),
	("age", HAge),
	("allow", HAllow),
	("authorization", HAuthorization),
	("cache-control", HCacheControl),
	("connection", HConnection),
	("content-base", HContentBase),
	("content-disposition", HContentDisposition),
	("content-encoding", HContentEncoding),
	("content-language", HContentLanguage),
	("content-length", HContentLength),
	("content-location", HContentLocation),
	("content-md5", HContentMD5),
	("content-range", HContentRange),
	("content-type", HContentType),
	("cookie", HCookie),
	("date", HDate),
	("etag", HETag),
	("expect", HExpect),
	("expires", HExpires),
	("from", HFrom),
	("host", HHost),
	("if-modified-since", HIfModifiedSince),
	("if-match", HIfMatch),
	("if-none-match", HIfNoneMatch),
	("if-range", HIfRange),
	("if-unmodified-since", HIfUnmodifiedSince),
	("keep-alive", HKeepAlive),
	("last-modified", HLastModified),
	("location", HLocation),
	("max-forwards", HMaxForwards),
	("pics-label", HPICSLabel),
	("pragma", HPragma),
	("proxy-authenticate", HProxyAuthenticate),
	("proxy-authorization", HProxyAuthorization),
	("public", HPublic),
	("range", HRange),
	("referer", HReferer),
	("refresh", HRefresh),
	("retry-after", HRetryAfter),
	("server", HServer),
	("set-cookie", HSetCookie),
	("set-proxy", HSetProxy),
	("transfer-encoding", HTransferEncoding),
	("upgrade", HUpgrade),
	("user-agent", HUserAgent),
	("vary", HVary),
	("via", HVia),
	("warning", HWarning),
	("window-target", HWindowTarget),
	("www-authenticate", HWWWAuthenticate),
	("x-req-time", HXReqTime),
	("x-resp-time", HXRespTime),
	("x-url", HXUrl)
};

HTTP_Header: adt {
	startline: string;

	# following four fields only filled in if this is a response header
	protomajor: int;
	protominor: int;
	code: int;
	reason: string;
	iossl: int; # true for ssl 

	vals: array of string;
	cookies: list of string;

	new: fn() : ref HTTP_Header;
 	read: fn(h: self ref HTTP_Header, fd: ref sys->FD, sslx: ref SSL3->Context, buf: array of byte) : (string, int, int);
 	write: fn(h: self ref HTTP_Header, fd: ref sys->FD, sslx: ref SSL3->Context) : int;
	usessl: fn(h: self ref HTTP_Header);
	addval: fn(h: self ref HTTP_Header, key: int, val: string);
	getval: fn(h: self ref HTTP_Header, key: int) : string;
};

mediatable: array of T->StringInt;

agent : string;
dbg := 0;
warn := 0;
sptab : con " \t";

init(cu: CharonUtils)
{
	CU = cu;
	sys = load Sys Sys->PATH;
	S = load String String->PATH;
	U = load Url Url->PATH; 
	if (U != nil)
		U->init();
	C = cu->C;
	T = load StringIntTab StringIntTab->PATH;
#	D = load Date CU->loadpath(Date->PATH);
#	if (D == nil)
#		CU->raise(sys->sprint("EXInternal: can't load Date: %r"));
#	D->init(cu);
	ctype = C->ctype;
	# sslhs = nil;	# load on demand
	ssl3 = nil; # load on demand
	mediatable = CU->makestrinttab(CU->mnames);
	agent = (CU->config).agentname;
	dbg = int (CU->config).dbg['n'];
	warn = dbg || int (CU->config).dbg['w'];
}

connect(nc: ref Netconn, bs: ref ByteSource)
{
	if(nc.scheme == "https")
		nc.tstate |= TSSL;
	if(config.httpminor == 0)
		nc.tstate |= THTTP_1_0;
	dialhost := nc.host;
	dialport := string nc.port;
	if(nc.scheme != "https" && config.httpproxy != nil && need_proxy(nc.host)) {
		nc.tstate |= TProxy;
		dialhost = config.httpproxy.host;
		if(config.httpproxy.port != "")
			dialport = config.httpproxy.port;
	}
	addr := "tcp!" + dialhost + "!" + dialport;
	err := "";
	if(dbg)
		sys->print("http %d: dialing %s\n", nc.id, addr);
	rv: int;
	(rv, nc.conn) = sys->dial(addr, nil);
	if(rv < 0) {
		syserr := sys->sprint("%r");
		if(S->prefix("cs: dialup", syserr))
			err = syserr[4:];
		else if(S->prefix("cs: dns: no translation found", syserr))
			err = "unknown host";
		else
			err = sys->sprint("couldn't connect: %s", syserr);
	}
	else {
		if(dbg)
			sys->print("http %d: connected\n", nc.id);
		if(nc.tstate&TSSL) {
			#if(sslhs == nil) {
			#	sslhs = load SSLHS SSLHS->PATH;
			#	if(sslhs == nil)
			#		err = sys->sprint("can't load SSLHS: %r");
			#	else
			#		sslhs->init(2);
			#}
			#if(err == "")
			#	(err, nc.conn) = sslhs->client(nc.conn.dfd, addr);
			if(nc.tstate&TProxy) # tunelling SSL through proxy
				err = tunnel_ssl(nc);
	 		vers := 0;
 			if(err == "") {
				if(ssl3 == nil) {
	 				m := load SSL3 SSL3->PATH;
 					if(m == nil)
 						err = "can't load SSL3 module";
					else if((err = m->init()) == nil)
						ssl3 = m;
				}
				if(config.usessl == CU->NOSSL)
					err = "ssl is configured off";
				else if((config.usessl & CU->SSLV23) == CU->SSLV23)
					vers = 23;
	 			else if(config.usessl & CU->SSLV2)
					vers = 2;
	 			else if(config.usessl & CU->SSLV3)
					vers = 3;
			}
 			if(err == "") {
 				nc.sslx = ssl3->Context.new();
 				if(config.devssl)
 					nc.sslx.use_devssl();
 				info := ref SSL3->Authinfo(ssl_suites, ssl_comprs, nil, 
 						0, nil, nil, nil);
vers = 3;
 				(err, nc.vers) =  nc.sslx.client(nc.conn.dfd, addr, vers, info);
 			}
		}
	}
	if(err == "") {
		nc.connected = 1;
		nc.state = CU->NCgethdr;
	}
	else {
		if(dbg)
			sys->print("http %d: connection failed: %s\n", nc.id, err);
		bs.err = err;
#constate("connect", nc.conn);
		closeconn(nc);
	}
}

constate(msg: string, conn: Sys->Connection)
{
	fd := conn.dfd;
	fdfd := -1;
	if (fd != nil)
		fdfd = fd.fd;
	sys->print("connstate(%s, %d) ", msg, fdfd);
	sfd := sys->open(conn.dir + "/status", Sys->OREAD);
	if (sfd == nil) {
		sys->print("cannot open %s/status: %r\n", conn.dir);
		return;
	}
	buf := array [1024] of byte;
	n := sys->read(sfd, buf, len buf);
	s := sys->sprint("error: %r");
	if (n > 0)
		s = string buf[:n];
	sys->print("%s status: %s\n", conn.dir, s);
}

tunnel_ssl(nc: ref Netconn) : string
{
	httpvers: string;
	if(nc.state&THTTP_1_0)
		httpvers = "1.0";
	else
		httpvers = "1.1";
	req := "CONNECT " + nc.host + ":" + string nc.port + " HTTP/" + httpvers;
 	n := sys->fprint(nc.conn.dfd, "%s\r\n\r\n", req);
	if(n < 0)
		return sys->sprint("proxy: %r");
	buf := array [Sys->ATOMICIO] of byte;
	n = sys->read(nc.conn.dfd, buf, Sys->ATOMICIO);
	if(n < 0)
		return sys->sprint("proxy: %r");;
	resp := string buf[0:n];
	(m, s) := sys->tokenize(resp, " ");

	if(m < 2)
		return "proxy: " + resp;
	if(hd tl s != "200"){
		(nil, e) := sys->tokenize(resp, "\n\r");
		return hd e;
	}
	return "";
}

need_proxy(h: string) : int
{
	doms := config.noproxydoms;
	lh := len h;
	for(; doms != nil; doms = tl doms) {
		dom := hd doms;
		ld := len dom;
		if(lh >= ld && h[lh-ld:] == dom)
			return 0; # domain is on the no proxy list
	}
	return 1;
}

writereq(nc: ref Netconn, bs: ref ByteSource)
{
	#
	# Prepare the request
	#
	req := bs.req;
	u := ref *req.url;
	requ, httpvers: string;
	#if(nc.tstate&TProxy)
	if((nc.tstate&TProxy) && !(nc.tstate&TSSL)) {
		u.frag = nil;
		requ = u.tostring();
	} else {
		requ = u.path;
		if(u.query != "")
			requ += "?" + u.query;
	}
	if(nc.tstate&THTTP_1_0)
		httpvers = "1.0";
	else
		httpvers = "1.1";
	reqhdr := HTTP_Header.new();
 	if(nc.tstate&TSSL)
 		reqhdr.usessl();
	reqhdr.startline = CU->hmeth[req.method] + " " +  requ + " HTTP/" + httpvers;
	if(u.port != "")
		reqhdr.addval(HHost, u.host+ ":" + u.port);
	else
		reqhdr.addval(HHost, u.host);
	reqhdr.addval(HUserAgent, agent);
	reqhdr.addval(HAccept, "*/*; *");
#	if(cr != nil && (cr.status == CRRevalidate || cr.status == CRMustRevalidate)) {
#		if(cr.etag != "")
#			reqhdr.addval(HIfNoneMatch, cr.etag);
#		else
#			reqhdr.addval(HIfModifiedSince, D->dateconv(cr.notafter));
#	}
	if(req.auth != "")
		reqhdr.addval(HAuthorization, "Basic " + req.auth);
	if(req.method == CU->HPost) {
		reqhdr.addval(HContentLength, string (len req.body));
		reqhdr.addval(HContentType, "application/x-www-form-urlencoded");
	}
        if((CU->config).docookies > 0) {
                cookies := CU->getcookies(u.host, u.path, nc.tstate&TSSL);
		if (cookies != nil)
                       reqhdr.addval(HCookie, cookies);
        }
	#
	# Issue the request
	#
	err := "";
	if(dbg > 1) {
		sys->print("http %d: writing request:\n", nc.id);
		reqhdr.write(sys->fildes(1), nil);
	}
	rv := reqhdr.write(nc.conn.dfd, nc.sslx);
	if(rv >= 0 && req.method == CU->HPost) {
		if(dbg > 1)
			sys->print("http %d: writing body:\n%s\n", nc.id, string req.body);
 		if((nc.tstate&TSSL) && nc.sslx != nil)
 			rv = nc.sslx.write(req.body, len req.body);
 		else
 			rv = sys->write(nc.conn.dfd, req.body, len req.body);
	}
	if(rv < 0) {
		err = sys->sprint("error writing to host: %r");
#constate("writereq", nc.conn);
	}
	if(err != "") {
		if(dbg)
			sys->print("http %d: error: %s", nc.id, err);
		bs.err = err;
		closeconn(nc);
	}
}


gethdr(nc: ref Netconn, bs: ref ByteSource)
{
	resph := HTTP_Header.new();
 	if(nc.tstate&TSSL)
 		resph.usessl();
	hbuf := array[8000] of byte;
 	(err, i, j) := resph.read(nc.conn.dfd, nc.sslx, hbuf);
	if(err != "") {
#constate("gethdr", nc.conn);
		if(!(nc.tstate&THTTP_1_0)) {
			# try switching to http 1.0
			if(dbg)
				sys->print("http %d: switching to HTTP/1.0\n", nc.id);
			nc.tstate |= THTTP_1_0;
		}
	}
	else {
		if(dbg) {
			sys->print("http %d: got response header:\n", nc.id);
			resph.write(sys->fildes(1), nil);
			sys->print("http %d: %d bytes remaining from read\n", nc.id, j-i);
		}
		if(resph.protomajor == 1) {
			if(!(nc.tstate&THTTP_1_0) && resph.protominor == 0) {
				nc.tstate |= THTTP_1_0;
				if(dbg)
					sys->print("http %d: switching to HTTP/1.0\n", nc.id);
			}
		}
		else if(warn)
			sys->print("warning: unimplemented major protocol %d.%d\n",
				resph.protomajor, resph.protominor);
		if(j > i)
			nc.tbuf = hbuf[i:j];
		else
			nc.tbuf = nil;
		bs.hdr = hdrconv(resph, bs.req.url);
		if(bs.hdr.length == 0 && (nc.tstate&THTTP_1_0))
			closeconn(nc);
	}
	if(err != "") {
		if(dbg)
			sys->print("http %d: error %s\n", nc.id, err);
		bs.err = err;
		closeconn(nc);
	}
}

# returns number of bytes transferred to bs.data
# 0 => EOF
# -1 => error
getdata(nc: ref Netconn, bs: ref ByteSource): int
{
	if (bs.data == nil || bs.edata >= len bs.data) {
		if(nc.tstate&THTTP_1_0) {
			# hmm - when do non-eof'd HTTP1.1 connections close?
			closeconn(nc);
		}
		return 0;
	}
	buf := bs.data[bs.edata:];
	n := len buf;
	if (nc.tbuf != nil) {
		# initial overread of header
		if (n >= len nc.tbuf) {
			n = len nc.tbuf;
			buf[:] = nc.tbuf;
			nc.tbuf = nil;
			return n;
		}
		buf[:] = nc.tbuf[:n];
		nc.tbuf = nc.tbuf[n:];
		return n;
	}
	if ((nc.tstate&TSSL) && nc.sslx != nil) 
		n = nc.sslx.read(buf, n);
	else
		n = sys->read(nc.conn.dfd, buf, n);
	if(dbg > 1)
		sys->print("http %d: read %d bytes\n", nc.id, n);
	if (n <= 0) {
#constate("getdata", nc.conn);
		closeconn(nc);
		if(n < 0)
			bs.err = sys->sprint("%r");
	}
#else
#sys->write(sys->fildes(1), buf[:n], n);
	return n;
 }

#getdata(nc: ref Netconn, bs: ref ByteSource)
#{
#	buf := bs.data;
#	n := 0;
#	if(nc.tbuf != nil) {
#		# initial data from overread of header
#		# Note: can have more data in nc.tbuf than was
#		# reported by the HTTP header
#		n = len nc.tbuf;
#		if (n > bs.hdr.length) {
#			n = bs.hdr.length;
#			nc.tbuf = nc.tbuf[0:n];
#		}
#		if(len buf <= n) {
#			if(warn && len buf < n)
#				sys->print("more initial data than specified length\n");
#			bs.data = nc.tbuf;
#		}
#		else
#			buf[0:] = nc.tbuf[:n];
#		nc.tbuf = nil;
#	}
#	if(n == 0) {
# 		if((nc.tstate&TSSL) && nc.sslx != nil) 
# 			n = nc.sslx.read(buf[bs.edata:], len buf - bs.edata);
# 		else
# 			n = sys->read(nc.conn.dfd, buf[bs.edata:], len buf - bs.edata);
#	}
#	if(dbg > 1)
#		sys->print("http %d: read %d bytes\n", nc.id, n);
#	if(n <= 0) {
#		closeconn(nc);
#		if(n < 0)
#			bs.err = sys->sprint("%r");
#	}
#	else {
#		bs.edata += n;
#		if(bs.edata == len buf && bs.hdr.length != 100000000) {
#			if(nc.tstate&THTTP_1_0) {
#				closeconn(nc);
#			}
#		}
#	}
#	if(bs.err != "") {
#		if(dbg)
#			sys->print("http %d: error %s\n", nc.id, bs.err);
#		closeconn(nc);
#	}
#}

hdrconv(hh: ref HTTP_Header, u: ref Parsedurl) : ref Header
{
	hdr := Header.new();
	hdr.code = hh.code;
	hdr.actual = u;
	s := hh.getval(HContentBase);
	if(s != "")
		hdr.base = U->parse(s);
	else
		hdr.base = hdr.actual;
	s = hh.getval(HLocation);
	if(s != "")
		hdr.location = U->parse(s);
	s = hh.getval(HContentLength);
	if(s != "")
		hdr.length = int s;
	else
		hdr.length = -1;
	s = hh.getval(HContentType);
	if(s != "")
		setmtype(hdr, s);
	hdr.msg = hh.reason;
	hdr.refresh = hh.getval(HRefresh);
	hdr.chal = hh.getval(HWWWAuthenticate);
	s = hh.getval(HContentEncoding);
	if(s != "") {
		if(warn)
			sys->print("warning: unhandled content encoding: %s\n", s);
		# force "save as" dialog
		hdr.mtype = CU->UnknownType;
	}
	hdr.warn = hh.getval(HWarning);
	hdr.lastModified = hh.getval(HLastModified);
        if((CU->config).docookies > 0) {
		for (ckl := hh.cookies; ckl != nil; ckl = tl ckl)
			CU->setcookie(u.host, u.path, hd ckl);
	}
	return hdr;
}

# Set hdr's media type and chset (if a text type).
# If can't set media type, leave it alone (caller will guess).
setmtype(hdr: ref CU->Header, s: string)
{
	(ty, parms) := S->splitl(S->tolower(s), ";");
	(fnd, val) := T->lookup(mediatable, trim(ty));
	if(fnd) {
		hdr.mtype = val;
		if(len parms > 0 && val >= CU->TextCss && val <= CU->TextXml) {
			nvs := Nameval.namevals(parms[1:], ';');
			s: string;
			(fnd, s) = Nameval.find(nvs, "charset");
			if(fnd)
				hdr.chset = s;
		}
	}
	else {
		if(warn)
			sys->print("warning: unknown media type in %s\n", s);
	}
}

# Remove leading and trailing whitespace from s.
trim(s: string) : string
{
	is := 0;
	ie := len s;
	while(is < ie) {
		if(ctype[s[is]] != C->W)
			break;
		is++;
	}
	if(is == ie)
		return "";
	while(ie > is) {
		if(ctype[s[ie-1]] != C->W)
			break;
		ie--;
	}
	if(is >= ie)
		return "";
	if(is == 0 && ie == len s)
		return s;
	return s[is:ie];
}

# If s is in double quotes, remove them
remquotes(s: string) : string
{
	n := len s;
	if(n >= 2 && s[0] == '"' && s[n-1] == '"')
		return s[1:n-1];
	return s;
}

HTTP_Header.new() : ref HTTP_Header
{
	return ref HTTP_Header("", 0, 0, 0, "", 0, array[NumHfields] of { * => "" }, nil);
}

HTTP_Header.usessl(h: self ref HTTP_Header)
{
 	h.iossl = 1;
}

HTTP_Header.addval(h: self ref HTTP_Header, key: int, val: string)
{
	if (key == HSetCookie) {
		h.cookies = val :: h.cookies;
		return;
	}
	oldv := h.vals[key];
	if(oldv != "") {
		# check that hdr type allows list of things
		case key {
		HAccept or HAcceptCharset or HAcceptEncoding
		or HAcceptLanguage or HAcceptRanges
		or HCacheControl or HConnection or HContentEncoding
		or HContentLanguage or HIfMatch or HIfNoneMatch
		or HPragma or HPublic or HUpgrade or HVia
		or HWarning or HWWWAuthenticate or HExpect =>
			val = oldv + ", " + val;
		HCookie =>
			val = oldv + "; " + val;
		* =>
			if(warn)
				sys->print("warning: multiple %s headers not allowed\n", hdrnames[key]);
		}
	}
	h.vals[key] = val;
}

HTTP_Header.getval(h: self ref HTTP_Header, key: int) : string
{
	return h.vals[key];
}

# Read into supplied buf.
# Returns (ok, start of non-header bytes, end of non-header bytes)
# If bytes > 127 appear, assume Latin-1
#
# Header values added will always be trimmed (see trim() above).
HTTP_Header.read(h: self ref HTTP_Header, fd: ref sys->FD, sslx: ref SSL3->Context, buf: array of byte) : (string, int, int)
{
	i := 0;
	j := 0;
	aline : array of byte = nil;
	eof := 0;
 	if(h.iossl && sslx != nil) {
 		(aline, eof, i, j) = ssl_getline(sslx, buf, i, j);
 	}
 	else {
 		(aline, eof, i, j) = CU->getline(fd, buf, i, j);
 	}
	if(aline == nil) {
		return ("header read got immediate eof", 0, 0);
	}
	h.startline = latin1tostring(aline);
	if(dbg > 1)
		sys->print("header read, startline=%s\n", h.startline);
	(vers, srest) := S->splitl(h.startline, " ");
	if(len srest > 0)
		srest = srest[1:];
	(scode, reason) := S->splitl(srest, " ");
	ok := 1;
	if(len vers >= 8 && vers[0:5] == "HTTP/") {
		(smaj, vrest) := S->splitl(vers[5:], ".");
		if(smaj == "" || len vrest <= 1)
			ok = 0;
		else {
			h.protomajor = int smaj;
			if(h.protomajor < 1)
				ok = 0;
			else
				h.protominor = int vrest[1:];
		}
		if(len scode != 3)
			ok = 0;
		else {
			h.code = int scode;
			if(h.code < 100)
				ok = 0;
		}
		if(len reason > 0)
			reason = reason[1:];
		h.reason = reason;
	}
	else
		ok = 0;
	if(!ok)
		return (sys->sprint("header read failed to parse start line '%s'\n", string aline), 0, 0);
	
	prevkey := -1;
	while(len aline > 0) {
 		if(h.iossl && sslx != nil) {
 			(aline, eof, i, j) = ssl_getline(sslx, buf, i, j);
 		}
 		else {
 			(aline, eof, i, j) = CU->getline(fd, buf, i, j);
 		}
		if(eof)
			return ("header doesn't end with blank line", 0, 0);
		if(len aline == 0)
			break;
		line := latin1tostring(aline);
		if(dbg > 1)
			sys->print("%s\n", line);
		if(ctype[line[0]] == C->W) {
			if(prevkey < 0) {
				if(warn)
					sys->print("warning: header continuation line at beginning: %s\n", line);
			}
			else
				h.vals[prevkey] = h.vals[prevkey] + " " + trim(line);
		}
		else {
			(nam, val) := S->splitl(line, ":");
			if(val == nil) {
				if(warn)
					sys->print("warning: header line has no colon: %s\n", line);
			}
			else {
				(fnd, key) := T->lookup(hdrtable, S->tolower(nam));
				if(!fnd) {
					if(warn)
						sys->print("warning: unknown header field: %s\n", line);
				}
				else {
					h.addval(key, trim(val[1:]));
					prevkey = key;
				}
			}
		}
	}
	return ("", i, j);
}

# Write in big hunks.  Convert to Latin1.
# Return last sys->write return value.
HTTP_Header.write(h: self ref HTTP_Header, fd: ref sys->FD, sslx: ref SSL3->Context) : int
{
	# Expect almost all responses will fit in this sized buf
	buf := array[sys->ATOMICIO] of byte;
	i := 0;
	buflen := len buf;
	need := len h.startline + 2 + 2;
	if(need > buflen) {
		buf = CU->realloc(buf, need-buflen);
		buflen = len buf;
	}
	i = copyaslatin1(buf, h.startline, i, 1);
	for(key := 0; key < NumHfields; key++) {
		val := h.vals[key];
		if(val != "") {
			# 4 extra for this line, 2 for final cr/lf
			need = len val + len hdrnames[key] + 4 + 2;
			if(i + need > buflen) {
				buf = CU->realloc(buf, i+need-buflen);
				buflen = len buf;
			}
			i = copyaslatin1(buf, hdrnames[key], i, 0);
			buf[i++] = byte ':';
			buf[i++] = byte ' ';
			# perhaps should break up really long lines,
			# but we aren't expecting any
			i = copyaslatin1(buf, val, i, 1);
		}
	}
	buf[i++] = byte '\r';
	buf[i++] = byte '\n';
	n := 0;
	for(k := 0; k < i; ) {
 		if(h.iossl && sslx != nil) {
 			n = sslx.write(buf[k:], i-k);
 		}
 		else {
 			n = sys->write(fd, buf[k:], i-k);
 		}
		if(n <= 0)
			break;
		k += n;
	}
	return n;
}

# For latin1tostring, so don't have to keep allocating it
lbuf := array[300] of byte;

# Assume we call this on 'lines', so they won't be too long
latin1tostring(a: array of byte) : string
{
	imax := len lbuf - 1;
	i := 0;
	n := len a;
	for(k := 0; k < n; k++) {
		b := a[k];
		if(b < byte 128)
			lbuf[i++] = b;
		else
			i += sys->char2byte(int b, lbuf, i);
		if(i >= imax) {
			if(imax > 1000) {
				if(warn)
					sys->print("warning: header line too long\n");
				break;
			}
			lbuf = CU->realloc(lbuf, 100);
			imax = len lbuf - 1;
		}
	}
	ans := string lbuf[0:i];
	return ans;
}

# Copy s into a[i:], converting to Latin1.
# Add cr/lf if addcrlf is true.
# Assume caller has checked that a has enough room.
copyaslatin1(a: array of byte, s: string, i: int, addcrlf: int) : int
{
	ns := len s;
	for(k := 0; k < ns; k++) {
		c := s[k];
		if(c < 256)
			a[i++] = byte c;
		else {
			if(warn)
				sys->print("warning: non-latin1 char in header ignored: '%c'\n", c);
		}
	}
	if(addcrlf) {
		a[i++] = byte '\r';
		a[i++] = byte '\n';
	}
	return i;
}

defaultport(scheme: string) : int
{
	if(scheme == "https")
		return HTTPSD;
	return HTTPD;
}

closeconn(nc: ref Netconn)
{
	nc.conn.dfd = nil;
	nc.conn.cfd = nil;
	nc.conn.dir = "";
	nc.connected = 0;
	nc.sslx = nil;
}

ssl_getline(sslx: ref SSL3->Context, buf: array of byte, bstart, bend: int)
	:(array of byte, int, int, int)
{
 	ans : array of byte = nil;
 	last : array of byte = nil;
 	eof := 0;
mainloop:
 	for(;;) {
 		for(i := bstart; i < bend; i++) {
 			if(buf[i] == byte '\n') {
 				k := i;
 				if(k > bstart && buf[k-1] == byte '\r')
 					k--;
 				last = buf[bstart:k];
 				bstart = i+1;
 				break mainloop;
 			}
 		}
 		if(bend > bstart)
 			ans = append(ans, buf[bstart:bend]);
 		last = nil;
 		bstart = 0;
 		bend = sslx.read(buf, len buf);
 		if(bend <= 0) {
 			eof = 1;
 			bend = 0;
 			break mainloop;
 		}
 	}
 	return (append(ans, last), eof, bstart, bend);
}
 
# Append copy of second array to first, return (possibly new)
# address of the concatenation.
append(a: array of byte, b: array of byte) : array of byte
{
 	if(b == nil)
 		return a;
 	na := len a;
 	nb := len b;
 	ans := realloc(a, nb);
 	ans[na:] = b;
 	return ans;
}
 
# Return copy of a, but incr bytes bigger
realloc(a: array of byte, incr: int) : array of byte
{
 	n := len a;
 	newa := array[n + incr] of byte;
 	if(a != nil)
 		newa[0:] = a;
 	return newa;
}

