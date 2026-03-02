implement TLSLiveTest;

#
# Live TLS handshake tests — connect to real servers.
#
# Tests:
#   - TLS handshake with hostname verification (no insecure flag)
#   - HTTP GET over TLS and check for HTTP response
#   - Both TLS 1.2 and TLS 1.3 servers
#
# Note: These tests require network connectivity.
# Tests will be skipped if network is unavailable.
#
# Uses IP addresses for dial() since the emulator may not have
# a connection server (cs) for DNS resolution. Hostnames are
# sent via SNI and Host header.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "tls.m";
	tls: TLS;
	Conn, Config: import tls;

include "testing.m";
	testing: Testing;
	T: import testing;

TLSLiveTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

passed := 0;
failed := 0;
skipped := 0;

SRCFILE: con "/tests/tls_live_test.b";

# Well-known server IPs (resolved at test-writing time).
# If these change, update them or skip.
EXAMPLE_COM_IP: con "104.18.26.120";
CLOUDFLARE_COM_IP: con "104.16.132.229";

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

# Helper: TCP connect + TLS handshake
tlsconnect(ip, port: string, config: ref Config): (ref Conn, string)
{
	addr := sys->sprint("tcp!%s!%s", ip, port);
	(ok, conn) := sys->dial(addr, nil);
	if(ok < 0)
		return (nil, sys->sprint("dial %s: %r", addr));

	return tls->client(conn.dfd, config);
}

# Helper: send HTTP GET, return first chunk of response
httpget(c: ref Conn, host, path: string): (string, string)
{
	request := sys->sprint("GET %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\nUser-Agent: Infernode-Test/1.0\r\n\r\n", path, host);
	reqbytes := array of byte request;
	if(c.write(reqbytes, len reqbytes) < 0)
		return (nil, "write failed");

	# Read response (first chunk is enough to check status)
	buf := array[4096] of byte;
	n := c.read(buf, len buf);
	if(n <= 0)
		return (nil, "read failed or empty response");

	return (string buf[0:n], nil);
}

# Extract HTTP status code from "HTTP/x.y NNN ..."
getstatus(response: string): int
{
	i := 0;
	for(; i < len response && response[i] != ' '; i++)
		;
	i++;
	code := 0;
	for(j := 0; j < 3 && i+j < len response; j++) {
		c := response[i+j];
		if(c < '0' || c > '9')
			return 0;
		code = code * 10 + (c - '0');
	}
	return code;
}

# ============================================================
# Test 1: TLS handshake to example.com (insecure first)
#
# Start with insecure mode to isolate TLS protocol issues
# from certificate verification issues.
# ============================================================

testTLSInsecure(t: ref T)
{
	t.log("Connecting to example.com:443 (insecure)...");

	config := tls->defaultconfig();
	config.servername = "example.com";
	config.insecure = 1;

	(conn, err) := tlsconnect(EXAMPLE_COM_IP, "443", config);
	if(err != nil) {
		if(hasprefix(err, "dial "))
			t.skip("network unavailable: " + err);
		else
			t.fatal("TLS handshake failed: " + err);
		return;
	}

	t.log(sys->sprint("TLS version: 0x%04x, suite: 0x%04x", conn.version, conn.suite));
	t.assert(conn.version >= TLS->TLS12, "version >= TLS 1.2");

	(response, rerr) := httpget(conn, "example.com", "/");
	conn.close();

	if(rerr != nil) {
		t.fatal("HTTP GET failed: " + rerr);
		return;
	}

	t.assert(len response > 0, "got HTTP response");
	t.assert(hasprefix(response, "HTTP/"), "response starts with HTTP/");

	status := getstatus(response);
	t.log(sys->sprint("HTTP status: %d", status));
	t.assert(status >= 200 && status < 400, "HTTP status 2xx/3xx");
}

# ============================================================
# Test 2: TLS with full verification (hostname + cert chain)
# ============================================================

testTLSVerified(t: ref T)
{
	t.log("Connecting to example.com:443 (verified)...");

	config := tls->defaultconfig();
	config.servername = "example.com";
	# No insecure flag — full hostname + cert verification

	(conn, err) := tlsconnect(EXAMPLE_COM_IP, "443", config);
	if(err != nil) {
		if(hasprefix(err, "dial "))
			t.skip("network unavailable: " + err);
		else
			t.fatal("TLS handshake failed: " + err);
		return;
	}

	t.log(sys->sprint("TLS version: 0x%04x, suite: 0x%04x", conn.version, conn.suite));
	t.assert(conn.version >= TLS->TLS12, "version >= TLS 1.2");

	(response, rerr) := httpget(conn, "example.com", "/");
	conn.close();

	if(rerr != nil) {
		t.fatal("HTTP GET failed: " + rerr);
		return;
	}

	t.assert(hasprefix(response, "HTTP/"), "response starts with HTTP/");

	status := getstatus(response);
	t.log(sys->sprint("HTTP status: %d", status));
	t.assert(status >= 200 && status < 400, "HTTP status 2xx/3xx");
}

# ============================================================
# Test 3: TLS 1.3 handshake to cloudflare.com
# ============================================================

testTLS13(t: ref T)
{
	t.log("Connecting to cloudflare.com:443...");

	config := tls->defaultconfig();
	config.servername = "cloudflare.com";
	config.insecure = 1;	# cert verification tested separately

	(conn, err) := tlsconnect(CLOUDFLARE_COM_IP, "443", config);
	if(err != nil) {
		if(hasprefix(err, "dial "))
			t.skip("network unavailable: " + err);
		else
			t.fatal("TLS handshake failed: " + err);
		return;
	}

	t.log(sys->sprint("TLS version: 0x%04x, suite: 0x%04x", conn.version, conn.suite));
	t.assert(conn.version >= TLS->TLS12, "version >= TLS 1.2");

	(response, rerr) := httpget(conn, "cloudflare.com", "/");
	conn.close();

	if(rerr != nil) {
		t.fatal("HTTP GET failed: " + rerr);
		return;
	}

	t.assert(hasprefix(response, "HTTP/"), "response starts with HTTP/");

	status := getstatus(response);
	t.log(sys->sprint("HTTP status: %d", status));
	t.assert(status >= 200 && status < 400, "HTTP status 2xx/3xx");
}

# ============================================================
# Test 4: Hostname mismatch detection
# ============================================================

testHostnameMismatch(t: ref T)
{
	t.log("Testing hostname mismatch detection...");

	config := tls->defaultconfig();
	# Set SNI to wrong hostname — cert won't match
	config.servername = "wrong.hostname.invalid";

	# Connect to example.com IP but claim we want wrong.hostname.invalid
	(ok, conn) := sys->dial("tcp!" + EXAMPLE_COM_IP + "!443", nil);
	if(ok < 0) {
		t.skip(sys->sprint("network unavailable: %r"));
		return;
	}

	(tlsconn, err) := tls->client(conn.dfd, config);
	if(err != nil) {
		# Expected: should fail due to hostname mismatch
		t.log("correctly rejected: " + err);
	} else {
		tlsconn.close();
		t.error("should have rejected hostname mismatch");
	}
}

# ============================================================
# Utility
# ============================================================

hasprefix(s, prefix: string): int
{
	if(len s < len prefix)
		return 0;
	return s[0:len prefix] == prefix;
}

# ============================================================
# Main
# ============================================================

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	testing = load Testing Testing->PATH;
	tls = load TLS TLS->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}
	if(tls == nil) {
		sys->fprint(sys->fildes(2), "cannot load TLS module: %r\n");
		raise "fail:cannot load TLS";
	}

	testing->init();
	terr := tls->init();
	if(terr != nil) {
		sys->fprint(sys->fildes(2), "TLS init failed: %s\n", terr);
		raise "fail:TLS init";
	}

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	sys->fprint(sys->fildes(2), "\n=== Live TLS Handshake Tests ===\n\n");

	run("TLS/Insecure", testTLSInsecure);
	run("TLS/Verified", testTLSVerified);
	run("TLS/TLS13", testTLS13);
	run("TLS/HostnameMismatch", testHostnameMismatch);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
