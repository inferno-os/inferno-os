implement CharonUtils;

include "common.m";
include "transport.m";
include "date.m";
include "translate.m";

	date: Date;
	me: CharonUtils;
	sys: Sys;
	D: Draw;
	S: String;
	U: Url;
	T: StringIntTab;

Font : import D;
Parsedurl: import U;
convcs : Convcs;
trans : Translate;
	Dict : import trans;
dict : ref Dict;

NCTimeout : con 100000;		# free NC slot after 100 seconds
UBufsize : con 40*1024;		# initial buffer size for unknown lengths
UEBufsize : con 1024;		# initial buffer size for unknown lengths, error responses

botchexception := "EXInternal: ByteSource protocol botch";
bytesourceid := 0;
crlf : con "\r\n";
ctype : array of byte;	# local ref to C->ctype[]
dbgproto : int;
dbg: int;
netconnid := 0;
netconns := array[10] of ref Netconn;
sptab : con " \t";

THTTP, TFTP, TFILE, TMAX: con iota;
transports := array[TMAX] of Transport;
tpaths := array [TMAX] of {
	THTTP =>	Transport->HTTPPATH,
	TFTP =>	Transport->FTPPATH,
	TFILE =>	Transport->FILEPATH,
};

schemes := array [] of {
	("http", 	THTTP),
	("https",	THTTP),
	("ftp",	TFTP),
	("file",	TFILE),
};

ngchan : chan of (int, list of ref ByteSource, ref Netconn, chan of ref ByteSource);

# must track HTTP methods in chutils.m
# (upper-case, since that's required in HTTP requests)
hmeth = array[] of { "GET", "POST" };

# following array must track media type def in chutils.m
# keep in alphabetical order
mnames = array[] of {
	"application/msword",
	"application/octet-stream",
	"application/pdf",
	"application/postscript",
	"application/rtf",
	"application/vnd.framemaker",
	"application/vnd.ms-excel",
	"application/vnd.ms-powerpoint",
	"application/x-unknown",
	"audio/32kadpcm",
	"audio/basic",
	"image/cgm",
	"image/g3fax",
	"image/gif",
	"image/ief",
	"image/jpeg",
	"image/png",
	"image/tiff",
	"image/x-bit",
	"image/x-bit2",
	"image/x-bitmulti",
	"image/x-inferno-bit",
	"image/x-xbitmap",
	"model/vrml",
	"multipart/digest",
	"multipart/mixed",
	"text/css",
	"text/enriched",
	"text/html",
	"text/javascript",
	"text/plain",
	"text/richtext",
	"text/sgml",
	"text/tab-separated-values",
	"text/xml",
	"video/mpeg",
	"video/quicktime"
};

ncstatenames = array[] of {
	"free", "idle", "connect", "gethdr", "getdata",
	"done", "err"
};

hsnames = array[] of {
	"none", "information", "ok", "redirect", "request error", "server error"
};

hcphrase(code: int) : string
{
	ans : string;
	case code {
	HCContinue =>				ans = X("Continue", "http");
	HCSwitchProto =>			ans = X("Switching Protocols", "http");
	HCOk =>					ans = X("Ok", "http");
	HCCreated =>				ans = X("Created", "http");
	HCAccepted =>				ans = X("Accepted", "http");
	HCOkNonAuthoritative =>		ans = X("Non-Authoratative Information", "http");
	HCNoContent =>			ans = X("No content", "http");
	HCResetContent =>			ans = X("Reset content", "http");
	HCPartialContent =>			ans = X("Partial content", "http");
	HCMultipleChoices =>		ans = X("Multiple choices", "http");
	HCMovedPerm =>			ans = X("Moved permanently", "http");
	HCMovedTemp =>			ans = X("Moved temporarily", "http");
	HCSeeOther =>				ans = X("See other", "http");
	HCNotModified =>			ans = X("Not modified", "http");
	HCUseProxy =>				ans = X("Use proxy", "http");
	HCBadRequest =>			ans = X("Bad request", "http");
	HCUnauthorized =>			ans = X("Unauthorized", "http");
	HCPaymentRequired =>		ans = X("Payment required", "http");
	HCForbidden =>			ans = X("Forbidden", "http");
	HCNotFound =>			ans = X("Not found", "http");
	HCMethodNotAllowed =>		ans = X("Method not allowed", "http");
	HCNotAcceptable =>			ans = X("Not Acceptable", "http");
	HCProxyAuthRequired =>		ans = X("Proxy authentication required", "http");
	HCRequestTimeout =>		ans = X("Request timed-out", "http");
	HCConflict =>				ans = X("Conflict", "http");
	HCGone =>				ans = X("Gone", "http");
	HCLengthRequired =>		ans = X("Length required", "http");
	HCPreconditionFailed =>		ans = X("Precondition failed", "http");
	HCRequestTooLarge =>		ans = X("Request entity too large", "http");
	HCRequestURITooLarge =>	ans = X("Request-URI too large", "http");
	HCUnsupportedMedia =>		ans = X("Unsupported media type", "http");
	HCRangeInvalid =>			ans = X("Requested range not valid", "http");
	HCExpectFailed =>			ans = X("Expectation failed", "http");
	HCServerError =>			ans = X("Internal server error", "http");
	HCNotImplemented =>		ans = X("Not implemented", "http");
	HCBadGateway =>			ans = X("Bad gateway", "http");
	HCServiceUnavailable =>		ans = X("Service unavailable", "http");
	HCGatewayTimeout =>		ans = X("Gateway time-out", "http");
	HCVersionUnsupported =>	ans = X("HTTP version not supported", "http");
	HCRedirectionFailed =>		ans = X("Redirection failed", "http");
	* =>						ans = X("Unknown code", "http");
	}
	return ans;
}

# This array should be kept sorted
fileexttable := array[] of { T->StringInt
	("ai", ApplPostscript),
	("au", AudioBasic),
# ("bit", ImageXBit),
	("bit", ImageXInfernoBit),
	("bit2", ImageXBit2),
	("bitm", ImageXBitmulti),
	("eps", ApplPostscript),
	("gif", ImageGif),
	("gz",	ApplOctets),
	("htm", TextHtml),
	("html", TextHtml),
	("jpe", ImageJpeg),
	("jpeg", ImageJpeg),
	("jpg", ImageJpeg),
	("pdf", ApplPdf),
	("png", ImagePng),
	("ps", ApplPostscript),
	("shtml", TextHtml),
	("text", TextPlain),
	("tif", ImageTiff),
	("tiff", ImageTiff),
	("txt", TextPlain),
	("zip", ApplOctets)
};

# argl is command line
# Return string that is empty if all ok, else path of module
# that failed to load.
init(ch: Charon, c: CharonUtils, argl: list of string, evc: chan of ref E->Event, cksrv: Cookiesrv, ckc: ref Cookiesrv->Client) : string
{
	me = c;
	sys = load Sys Sys->PATH;
	startres = ResourceState.cur();
	D = load Draw Draw->PATH;
	CH = ch;
	S = load String String->PATH;
	if(S == nil)
		return String->PATH;

	U = load Url Url->PATH;
	if(U == nil)
		return Url->PATH;
	U->init();

	T = load StringIntTab StringIntTab->PATH;
	if(T == nil)
		return StringIntTab->PATH;

	trans = load Translate Translate->PATH;
	if (trans != nil) {
		trans->init();
		(dict, nil) = trans->opendict(trans->mkdictname(nil, "charon"));
	}

	# Now have all the modules needed to process command line
	# (hereafter can use our loadpath() function to substitute the
	# build directory version if dbg['u'] is set)

	setconfig(argl);
	dbg = int config.dbg['d'];

	G = load Gui loadpath(Gui->PATH);
	if(G == nil)
		return loadpath(Gui->PATH);

	C = load Ctype loadpath(Ctype->PATH);
	if(C == nil)
		return loadpath(Ctype->PATH);

	E = load Events Events->PATH;
	if(E == nil)
		return loadpath(Events->PATH);

	J = load Script loadpath(Script->JSCRIPTPATH);
	# don't report an error loading JavaScript, handled elsewhere

	LX = load Lex loadpath(Lex->PATH);
	if(LX == nil)
		return loadpath(Lex->PATH);

	B = load Build loadpath(Build->PATH);
	if(B == nil)
		return loadpath(Build->PATH);

	I = load Img loadpath(Img->PATH);
	if(I == nil)
		return loadpath(Img->PATH);

	L = load Layout loadpath(Layout->PATH);
	if(L == nil)
		return loadpath(Layout->PATH);
	date = load Date loadpath(Date->PATH);
	if (date == nil)
		return loadpath(Date->PATH);

	convcs = load Convcs Convcs->PATH;
	if (convcs == nil)
		return loadpath(Convcs->PATH);


	# Intialize all modules after loading all, so that each
	# may cache pointers to the other modules
	# (G will be initialized in main charon routine, and L has to
	# be inited after that, because it needs G's display to allocate fonts)

	E->init(evc);
	I->init(me);
	err := convcs->init(nil);
	if (err != nil)
		return err;
	if(J != nil) {
		err = J->init(me);
		if (err != nil) {
			# non-fatal: just don't handle javascript
			J = nil;
			if (dbg)
				sys->print("%s\n", err);
		}
	}
	B->init(me);
	LX->init(me);
	date->init(me);

	if (config.docookies) {
		CK = cksrv;
		ckclient = ckc;
		if (CK == nil) {
			path := loadpath(Cookiesrv->PATH);
			CK = load Cookiesrv path;
			if (CK == nil)
				sys->print("cookies: cannot load server %s: %r\n", path);
			else
				ckclient = CK->start(config.userdir + "/cookies", 0);
		}
	}

	# preload some transports
	gettransport("http");
	gettransport("file");

	progresschan = chan of (int, int, int, string);
	imcache = ref ImageCache;
	ctype = C->ctype;
	dbgproto = int config.dbg['p'];
	ngchan = chan of (int, list of ref ByteSource, ref Netconn, chan of ref ByteSource);
	return "";
}

# like startreq() but special case for a string ByteSource
# which doesn't need an associated netconn
stringreq(s : string) : ref ByteSource
{
	bs := ByteSource.stringsource(s);

	G->progress <-= (bs.id, G->Pstart, 0, "text");
	anschan := chan of ref ByteSource;
	ngchan <-= (NGstartreq, bs :: nil, nil, anschan);
	<-anschan;
	return bs;
}

# Make a ByteSource for given request, and make sure
# that it is on the queue of some Netconn.
# If don't have a transport for the request's scheme,
# the returned bs will have err set.
startreq(req: ref ReqInfo) : ref ByteSource
{
	bs := ref ByteSource(
			bytesourceid++,
			req,		# req
			nil,		# hdr
			nil,		# data
			0,		# edata
			"",		# err
			nil,		# net
			1,		# refgo
			1,		# refnc
			0,		# eof
			0,		# lim
			0		# seenhdr
		);

	G->progress <-= (bs.id, G->Pstart, 0, req.url.tostring());
	anschan := chan of ref ByteSource;
	ngchan <-= (NGstartreq, bs::nil, nil, anschan);
	<-anschan;
	return bs;
}

# Wait for some ByteSource in current go generation to
# have a state change that goproc hasn't seen yet.
waitreq(bsl: list of ref ByteSource) : ref ByteSource
{
	anschan := chan of ref ByteSource;
	ngchan <-= (NGwaitreq, bsl, nil, anschan);
	return <-anschan;
}

# Notify netget that goproc is finished with bs.
freebs(bs: ref ByteSource)
{
	anschan := chan of ref ByteSource;
	ngchan <-= (NGfreebs, bs::nil, nil, anschan);
	<-anschan;
}

abortgo(gopgrp: int)
{
	if(int config.dbg['d'])
		sys->print("abort go\n");
	kill(gopgrp, 1);
	freegoresources();
	# renew the channels so that receives/sends by killed threads don't
	# muck things up
	ngchan = chan of (int, list of ref ByteSource, ref Netconn, chan of ref ByteSource);
}

freegoresources()
{
	for(i := 0; i < len netconns; i++) {
		nc := netconns[i];
		nc.makefree();
	}
}

# This runs as a separate thread.
# It acts as a monitor to synchronize access to the Netconn data
# structures, as a dispatcher to start runnetconn's as needed to
# process work on Netconn queues, and as a notifier to let goproc
# know when any ByteSources have advanced their state.
netget()
{
	msg, n, i: int;
	bsl : list of ref ByteSource;
	nc: ref Netconn;
	waitix := 0;
	c : chan of ref ByteSource;
	waitpending : list of (list of ref ByteSource, chan of ref ByteSource);
	maxconn := config.nthreads;
	gncs := array[maxconn] of int;

	for(n = 0; n < len netconns; n++)
		netconns[n] = Netconn.new(n);

	# capture netget chan to prevent abortgo() reset of
	# ngchan from breaking us (channel hungup) before kill() does its job
	ngc := ngchan;
mainloop:
	for(;;) {
		(msg,bsl,nc,c) = <- ngc;
		case msg {
		NGstartreq =>
			bs := hd bsl;
			# bs has req filled in, and is otherwise in its initial state.
			# Find a suitable Netconn and add bs to its queue of work,
			# then send nil along c to let goproc continue.

			# if ReqInfo is nil then this is a string ByteSource
			# in which case we don't need a netconn to service it as we have all
			# data already
			if (bs.req == nil) {
				c <- = nil;
				continue;
			}

			if(dbgproto)
				sys->print("Startreq BS=%d for %s\n", bs.id, bs.req.url.tostring());
			scheme := bs.req.url.scheme;
			host := bs.req.url.host;
			(transport, err) := gettransport(scheme);
			if(err != "")
				bs.err = err;
			else {
				sport :=bs.req.url.port;
				if(sport == "")
					port := transport->defaultport(scheme);
				else
					port = int sport;
				i = 0;
				freen := -1;
				for(n = 0; n < len netconns && (i < maxconn || freen == -1); n++) {
					nc = netconns[n];
					if(nc.state == NCfree) {
						if(freen == -1)
							freen = n;
					}
					else if(nc.host == host
					   && nc.port == port && nc.scheme == scheme && i < maxconn) {
						gncs[i++] = n;
					}
				}
				if(i < maxconn) {
					# use a new netconn for this bs
					if(freen == -1) {
						freen = len netconns;
						newncs := array[freen+10] of ref Netconn;
						newncs[0:] = netconns;
						for(n = freen; n < freen+10; n++)
							newncs[n] = Netconn.new(n);
						netconns = newncs;
					}
					nc = netconns[freen];
					nc.host = host;
					nc.port = port;
					nc.scheme = scheme;
					nc.qlen = 0;
					nc.ngcur = 0;
					nc.gocur = 0;
					nc.reqsent = 0;
					nc.pipeline = 0;
					nc.connected = 0;
				}
				else {
					# use existing netconn with fewest outstanding requests
					nc = netconns[gncs[0]];
					if(maxconn > 1) {
						minqlen := nc.qlen - nc.gocur;
						for(i = 1; i < maxconn; i++) {
							x := netconns[gncs[i]];
							if(x.qlen-x.gocur < minqlen) {
								nc = x;
								minqlen = x.qlen-x.gocur;
							}
						}
					}
				}
				if(nc.qlen == len nc.queue) {
					nq := array[nc.qlen+10] of ref ByteSource;
					nq[0:] = nc.queue;
					nc.queue = nq;
				}
				nc.queue[nc.qlen++] = bs;
				bs.net = nc;
				if(dbgproto)
					sys->print("Chose NC=%d for BS %d, qlen=%d\n", nc.id, bs.id, nc.qlen);
				if(nc.state == NCfree || nc.state == NCidle) {
					if(nc.connected) {
						nc.state = NCgethdr;
						if(dbgproto)
							sys->print("NC %d: starting runnetconn in gethdr state\n", nc.id);
					}
					else {
						nc.state = NCconnect;
						if(dbgproto)
							sys->print("NC %d: starting runnetconn in connect state\n", nc.id);
					}
					spawn runnetconn(nc, transport);
				}
			}
			c <-= nil;

		NGwaitreq =>
			# goproc wants to be notified when some ByteSource
			# changes to a state that the goproc hasn't seen yet.
			# Send such a ByteSource along return channel c.

			if(dbgproto)
				sys->print("Waitreq\n");

			for (scanlist := bsl; scanlist != nil; scanlist = tl scanlist) {
				bs := hd scanlist;
				if (bs.refnc == 0) {
					# string ByteSource or completed or error
					if (bs.err != nil || bs.edata >= bs.lim) {
						c <-= bs;
						continue mainloop;
					}
					continue;
				}
				# netcon based bytesource
				if ((bs.hdr != nil && !bs.seenhdr && bs.hdr.mtype != UnknownType) || bs.edata > bs.lim) {
					c <-= bs;
					continue mainloop;
				}
			}

			if(dbgproto)
				sys->print("Waitpending\n");
			waitpending = (bsl, c) :: waitpending;
			
		NGfreebs =>
			# goproc is finished with bs.
			bs := hd bsl;

			if(dbgproto)
				sys->print("Freebs BS=%d\n", bs.id);
			nc = bs.net;
			bs.refgo = 0;
			if(bs.refnc == 0) {
				bs.free();
				if(nc != nil)
					nc.queue[nc.gocur] = nil;
			}
			if(nc != nil) {
				# can be nil if no transport was found
				nc.gocur++;
				if(dbgproto)
					sys->print("NC %d: gocur=%d, ngcur=%d, qlen=%d\n", nc.id, nc.gocur, nc.ngcur, nc.qlen);
				if(nc.gocur == nc.qlen && nc.ngcur == nc.qlen) {
					if(!nc.connected)
						nc.makefree();
				}
			}
			# don't need to check waitpending fro NGwait requests involving bs
			# the only thread doing a freebs() should be the only thread that
			# can do a waitreq() on the same bs.  Same thread cannot be in both states.
	
			c <-= nil;

		NGstatechg =>
			# Some runnetconn is telling us tht it changed the
			# state of nc.  Send a nil along c to let it continue.
			bs : ref ByteSource;
			if(dbgproto)
				sys->print("Statechg NC=%d, state=%s\n",
					nc.id, ncstatenames[nc.state]);
			sendtopending : ref ByteSource = nil;
			pendingchan : chan of ref ByteSource;
			if(waitpending != nil && nc.gocur < nc.qlen) {
				bs = nc.queue[nc.gocur];
				if(dbgproto) {
					totlen := 0;
					if(bs.hdr != nil)
						totlen = bs.hdr.length;
					sys->print("BS %d: havehdr=%d seenhdr=%d edata=%d lim=%d, length=%d\n",
						bs.id, bs.hdr != nil, bs.seenhdr, bs.edata, bs.lim, totlen);
					if(bs.err != "")
						sys->print ("   err=%s\n", bs.err);
				}
				if(bs.refgo &&
				   (bs.err != "" ||
				   (bs.hdr != nil && !bs.seenhdr) ||
				   (nc.gocur == nc.ngcur && nc.state == NCdone) ||
				   (bs.edata > bs.lim))) {
					nwp: list of (list of ref ByteSource, chan of ref ByteSource) = nil;
					for (waitlist := waitpending; waitlist != nil; waitlist = tl waitlist) {
						(bslist, anschan) := hd waitlist;
						if (sendtopending != nil) {
							nwp = (bslist, anschan) :: nwp;
							continue;
						}
						for (look := bslist; look != nil; look = tl look) {
							if (bs == hd look) {
								sendtopending = bs;
								pendingchan = anschan;
								break;
							}
						}
						if (sendtopending == nil)
							nwp = (bslist, anschan) :: nwp;
					}
					waitpending = nwp;
				}
			}
			if(nc.state == NCdone || nc.state == NCerr) {
				if(dbgproto)
					sys->print("NC %d: runnetconn finishing\n", nc.id);
				assert(nc.ngcur < nc.qlen);
				bs = nc.queue[nc.ngcur];
				bs.refnc = 0;
				if(bs.refgo == 0) {
					bs.free();
					nc.queue[nc.ngcur] = nil;
				}
				nc.ngcur++;
				if(dbgproto)
					sys->print("NC %d: ngcur=%d\n", nc.id, nc.ngcur);
				nc.state = NCidle;
				if(dbgproto)
					sys->print("NC %d: idle\n", nc.id);
				if(nc.ngcur < nc.qlen) {
					if(nc.connected) {
						nc.state = NCgethdr;
						if(dbgproto)
							sys->print("NC %d: starting runnetconn in gethdr state\n", nc.id);
					}
					else {
						nc.state = NCconnect;
						if(dbgproto)
							sys->print("NC %d: starting runnetconn in connect state\n", nc.id);
					}
					(t, nil) := gettransport(nc.scheme);
					spawn runnetconn(nc, t);
				}
				else if(nc.gocur == nc.qlen && !nc.connected)
					nc.makefree();
			}
			c <-= nil;
			if(sendtopending != nil) {
				if(dbgproto)
					sys->print("Send BS %d to pending waitreq\n", bs.id);
				pendingchan <-= sendtopending;
				sendtopending = nil;
			}
		}
	}
}

# A separate thread, to handle ngcur request of transport.
# If nc.gen ever goes < gen, we have aborted this go.
runnetconn(nc: ref Netconn, t: Transport)
{
	ach := chan of ref ByteSource;
	retry := 4;
#	retry := 0;
	err := "";

	assert(nc.ngcur < nc.qlen);
	bs := nc.queue[nc.ngcur];

	# dummy loop, just for breaking out of in error cases
eloop:
	for(;;) {
		# Make the connection, if necessary
		if(nc.state == NCconnect) {
			t->connect(nc, bs);
			if(bs.err != "") {
				if (retry) {
					retry--;
					bs.err = "";
					sys->sleep(100);
					continue eloop;
				}
				break eloop;
			}
			nc.state = NCgethdr;
		}
		assert(nc.state == NCgethdr && nc.connected);
		if(nc.scheme == "https")
			G->progress <-= (bs.id, G->Psslconnected, 0, "");
		else
			G->progress <-= (bs.id, G->Pconnected, 0, "");

		t->writereq(nc, bs);
		nc.reqsent++;
		if (bs.err != "") {
			if (retry) {
				retry--;
				bs.err = "";
				nc.state = NCconnect;
				sys->sleep(100);
				continue eloop;
			}
			break eloop;
		}
		# managed to write the request
		# do not retry if we are doing form POSTs	
		# See RFC1945 section 12.2 "Safe Methods"
		if (bs.req.method == HPost)
			retry = 0;

		# Get the header
		t->gethdr(nc, bs);
		if(bs.err != "") {
			if (retry) {
				retry--;
				bs.err = "";
				nc.state = NCconnect;
				sys->sleep(100);
				continue eloop;
			}
			break eloop;
		}
		assert(bs.hdr != nil);
		G->progress <-= (bs.id, G->Phavehdr, 0, "");

		nc.state = NCgetdata;

		# read enough data to guess media type
		while (bs.hdr.mtype == UnknownType && ncgetdata(t, nc, bs))
			bs.hdr.setmediatype(bs.hdr.actual.path, bs.data[:bs.edata]);
		if (bs.hdr.mtype == UnknownType) {
			bs.hdr.mtype = TextPlain;
			bs.hdr.chset = "utf8";
		}
		ngchan <-= (NGstatechg,nil,nc,ach);
		<- ach;
		while (ncgetdata(t, nc, bs)) {
			ngchan <-= (NGstatechg,nil,nc,ach);
			<- ach;
		}
		nc.state = NCdone;
		G->progress <-= (bs.id, G->Phavedata, 100, "");
		break;
	}
	if(bs.err != "") {
		nc.state = NCerr;
		nc.connected = 0;
		G->progress <-= (bs.id, G->Perr, 0, bs.err);
	}
	bs.eof = 1;
	ngchan <-= (NGstatechg, nil, nc, ach);
	<- ach;
}

ncgetdata(t: Transport, nc: ref Netconn, bs: ref ByteSource): int
{
	hdr := bs.hdr;
	if (bs.data == nil) {
		blen := hdr.length;
		if (blen <= 0) {
			if(hdr.code == HCOk || hdr.code == HCOkNonAuthoritative)
				blen = UBufsize;
			else
				blen = UEBufsize;
		}
		bs.data = array[blen] of byte;
	}
	nr := 0;
	if (hdr.length > 0) {
		if (bs.edata == hdr.length)
			return 0;
		nr = t->getdata(nc, bs);
		if (nr <= 0)
			return 0;
	} else {
		# don't know data length - keep growing input buffer as needed
		if (bs.edata == len bs.data) {
			nd := array [2*len bs.data] of byte;
			nd[:] = bs.data;
			bs.data = nd;
		}
		nr = t->getdata(nc, bs);
		if (nr <= 0) {
			# assume EOF
			bs.data = bs.data[0:bs.edata];
			bs.err = "";
			hdr.length = bs.edata;
			nc.connected = 0;
			return 0;
		}
	}
	bs.edata += nr;
	G->progress <-= (bs.id, G->Phavedata, 100*bs.edata/len bs.data, "");
	return 1;
}

Netconn.new(id: int) : ref Netconn
{
	return ref Netconn(
			id,		# id
			"",		# host
			0,		# port
			"",		# scheme
			sys->Connection(nil, nil, ""),	# conn
			nil,		# ssl context
			0,		# undetermined ssl version
			NCfree,	# state
			array[10] of ref ByteSource,	# queue
			0,		# qlen
			0,0,0,	# gocur, ngcur, reqsent
			0,		# pipeline
			0,		# connected
			0,		# tstate
			nil,		# tbuf
			0		# idlestart
			);
}

Netconn.makefree(nc: self ref Netconn)
{
	if(dbgproto)
		sys->print("NC %d: free\n", nc.id);
	nc.state = NCfree;
	nc.host = "";
	nc.conn.dfd = nil;
	nc.conn.cfd = nil;
	nc.conn.dir = "";
	nc.qlen = 0;
	nc.gocur = 0;
	nc.ngcur = 0;
	nc.reqsent = 0;
	nc.pipeline = 0;
	nc.connected = 0;
	nc.tstate = 0;
	nc.tbuf = nil;
	for(i := 0; i < len nc.queue; i++)
		nc.queue[i] = nil;
}

ByteSource.free(bs: self ref ByteSource)
{
	if(dbgproto)
		sys->print("BS %d freed\n", bs.id);
	if(bs.err == "")
		G->progress <-= (bs.id, G->Pdone, 100, "");
	else
		G->progress <-= (bs.id, G->Perr, 0, bs.err);
	bs.req = nil;
	bs.hdr = nil;
	bs.data = nil;
	bs.err = "";
	bs.net = nil;
}

# Return an ByteSource that is completely filled, from string s
ByteSource.stringsource(s: string) : ref ByteSource
{
	a := array of byte s;
	n := len a;
	hdr := ref Header(
			HCOk,		# code
			nil,			# actual
			nil,			# base
			nil,			# location
			n,			# length
			TextHtml, 	# mtype
			"utf8",		# chset
			"",			# msg
			"",			# refresh
			"",			# chal
			"",			# warn
			""			# last-modified
		);
	bs := ref ByteSource(
			bytesourceid++,
			nil,		# req
			hdr,		# hdr
			a,		# data
			n,		# edata
			"",		# err
			nil,		# net
			1,		# refgo
			0,		# refnc
			1,		# eof	- edata is final
			0,		# lim
			1		# seenhdr
		);
	return bs;
}

MaskedImage.free(mim: self ref MaskedImage)
{
	mim.im = nil;
	mim.mask = nil;
}

CImage.new(src: ref U->Parsedurl, lowsrc: ref U->Parsedurl, width, height: int) : ref CImage
{
	return ref CImage(src, lowsrc, nil, strhash(src.host + "/" + src.path), width, height, nil, nil, 0);
}

# Return true if Cimages a and b represent the same image.
# As well as matching the src urls, the specified widths and heights must match too.
# (Widths and heights are specified if at least one of those is not zero.)
#
# BUG: the width/height matching code isn't right.  If one has width and height
# specified, and the other doesn't, should say "don't match", because the unspecified
# one should come in at its natural size.  But we overwrite the width and height fields
# when the actual size comes in, so we can't tell whether width and height are nonzero
# because they were specified or because they're their natural size.
CImage.match(a: self ref CImage, b: ref CImage) : int
{
	if(a.imhash == b.imhash) {
		if(urlequal(a.src, b.src)) {
			return (a.width == 0 || b.width == 0 || a.width == b.width) &&
				(a.height == 0 || b.height == 0 || a.height == b.height);
			# (above is not quite enough: should also check that don't have
			# situation where one has width set, not height, and the other has reverse,
			# but it is unusual for an image to have a spec in only one dimension anyway)
		}
	}
	return 0;
}

# Return approximate number of bytes in image memory used
# by ci.
CImage.bytes(ci: self ref CImage) : int
{
	tot := 0;
	for(i := 0; i < len ci.mims; i++) {
		mim := ci.mims[i];
		dim := mim.im;
		if(dim != nil)
			tot += ((dim.r.max.x-dim.r.min.x)*dim.depth/8) *
					(dim.r.max.y-dim.r.min.y);
		dim = mim.mask;
		if(dim != nil)
			tot += ((dim.r.max.x-dim.r.min.x)*dim.depth/8) *
					(dim.r.max.y-dim.r.min.y);
	}
	return tot;
}

# Call this after initial windows have been made,
# so that resetlimits() will exclude the images for those
# windows from the available memory.
ImageCache.init(ic: self ref ImageCache)
{
	ic.imhd = nil;
	ic.imtl = nil;
	ic.n = 0;
	ic.memused = 0;
	ic.resetlimits();
}

# Call resetlimits when amount of non-image-cache image
# memory might have changed significantly (e.g., on main window resize).
ImageCache.resetlimits(ic: self ref ImageCache)
{
	res := ResourceState.cur();
	avail := res.imagelim - (res.image-ic.memused);
		# (res.image-ic.memused) is used memory not in image cache
	avail = 8*avail/10;	# allow 20% slop for other applications, etc.
	ic.memlimit = config.imagecachemem;
	if(ic.memlimit > avail)
		ic.memlimit = avail;
#	ic.nlimit = config.imagecachenum;
	ic.nlimit = 10000;	# let's try this
	ic.need(0);	# if resized, perhaps need to shed some images
}

# Look for a CImage matching ci, and if found, move it
# to the tail position (i.e., MRU)
ImageCache.look(ic: self ref ImageCache, ci: ref CImage) : ref CImage
{
	ans : ref CImage = nil;
	prev : ref CImage = nil;
	for(i := ic.imhd; i != nil; i = i.next) {
		if(i.match(ci)) {
			if(ic.imtl != i) {
				# remove from current place in cache chain
				# and put at tail
				if(prev != nil)
					prev.next = i.next;
				else
					ic.imhd = i.next;
				i.next = nil;
				ic.imtl.next = i;
				ic.imtl = i;
			}
			ans = i;
			break;
		}
		prev = i;
	}
	return ans;
}

# Call this to add ci as MRU of cache chain (should only call if
# it is known that a ci with same image isn't already there).
# Update ic.memused.
# Assume ic.need has been called to ensure that neither
# memlimit nor nlimit will be exceeded.
ImageCache.add(ic: self ref ImageCache, ci: ref CImage)
{
	ci.next = nil;
	if(ic.imhd == nil)
		ic.imhd = ci;
	else
		ic.imtl.next = ci;
	ic.imtl = ci;
	ic.memused += ci.bytes();
	ic.n++;
}

# Delete least-recently-used image in image cache
# and update memused and n.
ImageCache.deletelru(ic: self ref ImageCache)
{
	ci := ic.imhd;
	if(ci != nil) {
		ic.imhd = ci.next;
		if(ic.imhd == nil) {
			ic.imtl = nil;
			ic.memused = 0;
		}
		else
			ic.memused -= ci.bytes();
		for(i := 0; i < len ci.mims; i++)
			ci.mims[i].free();
		ci.mims = nil;
		ic.n--;
	}
}

ImageCache.clear(ic: self ref ImageCache)
{
	while(ic.imhd != nil)
		ic.deletelru();
}

# Call this just before allocating an Image that will used nbytes
# of image memory, to ensure that if the image were to be
# added to the image cache then memlimit and nlimit will be ok.
# LRU images will be shed if necessary.
# Return 0 if it will be impossible to make enough memory.
ImageCache.need(ic: self ref ImageCache, nbytes: int) : int
{
	while(ic.n >= ic.nlimit || ic.memused+nbytes > ic.memlimit) {
		if(ic.imhd == nil)
			return 0;
		ic.deletelru();
	}
	return 1;
}

strhash(s: string) : int
{
	prime: con 8388617;
	hash := 0;
	n := len s;
	for(i := 0; i < n; i++) {
		hash = hash % prime;
		hash = (hash << 7) + s[i];
	}
	return hash;
}

schemeid(s: string): int
{
	for (i := 0; i < len schemes; i++) {
		(n, id) := schemes[i];
		if (n == s)
			return id;
	}
	return -1;
}

schemeok(s: string): int
{
	return schemeid(s) != -1;
}

gettransport(scheme: string) : (Transport, string)
{
	err := "";
	transport: Transport = nil;
	tindex := schemeid(scheme);
	if (tindex == -1)
		return (nil, "Unknown scheme");
	transport = transports[tindex];
	if (transport == nil) {
		transport = load Transport loadpath(tpaths[tindex]);
		if(transport == nil)
			return (nil, sys->sprint("Can't load transport %s: %r", tpaths[tindex]));
		transport->init(me);
		transports[tindex] = transport;
	}
	return (transport, err);
}

# Return new Header with default values for fields
Header.new() : ref Header
{
	return ref Header(
		HCOk,		# code
		nil,		# actual
		nil,		# base
		nil,		# location
		-1,		# length
		UnknownType,	# mtype
		nil,		# chset
		"",		# msg
		"",		# refresh
		"",		# chal
		"",		# warn
		""		# last-modified
	);
}

jpmagic := array[] of {byte 16rFF, byte 16rD8, byte 16rFF, byte 16rE0,
		byte 0, byte 0, byte 'J', byte 'F', byte 'I', byte 'F', byte 0};
pngsig := array[] of { byte 137, byte 80, byte 78, byte 71, byte 13, byte 10, byte 26, byte 10 };

# Set the mtype (and possibly chset) fields of h based on (in order):
#	first bytes of file, if unambigous
#	file name extension
#	first bytes of file, even if unambigous (guess)
#	if all else fails, then leave as UnknownType.
# If it's a text type, also set the chset.
# (HTTP Transport will try to use Content-Type first, and call this if that
# doesn't work; other Transports will have to rely on this "guessing" function.)
Header.setmediatype(h: self ref Header, name: string, first: array of byte)
{
	# Look for key signatures at beginning of file (perhaps after whitespace)
	n := len first;
	mt := UnknownType;
	for(i := 0; i < n; i++)
		if(ctype[int first[i]] != C->W)
			break;
	if(n - i >= 6) {
		s := string first[i:i+6];
		case S->tolower(s) {
		"<html " or "<html\t" or "<html>" or "<head>" or "<title" =>
			mt = TextHtml;
		"<!doct" =>
			if(n - i >= 14 && string first[i+6:i+14] == "ype html")
				mt = TextHtml;
		"gif87a" or "gif89a" =>
			if(i == 0)
				mt = ImageGif;
		"#defin" =>
			# perhaps should check more definitively...
			mt = ImageXXBitmap;
		}

		if (mt == UnknownType && n > 0) {
			if (first[0] == jpmagic[0] && n >= len jpmagic) {
				for(i++; i<len jpmagic; i++)
					if(jpmagic[i]>byte 0 && first[i]!=jpmagic[i])
						break;
				if (i == len jpmagic)
					mt = ImageJpeg;
			} else if (first[0] == pngsig[0] && n >= len pngsig) {
				for(i++; i<len pngsig; i++)
					if (first[i] != pngsig[i])
						break;
				if (i == len pngsig)
					mt = ImagePng;
			}
		}
	}

	if(mt == UnknownType) {
		# Try file name extension
		(nil, file) := S->splitr(name, "/");
		if(file != "") {
			(f, ext) := S->splitr(file, ".");
			if(f != "" && ext != "") {
				(fnd, val) := T->lookup(fileexttable, S->tolower(ext));
				if(fnd)
					mt = val;
			}
		}
	}

#	if(mt == UnknownType) {
#		mt = TextPlain;
#		h.chset = "utf8";
#	}
	h.mtype = mt;
}

Header.print(h: self ref Header)
{
	mtype := "?";
	if(h.mtype >= 0 && h.mtype < len mnames)
		mtype = mnames[h.mtype];
	chset := "?";
	if(h.chset != nil)
		chset = h.chset;
	# sys->print("code=%d (%s) length=%d mtype=%s chset=%s\n",
	#	h.code, hcphrase(h.code), h.length, mtype, chset);
	if(h.base != nil)
		sys->print("  base=%s\n", h.base.tostring());
	if(h.location != nil)
		sys->print("  location=%s\n", h.location.tostring());
	if(h.refresh != "")
		sys->print("  refresh=%s\n", h.refresh);
	if(h.chal != "")
		sys->print("  chal=%s\n", h.chal);
	if(h.warn != "")
		sys->print("  warn=%s\n", h.warn);
}


mfd : ref sys->FD = nil;
ResourceState.cur() : ResourceState
{
	ms := sys->millisec();
	main := 0;
	mainlim := 0;
	heap := 0;
	heaplim := 0;
	image := 0;
	imagelim := 0;
	if(mfd == nil)
		mfd = sys->open("/dev/memory", sys->OREAD);
	if (mfd == nil)
		raisex(sys->sprint("can't open /dev/memory: %r"));

	sys->seek(mfd, big 0, Sys->SEEKSTART);

	buf := array[400] of byte;
	n := sys->read(mfd, buf, len buf);
	if (n <= 0)
		raisex(sys->sprint("can't read /dev/memory: %r"));

	(nil, l) := sys->tokenize(string buf[0:n], "\n");
	# p->cursize, p->maxsize, p->hw, p->nalloc, p->nfree, p->nbrk, poolmax(p), p->name)
	while(l != nil) {
		s := hd l;
		cur_size := int s[0:12];				
		max_size := int s[12:24];
		case s[7*12:] {
		"main" =>
			main = cur_size;
			mainlim = max_size;
		"heap" =>
			heap = cur_size;
			heaplim = max_size;
		"image" =>
			image = cur_size;
			imagelim = max_size;
		}
		l = tl l;
	}

	return ResourceState(ms, main, mainlim, heap, heaplim, image, imagelim);
}

ResourceState.since(rnew: self ResourceState, rold: ResourceState) : ResourceState
{
	return (rnew.ms - rold.ms, 
		rnew.main - rold.main, 
		rnew.heaplim,
		rnew.heap - rold.heap,
		rnew.heaplim, 
		rnew.image - rold.image, 
		rnew.imagelim);
}

ResourceState.print(r: self ResourceState, msg: string)
{
	sys->print("%s:\n\ttime: %d.%#.3ds; memory: main %dk, mainlim %dk, heap %dk, heaplim %dk, image %dk, imagelim %dk\n",
				msg, r.ms/1000, r.ms % 1000, r.main / 1024, r.mainlim / 1024,
				r.heap / 1024, r.heaplim / 1024, r.image / 1024, r.imagelim / 1024);
}

# Decide what to do based on Header and whether this is
# for the main entity or not, and the number of redirections-so-far.
# Return tuple contains:
#	(use, error, challenge, redir)
# and action to do is:
#	If use==1, use the entity else drain its byte source.
#	If error != nil, mesg was put in progress bar
#	If challenge != nil, get auth info and make new request with auth
#	Else if redir != nil, make a new request with redir for url
#
# (if challenge or redir is non-nil, use will be 0)
hdraction(bs: ref ByteSource, ismain: int, nredirs: int) : (int, string, string, ref U->Parsedurl)
{
	use := 1;
	error := "";
	challenge := "";
	redir : ref U->Parsedurl = nil;

	h := bs.hdr;
	assert(h != nil);
	bs.seenhdr = 1;
	code := h.code;
	case code/100 {
	HSOk =>
		if(code != HCOk)
			error = "unexpected code: " + hcphrase(code);
	HSRedirect =>
		if(h.location != nil) {
			redir = h.location;
			# spec says url should be absolute, but some
			# sites give relative ones
			if(redir.scheme == nil)
				redir = U->mkabs(redir, h.base);
			if(dbg)
				sys->print("redirect %s to %s\n", h.actual.tostring(), redir.tostring());
			if(nredirs >= Maxredir) {
				redir = nil;
				error = "probable redirect loop";
			}
			else
				use = 0;
		}
	HSError =>
		if(code == HCUnauthorized && h.chal != "") {
			challenge = h.chal;
			use = 0;
		}
		else {
			error = hcphrase(code);
			use = ismain;
		}
	HSServererr =>
		error = hcphrase(code);
		use = ismain;
	* =>
		error = "unexpected code: " + string code;
		use = 0;

	}
	if(error != "")
		G->progress <-= (bs.id, G->Perr, 0, error);
	return (use, error, challenge, redir);
}

# Use event when only care about time stamps on events
event(s: string, data: int)
{
	sys->print("%s: %d %d\n", s, sys->millisec()-startres.ms, data);
}

kill(pid: int, dogroup: int)
{
	msg : array of byte;
	if(dogroup)
		msg = array of byte "killgrp";
	else
		msg = array of byte "kill";
	ctl := sys->open("#p/" + string pid + "/ctl", sys->OWRITE);
	if(ctl != nil)
		if (sys->write(ctl, msg, len msg) < 0)
			sys->print("charon: kill write failed (pid %d, grp %d): %r\n", pid, dogroup);
}

# Read a line up to and including cr/lf (be tolerant and allow missing cr).
# Look first in buf[bstart:bend], and if that isn't sufficient to get whole line,
# refill buf from fd as needed.
# Return values:
#	array of byte: the line, not including cr/lf
#	eof, true if there was no line to get or a read error
#	bstart', bend': new valid portion of buf (after cr/lf).
getline(fd: ref sys->FD, buf: array of byte, bstart, bend: int) :
		(array of byte, int, int, int)
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
		bend = sys->read(fd, buf, len buf);
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

# Look (linearly) through a for s; return its index if found, else -1.
strlookup(a: array of string, s: string) : int
{
	n := len a;
	for(i := 0; i < n; i++)
		if(s == a[i])
			return i;
	return -1;
}

# Set up config global to defaults, then try to read user-specifiic
# config data from /usr/<username>/charon/config, then try to
# override from command line arguments.
setconfig(argl: list of string)
{
	# Defaults, in absence of any other information
	config.userdir = "";
	config.srcdir = "/appl/cmd/charon";
	config.starturl = "file:/services/webget/start.html";
	config.homeurl = config.starturl;
	config.change_homeurl = 1;
	config.helpurl = "file:/services/webget/help.html";
	config.usessl = SSLV3;	# was NOSSL
	config.devssl = 0;
	config.custbkurl = "/services/config/bookmarks.html";
	config.dualbkurl = "/services/config/dualdisplay.html";
	config.httpproxy = nil;
	config.noproxydoms = nil;
	config.buttons = "help,resize,hide,exit";
	config.framework = "all";
	config.defaultwidth = 640;
	config.defaultheight = 480;
	config.x = -1;
	config.y = -1;
	config.nocache = 0;
	config.maxstale = 0;
	config.imagelvl = ImgFull;
	config.imagecachenum = 120;
	config.imagecachemem = 100000000;	# 100Meg, will get lowered later
	config.docookies = 1;
	config.doscripts = 1;
	config.httpminor = 0;
	config.agentname = "Mozilla/4.08 (Charon; Inferno)";
	config.nthreads = 4;
	config.offersave = 1;
	config.charset = "windows-1252";
	config.plumbport = "web";
	config.wintitle = "Charon";	# tkclient->titlebar() title, used by GUI
	config.dbgfile = "";
	config.dbg = array[128] of { * => byte 0 };
	
	# Reading default config file
	readconf("/services/config/charon.cfg");

	# Try reading user config file
	user := "";
	fd := sys->open("/dev/user", sys->OREAD);
	if(fd != nil) {
		b := array[40] of byte;
		n := sys->read(fd, b, len b);
		if(n > 0)
			user = string b[0:n];
	}
	if(user != "") {
		config.userdir = "/usr/" + user + "/charon";
		readconf(config.userdir + "/config");
	}

	if(argl == nil)
		return;
	# Try command line arguments
	# All should be 'key=val' or '-key' or '-key val', except last which can be url to start
	for(l := tl argl; l != nil; l = tl l) {
		s := hd l;
		if(s == "")
			continue;
		if (s[0] != '-')
			break;
		a := s[1:];
		b := "";
		if(tl l != nil) {
			b = hd tl l;
			if(S->prefix("-", b))
				b = "";
			else
				l = tl l;
		}
		if(!setopt(a, b)) {
			if (b != nil)
				s += " "+b;
			sys->print("couldn't set option from arg '%s'\n", s);
		}
	}
	if(l != nil) {
		if (tl l != nil)
			# usage error
			sys->print("too many URL's\n");
		else
			if(!setopt("starturl", hd l))
				sys->print("couldn't set starturl from arg '%s'\n", hd l);
	}
}

readconf(fname: string)
{
	cfgio := sys->open(fname, sys->OREAD);
	if(cfgio != nil) {
		buf := array[sys->ATOMICIO] of byte;
		i := 0;
		j := 0;
		aline : array of byte;
		eof := 0;
		for(;;) {
			(aline, eof, i, j) = getline(cfgio, buf, i, j);
			if(eof)
				break;
			line := string aline;
			if(len line == 0 || line[0]=='#')
				continue;
			(key, val) := S->splitl(line, " \t=");
			if(key != "") {
				val = S->take(S->drop(val, " \t="), "^#\r\n");
				if(!setopt(key, val))
					sys->print("couldn't set option from line '%s'\n", line);
			}
		}
	}
}

# Set config option named 'key' to val, returning 1 if OK
setopt(key: string, val: string) : int
{
	ok := 1;
	if(val == "none")
		val = "";
	v := int val;
	case key {
	"userdir" =>
		config.userdir = val;
	"srcdir" =>
		config.srcdir = val;
	"starturl" =>
		if(val != "")
			config.starturl = val;
		else
			ok = 0;
	"change_homeurl" =>
		config.change_homeurl = v;
	"homeurl" =>
		if(val != "")
			if(config.change_homeurl) {
				config.homeurl = val;
				# order dependent
				config.starturl = config.homeurl;
			}
		else
			ok = 0;
	"helpurl" =>
		if(val != "")
			config.helpurl = val;
		else
			ok = 0;
 	"usessl" =>
 		if(val == "v2")
 			config.usessl |= SSLV2;
 		if(val == "v3")
 			config.usessl |= SSLV3;
 	"devssl" =>
 		if(v == 0)
 			config.devssl = 0;
 		else
 			config.devssl = 1;
#	"custbkurl" =>
#	"dualbkurl" =>
	"httpproxy" =>
		if(val != "")
			config.httpproxy = makeabsurl(val);
		else
			config.httpproxy = nil;
	"noproxy" or "noproxydoms" =>
		(nil, config.noproxydoms) = sys->tokenize(val, ";, \t");
	"buttons" =>
		config.buttons = S->tolower(val);
	"framework" =>
		config.framework = S->tolower(val);
	"defaultwidth" or "width" =>
		if(v > 200)
			config.defaultwidth = v;
		else
			ok = 0;
	"defaultheight" or "height" =>
		if(v > 100)
			config.defaultheight = v;
		else
			ok = 0;
	"x" =>
		config.x = v;
	"y" =>
		config.y = v;
	"nocache" =>
		config.nocache = v;
	"maxstale" =>
		config.maxstale = v;
	"imagelvl" =>
		config.imagelvl = v;
	"imagecachenum" =>
		config.imagecachenum = v;
	"imagecachemem" =>
		config.imagecachemem = v;
	"docookies" =>
		config.docookies = v;
	"doscripts" =>
		config.doscripts = v;
	"http" =>
		if(val == "1.1")
			config.httpminor = 1;
		else
			config.httpminor = 0;
	"agentname" =>
		config.agentname = val;
	"nthreads" =>
		if (v < 1)
			ok = 0;
		else
			config.nthreads = v;
	"offersave" =>
		if (v < 1)
			config.offersave = 0;
		else
			config.offersave = 1;
	"charset" =>
		config.charset = val;
	"plumbport" =>
		config.plumbport = val;
	"wintitle" =>
		config.wintitle = val;
	"dbgfile" =>
		config.dbgfile = val;
	"dbg" =>
		for(i := 0; i < len val; i++) {
			c := val[i];
			if(c < len config.dbg)
				config.dbg[c]++;
			else {
				ok = 0;
				break;
			}
		}
	* =>
		ok = 0;
	}
	return ok;
}

saveconfig(): int
{
	fname := config.userdir + "/config";
	buf := array [Sys->ATOMICIO] of byte;
	fd := sys->create(fname, Sys->OWRITE, 8r600);
	if(fd == nil)
		return -1;

	nbyte := savealine(fd, buf, "# Charon user configuration\n", 0);
	nbyte = savealine(fd, buf, "userdir=" + config.userdir + "\n", nbyte);
	nbyte = savealine(fd, buf, "srcdir=" + config.srcdir +"\n", nbyte);
	if(config.change_homeurl){ 
		nbyte = savealine(fd, buf, "starturl=" + config.starturl + "\n", nbyte);
 		nbyte = savealine(fd, buf, "homeurl=" + config.homeurl + "\n", nbyte); 	
	}
	if(config.httpproxy != nil)
		nbyte = savealine(fd, buf, "httpproxy=" + config.httpproxy.tostring() + "\n", nbyte); 	
 	if(config.usessl & SSLV23) {
 		nbyte = savealine(fd, buf, "usessl=v2\n", nbyte);
 		nbyte = savealine(fd, buf, "usessl=v3\n", nbyte);
	}
	else {
 		if(config.usessl & SSLV2)
 			nbyte = savealine(fd, buf, "usessl=v2\n", nbyte);
 		if(config.usessl & SSLV3)
 			nbyte = savealine(fd, buf, "usessl=v3\n", nbyte);
 	}
	if(config.devssl == 0)
		nbyte = savealine(fd, buf, "devssl=0\n", nbyte);
	else
		nbyte = savealine(fd, buf, "devssl=1\n", nbyte);
	if(config.noproxydoms != nil) {
		doms := "";
		doml := config.noproxydoms;
		while(doml != nil) {
			doms += hd doml + ",";
			doml = tl doml;
		}
		nbyte = savealine(fd, buf, "noproxy=" + doms + "\n", nbyte);
	}
	nbyte = savealine(fd, buf, "defaultwidth=" + string config.defaultwidth + "\n", nbyte); 	 	
	nbyte = savealine(fd, buf, "defaultheight=" + string config.defaultheight + "\n", nbyte); 	
	if(config.x >= 0)
		nbyte = savealine(fd, buf, "x=" + string config.x + "\n", nbyte);
	if(config.y >= 0)
		nbyte = savealine(fd, buf, "y=" + string config.y + "\n", nbyte);
	nbyte = savealine(fd, buf, "nocache=" + string config.nocache + "\n", nbyte);
	nbyte = savealine(fd, buf, "maxstale=" + string config.maxstale + "\n", nbyte);
	nbyte = savealine(fd, buf, "imagelvl=" + string config.imagelvl + "\n", nbyte);
	nbyte = savealine(fd, buf, "imagecachenum=" + string config.imagecachenum + "\n", nbyte);
	nbyte = savealine(fd, buf, "imagecachemem=" + string config.imagecachemem + "\n", nbyte);
	nbyte = savealine(fd, buf, "docookies=" + string config.docookies + "\n", nbyte);
	nbyte = savealine(fd, buf, "doscripts=" + string config.doscripts + "\n", nbyte);
	nbyte = savealine(fd, buf, "http=" + "1." + string config.httpminor + "\n", nbyte);
	nbyte = savealine(fd, buf, "agentname=" + string config.agentname + "\n", nbyte);
	nbyte = savealine(fd, buf, "nthreads=" + string config.nthreads + "\n", nbyte);
	nbyte = savealine(fd, buf, "charset=" + config.charset + "\n", nbyte);
	#for(i := 0; i < len config.dbg; i++)
		#nbyte = savealine(fd, buf, "dbg=" + string config.dbg[i] + "\n", nbyte);

	if(nbyte > 0)
		sys->write(fd, buf, nbyte);

	return 0; 
}

savealine(fd: ref Sys->FD, buf: array of byte, s: string, n: int): int
{
	if(Sys->ATOMICIO < n + len s) {
		sys->write(fd, buf, n);
		buf[0:] = array of byte s;
		return len s;
	}
	buf[n:] = array of byte s;
	return n + len s;
}

# Make a StringInt table out of a, mapping each string
# to its index.  Check that entries are in alphabetical order.
makestrinttab(a: array of string) : array of T->StringInt
{
	n := len a;
	ans := array[n] of T->StringInt;
	for(i := 0; i < n; i++) {
		ans[i].key = a[i];
		ans[i].val = i;
		if(i > 0 && a[i] < a[i-1])
			raisex("EXInternal: table out of alphabetical order");
	}
	return ans;
}

# Should really move into Url module.
# Don't include fragment in test, since we are testing if the
# pointed to docs are the same, not places within docs.
urlequal(a, b: ref U->Parsedurl) : int
{
	return a.scheme == b.scheme
		&& a.host == b.host
		&& a.port == b.port
		&& a.user == b.user
		&& a.passwd == b.passwd
		&& a.path == b.path
		&& a.query == b.query;
}

# U->makeurl, but add http:// if not an absolute path already
makeabsurl(s: string) : ref Parsedurl
{
	if (s == "")
		return nil;
	u := U->parse(s);
	if (u.scheme != nil)
		return u;
	if (s[0] == '/')
		# try file:
		s = "file://localhost" + s;
	else
		# try http
		s = "http://" + s;
	u = U->parse(s);
	return u;
}

# Return place to load from, given installed-path name.
# (If config.dbg['u'] is set, change directory to config.srcdir.)
loadpath(s: string) : string
{
	if(config.dbg['u'] == byte 0)
		return s;
	(nil, f) := S->splitr(s, "/");
	return config.srcdir + "/" + f;
}

color_tab := array[] of { T->StringInt
	("aqua",	16r00FFFF),
	("black",	Black),
	("blue",	Blue),
	("fuchsia",	16rFF00FF),
	("gray",	16r808080),
	("green",	16r008000),
	("lime",	16r00FF00),
	("maroon",	16r800000),
	("navy",	Navy),
	("olive",	16r808000),
	("purple",	16r800080),
	("red",	Red),
	("silver",	16rC0C0C0),
	("teal",	16r008080),
	("white",	White),
	("yellow",	16rFFFF00)
};
# Convert HTML color spec to RGB value, returning dflt if can't.
# Argument is supposed to be a valid HTML color, or "".
# Return the RGB value of the color, using dflt if s
# is "" or an invalid color.
color(s: string, dflt: int) : int
{
	if(s == "")
		return dflt;
	s = S->tolower(s);
	c := s[0];
	if(c < C->NCTYPE && ctype[c] == C->L) {
		(fnd, v) := T->lookup(color_tab, s);
		if(fnd)
			return v;
	}
	if(s[0] == '#')
		s = s[1:];
	(v, rest) := S->toint(s, 16);
	if(rest == "")
		return v;
	# s was invalid, so choose a valid one
	return dflt;
}

max(a,b: int) : int
{
	if(a > b)
		return a;
	return b;
}

min(a,b: int) : int
{
	if(a < b)
		return a;
	return b;
}

raisex(e: string)
{
	raise e;
}

assert(i: int)
{
	if(!i) {
		raisex("EXInternal: assertion failed");
#		sys->print("assertion failed\n");
#		s := hmeth[-1];
	}
}

getcookies(host, path: string, secure: int): string
{
	if (CK == nil || ckclient == nil)
		return nil;
	Client: import CK;
	return ckclient.getcookies(host, path, secure);
}

setcookie(host, path, cookie: string)
{
	if (CK == nil || ckclient == nil)
		return;
	Client: import CK;
	ckclient.set(host, path, cookie);
}

ex_mkdir(dirname: string): int
{
	(ok, nil) := sys->stat(dirname);
	if(ok < 0) {
		f := sys->create(dirname, sys->OREAD, sys->DMDIR + 8r777);
		if(f == nil) {
			sys->print("mkdir: can't create %s: %r\n", dirname);
			return 0;
		}
		f = nil;
	}
	return 1;
}

stripscript(s: string): string
{
	# strip leading whitespace and SGML comment start symbol '<!--'
	if (s == nil)
		return nil;
	cs := "<!--";
	ci := 0;
	for (si := 0; si < len s; si++) {
		c := s[si];
		if (c == cs[ci]) {
			if (++ci >= len cs)
				ci = 0;
		} else {
			ci = 0;
			if (c == ' ' || c == '\t' || c == '\r' || c == '\n')
				continue;
			break;
		}
	}
	# strip trailing whitespace and SGML comment terminator '-->'
	cs = "-->";
	ci = len cs -1;
	for (se := len s - 1; se > si; se--) {
		c := s[se];
		if (c == cs[ci]) {
			if (ci-- == 0)
				ci = len cs -1;
		} else {
			ci = len cs - 1;
			if (c == ' ' || c == '\t' || c == '\r' || c == '\n')
				continue;
			break;
		}
	}
	if (se < si)
		return nil;
	return s[si:se+1];
}

# Split a value (guaranteed trimmed) into sep-separated list of one of
# 	token
#	token = token
#	token = "quoted string"
# and put into list of Namevals (lowercase the first token)
Nameval.namevals(s: string, sep: int) : list of Nameval
{
	ans : list of Nameval = nil;
	n := len s;
	i := 0;
	while(i < n) {
		tok : string;
		(tok, i) = gettok(s, i, n);
		if(tok == "")
			break;
		tok = S->tolower(tok);
		val := "";
		while(i < n && ctype[s[i]] == C->W)
			i++;
		if(i == n || s[i] == sep)
			i++;
		else if(s[i] == '=') {
			i++;
			while(i < n && ctype[s[i]] == C->W)
				i++;
			if (i == n)
				break;
			if(s[i] == '"')
				(val, i) = getqstring(s, i, n);
			else
				(val, i) = gettok(s, i, n);
		}
		else
			break;
		ans = Nameval(tok, val) :: ans;
	}
	return ans;
}

gettok(s: string, i,n: int) : (string, int)
{
	while(i < n && ctype[s[i]] == C->W)
		i++;
	if(i == n)
		return ("", i);
	is := i;
	for(; i < n; i++) {
		c := s[i];
		ct := ctype[c];
		if(!(int (ct&(C->D|C->L|C->U|C->N|C->S))))
			if(int (ct&(C->W|C->C)) || S->in(c, "()<>@,;:\\\"/[]?={}"))
				break;
	}
	return (s[is:i], i);
}

# get quoted string; return it without quotes, and index after it
getqstring(s: string, i,n: int) : (string, int)
{
	while(i < n && ctype[s[i]] == C->W)
		i++;
	if(i == n || s[i] != '"')
		return ("", i);
	is := ++i;
	for(; i < n; i++) {
		c := s[i];
		if(c == '\\')
			i++;
		else if(c == '"')
			return (s[is:i], i+1);
	}
	return (s[is:i], i);
}

# Find value corresponding to key (should be lowercase)
# and return (1, value) if found or (0, "")
Nameval.find(l: list of Nameval, key: string) : (int, string)
{
	for(; l != nil; l = tl l)
		if((hd l).key == key)
			return (1, (hd l).val);
	return (0, "");
}

# this should be a converter cache
getconv(chset : string) : Btos
{
	(btos, err) := convcs->getbtos(chset);
	if (err != nil)
		sys->print("Converter error: %s\n", err);
	return btos;
}

X(s, note : string) : string
{
	if (dict == nil)
		return s;
	return dict.xlaten(s, note);
}
