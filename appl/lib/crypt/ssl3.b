#
# SSL 3.0 protocol 
#
implement SSL3;

include "sys.m";				
	sys					: Sys;

include "keyring.m";				
	keyring					: Keyring;
	IPint, DigestState			: import keyring;

include "security.m";				
	random					: Random;
	ssl					: SSL;

include "daytime.m";				
	daytime					: Daytime;

include "asn1.m";
	asn1					: ASN1;

include "pkcs.m";
	pkcs					: PKCS;
	DHParams, DHPublicKey, DHPrivateKey, 
	RSAParams, RSAKey, 
	DSSPrivateKey, DSSPublicKey		: import PKCS;

include "x509.m";
	x509					: X509;
	Signed,	Certificate, SubjectPKInfo	: import x509;

include "sslsession.m";
	sslsession				: SSLsession;
	Session					: import sslsession;

include "ssl3.m";

#
# debug mode
#
SSL_DEBUG					: con 0;
logfd						: ref Sys->FD;

#
# version {major, minor}
#
SSL_VERSION_2_0					:= array [] of {byte 0, byte 16r02};
SSL_VERSION_3_0					:= array [] of {byte 16r03, byte 0};


# SSL Record Protocol

SSL_CHANGE_CIPHER_SPEC 				: con 20;
	SSL_ALERT				: con 21;
	SSL_HANDSHAKE 				: con 22;
	SSL_APPLICATION_DATA 			: con 23;
	SSL_V2HANDSHAKE				: con 0; # escape to sslv2

# SSL Application Protocol consists of alert protocol, change cipher spec protocol
# v2 and v3 handshake protocol and application data protocol. The v2 handshake
# protocol is included only for backward compatibility

Protocol: adt {
	pick {
	pAlert =>
		alert				: ref Alert;
	pChangeCipherSpec =>
		change_cipher_spec		: ref ChangeCipherSpec;
	pHandshake =>
		handshake			: ref Handshake;
	pV2Handshake =>
		handshake			: ref V2Handshake;
	pApplicationData =>
		data				: array of byte;
	}

	decode: fn(r: ref Record, ctx: ref Context): (ref Protocol, string);
	encode: fn(p: self ref Protocol, vers: array of byte): (ref Record, string);
	tostring: fn(p: self ref Protocol): string;
};

#
# ssl alert protocol
#
SSL_WARNING	 				: con 1; 
	SSL_FATAL				: con 2;

SSL_CLOSE_NOTIFY				: con 0;
	SSL_UNEXPECTED_MESSAGE			: con 10;
	SSL_BAD_RECORD_MAC			: con 20;
	SSL_DECOMPRESSION_FAILURE		: con 30;
	SSL_HANDSHAKE_FAILURE 			: con 40;
	SSL_NO_CERTIFICATE			: con 41;
	SSL_BAD_CERTIFICATE 			: con 42;
	SSL_UNSUPPORTED_CERTIFICATE 		: con 43;
	SSL_CERTIFICATE_REVOKED			: con 44;
	SSL_CERTIFICATE_EXPIRED			: con 45;
	SSL_CERTIFICATE_UNKNOWN			: con 46;
	SSL_ILLEGAL_PARAMETER 			: con 47;

Alert: adt {
	level 					: int; 
	description 				: int;
	
	tostring: fn(a: self ref Alert): string;
};

#
# ssl change cipher spec protocol
#
ChangeCipherSpec: adt {
	value					: int;
};

#
# ssl handshake protocol
#
SSL_HANDSHAKE_HELLO_REQUEST	 		: con 0; 
	SSL_HANDSHAKE_CLIENT_HELLO 		: con 1; 
	SSL_HANDSHAKE_SERVER_HELLO 		: con 2;
	SSL_HANDSHAKE_CERTIFICATE 		: con 11;
	SSL_HANDSHAKE_SERVER_KEY_EXCHANGE 	: con 12;
	SSL_HANDSHAKE_CERTIFICATE_REQUEST 	: con 13; 
	SSL_HANDSHAKE_SERVER_HELLO_DONE 	: con 14;
	SSL_HANDSHAKE_CERTIFICATE_VERIFY 	: con 15; 
	SSL_HANDSHAKE_CLIENT_KEY_EXCHANGE 	: con 16;
	SSL_HANDSHAKE_FINISHED	 		: con 20; 

Handshake: adt {
	pick {
       	HelloRequest =>				
        ClientHello =>
		version 			: array of byte; # [2]
		random 				: array of byte; # [32]
		session_id 			: array of byte; # <0..32>
		suites	 			: array of byte; # [2] x
		compressions			: array of byte; # [1] x
        ServerHello =>
		version 			: array of byte; # [2]
		random 				: array of byte; # [32]
		session_id 			: array of byte; # <0..32>
		suite	 			: array of byte; # [2]
		compression			: byte; # [1]
	Certificate =>
		cert_list 			: list of array of byte; # X509 cert chain
	ServerKeyExchange =>
		xkey				: array of byte; # exchange_keys
        CertificateRequest =>
		cert_types 			: array of byte;
		dn_list 			: list of array of byte; # DN list
	ServerHelloDone =>
        CertificateVerify =>
		signature			: array of byte;
        ClientKeyExchange =>
		xkey				: array of byte;
       	Finished =>
		md5_hash			: array of byte; # [16] Keyring->MD5dlen
		sha_hash 			: array of byte; # [20] Keyring->SHA1dlen
	}

	decode: fn(buf: array of byte): (ref Handshake, string);
	encode: fn(hm: self ref Handshake): (array of byte, string);
	tostring: fn(hm: self ref Handshake): string;
};

# cipher suites and cipher specs (default, not all supported)
#	- key exchange, signature, encrypt and digest algorithms

SSL3_Suites := array [] of {
	NULL_WITH_NULL_NULL => 			array [] of {byte 0, byte 16r00},

	RSA_WITH_NULL_MD5 => 			array [] of {byte 0, byte 16r01},
	RSA_WITH_NULL_SHA => 			array [] of {byte 0, byte 16r02},
	RSA_EXPORT_WITH_RC4_40_MD5 => 		array [] of {byte 0, byte 16r03},
	RSA_WITH_RC4_128_MD5 => 		array [] of {byte 0, byte 16r04},
	RSA_WITH_RC4_128_SHA => 		array [] of {byte 0, byte 16r05},
	RSA_EXPORT_WITH_RC2_CBC_40_MD5 => 	array [] of {byte 0, byte 16r06},
	RSA_WITH_IDEA_CBC_SHA => 		array [] of {byte 0, byte 16r07},
	RSA_EXPORT_WITH_DES40_CBC_SHA => 	array [] of {byte 0, byte 16r08},
	RSA_WITH_DES_CBC_SHA => 		array [] of {byte 0, byte 16r09},
	RSA_WITH_3DES_EDE_CBC_SHA => 		array [] of {byte 0, byte 16r0A},

	DH_DSS_EXPORT_WITH_DES40_CBC_SHA => 	array [] of {byte 0, byte 16r0B},
	DH_DSS_WITH_DES_CBC_SHA => 		array [] of {byte 0, byte 16r0C},
	DH_DSS_WITH_3DES_EDE_CBC_SHA => 	array [] of {byte 0, byte 16r0D},
	DH_RSA_EXPORT_WITH_DES40_CBC_SHA => 	array [] of {byte 0, byte 16r0E},
	DH_RSA_WITH_DES_CBC_SHA => 		array [] of {byte 0, byte 16r0F},
	DH_RSA_WITH_3DES_EDE_CBC_SHA => 	array [] of {byte 0, byte 16r10},
	DHE_DSS_EXPORT_WITH_DES40_CBC_SHA =>	array [] of {byte 0, byte 16r11},
	DHE_DSS_WITH_DES_CBC_SHA => 		array [] of {byte 0, byte 16r12},
	DHE_DSS_WITH_3DES_EDE_CBC_SHA => 	array [] of {byte 0, byte 16r13},
	DHE_RSA_EXPORT_WITH_DES40_CBC_SHA =>	array [] of {byte 0, byte 16r14},
	DHE_RSA_WITH_DES_CBC_SHA => 		array [] of {byte 0, byte 16r15},
	DHE_RSA_WITH_3DES_EDE_CBC_SHA => 	array [] of {byte 0, byte 16r16},

	DH_anon_EXPORT_WITH_RC4_40_MD5 => 	array [] of {byte 0, byte 16r17},
	DH_anon_WITH_RC4_128_MD5 => 		array [] of {byte 0, byte 16r18},
	DH_anon_EXPORT_WITH_DES40_CBC_SHA =>	array [] of {byte 0, byte 16r19},
	DH_anon_WITH_DES_CBC_SHA => 		array [] of {byte 0, byte 16r1A},
	DH_anon_WITH_3DES_EDE_CBC_SHA => 	array [] of {byte 0, byte 16r1B},

	FORTEZZA_KEA_WITH_NULL_SHA => 		array [] of {byte 0, byte 16r1C},
	FORTEZZA_KEA_WITH_FORTEZZA_CBC_SHA =>	array [] of {byte 0, byte 16r1D},
	FORTEZZA_KEA_WITH_RC4_128_SHA => 	array [] of {byte 0, byte 16r1E},
};

#
# key exchange algorithms
#
DHmodlen					: con 512; # default length


#
# certificate types
#
SSL_RSA_sign 					: con 1;
	SSL_DSS_sign 				: con 2;
	SSL_RSA_fixed_DH			: con 3;
	SSL_DSS_fixed_DH			: con 4;
	SSL_RSA_emhemeral_DH 			: con 5;
	SSL_DSS_empemeral_DH 			: con 6;
	SSL_FORTEZZA_MISSI			: con 20;

#
# cipher definitions
#
SSL_EXPORT_TRUE 				: con 0;
	SSL_EXPORT_FALSE 			: con 1;

SSL_NULL_CIPHER,
	SSL_RC4,
	SSL_RC2_CBC,
	SSL_IDEA_CBC,
	SSL_DES_CBC,
	SSL_3DES_EDE_CBC,
	SSL_FORTEZZA_CBC			: con iota;

SSL_STREAM_CIPHER,
	SSL_BLOCK_CIPHER			: con iota;

SSL_NULL_MAC,
	SSL_MD5,
	SSL_SHA					: con iota;

#
# MAC paddings
#
SSL_MAX_MAC_PADDING 				: con 48;
SSL_MAC_PAD1 := array [] of { 
	byte 16r36, byte 16r36, byte 16r36, byte 16r36, 
	byte 16r36, byte 16r36, byte 16r36, byte 16r36,
	byte 16r36, byte 16r36, byte 16r36, byte 16r36, 
	byte 16r36, byte 16r36, byte 16r36, byte 16r36,
	byte 16r36, byte 16r36, byte 16r36, byte 16r36, 
	byte 16r36, byte 16r36, byte 16r36, byte 16r36,
	byte 16r36, byte 16r36, byte 16r36, byte 16r36, 
	byte 16r36, byte 16r36, byte 16r36, byte 16r36,
	byte 16r36, byte 16r36, byte 16r36, byte 16r36, 
	byte 16r36, byte 16r36, byte 16r36, byte 16r36,
	byte 16r36, byte 16r36, byte 16r36, byte 16r36, 
	byte 16r36, byte 16r36, byte 16r36, byte 16r36,
};
SSL_MAC_PAD2 := array [] of {
	byte 16r5c, byte 16r5c, byte 16r5c, byte 16r5c,
	byte 16r5c, byte 16r5c, byte 16r5c, byte 16r5c,
	byte 16r5c, byte 16r5c, byte 16r5c, byte 16r5c,
	byte 16r5c, byte 16r5c, byte 16r5c, byte 16r5c,
	byte 16r5c, byte 16r5c, byte 16r5c, byte 16r5c,
	byte 16r5c, byte 16r5c, byte 16r5c, byte 16r5c,
	byte 16r5c, byte 16r5c, byte 16r5c, byte 16r5c,
	byte 16r5c, byte 16r5c, byte 16r5c, byte 16r5c,
	byte 16r5c, byte 16r5c, byte 16r5c, byte 16r5c,
	byte 16r5c, byte 16r5c, byte 16r5c, byte 16r5c,
	byte 16r5c, byte 16r5c, byte 16r5c, byte 16r5c,
	byte 16r5c, byte 16r5c, byte 16r5c, byte 16r5c,
};

#
# finished messages
#
SSL_CLIENT_SENDER := array [] of {
	byte 16r43, byte 16r4C, byte 16r4E, byte 16r54};
SSL_SERVER_SENDER := array [] of {
	byte 16r53, byte 16r52, byte 16r56, byte 16r52};

#
# a default distiguished names
#
RSA_COMMERCIAL_CA_ROOT_SUBJECT_NAME := array [] of {   
	byte 16r30, byte 16r5F, byte 16r31, byte 16r0B, 
	byte 16r30, byte 16r09, byte 16r06, byte 16r03, 
	byte 16r55, byte 16r04, byte 16r06, byte 16r13, 
	byte 16r02, byte 16r55, byte 16r53, byte 16r31, 
	byte 16r20, byte 16r30, byte 16r1E, byte 16r06, 
	byte 16r03, byte 16r55, byte 16r04, byte 16r0A, 
	byte 16r13, byte 16r17, byte 16r52, byte 16r53, 
	byte 16r41, byte 16r20, byte 16r44, byte 16r61, 
	byte 16r74, byte 16r61, byte 16r20, byte 16r53, 
	byte 16r65, byte 16r63, byte 16r75, byte 16r72, 
	byte 16r69, byte 16r74, byte 16r79, byte 16r2C, 
	byte 16r20, byte 16r49, byte 16r6E, byte 16r63, 
	byte 16r2E, byte 16r31, byte 16r2E, byte 16r30, 
	byte 16r2C, byte 16r06, byte 16r03, byte 16r55, 
	byte 16r04, byte 16r0B, byte 16r13, byte 16r25, 
	byte 16r53, byte 16r65, byte 16r63, byte 16r75, 
	byte 16r72, byte 16r65, byte 16r20, byte 16r53, 
	byte 16r65, byte 16r72, byte 16r76, byte 16r65, 
	byte 16r72, byte 16r20, byte 16r43, byte 16r65, 
	byte 16r72, byte 16r74, byte 16r69, byte 16r66, 
	byte 16r69, byte 16r63, byte 16r61, byte 16r74, 
	byte 16r69, byte 16r6F, byte 16r6E, byte 16r20, 
	byte 16r41, byte 16r75, byte 16r74, byte 16r68, 
	byte 16r6F, byte 16r72, byte 16r69, byte 16r74, 
	byte 16r79,
};

# SSL internal status
USE_DEVSSL,
	SSL3_RECORD,
	SSL3_HANDSHAKE,
	SSL2_HANDSHAKE,
	CLIENT_SIDE, 				
	SESSION_RESUMABLE,
	CLIENT_AUTH,
	CERT_REQUEST,
	CERT_SENT,
	CERT_RECEIVED,
	OUT_READY,
	IN_READY				: con  1 << iota;

# SSL internal state
STATE_EXIT,
	STATE_CHANGE_CIPHER_SPEC,
	STATE_HELLO_REQUEST,
	STATE_CLIENT_HELLO,
	STATE_SERVER_HELLO,
	STATE_CLIENT_KEY_EXCHANGE,
	STATE_SERVER_KEY_EXCHANGE,
	STATE_SERVER_HELLO_DONE,
	STATE_CLIENT_CERTIFICATE,
	STATE_SERVER_CERTIFICATE,
	STATE_CERTIFICATE_VERIFY,
	STATE_FINISHED				: con iota;

#
# load necessary modules
#
init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "ssl3: load sys module failed";
	logfd = sys->fildes(1);

	keyring = load Keyring Keyring->PATH;
	if(keyring == nil)
		return "ssl3: load keyring module failed";

	random = load Random Random->PATH;
	if(random == nil)
		return "ssl3: load random module failed";

	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		return "ssl3: load Daytime module failed";

	pkcs = load PKCS PKCS->PATH;
	if(pkcs == nil)
		return "ssl3: load pkcs module failed";
	pkcs->init();

	x509 = load X509 X509->PATH;
	if(x509 == nil)
		return "ssl3: load x509 module failed";
	x509->init();

	ssl = load SSL SSL->PATH;
	if(ssl == nil)
		return "ssl3: load SSL module failed";
	sslsession = load SSLsession SSLsession->PATH;
	if(sslsession == nil)
		return "ssl3: load sslsession module failed";
	e := sslsession->init();
	if(e != nil)
		return "ssl3: sslsession init failed: "+e;

	return "";
}

log(s: string)
{
	a := array of byte (s + "\n");
	sys->write(logfd, a, len a);
}

#
# protocol context
#

Context.new(): ref Context
{
	ctx := ref Context;

	ctx.c = nil;
	ctx.session = nil;
	ctx.local_info = nil;
		
	ctx.sha_state = nil;
	ctx.md5_state = nil;

	ctx.status = 0;
	ctx.state = 0;

	ctx.client_random = array [32] of byte;
	ctx.server_random = array [32] of byte;

	ctx.cw_mac = nil;
	ctx.sw_mac = nil;
	ctx.cw_key = nil;
	ctx.sw_key = nil;
	ctx.cw_IV = nil;
	ctx.sw_IV = nil;

	ctx.in_queue = RecordQueue.new();
	ctx.in_queue.data = ref Record(0, nil, array [1<<15] of byte) :: nil;
	ctx.out_queue = RecordQueue.new();

	# set session resumable as default
	ctx.status |= SESSION_RESUMABLE;

	return ctx;
}

Context.client(ctx: self ref Context, fd: ref Sys->FD, peername: string, ver: int, info: ref Authinfo)
	: (string, int)
{
	if(SSL_DEBUG)
		log(sys->sprint("ssl3: Context.Client peername=%s ver=%d\n", peername, ver));
	if ((ckstr := cksuites(info.suites)) != nil)
		return (ckstr, ver);
	# the order is important
	ctx.local_info = info;
	ctx.state = STATE_HELLO_REQUEST;
	e := ctx.connect(fd);
	if(e != "")
		return (e, ver);
	ctx.session = sslsession->get_session_byname(peername);

	# Request to resume an SSL 3.0 session should use an SSL 3.0 client hello
	if(ctx.session.session_id != nil) {
		if((ctx.session.version[0] == SSL_VERSION_3_0[0]) &&
			(ctx.session.version[1] == SSL_VERSION_3_0[1])) {
			ver = 3;
			ctx.status |= SSL3_HANDSHAKE;
			ctx.status &= ~SSL2_HANDSHAKE;
		}
	}
	e = ctx.set_version(ver);
	if(e != "")
		return (e, ver);
	reset_client_random(ctx);
	ctx.status |= CLIENT_SIDE;
	e = do_protocol(ctx);
	if(e != nil)
		return (e, ver);

	if(ctx.status & SSL3_RECORD)
		ver = 3;
	else
		ver = 2;
	return (nil, ver);
}

Context.server(ctx: self ref Context, fd: ref Sys->FD, info: ref Authinfo, client_auth: int)
	: string
{
	if ((ckstr := cksuites(info.suites)) != nil)
		return ckstr;
	ctx.local_info = info;
	if(client_auth)
		ctx.status |= CLIENT_AUTH;
	ctx.state = STATE_CLIENT_HELLO;
	e := ctx.connect(fd);
	if(e != "")
		return e;
	reset_server_random(ctx);
	e = ctx.set_version(3); # set ssl device to version 3
	if(e != "")
		return e;
	ctx.status &= ~CLIENT_SIDE;
	e = do_protocol(ctx);
	if(e != nil)
		return e;

	return "";
}


Context.use_devssl(ctx: self ref Context)
{
	if(!(ctx.status & IN_READY) && !(ctx.status & OUT_READY))
		ctx.status |= USE_DEVSSL;
}

Context.set_version(ctx: self ref Context, vers: int): string
{
	err := "";

	if(ctx.c == nil) {
		err = "no connection provided";
	}
	else {
		if(SSL_DEBUG)
			log("ssl3: record version = " + string vers);

		if(vers == 2) {
			ctx.status &= ~SSL3_RECORD;
			ctx.status &= ~SSL3_HANDSHAKE;
			ctx.status |= SSL2_HANDSHAKE;
			if (ctx.session != nil)
				ctx.session.version = SSL_VERSION_2_0;
		}
		else if(vers == 3) { # may be sslv2 handshake using ssl3 record
			ctx.status |= SSL3_RECORD;
			ctx.status |= SSL3_HANDSHAKE;
			ctx.status &= ~SSL2_HANDSHAKE; # tmp test only
			if (ctx.session != nil)
				ctx.session.version = SSL_VERSION_3_0;
		}
		else if(vers == 23) { # may be sslv2 handshake using ssl3 record
			ctx.status &= ~SSL3_RECORD;
			ctx.status |= SSL3_HANDSHAKE;
			ctx.status |= SSL2_HANDSHAKE;
			vers = 2;
		}
		else
			err = "unsupported ssl device version";

		if((err == "") && (ctx.status & USE_DEVSSL)) {
			if(sys->fprint(ctx.c.cfd, "ver %d", vers) < 0)
				err = sys->sprint("ssl3: set ssl device version failed: %r");
		}
	}

	return err;
}

Context.connect(ctx: self ref Context, fd: ref Sys->FD): string
{
	err := "";

	if(ctx.status & USE_DEVSSL)
		(err, ctx.c) = ssl->connect(fd);
	else {
		ctx.c = ref Sys->Connection(fd, nil, "");
		ctx.in_queue.sequence_numbers[0] = 0;
		ctx.out_queue.sequence_numbers[1] = 0;
	}

	return err;
}

Context.read(ctx: self ref Context, a: array of byte, n: int): int
{	
	if(ctx.state != STATE_EXIT || !(ctx.status & IN_READY)) {
		if(SSL_DEBUG)
			log("ssl3: read not ready\n");
		return -1;
	}

	if(ctx.out_queue.data != nil)
		record_write_queue(ctx);

	if(ctx.status & USE_DEVSSL) {
		fd := ctx.c.dfd;
		if(ctx.status & SSL3_RECORD) {
			buf := array [n+3] of byte;
			m := sys->read(fd, buf, n+3); # header + n bytes
			if(m < 3) {
				if(SSL_DEBUG)
					log(sys->sprint("ssl3: read failure: %r"));
				return -1;
			}

			if(buf[1] != SSL_VERSION_3_0[0] || buf[2] != SSL_VERSION_3_0[1]) {
				if(SSL_DEBUG)
					log("ssl3: not ssl version 3 data: header = [" + bastr(buf[0:3]) + "]");
				return -1;
			}

			a[0:] = buf[3:m];

			content_type := int buf[0];
			case content_type {
			SSL_APPLICATION_DATA =>
				break;
			SSL_ALERT =>				
				if(SSL_DEBUG)
					log("ssl3: expect application data, got alert: [" + bastr(buf[3:m]) +"]");
				return 0;
			SSL_HANDSHAKE =>
				if(SSL_DEBUG)
					log("ssl3: expect application data, got handshake message");
				return 0;
			SSL_CHANGE_CIPHER_SPEC =>
				if(SSL_DEBUG)
					log("ssl3: dynamic change cipher spec not supported yet");
				return 0;
			}
			return m-3;
		}
		else
			return sys->read(fd, a, n);
	}
	else {
		q := ctx.in_queue;
		got := 0;
		if(q.fragment) {
			d := (hd q.data).data;
			m := q.e - q.b;
			i := q.e - q.fragment;
			if(q.fragment > n) {
				a[0:] = d[i:i+n];
				q.fragment -= n;
				got = n;
			}
			else {
				a[0:] = d[i:q.e];
				got = q.fragment;
				q.fragment = 0;
			}
		}
out:
		while(got < n) {
			err := q.read(ctx, ctx.c.dfd);
			if(err != "") {	
				if(SSL_DEBUG)
					log("ssl3: read: " + err);
				break;
			}
			r := hd q.data;
			if(ctx.status & SSL3_RECORD) {
				case r.content_type {
				SSL_APPLICATION_DATA =>
					break;
				SSL_ALERT =>
					if(SSL_DEBUG)
						log("ssl3: read: got alert\n\t\t" + bastr(r.data[q.b:q.e]));
					# delete session id
					ctx.session.session_id = nil;
					ctx.status &= ~IN_READY;
					break out;
				SSL_CHANGE_CIPHER_SPEC =>
					if(SSL_DEBUG)
						log("ssl3: read: got change cipher spec\n");
				SSL_HANDSHAKE =>
					if(SSL_DEBUG)
						log("ssl3: read: got handshake data\n");
					#do_handshake(ctx, r); # ?
				* =>
					if(SSL_DEBUG)
						log("ssl3: read: unknown data\n");
				}
			}

			if((n - got) <= (q.e - q.b)) {
				a[got:] = r.data[q.b:q.b+n-got];
				q.fragment = q.e - q.b - n + got;
				got = n;
			}
			else {
				a[got:] = r.data[q.b:q.e];
				q.fragment = 0;
				got += q.e - q.b;
			}
		}
		if(SSL_DEBUG)
			log(sys->sprint("ssl3: read: returning %d bytes\n", got));
		return got;
	}
}

Context.write(ctx: self ref Context, a: array of byte, n: int): int
{	
	if(ctx.state != STATE_EXIT || !(ctx.status & OUT_READY))
		return-1;

	if(ctx.out_queue.data != nil)
		record_write_queue(ctx);

	if(ctx.status & USE_DEVSSL) {
		if(ctx.status & SSL3_RECORD) {
			buf := array [n+3] of byte;
			buf[0] = byte SSL_APPLICATION_DATA;
			buf[1:] = SSL_VERSION_3_0;
			buf[3:] = a[0:n];
			n = sys->write(ctx.c.dfd, buf, n+3);
			if(n > 0)
				n -= 3;
		}
		else
			n = sys->write(ctx.c.dfd, a, n);
	}
	else {
		q := ctx.out_queue;
		v := SSL_VERSION_2_0;
		if(ctx.status&SSL3_RECORD)
			v = SSL_VERSION_3_0;
		for(i := 0; i < n;){
			m := n-i;
			if(m > q.length)
				m = q.length;
			r := ref Record(SSL_APPLICATION_DATA, v, a[i:i+m]);
			record_write(r, ctx); # return error?		
			i += m;
		}
	}
	return n;
}

devssl_read(ctx: ref Context): (ref Record, string)
{
	buf := array [Sys->ATOMICIO] of byte;
	r: ref Record;
	c := ctx.c;

	n := sys->read(c.dfd, buf, 3);
	if(n < 0)
		return (nil, sys->sprint("record read: read failure: %r")); 

	# in case of undetermined, do auto record version detection
	if((ctx.state == SSL2_STATE_SERVER_HELLO) &&
		(ctx.status & SSL2_HANDSHAKE) && (ctx.status & SSL3_HANDSHAKE)) {

		fstatus := sys->open(ctx.c.dir + "/status", Sys->OREAD);
		if(fstatus == nil)
			return (nil, "open status: " + sys->sprint("%r"));
		status := array [64] of byte;
		nbyte := sys->read(fstatus, status, len status);
		if(nbyte != 1)
			return (nil, "read status: " + sys->sprint("%r"));

		ver := int status[0];

		if(SSL_DEBUG)
			log("ssl3: auto record version detect as: " + string ver); 

		# assert ctx.status & SSL2_RECORD true ? before reset
		if(ver == 2) {
			ctx.status &= ~SSL3_RECORD;
			ctx.status |= SSL2_HANDSHAKE;
			ctx.status &= ~SSL3_HANDSHAKE;
		}
		else { 
			ctx.status |= SSL3_RECORD;
		}
	}

	if(ctx.status & SSL3_RECORD) {
		if(n < 3)
			return (nil, sys->sprint("record read: read failure: %r")); 

		# assert only major version number
		if(buf[1] != SSL_VERSION_3_0[0])
			return (nil, "record read: version mismatch");

		case int buf[0] {
		SSL_ALERT =>
			n = sys->read(c.dfd, buf, 5); # read in header plus rest
			if(n != 5)
				return (nil, sys->sprint("read alert failed: %r"));
			r = ref Record(SSL_ALERT, SSL_VERSION_3_0, buf[3:5]);

		SSL_CHANGE_CIPHER_SPEC =>
			n = sys->read(c.dfd, buf, 4); # read in header plus rest
			if(n != 4)
				return (nil, sys->sprint("read change_cipher_spec failed: %r"));
			r = ref Record(SSL_CHANGE_CIPHER_SPEC, SSL_VERSION_3_0, buf[3:4]);

		SSL_HANDSHAKE =>
			n = sys->read(c.dfd, buf, 7); # header + msg length
			if(n != 7)
				return (nil, sys->sprint("read handshake header + msg length failed: %r"));
			m := int_decode(buf[4:7]);
			if(m < 0)
				return (nil, "read handshake failed: unexpected length");
			data := array [m+4] of byte;
			data[0:] = buf[3:7]; # msg type + length
			if(m != 0) {
				# need exact m bytes (exclude header), otherwise failure
				remain := m;
				now := 4;
				while(remain > 0) {
					n = sys->read(c.dfd, buf, remain+3); # header + msg
					if(n < 3 || int buf[0] != SSL_HANDSHAKE)
						return (nil, sys->sprint("read handshake msg body failed: %r"));
					sys->print("expect %d, got %d bytes\n", m, n-3);
					remain -= n - 3;
					data[now:] = buf[3:n];
					now += n - 3;
				}
			}

			r = ref Record(SSL_HANDSHAKE, SSL_VERSION_3_0, data);
		* =>
			return (nil, "trying to read unknown protocol message");
		}

		if(SSL_DEBUG)
			log("ssl3: record_read: \n\theader = \n\t\t" + bastr(buf[0:3])
			+ "\n\tdata = \n\t\t" + bastr(r.data) + "\n");
	}
	# v2 record layer
	else {
		# assume the handshake record size less than Sys->ATOMICIO
		# in most case, this is ok
		if(n == 3) {
			n = sys->read(c.dfd, buf[3:], Sys->ATOMICIO - 3);
			if(n < 0)
				return (nil, sys->sprint("v2 record read: read failure: %r")); 
		}

		r = ref Record(SSL_V2HANDSHAKE, SSL_VERSION_2_0, buf[0:n+3]);

		if(SSL_DEBUG)
			log("ssl3: v2 record_read: \n\tdata = \n\t\t" + bastr(r.data) + "\n");
	}

	return (r, nil);
}

record_read(ctx: ref Context): (ref Record, string) 
{
	q := ctx.in_queue;
	if(q.fragment == 0) {
		err := q.read(ctx, ctx.c.dfd);
		if(err != "")
			return (nil, err);
		q.fragment = q.e - q.b;
	}

	r := hd q.data;
	if(ctx.status & SSL3_RECORD) {
		# confirm only major version number
		if(r.version[0] != SSL_VERSION_3_0[0])
			return (nil, "record read: not v3 record");

		case r.content_type {
		SSL_ALERT =>
			a := array [2] of byte;
			n := fetch_data(ctx, a, 2);
			if(n != 2)
				return (nil, "read alert failed");
			r = ref Record(SSL_ALERT, SSL_VERSION_3_0, a);

		SSL_CHANGE_CIPHER_SPEC =>
			a := array [1] of byte;
			n := fetch_data(ctx, a, 1);
			if(n != 1)
				return (nil, "read change_cipher_spec failed");
			r = ref Record(SSL_CHANGE_CIPHER_SPEC, SSL_VERSION_3_0, a);

		SSL_HANDSHAKE =>
			a := array [4] of byte;
			n := fetch_data(ctx, a, 4);
			if(n != 4)
				return (nil, "read message length failed");
			m := int_decode(a[1:]);
			if(m < 0)
				return (nil, "unexpected handshake message length");
			b := array [m+4] of byte;
			b[0:] = a;
			n = fetch_data(ctx, b[4:], m);
			if(n != m)
				return (nil, "read message body failed");
			r = ref Record(SSL_HANDSHAKE, SSL_VERSION_3_0, b);
		* =>
			return (nil, "trying to read unknown protocol message");
		}
	}
	# v2 record layer
	else {
		r = ref Record(SSL_V2HANDSHAKE, SSL_VERSION_2_0, r.data[q.b:q.e]);
		q.fragment = 0;
	}

	return (r, nil);
}

fetch_data(ctx: ref Context, a: array of byte, n: int): int
{
	q := ctx.in_queue;
	r := hd q.data;

	got := 0;
	cnt := -1;
out:
	while(got < n) {
		if(q.fragment) {
			cnt = r.content_type;
			i := q.e - q.fragment;			
			if(n-got <= q.fragment) {
				a[got:] = r.data[i:i+n-got];
				q.fragment -= n - got;
				got = n;
			}
			else {
				a[got:] = r.data[i:q.e];
				got += q.fragment;
				q.fragment = 0;
			}
		}
		else {
			err := q.read(ctx, ctx.c.dfd);
			if(err != "") 
				break out;
			if(cnt == -1)
				cnt = r.content_type;
			if(ctx.status & SSL3_RECORD) {
				case r.content_type {
				SSL_APPLICATION_DATA =>
					break;
				* =>
					if(cnt != r.content_type)
						break out;
				}
			}
			else {
				r.content_type = SSL_V2HANDSHAKE;
			}
		}
	}
	return got;
}

record_write(r: ref Record, ctx: ref Context)
{
	if(ctx.status & USE_DEVSSL) {
		buf: array of byte;
		n: int;
		c := ctx.c;

		if(ctx.status & SSL3_RECORD) {
			buf = array [3 + len r.data] of byte;
			buf[0] = byte r.content_type;
			buf[1:] = r.version; 
			buf[3:] = r.data;
			n = sys->write(c.dfd, buf, len buf);
			if(n < 0 || n != len buf) {
				if(SSL_DEBUG)
					log(sys->sprint("ssl3: v3 record write error: %d %r", n));
				return; # don't terminated until alerts being read
			}
		}
		else {
			buf = r.data;
			n = sys->write(c.dfd, buf, len buf);
			if(n < 0 || n != len buf) {
				if(SSL_DEBUG)
					log(sys->sprint("ssl3: v2 record write error: %d %r", n));
				return; # don't terminated until alerts being read
			}
		}
	}
	else 
		ctx.out_queue.write(ctx, ctx.c.dfd, r);
	
	# if(SSL_DEBUG) 
	#	log("ssl3: record_write: \n\t\t" + bastr(buf) + "\n");	
}

RecordQueue.new(): ref RecordQueue
{
	q := ref RecordQueue(
		ref MacState.null(0),
		ref CipherState.null(1),
		1 << 15,
		array [2] of { * => 0},
		nil,
		0,
		0, # b 
		0  # e	
	);
	return q;
}

RecordQueue.read(q: self ref RecordQueue, ctx: ref Context, fd: ref Sys->FD): string
{
	r := hd q.data;
	a := r.data;
	if(ensure(fd, a, 2) < 0)
		return "no more data";
	# auto record version detection
	m, h, pad: int = 0;
	if(int a[0] < 20 || int a[0] > 23) {
		ctx.status &= ~SSL3_RECORD;
		if(int a[0] & 16r80) {
			h = 2;
			m = ((int a[0] & 16r7f) << 8) | int a[1];
			pad = 0;
		} else {
			h = 3;
			m = ((int a[0] & 16r3f) << 8) | int a[1];
			if(ensure(fd, a[2:], 1) < 0)
				return "bad v2 record";
			pad = int a[2];
			if(pad > m)
				return "bad v2 pad";
		}
		r.content_type = SSL_V2HANDSHAKE;
		r.version = SSL_VERSION_2_0;
	}
	else {
		ctx.status |= SSL3_RECORD;
		h = 5;
		if(ensure(fd, a[2:], 3) < 0)
			return "bad v3 record";
		m = ((int a[3]) << 8) | int a[4];
		r.content_type = int a[0];
		r.version = a[1:3];
	}
	if(ensure(fd, a[h:], m) < 0)
#		return "data too short";
		return sys->sprint("data too short wanted %d", m);
	if(SSL_DEBUG) {
		log("ssl3: record read\n\tbefore decrypt\n\t\t" + bastr(a[0:m+h]));
		log(sys->sprint("SSL3=%d\n", ctx.status & SSL3_RECORD));
	}

	# decrypt (data, pad, mac)
	pick dec := q.cipherState {
	null =>
	rc4 =>
		keyring->rc4(dec.es, a[h:], m);
		if (SSL_DEBUG) log("rc4 1");
	descbc =>
		keyring->descbc(dec.es, a[h:], m, 1);
		if (SSL_DEBUG) log("descbc 1");
	ideacbc =>
		keyring->ideacbc(dec.es, a[h:], m, 1);
		if (SSL_DEBUG) log("ideacbc 1");
	* =>
	}

	if(SSL_DEBUG)
		log("ssl3: record read\n\tafter decrypt\n\t\t" + bastr(a[0:m]));

	idata, imac, ipad: int = 0;
	if(ctx.status & SSL3_RECORD) {
		if(q.cipherState.block_size > 1){
			pad = int a[h + m - 1];
			if(pad >= q.cipherState.block_size)
				return "bad v3 pad";
			# pad++;
			ipad = h+m-pad-1;
		}
		else
			ipad = h+m-pad;
		imac = ipad - q.macState.hash_size;
		idata = h;
	}
	else {
		imac = h;
		idata = imac + q.macState.hash_size;
		ipad = h + m - pad;
	}
	if(tagof q.macState != tagof MacState.null) {
		if (ctx.status & SSL3_RECORD)
			mac := q.calcmac(ctx, r.content_type, a, idata, imac-idata);
		else
			mac = q.calcmac(ctx, r.content_type, a, idata, ipad+pad-idata);
		if(bytes_cmp(mac, a[imac:imac+len mac]) < 0)
			return "bad mac";
	}
	q.b = idata;
	if (ctx.status & SSL3_RECORD)
		q.e = imac;
	else
		q.e = ipad;
	q.fragment = q.e - q.b;

	if((++q.sequence_numbers[0] == 0) && (ctx.status&SSL3_RECORD))
		++q.sequence_numbers[1];

	return "";
}

ensure(fd: ref Sys->FD, a: array of byte, n: int): int
{
	i, m: int = 0;
	while(i < n) {
		m = sys->read(fd, a[i:], n - i);
		if(m <= 0) {
			return -1;
		}
		i += m;
	}
	return n;
}

RecordQueue.write(q: self ref RecordQueue, ctx: ref Context, fd: ref Sys->FD, 
	r: ref Record): string
{
	m := len r.data;
	h, pad: int = 0;
	if(ctx.status & SSL3_RECORD) {
		h = 5;
		if(q.cipherState.block_size > 1) {
			pad = (m+q.macState.hash_size+1)%q.cipherState.block_size;
			if (pad)
				pad = q.cipherState.block_size - pad;
		}
	}
	else {
		h = 2;
		if(q.cipherState.block_size > 1) {
			pad = m%q.cipherState.block_size;
			if(pad) {
				pad = q.cipherState.block_size - pad;
				h++;
			}
		}
	}

	m += pad + q.macState.hash_size;
	if ((ctx.status & SSL3_RECORD) && q.cipherState.block_size > 1)
		m++;
	a := array [h+m] of byte;

	idata, imac, ipad: int = 0;
	if(ctx.status & SSL3_RECORD) {
		a[0] = byte r.content_type;
		a[1:] = r.version;
		a[3] = byte (m >> 8);			#CJL - netscape ssl3 traces do not show top bit set
#		a[3] = byte ((m >> 8) | 16r80);	#CJL
#		a[3] = byte (m | 16r8000) >> 8;
		a[4] = byte m;
		idata = h;
		imac = idata + len r.data;
		ipad = imac + q.macState.hash_size;
		if (q.cipherState.block_size > 1)
			a[h+m-1] = byte pad;
	}
	else {
		if(pad) {
			a[0] = byte m >> 8;
			a[2] = byte pad;
		}
		else
			a[0] = byte ((m >> 8) | 16r80);
		a[1] = byte m;
		imac = h;
		idata = imac + q.macState.hash_size;
		ipad = idata + len r.data;
	}
	a[idata:] = r.data;
	if(pad)
		a[ipad:] = array [pad] of { * => byte (pad-1)};

	if(tagof q.macState != tagof MacState.null) {
		if (ctx.status & SSL3_RECORD)
			a[imac:] = q.calcmac(ctx, r.content_type, a, idata, len r.data);
		else
			a[imac:] = q.calcmac(ctx, r.content_type, a, idata, ipad+pad-idata);
	}

	 if(SSL_DEBUG) {
		log("ssl3: record write\n\tbefore encrypt\n\t\t" + bastr(a));	
		log(sys->sprint("SSL3=%d\n", ctx.status & SSL3_RECORD));
	}

	# encrypt (data, pad, mac)
	pick enc := q.cipherState {
	null =>
	rc4 =>
		keyring->rc4(enc.es, a[h:], m);
		if (SSL_DEBUG) log("rc4 0");
	descbc =>
		keyring->descbc(enc.es, a[h:], m, 0);
		if (SSL_DEBUG) log(sys->sprint("descbc 0 %d", m));
	ideacbc =>
		keyring->ideacbc(enc.es, a[h:], m, 0);
		if (SSL_DEBUG) log(sys->sprint("ideacbc 0 %d", m));
	* =>
	}

	 if(SSL_DEBUG)
		log("ssl3: record write\n\tafter encrypt\n\t\t" + bastr(a));

	if(sys->write(fd, a, h+m) < 0)
		return sys->sprint("ssl3: record write: %r");

	if((++q.sequence_numbers[0] == 0) && (ctx.status&SSL3_RECORD))
		++q.sequence_numbers[1];

	return "";
}

RecordQueue.calcmac(q: self ref RecordQueue, ctx: ref Context, cntype: int, a: array of byte, 
	ofs, n: int) : array of byte
{
	digest, b: array of byte;

	if(ctx.status & SSL3_RECORD) {
		b = array [11] of byte;
		i := putn(b, 0, q.sequence_numbers[1], 4);
		i = putn(b, i, q.sequence_numbers[0], 4);
		b[i++] = byte cntype;
		putn(b, i, n, 2);
	}
	else {
		b = array [4] of byte;
		putn(b, 0, q.sequence_numbers[0], 4);
	}

	# if(SSL_DEBUG)
	#	log("ssl3: record mac\n\tother =\n\t\t" + bastr(b));

	pick ms := q.macState {
	md5 =>
		digest = array [Keyring->MD5dlen] of byte;
		ds0 := ms.ds[0].copy();
		if(ctx.status & SSL3_RECORD) {
			keyring->md5(b, len b, nil, ds0);
			keyring->md5(a[ofs:], n, digest, ds0);
			ds1 := ms.ds[1].copy();
			keyring->md5(digest, len digest, digest, ds1);
		}
		else {
			keyring->md5(a[ofs:], n, nil, ds0);
			keyring->md5(b, len b, digest, ds0);
		}
	sha =>
		digest = array [Keyring->SHA1dlen] of byte;
		ds0 := ms.ds[0].copy();
		if(ctx.status & SSL3_RECORD) {
			keyring->sha1(b, len b, nil, ds0);
			keyring->sha1(a[ofs:], n, digest, ds0);
			ds1 := ms.ds[1].copy();
			keyring->sha1(digest, len digest, digest, ds1);
		}
		else {
			keyring->sha1(a[ofs:], n, nil, ds0);
			keyring->sha1(b, len b, digest, ds0);
		}
	}			
	return digest;
}

set_queues(ctx: ref Context): string
{
	sw: array of byte;
	if(ctx.sw_key != nil) {
		sw = array [len ctx.sw_key + len ctx.sw_IV] of byte;
		sw[0:] = ctx.sw_key;
		sw[len ctx.sw_key:] = ctx.sw_IV;
	}
	cw: array of byte;
	if(ctx.cw_key != nil) {
		cw = array [len ctx.cw_key + len ctx.cw_IV] of byte;
		cw[0:] = ctx.cw_key;
		cw[len ctx.cw_key:] = ctx.cw_IV;
	}

	err := "";
	if(ctx.status & USE_DEVSSL) {
		err = set_secrets(ctx.c, ctx.sw_mac, ctx.cw_mac, sw, cw);
		if(err == "")
			err = set_cipher_algs(ctx);
	}
	else {
		err = set_out_queue(ctx);
		if(err == "")
			err = set_in_queue(ctx);
	}

	return err;
}

set_in_queue(ctx: ref Context): string
{
	sw: array of byte;
	if(ctx.sw_key != nil) {
		sw = array [len ctx.sw_key + len ctx.sw_IV] of byte;
		sw[0:] = ctx.sw_key;
		sw[len ctx.sw_key:] = ctx.sw_IV;
	}

	err := "";
	if(ctx.status & USE_DEVSSL) {
		err = set_secrets(ctx.c, ctx.sw_mac, nil, sw, nil);
		if(err == "")
			err = set_cipher_algs(ctx);
	}
	else
		err = set_queue(ctx, ctx.in_queue, ctx.sw_mac, sw);

	return err;
}

set_out_queue(ctx: ref Context): string
{
	cw: array of byte;
	if(ctx.cw_key != nil) {
		cw = array [len ctx.cw_key + len ctx.cw_IV] of byte;
		cw[0:] = ctx.cw_key;
		cw[len ctx.cw_key:] = ctx.cw_IV;
	}

	err := "";
	if(ctx.status & USE_DEVSSL) {
		err = set_secrets(ctx.c, nil, ctx.cw_mac, nil, cw);
		if(err == "")
			err = set_cipher_algs(ctx);
	}
	else
		err = set_queue(ctx, ctx.out_queue, ctx.cw_mac, cw);

	return err;
}

set_queue(ctx: ref Context, q: ref RecordQueue, mac, key: array of byte): string
{
	e := "";

	case ctx.sel_ciph.mac_algorithm {
	SSL_NULL_MAC =>
		q.macState = ref MacState.null(0);
	SSL_MD5 =>
		ds: array of ref DigestState;
		if(ctx.status & SSL3_RECORD) {
			ds = array [2] of ref DigestState;
			ds[0] = keyring->md5(mac, len mac, nil, nil);
			ds[1] = keyring->md5(mac, len mac, nil, nil);
			ds[0] = keyring->md5(SSL_MAC_PAD1, 48, nil, ds[0]);
			ds[1] = keyring->md5(SSL_MAC_PAD2, 48, nil, ds[1]);
		}
		else {
			ds = array [1] of ref DigestState;
			ds[0] = keyring->md5(mac, len mac, nil, nil);
		}
		q.macState = ref MacState.md5(Keyring->MD5dlen, ds);
	SSL_SHA =>
		ds: array of ref DigestState;
		if(ctx.status & SSL3_RECORD) {
			ds = array [2] of ref DigestState;
			ds[0] = keyring->sha1(mac, len mac, nil, nil);
			ds[1] = keyring->sha1(mac, len mac, nil, nil);
			ds[0] = keyring->sha1(SSL_MAC_PAD1, 40, nil, ds[0]);
			ds[1] = keyring->sha1(SSL_MAC_PAD2, 40, nil, ds[1]);
		}
		else {
			ds = array [1] of ref DigestState;
			ds[0] = keyring->sha1(mac, len mac, nil, nil);
		}
		q.macState = ref MacState.sha(Keyring->SHA1dlen, ds);
	* =>
		e = "ssl3: digest method: unknown";
	}

	case ctx.sel_ciph.bulk_cipher_algorithm {
	SSL_NULL_CIPHER =>
		q.cipherState = ref CipherState.null(1);
	SSL_RC4 =>
		if (SSL_DEBUG) log("rc4setup");
		rcs := keyring->rc4setup(key);
		q.cipherState = ref CipherState.rc4(1, rcs);
	SSL_DES_CBC =>
		dcs : ref keyring->DESstate;

		if (SSL_DEBUG) log(sys->sprint("dessetup %d", len key));
		if (len key >= 16)
			dcs = keyring->dessetup(key[0:8], key[8:16]);
		else if (len key >= 8)
			dcs = keyring->dessetup(key[0:8], nil);
		else
			e = "ssl3: bad DES key length";
		q.cipherState = ref CipherState.descbc(8, dcs);
	SSL_IDEA_CBC =>
		ics : ref keyring->IDEAstate;

		if (SSL_DEBUG) log(sys->sprint("ideasetup %d", len key));
		if (len key >= 24)
			ics = keyring->ideasetup(key[0:16], key[16:24]);
		else if (len key >= 16)
			ics = keyring->ideasetup(key[0:16], nil);
		else
			e = "ssl3: bad IDEA key length";
		q.cipherState = ref CipherState.ideacbc(8, ics);
	SSL_RC2_CBC or
	SSL_3DES_EDE_CBC or
	SSL_FORTEZZA_CBC =>
		e = "ssl3: unsupported cipher";
	* =>
		e = "ssl3: unknown cipher";
	}

	if(ctx.status & SSL3_RECORD) {
		q.length = 1 << 14;
		if(tagof q.macState != tagof MacState.null)
			q.length += 2048;
	}
	else {
		if(q.cipherState.block_size > 1) {
			q.length = (1<<14) - q.macState.hash_size - 1;
			q.length -= q.length % q.cipherState.block_size;
		}
		else
			q.length = (1<<15) - q.macState.hash_size - 1;
	}
	if(ctx.status & SSL3_RECORD)
		q.sequence_numbers[0] = q.sequence_numbers[1] = 0;

	return e;
}

set_cipher_algs(ctx: ref Context) : string
{
	e: string;

	algspec := "alg";

	case enc := ctx.sel_ciph.bulk_cipher_algorithm {
	SSL_NULL_CIPHER =>
		algspec += " clear";
	SSL_RC4 => 	# stream cipher
		algspec += " rc4_128";
	SSL_DES_CBC => # block cipher
		algspec += " descbc";
	SSL_IDEA_CBC => # block cipher
		algspec += " ideacbc";
	SSL_RC2_CBC or
	SSL_3DES_EDE_CBC or
	SSL_FORTEZZA_CBC =>
		e = "ssl3: encrypt method: unsupported";
	* =>
		e = "ssl3: encrypt method: unknown";
	}

	case mac := ctx.sel_ciph.mac_algorithm {
	SSL_NULL_MAC =>
		algspec += " clear";
	SSL_MD5 =>
		algspec += " md5";
	SSL_SHA =>
		algspec += " sha1";
	* =>
		e = "ssl3: digest method: unknown";
	}

	e = set_ctl(ctx.c, algspec);
	if(e != "") {
		if(SSL_DEBUG)
			log("failed to set cipher algs: " + e);
	}

	return e;
}

set_ctl(c: ref Sys->Connection, s: string): string
{
	a := array of byte s;
	if(sys->write(c.cfd, a, len a) < 0)
		return sys->sprint("error writing sslctl: %r");

	if(SSL_DEBUG)
		log("ssl3: set cipher algorithm:\n\t\t" + s + "\n");

	return "";
}

set_secrets(c: ref Sys->Connection, min, mout, sin, sout: array of byte) : string
{
	fmin := sys->open(c.dir + "/macin", Sys->OWRITE);
	fmout := sys->open(c.dir + "/macout", Sys->OWRITE);
	fsin := sys->open(c.dir + "/secretin", Sys->OWRITE);
	fsout := sys->open(c.dir + "/secretout", Sys->OWRITE);
	if(fmin == nil || fmout == nil || fsin == nil || fsout == nil)
		return sys->sprint("can't open ssl secret files: %r\n");

	if(sin != nil) {
		if(SSL_DEBUG)
			log("ssl3: set encryption secret and IV\n\tsecretin:\n\t\t" + bastr(sin) + "\n");
		if(sys->write(fsin, sin, len sin) < 0)
			return sys->sprint("error writing secretin: %r");
	}
	if(sout != nil) {
		if(SSL_DEBUG)
			log("ssl3: set encryption secret and IV\n\tsecretout:\n\t\t" + bastr(sout) + "\n");
		if(sys->write(fsout, sout, len sout) < 0)
			return sys->sprint("error writing secretout: %r");
	}
	if(min != nil) {
		if(SSL_DEBUG)
			log("ssl3: set digest secret\n\tmacin:\n\t\t" + bastr(min) + "\n");
		if(sys->write(fmin, min, len min) < 0)
			return sys->sprint("error writing macin: %r");
	}
	if(mout != nil) {
		if(SSL_DEBUG)
			log("ssl3: set digest secret\n\tmacout:\n\t\t" + bastr(mout) + "\n");
		if(sys->write(fmout, mout, len mout) < 0)
			return sys->sprint("error writing macout: %r");
	}

	return "";
}

#
# description must be alert description
#
fatal(description: int, debug_msg: string, ctx: ref Context)
{
	if(SSL_DEBUG)
		log("ssl3: " + debug_msg);

	# TODO: use V2Handshake.Error for v2
	alert_enque(ref Alert(SSL_FATAL, description), ctx);

	# delete session id
	ctx.session.session_id = nil;

	ctx.state = STATE_EXIT;
}

alert_enque(a: ref Alert, ctx: ref Context)
{
	p := ref Protocol.pAlert(a);

	protocol_write(p, ctx);
}

# clean up out queue before switch cipher. this is why
# change cipher spec differs from handshake message by ssl spec

ccs_enque(cs: ref ChangeCipherSpec, ctx: ref Context)
{
	p := ref Protocol.pChangeCipherSpec(cs);

	protocol_write(p, ctx);

	record_write_queue(ctx);
	ctx.out_queue.data = nil;
}

handshake_enque(h: ref Handshake, ctx: ref Context)
{
	p := ref Protocol.pHandshake(h);

	protocol_write(p, ctx);
}

protocol_write(p: ref Protocol, ctx: ref Context)
{
	record_version := SSL_VERSION_2_0;
	if(ctx.status & SSL3_RECORD)
		record_version = SSL_VERSION_3_0;
	(r, e) := p.encode(record_version);
	if(e != "") {
		if(SSL_DEBUG)
			log("ssl3: protocol_write: " + e);
		exit;
	}

	# Note: only for sslv3
	if((ctx.status&SSL2_HANDSHAKE) && (ctx.status&SSL3_HANDSHAKE)) {
		if(ctx.state == STATE_HELLO_REQUEST) {
			e = update_handshake_hash(ctx, r);
			if(e != "") {
				if(SSL_DEBUG)
					log("ssl3: protocol_write: " + e);
				exit;
			}
		}
	}
	if((ctx.status&SSL3_HANDSHAKE) && (r.content_type == SSL_HANDSHAKE)) {
		e = update_handshake_hash(ctx, r);
		if(e != "") {
			if(SSL_DEBUG)
				log("ssl3: protocol_write: " + e);
			exit;
		}
	}

	ctx.out_queue.data = r :: ctx.out_queue.data;
}

#feed_data(ctx: ref Context, a: array of byte, n: int): int 
#{
#
#}

# FIFO
record_write_queue(ctx: ref Context)
{
	write_queue : list of ref Record;

	wq := ctx.out_queue.data;
	while(wq != nil) {
		write_queue = hd wq :: write_queue;
		wq = tl wq;
	}

	wq = write_queue;
	while(wq != nil) {
		record_write(hd wq, ctx);
		wq = tl wq;
	}
}

# Possible combinations are v2 only, v3 only and both (undetermined). The v2 only must be 
# v2 handshake and v2 record layer. The v3 only must be v3 handshake and v3 record layer. 
# If both v2 and v3 are supported, it may be v2 handshake and v2 record layer, or v3 
# handshake and v3 record layer, or v2 handshake and v3 record layer. In the case of 
# both, the client should send a v2 client hello message with handshake protocol version v3. 

do_protocol(ctx: ref Context): string
{
	r: ref Record;
	in: ref Protocol;
	e: string = nil;

	while(ctx.state != STATE_EXIT) {

		if(SSL_DEBUG)
			log("ssl3: state = " + state_info(ctx));

		# init a new handshake
		if(ctx.state == STATE_HELLO_REQUEST) {
			# v2 and v3
			if((ctx.status&SSL2_HANDSHAKE) && (ctx.status&SSL3_HANDSHAKE)) {
				ch := ref V2Handshake.ClientHello(
						SSL_VERSION_3_0,
						v3tov2specs(ctx.local_info.suites),
						ctx.session.session_id,
						ctx.client_random
					);
				v2handshake_enque(ch, ctx);
				in = ref Protocol.pV2Handshake(ch);
			}
			# v3 only
			else if(ctx.status&SSL3_HANDSHAKE) {
				in = ref Protocol.pHandshake(ref Handshake.HelloRequest());
			}
			# v2 only
			else if(ctx.status&SSL2_HANDSHAKE) {		
				ch := ref V2Handshake.ClientHello(
						SSL_VERSION_2_0,
						v3tov2specs(ctx.local_info.suites),
						ctx.session.session_id,
						ctx.client_random[32-SSL2_CHALLENGE_LENGTH:32]
					);
				v2handshake_enque(ch, ctx);
				in = ref Protocol.pV2Handshake(ch);
			}
			# unknown version
			else {
				e = "unknown ssl device version";
				fatal(SSL_CLOSE_NOTIFY, "ssl3: " + e, ctx);
				continue;
			}
		}

		if(in == nil) {
			(r, in, e) = protocol_read(ctx);
			if(e != "") {
				fatal(SSL_CLOSE_NOTIFY, "ssl3: " + e, ctx);
				continue;
			}
			if(SSL_DEBUG)
				log("ssl3: protocol_read: ------\n" + in.tostring());
		}

		pick p := in {	
		pAlert =>
			do_alert(p.alert, ctx);

		pChangeCipherSpec =>
			if(ctx.state != STATE_CHANGE_CIPHER_SPEC) {
				e += "ChangeCipherSpec";
				break;
			}
			do_change_cipher_spec(ctx);

		pHandshake =>
			if(!(ctx.status & SSL3_HANDSHAKE)) {
				e = "Wrong Handshake";
				break;
			}
			if((ctx.status & SSL3_RECORD) && 
				(ctx.state == SSL2_STATE_SERVER_HELLO)) {
				ctx.state = STATE_SERVER_HELLO;
				ctx.status &= ~SSL2_HANDSHAKE;
			}
			e = do_handshake(p.handshake, ctx);

		pV2Handshake =>
			if(ctx.state != STATE_HELLO_REQUEST) {
				if(!(ctx.status & SSL2_HANDSHAKE)) {
					e = "Wrong Handshake";
					break;
				}
				e = do_v2handshake(p.handshake, ctx);
			}
			else
				ctx.state = SSL2_STATE_SERVER_HELLO;


		* =>
			e = "unknown protocol message";
		}

		if(e != nil) {
			e = "do_protocol: wrong protocol side or protocol message: " + e;
			fatal(SSL_UNEXPECTED_MESSAGE, e, ctx);
		}

		in = nil;

		record_write_queue(ctx);
		ctx.out_queue.data = nil;
	}

	return e;
}

state_info(ctx: ref Context): string
{
	info: string;

	if(ctx.status & SSL3_RECORD)
		info = "\n\tRecord Version 3: ";
	else
		info = "\n\tRecord Version 2: ";

	if(ctx.status & SSL2_HANDSHAKE) {

		if(ctx.status & SSL3_HANDSHAKE) {
			info += "\n\tHandshake Version Undetermined: Client Hello";
		}
		else {
			info += "\n\tHandshake Version 2: ";

			case ctx.state {
			SSL2_STATE_CLIENT_HELLO =>
				info += "Client Hello";
			SSL2_STATE_SERVER_HELLO =>
				info += "Server Hello";
			SSL2_STATE_CLIENT_MASTER_KEY =>
				info += "Client Master Key";
			SSL2_STATE_SERVER_VERIFY =>
				info += "Server Verify";
			SSL2_STATE_REQUEST_CERTIFICATE =>
				info += "Request Certificate";
			SSL2_STATE_CLIENT_CERTIFICATE =>
				info += "Client Certificate";
			SSL2_STATE_CLIENT_FINISHED =>
				info += "Client Finished";
			SSL2_STATE_SERVER_FINISHED =>		
				info += "Server Finished";
			SSL2_STATE_ERROR =>
				info += "Error";
			}
		}
	}
	else {
		info = "\n\tHandshake Version 3: ";

		case ctx.state {
		STATE_EXIT =>
			info += "Exit";

		STATE_CHANGE_CIPHER_SPEC =>
			info += "Change Cipher Spec";

		STATE_HELLO_REQUEST =>
			info += "Hello Request";

		STATE_CLIENT_HELLO =>
			info += "Client Hello";	

		STATE_SERVER_HELLO =>
			info += "Server Hello";

		STATE_CLIENT_KEY_EXCHANGE =>
			info += "Client Key Exchange";

		STATE_SERVER_KEY_EXCHANGE =>
			info += "Server Key Exchange";

		STATE_SERVER_HELLO_DONE =>
			info += "Server Hello Done";

		STATE_CLIENT_CERTIFICATE =>
			info += "Client Certificate";

		STATE_SERVER_CERTIFICATE =>
			info += "Server Certificate";

		STATE_CERTIFICATE_VERIFY =>
			info += "Certificate Verify";

		STATE_FINISHED =>
			info += "Finished";
		}
	}

	if(ctx.status & CLIENT_AUTH)
		info += ": Client Auth";
	if(ctx.status & CERT_REQUEST)
		info += ": Cert Request";
	if(ctx.status & CERT_SENT)
		info += ": Cert Sent";
	if(ctx.status & CERT_RECEIVED)
		info += ": Cert Received";

	return info;
}

reset_client_random(ctx: ref Context)
{
	ctx.client_random[0:] = int_encode(ctx.session.connection_time, 4);
	ctx.client_random[4:] = random->randombuf(Random->NotQuiteRandom, 28);
}

reset_server_random(ctx: ref Context)
{
	ctx.server_random[0:] = int_encode(ctx.session.connection_time, 4);
	ctx.server_random[4:] = random->randombuf(Random->NotQuiteRandom, 28);
}

update_handshake_hash(ctx: ref Context, r: ref Record): string
{
	err := "";

	ctx.sha_state = keyring->sha1(r.data, len r.data, nil, ctx.sha_state);
	ctx.md5_state = keyring->md5(r.data, len r.data, nil, ctx.md5_state);
	if(ctx.sha_state == nil || ctx.md5_state == nil)
		err = "update handshake hash failed";

	# if(SSL_DEBUG)
	#	log("ssl3: update_handshake_hash\n\tmessage_data =\n\t\t" + bastr(r.data) + "\n");

	return err;
}

# Note:
#	this depends on the record protocol
protocol_read(ctx: ref Context): (ref Record, ref Protocol, string)
{
	p: ref Protocol;
	r: ref Record;
	e: string;

	vers := SSL_VERSION_2_0;
	if(ctx.status & SSL3_RECORD)
		vers = SSL_VERSION_3_0;
	if(ctx.status & USE_DEVSSL)
		(r, e) = devssl_read(ctx);
	else
		(r, e) = record_read(ctx);
	if(e != "")
		return (nil, nil, e);

	(p, e) = Protocol.decode(r, ctx);
	if(e != "")
		return (r, nil, e);

	return (r, p, nil);
}

# Alert messages with a level of fatal result in the immediate 
# termination of the connection and zero out session.

do_alert(a: ref Alert, ctx: ref Context)
{
	case a.level {
	SSL_FATAL =>

		case a.description {
		SSL_UNEXPECTED_MESSAGE =>

			# should never be observed in communication  
			# between proper implementations.
			break;

		SSL_HANDSHAKE_FAILURE =>

			# unable to negotiate an acceptable set of security
			# parameters given the options available. 
			break;

		* =>
			break;
		}

		ctx.session.session_id = nil;
		ctx.state = STATE_EXIT;

	SSL_WARNING =>

		case a.description {
		SSL_CLOSE_NOTIFY =>

			if(SSL_DEBUG)
				log("ssl3: do_alert SSL_WARNING:SSL_CLOSE_NOTIFY\n");
			# notifies the recipient that the sender will not 
			# send any more messages on this connection.

			ctx.state = STATE_EXIT;
			fatal(SSL_CLOSE_NOTIFY, "ssl3: response close notify", ctx);

		SSL_NO_CERTIFICATE =>

			# A no_certificate alert message may be sent in
			# response to a certification request if no
			# appropriate certificate is available.

			if(ctx.state == STATE_CLIENT_CERTIFICATE) {
				hm := ref Handshake.Certificate(ctx.local_info.certs);
				handshake_enque(hm, ctx);
			}

		SSL_BAD_CERTIFICATE or 

			# A certificate was corrupt, contained signatures
			# that did not verify correctly, etc.

		SSL_UNSUPPORTED_CERTIFICATE or 	

			# A certificate was of an unsupported type.

		SSL_CERTIFICATE_REVOKED or

			# A certificate was revoked by its signer. 	

		SSL_CERTIFICATE_EXPIRED or

			# A certificate has expired or is not currently
			# valid.	

		SSL_CERTIFICATE_UNKNOWN =>

			# Some other (unspecified) issue arose in
			# processing the certificate, rendering it
			# unacceptable.
			break;

		* =>
			ctx.session.session_id = nil;
			fatal(SSL_ILLEGAL_PARAMETER, "ssl3: unknown alert description", ctx);
		}

	* =>
		ctx.session.session_id = nil;
		fatal(SSL_ILLEGAL_PARAMETER, "ssl3: unknown alert level received", ctx);
	}
}

# notify the receiving party that subsequent records will
# be protected under the just-negotiated CipherSpec and keys.

do_change_cipher_spec(ctx: ref Context)
{
	# calculate and set new keys
	if(!(ctx.status & IN_READY)) {
		e := set_in_queue(ctx);
		if(e != "") {
			fatal(SSL_CLOSE_NOTIFY, "do_change_cipher_spec: setup new cipher failed", ctx);
			return;
		}
		ctx.status |= IN_READY;

		if(SSL_DEBUG)
			log("ssl3: set in cipher done\n");
	}

	ctx.state = STATE_FINISHED;
}


# process and advance handshake messages, update internal stack and switch to next 
# expected state(s).

do_handshake(handshake: ref Handshake, ctx: ref Context) : string
{
	e := "";
	
	pick h := handshake {
	HelloRequest =>
		if(!(ctx.status & CLIENT_SIDE) || ctx.state != STATE_HELLO_REQUEST) {
			e = "HelloRequest";
			break;
		}
		do_hello_request(ctx);

	ClientHello =>
		if((ctx.status & CLIENT_SIDE) || ctx.state != STATE_CLIENT_HELLO) {
			e = "ClientHello";
			break;
		}
		do_client_hello(h, ctx);

	ServerHello =>
		if(!(ctx.status & CLIENT_SIDE) || ctx.state != STATE_SERVER_HELLO) {
			e = "ServerHello";
			break;
		}
		do_server_hello(h, ctx);

	ClientKeyExchange =>
		if((ctx.status & CLIENT_SIDE) || ctx.state != STATE_CLIENT_KEY_EXCHANGE) {
			e = "ClientKeyExchange";
			break;
		}
		do_client_keyex(h, ctx);

	ServerKeyExchange =>
		if(!(ctx.status & CLIENT_SIDE) || 
			(ctx.state != STATE_SERVER_KEY_EXCHANGE && ctx.state != STATE_SERVER_HELLO_DONE)) {
			e = "ServerKeyExchange";
			break;
		}
		do_server_keyex(h, ctx);

	ServerHelloDone =>
		# diff from SSLRef, to support variant impl
		if(!(ctx.status & CLIENT_SIDE) || 
			(ctx.state != STATE_SERVER_HELLO_DONE && ctx.state != STATE_SERVER_KEY_EXCHANGE)) {
			e = "ServerHelloDone";
			break;
		}
		do_server_done(ctx);

	Certificate =>
		if(ctx.status & CLIENT_SIDE) {
			if(ctx.state != STATE_SERVER_CERTIFICATE) {
				e = "ServerCertificate";
				break;
			}
			do_server_cert(h, ctx);
		}
		else {
			if(ctx.state != STATE_CLIENT_CERTIFICATE) {
				e = "ClientCertificate";
				break;
			}
			do_client_cert(h, ctx); # server_side
		}

	CertificateRequest =>
		if(!(ctx.status & CLIENT_SIDE) || ctx.state != STATE_SERVER_HELLO_DONE
			|| ctx.state != STATE_SERVER_KEY_EXCHANGE) {
			e = "CertificateRequest";
			break;
		}
		do_cert_request(h, ctx);

	CertificateVerify =>
		if((ctx.status & CLIENT_SIDE) || ctx.state != STATE_CERTIFICATE_VERIFY) {
			e = "CertificateVerify";
			break;
		}
		do_cert_verify(h, ctx);

	Finished =>
		if(ctx.status & CLIENT_SIDE) {
			if(ctx.state != STATE_FINISHED) {
				e = "ClientFinished";
				break;
			}
			do_finished(SSL_CLIENT_SENDER, ctx);
		}
		else {
			if(ctx.state != STATE_FINISHED) {
				e = "ServerFinished";
				break;
			}
			do_finished(SSL_SERVER_SENDER, ctx);
		}

	* =>
		e = "unknown handshake message";
	}

	if(e != nil)
		e = "do_handshake: " + e;

	return e;
}

# [client side]
# The hello request message may be sent by server at any time, but will be ignored by 
# the client if the handshake protocol is already underway. It is simple notification 
# that the client should begin the negotiation process anew by sending a client hello 
# message.

do_hello_request(ctx: ref Context)
{
	# start from new handshake digest state
	ctx.sha_state = ctx.md5_state = nil;

	# Note:
	# 	sending ctx.local_info.suites instead of ctx.session.suite, 
	#	if session is resumable by server, ctx.session.suite will be used.
	handshake_enque(
		ref Handshake.ClientHello(
			ctx.session.version, 
			ctx.client_random, 
			ctx.session.session_id,	
			ctx.local_info.suites, 
			ctx.local_info.comprs
		),
		ctx
	);

	ctx.state = STATE_SERVER_HELLO;
}

# [client side]
# Processes the received server hello handshake message and determines if the session
# is resumable. (The client sends a client hello using the session id of the session
# to be resumed. The server then checks its session cache for a match. If a match is
# FOUND, and the server is WILLING to re-establish the connection under the specified
# session state, it will send a server hello with the SAME session id value.) If the
# session is resumed, at this point both client and server must send change cipher
# spec messages. If the session is not resumable, the client and server perform
# a full handshake. (On the server side, if a session id match is not found, the
# server generates a new session id or if the server is not willing to resume, the
# server uses a null session id).

do_server_hello(hm: ref Handshake.ServerHello, ctx: ref Context)
{
	# trying to resume
	if(bytes_cmp(ctx.session.session_id, hm.session_id) == 0) {

		if(SSL_DEBUG)
			log("ssl3: session resumed\n");

		ctx.status |= SESSION_RESUMABLE;
		# avoid version attack
		if(ctx.session.version[0] != hm.version[0] || 
			ctx.session.version[1] != hm.version[1]) {
			fatal(SSL_CLOSE_NOTIFY,	"do_server_hello: version mismatch", ctx);
			return;
		}

		ctx.server_random = hm.random;

		# uses the retrieved session suite by server (should be same by client)
		(ciph, keyx, sign, e) 
			:= suite_to_spec(hm.suite, SSL3_Suites);
		if(e != nil) {
			fatal(SSL_UNEXPECTED_MESSAGE, "server hello: suite not found", ctx);
			return;
		}
		ctx.sel_ciph = ciph;
		ctx.sel_keyx = keyx;
		ctx.sel_sign = sign;
		ctx.sel_cmpr = int ctx.session.compression; # not supported by ssl3 yet

		# calculate keys
		(ctx.cw_mac, ctx.sw_mac, ctx.cw_key, ctx.sw_key, ctx.cw_IV, ctx.sw_IV) 
			= calc_keys(ctx.sel_ciph, ctx.session.master_secret, 
			ctx.client_random, ctx.server_random);
		

		ctx.state = STATE_CHANGE_CIPHER_SPEC;
	}
	else {
		ctx.status &= ~SESSION_RESUMABLE;

		# On the server side, if a session id match is not found, the
		# server generates a new session id or if the server is not willing 
		# to resume, the server uses an empty session id and cannot be
		# cached by both client and server.

		ctx.session.session_id = hm.session_id;
		ctx.session.version = hm.version;
		ctx.server_random = hm.random;

		if(SSL_DEBUG)
			log("ssl3: do_server_hello:\n\tselected cipher suite =\n\t\t" 
			+ cipher_suite_info(hm.suite, SSL3_Suites) + "\n");

		(ciph, keyx, sign, e) := suite_to_spec(hm.suite, SSL3_Suites);
		if(e != nil) {
			fatal(SSL_UNEXPECTED_MESSAGE, "server hello: suite not found", ctx);
			return;
		}
		
		ctx.sel_ciph = ciph;
		ctx.sel_keyx = keyx;
		ctx.sel_sign = sign;
		ctx.sel_cmpr = int hm.compression; # not supported by ssl3 yet

		# next state is determined by selected key exchange and signature methods
		# the ctx.sel_keyx and ctx.sel_sign are completed by the following handshake
		# Certificate and/or ServerKeyExchange

		if(tagof ctx.sel_keyx == tagof KeyExAlg.DH && 
			tagof ctx.sel_sign == tagof SigAlg.anon)
			ctx.state = STATE_SERVER_KEY_EXCHANGE;
		else
			ctx.state = STATE_SERVER_CERTIFICATE;
	}
}

# [client side]
# Processes the received server key exchange message. The server key exchange message
# is sent by the server if it has no certificate, has a certificate only used for
# signing, or FORTEZZA KEA key exchange is used.

do_server_keyex(hm: ref Handshake.ServerKeyExchange, ctx: ref Context)
{
	# install exchange keys sent by server, this may require public key
	# retrieved from certificate sent by Handshake.Certificate message

	(err, i) := install_server_xkey(hm.xkey, ctx.sel_keyx);
	if(err == "")
		err = verify_server_xkey(ctx.client_random, ctx.server_random, hm.xkey, i, ctx.sel_sign);

	if(err == "")
		ctx.state = STATE_SERVER_HELLO_DONE;
	else
		fatal(SSL_HANDSHAKE_FAILURE, "do_server_keyex: " + err, ctx);
}

# [client side]
# Processes the received server hello done message by verifying that the server
# provided a valid certificate if required and checking that the server hello
# parameters are acceptable.

do_server_done(ctx: ref Context)
{
	# On client side, optionally send client cert chain if client_auth 
	# is required by the server. The server may drop the connection, 
	# if it does not receive client certificate in the following 
	# Handshake.ClientCertificate message
	if(ctx.status & CLIENT_AUTH) {
		if(ctx.local_info.certs != nil) {
			handshake_enque(
				ref Handshake.Certificate(ctx.local_info.certs),
				ctx
			);
			ctx.status |= CERT_SENT;
		}
		else {
			alert_enque(
				ref Alert(SSL_WARNING, SSL_NO_CERTIFICATE), 
				ctx
			);
		}
	}

	# calculate premaster secrect, client exchange keys and update ref KeyExAlg 
	# of the client side
	(x, pm, e) := calc_client_xkey(ctx.sel_keyx);
	if(e != "") {
		fatal(SSL_HANDSHAKE_FAILURE, e, ctx);
		return;
	}
	handshake_enque(ref Handshake.ClientKeyExchange(x), ctx);

	ms := calc_master_secret(pm, ctx.client_random, ctx.server_random);
	if(ms == nil) {
		fatal(SSL_HANDSHAKE_FAILURE, "server hello done: calc master secret failed", ctx);
		return;
	}
	# ctx.premaster_secret = pm;
	ctx.session.master_secret = ms;

	# sending certificate verifiy message if the client auth is required 
	# and client certificate has been sent,
	if(ctx.status & CERT_SENT) {
		sig : array of byte;
		(md5_hash, sha_hash) 
			:= calc_finished(nil, ctx.session.master_secret, ctx.sha_state, ctx.md5_state);
		# check type of client cert being sent
		pick sk := ctx.local_info.sk {
		RSA =>
			hashes := array [36] of byte;
			hashes[0:] = md5_hash;
			hashes[16:] = sha_hash;
			#(e, sig) = pkcs->rsa_sign(hashes, sk, PKCS->MD5_WithRSAEncryption);
		DSS =>
			#(e, sig) = pkcs->dss_sign(sha_hash, sk);
		* =>
			e = "unknown sign";
		}
		if(e != "") {
			fatal(SSL_HANDSHAKE_FAILURE, "server hello done: sign cert verify failed", ctx);
			return;
		}
		handshake_enque(ref Handshake.CertificateVerify(sig), ctx);
	}

	ccs_enque(ref ChangeCipherSpec(1), ctx);
	(ctx.cw_mac, ctx.sw_mac, ctx.cw_key, ctx.sw_key, ctx.cw_IV, ctx.sw_IV) 
		= calc_keys(ctx.sel_ciph, ctx.session.master_secret, 
		ctx.client_random, ctx.server_random);

	# set cipher on write channel
	e = set_out_queue(ctx);
	if(e != nil) {
		fatal(SSL_HANDSHAKE_FAILURE, "do_server_done: " + e, ctx);
		return;
	}
	ctx.status |= OUT_READY;

	if(SSL_DEBUG)
		log("ssl3: set out cipher done\n");
	(mh, sh) := calc_finished(SSL_CLIENT_SENDER, ctx.session.master_secret, 
		ctx.sha_state, ctx.md5_state);
# sending out the Finished msg causes MS https servers to hangup
#sys->print("RETURNING FROM DO_SERVER_DONE\n");
#return;
	handshake_enque(ref Handshake.Finished(mh, sh), ctx);

	ctx.state = STATE_CHANGE_CIPHER_SPEC;
}

# [client side]
# Process the received certificate message. 
# Note:
#	according to current US export law, RSA moduli larger than 512 bits
# 	may not be used for key exchange in software exported from US. With
# 	this message, larger RSA keys may be used as signature only
# 	certificates to sign temporary shorter RSA keys for key exchange.

do_server_cert(hm: ref Handshake.Certificate, ctx: ref Context)
{
	if(hm.cert_list == nil) {
		fatal(SSL_UNEXPECTED_MESSAGE, "nil peer certificate", ctx);
		return;
	}

	# server's certificate is the last one in the chain (reverse required)
	cl := hm.cert_list;
	ctx.session.peer_certs = nil;
	while(cl != nil) {
		ctx.session.peer_certs = hd cl::ctx.session.peer_certs;
		cl = tl cl;
	}

	# TODO: verify certificate chain
	#	check if in the acceptable dnlist
	# ctx.sel_keyx.peer_pk = x509->verify_chain(ctx.session.peer_certs);
	if(SSL_DEBUG)
		log("ssl3: number certificates got: " + string len ctx.session.peer_certs);
	peer_cert := hd ctx.session.peer_certs;
	(e, signed) := x509->Signed.decode(peer_cert);
	if(e != "") {
		if(SSL_DEBUG)
			log("ss3: server certificate: " + e);
		fatal(SSL_HANDSHAKE_FAILURE, "server certificate: " + e, ctx);
		return;
	}

	srv_cert: ref Certificate;
	(e, srv_cert) = x509->Certificate.decode(signed.tobe_signed);
	if(e != "") {
		if(SSL_DEBUG)
			log("ss3: server certificate: " + e);
		fatal(SSL_HANDSHAKE_FAILURE, "server certificate: " + e, ctx);
		return;
	}
	if(SSL_DEBUG)
		log("ssl3: " + srv_cert.tostring());

	# extract and determine byte of user certificate
	id: int;
	peer_pk: ref X509->PublicKey;
	(e, id, peer_pk) = srv_cert.subject_pkinfo.getPublicKey();
	if(e != "") {
		if(SSL_DEBUG)
			log("ss3: server certificate: " + e);
		fatal(SSL_HANDSHAKE_FAILURE, "server certificate:" + e, ctx);
		return;
	}

	pick key := peer_pk {
	RSA =>
		# TODO: to allow checking X509v3 KeyUsage extension
		if((0 && key.pk.modulus.bits() > 512 && ctx.sel_ciph.is_exportable)
			|| id == PKCS->id_pkcs_md2WithRSAEncryption 
			|| id == PKCS->id_pkcs_md4WithRSAEncryption 
			|| id == PKCS->id_pkcs_md5WithRSAEncryption) {
			pick sign := ctx.sel_sign {
			anon =>
				break;
			RSA =>
				break;
			* =>
				# error
			}
			if(ctx.local_info.sk == nil)
				ctx.sel_sign = ref SigAlg.RSA(nil, key.pk);
			else {
				pick mysk := ctx.local_info.sk {
				RSA =>
					ctx.sel_sign = ref SigAlg.RSA(mysk.sk, key.pk);
				* =>
					ctx.sel_sign = ref SigAlg.RSA(nil, key.pk);
				}
			}
			# key exchange may be tmp RSA, emhemeral DH depending on cipher suite
			ctx.state = STATE_SERVER_KEY_EXCHANGE;
		}
		# TODO: allow id == PKCS->id_rsa
		else if(id == PKCS->id_pkcs_rsaEncryption) {
			pick sign := ctx.sel_sign {
			anon =>
				break;
			* =>
				# error
			}
			ctx.sel_sign = ref SigAlg.anon();
			pick keyx := ctx.sel_keyx {
			RSA =>
				keyx.peer_pk = key.pk;
			* =>
				# error
			}
			ctx.state = STATE_SERVER_HELLO_DONE;
		}
		else {
			# error
		}
	DSS =>
		pick sign := ctx.sel_sign {
		DSS =>
			sign.peer_pk = key.pk;
			break;
		* =>
			# error
		}
		# should be key exchagne such as emhemeral DH
		ctx.state = STATE_SERVER_KEY_EXCHANGE;
	DH =>
		# fixed DH signed in certificate either by RSA or DSS???
		pick keyx := ctx.sel_keyx {
		DH =>
			keyx.peer_pk = key.pk;
		* => 
			# error 
		}
		ctx.state = STATE_SERVER_KEY_EXCHANGE;
	}

	if(e != nil) {
		fatal(SSL_HANDSHAKE_FAILURE, "do_server_cert: " + e, ctx);
		return;
	}
}

# [client side]
# Processes certificate request message. A non-anonymous server can optionally
# request a certificate from the client, if appropriate for the selected cipher
# suite It is a fatal handshake failure alert for an anonymous server to
# request client identification.

# TODO: use another module to do x509 certs, lookup and matching rules

do_cert_request(hm: ref Handshake.CertificateRequest, ctx: ref Context)
{
	found := 0;
	for(i := 0; i < len hm.cert_types; i++) {
		if(ctx.local_info.root_type == int hm.cert_types[i]) {
			found = 1;
			break;
		}
	}
	if(!found) {
		fatal(SSL_HANDSHAKE_FAILURE, "do_cert_request: no required type of cert", ctx);
		return;		
	}
	if(dn_cmp(ctx.local_info.dns, hm.dn_list) < 0) {
		fatal(SSL_HANDSHAKE_FAILURE, "do_cert_request: no required dn", ctx);
		return;		
	}
	if(ctx.session.peer_certs == nil) {
		fatal(SSL_NO_CERTIFICATE, "certificate request: no peer certificates", ctx);
		return;
	}

	ctx.status |= CLIENT_AUTH;
}

dn_cmp(a, b: list of array of byte): int
{
	return -1;
}

# [server side]
# Process client hello message. 

do_client_hello(hm: ref Handshake.ClientHello, ctx: ref Context)
{
	sndm : ref Handshake;
	e : string;

	if(hm.version[0] != SSL_VERSION_3_0[0] || hm.version[1] != SSL_VERSION_3_0[1]) { 
		fatal(SSL_UNEXPECTED_MESSAGE, "client hello: version mismatch", ctx);
		return;
	}
	# else SSL_VERSION_2_0

	if(hm.session_id != nil) { # trying to resume
		if(ctx.status & SESSION_RESUMABLE) {
			s := sslsession->get_session_byid(hm.session_id);
			if(s == nil) {
				fatal(SSL_UNEXPECTED_MESSAGE, "client hello: retrieve nil session", ctx);
				return;
			}

			if(s.version[0] != hm.version[0] || s.version[1] != hm.version[1]) {
				# avoid version attack
				fatal(SSL_UNEXPECTED_MESSAGE, "client hello: protocol mismatch", ctx);
				return;
			}

			reset_server_random(ctx);
			ctx.client_random = hm.random;

			sndm = ref Handshake.ServerHello(s.version, ctx.server_random, 
				s.session_id, s.suite, s.compression);
			handshake_enque(sndm, ctx);

			ccs_enque(ref ChangeCipherSpec(1), ctx);
			# use existing master_secret, calc keys
			(ctx.cw_mac, ctx.sw_mac, ctx.cw_key, ctx.sw_key, ctx.cw_IV, ctx.sw_IV) 
				= calc_keys(ctx.sel_ciph, ctx.session.master_secret, ctx.client_random, 
				ctx.server_random);
			e = set_out_queue(ctx);
			if(e != nil) {
				fatal(SSL_CLOSE_NOTIFY,	"client hello: setup new cipher failure", ctx);
				return;
			}
			if(SSL_DEBUG)
				log("do_client_hello: set out cipher done\n");

			(md5_hash, sha_hash) := calc_finished(SSL_SERVER_SENDER, 
				s.master_secret, ctx.sha_state, ctx.md5_state);

			handshake_enque(ref Handshake.Finished(md5_hash, sha_hash), ctx);
			
			ctx.session = s;
			ctx.state = STATE_CHANGE_CIPHER_SPEC;
			return;
		}

		fatal(SSL_CLOSE_NOTIFY,	"client hello: resume session failed", ctx);
		return;		
	}

	ctx.session.version = hm.version;
	if(ctx.session.peer != nil) {		
		ctx.session.session_id = random->randombuf(Random->NotQuiteRandom, 32);
		if(ctx.session.session_id == nil) {
			fatal(SSL_CLOSE_NOTIFY,	"client hello: generate session id failed", ctx);
			return;
		}
	}

	suite := find_cipher_suite(hm.suites, ctx.local_info.suites);
	if(suite != nil) {
		fatal(SSL_HANDSHAKE_FAILURE, "client hello: find cipher suite failed", ctx);
		return;
	}
		
	(ctx.sel_ciph, ctx.sel_keyx, ctx.sel_sign, e) = suite_to_spec(suite, SSL3_Suites);
	if(e != nil) {
		fatal(SSL_HANDSHAKE_FAILURE, "client hello: find cipher suite failed" + e, ctx);
		return;
	}

	# not supported by ssl3 yet
	ctx.sel_cmpr = int hm.compressions[0];
	ctx.client_random = hm.random;
	ctx.sha_state = nil;
	ctx.md5_state = nil;

	sndm = ref Handshake.ServerHello(ctx.session.version, ctx.server_random, 
		ctx.session.session_id, ctx.session.suite, ctx.session.compression);
	handshake_enque(sndm, ctx);

	# set up keys based on algorithms

	if(tagof ctx.sel_keyx != tagof KeyExAlg.DH) {
		if(ctx.local_info.certs == nil || ctx.local_info.sk == nil) {
			fatal(SSL_HANDSHAKE_FAILURE, "client hello: no local cert or key", ctx);
			return;
		}

		sndm = ref Handshake.Certificate(ctx.local_info.certs);
		handshake_enque(sndm, ctx);
	}

	if(tagof ctx.sel_keyx != tagof KeyExAlg.RSA || 
		tagof ctx.sel_sign != tagof SigAlg.anon) {
		params, signed_params, xkey: array of byte;
		(params, e) = calc_server_xkey(ctx.sel_keyx);
		if(e == "")
			(signed_params, e) = sign_server_xkey(ctx.sel_sign, params, 
				ctx.client_random, ctx.server_random); 
		if(e != "")
			
		n := len params + 2 + len signed_params;
		xkey = array [n] of byte;
		xkey[0:] = params;
		xkey[len params:] = int_encode(len signed_params, 2);
		xkey[len params+2:] = signed_params;
		handshake_enque(ref Handshake.ServerKeyExchange(xkey), ctx);
	}

	if(ctx.status & CLIENT_AUTH) {
		sndm = ref Handshake.CertificateRequest(ctx.local_info.types, ctx.local_info.dns);
		handshake_enque(sndm, ctx);

		ctx.status |= CERT_REQUEST;
		ctx.state = STATE_CLIENT_CERTIFICATE;
	}
	else
		ctx.state = STATE_CLIENT_KEY_EXCHANGE;

	handshake_enque(ref Handshake.ServerHelloDone(), ctx);
}

# [server side]
# Process the received client key exchange message. 

do_client_keyex(hm: ref Handshake.ClientKeyExchange, ctx: ref Context)
{
	(premaster_secret, err) := install_client_xkey(hm.xkey, ctx.sel_keyx);
	if(err != "") {
		fatal(SSL_HANDSHAKE_FAILURE, err, ctx);
		return;
	}
		
	ctx.session.master_secret = calc_master_secret(premaster_secret, 
		ctx.client_random, ctx.server_random);

	if(ctx.status & CERT_RECEIVED)	
		ctx.state = STATE_CERTIFICATE_VERIFY;
	else
		ctx.state = STATE_CHANGE_CIPHER_SPEC;
}

# [server side]
# Process the received certificate message from client. 

do_client_cert(hm: ref Handshake.Certificate, ctx: ref Context)
{
	ctx.session.peer_certs = hm.cert_list;
	
	# verify cert chain and determine the type of cert
	# ctx.peer_info.sk = x509->verify_chain(ctx.session.peer_certs);
	# if(ctx.peer_info.key == nil) {
	#	fatal(SSL_HANDSHAKE_FAILURE, "client certificate: cert verify failed", ctx);
	#	return;
	# }

	ctx.status |= CERT_RECEIVED;

	ctx.state = STATE_CLIENT_KEY_EXCHANGE;
}

# [server side]
# Process the received certificate verify message from client.

do_cert_verify(hm: ref Handshake.CertificateVerify, ctx: ref Context)
{
	if(ctx.status & CERT_RECEIVED) {
		# exp : array of byte;
		(md5_hash, sha_hash) 
			:= calc_finished(nil, ctx.session.master_secret, ctx.sha_state, ctx.md5_state);
		ok := 0;
		pick upk := ctx.sel_sign {
		RSA =>
			hashes := array [36] of byte;
			hashes[0:] = md5_hash;
			hashes[16:] = sha_hash;
			ok = pkcs->rsa_verify(hashes, hm.signature, upk.peer_pk, PKCS->MD5_WithRSAEncryption);
		DSS =>
			ok = pkcs->dss_verify(sha_hash, hm.signature, upk.peer_pk);
		}

		if(!ok) {
			fatal(SSL_HANDSHAKE_FAILURE, "do_cert_verify: client auth failed", ctx);
			return;
		}
	}
	else {
		alert_enque(ref Alert(SSL_WARNING, SSL_NO_CERTIFICATE), ctx);
		return;
	}

	ctx.state = STATE_CHANGE_CIPHER_SPEC;
}

# [client or server side]
# Process the received finished message either from client or server. 

do_finished(sender: array of byte, ctx: ref Context)
{
	# setup write_cipher if not yet
	if(!(ctx.status & OUT_READY)) {
		ccs_enque(ref ChangeCipherSpec(1), ctx);
		e := set_out_queue(ctx);
		if(e != nil) {
			fatal(SSL_CLOSE_NOTIFY, "do_finished: setup new cipher failed", ctx);
			return;
		}
		ctx.status |= OUT_READY;

		if(SSL_DEBUG)
			log("ssl3: set out cipher done\n");

		(md5_hash, sha_hash) := calc_finished(sender, ctx.session.master_secret, 
			ctx.sha_state, ctx.md5_state);
		handshake_enque(ref Handshake.Finished(md5_hash, sha_hash), ctx);
	}

	ctx.state = STATE_EXIT; # normal

	# clean read queue
	ctx.in_queue.fragment = 0;

	sslsession->add_session(ctx.session);

	if(SSL_DEBUG)
		log("ssl3: add session to session database done\n");
}

install_client_xkey(a: array of byte, keyx: ref KeyExAlg): (array of byte, string)
{
	pmaster, x : array of byte;
	err := "";
	pick kx := keyx {
	DH =>
		i := 0;
		(kx.peer_pk, i) = dh_params_decode(a);
		if(kx.peer_pk != nil) 
			pmaster = pkcs->computeDHAgreedKey(kx.sk.param, kx.sk.sk, kx.peer_pk.pk);
		else
			err = "decode dh params failed";
	RSA =>
		(err, x) = pkcs->rsa_decrypt(a, kx.sk, 2);
		if(err != "" || len x != 48) {
			err = "impl error";
		}
		else {
			if(x[0] != SSL_VERSION_3_0[0] && x[1] != SSL_VERSION_3_0[1])
				err = "version wrong: possible version attack";
			else
				pmaster = x[2:];
		}
	FORTEZZA_KEA =>
		err = "Fortezza unsupported";
	}
	return (pmaster, err);
}

install_server_xkey(a: array of byte, keyx: ref KeyExAlg): (string, int)
{
	err := "";
	i := 0;

	pick kx := keyx {
	DH =>
		(kx.peer_pk, i) = dh_params_decode(a);
		if(kx.peer_pk != nil) 
			kx.peer_params = kx.peer_pk.param;
	RSA =>
		peer_tmp: ref RSAParams;
		(peer_tmp, i, err) = rsa_params_decode(a);
		if(err == "") {
			modlen := len peer_tmp.modulus.iptobebytes();
			kx.peer_pk = ref RSAKey(peer_tmp.modulus, modlen, peer_tmp.exponent);
		}
	FORTEZZA_KEA =>	
		return ("Fortezza unsupported", i);
	}

	return (err, i);
}

verify_server_xkey(crand, srand: array of byte, a: array of byte, i : int, sign: ref SigAlg)
	: string
{
	pick sg := sign {
	anon => 
	RSA =>
		lb := a[0:i]::crand::srand::nil;
		(exp, nil, nil) := md5_sha_hash(lb, nil, nil);
		ok := pkcs->rsa_verify(exp, a[i+2:], sg.peer_pk, PKCS->MD5_WithRSAEncryption); 
		if(!ok)
			return "RSA sigature verification failed";
	DSS =>
		lb := a[0:i]::crand::srand::nil;
		(exp, nil) := sha_hash(lb, nil);
		ok := pkcs->dss_verify(exp, a[i+2:], sg.peer_pk); 
		if(!ok)
			return "DSS sigature verification failed";
	}

	return "";
}

calc_client_xkey(keyx: ref KeyExAlg): (array of byte, array of byte, string)
{
	pm, x : array of byte;
	err := "";
	pick kx := keyx {
	DH =>	
		# generate our own DH keys based on DH params of peer side
		(kx.sk, kx.exch_pk) = pkcs->setupDHAgreement(kx.peer_params);
		# TODO: need check type of client cert if(!ctx.status & CLIENT_AUTH)
		# 	for implicit case
		(x, err) = dh_exchpub_encode(kx.exch_pk);
		pm = pkcs->computeDHAgreedKey(kx.sk.param, kx.sk.sk, kx.peer_pk.pk);
	RSA =>
		pm = array [48] of byte;
		pm[0:] = SSL_VERSION_3_0; # against version attack
		pm[2:] = random->randombuf(Random->NotQuiteRandom, 46);
		(err, x) = pkcs->rsa_encrypt(pm, kx.peer_pk, 2);
	FORTEZZA_KEA =>	
		err = "Fortezza unsupported";
	}
	if(SSL_DEBUG)
		log("ssl3: calc_client_xkey: " + bastr(x));
	return (x, pm, err);
}

calc_server_xkey(keyx: ref KeyExAlg): (array of byte, string)
{
	params: array of byte;
	err: string;
	pick kx := keyx {
	DH =>
		(kx.sk, kx.exch_pk) = pkcs->setupDHAgreement(kx.params);
		(params, err) = dh_params_encode(kx.exch_pk);
	RSA =>
		tmp := ref RSAParams(kx.export_key.modulus, kx.export_key.exponent);
		(params, err) = rsa_params_encode(tmp);

	FORTEZZA_KEA =>	
		err = "Fortezza unsupported";
	}
	return (params, err);
}

sign_server_xkey(sign: ref SigAlg, params, cr, sr: array of byte): (array of byte, string)
{
	signed_params: array of byte;
	err: string;
	pick sg := sign {
	anon =>
	RSA =>
		lb := cr::sr::params::nil;
		(hashes, nil, nil) := md5_sha_hash(lb, nil, nil);
		(err, signed_params) = pkcs->rsa_sign(hashes, sg.sk, PKCS->MD5_WithRSAEncryption);
	DSS =>
		lb := cr::sr::params::nil;
		(hashes, nil) := sha_hash(lb, nil);
		(err, signed_params) = pkcs->dss_sign(hashes, sg.sk);
	}
	return (signed_params, err);
}

# ssl encoding of DH exchange public key

dh_exchpub_encode(dh: ref DHPublicKey): (array of byte, string)
{
	if(dh != nil) {		
		yb := dh.pk.iptobebytes();	
		if(yb != nil) {
			n := 2 + len yb;
			a := array [n] of byte;
			i := 0;
			a[i:] = int_encode(len yb, 2);			
			i += 2;
			a[i:] = yb;
			return (a, nil);
		}
	}
	return (nil, "nil dh params");
}

dh_params_encode(dh: ref DHPublicKey): (array of byte, string)
{
	if(dh != nil && dh.param != nil) {
		pb := dh.param.prime.iptobebytes();		
		gb := dh.param.base.iptobebytes();
		yb := dh.pk.iptobebytes();	
		if(pb != nil && gb != nil && yb != nil) {
			n := 6 + len pb + len gb + len yb;
			a := array [n] of byte;
			i := 0;
			a[i:] = int_encode(len pb, 2);			
			i += 2;
			a[i:] = pb;					
			i += len pb;
			a[i:] = int_encode(len gb, 2);			
			i += 2;
			a[i:] = gb;					
			i += len gb;
			a[i:] = int_encode(len yb, 2);			
			i += 2;
			a[i:] = yb;					
			i += len yb;
			return (a, nil);
		}
	}
	return (nil, "nil dh public key");
}

dh_params_decode(a: array of byte): (ref DHPublicKey, int)
{
	i := 0;
	for(;;) {
		n := int_decode(a[i:i+2]);			
		i += 2;
		if(i+n > len a)
			break;
		p := a[i:i+n];					
		i += n; 
		n = int_decode(a[i:i+2]);			
		i += 2;
		if(i+n > len a)
			break;
		g := a[i:i+n];					
		i += n;
		n = int_decode(a[i:i+2]);			
		i += 2;
		if(i+n > len a)
			break;
		Ys := a[i:i+n];				
		i += n;

		if(SSL_DEBUG)
			log("ssl3: dh_params_decode:" + "\n\tp =\n\t\t" + bastr(p)
			+ "\n\tg =\n\t\t" + bastr(g) + "\n\tYs =\n\t\t" + bastr(Ys) + "\n");

		# don't care privateValueLength
		param := ref DHParams(IPint.bebytestoip(p), IPint.bebytestoip(g), 0);
		return (ref DHPublicKey(param, IPint.bebytestoip(Ys)), i);
	}
	return (nil, i);
}

rsa_params_encode(rsa_params: ref RSAParams): (array of byte, string)
{
	if(rsa_params != nil) {
		mod := rsa_params.modulus.iptobebytes();
		exp := rsa_params.exponent.iptobebytes();
		if(mod != nil || exp != nil) {
			n := 4 + len mod + len exp;
			a := array [n] of byte;
			i := 0;
			a[i:] = int_encode(len mod, 2); 		
			i += 2;
			a[i:] = mod;					
			i += len mod;
			a[i:] = int_encode(len exp, 2);			
			i += 2;
			a[i:] = exp;					
			i += len exp;
			return (a, nil);
		}
	}
	return (nil, "nil rsa params");
}

rsa_params_decode(a: array of byte): (ref RSAParams, int, string)
{
	i := 0;
	for(;;) {
		if(len a < 2)
			break;
		n := int_decode(a[i:i+2]);
		i += 2;
		if(n < 0 || n + i > len a)
			break;
		mod := a[i:i+n];				
		i += n;
		n = int_decode(a[i:i+2]);			
		i += 2;
		if(n < 0 || n + i > len a)
			break;
		exp := a[i:i+n];				
		i += n;
		m := i;
		modulus := IPint.bebytestoip(mod);
		exponent := IPint.bebytestoip(exp);

		if(SSL_DEBUG)
			log("ssl3: decode RSA params\n\tmodulus = \n\t\t" + bastr(mod)
			+ "\n\texponent = \n\t\t" + bastr(exp) + "\n");

		if(len a < i+2)
			break;
		n = int_decode(a[i:i+2]);
		i += 2;
		if(len a != i + n)	
			break;
		return (ref RSAParams(modulus, exponent), m, nil);
	}
	return (nil, i, "encoding error");
}

# md5_hash       MD5(master_secret + pad2 +
#                     MD5(handshake_messages + Sender +
#                          master_secret + pad1));
# sha_hash       SHA(master_secret + pad2 +
#                     SHA(handshake_messages + Sender +
#                          master_secret + pad1));
#
# handshake_messages  All of the data from all handshake messages
#                     up to but not including this message.  This
#                     is only data visible at the handshake layer
#                     and does not include record layer headers.
#
# sender [4], master_secret [48]
# pad1 and pad2, 48 bytes for md5, 40 bytes for sha

calc_finished(sender, master_secret: array of byte, sha_state, md5_state: ref DigestState)
	: (array of byte, array of byte)
{
	sha_value := array [Keyring->SHA1dlen] of byte;
	md5_value := array [Keyring->MD5dlen] of byte;
	sha_inner := array [Keyring->SHA1dlen] of byte;
	md5_inner := array [Keyring->MD5dlen] of byte;

	lb := master_secret::SSL_MAC_PAD1[0:48]::nil;
	if(sender != nil)
		lb = sender::lb;
	(md5_inner, nil) = md5_hash(lb, md5_state);

	lb = master_secret::SSL_MAC_PAD1[0:40]::nil;
	if(sender != nil)
		lb = sender::lb;
	(sha_inner, nil) = sha_hash(lb, sha_state);

	(md5_value, nil) = md5_hash(master_secret::SSL_MAC_PAD2[0:48]::md5_inner::nil, nil);
	(sha_value, nil) = sha_hash(master_secret::SSL_MAC_PAD2[0:40]::sha_inner::nil, nil);

	# if(SSL_DEBUG)
	#	log("ssl3: calc_finished:" 
	#	+ "\n\tmd5_inner = \n\t\t" + bastr(md5_inner) 
	#	+ "\n\tsha_inner = \n\t\t" + bastr(sha_inner)
	#	+ "\n\tmd5_value = \n\t\t" + bastr(md5_value)
	#	+ "\n\tsha_value = \n\t\t" + bastr(sha_value) 
	#	+ "\n");

	return (md5_value, sha_value);
}


# master_secret =
#	MD5(premaster_secret + SHA('A' + premaster_secret +
#		ClientHello.random + ServerHello.random)) +
#	MD5(premaster_secret + SHA('BB' + premaster_secret +
#		ClientHello.random + ServerHello.random)) +
#	MD5(premaster_secret + SHA('CCC' + premaster_secret +
#		ClientHello.random + ServerHello.random));

calc_master_secret(pm, cr, sr: array of byte): array of byte
{
	ms := array [48] of byte;
	sha_value := array [Keyring->SHA1dlen] of byte;
	leader := array [3] of byte;

	j := 0;
	lb := pm::cr::sr::nil;
	for(i := 1; i <= 3; i++) {
		leader[0] = leader[1] = leader[2] = byte (16r40 + i);
		(sha_value, nil) = sha_hash(leader[0:i]::lb, nil);
		(ms[j:], nil) = md5_hash(pm::sha_value::nil, nil); 
		j += 16; # Keyring->MD5dlen
	}

	if(SSL_DEBUG)
		log("ssl3: calc_master_secret:\n\tmaster_secret = \n\t\t" + bastr(ms) + "\n");

	return ms;
}


# key_block =
# 	MD5(master_secret + SHA(`A' + master_secret + 
#				ServerHello.random + ClientHello.random)) +
#       MD5(master_secret + SHA(`BB' + master_secret + 
#				ServerHello.random + ClientHello.random)) +
#       MD5(master_secret + SHA(`CCC' + master_secret + 
#				ServerHello.random + ClientHello.random)) +
#	[...];

calc_key_material(n: int, ms, cr, sr: array of byte): array of byte
{
	key_block := array [n] of byte;
	sha_value := array [Keyring->SHA1dlen] of byte; # [20]
	md5_value := array [Keyring->MD5dlen] of byte; # [16]
	leader := array [10] of byte;

	if(n > 16*(len leader)) {
		if(SSL_DEBUG)
			log(sys->sprint("ssl3: calc key block: key size too long [%d]", n));
		return nil;
	}

	m := n;
	i, j, consumed, next : int = 0;
	lb := ms::sr::cr::nil;
	for(i = 0; m > 0; i++) {
		for(j = 0; j <= i; j++)
			leader[j] = byte (16r41 + i); # 'A', 'BB', 'CCC', etc.

		(sha_value, nil) = sha_hash(leader[0:i+1]::lb, nil);
		(md5_value, nil) = md5_hash(ms::sha_value::nil, nil); 

		consumed = Keyring->MD5dlen;
		if(m < Keyring->MD5dlen)
			consumed = m;
		m -= consumed;

		key_block[next:] = md5_value[0:consumed];
		next += consumed;		
	}

	if(SSL_DEBUG)
		log("ssl3: calc_key_material:" + "\n\tkey_block = \n\t\t" + bastr(key_block) + "\n");

	return key_block;
}

# Then the key_block is partitioned as follows.
#
#	client_write_MAC_secret[CipherSpec.hash_size]
#	server_write_MAC_secret[CipherSpec.hash_size]
#	client_write_key[CipherSpec.key_material]
#	server_write_key[CipherSpec.key_material]
#	client_write_IV[CipherSpec.IV_size] /* non-export ciphers */
#	server_write_IV[CipherSpec.IV_size] /* non-export ciphers */
#
# Any extra key_block material is discarded.
#
# Exportable encryption algorithms (for which
# CipherSpec.is_exportable is true) require additional processing as
# follows to derive their final write keys:
#
#	final_client_write_key = MD5(client_write_key +
#					ClientHello.random +
#					ServerHello.random);
#	final_server_write_key = MD5(server_write_key +
#					ServerHello.random +
#					ClientHello.random);
#
# Exportable encryption algorithms derive their IVs from the random
# messages:
#
#	client_write_IV = MD5(ClientHello.random + ServerHello.random);
#	server_write_IV = MD5(ServerHello.random + ClientHello.random);

calc_keys(ciph: ref CipherSpec, ms, cr, sr: array of byte) 
	: (array of byte, array of byte, array of byte, array of byte, array of byte, array of byte)
{
	cw_mac, sw_mac, cw_key, sw_key,	cw_IV, sw_IV: array of byte;

	n := ciph.key_material + ciph.hash_size;
	if(ciph.is_exportable == SSL_EXPORT_FALSE)
		n += ciph.IV_size;
	n *= 2;

	key_block := calc_key_material(n, ms, cr, sr);

	i := 0;
	if(ciph.hash_size != 0) {
		cw_mac = key_block[i:i+ciph.hash_size]; 
		i += ciph.hash_size;
		sw_mac = key_block[i:i+ciph.hash_size]; 
		i += ciph.hash_size;
	}

	if(ciph.is_exportable == SSL_EXPORT_FALSE) {
		if(ciph.key_material != 0) {
			cw_key = key_block[i:i+ciph.key_material]; 
			i += ciph.key_material;
			sw_key = key_block[i:i+ciph.key_material]; 
			i += ciph.key_material;
		}
		if(ciph.IV_size != 0) {
			cw_IV = key_block[i:i+ciph.IV_size]; 
			i += ciph.IV_size;
			sw_IV = key_block[i:i+ciph.IV_size]; 
			i += ciph.IV_size;
		}
	}
	else {
		if(ciph.key_material != 0) {
			cw_key = key_block[i:i+ciph.key_material]; 
			i += ciph.key_material;
			sw_key = key_block[i:i+ciph.key_material]; 
			i += ciph.key_material;
			(cw_key, nil) = md5_hash(cw_key::cr::sr::nil, nil);
			(sw_key, nil) = md5_hash(sw_key::sr::cr::nil, nil);
		}
		if(ciph.IV_size != 0) {
			(cw_IV, nil) = md5_hash(cr::sr::nil, nil);
			(sw_IV, nil) = md5_hash(sr::cr::nil, nil);
		}
	}

	if(SSL_DEBUG)
		log("ssl3: calc_keys:" 
		+ "\n\tclient_write_mac = \n\t\t" + bastr(cw_mac)
		+ "\n\tserver_write_mac = \n\t\t" + bastr(sw_mac)
		+ "\n\tclient_write_key = \n\t\t" + bastr(cw_key)
		+ "\n\tserver_write_key = \n\t\t" + bastr(sw_key)
 		+ "\n\tclient_write_IV  = \n\t\t" + bastr(cw_IV)
		+ "\n\tserver_write_IV = \n\t\t" + bastr(sw_IV) + "\n");

	return (cw_mac, sw_mac, cw_key, sw_key, cw_IV, sw_IV);
}

#
# decode protocol message
#
Protocol.decode(r: ref Record, ctx: ref Context): (ref Protocol, string)
{
	p : ref Protocol;

	case r.content_type {
	SSL_ALERT =>
		if(len r.data != 2)
			return (nil, "alert decode failed");

		p = ref Protocol.pAlert(ref Alert(int r.data[0], int r.data[1])); 

	SSL_CHANGE_CIPHER_SPEC =>
		if(len r.data != 1 || r.data[0] != byte 1)
			return (nil, "ChangeCipherSpec decode failed");

		p = ref Protocol.pChangeCipherSpec(ref ChangeCipherSpec(1));

	SSL_HANDSHAKE =>
		(hm, e) := Handshake.decode(r.data);
		if(e != nil)
			return (nil, e);

		pick h := hm {
		Finished =>
			exp_sender := SSL_CLIENT_SENDER;
			if(ctx.status & CLIENT_SIDE)
				exp_sender = SSL_SERVER_SENDER;

			(md5_hash, sha_hash) := calc_finished(exp_sender, 
				ctx.session.master_secret, ctx.sha_state, ctx.md5_state);

			if(SSL_DEBUG)
				log("ssl3: handshake_decode: finished"
				+ "\n\texpected_md5_hash = \n\t\t" + bastr(md5_hash)
				+ "\n\tgot_md5_hash = \n\t\t" + bastr(h.md5_hash)
				+ "\n\texpected_sha_hash = \n\t\t" + bastr(sha_hash)
				+ "\n\tgot_sha_hash = \n\t\t" + bastr(h.sha_hash) + "\n");

			#if(string md5_hash != string h.md5_hash || string sha_hash != string h.sha_hash)
			if(bytes_cmp(md5_hash, h.md5_hash) < 0 || bytes_cmp(sha_hash, h.sha_hash) < 0)
				return (nil, "finished: sender mismatch");

			e = update_handshake_hash(ctx, r);
			if(e != nil)
				return (nil, e);

		CertificateVerify =>

			e = update_handshake_hash(ctx, r);
			if(e != nil)
				return (nil, e);

		* =>
			e = update_handshake_hash(ctx, r);
			if(e != nil)
				return (nil, e);
		}

		p = ref Protocol.pHandshake(hm);

	SSL_V2HANDSHAKE =>

		(hm, e) := V2Handshake.decode(r.data);
		if(e != "")
			return (nil, e);

		p = ref Protocol.pV2Handshake(hm);

	* =>
		return (nil, "protocol read: unknown protocol");
	}

	return (p, nil);

}


# encode protocol message and return tuple of data record and error message,
# may be v2 or v3 record depending on vers.

Protocol.encode(protocol: self ref Protocol, vers: array of byte): (ref Record, string)
{
	r: ref Record;
	e: string;

	pick p := protocol {
	pAlert =>
		r = ref Record(
				SSL_ALERT,
				vers,
				array [] of {byte p.alert.level, byte p.alert.description}
			);

	pChangeCipherSpec =>
		r = ref Record(
				SSL_CHANGE_CIPHER_SPEC,
				vers,
				array [] of {byte p.change_cipher_spec.value}
			);

	pHandshake =>
		data: array of byte;
		(data, e) = p.handshake.encode();
		if(e != "")
			break;
		r = ref Record(
				SSL_HANDSHAKE, 
				vers,
				data
			);

	pV2Handshake =>
		data: array of byte;
		(data, e) = p.handshake.encode();
		if(e != "")
			break;
		r = ref Record(
				SSL_V2HANDSHAKE,
				vers,
				data
			);

	* =>
		e = "unknown protocol";
	}

	if(SSL_DEBUG)
		log("ssl3: protocol encode\n" + protocol.tostring());

	return (r, e);
}

#
# protocol message description
#
Protocol.tostring(protocol: self ref Protocol): string
{
	info : string;

	pick p := protocol {
	pAlert =>
		info = "\tAlert\n" + p.alert.tostring();

	pChangeCipherSpec =>
		info = "\tChangeCipherSpec\n";

	pHandshake =>
		info = "\tHandshake\n" + p.handshake.tostring();

	pV2Handshake =>
		info = "\tV2Handshake\n" + p.handshake.tostring();

	pApplicationData =>
		info = "\tApplicationData\n";

	* =>
		info = "\tUnknownProtocolType\n";
	}

	return "ssl3: Protocol:\n" + info;
}

Handshake.decode(buf: array of byte): (ref Handshake, string)
{
	m : ref Handshake;
	e : string;

	a := buf[4:]; # ignore msg length

	i := 0;
	case int buf[0] {
	SSL_HANDSHAKE_HELLO_REQUEST =>
		m = ref Handshake.HelloRequest();

        SSL_HANDSHAKE_CLIENT_HELLO =>
    		if(len a < 38) {
			e = "client hello: unexpected message";
			break;
		}
    		cv := a[i:i+2];
		i += 2;
		rd := a[i:i+32];	
		i += 32;    
		lsi := int a[i++];
    		if(len a < 38 + lsi) {
			e = "client hello: unexpected message";
			break;
		}
		sid: array of byte;
		if(lsi != 0) {
			sid = a[i:i+lsi];			
			i += lsi;
		}
		else
			sid = nil;
		lcs := int_decode(a[i:i+2]);    	
		i += 2;
		if((lcs & 1) || lcs < 2 || len a < 40 + lsi + lcs) {
			e = "client hello: unexpected message";
			break;
		}
		cs := array [lcs/2] of byte;
		cs = a[i:i+lcs];
		i += lcs;
		lcm := int a[i++];
		cr := a[i:i+lcm];			
		i += lcm;
		# In the interest of forward compatibility, it is
		# permitted for a client hello message to include
		# extra data after the compression methods. This
		# data must be included in the handshake hashes, 
		# but otherwise be ignored.
		# if(i != len a) {
		#	e = "client hello: unexpected message";
		#	break;
		# }
		m = ref Handshake.ClientHello(cv, rd, sid, cs, cr);

        SSL_HANDSHAKE_SERVER_HELLO =>
		if(len a < 38) {
			e = "server hello: unexpected message";
			break;
		}
		sv := a[i:i+2];			
		i += 2;
		rd := a[i:i+32];			
		i += 32;
		lsi := int a[i++];
		if(len a < 38 + lsi) {
			e = "server hello: unexpected message";
			break;
		}
		sid : array of byte;
		if(lsi != 0) {
			sid = a[i:i+lsi];			
			i += lsi;
		}
		else
			sid = nil;
		cs := a[i:i+2];			
		i += 2;
		cr := a[i++];
		if(i != len a) {
			e = "server hello: unexpected message";
			break;
		}
		m = ref Handshake.ServerHello(sv, rd, sid, cs, cr);

        SSL_HANDSHAKE_CERTIFICATE =>
		n := int_decode(a[i:i+3]);		
		i += 3;
		if(len a != n + 3) {
			e = "certificate: unexpected message";
			break;
		}
		cl : list of array of byte;
		k : int;
		while(i < n) {
			k = int_decode(a[i:i+3]);
			i += 3;	
			if(k < 0 || i + k > len a) {
				e = "certificate: unexpected message";
				break;
			}
			cl = a[i:i+k] :: cl;		
			i += k;
		}
		if(e != nil)
			break;
		m = ref Handshake.Certificate(cl);

        SSL_HANDSHAKE_SERVER_KEY_EXCHANGE =>

		m = ref Handshake.ServerKeyExchange(a[i:]);
		
        SSL_HANDSHAKE_CERTIFICATE_REQUEST =>
		ln := int_decode(a[i:i+2]);		
		i += 2;
		types := a[i:i+ln];			
		i += ln;
		ln = int_decode(a[i:i+2]);		
		i += 2;
		auths : list of array of byte;
		for(j := 0; j < ln; j++) {
			ln = int_decode(a[i:i+2]);	
			i += 2;
			auths = a[i:i+ln]::auths;	
			i += ln;
		}
		m = ref Handshake.CertificateRequest(types, auths);

        SSL_HANDSHAKE_SERVER_HELLO_DONE =>
		if(len a != 0) {
			e = "server hello done: unexpected message";
			break;
		}
		m = ref Handshake.ServerHelloDone();
	
        SSL_HANDSHAKE_CERTIFICATE_VERIFY =>
		ln := int_decode(a[i:i+2]);		
		i +=2;
		sig := a[i:];				
		i += ln;
		if(i != len a) {
			e = "certificate verify: unexpected message";
			break;
		}
		m = ref Handshake.CertificateVerify(sig);

        SSL_HANDSHAKE_CLIENT_KEY_EXCHANGE =>
		m = ref Handshake.ClientKeyExchange(a);

        SSL_HANDSHAKE_FINISHED =>
		if(len a != Keyring->MD5dlen + Keyring->SHA1dlen) { # 16+20
			e = "finished: unexpected message";
			break;
		}
		md5_hash := a[i:i+Keyring->MD5dlen];	
		i += Keyring->MD5dlen;
		sha_hash := a[i:i+Keyring->SHA1dlen];	
		i += Keyring->SHA1dlen;
		if(i != len a) {
			e = "finished: unexpected message";
			break;
		}
		m = ref Handshake.Finished(md5_hash, sha_hash);

	* =>
		e = "unknown message";
	}

	if(e != nil)
		return (nil, "Handshake decode: " + e);

	return (m, nil);
}

Handshake.encode(hm: self ref Handshake): (array of byte, string)
{
	a : array of byte;
	n : int;
	e : string;

	i := 0;
	pick m := hm {
	HelloRequest =>
		a = array [4] of byte;
		a[i++] = byte SSL_HANDSHAKE_HELLO_REQUEST;
		a[i:] = int_encode(n, 3);
		i += 3;
		if(i != 4)
			e = "hello request: wrong message length";

        ClientHello =>
		lsi := len m.session_id;
		lcs := len m.suites;
		if((lcs &1) || lcs < 2) {
			e = "client hello: cipher suites is not multiple of 2 bytes";
			break;
		}
		lcm := len m.compressions;
		n = 38 + lsi + lcs + lcm; # 2+32+1+2+1
		a = array[n+4] of byte;
		a[i++] = byte SSL_HANDSHAKE_CLIENT_HELLO;
		a[i:] = int_encode(n, 3);
		i += 3;
		a[i:] = m.version;
		i += 2;
		a[i:] = m.random;
		i += 32;
		a[i++] = byte lsi;
		if(lsi != 0) {
			a[i:] = m.session_id;	
			i += lsi;
		}
		a[i:] = int_encode(lcs, 2);		
		i += 2;
		a[i:] = m.suites; # not nil
		i += lcs;
		a[i++] = byte lcm;
		a[i:] = m.compressions;	# not nil	
		i += lcm;
		if(i != n+4)
			e = "client hello: wrong message length";

        ServerHello =>
		lsi := len m.session_id;
		n = 38 + lsi; # 2+32+1+2+1
		a = array [n+4] of byte;
		a[i++] = byte SSL_HANDSHAKE_SERVER_HELLO;
		a[i:] = int_encode(n, 3);		
		i += 3;
		a[i:] = m.version;		
		i += 2;
		a[i:] = m.random;			
		i += 32;
		a[i++] = byte lsi;
		if(lsi != 0) {
			a[i:] = m.session_id;			
			i += lsi;
		}
		a[i:] = m.suite; # should be verified, not nil
		i += 2;
		a[i++] = m.compression; # should be verified, not nil
		if(i != n+4)
			e = "server hello: wrong message length";

        Certificate =>
		cl := m.cert_list;
		while(cl != nil) {
			n += 3 + len hd cl;
			cl = tl cl;
		}
		a = array [n+7] of byte; 
		a[i++] = byte SSL_HANDSHAKE_CERTIFICATE;
		a[i:] = int_encode(n+3, 3); # length of record		
		i += 3;
		a[i:] = int_encode(n, 3); # total length of cert chain
		i += 3;
		cl = m.cert_list;
		while(cl != nil) {
			a[i:] = int_encode(len hd cl, 3); 
			i += 3;
			a[i:] = hd cl;			
			i += len hd cl;
			cl = tl cl;
		} 
		if(i != n+7)
			e = "certificate: wrong message length";

        ServerKeyExchange =>
		n = len m.xkey;
		a = array [n+4] of byte;
		a[i++] = byte SSL_HANDSHAKE_SERVER_KEY_EXCHANGE;
		a[i:] = int_encode(n, 3);		
		i += 3;
		a[i:] = m.xkey;		
		i += len m.xkey;
		if(i != n+4)
			e = "server key exchange: wrong message length";
		
        CertificateRequest =>
		ntypes := len m.cert_types;
		nauths := len m.dn_list;
		n = 1 + ntypes;
		dl := m.dn_list;
		while(dl != nil) {
			n += 2 + len hd dl;			
			dl = tl dl;
		}
		n += 2;	
		a = array [n+4] of byte;
		a[i++] =  byte SSL_HANDSHAKE_CERTIFICATE_REQUEST;
		a[i:] = int_encode(n, 3);		
		i += 3;
		a[i++] = byte ntypes;
		a[i:] = m.cert_types;		
		i += ntypes;
		a[i:] = int_encode(nauths, 2);		
		i += 2;
		dl = m.dn_list;
		while(dl != nil) {
			a[i:] = int_encode(len hd dl, 2); 
			i += 2;
			a[i:] = hd dl;			
			i += len hd dl;
			dl = tl dl;
		}
		if(i != n+4)
			e = "certificate request: wrong message length";
		
        ServerHelloDone =>
		n = 0;
		a = array[n+4] of byte;
		a[i++] = byte SSL_HANDSHAKE_SERVER_HELLO_DONE;
		a[i:] = int_encode(0, 3); # message has 0 length
		i += 3;
		if(i != n+4)
			e = "server hello done: wrong message length";

        CertificateVerify =>
		n = 2 + len m.signature;
		a = array [n+4] of byte;
		a[i++] = byte SSL_HANDSHAKE_CERTIFICATE_VERIFY;
		a[i:] = int_encode(n, 3);		
		i += 3;
		a[i:] = int_encode(n-2, 2);		
		i += 2;
		a[i:] = m.signature;			
		i += n-2;
		if(i != n+4)
			e = "certificate verify: wrong message length";

        ClientKeyExchange =>
		n = len m.xkey;
		a = array [n+4] of byte;
		a[i++] = byte SSL_HANDSHAKE_CLIENT_KEY_EXCHANGE;
		a[i:] = int_encode(n, 3);		
		i += 3;
		a[i:] = m.xkey;		
		i += n;
		if(i != n+4)
			e = "client key exchange: wrong message length";

        Finished =>
		n = len m.md5_hash + len m.sha_hash;
		a = array [n+4] of byte;
		a[i++] = byte SSL_HANDSHAKE_FINISHED;    
		a[i:] = int_encode(n, 3);
		i += 3;
		a[i:] = m.md5_hash;			
		i += len m.md5_hash;
		a[i:] = m.sha_hash;			
		i += len m.sha_hash;
		if(i != n+4)
			e = "finished: wrong message length";

	* =>
		e = "unknown message";
	}
	
	if(e != nil)
		return (nil, "Handshake encode: " + e);

	return (a, e);
}

Handshake.tostring(handshake: self ref Handshake): string
{
	info: string;

	pick m := handshake {
        HelloRequest =>
		info = "\tHelloRequest\n"; 

        ClientHello =>
		info = "\tClientHello\n" + 
			"\tversion = \n\t\t" + bastr(m.version) + "\n" +
			"\trandom = \n\t\t" + bastr(m.random) + "\n" +
			"\tsession_id = \n\t\t" + bastr(m.session_id) + "\n" +
			"\tsuites = \n\t\t" + bastr(m.suites) + "\n" +
			"\tcomperssion_methods = \n\t\t" + bastr(m.compressions) +"\n";

        ServerHello =>
		info = "\tServerHello\n" + 
			"\tversion = \n\t\t" + bastr(m.version) + "\n" +
			"\trandom = \n\t\t" + bastr(m.random) + "\n" +
			"\tsession_id = \n\t\t" + bastr(m.session_id) + "\n" +
			"\tsuite = \n\t\t" + bastr(m.suite) + "\n" +
			"\tcomperssion_method = \n\t\t" + string m.compression +"\n";

        Certificate =>
		info = "\tCertificate\n" + 
			"\tcert_list = \n\t\t" + lbastr(m.cert_list) + "\n";

        ServerKeyExchange =>
		info = "\tServerKeyExchange\n" +
			"\txkey = \n\t\t" + bastr(m.xkey) +"\n";

        CertificateRequest =>
		info = "\tCertificateRequest\n" +
			"\tcert_types = \n\t\t" + bastr(m.cert_types) + "\n" +
			"\tdn_list = \n\t\t" + lbastr(m.dn_list) + "\n";

        ServerHelloDone =>
		info = "\tServerDone\n";

        CertificateVerify =>
		info = "\tCertificateVerify\n" +
			"\tsignature = \n\t\t" + bastr(m.signature) + "\n"; 

        ClientKeyExchange =>
		info = "\tClientKeyExchange\n" +
			"\txkey = \n\t\t" + bastr(m.xkey) +"\n";

        Finished =>
		info = "\tFinished\n" +
			"\tmd5_hash = \n\t\t" + bastr(m.md5_hash) + "\n" +
			"\tsha_hash = \n\t\t" + bastr(m.sha_hash) + "\n";
	}

	return info;
}

Alert.tostring(alert: self ref Alert): string
{
	info: string;

	case alert.level {
	SSL_WARNING =>				
		info += "\t\twarning: ";

	SSL_FATAL =>				
		info += "\t\tfatal: ";

	*  =>
		info += sys->sprint("unknown alert level[%d]: ", alert.level);
	}

	case alert.description {
	SSL_CLOSE_NOTIFY => 			
		info += "close notify";

	SSL_NO_CERTIFICATE => 			
		info += "no certificate";

	SSL_BAD_CERTIFICATE => 			
		info += "bad certificate";

	SSL_UNSUPPORTED_CERTIFICATE => 		
		info += "unsupported certificate";

	SSL_CERTIFICATE_REVOKED => 		
		info += "certificate revoked";

	SSL_CERTIFICATE_EXPIRED =>		
		info += "certificate expired";

	SSL_CERTIFICATE_UNKNOWN =>		
		info += "certificate unknown";

	SSL_UNEXPECTED_MESSAGE =>		
		info += "unexpected message";

	SSL_BAD_RECORD_MAC =>	 		
		info += "bad record mac";

	SSL_DECOMPRESSION_FAILURE => 		
		info += "decompression failure";

	SSL_HANDSHAKE_FAILURE => 		
		info += "handshake failure";

	SSL_ILLEGAL_PARAMETER => 		
		info += "illegal parameter";

	* =>
		info += sys->sprint("unknown alert description[%d]", alert.description);
	}

	return info;
}

find_cipher_suite(s, suites: array of byte) : array of byte
{
	i, j : int;
	a, b : array of byte;

	n := len s;
	if((n & 1) || n < 2)
		return nil;

	m := len suites;
	if((m & 1) || m < 2)
		return nil;

	for(i = 0; i < n; ) {
		a = s[i:i+2];
		i += 2;
		for(j = 0; j < m; ) {
			b = suites[j:j+2];
			j += 2;
			if(a[0] == b[0] && a[1] == b[1]) 
				return b;
		}
	}

	return nil;
}

#
# cipher suites and specs
#
suite_to_spec(cs: array of byte, cipher_suites: array of array of byte) 
	: (ref CipherSpec, ref KeyExAlg, ref SigAlg, string)
{
	cip : ref CipherSpec;
	kex : ref KeyExAlg;
	sig : ref SigAlg;

	n := len cipher_suites;
	i : int;
	found := array [2] of byte;
	for(i = 0; i < n; i++) {
		found = cipher_suites[i];
		if(found[0]==cs[0] && found[1]==cs[1]) break;
	}

	if(i == n)
		return (nil, nil, nil, "fail to find a matched spec");

	case i {
	NULL_WITH_NULL_NULL =>
		cip = ref CipherSpec(SSL_EXPORT_TRUE, SSL_NULL_CIPHER, 
			SSL_STREAM_CIPHER, 0, 0, SSL_NULL_MAC, 0);
		kex = ref KeyExAlg.NULL();
		sig = ref SigAlg.anon();

	RSA_WITH_NULL_MD5 => # sign only certificate
		cip = ref CipherSpec(SSL_EXPORT_TRUE, SSL_NULL_CIPHER, 
			SSL_STREAM_CIPHER, 0, 0, SSL_MD5, Keyring->MD5dlen);
		kex = ref KeyExAlg.RSA(nil, nil, nil);
		sig = ref SigAlg.anon();

	RSA_WITH_NULL_SHA => 	
		cip = ref CipherSpec(SSL_EXPORT_TRUE, SSL_NULL_CIPHER, 
			SSL_STREAM_CIPHER, 0, 0, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.RSA(nil, nil, nil);
		sig = ref SigAlg.anon();

	RSA_EXPORT_WITH_RC4_40_MD5 =>
		cip = ref CipherSpec(SSL_EXPORT_TRUE, SSL_RC4, 
			SSL_STREAM_CIPHER, 5, 0, SSL_MD5, Keyring->MD5dlen);
		kex = ref KeyExAlg.RSA(nil, nil, nil);
		sig = ref SigAlg.anon();

	RSA_WITH_RC4_128_MD5 => 	
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_RC4, 
			SSL_STREAM_CIPHER, 16, 0, SSL_MD5, Keyring->MD5dlen);
		kex = ref KeyExAlg.RSA(nil, nil, nil);
		sig = ref SigAlg.anon();

	RSA_WITH_RC4_128_SHA => 	
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_RC4, 
			SSL_STREAM_CIPHER, 16, 0, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.RSA(nil, nil, nil);
		sig = ref SigAlg.anon();

	RSA_EXPORT_WITH_RC2_CBC_40_MD5 =>
		cip = ref CipherSpec(SSL_EXPORT_TRUE, SSL_RC2_CBC, 
			SSL_BLOCK_CIPHER, 5, 8, SSL_MD5, Keyring->MD5dlen);
		kex = ref KeyExAlg.RSA(nil, nil, nil);
		sig = ref SigAlg.RSA(nil, nil);

	RSA_WITH_IDEA_CBC_SHA => 	
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_IDEA_CBC,
			SSL_BLOCK_CIPHER, 16, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.RSA(nil, nil, nil);
		sig = ref SigAlg.anon();

	RSA_EXPORT_WITH_DES40_CBC_SHA => 
		cip = ref CipherSpec(SSL_EXPORT_TRUE, SSL_DES_CBC, 
			SSL_BLOCK_CIPHER, 5, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.RSA(nil, nil, nil);
		sig = ref SigAlg.RSA(nil, nil);

	RSA_WITH_DES_CBC_SHA => 
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_DES_CBC, 
			SSL_BLOCK_CIPHER, 8, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.RSA(nil, nil, nil);
		sig = ref SigAlg.anon();

	RSA_WITH_3DES_EDE_CBC_SHA => 
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_3DES_EDE_CBC, 
			SSL_BLOCK_CIPHER, 24, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.RSA(nil, nil, nil);
		sig = ref SigAlg.anon();

	DH_DSS_EXPORT_WITH_DES40_CBC_SHA =>
		cip = ref CipherSpec(SSL_EXPORT_TRUE, SSL_DES_CBC, 
			SSL_BLOCK_CIPHER, 5, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.DH(nil, nil, nil, nil, nil);
		sig = ref SigAlg.DSS(nil, nil);

	DH_DSS_WITH_DES_CBC_SHA => 	
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_DES_CBC, 
			SSL_BLOCK_CIPHER, 8, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.DH(nil, nil, nil, nil, nil);
		sig = ref SigAlg.DSS(nil, nil);

	DH_DSS_WITH_3DES_EDE_CBC_SHA => 
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_3DES_EDE_CBC, 
			SSL_BLOCK_CIPHER, 24, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.DH(nil, nil, nil, nil, nil);
		sig = ref SigAlg.DSS(nil, nil);

	DH_RSA_EXPORT_WITH_DES40_CBC_SHA => 
		cip = ref CipherSpec(SSL_EXPORT_TRUE, SSL_DES_CBC, 
			SSL_BLOCK_CIPHER, 5, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.DH(nil, nil, nil, nil, nil);
		sig = ref SigAlg.RSA(nil, nil);

	DH_RSA_WITH_DES_CBC_SHA => 
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_DES_CBC, 
			SSL_STREAM_CIPHER, 8, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.DH(nil, nil, nil, nil, nil);
		sig = ref SigAlg.RSA(nil, nil);

	DH_RSA_WITH_3DES_EDE_CBC_SHA => 
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_3DES_EDE_CBC, 
			SSL_BLOCK_CIPHER, 24, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.DH(nil, nil, nil, nil, nil);
		sig = ref SigAlg.RSA(nil, nil);

	DHE_DSS_EXPORT_WITH_DES40_CBC_SHA =>
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_DES_CBC, 
			SSL_BLOCK_CIPHER, 5, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.DH(nil, nil, nil, nil, nil);
		sig = ref SigAlg.DSS(nil, nil);

	DHE_DSS_WITH_DES_CBC_SHA => 
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_DES_CBC, 
			SSL_BLOCK_CIPHER, 8, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.DH(nil, nil, nil, nil, nil);
		sig = ref SigAlg.DSS(nil, nil);

	DHE_DSS_WITH_3DES_EDE_CBC_SHA => 
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_3DES_EDE_CBC, 
			SSL_BLOCK_CIPHER, 24, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.DH(nil, nil, nil, nil, nil);
		sig = ref SigAlg.DSS(nil, nil);

	DHE_RSA_EXPORT_WITH_DES40_CBC_SHA =>
		cip = ref CipherSpec(SSL_EXPORT_TRUE, SSL_DES_CBC, 
			SSL_BLOCK_CIPHER, 5, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.DH(nil, nil, nil, nil, nil);
		sig = ref SigAlg.RSA(nil, nil);

	DHE_RSA_WITH_DES_CBC_SHA => 	
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_DES_CBC, 
			SSL_BLOCK_CIPHER, 8, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.DH(nil, nil, nil, nil, nil);
		sig = ref SigAlg.RSA(nil, nil);

	DHE_RSA_WITH_3DES_EDE_CBC_SHA => 	
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_3DES_EDE_CBC, 
			SSL_BLOCK_CIPHER, 24, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.DH(nil, nil, nil, nil, nil);
		sig = ref SigAlg.RSA(nil, nil);

	DH_anon_EXPORT_WITH_RC4_40_MD5 => 
		cip = ref CipherSpec(SSL_EXPORT_TRUE, SSL_RC4, 
			SSL_STREAM_CIPHER, 5, 0, SSL_MD5, Keyring->MD5dlen);
		kex = ref KeyExAlg.DH(nil, nil, nil, nil, nil);
		sig = ref SigAlg.anon();

	DH_anon_WITH_RC4_128_MD5 => 
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_RC4, 
			SSL_STREAM_CIPHER, 16, 0, SSL_MD5, Keyring->MD5dlen);
		kex = ref KeyExAlg.DH(nil, nil, nil, nil, nil);
		sig = ref SigAlg.anon();

	DH_anon_EXPORT_WITH_DES40_CBC_SHA =>
		cip = ref CipherSpec(SSL_EXPORT_TRUE, SSL_DES_CBC, 
			SSL_BLOCK_CIPHER, 5, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.DH(nil, nil, nil, nil, nil);
		sig = ref SigAlg.anon();

	DH_anon_WITH_DES_CBC_SHA => 	
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_DES_CBC, 
			SSL_BLOCK_CIPHER, 8, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.DH(nil, nil, nil, nil, nil);
		sig = ref SigAlg.anon();

	DH_anon_WITH_3DES_EDE_CBC_SHA => 	
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_3DES_EDE_CBC, 
			SSL_BLOCK_CIPHER, 24, 8, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.DH(nil, nil, nil, nil, nil);
		sig = ref SigAlg.anon();

	FORTEZZA_KEA_WITH_NULL_SHA => 	
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_NULL_CIPHER, 
			SSL_STREAM_CIPHER, 0, 0, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.FORTEZZA_KEA();
		sig = ref SigAlg.FORTEZZA_KEA();

	FORTEZZA_KEA_WITH_FORTEZZA_CBC_SHA =>
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_FORTEZZA_CBC, 
			SSL_BLOCK_CIPHER, 0, 0, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.FORTEZZA_KEA();
		sig = ref SigAlg.FORTEZZA_KEA();

	FORTEZZA_KEA_WITH_RC4_128_SHA =>
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_RC4, 
			SSL_STREAM_CIPHER, 16, 0, SSL_SHA, Keyring->SHA1dlen);
		kex = ref KeyExAlg.FORTEZZA_KEA();
		sig = ref SigAlg.FORTEZZA_KEA();

	}

	return (cip, kex, sig, nil);
}

#
# use suites as default SSL3_Suites
#
cipher_suite_info(cs: array of byte, suites: array of array of byte) : string
{
	tag : string;

	a := array [2] of byte;
	n := len suites;
	for(i := 0; i < n; i++) {
		a = suites[i];
		if(a[0]==cs[0] && a[1]==cs[1]) break;
	}

	if(i == n)
		return "unknown cipher suite [" + string cs + "]";

	case i {
	NULL_WITH_NULL_NULL => 		
		tag = "NULL_WITH_NULL_NULL";

	RSA_WITH_NULL_MD5 => 		
		tag = "RSA_WITH_NULL_MD5";

	RSA_WITH_NULL_SHA => 		
		tag = "RSA_WITH_NULL_SHA";

	RSA_EXPORT_WITH_RC4_40_MD5 => 	
		tag = "RSA_EXPORT_WITH_RC4_40_MD5";

	RSA_WITH_RC4_128_MD5 => 		
		tag = "RSA_WITH_RC4_128_MD5"; 	

	RSA_WITH_RC4_128_SHA => 		
		tag = "RSA_WITH_RC4_128_SHA";

	RSA_EXPORT_WITH_RC2_CBC_40_MD5 => 	
		tag = "RSA_EXPORT_WITH_RC2_CBC_40_MD5";

	RSA_WITH_IDEA_CBC_SHA => 		
		tag = "RSA_WITH_IDEA_CBC_SHA";

	RSA_EXPORT_WITH_DES40_CBC_SHA => 	
		tag ="RSA_EXPORT_WITH_DES40_CBC_SHA";

	RSA_WITH_DES_CBC_SHA =>		
		tag = "RSA_WITH_DES_CBC_SHA";

	RSA_WITH_3DES_EDE_CBC_SHA => 	
		tag = "RSA_WITH_3DES_EDE_CBC_SHA";

	DH_DSS_EXPORT_WITH_DES40_CBC_SHA => 
		tag = "DH_DSS_EXPORT_WITH_DES40_CBC_SHA";

	DH_DSS_WITH_DES_CBC_SHA => 		
		tag = "DH_DSS_WITH_DES_CBC_SHA";

	DH_DSS_WITH_3DES_EDE_CBC_SHA => 	
		tag = "DH_DSS_WITH_3DES_EDE_CBC_SHA";

	DH_RSA_EXPORT_WITH_DES40_CBC_SHA => 
		tag = "DH_RSA_EXPORT_WITH_DES40_CBC_SHA";

	DH_RSA_WITH_DES_CBC_SHA => 		
		tag = "DH_RSA_WITH_DES_CBC_SHA";

	DH_RSA_WITH_3DES_EDE_CBC_SHA => 	
		tag = "DH_RSA_WITH_3DES_EDE_CBC_SHA";

	DHE_DSS_EXPORT_WITH_DES40_CBC_SHA => 
		tag = "DHE_DSS_EXPORT_WITH_DES40_CBC_SHA";

	DHE_DSS_WITH_DES_CBC_SHA => 	
		tag = "DHE_DSS_WITH_DES_CBC_SHA";

	DHE_DSS_WITH_3DES_EDE_CBC_SHA => 	
		tag = "DHE_DSS_WITH_3DES_EDE_CBC_SHA";

	DHE_RSA_EXPORT_WITH_DES40_CBC_SHA => 
		tag = "DHE_RSA_EXPORT_WITH_DES40_CBC_SHA";

	DHE_RSA_WITH_DES_CBC_SHA => 
		tag = "DHE_RSA_WITH_DES_CBC_SHA";

	DHE_RSA_WITH_3DES_EDE_CBC_SHA => 
		tag = "DHE_RSA_WITH_3DES_EDE_CBC_SHA";

	DH_anon_EXPORT_WITH_RC4_40_MD5 => 
		tag = "DH_anon_EXPORT_WITH_RC4_40_MD5";

	DH_anon_WITH_RC4_128_MD5 => 
		tag = "DH_anon_WITH_RC4_128_MD5";

	DH_anon_EXPORT_WITH_DES40_CBC_SHA => 
		tag = "DH_anon_EXPORT_WITH_DES40_CBC_SHA";

	DH_anon_WITH_DES_CBC_SHA => 
		tag = "DH_anon_WITH_DES_CBC_SHA";

	DH_anon_WITH_3DES_EDE_CBC_SHA => 
		tag = "DH_anon_WITH_3DES_EDE_CBC_SHA";

	FORTEZZA_KEA_WITH_NULL_SHA => 
		tag = "FORTEZZA_KEA_WITH_NULL_SHA";

	FORTEZZA_KEA_WITH_FORTEZZA_CBC_SHA => 
		tag = "FORTEZZA_KEA_WITH_FORTEZZA_CBC_SHA";

	FORTEZZA_KEA_WITH_RC4_128_SHA => 
		tag = "FORTEZZA_KEA_WITH_RC4_128_SHA";
	}

	return "cipher suite = [" + tag + "]";
}

#################################
## FOR SSLv2 BACKWARD COMPATIBLE
#################################

# Protocol Version Codes
SSL2_CLIENT_VERSION				:= array [] of {byte 0, byte 16r02};
SSL2_SERVER_VERSION				:= array [] of {byte 0, byte 16r02};

# Protocol Message Codes

SSL2_MT_ERROR,
	SSL2_MT_CLIENT_HELLO,
	SSL2_MT_CLIENT_MASTER_KEY,
	SSL2_MT_CLIENT_FINISHED,
	SSL2_MT_SERVER_HELLO,
	SSL2_MT_SERVER_VERIFY,
	SSL2_MT_SERVER_FINISHED,
	SSL2_MT_REQUEST_CERTIFICATE,
	SSL2_MT_CLIENT_CERTIFICATE		: con iota;

# Error Message Codes

SSL2_PE_NO_CIPHER				:= array [] of {byte 0, byte 16r01};
SSL2_PE_NO_CERTIFICATE				:= array [] of {byte 0, byte 16r02};
SSL2_PE_BAD_CERTIFICATE				:= array [] of {byte 0, byte 16r04};
SSL2_PE_UNSUPPORTED_CERTIFICATE_TYPE		:= array [] of {byte 0, byte 16r06};

# Cipher Kind Values

SSL2_CK_RC4_128_WITH_MD5,
	SSL2_CK_RC4_128_EXPORT40_WITH_MD5,
	SSL2_CK_RC2_CBC_128_CBC_WITH_MD5,
	SSL2_CK_RC2_CBC_128_CBC_EXPORT40_WITH_MD5,
	SSL2_CK_IDEA_128_CBC_WITH_MD5,
	SSL2_CK_DES_64_CBC_WITH_MD5,
	SSL2_CK_DES_192_EDE3_CBC_WITH_MD5 	: con iota;

SSL2_Cipher_Kinds := array [] of {
	SSL2_CK_RC4_128_WITH_MD5 => 		array [] of {byte 16r01, byte 0, byte 16r80},
	SSL2_CK_RC4_128_EXPORT40_WITH_MD5 => 	array [] of {byte 16r02, byte 0, byte 16r80},
	SSL2_CK_RC2_CBC_128_CBC_WITH_MD5 => 	array [] of {byte 16r03, byte 0, byte 16r80},
	SSL2_CK_RC2_CBC_128_CBC_EXPORT40_WITH_MD5 =>
						array [] of {byte 16r04, byte 0, byte 16r80},
	SSL2_CK_IDEA_128_CBC_WITH_MD5 => 	array [] of {byte 16r05, byte 0, byte 16r80},
	SSL2_CK_DES_64_CBC_WITH_MD5 => 		array [] of {byte 16r06, byte 0, byte 16r40},
	SSL2_CK_DES_192_EDE3_CBC_WITH_MD5 => 	array [] of {byte 16r07, byte 0, byte 16rC0},
};

# Certificate Type Codes

SSL2_CT_X509_CERTIFICATE			: con 16r01; # encode as one byte

# Authentication Type Codes

SSL2_AT_MD5_WITH_RSA_ENCRYPTION			: con byte 16r01;

# Upper/Lower Bounds

SSL2_MAX_MASTER_KEY_LENGTH_IN_BITS		: con 256;
SSL2_MAX_SESSION_ID_LENGTH_IN_BYTES		: con 16;
SSL2_MIN_RSA_MODULUS_LENGTH_IN_BYTES		: con 64;
SSL2_MAX_RECORD_LENGTH_2_BYTE_HEADER		: con 32767;
SSL2_MAX_RECORD_LENGTH_3_BYTE_HEADER		: con 16383;

# Handshake Internal State

SSL2_STATE_CLIENT_HELLO,
	SSL2_STATE_SERVER_HELLO,
	SSL2_STATE_CLIENT_MASTER_KEY,	
	SSL2_STATE_SERVER_VERIFY,
	SSL2_STATE_REQUEST_CERTIFICATE,
	SSL2_STATE_CLIENT_CERTIFICATE,
	SSL2_STATE_CLIENT_FINISHED,
	SSL2_STATE_SERVER_FINISHED,		
	SSL2_STATE_ERROR			: con iota;

# The client's challenge to the server for the server to identify itself is a 
# (near) arbitary length random. The v3 server will right justify the challenge 
# data to become the ClientHello.random data (padding with leading zeros, if 
# necessary). If the length of the challenge is greater than 32 bytes, then only
# the last 32 bytes are used. It is legitimate (but not necessary) for a v3 
# server to reject a v2 ClientHello that has fewer than 16 bytes of challenge 
# data.

SSL2_CHALLENGE_LENGTH				: con 16;

V2Handshake: adt {
	pick {
	Error =>
		code				: array of byte; # [2];
	ClientHello =>
		version				: array of byte; # [2]
		cipher_specs			: array of byte; # [3] x
		session_id			: array of byte;
		challenge			: array of byte;
	ServerHello =>
		session_id_hit			: int;
		certificate_type		: int;
		version				: array of byte; # [2]
		certificate			: array of byte; # only user certificate
		cipher_specs			: array of byte; # [3] x
		connection_id			: array of byte;
	ClientMasterKey =>
		cipher_kind			: array of byte; # [3]
		clear_key			: array of byte;
		encrypt_key			: array of byte;
		key_arg				: array of byte;
	ServerVerify =>
		challenge			: array of byte;
	RequestCertificate =>
		authentication_type		: int;
		certificate_challenge		: array of byte;
	ClientCertificate =>
		certificate_type		: int;
		certificate			: array of byte; # only user certificate
		response			: array of byte;
	ClientFinished =>
		connection_id			: array of byte;
	ServerFinished =>
		session_id			: array of byte;
	}  

	encode: fn(hm: self ref V2Handshake): (array of byte, string);
	decode: fn(a: array of byte): (ref V2Handshake, string);
	tostring: fn(h: self ref V2Handshake): string;
};


V2Handshake.tostring(handshake: self ref V2Handshake): string
{
	info := "";

	pick m := handshake {
        ClientHello =>
		info += "\tClientHello\n" + 
			"\tversion = \n\t\t" + bastr(m.version) + "\n" +
			"\tcipher_specs = \n\t\t" + bastr(m.cipher_specs) + "\n" +
			"\tsession_id = \n\t\t" + bastr(m.session_id) + "\n" +
			"\tchallenge = \n\t\t" + bastr(m.challenge) + "\n";

        ServerHello =>
		info += "\tServerHello\n" + 
			"\tsession_id_hit = \n\t\t" + string m.session_id_hit + "\n" +
			"\tcertificate_type = \n\t\t" + string m.certificate_type + "\n" +
			"\tversion = \n\t\t" + bastr(m.version) + "\n" +
			"\tcertificate = \n\t\t" + bastr(m.certificate) + "\n" +
			"\tcipher_specs = \n\t\t" + bastr(m.cipher_specs) + "\n" +
			"\tconnection_id = \n\t\t" + bastr(m.connection_id) + "\n";

	ClientMasterKey =>
		info += "\tClientMasterKey\n" +
			"\tcipher_kind = \n\t\t" + bastr(m.cipher_kind) + "\n" +
			"\tclear_key = \n\t\t" + bastr(m.clear_key) + "\n" +
			"\tencrypt_key = \n\t\t" + bastr(m.encrypt_key) + "\n" +
			"\tkey_arg = \n\t\t" + bastr(m.key_arg) + "\n";

	ServerVerify =>
		info += "\tServerVerify\n" + 
			"\tchallenge = \n\t\t" + bastr(m.challenge) + "\n";

	RequestCertificate =>
		info += "\tRequestCertificate\n" +
			"\tauthentication_type = \n\t\t" + string m.authentication_type + "\n" +
			"\tcertificate_challenge = \n\t\t" + bastr(m.certificate_challenge) + "\n";

	ClientCertificate =>
		info += "ClientCertificate\n" +
			"\tcertificate_type = \n\t\t" + string m.certificate_type + "\n" +
			"\tcertificate = \n\t\t" + bastr(m.certificate) + "\n" +
			"\tresponse = \n\t\t" + bastr(m.response) + "\n";

	ClientFinished =>
		info += "\tClientFinished\n" +
			"\tconnection_id = \n\t\t" + bastr(m.connection_id) + "\n";

	ServerFinished =>
		info += "\tServerFinished\n" +
			"\tsession_id = \n\t\t" + bastr(m.session_id) + "\n";
	}

	return info;
}


# v2 handshake protocol - message driven, v2 and v3 sharing the same context stack

do_v2handshake(v2hs: ref V2Handshake, ctx: ref Context): string
{
	e: string = nil;

	pick h := v2hs {
	Error =>
		do_v2error(h, ctx);

	ClientHello =>
		if((ctx.status & CLIENT_SIDE) || ctx.state != SSL2_STATE_CLIENT_HELLO) {
			e = "V2ClientHello";
			break;
		}
		do_v2client_hello(h, ctx);

	ServerHello =>
		if(!(ctx.status & CLIENT_SIDE) || ctx.state != SSL2_STATE_SERVER_HELLO) {
			e = "V2ServerHello";
			break;
		}
		do_v2server_hello(h, ctx);

	ClientMasterKey =>
		if((ctx.status & CLIENT_SIDE) || ctx.state != SSL2_STATE_CLIENT_MASTER_KEY) {
			e = "V2ClientMasterKey";
			break;
		}
		do_v2client_master_key(h, ctx);

	ServerVerify =>
		if(!(ctx.status & CLIENT_SIDE) || ctx.state != SSL2_STATE_SERVER_VERIFY) {
			e = "V2ServerVerify";
			break;
		}
		do_v2server_verify(h, ctx);
		
	RequestCertificate =>
		if(!(ctx.status & CLIENT_SIDE) || ctx.state != SSL2_STATE_SERVER_VERIFY) {
			e = "V2RequestCertificate";
			break;
		}
		do_v2req_cert(h, ctx);

	ClientCertificate =>
		if((ctx.status & CLIENT_SIDE) || ctx.state != SSL2_STATE_CLIENT_CERTIFICATE) {
			e = "V2ClientCertificate";
			break;
		}
		do_v2client_certificate(h, ctx);

	ClientFinished =>
		if((ctx.status & CLIENT_SIDE) || ctx.state != SSL2_STATE_CLIENT_FINISHED) {
			e = "V2ClientFinished";
			break;
		}
		do_v2client_finished(h, ctx);

	ServerFinished =>
		if(!(ctx.status & CLIENT_SIDE) || ctx.state != SSL2_STATE_SERVER_FINISHED) {
			e = "V2ServerFinished";
			break;
		}
		do_v2server_finished(h, ctx);
	}

	return e;
}

do_v2error(v2hs: ref V2Handshake.Error, ctx: ref Context)
{
	if(SSL_DEBUG)
		log("do_v2error: " + string v2hs.code);
	ctx.state = STATE_EXIT;
}

# [server side]
do_v2client_hello(v2hs: ref V2Handshake.ClientHello, ctx: ref Context)
{
	if(v2hs.version[0] != SSL2_CLIENT_VERSION[0] || v2hs.version[1] != SSL2_CLIENT_VERSION[1]) {
		# promote this message to v3 handshake protocol
		ctx.state = STATE_CLIENT_HELLO;
		return;
	}
	
	# trying to resume
	s: ref Session;
	if((v2hs.session_id != nil) && (ctx.status & SESSION_RESUMABLE))
		s = sslsession->get_session_byid(v2hs.session_id);
	if(s != nil) { # found a hit
		# prepare and send v2 handshake hello message
		v2handshake_enque(
			ref V2Handshake.ServerHello(
				1, # hit found
				0, # no certificate required
				SSL2_SERVER_VERSION, 
				nil, # no authetication required
				s.suite, # use hit session cipher kind
				ctx.server_random # connection_id
			),
			ctx
		);
		# TODO: should in supported cipher_kinds
		err: string;
		(ctx.sel_ciph, ctx.sel_keyx, ctx.sel_sign, err) 
			= v2suite_to_spec(ctx.session.suite, SSL2_Cipher_Kinds);
		if(err != "") {
			if(SSL_DEBUG)
				log("do_v2client_hello: " + err);
			ctx.state = SSL2_STATE_ERROR;
			return;
		}			
		ctx.state = SSL2_STATE_SERVER_FINISHED;
	}
	else {
		# find matching cipher kinds
		n := len v2hs.cipher_specs;
		matchs := array [n] of byte; 
		j, k: int = 0;
		while(j < n) {
			# ignore those not in SSL2_Cipher_Kinds
			matchs[k:] = v2hs.cipher_specs[j:j+3];
			for(i := 0; i < len SSL2_Cipher_Kinds; i++) {
				ck := SSL2_Cipher_Kinds[i];
				if(matchs[k] == ck[0] && matchs[k+1] == ck[1] && matchs[k+2] == ck[2])
					k +=3;
			}
			j += 3;
		}
		if(k == 0) {
			if(SSL_DEBUG)
				log("do_v2client_hello: No matching cipher kind");
			ctx.state = SSL2_STATE_ERROR;
		}
		else {
			matchs = matchs[0:k];

			# Note: 
			#	v2 challenge -> v3 client_random
			#	v2 connection_id -> v3 server_random

			chlen := len v2hs.challenge;
			if(chlen > 32)
				chlen = 32;
			ctx.client_random = array [chlen] of byte;
			if(chlen > 32)
				ctx.client_random[0:] = v2hs.challenge[chlen-32:];
			else
				ctx.client_random[0:] = v2hs.challenge;
			ctx.server_random = random->randombuf(Random->NotQuiteRandom, 16);
			s.session_id = random->randombuf (
					Random->NotQuiteRandom, 
					SSL2_MAX_SESSION_ID_LENGTH_IN_BYTES
				);
			s.suite = matchs;
			ctx.session = s;
			v2handshake_enque(
				ref V2Handshake.ServerHello(
					0, # no hit - not resumable
					SSL2_CT_X509_CERTIFICATE, 
					SSL2_SERVER_VERSION, 
					hd ctx.local_info.certs, # the first is user certificate
					ctx.session.suite, # matched cipher kinds
					ctx.server_random # connection_id
				),
				ctx
			);
			ctx.state = SSL2_STATE_CLIENT_MASTER_KEY;
		}
	}
}

# [client side]

do_v2server_hello(v2hs: ref V2Handshake.ServerHello, ctx: ref Context)
{
	# must be v2 server hello otherwise it will be v3 server hello
	# determined by auto record layer version detection
	if(v2hs.version[0] != SSL2_SERVER_VERSION[0] 
		|| v2hs.version[1] != SSL2_SERVER_VERSION[1]) {
		if(SSL_DEBUG)
			log("do_v2server_hello: not a v2 version");
		ctx.state = SSL2_STATE_ERROR;
		return;
	}

	ctx.session.version = SSL2_SERVER_VERSION;
	ctx.server_random = v2hs.connection_id;

	# check if a resumable session is found
	if(v2hs.session_id_hit != 0) { # resume ok
		err: string;
		# TODO: should in supported cipher_kinds
		(ctx.sel_ciph, nil, nil, err) = v2suite_to_spec(ctx.session.suite, SSL2_Cipher_Kinds);
		if(err !=  "") {
			if(SSL_DEBUG)
				log("do_v2server_hello: " + err);
			ctx.state = SSL2_STATE_ERROR;
			return;
		}
	}
	else { 	# not resumable session

		# use the first matched cipher kind; install cipher spec
		if(len v2hs.cipher_specs < 3) {
			if(SSL_DEBUG)
				log("do_v2server_hello: too few bytes");
			ctx.state = SSL2_STATE_ERROR;
			return;
		}
		ctx.session.suite = array [3] of byte;
		ctx.session.suite[0:] = v2hs.cipher_specs[0:3];
		err: string;
		(ctx.sel_ciph, nil, nil, err) = v2suite_to_spec(ctx.session.suite, SSL2_Cipher_Kinds);
		if(err != "") {
			if(SSL_DEBUG)
				log("do_v2server_hello: " + err);
			return;
		}
			
		# decode x509 certificates, authenticate server and extract 
		# public key from server certificate
		if(v2hs.certificate_type != int SSL2_CT_X509_CERTIFICATE) {
			if(SSL_DEBUG)
				log("do_v2server_hello: not x509 certificate");
			ctx.state = SSL2_STATE_ERROR;
			return;
		}
		ctx.session.peer_certs = v2hs.certificate :: nil;
		# TODO: decode v2hs.certificate as list of certificate
		# 	verify the list of certificate
		(e, signed) := x509->Signed.decode(v2hs.certificate);
		if(e != "") {
			if(SSL_DEBUG)
				log("do_v2server_hello: " + e);
			ctx.state = SSL2_STATE_ERROR;
			return;
		}
		certificate: ref Certificate;
		(e, certificate) = x509->Certificate.decode(signed.tobe_signed);
		if(e != "") {
			if(SSL_DEBUG)
				log("do_v2server_hello: " + e);
			ctx.state = SSL2_STATE_ERROR;
			return;
		}		
		id: int;
		peer_pk: ref X509->PublicKey;
		(e, id, peer_pk) = certificate.subject_pkinfo.getPublicKey();
		if(e != nil) {
			ctx.state = SSL2_STATE_ERROR; # protocol error
			return;
		}
		pk: ref RSAKey;
		pick key := peer_pk {
		RSA =>
			pk = key.pk;
		* =>
		}
		# prepare and send client master key message
		# TODO: change CipherSpec adt for more key info
		# Temporary solution
		# mkey (master key), ckey (clear key), skey(secret key)
		mkey, ckey, skey, keyarg: array of byte;
		(mkeylen, ckeylen, keyarglen) := v2suite_more(ctx.sel_ciph);
		mkey = random->randombuf(Random->NotQuiteRandom, mkeylen);
		if(ckeylen != 0)
			ckey = mkey[0:ckeylen];
		if(mkeylen > ckeylen)
			skey = mkey[ckeylen:];
		if(keyarglen > 0)
			keyarg = random->randombuf(Random->NotQuiteRandom, keyarglen);
		ekey: array of byte;
		(e, ekey) = pkcs->rsa_encrypt(skey, pk, 2);
		if(e != nil) {
			if(SSL_DEBUG)
				log("do_v2server_hello: " + e);
			ctx.state = SSL2_STATE_ERROR;	
			return;
		}
		ctx.session.master_secret = mkey;
		v2handshake_enque(
			ref V2Handshake.ClientMasterKey(ctx.session.suite, ckey, ekey, keyarg),
			ctx
		);
	}

	# clean up out_queue before switch cipher
	record_write_queue(ctx);
	ctx.out_queue.data = nil;

	# install keys onto ctx that will be pushed on ssl record when ready
	(ctx.cw_mac, ctx.sw_mac, ctx.cw_key, ctx.sw_key, ctx.cw_IV, ctx.sw_IV)
		= v2calc_keys(ctx.sel_ciph, ctx.session.master_secret, 
		ctx.client_random, ctx.server_random);
	e := set_queues(ctx);
	if(e != "") {
		if(SSL_DEBUG)
			log("do_v2server_finished: " + e);
		ctx.state = SSL2_STATE_ERROR;
		return;
	}
	ctx.status |= IN_READY;
	ctx.status |= OUT_READY;

	# prepare and send client finished message
	v2handshake_enque(
		ref V2Handshake.ClientFinished(ctx.server_random), # as connection_id
		ctx
	);

	ctx.state = SSL2_STATE_SERVER_VERIFY;
}

# [server side]

do_v2client_master_key(v2hs: ref V2Handshake.ClientMasterKey, ctx: ref Context)
{
	#if(cmk.cipher == -1 || cipher_info[cmk.cipher].cryptalg == -1) {
	#	# return ("protocol error: bad cipher in masterkey", nullc);
	#	ctx.state = SSL2_STATE_ERROR; # protocol error
	#	return;
	#}

	ctx.session.suite = v2hs.cipher_kind;

	# TODO:
	#	someplace shall be able to install the key
	# need further encapsulate encrypt and decrypt functions from KeyExAlg adt
	master_key_length: int;
	secret_key: array of byte;
	pick alg := ctx.sel_keyx {
	RSA =>
		e: string;
		(e, secret_key) = pkcs->rsa_decrypt(v2hs.encrypt_key, alg.sk, 0);
		if(e != "") {
			if(SSL_DEBUG)
				log("do_v2client_master_key: " + e);
			ctx.state = SSL2_STATE_ERROR;
			return;
		}
		master_key_length = len v2hs.clear_key + len secret_key;
	* =>
		if(SSL_DEBUG)
			log("do_v2client_master_key: unknown public key algorithm");
		ctx.state = SSL2_STATE_ERROR;
		return;
	}
	#TODO: do the following lines after modifying the CipherSpec adt
	#if(master_key_length != ci.keylen) {
	#	ctx.state = SSL2_STATE_ERROR; # protocol error
	#	return;
	#}

	ctx.session.master_secret = array [master_key_length] of byte;
	ctx.session.master_secret[0:] = v2hs.clear_key;
	ctx.session.master_secret[len v2hs.clear_key:] = secret_key;

	# install keys onto ctx that will be pushed on ssl record when ready
	(ctx.cw_mac, ctx.sw_mac, ctx.cw_key, ctx.sw_key, ctx.cw_IV, ctx.sw_IV)
		= v2calc_keys(ctx.sel_ciph, ctx.session.master_secret, 
		ctx.client_random, ctx.server_random);
	v2handshake_enque(
		ref V2Handshake.ServerVerify(ctx.client_random[16:]),
		ctx
	);
	v2handshake_enque(
		ref V2Handshake.ServerFinished(ctx.session.session_id),
		ctx
	);
	ctx.state = SSL2_STATE_CLIENT_FINISHED;
}

# used by client side
do_v2server_verify(v2hs: ref V2Handshake.ServerVerify, ctx: ref Context)
{
	# TODO:
	#	the challenge length may not be 16 bytes
	if(bytes_cmp(v2hs.challenge, ctx.client_random[32-SSL2_CHALLENGE_LENGTH:]) < 0) {
		if(SSL_DEBUG)
			log("do_v2server_verify: challenge mismatch");
		ctx.state = SSL2_STATE_ERROR;
		return;
	}

	ctx.state = SSL2_STATE_SERVER_FINISHED;
}

# [client side]

do_v2req_cert(v2hs: ref V2Handshake.RequestCertificate, ctx: ref Context)
{
	# not supported until v3
	if(SSL_DEBUG)
		log("do_v2req_cert: authenticate client not supported");
	v2hs = nil;
	ctx.state = SSL2_STATE_ERROR;
}

# [server side]

do_v2client_certificate(v2hs: ref V2Handshake.ClientCertificate, ctx: ref Context)
{
	# not supported until v3
	if(SSL_DEBUG)
		log("do_v2client_certificate: authenticate client not supported");
	v2handshake_enque (
		ref V2Handshake.Error(SSL2_PE_NO_CERTIFICATE),
		ctx
	);
	v2hs = nil;
	ctx.state = SSL2_STATE_ERROR;
}

# [server side]

do_v2client_finished(v2hs: ref V2Handshake.ClientFinished, ctx: ref Context)
{
	if(bytes_cmp(ctx.server_random, v2hs.connection_id) < 0) {
		ctx.session.session_id = nil;
		if(SSL_DEBUG)
			log("do_v2client_finished: connection id mismatch");
		ctx.state = SSL2_STATE_ERROR;
	}
	# TODO:
	#	the challenge length may not be 16 bytes
	v2handshake_enque(
		ref V2Handshake.ServerVerify(ctx.client_random[32-SSL2_CHALLENGE_LENGTH:]),
		ctx
	);
	if(ctx.session.session_id == nil)
		ctx.session.session_id = random->randombuf(Random->NotQuiteRandom, 16);
	v2handshake_enque(
		ref V2Handshake.ServerFinished(ctx.session.session_id),
		ctx
	);
	e := set_queues(ctx);
	if(e != "") {
		if(SSL_DEBUG)
			log("do_v2client_finished: " + e);
		ctx.state = SSL2_STATE_ERROR;
		return;
	}
	ctx.status |= IN_READY;
	ctx.status |= OUT_READY;
	sslsession->add_session(ctx.session);

	ctx.state = STATE_EXIT;
}

# [client side]

do_v2server_finished(v2hs: ref V2Handshake.ServerFinished, ctx: ref Context)
{
	if(ctx.session.session_id == nil)
		ctx.session.session_id = array [16] of byte;
	ctx.session.session_id[0:] = v2hs.session_id[0:];

	sslsession->add_session(ctx.session);

	ctx.state = STATE_EXIT;
}


# Note:
#	the key partitioning for v2 is different from v3

v2calc_keys(ciph: ref CipherSpec, ms, cr, sr: array of byte)
	: (array of byte, array of byte, array of byte, array of byte, array of byte, array of byte)
{
	cw_mac, sw_mac, cw_key, sw_key,	cw_IV, sw_IV: array of byte;

	# TODO: check the size of key block if IV exists
	(mkeylen, ckeylen, keyarglen) := v2suite_more(ciph);
	kblen := 2*mkeylen;
	if(kblen%Keyring->MD5dlen != 0) {
		if(SSL_DEBUG)
			log("v2calc_keys: key block length is not multiple of MD5 hash length");
	}
	else {
		key_block := array [kblen] of byte;

		challenge := cr[32-SSL2_CHALLENGE_LENGTH:32]; # TODO: if challenge length != 16 ?
		connection_id := sr[0:16]; # TODO: if connection_id length != 16 ?
		var := array [1] of byte;
		var[0] = byte 16r30;
		i := 0;
		while(i < kblen) {
			(hash, nil) := md5_hash(ms::var::challenge::connection_id::nil, nil);
			key_block[i:] = hash;
			i += Keyring->MD5dlen;
			++var[0];
		}

		if(SSL_DEBUG)
			log("ssl3: calc_keys:" 
			+ "\n\tmaster key = \n\t\t" + bastr(ms)
			+ "\n\tchallenge = \n\t\t" + bastr(challenge)
			+ "\n\tconnection id = \n\t\t" + bastr(connection_id)
			+ "\n\tkey block = \n\t\t" + bastr(key_block) + "\n");

		i = 0;
		# server write key == client read key
		# server write mac == server write key
		sw_key = array [mkeylen] of byte;
		sw_key[0:] = key_block[i:mkeylen];
		sw_mac = array [mkeylen] of byte;
		sw_mac[0:] = key_block[i:mkeylen];
		# client write key == server read key
		# client write mac == client write key
		i += mkeylen;
		cw_key = array [mkeylen] of byte;
		cw_key[0:] = key_block[i:i+mkeylen];
		cw_mac = array [mkeylen] of byte;
		cw_mac[0:] = key_block[i:i+mkeylen];
		# client IV == server IV
		# Note:
		#	IV is a part of writing or reading key for ssl device
		#	this is composed again in setctl
		cw_IV = array [keyarglen] of byte;
		cw_IV[0:] = ms[mkeylen:mkeylen+keyarglen];
		sw_IV = array [keyarglen] of byte;
		sw_IV[0:] = ms[mkeylen:mkeylen+keyarglen];
	}

	if(SSL_DEBUG)
		log("ssl3: calc_keys:" 
		+ "\n\tclient_write_mac = \n\t\t" + bastr(cw_mac)
		+ "\n\tserver_write_mac = \n\t\t" + bastr(sw_mac)
		+ "\n\tclient_write_key = \n\t\t" + bastr(cw_key)
		+ "\n\tserver_write_key = \n\t\t" + bastr(sw_key)
 		+ "\n\tclient_write_IV  = \n\t\t" + bastr(cw_IV)
		+ "\n\tserver_write_IV = \n\t\t" + bastr(sw_IV) + "\n");

	return (cw_mac, sw_mac, cw_key, sw_key, cw_IV, sw_IV);
}

v3tov2specs(suites: array of byte): array of byte
{
	# v3 suite codes are 2 bytes each, v2 codes are 3 bytes
	n := len suites / 2;
	kinds := array [n*3*2] of byte;
	k := 0;
	for(i := 0; i < n;) {
		a := suites[i:i+2];
		i += 2;
		m := len SSL3_Suites;
		for(j := 0; j < m; j++) {
			b := SSL3_Suites[j]; 
			if(a[0]==b[0] && a[1]==b[1]) 
				break;
		}
		if (j == m) {
			if(SSL_DEBUG)
				log("ssl3: unknown v3 suite");
			continue;
		}
		case j {
		RSA_EXPORT_WITH_RC4_40_MD5 => 	
			kinds[k:] = SSL2_Cipher_Kinds[SSL2_CK_RC4_128_EXPORT40_WITH_MD5];
			k += 3;
		RSA_WITH_RC4_128_MD5 => 		
			kinds[k:] = SSL2_Cipher_Kinds[SSL2_CK_RC4_128_WITH_MD5];
			k += 3;
		RSA_WITH_IDEA_CBC_SHA =>
			kinds[k:] = SSL2_Cipher_Kinds[SSL2_CK_IDEA_128_CBC_WITH_MD5];
			k += 3;
		RSA_WITH_DES_CBC_SHA =>
			;
		* =>
			if(SSL_DEBUG)
				log("ssl3: unable to convert v3 suite to v2 kind");
		}
		# append v3 code in v2-safe manner
		# (suite[0] == 0) => will be ignored by v2 server, picked up by v3 server
		kinds[k] = byte 16r00;
		kinds[k+1:] = SSL3_Suites[j];
		k += 3;
	}
	return kinds[0:k];
}

v2suite_to_spec(cs: array of byte, cipher_kinds: array of array of byte)
	: (ref CipherSpec, ref KeyExAlg, ref SigAlg, string)
{
	cip : ref CipherSpec;
	kex : ref KeyExAlg;
	sig : ref SigAlg;

	n := len cipher_kinds;
	for(i := 0; i < n; i++) {
		found := cipher_kinds[i];
		if(found[0]==cs[0] && found[1]==cs[1] && found[2]==cs[2]) break;
	}

	if(i == n)
		return (nil, nil, nil, "fail to find a matched spec");

	case i {
	SSL2_CK_RC4_128_WITH_MD5 =>
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_RC4, SSL_STREAM_CIPHER, 
				16, 0, SSL_MD5, Keyring->MD4dlen);

	SSL2_CK_RC4_128_EXPORT40_WITH_MD5 =>
		cip = ref CipherSpec(SSL_EXPORT_TRUE, SSL_RC4, SSL_STREAM_CIPHER, 
				5, 0, SSL_MD5, Keyring->MD4dlen);

	SSL2_CK_RC2_CBC_128_CBC_WITH_MD5 =>
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_RC2_CBC, SSL_BLOCK_CIPHER, 
				16, 8, SSL_MD5, Keyring->MD4dlen);

	SSL2_CK_RC2_CBC_128_CBC_EXPORT40_WITH_MD5 =>
		cip = ref CipherSpec(SSL_EXPORT_TRUE, SSL_RC2_CBC, SSL_BLOCK_CIPHER, 
				5, 8, SSL_MD5, Keyring->MD4dlen);

	SSL2_CK_IDEA_128_CBC_WITH_MD5 =>
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_IDEA_CBC, SSL_BLOCK_CIPHER, 
				16, 8, SSL_MD5, Keyring->MD4dlen);

	SSL2_CK_DES_64_CBC_WITH_MD5 =>
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_DES_CBC, SSL_BLOCK_CIPHER, 
				8, 8, SSL_MD5, Keyring->MD4dlen);

	SSL2_CK_DES_192_EDE3_CBC_WITH_MD5 =>
		cip = ref CipherSpec(SSL_EXPORT_FALSE, SSL_3DES_EDE_CBC, SSL_BLOCK_CIPHER, 
				24, 8, SSL_MD5, Keyring->MD4dlen);
	}

	kex = ref KeyExAlg.RSA(nil, nil, nil);
	sig = ref SigAlg.RSA(nil, nil);

	return (cip, kex, sig, nil);
}

v2suite_more(ciph: ref CipherSpec): (int, int, int)
{
	mkeylen, ckeylen, keyarglen: int;

	case ciph.bulk_cipher_algorithm {
	SSL_RC4 =>
		mkeylen = 16;
		if(ciph.key_material == 5)
			ckeylen = 16 - 5;
		else
			ckeylen = 0;
		keyarglen = 0;
		
	SSL_RC2_CBC =>
		mkeylen = 16;
		if(ciph.key_material == 5)
			ckeylen = 16 - 5;
		else
			ckeylen = 0;
		keyarglen = 8;

	SSL_IDEA_CBC =>
		mkeylen = 16;
		ckeylen = 0;
		keyarglen = 8;

	SSL_DES_CBC =>
		mkeylen = 8;
		if(ciph.key_material == 5)
			ckeylen = 8 - 5;
		else
			ckeylen = 0;
		keyarglen = 8;

	SSL_3DES_EDE_CBC =>
		mkeylen = 24;
		ckeylen = 0;
		keyarglen = 8;
	}

	return (mkeylen, ckeylen, keyarglen);
}

v2handshake_enque(h: ref V2Handshake, ctx: ref Context)
{
	p := ref Protocol.pV2Handshake(h);

	protocol_write(p, ctx);
}

V2Handshake.encode(hm: self ref V2Handshake): (array of byte, string)
{
	a : array of byte;
	n : int;
	e : string;

	i := 0;
	pick m := hm {
	Error =>
		n = 3;
		a = array[n] of byte;
		a[i++] = byte SSL2_MT_ERROR;
		a[i:] = m.code;

	ClientHello =>
		specslen := len m.cipher_specs;
		sidlen := len m.session_id;
		challen := len m.challenge;
		n = 9+specslen + sidlen + challen;
		a = array[n] of byte;
		a[i++] = byte SSL2_MT_CLIENT_HELLO;
		a[i:] = m.version;
		i += 2;
		a[i:] = int_encode(specslen, 2);
		i += 2;
		a[i:] = int_encode(sidlen, 2);
		i += 2;
		a[i:] = int_encode(challen, 2);
		i += 2;
		a[i:] = m.cipher_specs;
		i += specslen;
		if(sidlen != 0) {
			a[i:] = m.session_id;
			i += sidlen;
		}
		if(challen != 0) {
			a[i:] = m.challenge;
			i += challen;
		}	

	ServerHello =>
		# use only the user certificate
		certlen := len m.certificate;
#		specslen := 3*len m.cipher_specs;
		specslen := len m.cipher_specs;
		cidlen := len m.connection_id;
		n = 11 + certlen + specslen + cidlen;
		a = array[n] of byte;
		a[i++] = byte SSL2_MT_SERVER_HELLO;
		a[i++] = byte m.session_id_hit;
		a[i++] = byte m.certificate_type;
		a[i:] = m.version;
		i += 2;
		a[i:] = int_encode(certlen, 2);
		i += 2;
		a[i:] = int_encode(specslen, 2);
		i += 2;
		a[i:] = int_encode(cidlen, 2);
		i += 2;
		a[i:] = m.certificate;		
		i += certlen;
		a[i:] = m.cipher_specs;
		i += specslen;
		a[i:] = m.connection_id;
		i += cidlen;

	ClientMasterKey =>
		ckeylen := len m.clear_key;
		ekeylen := len m.encrypt_key;
		karglen := len m.key_arg;
		n = 10 + ckeylen + ekeylen + karglen;
		a = array[n] of byte;
		a[i++] = byte SSL2_MT_CLIENT_MASTER_KEY;
		a[i:] = m.cipher_kind;
		i += 3;
		a[i:] = int_encode(ckeylen, 2);
		i += 2;
		a[i:] = int_encode(ekeylen, 2);
		i += 2;
		a[i:] = int_encode(karglen, 2);
		i += 2;
		a[i:] = m.clear_key;
		i += ckeylen;
		a[i:] = m.encrypt_key;
		i += ekeylen;
		a[i:] = m.key_arg;
		i += karglen;

	ServerVerify =>
		challen := len m.challenge;
		n = 1 + challen;
		a = array[n] of byte;
		a[i++] = byte SSL2_MT_SERVER_VERIFY;
		a[i:] = m.challenge;

	RequestCertificate =>
		cclen := len m.certificate_challenge;
		n = 2 + cclen;
		a = array[n] of byte;
		a[i++] = byte SSL2_MT_REQUEST_CERTIFICATE;
		a[i++] = byte m.authentication_type;
		a[i:] = m.certificate_challenge;
		i += cclen;

	ClientCertificate =>
		# use only the user certificate
		certlen := len m.certificate;
		resplen := len m.response;
		n = 6 + certlen + resplen;
		a = array[n] of byte;
		a[i++] = byte SSL2_MT_CLIENT_CERTIFICATE;
		a[i++] = byte m.certificate_type;
		a[i:] = int_encode(certlen, 2);
		i += 2;
		a[i:] = int_encode(resplen, 2);
		i += 2;
		a[i:] = m.certificate;
		i += certlen;
		a[i:] = m.response;
		i += resplen;

	ClientFinished =>
		cidlen := len m.connection_id;
		n = 1 + cidlen;
		a = array[n] of byte;
		a[i++] = byte SSL2_MT_CLIENT_FINISHED;
		a[i:] = m.connection_id;
		i += cidlen;

	ServerFinished =>
		sidlen := len m.session_id;
		n = 1 + sidlen;
		a = array[n] of byte;
		a[i++] = byte SSL2_MT_SERVER_FINISHED;
		a[i:] = m.session_id;
		i += sidlen;
	}

	return (a, e);
}

V2Handshake.decode(a: array of byte): (ref V2Handshake, string)
{
	m : ref V2Handshake;
	e : string;

	n := len a;
	i := 1; 
	case int a[0] {
	SSL2_MT_ERROR =>
		if(n != 3)
			break;
		code := a[i:i+2];
		i += 2;
		m = ref V2Handshake.Error(code);

	SSL2_MT_CLIENT_HELLO =>
		if(n < 9) {
			e = "client hello: message too short";
			break;
		}
		ver := a[i:i+2];
		i += 2;
		specslen := int_decode(a[i:i+2]);
		i += 2;
		sidlen := int_decode(a[i:i+2]);
		i += 2;
		challen := int_decode(a[i:i+2]);
		i += 2;
		if(n != 9+specslen+sidlen+challen) {
			e = "client hello: length mismatch";
			break;
		}
		if(specslen%3 != 0) {
			e = "client hello: must multiple of 3 bytes";
			break;
		}
		specs: array of byte;
		if(specslen != 0) {
			specs = a[i:i+specslen];
			i += specslen;
		}
		sid: array of byte;
		if(sidlen != 0) {
			sid = a[i:i+sidlen];
			i += sidlen;
		}
		chal: array of byte;
		if(challen != 0) {
			chal = a[i:i+challen];
			i += challen;
		}
		m = ref V2Handshake.ClientHello(ver, specs, sid, chal);

	SSL2_MT_CLIENT_MASTER_KEY =>
		if(n < 10) {
			e = "client master key: message too short";
			break;
		}
		kind := a[i:i+3];
		i += 3;
		ckeylen := int_decode(a[i:i+2]);
		i += 2;
		ekeylen := int_decode(a[i:i+2]);
		i += 2;
		karglen := int_decode(a[i:i+2]);
		i += 2;
		if(n != 10 + ckeylen + ekeylen + karglen) {
			e = "client master key: length mismatch";
			break;
		}
		ckey := a[i:i+ckeylen];
		i += ckeylen;
		ekey := a[i:i+ekeylen];
		i += ekeylen;
		karg := a[i:i+karglen];
		i += karglen;
		m = ref V2Handshake.ClientMasterKey(kind, ckey, ekey, karg);

	SSL2_MT_CLIENT_FINISHED =>
		cid := a[i:n];
		i = n;
		m = ref V2Handshake.ClientFinished(cid);

	SSL2_MT_SERVER_HELLO =>
		if(n < 11) {
			e = "server hello: messsage too short";
			break;
		}
		sidhit := int a[i++];
		certtype := int a[i++];
		ver := a[i:i+2];
		i += 2;
		certlen := int_decode(a[i:i+2]);
		i += 2;
		specslen := int_decode(a[i:i+2]);
		i += 2;
		cidlen := int_decode(a[i:i+2]);
		i += 2;
		if(n != 11+certlen+specslen+cidlen) {
			e = "server hello: length mismatch";
			break;
		}
		cert := a[i:i+certlen];
		i += certlen;
		if(specslen%3 != 0) {
			e = "server hello: must be multiple of 3 bytes";
			break;
		}
		specs := a[i:i+specslen];
		i += specslen;
		if(cidlen < 16 || cidlen > 32) {
			e = "server hello: connection id length out of range";
			break;
		}
		cid := a[i:i+cidlen];
		i += cidlen;
		m = ref V2Handshake.ServerHello(sidhit, certtype, ver, cert, specs, cid);

	SSL2_MT_SERVER_VERIFY =>
		chal := a[i:n];
		i = n;
		m = ref V2Handshake.ServerVerify(chal);

	SSL2_MT_SERVER_FINISHED =>
		sid := a[i:n];
		m = ref V2Handshake.ServerFinished(sid);

	SSL2_MT_REQUEST_CERTIFICATE =>
		if(n < 2) {
			e = "request certificate: message too short";
			break;
		}
		authtype := int a[i++];
		certchal := a[i:n];
		i = n;
		m = ref V2Handshake.RequestCertificate(authtype, certchal);

	SSL2_MT_CLIENT_CERTIFICATE =>
		if(n < 6) {
			e = "client certificate: message too short";
			break;
		}
		certtype := int a[i++];
		certlen := int_decode(a[i:i+2]);
		i += 2;
		resplen := int_decode(a[i:i+2]);
		i += 2;
		if(n != 6+certlen+resplen) {
			e = "client certificate: length mismatch";
			break;
		}
		cert := a[i:i+certlen];
		i += certlen;
		resp := a[i:i+resplen];
		m = ref V2Handshake.ClientCertificate(certtype, cert, resp);

	* =>
		e = "unknown message [" + string a[0] + "]";
	}

	return (m, e);
}

# utilities

md5_hash(input: list of array of byte, md5_ds: ref DigestState): (array of byte, ref DigestState)
{
	hash_value := array [Keyring->MD5dlen] of byte;
	ds : ref DigestState;

	if(md5_ds != nil)
		ds = md5_ds.copy();

	lab := input;
	for(i := 0; i < len input - 1; i++) {
		ds = keyring->md5(hd lab, len hd lab, nil, ds);
		lab = tl lab;
	}
	ds = keyring->md5(hd lab, len hd lab, hash_value, ds);

	return (hash_value, ds);
}

sha_hash(input: list of array of byte, sha_ds: ref DigestState): (array of byte, ref DigestState)
{
	hash_value := array [Keyring->SHA1dlen] of byte;
	ds : ref DigestState;

	if(sha_ds != nil)
		ds = sha_ds.copy();

	lab := input;
	for(i := 0; i < len input - 1; i++) {
		ds = keyring->sha1(hd lab, len hd lab, nil, ds);
		lab = tl lab;
	}
	ds = keyring->sha1(hd lab, len hd lab, hash_value, ds);

	return (hash_value, ds);
}

md5_sha_hash(input: list of array of byte, md5_ds, sha_ds: ref DigestState)
	: (array of byte, ref DigestState, ref DigestState)
{
	buf := array [Keyring->MD5dlen+Keyring->SHA1dlen] of byte;

	(buf[0:], md5_ds) = md5_hash(input, md5_ds);
	(buf[Keyring->MD5dlen:], sha_ds) = sha_hash(input, sha_ds);

	return (buf, md5_ds, sha_ds);
}

int_decode(buf: array of byte): int
{
	val := 0;
	for(i := 0; i < len buf; i++)
		val = (val << 8) | (int buf[i]);

	return val;	
}

int_encode(value, length: int): array of byte
{
	buf := array [length] of byte;

	while(length--)	{   
		buf[length] = byte value;
		value >>= 8;
	}

	return buf;
}


bastr(a: array of byte) : string
{
	ans : string = "";

	for(i := 0; i < len a; i++) {
		if(i < len a - 1 && i != 0 && i%10 == 0)
			ans += "\n\t\t";
		if(i == len a -1)
			ans += sys->sprint("%2x", int a[i]);
		else
			ans += sys->sprint("%2x ", int a[i]);
	}

	return ans;
}

bbastr(a: array of array of byte) : string
{
	info := "";

	for(i := 0; i < len a; i++)
		info += bastr(a[i]);
	
	return info;
}

lbastr(a: list of array of byte) : string
{
	info := "";

	l := a;
	while(l != nil) {
		info += bastr(hd l) + "\n\t\t";
		l = tl l;
	}

	return info;
}

# need to fix (string a == string b)
bytes_cmp(a, b: array of byte): int
{
	if(len a != len b)
		return -1;

	n := len a;
	for(i := 0; i < n; i++) {
		if(a[i] != b[i])
			return -1;
	}

	return 0;
}

putn(a: array of byte, i, value, n: int): int
{
	j := n;
	while(j--) {   
		a[i+j] = byte value;
		value >>= 8;
	}
	return i+n;
}

INVALID_SUITE : con "invalid suite list";
ILLEGAL_SUITE : con "illegal suite list";

cksuites(suites : array of byte) : string
{
	m := len suites;
	if (m == 0 || (m&1))
		return INVALID_SUITE;
	n := len SSL3_Suites;
	ssl3s := array [2] of byte;
	for (j := 0; j < m; j += 2) {
		for( i := 0; i < n; i++) {
			ssl3s = SSL3_Suites[i];
			if(suites[j] == ssl3s[0] && suites[j+1] == ssl3s[1])
				break;
		}
		if (i == n)
			return ILLEGAL_SUITE;
	}
	return nil;
}
