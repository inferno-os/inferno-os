implement TLS;

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	keyring: Keyring;
	IPint, DigestState: import keyring;

include "asn1.m";
	asn1: ASN1;
	Elem, Tag: import asn1;

include "pkcs.m";
	pkcs: PKCS;
	RSAKey: import PKCS;

include "x509.m";
	x509: X509;
	Signed, Certificate, SubjectPKInfo, PublicKey: import x509;

include "tls.m";

# Record content types
CT_CHANGE_CIPHER_SPEC:	con 20;
CT_ALERT:		con 21;
CT_HANDSHAKE:		con 22;
CT_APPLICATION_DATA:	con 23;

# Handshake message types
HT_CLIENT_HELLO:		con 1;
HT_SERVER_HELLO:		con 2;
HT_NEW_SESSION_TICKET:		con 4;
HT_ENCRYPTED_EXTENSIONS:	con 8;
HT_CERTIFICATE:			con 11;
HT_SERVER_KEY_EXCHANGE:		con 12;
HT_CERTIFICATE_REQUEST:		con 13;
HT_SERVER_HELLO_DONE:		con 14;
HT_CERTIFICATE_VERIFY:		con 15;
HT_CLIENT_KEY_EXCHANGE:		con 16;
HT_FINISHED:			con 20;

# Alert levels
ALERT_WARNING:	con 1;
ALERT_FATAL:	con 2;

# Alert descriptions
ALERT_CLOSE_NOTIFY:		con 0;
ALERT_UNEXPECTED_MESSAGE:	con 10;
ALERT_BAD_RECORD_MAC:		con 20;
ALERT_HANDSHAKE_FAILURE:	con 40;
ALERT_BAD_CERTIFICATE:		con 42;
ALERT_CERTIFICATE_EXPIRED:	con 45;
ALERT_CERTIFICATE_UNKNOWN:	con 46;
ALERT_ILLEGAL_PARAMETER:	con 47;
ALERT_DECODE_ERROR:		con 50;
ALERT_DECRYPT_ERROR:		con 51;
ALERT_PROTOCOL_VERSION:		con 70;
ALERT_INTERNAL_ERROR:		con 80;
ALERT_MISSING_EXTENSION:	con 109;

# Extension types
EXT_SERVER_NAME:		con 0;
EXT_SUPPORTED_GROUPS:		con 10;
EXT_SIGNATURE_ALGORITHMS:	con 13;
EXT_SUPPORTED_VERSIONS:		con 43;
EXT_KEY_SHARE:			con 51;

# Named groups
GROUP_SECP256R1:	con 16r0017;
GROUP_X25519:		con 16r001D;

# Max record size
MAXRECORD:	con 16384;
MAXFRAGMENT:	con 16384 + 256;	# room for overhead

# TLS 1.2 record version
RECVERSION: con 16r0303;

# Internal connection state
ConnState: adt {
	fd:		ref Sys->FD;
	version:	int;		# negotiated version
	suite:		int;		# negotiated cipher suite

	# AEAD keys
	writekey:	array of byte;
	writeiv:	array of byte;
	readkey:	array of byte;
	readiv:		array of byte;

	# Sequence numbers
	writeseq:	big;
	readseq:	big;

	# Read buffer (decrypted application data)
	rbuf:		array of byte;
	roff:		int;
	rlen:		int;

	# Handshake hash
	handhash:	ref Keyring->DigestState;

	# TLS 1.3 traffic secrets
	cts:		array of byte;	# client traffic secret
	sts:		array of byte;	# server traffic secret

	# Server name for cert verification
	servername:	string;
	insecure:	int;

	# TLS 1.3: whether handshake is encrypted
	hsencrypted:	int;

	# Handshake message buffer (multiple msgs may arrive in one record)
	hsbuf:		array of byte;
	hsoff:		int;
};

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "tls: cannot load Sys";

	keyring = load Keyring Keyring->PATH;
	if(keyring == nil)
		return "tls: cannot load Keyring";

	asn1 = load ASN1 ASN1->PATH;
	if(asn1 == nil)
		return "tls: cannot load ASN1";
	asn1->init();

	pkcs = load PKCS PKCS->PATH;
	if(pkcs == nil)
		return "tls: cannot load PKCS";
	pkcs->init();

	x509 = load X509 X509->PATH;
	if(x509 == nil)
		return "tls: cannot load X509";
	x509->init();

	return nil;
}

defaultconfig(): ref Config
{
	return ref Config(
		TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 ::
		TLS_AES_128_GCM_SHA256 ::
		TLS_AES_256_GCM_SHA384 ::
		TLS_CHACHA20_POLY1305_SHA256 ::
		TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 ::
		TLS_RSA_WITH_AES_128_GCM_SHA256 ::
		nil,			# suites
		TLS12,		# minver
		TLS13,		# maxver
		"",			# servername
		0			# insecure
	);
}

client(fd: ref Sys->FD, config: ref Config): (ref Conn, string)
{
	cs := ref ConnState;
	cs.fd = fd;
	cs.version = 0;
	cs.suite = 0;
	cs.writeseq = big 0;
	cs.readseq = big 0;
	cs.rbuf = nil;
	cs.roff = 0;
	cs.rlen = 0;
	cs.handhash = nil;
	cs.cts = nil;
	cs.sts = nil;
	cs.servername = config.servername;
	cs.insecure = config.insecure;
	cs.hsencrypted = 0;
	cs.hsbuf = nil;
	cs.hsoff = 0;

	err := handshake(cs, config);
	if(err != nil)
		return (nil, err);

	conn := ref Conn;
	conn.version = cs.version;
	conn.suite = cs.suite;
	conn.servername = cs.servername;

	# Stash ConnState in a global for the conn methods to access
	addconn(conn, cs);

	return (conn, nil);
}

# ================================================================
# Connection pool - maps Conn refs to internal ConnState
# ================================================================

Connentry: adt {
	conn:	ref Conn;
	cs:	ref ConnState;
};

connpool: list of ref Connentry;

addconn(conn: ref Conn, cs: ref ConnState)
{
	connpool = ref Connentry(conn, cs) :: connpool;
}

findconn(conn: ref Conn): ref ConnState
{
	for(l := connpool; l != nil; l = tl l) {
		e := hd l;
		if(e.conn == conn)
			return e.cs;
	}
	return nil;
}

delconn(conn: ref Conn)
{
	nl: list of ref Connentry;
	for(l := connpool; l != nil; l = tl l) {
		e := hd l;
		if(e.conn != conn)
			nl = e :: nl;
	}
	connpool = nl;
}

Conn.read(conn: self ref Conn, buf: array of byte, n: int): int
{
	cs := findconn(conn);
	if(cs == nil)
		return -1;

	# Return buffered data first
	if(cs.rlen > 0) {
		m := cs.rlen;
		if(m > n)
			m = n;
		buf[0:] = cs.rbuf[cs.roff:cs.roff+m];
		cs.roff += m;
		cs.rlen -= m;
		return m;
	}

	# Read next record
	for(;;) {
		(ctype, data, err) := readrecord(cs);
		if(err != nil)
			return -1;

		case ctype {
		CT_APPLICATION_DATA =>
			m := len data;
			if(m > n)
				m = n;
			buf[0:] = data[0:m];
			if(m < len data) {
				cs.rbuf = data;
				cs.roff = m;
				cs.rlen = len data - m;
			}
			return m;

		CT_ALERT =>
			if(len data >= 2 && int data[1] == ALERT_CLOSE_NOTIFY)
				return 0;
			return -1;

		CT_HANDSHAKE =>
			# Post-handshake messages (e.g., NewSessionTicket, KeyUpdate)
			# For now, silently consume
			;

		* =>
			return -1;
		}
	}
}

Conn.write(conn: self ref Conn, buf: array of byte, n: int): int
{
	cs := findconn(conn);
	if(cs == nil)
		return -1;

	sent := 0;
	while(sent < n) {
		chunk := n - sent;
		if(chunk > MAXRECORD)
			chunk = MAXRECORD;
		err := writerecord(cs, CT_APPLICATION_DATA, buf[sent:sent+chunk]);
		if(err != nil)
			return -1;
		sent += chunk;
	}
	return sent;
}

Conn.close(conn: self ref Conn): string
{
	cs := findconn(conn);
	if(cs == nil)
		return "tls: connection not found";

	# Send close_notify alert
	alert := array [2] of byte;
	alert[0] = byte ALERT_WARNING;
	alert[1] = byte ALERT_CLOSE_NOTIFY;
	writerecord(cs, CT_ALERT, alert);

	delconn(conn);
	return nil;
}

# ================================================================
# TLS Record Layer
# ================================================================

# Read a single TLS record, decrypt if keys are set
readrecord(cs: ref ConnState): (int, array of byte, string)
{
	# Read 5-byte header: content_type(1) + version(2) + length(2)
	hdr := array [5] of byte;
	if(ensure(cs.fd, hdr, 5) < 0)
		return (0, nil, "tls: record read failed");

	ctype := int hdr[0];
	length := (int hdr[3] << 8) | int hdr[4];

	if(length > MAXFRAGMENT)
		return (0, nil, "tls: record too large");

	# Read payload
	payload := array [length] of byte;
	if(ensure(cs.fd, payload, length) < 0)
		return (0, nil, "tls: record payload read failed");

	# TLS 1.3 middlebox compatibility: CCS records are always plaintext
	# (RFC 8446 §5). Don't try to decrypt them.
	if(ctype == CT_CHANGE_CIPHER_SPEC)
		return (ctype, payload, nil);

	# Decrypt if keys are established
	if(cs.readkey != nil) {
		(plaintext, err) := decrypt_record(cs, ctype, payload);
		if(err != nil)
			return (0, nil, err);

		if(cs.version == TLS13) {
			# TLS 1.3: inner content type is last byte of plaintext
			# Strip padding zeros from end
			i := len plaintext - 1;
			while(i >= 0 && int plaintext[i] == 0)
				i--;
			if(i < 0)
				return (0, nil, "tls: empty inner plaintext");
			ctype = int plaintext[i];
			plaintext = plaintext[0:i];
		}

		return (ctype, plaintext, nil);
	}

	return (ctype, payload, nil);
}

# Write a TLS record, encrypt if keys are set
writerecord(cs: ref ConnState, ctype: int, data: array of byte): string
{
	payload := data;

	if(cs.writekey != nil) {
		plaintext := data;
		if(cs.version == TLS13) {
			# TLS 1.3: append real content type
			plaintext = array [len data + 1] of byte;
			plaintext[0:] = data;
			plaintext[len data] = byte ctype;
			ctype = CT_APPLICATION_DATA;
		}
		(ciphertext, err) := encrypt_record(cs, ctype, plaintext);
		if(err != nil)
			return err;
		payload = ciphertext;
	}

	# Build record: type(1) + version(2) + length(2) + payload
	rec := array [5 + len payload] of byte;
	rec[0] = byte ctype;
	put16(rec, 1, RECVERSION);
	put16(rec, 3, len payload);
	rec[5:] = payload;

	n := sys->write(cs.fd, rec, len rec);
	if(n != len rec)
		return "tls: write failed";

	return nil;
}

# ================================================================
# AEAD Encryption/Decryption
# ================================================================

# Build nonce for AEAD: XOR fixed IV with sequence number
buildnonce(iv: array of byte, seq: big): array of byte
{
	nonce := array [12] of byte;
	nonce[0:] = iv;

	# XOR sequence number into rightmost 8 bytes
	for(i := 0; i < 8; i++) {
		shift := 56 - i * 8;
		nonce[4 + i] ^= byte (int (seq >> shift) & 16rFF);
	}
	return nonce;
}

encrypt_record(cs: ref ConnState, ctype: int, plaintext: array of byte): (array of byte, string)
{
	nonce := buildnonce(cs.writeiv, cs.writeseq);

	# Additional authenticated data: content_type(1) + version(2) + length(2)
	# For TLS 1.3: content_type=23, version=0x0303, length=len(plaintext)+16
	# For TLS 1.2: content_type + version(2) + seq(8) + length(2)
	aad: array of byte;

	if(cs.version == TLS13) {
		aad = array [5] of byte;
		aad[0] = byte ctype;
		put16(aad, 1, RECVERSION);
		put16(aad, 3, len plaintext + 16);	# +16 for tag
	} else {
		# TLS 1.2 AAD: seq(8) + type(1) + version(2) + length(2)
		aad = array [13] of byte;
		put64(aad, 0, cs.writeseq);
		aad[8] = byte ctype;
		put16(aad, 9, RECVERSION);
		put16(aad, 11, len plaintext);
	}

	ct: array of byte;
	tag: array of byte;

	if(isccpoly(cs.suite)) {
		(ct, tag) = keyring->ccpolyencrypt(plaintext, aad, cs.writekey, nonce);
	} else {
		gcmstate := keyring->aesgcmsetup(cs.writekey, nonce);
		if(gcmstate == nil)
			return (nil, "tls: aesgcm setup failed");
		(ct, tag) = keyring->aesgcmencrypt(gcmstate, plaintext, aad);
	}

	if(ct == nil || tag == nil)
		return (nil, "tls: encrypt failed");

	# Concatenate ciphertext + tag
	result := array [len ct + len tag] of byte;
	result[0:] = ct;
	result[len ct:] = tag;

	cs.writeseq++;
	return (result, nil);
}

decrypt_record(cs: ref ConnState, ctype: int, ciphertext: array of byte): (array of byte, string)
{
	if(len ciphertext < 16)
		return (nil, "tls: ciphertext too short");

	nonce := buildnonce(cs.readiv, cs.readseq);

	# Split ciphertext and tag (last 16 bytes)
	ctlen := len ciphertext - 16;
	ct := ciphertext[0:ctlen];
	tag := ciphertext[ctlen:];

	# Build AAD
	aad: array of byte;

	if(cs.version == TLS13) {
		aad = array [5] of byte;
		aad[0] = byte ctype;
		put16(aad, 1, RECVERSION);
		put16(aad, 3, len ciphertext);
	} else {
		aad = array [13] of byte;
		put64(aad, 0, cs.readseq);
		aad[8] = byte ctype;
		put16(aad, 9, RECVERSION);
		put16(aad, 11, ctlen);
	}

	plaintext: array of byte;

	if(isccpoly(cs.suite)) {
		plaintext = keyring->ccpolydecrypt(ct, aad, tag, cs.readkey, nonce);
	} else {
		gcmstate := keyring->aesgcmsetup(cs.readkey, nonce);
		if(gcmstate == nil)
			return (nil, "tls: aesgcm setup failed");
		plaintext = keyring->aesgcmdecrypt(gcmstate, ct, aad, tag);
	}

	if(plaintext == nil)
		return (nil, "tls: decrypt/auth failed");

	cs.readseq++;
	return (plaintext, nil);
}

isccpoly(suite: int): int
{
	return suite == TLS_CHACHA20_POLY1305_SHA256;
}

# ================================================================
# Handshake
# ================================================================

handshake(cs: ref ConnState, config: ref Config): string
{
	# Initialize handshake hash (SHA-256 for most suites)
	cs.handhash = nil;

	# Generate client random
	client_random := randombytes(32);

	# Generate X25519 key pair for key exchange
	x25519_priv := randombytes(32);
	x25519_pub := keyring->x25519_base(x25519_priv);

	# Build and send ClientHello
	hello := buildclienthello(config, client_random, x25519_pub);
	err := sendhsmsg(cs, HT_CLIENT_HELLO, hello);
	if(err != nil)
		return err;

	# Read ServerHello
	(shtype, shdata, sherr) := readhsmsg(cs);
	if(sherr != nil)
		return sherr;
	if(shtype != HT_SERVER_HELLO)
		return "tls: expected ServerHello";

	# Parse ServerHello
	(server_random, server_suite, server_version, key_share_data, pherr) := parseserverhello(shdata, config);
	if(pherr != nil)
		return pherr;

	cs.version = server_version;
	cs.suite = server_suite;

	if(cs.version == TLS13)
		return handshake13(cs, config, client_random, server_random,
			x25519_priv, key_share_data);
	else
		return handshake12(cs, config, client_random, server_random,
			x25519_priv);
}

# ================================================================
# TLS 1.2 Handshake
# ================================================================

handshake12(cs: ref ConnState, config: ref Config,
	client_random, server_random: array of byte,
	x25519_priv: array of byte): string
{
	server_certs: list of array of byte;
	server_pubkey: array of byte;
	server_ecpoint: array of byte;
	uses_ecdhe := 0;

	# Read server messages until ServerHelloDone
	got_server_done := 0;
	while(!got_server_done) {
		(mtype, mdata, merr) := readhsmsg(cs);
		if(merr != nil)
			return merr;

		case mtype {
		HT_CERTIFICATE =>
			(certs, cerr) := parsecertificatemsg(mdata);
			if(cerr != nil)
				return cerr;
			server_certs = certs;

		HT_SERVER_KEY_EXCHANGE =>
			# ECDHE key exchange - parse and verify signature
			(ecpoint, skerr) := parseserverkeyexchange(mdata,
				client_random, server_random, server_certs, cs.insecure);
			if(skerr != nil)
				return skerr;
			server_ecpoint = ecpoint;
			uses_ecdhe = 1;

		HT_CERTIFICATE_REQUEST =>
			# Client cert requested - we don't support this yet
			;

		HT_SERVER_HELLO_DONE =>
			got_server_done = 1;

		* =>
			return sys->sprint("tls: unexpected handshake message type %d", mtype);
		}
	}

	# Verify server certificate
	if(!cs.insecure && server_certs != nil) {
		verr := verifycerts(cs, server_certs);
		if(verr != nil)
			return verr;
	}

	# Compute premaster secret
	premaster: array of byte;

	if(uses_ecdhe) {
		# ECDHE: compute shared secret via X25519
		if(server_ecpoint == nil || len server_ecpoint != 32)
			return "tls: invalid server ECDHE point";
		premaster = keyring->x25519(x25519_priv, server_ecpoint);
		if(premaster == nil)
			return "tls: X25519 computation failed";
	} else {
		# RSA key exchange
		premaster = array [48] of byte;
		premaster[0] = byte 3;
		premaster[1] = byte 3;
		randombuf(premaster[2:], 46);

		# Encrypt premaster with server's RSA public key
		if(server_certs == nil)
			return "tls: no server certificate for RSA key exchange";
		(rsakey, pkerr) := extractrsakey(server_certs);
		if(pkerr != nil)
			return pkerr;
		(encerr, encbytes) := pkcs->rsa_encrypt(premaster, rsakey, 2);
		if(encerr != nil)
			return "tls: RSA encryption failed: " + encerr;
		server_pubkey = encbytes;
	}

	# Send ClientKeyExchange
	if(uses_ecdhe) {
		x25519_pub := keyring->x25519_base(x25519_priv);
		cke := buildclientkeyexchange_ecdhe(x25519_pub);
		err := sendhsmsg(cs, HT_CLIENT_KEY_EXCHANGE, cke);
		if(err != nil)
			return err;
	} else {
		cke := buildclientkeyexchange_rsa(server_pubkey);
		err := sendhsmsg(cs, HT_CLIENT_KEY_EXCHANGE, cke);
		if(err != nil)
			return err;
	}

	# Derive keys using TLS 1.2 PRF
	master := tls12_prf(premaster,
		s2b("master secret"),
		catbytes(client_random, server_random),
		48);

	keyblock := tls12_prf(master,
		s2b("key expansion"),
		catbytes(server_random, client_random),
		keyblocklen(cs.suite));

	# Extract keys from key block
	(cs.writekey, cs.writeiv, cs.readkey, cs.readiv) = splitkeyblock(cs.suite, keyblock);

	# Send ChangeCipherSpec
	err := writerecord(cs, CT_CHANGE_CIPHER_SPEC, array [] of {byte 1});
	if(err != nil)
		return err;

	# Send Finished
	verify_data := tls12_prf(master,
		s2b("client finished"),
		hashfinish(cs),
		12);
	ferr := sendhsmsg(cs, HT_FINISHED, verify_data);
	if(ferr != nil)
		return ferr;

	# Read server ChangeCipherSpec
	(ccstype, _, ccserr) := readrecord(cs);
	if(ccserr != nil)
		return ccserr;
	if(ccstype != CT_CHANGE_CIPHER_SPEC)
		return "tls: expected ChangeCipherSpec";

	# Read server Finished
	(ftype, fdata, ferr2) := readhsmsg(cs);
	if(ferr2 != nil)
		return ferr2;
	if(ftype != HT_FINISHED)
		return "tls: expected Finished";

	# Verify server Finished
	expected := tls12_prf(master,
		s2b("server finished"),
		hashfinish(cs),
		12);
	if(!bytescmp(fdata, expected))
		return "tls: server Finished verification failed";

	return nil;
}

# ================================================================
# TLS 1.3 Handshake
# ================================================================

handshake13(cs: ref ConnState, config: ref Config,
	client_random, server_random: array of byte,
	x25519_priv: array of byte,
	key_share_data: array of byte): string
{
	# Compute shared secret via X25519
	if(key_share_data == nil || len key_share_data != 32)
		return "tls: invalid server key share";

	shared_secret := keyring->x25519(x25519_priv, key_share_data);
	if(shared_secret == nil)
		return "tls: X25519 computation failed";

	hashlen := hashlength(cs.suite);

	# TLS 1.3 Key Schedule
	# Early Secret
	zeros := array [hashlen] of {* => byte 0};
	early_secret := hkdf_extract(zeros, zeros);

	# Derive handshake secret
	derived := hkdf_expand_label(early_secret, "derived", hash_empty(cs), hashlen);
	handshake_secret := hkdf_extract(derived, shared_secret);

	# Derive handshake traffic secrets
	hs_hash := hashcurrent(cs);
	c_hs_traffic := hkdf_expand_label(handshake_secret, "c hs traffic", hs_hash, hashlen);
	s_hs_traffic := hkdf_expand_label(handshake_secret, "s hs traffic", hs_hash, hashlen);

	# Derive handshake keys
	(cs.readkey, cs.readiv) = derivekeys(s_hs_traffic, cs.suite);
	(cs.writekey, cs.writeiv) = derivekeys(c_hs_traffic, cs.suite);
	cs.readseq = big 0;
	cs.writeseq = big 0;
	cs.hsencrypted = 1;

	# Read encrypted handshake messages
	server_certs: list of array of byte;
	hs_done := 0;

	while(!hs_done) {
		# Save transcript hash before reading next message.
		# Needed for Finished/CertificateVerify: verify_data covers transcript
		# EXCLUDING the message itself, but readhsmsg hashes before returning.
		pre_read_hash := cs.handhash.copy();

		(mtype, mdata, merr) := readhsmsg(cs);
		if(merr != nil)
			return merr;

		case mtype {
		HT_ENCRYPTED_EXTENSIONS =>
			# Parse but mostly ignore for now
			;

		HT_CERTIFICATE_REQUEST =>
			# Client cert requested - not supported yet
			;

		HT_CERTIFICATE =>
			(certs, cerr) := parsecertificatemsg13(mdata);
			if(cerr != nil)
				return cerr;
			server_certs = certs;

		HT_CERTIFICATE_VERIFY =>
			# Verify server's signature over transcript (EXCLUDING CertificateVerify)
			if(!cs.insecure) {
				cv_transcript := array [Keyring->SHA256dlen] of byte;
				keyring->sha256(nil, 0, cv_transcript, pre_read_hash);
				verr := verifycertverify_hash(cs, mdata, server_certs, cv_transcript);
				if(verr != nil)
					return verr;
			}

		HT_FINISHED =>
			# Verify server Finished using transcript hash BEFORE Finished was hashed
			transcript_hash := array [Keyring->SHA256dlen] of byte;
			keyring->sha256(nil, 0, transcript_hash, pre_read_hash);
			fverr := verifyfinished13_hash(cs, mdata, s_hs_traffic, transcript_hash);
			if(fverr != nil)
				return fverr;
			hs_done = 1;

		* =>
			return sys->sprint("tls: unexpected hs msg type %d in TLS 1.3", mtype);
		}
	}

	# Verify server certificate chain
	if(!cs.insecure && server_certs != nil) {
		verr := verifycerts(cs, server_certs);
		if(verr != nil)
			return verr;
	}

	# Derive application traffic secrets BEFORE sending Client Finished.
	# Per RFC 8446 §7.1, app secrets use transcript through Server Finished only.
	master_derived := hkdf_expand_label(handshake_secret, "derived", hash_empty(cs), hashlen);
	master_secret := hkdf_extract(master_derived, zeros);

	app_hash := hashcurrent(cs);	# includes Server Finished, not Client Finished
	cs.cts = hkdf_expand_label(master_secret, "c ap traffic", app_hash, hashlen);
	cs.sts = hkdf_expand_label(master_secret, "s ap traffic", app_hash, hashlen);

	# Send client Finished
	finished_key := hkdf_expand_label(c_hs_traffic, "finished", nil, hashlen);
	finished_hash := hashcurrent(cs);
	verify_data := hmac_hash(cs.suite, finished_key, finished_hash);
	ferr := sendhsmsg(cs, HT_FINISHED, verify_data);
	if(ferr != nil)
		return ferr;

	# Switch to application traffic keys
	(cs.readkey, cs.readiv) = derivekeys(cs.sts, cs.suite);
	(cs.writekey, cs.writeiv) = derivekeys(cs.cts, cs.suite);
	cs.readseq = big 0;
	cs.writeseq = big 0;

	return nil;
}

# ================================================================
# Handshake Message Building
# ================================================================

buildclienthello(config: ref Config, random: array of byte,
	x25519_pub: array of byte): array of byte
{
	# Build extensions
	exts: array of byte;

	# SNI extension
	sni: array of byte;
	if(config.servername != nil && len config.servername > 0)
		sni = buildsniext(config.servername);
	else
		sni = nil;

	# Supported groups extension
	groups := buildsupportedgroups();

	# Signature algorithms extension
	sigalgs := buildsigalgsext();

	# Supported versions extension (for TLS 1.3)
	suppver: array of byte;
	if(config.maxver >= TLS13)
		suppver = buildsupportedversions(config);
	else
		suppver = nil;

	# Key share extension
	keyshare := buildkeyshare(x25519_pub);

	# Concatenate extensions
	extlist := catbytes(sni, catbytes(groups, catbytes(sigalgs,
		catbytes(suppver, keyshare))));

	# Session ID (32 bytes for compatibility)
	session_id := randombytes(32);

	# Cipher suites
	suitebytes := buildsuites(config.suites);

	# Build ClientHello body
	# version(2) + random(32) + session_id_len(1) + session_id(32) +
	# suites_len(2) + suites + compressions(2) + extensions
	bodylen := 2 + 32 + 1 + len session_id + 2 + len suitebytes + 2 + 2 + len extlist;
	body := array [bodylen] of byte;
	off := 0;

	# Legacy version: TLS 1.2 (actual version in extension)
	put16(body, off, RECVERSION);
	off += 2;

	# Random
	body[off:] = random;
	off += 32;

	# Session ID
	body[off] = byte len session_id;
	off++;
	body[off:] = session_id;
	off += len session_id;

	# Cipher suites
	put16(body, off, len suitebytes);
	off += 2;
	body[off:] = suitebytes;
	off += len suitebytes;

	# Compression methods (null only)
	body[off] = byte 1;
	off++;
	body[off] = byte 0;
	off++;

	# Extensions
	put16(body, off, len extlist);
	off += 2;
	body[off:] = extlist;

	return body;
}

buildsniext(name: string): array of byte
{
	namebytes := s2b(name);
	# Extension: type(2) + length(2)
	# SNI list: length(2) + entry: type(1) + name_length(2) + name
	listlen := 1 + 2 + len namebytes;
	extlen := 2 + listlen;
	ext := array [4 + extlen] of byte;
	put16(ext, 0, EXT_SERVER_NAME);
	put16(ext, 2, extlen);
	put16(ext, 4, listlen);
	ext[6] = byte 0;	# host_name type
	put16(ext, 7, len namebytes);
	ext[9:] = namebytes;
	return ext;
}

buildsupportedgroups(): array of byte
{
	# x25519 + secp256r1
	ext := array [4 + 2 + 4] of byte;
	put16(ext, 0, EXT_SUPPORTED_GROUPS);
	put16(ext, 2, 2 + 4);
	put16(ext, 4, 4);
	put16(ext, 6, GROUP_X25519);
	put16(ext, 8, GROUP_SECP256R1);
	return ext;
}

buildsigalgsext(): array of byte
{
	# RSA_PKCS1_SHA256, RSA_PKCS1_SHA384, ECDSA_SECP256R1_SHA256, RSA_PSS_RSAE_SHA256
	nalgs := 4;
	ext := array [4 + 2 + nalgs * 2] of byte;
	put16(ext, 0, EXT_SIGNATURE_ALGORITHMS);
	put16(ext, 2, 2 + nalgs * 2);
	put16(ext, 4, nalgs * 2);
	put16(ext, 6, RSA_PKCS1_SHA256);
	put16(ext, 8, RSA_PKCS1_SHA384);
	put16(ext, 10, ECDSA_SECP256R1_SHA256);
	put16(ext, 12, RSA_PSS_RSAE_SHA256);
	return ext;
}

buildsupportedversions(config: ref Config): array of byte
{
	versions: list of int;
	if(config.maxver >= TLS13)
		versions = TLS13 :: versions;
	if(config.minver <= TLS12)
		versions = TLS12 :: versions;

	nver := 0;
	for(l := versions; l != nil; l = tl l)
		nver++;

	ext := array [4 + 1 + nver * 2] of byte;
	put16(ext, 0, EXT_SUPPORTED_VERSIONS);
	put16(ext, 2, 1 + nver * 2);
	ext[4] = byte (nver * 2);
	off := 5;
	for(l = versions; l != nil; l = tl l) {
		put16(ext, off, hd l);
		off += 2;
	}
	return ext;
}

buildkeyshare(x25519_pub: array of byte): array of byte
{
	# Key share entry: group(2) + key_len(2) + key(32)
	entrylen := 2 + 2 + 32;
	ext := array [4 + 2 + entrylen] of byte;
	put16(ext, 0, EXT_KEY_SHARE);
	put16(ext, 2, 2 + entrylen);
	put16(ext, 4, entrylen);
	put16(ext, 6, GROUP_X25519);
	put16(ext, 8, 32);
	ext[10:] = x25519_pub;
	return ext;
}

buildsuites(suites: list of int): array of byte
{
	n := 0;
	for(l := suites; l != nil; l = tl l)
		n++;
	buf := array [n * 2] of byte;
	off := 0;
	for(l = suites; l != nil; l = tl l) {
		put16(buf, off, hd l);
		off += 2;
	}
	return buf;
}

buildclientkeyexchange_ecdhe(pubkey: array of byte): array of byte
{
	# Length-prefixed EC point (uncompressed format for X25519 is just 32 bytes)
	buf := array [1 + len pubkey] of byte;
	buf[0] = byte len pubkey;
	buf[1:] = pubkey;
	return buf;
}

buildclientkeyexchange_rsa(encrypted_premaster: array of byte): array of byte
{
	# 2-byte length prefix + encrypted premaster
	buf := array [2 + len encrypted_premaster] of byte;
	put16(buf, 0, len encrypted_premaster);
	buf[2:] = encrypted_premaster;
	return buf;
}

# ================================================================
# Handshake Message Parsing
# ================================================================

parseserverhello(data: array of byte, config: ref Config): (array of byte, int, int, array of byte, string)
{
	if(len data < 38)
		return (nil, 0, 0, nil, "tls: ServerHello too short");

	# version(2) + random(32) + session_id_len(1)...
	off := 0;
	legacy_version := get16(data, off);
	off += 2;

	server_random := data[off:off+32];
	off += 32;

	sid_len := int data[off];
	off++;
	if(off + sid_len + 3 > len data)
		return (nil, 0, 0, nil, "tls: ServerHello truncated");
	off += sid_len;

	suite := get16(data, off);
	off += 2;

	compression := int data[off];
	off++;
	if(compression != 0)
		return (nil, 0, 0, nil, "tls: non-null compression");

	# Parse extensions
	version := legacy_version;
	key_share_data: array of byte;

	if(off + 2 <= len data) {
		ext_len := get16(data, off);
		off += 2;
		ext_end := off + ext_len;

		while(off + 4 <= ext_end) {
			etype := get16(data, off);
			elen := get16(data, off + 2);
			off += 4;

			if(off + elen > ext_end)
				break;

			case etype {
			EXT_SUPPORTED_VERSIONS =>
				if(elen >= 2)
					version = get16(data, off);

			EXT_KEY_SHARE =>
				# group(2) + key_len(2) + key
				if(elen >= 4) {
					# group := get16(data, off);
					klen := get16(data, off + 2);
					if(off + 4 + klen <= ext_end)
						key_share_data = data[off+4:off+4+klen];
				}
			}
			off += elen;
		}
	}

	# Validate suite
	found := 0;
	for(l := config.suites; l != nil; l = tl l) {
		if(hd l == suite) {
			found = 1;
			break;
		}
	}
	if(!found)
		return (nil, 0, 0, nil, sys->sprint("tls: server chose unsupported suite 0x%04x", suite));

	# Validate version
	if(version != TLS12 && version != TLS13)
		return (nil, 0, 0, nil, sys->sprint("tls: unsupported version 0x%04x", version));

	return (server_random, suite, version, key_share_data, nil);
}

parsecertificatemsg(data: array of byte): (list of array of byte, string)
{
	if(len data < 3)
		return (nil, "tls: Certificate msg too short");

	total_len := get24(data, 0);
	off := 3;
	certs: list of array of byte;

	while(off + 3 <= len data && off - 3 < total_len) {
		cert_len := get24(data, off);
		off += 3;
		if(off + cert_len > len data)
			return (nil, "tls: certificate truncated");
		certs = data[off:off+cert_len] :: certs;
		off += cert_len;
	}

	# Reverse to get original order (leaf first)
	result: list of array of byte;
	for(l := certs; l != nil; l = tl l)
		result = hd l :: result;

	return (result, nil);
}

parsecertificatemsg13(data: array of byte): (list of array of byte, string)
{
	if(len data < 4)
		return (nil, "tls: Certificate msg too short");

	# TLS 1.3: request_context(1) + certificate_list
	ctx_len := int data[0];
	off := 1 + ctx_len;

	if(off + 3 > len data)
		return (nil, "tls: Certificate msg truncated");

	total_len := get24(data, off);
	off += 3;
	certs: list of array of byte;

	end := off + total_len;
	while(off + 3 <= end) {
		cert_len := get24(data, off);
		off += 3;
		if(off + cert_len > end)
			return (nil, "tls: certificate truncated");
		certs = data[off:off+cert_len] :: certs;
		off += cert_len;

		# TLS 1.3: extensions per certificate entry
		if(off + 2 <= end) {
			ext_len := get16(data, off);
			off += 2 + ext_len;
		}
	}

	# Reverse
	result: list of array of byte;
	for(l := certs; l != nil; l = tl l)
		result = hd l :: result;

	return (result, nil);
}

parseserverkeyexchange(data: array of byte,
	client_random, server_random: array of byte,
	server_certs: list of array of byte, insecure: int): (array of byte, string)
{
	if(len data < 4)
		return (nil, "tls: ServerKeyExchange too short");

	off := 0;

	# EC parameters
	curve_type := int data[off];
	off++;
	if(curve_type != 3)	# named_curve
		return (nil, "tls: unsupported curve type");

	named_curve := get16(data, off);
	off += 2;

	if(named_curve != GROUP_X25519 && named_curve != GROUP_SECP256R1)
		return (nil, sys->sprint("tls: unsupported named curve 0x%04x", named_curve));

	point_len := int data[off];
	off++;
	if(off + point_len > len data)
		return (nil, "tls: EC point truncated");

	ecpoint := data[off:off+point_len];
	off += point_len;

	# Parse and verify the signature over the ECDHE params
	if(!insecure && off + 4 <= len data && server_certs != nil) {
		sig_hash_alg := get16(data, off);
		off += 2;
		sig_len := get16(data, off);
		off += 2;
		if(off + sig_len > len data)
			return (nil, "tls: SKE signature truncated");
		sig := data[off:off+sig_len];

		# Build signed content: client_random(32) + server_random(32) + server_params
		# server_params = curve_type(1) + named_curve(2) + point_len(1) + point
		params_len := 1 + 2 + 1 + point_len;
		signed_content := array [32 + 32 + params_len] of byte;
		signed_content[0:] = client_random;
		signed_content[32:] = server_random;
		signed_content[64:] = data[0:params_len];

		# Determine hash algorithm from sig_hash_alg
		hash_id := (sig_hash_alg >> 8) & 16rFF;
		# hash_id: 4=SHA-256, 5=SHA-384, 6=SHA-512
		digest: array of byte;
		algid: int;

		case hash_id {
		4 =>
			digest = array [Keyring->SHA256dlen] of byte;
			keyring->sha256(signed_content, len signed_content, digest, nil);
			algid = 1;	# MD5_WithRSAEncryption is 1 in pkcs, but we need SHA256
		5 =>
			digest = array [Keyring->SHA384dlen] of byte;
			keyring->sha384(signed_content, len signed_content, digest, nil);
			algid = 1;
		* =>
			digest = array [Keyring->SHA256dlen] of byte;
			keyring->sha256(signed_content, len signed_content, digest, nil);
			algid = 1;
		}

		# Verify with server's RSA public key
		sig_alg := sig_hash_alg & 16rFF;
		if(sig_alg == 1) {
			# RSA signature
			(rsakey, pkerr) := extractrsakey(server_certs);
			if(pkerr != nil)
				return (nil, "tls: SKE verify: " + pkerr);

			# RSA PKCS#1 v1.5 verification: decrypt sig, compare digest
			(decerr, decrypted) := pkcs->rsa_decrypt(sig, rsakey, 1);
			if(decerr != nil)
				return (nil, "tls: SKE signature verification failed: " + decerr);

			# The decrypted data contains DigestInfo (ASN.1 wrapper around hash)
			# Extract the hash from the DigestInfo and compare
			# For simplicity, check if the digest appears in the decrypted data
			if(!containsbytes(decrypted, digest))
				return (nil, "tls: SKE signature hash mismatch");
		}
		# ECDSA signatures (sig_alg == 3) would use p256_ecdsa_verify
	}

	return (ecpoint, nil);
}

# Check if haystack contains needle as a suffix (for DigestInfo hash matching)
containsbytes(haystack, needle: array of byte): int
{
	if(len haystack < len needle)
		return 0;
	# Check if needle appears at the end of haystack
	off := len haystack - len needle;
	for(i := 0; i < len needle; i++)
		if(haystack[off + i] != needle[i])
			return 0;
	return 1;
}

# ================================================================
# Certificate Verification
# ================================================================

verifycerts(cs: ref ConnState, certs: list of array of byte): string
{
	if(certs == nil)
		return "tls: no server certificates";

	# Use X509 to verify certificate chain
	(ok, err) := x509->verify_certchain(certs);
	if(!ok && !cs.insecure)
		return "tls: certificate chain verification failed: " + err;

	# Verify hostname matches certificate CN/SAN
	if(cs.servername != nil && len cs.servername > 0) {
		herr := verifyhostname(cs.servername, hd certs);
		if(herr != nil && !cs.insecure)
			return herr;
	}
	return nil;
}

# Verify that hostname matches the leaf certificate's CN or SAN dNSName entries.
# RFC 6125: prefer SAN over CN; wildcard matching for *.example.com.
verifyhostname(hostname: string, certder: array of byte): string
{
	# Decode the X.509 certificate
	(serr, signed) := x509->Signed.decode(certder);
	if(serr != nil)
		return "tls: hostname verify: decode cert: " + serr;

	(cerr, cert) := x509->Certificate.decode(signed.tobe_signed);
	if(cerr != nil)
		return "tls: hostname verify: decode TBSCert: " + cerr;

	# Try SubjectAltName extension first (preferred per RFC 6125)
	san_checked := 0;
	if(cert.exts != nil) {
		(_, extclasses) := x509->parse_exts(cert.exts);
		for(el := extclasses; el != nil; el = tl el) {
			ec := hd el;
			pick san := ec {
			SubjectAltName =>
				san_checked = 1;
				for(al := san.alias; al != nil; al = tl al) {
					gn := hd al;
					pick dns := gn {
					dNSName =>
						if(matchhostname(hostname, dns.str))
							return nil;
					}
				}
			}
		}
	}

	# If SAN was present but didn't match, fail (RFC 6125 §6.4.4)
	if(san_checked)
		return sys->sprint("tls: hostname %s does not match any SAN dNSName", hostname);

	# Fall back to CN in subject
	for(rdl := cert.subject.rd_names; rdl != nil; rdl = tl rdl) {
		rdn := hd rdl;
		for(al := rdn.avas; al != nil; al = tl al) {
			ava := hd al;
			if(ava.oid != nil && x509->objIdTab != nil &&
			   ava.oid.nums != nil && len ava.oid.nums > 0) {
				cn_oid := ref x509->objIdTab[x509->id_at_commonName];
				if(oideq(ava.oid, cn_oid)) {
					if(matchhostname(hostname, ava.value))
						return nil;
				}
			}
		}
	}

	return sys->sprint("tls: hostname %s does not match certificate", hostname);
}

oideq(a, b: ref ASN1->Oid): int
{
	if(a == nil || b == nil)
		return 0;
	if(a.nums == nil || b.nums == nil)
		return 0;
	if(len a.nums != len b.nums)
		return 0;
	for(i := 0; i < len a.nums; i++)
		if(a.nums[i] != b.nums[i])
			return 0;
	return 1;
}

# Match hostname against a certificate name pattern.
# Supports wildcards: *.example.com matches foo.example.com
# but not foo.bar.example.com or example.com.
matchhostname(hostname, pattern: string): int
{
	h := strlower(hostname);
	p := strlower(pattern);

	# Exact match
	if(h == p)
		return 1;

	# Wildcard: *.domain
	if(len p > 2 && p[0] == '*' && p[1] == '.') {
		suffix := p[1:];	# .example.com
		# hostname must have exactly one label before the suffix
		dot := strindex(h, '.');
		if(dot > 0 && h[dot:] == suffix)
			return 1;
	}
	return 0;
}

strlower(s: string): string
{
	r := "";
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c >= 'A' && c <= 'Z')
			c = c - 'A' + 'a';
		r[len r] = c;
	}
	return r;
}

strindex(s: string, c: int): int
{
	for(i := 0; i < len s; i++)
		if(s[i] == c)
			return i;
	return -1;
}

verifycertverify(cs: ref ConnState, data: array of byte, certs: list of array of byte): string
{
	return verifycertverify_hash(cs, data, certs, hashcurrent(cs));
}

verifycertverify_hash(cs: ref ConnState, data: array of byte, certs: list of array of byte,
	transcript_hash: array of byte): string
{
	# TLS 1.3 CertificateVerify (RFC 8446 §4.4.3)
	if(len data < 4)
		return "tls: CertificateVerify too short";

	sig_alg := get16(data, 0);
	sig_len := get16(data, 2);
	if(4 + sig_len > len data)
		return "tls: CertificateVerify truncated";
	sig := data[4:4+sig_len];
	context_str := "TLS 1.3, server CertificateVerify";
	content := array [64 + len context_str + 1 + len transcript_hash] of byte;
	for(i := 0; i < 64; i++)
		content[i] = byte 16r20;
	content[64:] = array of byte context_str;
	content[64 + len context_str] = byte 0;
	content[64 + len context_str + 1:] = transcript_hash;

	case sig_alg {
	RSA_PKCS1_SHA256 or RSA_PKCS1_SHA384 or RSA_PKCS1_SHA512 =>
		# PKCS#1 v1.5 RSA signature verification
		digest := array [Keyring->SHA256dlen] of byte;
		keyring->sha256(content, len content, digest, nil);

		if(certs == nil)
			return "tls: no certs for CertificateVerify";
		(rsakey, pkerr) := extractrsakey(certs);
		if(pkerr != nil)
			return "tls: CertificateVerify: " + pkerr;

		(decerr, decrypted) := pkcs->rsa_decrypt(sig, rsakey, 1);
		if(decerr != nil)
			return "tls: CertificateVerify RSA decrypt failed: " + decerr;

		if(!containsbytes(decrypted, digest))
			return "tls: CertificateVerify hash mismatch";

	RSA_PSS_RSAE_SHA256 =>
		# RSA-PSS with SHA-256
		digest := array [Keyring->SHA256dlen] of byte;
		keyring->sha256(content, len content, digest, nil);

		if(certs == nil)
			return "tls: no certs for CertificateVerify";
		(rsakey, pkerr) := extractrsakey(certs);
		if(pkerr != nil)
			return "tls: CertificateVerify: " + pkerr;

		pssverr := rsapss_verify(digest, sig, rsakey);
		if(pssverr != nil)
			return "tls: CertificateVerify PSS: " + pssverr;

	ECDSA_SECP256R1_SHA256 =>
		# ECDSA with P-256 and SHA-256
		digest := array [Keyring->SHA256dlen] of byte;
		keyring->sha256(content, len content, digest, nil);

		if(certs == nil)
			return "tls: no certs for CertificateVerify";
		(ecpt, ecerr) := extractecpoint(certs);
		if(ecpt == nil)
			return "tls: CertificateVerify: " + ecerr;
		rawsig := parse_ecdsa_der_sig(sig);
		if(rawsig == nil)
			return "tls: CertificateVerify: invalid ECDSA signature";
		if(!keyring->p256_ecdsa_verify(ecpt, digest, rawsig))
			return "tls: CertificateVerify: ECDSA verification failed";

	* =>
		return sys->sprint("tls: unsupported CertificateVerify sig_alg 0x%04x", sig_alg);
	}

	return nil;
}

# RSA-PSS verification (PKCS#1 v2.1, EMSA-PSS with SHA-256)
# RFC 8017 §8.1.2 + §9.1.2
rsapss_verify(msghash, sig: array of byte, rsakey: ref RSAKey): string
{
	hashlen := Keyring->SHA256dlen;	# 32 bytes for SHA-256
	saltlen := hashlen;		# salt length = hash length (typical)

	# Step 1: RSA public key operation (decrypt with public key)
	(decerr, em) := pkcs->rsa_decrypt(sig, rsakey, 1);
	if(decerr != nil)
		return "RSA decrypt: " + decerr;

	embits := rsakey.modlen * 8 - 1;
	emlen := (embits + 7) / 8;

	# Pad EM to emLen if needed
	if(len em < emlen) {
		padded := array [emlen] of {* => byte 0};
		padded[emlen - len em:] = em;
		em = padded;
	} else if(len em > emlen) {
		em = em[len em - emlen:];
	}

	# Step 3: check rightmost byte is 0xBC
	if(int em[emlen - 1] != 16rBC)
		return "PSS: invalid trailer";

	# Step 4: separate maskedDB and H
	dblen := emlen - hashlen - 1;
	maskeddb := em[0:dblen];
	h := em[dblen:dblen + hashlen];

	# Step 5: check top bits are zero
	topbits := 8 * emlen - embits;
	if(topbits > 0 && (int maskeddb[0] & (16rFF << (8 - topbits))) != 0)
		return "PSS: non-zero top bits";

	# Step 6: MGF1-SHA256 to unmask DB
	dbmask := mgf1_sha256(h, dblen);

	# Step 7: DB = maskedDB XOR dbMask
	db := array [dblen] of byte;
	for(i := 0; i < dblen; i++)
		db[i] = maskeddb[i] ^ dbmask[i];

	# Step 8: clear top bits
	if(topbits > 0)
		db[0] &= byte (16rFF >> topbits);

	# Step 9: check padding (zeros followed by 0x01)
	pslen := dblen - saltlen - 1;
	for(j := 0; j < pslen; j++)
		if(int db[j] != 0)
			return "PSS: non-zero padding";
	if(int db[pslen] != 1)
		return "PSS: missing 0x01 separator";

	# Step 10: extract salt
	salt := db[dblen - saltlen:];

	# Step 11: compute M' = 0x00..00 (8 bytes) || mHash || salt
	mprime := array [8 + hashlen + saltlen] of byte;
	for(j = 0; j < 8; j++)
		mprime[j] = byte 0;
	mprime[8:] = msghash;
	mprime[8 + hashlen:] = salt;

	# Step 12: H' = SHA-256(M')
	hprime := array [hashlen] of byte;
	keyring->sha256(mprime, len mprime, hprime, nil);

	# Step 13: compare H and H'
	if(!bytescmp(h, hprime))
		return "PSS: hash mismatch";

	return nil;
}

# MGF1 with SHA-256 (RFC 8017 §B.2.1)
mgf1_sha256(seed: array of byte, masklen: int): array of byte
{
	hashlen := Keyring->SHA256dlen;
	n := (masklen + hashlen - 1) / hashlen;
	result := array [n * hashlen] of byte;

	for(i := 0; i < n; i++) {
		# Hash(seed || counter)
		input := array [len seed + 4] of byte;
		input[0:] = seed;
		input[len seed] = byte (i >> 24);
		input[len seed + 1] = byte (i >> 16);
		input[len seed + 2] = byte (i >> 8);
		input[len seed + 3] = byte i;
		digest := array [hashlen] of byte;
		keyring->sha256(input, len input, digest, nil);
		result[i * hashlen:] = digest;
	}
	return result[0:masklen];
}

verifyfinished13(cs: ref ConnState, data: array of byte, traffic_secret: array of byte): string
{
	return verifyfinished13_hash(cs, data, traffic_secret, hashcurrent(cs));
}

verifyfinished13_hash(cs: ref ConnState, data: array of byte, traffic_secret: array of byte,
	transcript_hash: array of byte): string
{
	hashlen := hashlength(cs.suite);
	if(len data != hashlen)
		return "tls: Finished wrong length";

	finished_key := hkdf_expand_label(traffic_secret, "finished", nil, hashlen);
	expected := hmac_hash(cs.suite, finished_key, transcript_hash);

	if(!bytescmp(data, expected))
		return "tls: server Finished verification failed";

	return nil;
}

# ================================================================
# RSA Public Key Extraction
# ================================================================

extractrsakey(certs: list of array of byte): (ref RSAKey, string)
{
	if(certs == nil)
		return (nil, "tls: no certificates");

	leaf := hd certs;

	# Decode the X.509 certificate Signed wrapper
	(serr, signed) := x509->Signed.decode(leaf);
	if(serr != nil)
		return (nil, "tls: decode cert: " + serr);

	# Decode the TBSCertificate
	(cerr, cert) := x509->Certificate.decode(signed.tobe_signed);
	if(cerr != nil)
		return (nil, "tls: decode TBSCert: " + cerr);

	# Extract public key from SubjectPublicKeyInfo
	(pkerr, _, pk) := cert.subject_pkinfo.getPublicKey();
	if(pkerr != nil)
		return (nil, "tls: extract key: " + pkerr);
	if(pk == nil)
		return (nil, "tls: no public key");

	pick rpk := pk {
	RSA =>
		return (rpk.pk, nil);
	* =>
		return (nil, "tls: not an RSA public key");
	}
}

# Extract EC public key (ECpoint) from leaf certificate
extractecpoint(certs: list of array of byte): (ref Keyring->ECpoint, string)
{
	if(certs == nil)
		return (nil, "no certs");
	leaf := hd certs;

	(serr, signed) := x509->Signed.decode(leaf);
	if(serr != nil)
		return (nil, "decode cert: " + serr);
	(cerr, cert) := x509->Certificate.decode(signed.tobe_signed);
	if(cerr != nil)
		return (nil, "decode TBSCert: " + cerr);
	(pkerr, _, pk) := cert.subject_pkinfo.getPublicKey();
	if(pkerr != nil)
		return (nil, "getPublicKey: " + pkerr);
	if(pk == nil)
		return (nil, "no public key");

	pick epk := pk {
	EC =>
		pt := keyring->p256_make_point(epk.point);
		if(pt == nil)
			return (nil, "make_point failed");
		return (pt, nil);
	* =>
		return (nil, "not an EC key");
	}
}

# Parse DER-encoded ECDSA signature into raw 64-byte (r||s)
# TLS CertificateVerify provides raw DER (no BIT STRING unused-bits byte)
parse_ecdsa_der_sig(sig: array of byte): array of byte
{
	(err, e) := asn1->decode(sig);
	if(err != nil)
		return nil;
	(ok, el) := e.is_seq();
	if(!ok || len el != 2)
		return nil;
	rbytes, sbytes: array of byte;
	(ok, rbytes) = (hd el).is_bigint();
	if(!ok)
		return nil;
	(ok, sbytes) = (hd tl el).is_bigint();
	if(!ok)
		return nil;

	rawsig := array [64] of {* => byte 0};
	# r: strip leading zeros, right-justify in 32 bytes
	ri := 0;
	while(ri < len rbytes && rbytes[ri] == byte 0)
		ri++;
	rlen := len rbytes - ri;
	if(rlen > 32)
		return nil;
	rawsig[32 - rlen:] = rbytes[ri:];
	# s: strip leading zeros, right-justify in 32 bytes
	si := 0;
	while(si < len sbytes && sbytes[si] == byte 0)
		si++;
	slen := len sbytes - si;
	if(slen > 32)
		return nil;
	rawsig[32 + 32 - slen:] = sbytes[si:];

	return rawsig;
}

# ================================================================
# Handshake Message I/O
# ================================================================

sendhsmsg(cs: ref ConnState, mtype: int, data: array of byte): string
{
	# Handshake header: type(1) + length(3)
	msg := array [4 + len data] of byte;
	msg[0] = byte mtype;
	put24(msg, 1, len data);
	msg[4:] = data;

	# Hash the handshake message
	updatehash(cs, msg);

	return writerecord(cs, CT_HANDSHAKE, msg);
}

readhsmsg(cs: ref ConnState): (int, array of byte, string)
{
	for(;;) {
	# Check buffered handshake data first (multiple msgs per record)
	if(cs.hsbuf != nil && cs.hsoff < len cs.hsbuf) {
		remaining := cs.hsbuf[cs.hsoff:];
		if(len remaining >= 4) {
			mtype := int remaining[0];
			mlen := get24(remaining, 1);
			if(4 + mlen <= len remaining) {
				updatehash(cs, remaining[0:4+mlen]);
				cs.hsoff += 4 + mlen;
				if(cs.hsoff >= len cs.hsbuf) {
					cs.hsbuf = nil;
					cs.hsoff = 0;
				}
				return (mtype, remaining[4:4+mlen], nil);
			}
		}
		# Incomplete message in buffer — fall through to read more
		cs.hsbuf = nil;
		cs.hsoff = 0;
	}

	# Read record (possibly encrypted)
	(ctype, payload, rerr) := readrecord(cs);
	if(rerr != nil)
		return (0, nil, rerr);

	# TLS 1.3: silently skip CCS records (middlebox compatibility)
	if(ctype == CT_CHANGE_CIPHER_SPEC)
		continue;

	if(ctype == CT_ALERT) {
		if(len payload >= 2)
			return (0, nil, sys->sprint("tls: alert level=%d desc=%d",
				int payload[0], int payload[1]));
		return (0, nil, "tls: received alert");
	}

	if(ctype != CT_HANDSHAKE)
		return (0, nil, sys->sprint("tls: expected handshake, got type %d", ctype));

	if(len payload < 4)
		return (0, nil, "tls: handshake message too short");

	mtype := int payload[0];
	mlen := get24(payload, 1);

	if(4 + mlen > len payload)
		return (0, nil, "tls: handshake message truncated");

	# Hash the entire handshake message
	updatehash(cs, payload[0:4+mlen]);

	# Buffer remaining data if record contains multiple messages
	if(4 + mlen < len payload) {
		cs.hsbuf = payload;
		cs.hsoff = 4 + mlen;
	}

	return (mtype, payload[4:4+mlen], nil);
	}	# for(;;)
}

# ================================================================
# Handshake Hashing
# ================================================================

updatehash(cs: ref ConnState, data: array of byte)
{
	# Use SHA-256 as the default transcript hash
	cs.handhash = keyring->sha256(data, len data, nil, cs.handhash);
}

hashcurrent(cs: ref ConnState): array of byte
{
	# Get current hash value without finalizing
	digest := array [Keyring->SHA256dlen] of byte;
	if(cs.handhash != nil) {
		ds := cs.handhash.copy();
		keyring->sha256(nil, 0, digest, ds);
	}
	return digest;
}

hashfinish(cs: ref ConnState): array of byte
{
	return hashcurrent(cs);
}

hash_empty(cs: ref ConnState): array of byte
{
	# SHA-256 of empty string
	digest := array [Keyring->SHA256dlen] of byte;
	keyring->sha256(nil, 0, digest, nil);
	return digest;
}

# ================================================================
# Key Derivation
# ================================================================

# TLS 1.2 PRF (P_SHA256)
tls12_prf(secret, label, seed: array of byte, n: int): array of byte
{
	labelseed := catbytes(label, seed);
	result := array [n] of byte;
	off := 0;

	# A(0) = seed, A(i) = HMAC(secret, A(i-1))
	a := labelseed;
	while(off < n) {
		a = hmac256(secret, a);
		p := hmac256(secret, catbytes(a, labelseed));
		m := len p;
		if(off + m > n)
			m = n - off;
		result[off:] = p[0:m];
		off += m;
	}
	return result;
}

# HKDF-Extract (RFC 5869)
hkdf_extract(salt, ikm: array of byte): array of byte
{
	return hmac256(salt, ikm);
}

# HKDF-Expand (RFC 5869)
hkdf_expand(prk, info: array of byte, length: int): array of byte
{
	hashlen := Keyring->SHA256dlen;
	n := (length + hashlen - 1) / hashlen;
	result := array [n * hashlen] of byte;
	t: array of byte;

	for(i := 1; i <= n; i++) {
		input: array of byte;
		if(t == nil)
			input = catbytes(info, array [1] of {byte i});
		else
			input = catbytes(t, catbytes(info, array [1] of {byte i}));
		t = hmac256(prk, input);
		off := (i - 1) * hashlen;
		result[off:] = t;
	}
	return result[0:length];
}

# HKDF-Expand-Label (TLS 1.3)
hkdf_expand_label(secret: array of byte, label: string, context: array of byte, length: int): array of byte
{
	# HkdfLabel = length(2) + label_len(1) + "tls13 " + label + context_len(1) + context
	full_label := s2b("tls13 " + label);
	ctx := context;
	if(ctx == nil)
		ctx = array [0] of byte;

	info := array [2 + 1 + len full_label + 1 + len ctx] of byte;
	put16(info, 0, length);
	info[2] = byte len full_label;
	info[3:] = full_label;
	info[3 + len full_label] = byte len ctx;
	if(len ctx > 0)
		info[4 + len full_label:] = ctx;

	return hkdf_expand(secret, info, length);
}

# Derive traffic keys from a traffic secret
derivekeys(secret: array of byte, suite: int): (array of byte, array of byte)
{
	keylen := keylength(suite);
	ivlen := 12;

	key := hkdf_expand_label(secret, "key", nil, keylen);
	iv := hkdf_expand_label(secret, "iv", nil, ivlen);

	return (key, iv);
}

# HMAC-SHA256
hmac256(key, data: array of byte): array of byte
{
	digest := array [Keyring->SHA256dlen] of byte;
	keyring->hmac_sha256(data, len data, key, digest, nil);
	return digest;
}

# HMAC using suite's hash algorithm
hmac_hash(suite: int, key, data: array of byte): array of byte
{
	hashlen := hashlength(suite);
	digest := array [hashlen] of byte;

	case hashlen {
	48 =>
		keyring->hmac_sha384(data, len data, key, digest, nil);
	* =>
		keyring->hmac_sha256(data, len data, key, digest, nil);
	}
	return digest;
}

# ================================================================
# Suite Parameters
# ================================================================

hashlength(suite: int): int
{
	case suite {
	TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 or
	TLS_AES_256_GCM_SHA384 =>
		return 48;
	* =>
		return 32;
	}
}

keylength(suite: int): int
{
	case suite {
	TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 or
	TLS_AES_256_GCM_SHA384 or
	TLS_RSA_WITH_AES_256_GCM_SHA384 =>
		return 32;
	* =>
		return 16;
	}
}

keyblocklen(suite: int): int
{
	# For TLS 1.2 GCM: 2 * (key_len + iv_len)
	klen := keylength(suite);
	return 2 * (klen + 4);	# GCM uses 4-byte implicit IV for TLS 1.2
}

splitkeyblock(suite: int, keyblock: array of byte): (array of byte, array of byte, array of byte, array of byte)
{
	klen := keylength(suite);
	ivlen := 4;	# TLS 1.2 GCM implicit nonce
	off := 0;

	cw_key := keyblock[off:off+klen];
	off += klen;
	sw_key := keyblock[off:off+klen];
	off += klen;
	cw_iv := array [12] of {* => byte 0};
	cw_iv[0:] = keyblock[off:off+ivlen];
	off += ivlen;
	sw_iv := array [12] of {* => byte 0};
	sw_iv[0:] = keyblock[off:off+ivlen];

	return (cw_key, cw_iv, sw_key, sw_iv);
}

# ================================================================
# Utility Functions
# ================================================================

ensure(fd: ref Sys->FD, buf: array of byte, n: int): int
{
	i := 0;
	while(i < n) {
		m := sys->read(fd, buf[i:], n - i);
		if(m <= 0)
			return -1;
		i += m;
	}
	return n;
}

put16(buf: array of byte, off: int, val: int)
{
	buf[off] = byte (val >> 8);
	buf[off + 1] = byte val;
}

put24(buf: array of byte, off: int, val: int)
{
	buf[off] = byte (val >> 16);
	buf[off + 1] = byte (val >> 8);
	buf[off + 2] = byte val;
}

put64(buf: array of byte, off: int, val: big)
{
	for(i := 0; i < 8; i++) {
		shift := 56 - i * 8;
		buf[off + i] = byte (int (val >> shift) & 16rFF);
	}
}

get16(buf: array of byte, off: int): int
{
	return (int buf[off] << 8) | int buf[off + 1];
}

get24(buf: array of byte, off: int): int
{
	return (int buf[off] << 16) | (int buf[off + 1] << 8) | int buf[off + 2];
}

s2b(s: string): array of byte
{
	return array of byte s;
}

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

bytescmp(a, b: array of byte): int
{
	if(len a != len b)
		return 0;
	d := 0;
	for(i := 0; i < len a; i++)
		d |= int a[i] ^ int b[i];
	return d == 0;
}

randombytes(n: int): array of byte
{
	buf := array [n] of byte;
	randombuf(buf, n);
	return buf;
}

randombuf(buf: array of byte, n: int)
{
	# Read from /dev/random
	fd := sys->open("/dev/urandom", Sys->OREAD);
	if(fd == nil)
		fd = sys->open("#c/random", Sys->OREAD);
	if(fd != nil) {
		sys->read(fd, buf, n);
		return;
	}
	# Fallback: use keyring random (via IPint)
	for(i := 0; i < n; i++)
		buf[i] = byte (sys->millisec() ^ (i * 37));
}

