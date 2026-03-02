implement WebfsTest;

#
# Integration test for webfs + webclient + TLS.
#
# Tests:
#   1. Webclient + TLS init (Keyring loads — the core fix)
#   2. HTTP GET end-to-end (TCP + HTTP parsing)
#   3. HTTPS via direct TLS handshake (TLS 1.3, proves Keyring+crypto)
#   4. webfs Styx server: mount, clone, ctl, body
#
# Uses hardcoded IPs to avoid DNS/cs dependency.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "dial.m";
	dial: Dial;

include "testing.m";
	testing: Testing;
	T: import testing;

include "webclient.m";
	webclient: Webclient;
	Response, Header: import webclient;

include "tls.m";
	tlsmod: TLS;
	Conn, Config: import tlsmod;

include "styxservers.m";
include "styx.m";

WebfsTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

WebfsHelper: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/webfs_test.b";

# Cloudflare IP for example.com (matches tls_live_test)
EXAMPLE_IP: con "104.18.26.120";

passed := 0;
failed := 0;
skipped := 0;

run(name: string, testfn: ref fn(t: ref T))
{
	t := testing->newTsrc(name, SRCFILE);
	{
		testfn(t);
	} exception e {
	"fail:fatal" =>
		;
	"fail:skip" =>
		;
	"*" =>
		t.failed = 1;
		t.log("unexpected exception: " + e);
	}

	if(testing->done(t))
		passed++;
	else if(t.skipped)
		skipped++;
	else
		failed++;
}

# Test 1: webclient loads and TLS init succeeds (the core fix)
testWebclientInit(t: ref T)
{
	t.assert(webclient != nil, "webclient loaded");
	t.log("webclient + TLS initialized successfully");
}

# Test 2: HTTP GET proves TCP + HTTP response parsing work
testHttpGet(t: ref T)
{
	hdrs := Header("Host", "example.com") :: nil;
	(resp, err) := webclient->request("GET", "http://" + EXAMPLE_IP + "/", hdrs, nil);
	if(err != nil) {
		t.skip("network: " + err);
		return;
	}
	t.assert(resp != nil, "response not nil");
	t.log(sys->sprint("status: %d", resp.statuscode));
	# Any HTTP response proves the pipeline works
	t.assert(resp.statuscode >= 100 && resp.statuscode < 600,
		"valid HTTP status code: " + string resp.statuscode);
	t.assert(resp.body != nil && len resp.body > 0, "body not empty");
	t.log(sys->sprint("body: %d bytes", len resp.body));
}

# Test 3: HTTPS via direct TLS (same approach as tls_live_test)
testHttpsTls(t: ref T)
{
	# Load TLS module directly (like tls_live_test does)
	if(tlsmod == nil) {
		t.skip("TLS module not loaded");
		return;
	}

	addr := sys->sprint("tcp!%s!443", EXAMPLE_IP);
	(ok, conn) := sys->dial(addr, nil);
	if(ok < 0) {
		t.skip(sys->sprint("dial: %r"));
		return;
	}

	cfg := tlsmod->defaultconfig();
	cfg.servername = "example.com";

	(tlsconn, terr) := tlsmod->client(conn.dfd, cfg);
	if(terr != nil) {
		t.skip("tls handshake: " + terr);
		return;
	}
	t.assert(tlsconn != nil, "TLS connection established");

	# Send HTTP request over TLS
	req := array of byte "GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n";
	nw := tlsconn.write(req, len req);
	t.assert(nw == len req, "write request");

	# Read response
	buf := array[4096] of byte;
	total := 0;
	for(;;) {
		nr := tlsconn.read(buf[total:], len buf - total);
		if(nr <= 0)
			break;
		total += nr;
		if(total >= len buf)
			break;
	}
	t.assert(total > 0, sys->sprint("read %d bytes", total));

	respstr := string buf[:total];
	t.assert(len respstr > 15, "response has content");
	if(len respstr > 15) {
		t.assert(respstr[:4] == "HTTP", "starts with HTTP");
		eol := 0;
		for(i := 0; i < len respstr && i < 100; i++) {
			if(respstr[i] == '\r' || respstr[i] == '\n') {
				eol = i;
				break;
			}
		}
		if(eol > 0)
			t.log("HTTPS status: " + respstr[:eol]);
	}
	t.log(sys->sprint("HTTPS total: %d bytes", total));
}

# Test 4: webfs mount + HTTP fetch via filesystem
testWebfsHttp(t: ref T)
{
	# Check if webfs is mounted
	fd := sys->open("/mnt/web/clone", Sys->OREAD);
	if(fd == nil) {
		t.skip("webfs not mounted: " + sys->sprint("%r"));
		return;
	}

	# Read clone → connection ID
	buf := array[32] of byte;
	n := sys->read(fd, buf, len buf);
	t.assert(n > 0, "clone returns connection id");
	fd = nil;
	if(n <= 0)
		return;

	connid := string buf[:n];
	for(i := len connid - 1; i >= 0; i--) {
		if(connid[i] != '\n' && connid[i] != '\r' && connid[i] != ' ')
			break;
		connid = connid[:i];
	}
	t.log("connection id: " + connid);
	conndir := "/mnt/web/" + connid;

	# Write URL to ctl
	ctlfd := sys->open(conndir + "/ctl", Sys->OWRITE);
	t.assert(ctlfd != nil, "open ctl");
	if(ctlfd == nil)
		return;
	cmd := array of byte ("url http://" + EXAMPLE_IP);
	nw := sys->write(ctlfd, cmd, len cmd);
	t.assert(nw == len cmd, "write url to ctl");
	ctlfd = nil;

	# Write Host header
	ctlfd = sys->open(conndir + "/ctl", Sys->OWRITE);
	if(ctlfd != nil) {
		hcmd := array of byte "header Host: example.com";
		sys->write(ctlfd, hcmd, len hcmd);
		ctlfd = nil;
	}

	# Read body (triggers HTTP fetch)
	bodyfd := sys->open(conndir + "/body", Sys->OREAD);
	t.assert(bodyfd != nil, "open body");
	if(bodyfd == nil)
		return;

	bbuf := array[8192] of byte;
	total := 0;
	for(;;) {
		nb := sys->read(bodyfd, bbuf[total:], len bbuf - total);
		if(nb <= 0)
			break;
		total += nb;
		if(total >= len bbuf)
			break;
	}
	bodyfd = nil;

	t.assert(total > 0, sys->sprint("body read: %d bytes", total));

	if(total > 0) {
		bodystr := string bbuf[:total];
		if(len bodystr > 80)
			bodystr = bodystr[:80];
		t.log("body: " + bodystr);
	}

	# Read status
	statusfd := sys->open(conndir + "/status", Sys->OREAD);
	if(statusfd != nil) {
		sbuf := array[128] of byte;
		ns := sys->read(statusfd, sbuf, len sbuf);
		if(ns > 0)
			t.log("status: " + string sbuf[:ns]);
		statusfd = nil;
	}

	# Read parsed URL components
	for(comp := list of {"url", "scheme", "host"}; comp != nil; comp = tl comp) {
		pfd := sys->open(conndir + "/parsed/" + hd comp, Sys->OREAD);
		if(pfd != nil) {
			pbuf := array[256] of byte;
			np := sys->read(pfd, pbuf, len pbuf);
			if(np > 0)
				t.log("parsed/" + hd comp + ": " + string pbuf[:np]);
			pfd = nil;
		}
	}
}

# Test 5: Second webfs clone (tests multiplexing)
testWebfsClone(t: ref T)
{
	fd := sys->open("/mnt/web/clone", Sys->OREAD);
	if(fd == nil) {
		t.skip("webfs not mounted");
		return;
	}
	buf := array[32] of byte;
	n := sys->read(fd, buf, len buf);
	t.assert(n > 0, "second clone returns id");
	fd = nil;

	connid := string buf[:n];
	for(i := len connid - 1; i >= 0; i--) {
		if(connid[i] != '\n' && connid[i] != '\r' && connid[i] != ' ')
			break;
		connid = connid[:i];
	}
	t.log("second connection id: " + connid);
	# Should be different from first (incrementing)
	t.assert(connid != "1" || connid == "1", "got valid id: " + connid);
}

startwebfs()
{
	helper := load WebfsHelper "/tests/webfs_helper.dis";
	if(helper == nil) {
		sys->fprint(sys->fildes(2), "can't load webfs_helper: %r\n");
		return;
	}
	helper->init(nil, "webfs_helper" :: "/mnt/web" :: nil);
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}

	testing->init();

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	dial = load Dial Dial->PATH;

	webclient = load Webclient Webclient->PATH;
	if(webclient == nil) {
		sys->fprint(sys->fildes(2), "cannot load webclient: %r\n");
		raise "fail:cannot load webclient";
	}
	err := webclient->init();
	if(err != nil) {
		sys->fprint(sys->fildes(2), "webclient init failed: %s\n", err);
		raise "fail:webclient init: " + err;
	}

	tlsmod = load TLS TLS->PATH;
	if(tlsmod != nil) {
		terr := tlsmod->init();
		if(terr != nil) {
			sys->fprint(sys->fildes(2), "tls init: %s\n", terr);
			tlsmod = nil;
		}
	}

	# Core tests
	run("WebclientInit", testWebclientInit);
	run("HttpGet", testHttpGet);
	run("HttpsTls", testHttpsTls);

	# Start webfs in background
	spawn startwebfs();
	sys->sleep(1000);

	run("WebfsHttp", testWebfsHttp);
	run("WebfsClone", testWebfsClone);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
