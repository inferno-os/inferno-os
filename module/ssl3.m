#
# ssl 3.0 protocol
#

SSL3: module {

	PATH: con "/dis/lib/crypt/ssl3.dis";

	init: fn(): string;

	# SSL cipher suites

	NULL_WITH_NULL_NULL,
	RSA_WITH_NULL_MD5,
	RSA_WITH_NULL_SHA,
	RSA_EXPORT_WITH_RC4_40_MD5,
	RSA_WITH_RC4_128_MD5,
	RSA_WITH_RC4_128_SHA,
	RSA_EXPORT_WITH_RC2_CBC_40_MD5,
	RSA_WITH_IDEA_CBC_SHA,
	RSA_EXPORT_WITH_DES40_CBC_SHA,
	RSA_WITH_DES_CBC_SHA,
	RSA_WITH_3DES_EDE_CBC_SHA,
	DH_DSS_EXPORT_WITH_DES40_CBC_SHA,
	DH_DSS_WITH_DES_CBC_SHA,
	DH_DSS_WITH_3DES_EDE_CBC_SHA,
	DH_RSA_EXPORT_WITH_DES40_CBC_SHA,
	DH_RSA_WITH_DES_CBC_SHA,
	DH_RSA_WITH_3DES_EDE_CBC_SHA,
	DHE_DSS_EXPORT_WITH_DES40_CBC_SHA,
	DHE_DSS_WITH_DES_CBC_SHA,
	DHE_DSS_WITH_3DES_EDE_CBC_SHA,
	DHE_RSA_EXPORT_WITH_DES40_CBC_SHA,
	DHE_RSA_WITH_DES_CBC_SHA,
	DHE_RSA_WITH_3DES_EDE_CBC_SHA,
	DH_anon_EXPORT_WITH_RC4_40_MD5,
	DH_anon_WITH_RC4_128_MD5,
	DH_anon_EXPORT_WITH_DES40_CBC_SHA,
	DH_anon_WITH_DES_CBC_SHA,
	DH_anon_WITH_3DES_EDE_CBC_SHA,
	FORTEZZA_KEA_WITH_NULL_SHA,
	FORTEZZA_KEA_WITH_FORTEZZA_CBC_SHA,
	FORTEZZA_KEA_WITH_RC4_128_SHA 		: con iota;

	Authinfo: adt {
		suites: array of byte; # [2] x
		comprs: array of byte; # [1] x

		sk: ref PrivateKey; # for user certs 
		root_type: int; # root type of certs
		certs: list of array of byte; # x509 cert chain

		types: array of byte; # acceptable cert types
		dns: list of array of byte; # acceptable cert authorities
	};

	PrivateKey: adt {
		pick {
		RSA =>
			sk			: ref PKCS->RSAKey;
		DSS =>
			sk			: ref PKCS->DSSPrivateKey;
		DH =>
			sk			: ref PKCS->DHPrivateKey;
		}
	};

	Record: adt {
		content_type			: int;
		version			 	: array of byte; # [2]		
		data				: array of byte;
	};

	# key exchange algorithms

	KeyExAlg: adt {
		pick {
		NULL =>
		DH =>
			params			: ref PKCS->DHParams;
			sk			: ref PKCS->DHPrivateKey;			
			peer_params		: ref PKCS->DHParams;
			peer_pk			: ref PKCS->DHPublicKey;
			exch_pk			: ref PKCS->DHPublicKey;
		RSA =>
			sk	 		: ref PKCS->RSAKey; # for RSA key exchange
			export_key 		: ref PKCS->RSAKey; # server RSA temp key
			peer_pk			: ref PKCS->RSAKey; # temp key from server
		FORTEZZA_KEA =>	
			# not supported yet
		}
	};

	SigAlg: adt {
		pick {
		anon =>
		RSA =>
			sk	 		: ref PKCS->RSAKey; # for sign
			peer_pk			: ref PKCS->RSAKey; # for verify from peer cert
		DSS =>
			sk	 		: ref PKCS->DSSPrivateKey; # for sign
			peer_pk			: ref PKCS->DSSPublicKey; # for verify from peer cert
		FORTEZZA_KEA =>	# not supported yet
		}
	};

	CipherSpec: adt {
		is_exportable			: int;
	
		bulk_cipher_algorithm		: int;
		cipher_type			: int;
		key_material			: int;
		IV_size				: int;

		mac_algorithm			: int;
		hash_size			: int;		
	};

	# record format queue

	RecordQueue: adt {
		macState			: ref MacState;
		cipherState			: ref CipherState;

		length				: int;
		sequence_numbers		: array of int;
	
		data				: list of ref Record;
		fragment			: int;
		b, e				: int;

		new: fn(): ref RecordQueue;
		read: fn(q: self ref RecordQueue, ctx: ref Context, fd: ref Sys->FD): string;
		write: fn(q: self ref RecordQueue, ctx: ref Context, fd: ref Sys->FD, r: ref Record): string;
		calcmac: fn(q: self ref RecordQueue, ctx: ref Context, cntype: int, a: array of byte, ofs, n: int) : array of byte;
	};

	MacState: adt {
		hash_size			: int;
		pick {
		null =>
		md5 =>
			ds			: array of ref Keyring->DigestState;
		sha =>
			ds			: array of ref Keyring->DigestState;
		}
	};

	CipherState: adt {
		block_size			: int;
		pick {
		null =>
		rc4 =>
			es			: ref Keyring->RC4state;
		descbc =>
			es			: ref Keyring->DESstate;
		ideacbc =>
			es			: ref Keyring->IDEAstate;
		}
	};

	# context for processing both v2 and v3 protocols.

	Context: adt {
		c				: ref Sys->Connection;
		session				: ref SSLsession->Session;

		sel_keyx			: ref KeyExAlg;
		sel_sign			: ref SigAlg;
		sel_ciph			: ref CipherSpec;
		sel_cmpr			: int;

		local_info			: ref Authinfo;

		client_random			: array of byte; # [32]
		server_random			: array of byte; # [32]
		
		sha_state			: ref Keyring->DigestState;
		md5_state			: ref Keyring->DigestState;

		cw_mac				: array of byte;
		sw_mac				: array of byte;
		cw_key				: array of byte;
		sw_key				: array of byte;
		cw_IV				: array of byte;
		sw_IV				: array of byte;

		in_queue			: ref RecordQueue;
		out_queue			: ref RecordQueue;

		status				: int;
		state				: int;


		new: fn(): ref Context;
		client: fn(ctx: self ref Context, fd: ref Sys->FD, peer: string, ver: int, info: ref Authinfo): (string, int);
		server: fn(ctx: self ref Context, fd: ref Sys->FD, info: ref Authinfo, client_auth: int): string;
		use_devssl: fn(ctx: self ref Context);
		set_version: fn(ctx: self ref Context, vers: int): string;
		connect: fn(ctx: self ref Context, fd: ref Sys->FD): string;
		read: fn(ctx: self ref Context, a: array of byte, n: int): int;
		write: fn(ctx: self ref Context, a: array of byte, n: int): int;
	};
};
