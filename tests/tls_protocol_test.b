implement TLSProtocolTest;

#
# TLS protocol error tests — verifies error handling for malformed records,
# handshake messages, ServerHello parsing, alerts, and certificate messages.
#
# Uses pipe-based fake servers that write crafted malformed TLS records.
# The TLS client should reject them with specific error strings.
#
# Performance: each test calls tls->client() which reads 64 bytes from
# /dev/random. Inferno's random device generates ~12 bytes/sec via entropy
# sampling, so 15 tests take ~90s. For fast runs (~2s), create a host
# urandom symlink: mkdir -p dev && ln -s /dev/urandom dev/urandom
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

TLSProtocolTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/tls_protocol_test.b";

passed := 0;
failed := 0;
skipped := 0;

run(name: string, testfn: ref fn(t: ref T))
{
	t := testing->newTsrc(name, SRCFILE);
	{
		testfn(t);
	} exception {
	"fail:fatal" =>
		;
	"fail:skip" =>
		;
	* =>
		t.failed = 1;
	}

	if(testing->done(t))
		passed++;
	else if(t.skipped)
		skipped++;
	else
		failed++;
}

# ================================================================
# Helpers
# ================================================================

# Build a TLS record: content_type(1) + version(2) + length(2) + payload
mkrecord(ctype: int, payload: array of byte): array of byte
{
	n := len payload;
	rec := array [5 + n] of byte;
	rec[0] = byte ctype;
	rec[1] = byte 16r03;
	rec[2] = byte 16r03;
	rec[3] = byte (n >> 8);
	rec[4] = byte n;
	rec[5:] = payload;
	return rec;
}

# Build a handshake message: type(1) + length(3) + body
mkhsmsg(hstype: int, body: array of byte): array of byte
{
	n := len body;
	msg := array [4 + n] of byte;
	msg[0] = byte hstype;
	msg[1] = byte (n >> 16);
	msg[2] = byte (n >> 8);
	msg[3] = byte n;
	msg[4:] = body;
	return msg;
}

# Build a minimal valid TLS 1.2 ServerHello:
# version=0x0303, random=32 zeros, session_id_len=0,
# cipher_suite=0xC02F (TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256), compression=0
mkserverhello(): array of byte
{
	body := array [38] of {* => byte 0};
	body[0] = byte 16r03;
	body[1] = byte 16r03;
	# random: bytes 2..33 already zero
	# session_id_len: byte 34 already zero
	body[35] = byte 16rC0;
	body[36] = byte 16r2F;
	# compression: byte 37 already zero
	return body;
}

# Concatenate two byte arrays
catbytes(a, b: array of byte): array of byte
{
	if(a == nil)
		return b;
	if(b == nil)
		return a;
	r := array [len a + len b] of byte;
	r[0:] = a;
	r[len a:] = b;
	return r;
}

# Check if string s contains substring sub
contains(s, sub: string): int
{
	if(len sub > len s)
		return 0;
	for(i := 0; i <= len s - len sub; i++) {
		if(s[i:i+len sub] == sub)
			return 1;
	}
	return 0;
}

# Fake server: drain ClientHello, write response, close pipe end
fakeserver(fd: ref Sys->FD, response: array of byte)
{
	# Drain the ClientHello (typically ~200-300 bytes)
	buf := array [4096] of byte;
	sys->read(fd, buf, len buf);

	# Write crafted response
	if(response != nil && len response > 0)
		sys->write(fd, response, len response);

	# Close pipe end (reference counting closes fd immediately)
	fd = nil;
}

# Create a pipe, spawn fake server, call tls->client(), assert error contains want
expecterr(t: ref T, response: array of byte, want: string)
{
	p := array [2] of ref Sys->FD;
	if(sys->pipe(p) < 0) {
		t.fatal(sys->sprint("pipe: %r"));
		return;
	}

	spawn fakeserver(p[1], response);
	p[1] = nil;	# drop our reference so pipe closes when fakeserver finishes

	config := tls->defaultconfig();
	config.servername = "test.example.com";
	config.insecure = 1;

	(conn, err) := tls->client(p[0], config);
	p[0] = nil;

	if(conn != nil) {
		conn.close();
		t.error("expected error but got connection");
		return;
	}

	if(err == nil) {
		t.error("expected error but got nil");
		return;
	}

	if(!contains(err, want)) {
		t.error("error '" + err + "' does not contain '" + want + "'");
		return;
	}

	t.log("got expected error: " + err);
}

# ================================================================
# Record Layer Tests
# ================================================================

# Close pipe after only 3 bytes (incomplete 5-byte record header)
testRecordTruncated(t: ref T)
{
	response := array [3] of byte;
	response[0] = byte 22;		# CT_HANDSHAKE
	response[1] = byte 16r03;
	response[2] = byte 16r03;
	expecterr(t, response, "record read failed");
}

# Record with length field > MAXFRAGMENT (16640)
testRecordTooLarge(t: ref T)
{
	response := array [5] of byte;
	response[0] = byte 22;
	response[1] = byte 16r03;
	response[2] = byte 16r03;
	# length = 16641 = 0x4101
	response[3] = byte 16r41;
	response[4] = byte 16r01;
	expecterr(t, response, "record too large");
}

# Valid 5-byte header claiming 100 bytes, but only 10 bytes follow
testRecordPayloadTruncated(t: ref T)
{
	response := array [5 + 10] of {* => byte 0};
	response[0] = byte 22;
	response[1] = byte 16r03;
	response[2] = byte 16r03;
	response[3] = byte 0;
	response[4] = byte 100;	# claims 100 bytes payload
	# only 10 bytes of payload follow (bytes 5-14)
	expecterr(t, response, "record payload read failed");
}

# Record with content type 23 (APPLICATION_DATA) instead of 22 (HANDSHAKE)
testRecordWrongType(t: ref T)
{
	payload := array [10] of {* => byte 0};
	response := mkrecord(23, payload);
	expecterr(t, response, "expected handshake");
}

# ================================================================
# Handshake Message Tests
# ================================================================

# Valid record containing only 2 bytes (< 4-byte handshake header)
testHandshakeTruncatedHeader(t: ref T)
{
	payload := array [2] of {* => byte 0};
	response := mkrecord(22, payload);
	expecterr(t, response, "handshake message too short");
}

# Handshake header claiming 100-byte body, but only 10 bytes present
testHandshakeTruncatedBody(t: ref T)
{
	# Total payload: 4 (HS header) + 10 (partial body) = 14 bytes
	payload := array [14] of {* => byte 0};
	payload[0] = byte 2;		# HT_SERVER_HELLO
	payload[1] = byte 0;
	payload[2] = byte 0;
	payload[3] = byte 100;		# claims 100 bytes body
	# only 10 bytes of body follow (bytes 4-13)
	response := mkrecord(22, payload);
	expecterr(t, response, "handshake message truncated");
}

# Send Certificate (type 11) when ServerHello (type 2) expected
testHandshakeWrongType(t: ref T)
{
	body := mkserverhello();
	hsmsg := mkhsmsg(11, body);		# HT_CERTIFICATE instead of HT_SERVER_HELLO
	response := mkrecord(22, hsmsg);
	expecterr(t, response, "expected ServerHello");
}

# ================================================================
# ServerHello Parsing Tests
# ================================================================

# ServerHello body < 38 bytes
testServerHelloTooShort(t: ref T)
{
	body := array [10] of {* => byte 0};
	hsmsg := mkhsmsg(2, body);
	response := mkrecord(22, hsmsg);
	expecterr(t, response, "ServerHello too short");
}

# ServerHello with legacy version 0x0301 (TLS 1.0), no supported_versions extension
testServerHelloUnsupportedVersion(t: ref T)
{
	body := mkserverhello();
	body[0] = byte 16r03;
	body[1] = byte 16r01;		# TLS 1.0
	hsmsg := mkhsmsg(2, body);
	response := mkrecord(22, hsmsg);
	expecterr(t, response, "unsupported version");
}

# ServerHello with compression method = 1 (deflate)
testServerHelloNonNullCompression(t: ref T)
{
	body := mkserverhello();
	body[37] = byte 1;		# deflate
	hsmsg := mkhsmsg(2, body);
	response := mkrecord(22, hsmsg);
	expecterr(t, response, "non-null compression");
}

# ServerHello with cipher suite 0xFFFF (not in client's list)
testServerHelloBadSuite(t: ref T)
{
	body := mkserverhello();
	body[35] = byte 16rFF;
	body[36] = byte 16rFF;
	hsmsg := mkhsmsg(2, body);
	response := mkrecord(22, hsmsg);
	expecterr(t, response, "unsupported suite");
}

# ================================================================
# Alert Handling Tests
# ================================================================

# Send alert record: level=2 (fatal), desc=40 (handshake_failure)
testAlertReceived(t: ref T)
{
	payload := array [2] of byte;
	payload[0] = byte 2;		# ALERT_FATAL
	payload[1] = byte 40;		# ALERT_HANDSHAKE_FAILURE
	response := mkrecord(21, payload);	# CT_ALERT
	expecterr(t, response, "alert");
}

# ================================================================
# Connection Tests
# ================================================================

# Close pipe immediately after draining ClientHello (no response at all)
testConnectionClosed(t: ref T)
{
	expecterr(t, nil, "record read failed");
}

# ================================================================
# Certificate Message Tests
# ================================================================

# After valid ServerHello, send Certificate with < 3 bytes body
testCertMsgTooShort(t: ref T)
{
	# ServerHello record
	sh := mkhsmsg(2, mkserverhello());
	shrec := mkrecord(22, sh);

	# Certificate with 2-byte body (too short, needs >= 3)
	certbody := array [2] of {* => byte 0};
	certmsg := mkhsmsg(11, certbody);
	certrec := mkrecord(22, certmsg);

	response := catbytes(shrec, certrec);
	expecterr(t, response, "Certificate msg too short");
}

# After valid ServerHello, send Certificate where cert_len exceeds actual data
testCertMsgTruncated(t: ref T)
{
	# ServerHello record
	sh := mkhsmsg(2, mkserverhello());
	shrec := mkrecord(22, sh);

	# Certificate body: total_length=1000, first cert claims 500 bytes but only 5 present
	certbody := array [11] of {* => byte 0};
	# total_length = 1000 (3 bytes big-endian)
	certbody[0] = byte 0;
	certbody[1] = byte 3;
	certbody[2] = byte 16rE8;
	# first cert: length = 500 (3 bytes big-endian)
	certbody[3] = byte 0;
	certbody[4] = byte 1;
	certbody[5] = byte 16rF4;
	# only 5 bytes of cert data follow (bytes 6-10)
	certmsg := mkhsmsg(11, certbody);
	certrec := mkrecord(22, certmsg);

	response := catbytes(shrec, certrec);
	expecterr(t, response, "certificate truncated");
}

# ================================================================
# Main
# ================================================================

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

	# Try to bind host /dev/urandom for fast random generation.
	# Without this, tls->client() uses Inferno's slow entropy-based
	# /dev/random (~12 bytes/sec), making 15 tests take ~90 seconds.
	# The bind works if $ROOT/dev/ exists with a urandom symlink.
	sys->bind("#U/dev", "/dev", Sys->MAFTER);

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

	# Record layer tests
	run("RecordTruncated", testRecordTruncated);
	run("RecordTooLarge", testRecordTooLarge);
	run("RecordPayloadTruncated", testRecordPayloadTruncated);
	run("RecordWrongType", testRecordWrongType);

	# Handshake message tests
	run("HandshakeTruncatedHeader", testHandshakeTruncatedHeader);
	run("HandshakeTruncatedBody", testHandshakeTruncatedBody);
	run("HandshakeWrongType", testHandshakeWrongType);

	# ServerHello parsing tests
	run("ServerHelloTooShort", testServerHelloTooShort);
	run("ServerHelloUnsupportedVersion", testServerHelloUnsupportedVersion);
	run("ServerHelloNonNullCompression", testServerHelloNonNullCompression);
	run("ServerHelloBadSuite", testServerHelloBadSuite);

	# Alert handling
	run("AlertReceived", testAlertReceived);

	# Connection tests
	run("ConnectionClosed", testConnectionClosed);

	# Certificate message tests
	run("CertMsgTooShort", testCertMsgTooShort);
	run("CertMsgTruncated", testCertMsgTruncated);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
