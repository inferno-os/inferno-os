implement X509Test;

#
# X.509 certificate unit tests
#
# Tests certificate parsing, name comparison, public key extraction,
# extension parsing, signature verification, chain verification,
# validity checking, and error handling using real root CA DER files
# from /lib/certs/ as test fixtures.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	keyring: Keyring;

include "daytime.m";
	daytime: Daytime;

include "asn1.m";
	asn1: ASN1;

include "security.m";

include "pkcs.m";
	pkcs: PKCS;

include "x509.m";
	x509: X509;
	Signed, Certificate, Name, SubjectPKInfo, PublicKey,
	Extension, ExtClass, Validity,
	KeyUsage_KeyCertSign, KeyUsage_CRLSign: import x509;

include "testing.m";
	testing: Testing;
	T: import testing;

X509Test: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/x509_test.b";

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

# Helper: read a file into a byte array
readfile(path: string): array of byte
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	(ok, dir) := sys->fstat(fd);
	if(ok < 0)
		return nil;
	n := int dir.length;
	buf := array[n] of byte;
	nr := sys->read(fd, buf, n);
	if(nr != n)
		return nil;
	return buf;
}

# Helper: decode DER to (Signed, Certificate), fatal on error
decodecert(t: ref T, der: array of byte): (ref Signed, ref Certificate)
{
	(err, s) := Signed.decode(der);
	if(err != nil) {
		t.fatal("Signed.decode: " + err);
		return (nil, nil);
	}
	cerr: string;
	c: ref Certificate;
	(cerr, c) = Certificate.decode(s.tobe_signed);
	if(cerr != nil) {
		t.fatal("Certificate.decode: " + cerr);
		return (nil, nil);
	}
	return (s, c);
}

# Helper: count list elements
extlistlen(l: list of ref ExtClass): int
{
	n := 0;
	while(l != nil) {
		n++;
		l = tl l;
	}
	return n;
}

# Helper: substring check
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

# Cert file paths
GLOBALSIGN_ECC := "/lib/certs/globalsign-ecc-root-r5.der";
ISRG_ROOT_X1 := "/lib/certs/isrg-root-x1.der";
DIGICERT_G2 := "/lib/certs/digicert-global-root-g2.der";
GLOBALSIGN_R6 := "/lib/certs/globalsign-root-r6.der";
GLOBALSIGN_R3 := "/lib/certs/globalsign-root-r3.der";
SSLCOM_ECC := "/lib/certs/sslcom-root-ca-ecc.der";
SSLCOM_RSA := "/lib/certs/sslcom-root-ca-rsa.der";
COMODO_AAA := "/lib/certs/comodo-aaa-certificate-services.der";

CERTFILES: array of string;

# ============================================================
# Certificate Parsing (4 tests)
# ============================================================

testParseGlobalSignECC(t: ref T)
{
	der := readfile(GLOBALSIGN_ECC);
	if(der == nil) {
		t.fatal("cannot read " + GLOBALSIGN_ECC);
		return;
	}
	t.log(sys->sprint("read %d bytes", len der));

	(nil, c) := decodecert(t, der);
	if(c == nil)
		return;

	t.asserteq(c.version, 2, "version should be 2 (v3)");
	t.assert(c.serial_number != nil, "serial_number should not be nil");
	t.assert(c.issuer != nil, "issuer should not be nil");
	t.assert(c.subject != nil, "subject should not be nil");
	t.assert(c.validity != nil, "validity should not be nil");
	t.assert(c.subject_pkinfo != nil, "subject_pkinfo should not be nil");
	t.assert(c.exts != nil, "exts should not be nil");
}

testParseISRGRootX1(t: ref T)
{
	der := readfile(ISRG_ROOT_X1);
	if(der == nil) {
		t.fatal("cannot read " + ISRG_ROOT_X1);
		return;
	}
	t.log(sys->sprint("read %d bytes", len der));

	(nil, c) := decodecert(t, der);
	if(c == nil)
		return;

	t.asserteq(c.version, 2, "version should be 2 (v3)");
	t.assert(c.serial_number != nil, "serial_number should not be nil");
	t.assert(c.exts != nil, "exts should not be nil");
}

testParseAllRootCAs(t: ref T)
{
	for(i := 0; i < len CERTFILES; i++) {
		der := readfile(CERTFILES[i]);
		if(der == nil) {
			t.error("cannot read " + CERTFILES[i]);
			continue;
		}
		t.log(sys->sprint("%s: %d bytes", CERTFILES[i], len der));

		(err, s) := Signed.decode(der);
		if(err != nil) {
			t.error(CERTFILES[i] + ": Signed.decode: " + err);
			continue;
		}
		cerr: string;
		(cerr, nil) = Certificate.decode(s.tobe_signed);
		if(cerr != nil) {
			t.error(CERTFILES[i] + ": Certificate.decode: " + cerr);
			continue;
		}
		t.log(CERTFILES[i] + ": OK");
	}
}

testParseGlobalSignR6(t: ref T)
{
	der := readfile(GLOBALSIGN_R6);
	if(der == nil) {
		t.fatal("cannot read " + GLOBALSIGN_R6);
		return;
	}
	t.log(sys->sprint("read %d bytes", len der));

	(nil, c) := decodecert(t, der);
	if(c == nil)
		return;

	t.asserteq(c.version, 2, "version should be 2 (v3)");
	t.assert(c.serial_number != nil, "serial_number should not be nil");
	t.assert(c.exts != nil, "exts should not be nil");
	t.assert(c.issuer != nil, "issuer should not be nil");
}

# ============================================================
# Name Parsing & Comparison (3 tests)
# ============================================================

testNameSelfSigned(t: ref T)
{
	# Self-signed roots should have issuer == subject
	der1 := readfile(GLOBALSIGN_ECC);
	der2 := readfile(ISRG_ROOT_X1);
	if(der1 == nil || der2 == nil) {
		t.fatal("cannot read cert files");
		return;
	}

	(nil, c1) := decodecert(t, der1);
	(nil, c2) := decodecert(t, der2);
	if(c1 == nil || c2 == nil)
		return;

	t.asserteq(c1.issuer.equal(c1.subject), 1, "GlobalSign ECC issuer == subject (self-signed)");
	t.asserteq(c2.issuer.equal(c2.subject), 1, "ISRG Root X1 issuer == subject (self-signed)");
}

testNameDifferent(t: ref T)
{
	der1 := readfile(GLOBALSIGN_ECC);
	der2 := readfile(ISRG_ROOT_X1);
	if(der1 == nil || der2 == nil) {
		t.fatal("cannot read cert files");
		return;
	}

	(nil, c1) := decodecert(t, der1);
	(nil, c2) := decodecert(t, der2);
	if(c1 == nil || c2 == nil)
		return;

	t.asserteq(c1.issuer.equal(c2.subject), 0, "GlobalSign issuer != ISRG subject");
	t.log("issuer1: " + c1.issuer.tostring());
	t.log("subject2: " + c2.subject.tostring());
}

testNameTostring(t: ref T)
{
	der := readfile(GLOBALSIGN_ECC);
	if(der == nil) {
		t.fatal("cannot read " + GLOBALSIGN_ECC);
		return;
	}

	(nil, c) := decodecert(t, der);
	if(c == nil)
		return;

	s := c.issuer.tostring();
	t.assert(len s > 0, "issuer.tostring() should be non-empty");
	t.assert(contains(s, "GlobalSign"), "issuer should contain 'GlobalSign'");
	t.log("issuer: " + s);
}

# ============================================================
# Public Key Extraction (3 tests)
# ============================================================

testPubKeyEC(t: ref T)
{
	der := readfile(GLOBALSIGN_ECC);
	if(der == nil) {
		t.fatal("cannot read " + GLOBALSIGN_ECC);
		return;
	}

	(nil, c) := decodecert(t, der);
	if(c == nil)
		return;

	(err, nil, pk) := c.subject_pkinfo.getPublicKey();
	if(err != nil) {
		t.fatal("getPublicKey: " + err);
		return;
	}

	pick k := pk {
	EC =>
		t.asserteq(len k.point, 97, "P-384 uncompressed point should be 97 bytes");
		t.log(sys->sprint("EC point length: %d", len k.point));
	* =>
		t.error("expected PublicKey.EC, got other type");
	}
}

testPubKeyRSA(t: ref T)
{
	der := readfile(ISRG_ROOT_X1);
	if(der == nil) {
		t.fatal("cannot read " + ISRG_ROOT_X1);
		return;
	}

	(nil, c) := decodecert(t, der);
	if(c == nil)
		return;

	(err, nil, pk) := c.subject_pkinfo.getPublicKey();
	if(err != nil) {
		t.fatal("getPublicKey: " + err);
		return;
	}

	pick k := pk {
	RSA =>
		t.assert(k.pk != nil, "RSA public key should not be nil");
		t.log("RSA public key extracted OK");
	* =>
		t.error("expected PublicKey.RSA, got other type");
	}
}

testPubKeyDigicertRSA(t: ref T)
{
	der := readfile(DIGICERT_G2);
	if(der == nil) {
		t.fatal("cannot read " + DIGICERT_G2);
		return;
	}

	(nil, c) := decodecert(t, der);
	if(c == nil)
		return;

	(err, nil, pk) := c.subject_pkinfo.getPublicKey();
	if(err != nil) {
		t.fatal("getPublicKey: " + err);
		return;
	}

	pick k := pk {
	RSA =>
		t.assert(k.pk != nil, "RSA public key should not be nil");
		t.log("DigiCert RSA public key extracted OK");
	* =>
		t.error("expected PublicKey.RSA, got other type");
	}
}

# ============================================================
# Extension Parsing (4 tests)
# ============================================================

testExtParse(t: ref T)
{
	der := readfile(GLOBALSIGN_ECC);
	if(der == nil) {
		t.fatal("cannot read " + GLOBALSIGN_ECC);
		return;
	}

	(nil, c) := decodecert(t, der);
	if(c == nil)
		return;

	(err, ecs) := x509->parse_exts(c.exts);
	if(err != nil)
		t.fatal("parse_exts: " + err);
	n := extlistlen(ecs);
	t.assert(n >= 3, sys->sprint("should have >= 3 decoded extensions, got %d", n));
	t.log(sys->sprint("%d extensions decoded via parse_exts", n));
}

testExtBasicConstraints(t: ref T)
{
	der := readfile(ISRG_ROOT_X1);
	if(der == nil) {
		t.fatal("cannot read " + ISRG_ROOT_X1);
		return;
	}

	(nil, c) := decodecert(t, der);
	if(c == nil)
		return;

	found := 0;
	for(l := c.exts; l != nil; l = tl l) {
		(err, ec) := ExtClass.decode(hd l);
		if(err != nil || ec == nil)
			continue;
		pick e := ec {
		BasicConstraints =>
			found = 1;
			t.log(sys->sprint("BasicConstraints: depth=%d", e.depth));
		}
	}
	t.asserteq(found, 1, "should find and decode BasicConstraints extension");
}

testExtKeyUsage(t: ref T)
{
	der := readfile(GLOBALSIGN_ECC);
	if(der == nil) {
		t.fatal("cannot read " + GLOBALSIGN_ECC);
		return;
	}

	(nil, c) := decodecert(t, der);
	if(c == nil)
		return;

	(err, ecs) := x509->parse_exts(c.exts);
	if(err != nil)
		t.fatal("parse_exts: " + err);
	found := 0;
	for(; ecs != nil; ecs = tl ecs) {
		pick e := hd ecs {
		KeyUsage =>
			found = 1;
			t.log(sys->sprint("KeyUsage: 0x%x", e.usage));
			t.assert(e.usage & KeyUsage_KeyCertSign, "KeyCertSign should be set");
			t.assert(e.usage & KeyUsage_CRLSign, "CRLSign should be set");
		}
	}
	t.asserteq(found, 1, "should find KeyUsage extension");
}

testExtSubjectKeyId(t: ref T)
{
	der := readfile(GLOBALSIGN_ECC);
	if(der == nil) {
		t.fatal("cannot read " + GLOBALSIGN_ECC);
		return;
	}

	(nil, c) := decodecert(t, der);
	if(c == nil)
		return;

	(err, ecs) := x509->parse_exts(c.exts);
	if(err != nil)
		t.fatal("parse_exts: " + err);
	found := 0;
	for(; ecs != nil; ecs = tl ecs) {
		pick e := hd ecs {
		SubjectKeyIdentifier =>
			found = 1;
			t.assert(len e.id > 0, "SubjectKeyIdentifier id should be non-empty");
			t.log(sys->sprint("SKI length: %d bytes", len e.id));
		}
	}
	t.asserteq(found, 1, "should find SubjectKeyIdentifier extension");
}

# ============================================================
# Signature Verification (2 tests)
# ============================================================

testSigVerifyECC(t: ref T)
{
	der := readfile(GLOBALSIGN_ECC);
	if(der == nil) {
		t.fatal("cannot read " + GLOBALSIGN_ECC);
		return;
	}

	(s, c) := decodecert(t, der);
	if(s == nil || c == nil)
		return;

	(err, nil, pk) := c.subject_pkinfo.getPublicKey();
	if(err != nil) {
		t.fatal("getPublicKey: " + err);
		return;
	}

	ok := s.verify(pk, 0);
	t.asserteq(ok, 1, "self-signed ECC root should verify (P-384/SHA-384)");
}

testSigVerifyRSA(t: ref T)
{
	der := readfile(ISRG_ROOT_X1);
	if(der == nil) {
		t.fatal("cannot read " + ISRG_ROOT_X1);
		return;
	}

	(s, c) := decodecert(t, der);
	if(s == nil || c == nil)
		return;

	(err, nil, pk) := c.subject_pkinfo.getPublicKey();
	if(err != nil) {
		t.fatal("getPublicKey: " + err);
		return;
	}

	ok := s.verify(pk, 0);
	t.asserteq(ok, 1, "self-signed RSA root should verify (RSA/SHA-256)");
}

# ============================================================
# Certificate Chain Verification (2 tests)
# ============================================================

testChainSingleRoot(t: ref T)
{
	der := readfile(GLOBALSIGN_ECC);
	if(der == nil) {
		t.fatal("cannot read " + GLOBALSIGN_ECC);
		return;
	}

	(ok, err) := x509->verify_certchain(der :: nil);
	t.asserteq(ok, 1, "single self-signed root should verify");
	if(err != nil)
		t.log("chain error: " + err);
}

testChainMismatch(t: ref T)
{
	der1 := readfile(GLOBALSIGN_ECC);
	der2 := readfile(ISRG_ROOT_X1);
	if(der1 == nil || der2 == nil) {
		t.fatal("cannot read cert files");
		return;
	}

	# Two unrelated roots: second cert's issuer won't match first's subject
	(ok, err) := x509->verify_certchain(der1 :: der2 :: nil);
	t.asserteq(ok, 0, "mismatched chain should fail");
	t.assert(err != nil && len err > 0, "should return error message");
	t.log("expected error: " + err);
}

# ============================================================
# Validity (1 test)
# ============================================================

testValidityNotExpired(t: ref T)
{
	der := readfile(ISRG_ROOT_X1);
	if(der == nil) {
		t.fatal("cannot read " + ISRG_ROOT_X1);
		return;
	}

	(nil, c) := decodecert(t, der);
	if(c == nil)
		return;

	now := daytime->now();
	expired := c.is_expired(now);
	t.asserteq(expired, 0, "ISRG Root X1 should not be expired (expires 2035)");
	t.log(sys->sprint("validity: %d - %d, now: %d", c.validity.not_before, c.validity.not_after, now));
}

# ============================================================
# Error Handling (2 tests)
# ============================================================

testErrorGarbage(t: ref T)
{
	garbage := array[100] of byte;
	for(i := 0; i < len garbage; i++)
		garbage[i] = byte 16rFF;

	(err, nil) := Signed.decode(garbage);
	t.assert(err != nil && len err > 0, "garbage input should return error");
	t.log("error: " + err);
}

testErrorTruncated(t: ref T)
{
	der := readfile(GLOBALSIGN_ECC);
	if(der == nil) {
		t.fatal("cannot read " + GLOBALSIGN_ECC);
		return;
	}

	truncated := der[0:50];
	(err, nil) := Signed.decode(truncated);
	t.assert(err != nil && len err > 0, "truncated cert should return error");
	t.log("error: " + err);
}

# ============================================================
# init
# ============================================================

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	keyring = load Keyring Keyring->PATH;
	daytime = load Daytime Daytime->PATH;
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

	asn1 = load ASN1 ASN1->PATH;
	if(asn1 == nil) {
		sys->fprint(sys->fildes(2), "cannot load asn1: %r\n");
		raise "fail:cannot load asn1";
	}
	asn1->init();

	x509 = load X509 X509->PATH;
	if(x509 == nil) {
		sys->fprint(sys->fildes(2), "cannot load x509: %r\n");
		raise "fail:cannot load x509";
	}
	err := x509->init();
	if(err != nil) {
		sys->fprint(sys->fildes(2), "x509 init: %s\n", err);
		raise "fail:x509 init";
	}

	if(daytime == nil) {
		sys->fprint(sys->fildes(2), "cannot load daytime: %r\n");
		raise "fail:cannot load daytime";
	}

	# Initialize cert file list
	CERTFILES = array[] of {
		GLOBALSIGN_ECC,
		ISRG_ROOT_X1,
		DIGICERT_G2,
		GLOBALSIGN_R6,
		GLOBALSIGN_R3,
		SSLCOM_ECC,
		SSLCOM_RSA,
		COMODO_AAA,
	};

	# Certificate Parsing
	run("Parse/GlobalSignECC", testParseGlobalSignECC);
	run("Parse/ISRGRootX1", testParseISRGRootX1);
	run("Parse/AllRootCAs", testParseAllRootCAs);
	run("Parse/GlobalSignR6", testParseGlobalSignR6);

	# Name Parsing & Comparison
	run("Name/SelfSigned", testNameSelfSigned);
	run("Name/Different", testNameDifferent);
	run("Name/Tostring", testNameTostring);

	# Public Key Extraction
	run("PubKey/EC", testPubKeyEC);
	run("PubKey/RSA", testPubKeyRSA);
	run("PubKey/DigicertRSA", testPubKeyDigicertRSA);

	# Extension Parsing
	run("Ext/Parse", testExtParse);
	run("Ext/BasicConstraints", testExtBasicConstraints);
	run("Ext/KeyUsage", testExtKeyUsage);
	run("Ext/SubjectKeyId", testExtSubjectKeyId);

	# Signature Verification
	run("SigVerify/ECC", testSigVerifyECC);
	run("SigVerify/RSA", testSigVerifyRSA);

	# Certificate Chain Verification
	run("Chain/SingleRoot", testChainSingleRoot);
	run("Chain/Mismatch", testChainMismatch);

	# Validity
	run("Validity/NotExpired", testValidityNotExpired);

	# Error Handling
	run("Error/Garbage", testErrorGarbage);
	run("Error/Truncated", testErrorTruncated);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
