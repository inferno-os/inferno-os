#
# TLS 1.2/1.3 protocol
#

TLS: module {

	PATH: con "/dis/lib/crypt/tls.dis";

	init: fn(): string;

	# TLS versions
	TLS12: con 16r0303;
	TLS13: con 16r0304;

	# Cipher suite IDs
	TLS_RSA_WITH_AES_128_GCM_SHA256:		con 16r009C;
	TLS_RSA_WITH_AES_256_GCM_SHA384:		con 16r009D;
	TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256:		con 16rC02F;
	TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384:		con 16rC030;
	TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256:	con 16rC02B;
	TLS_AES_128_GCM_SHA256:			con 16r1301;
	TLS_AES_256_GCM_SHA384:			con 16r1302;
	TLS_CHACHA20_POLY1305_SHA256:			con 16r1303;

	# Named groups
	X25519:		con 16r001D;
	SECP256R1:	con 16r0017;

	# Signature algorithms
	RSA_PKCS1_SHA256:		con 16r0401;
	RSA_PKCS1_SHA384:		con 16r0501;
	RSA_PKCS1_SHA512:		con 16r0601;
	RSA_PSS_RSAE_SHA256:		con 16r0804;
	ECDSA_SECP256R1_SHA256:		con 16r0403;

	# Configuration
	Config: adt {
		suites:		list of int;	# cipher suite IDs (preference order)
		minver:		int;		# minimum TLS version
		maxver:		int;		# maximum TLS version
		servername:	string;		# SNI hostname
		insecure:	int;		# skip cert verification
	};

	# Connection (read/write after handshake)
	Conn: adt {
		version:	int;		# negotiated TLS version
		suite:		int;		# negotiated cipher suite
		servername:	string;		# peer name

		read:	fn(c: self ref Conn, buf: array of byte, n: int): int;
		write:	fn(c: self ref Conn, buf: array of byte, n: int): int;
		close:	fn(c: self ref Conn): string;
	};

	# Primary API
	client:		fn(fd: ref Sys->FD, config: ref Config): (ref Conn, string);
	defaultconfig:	fn(): ref Config;
};
