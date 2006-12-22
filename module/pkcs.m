#
# Public-Key Cryptography Standards (PKCS)
#
#	Ref: 	http://www.rsa.com
#		RFC1423
#

PKCS: module {

	PATH: con "/dis/lib/crypt/pkcs.dis";

	init: fn(): string;

	# PKCS Object Identifiers

	objIdTab			: array of ASN1->Oid;

	id_pkcs,
	id_pkcs_1,
	id_pkcs_rsaEncryption,
	id_pkcs_md2WithRSAEncryption,
	id_pkcs_md4WithRSAEncryption,
	id_pkcs_md5WithRSAEncryption,
	id_pkcs_3,
	id_pkcs_dhKeyAgreement,
	id_pkcs_5,
	id_pkcs_pbeWithMD2AndDESCBC,
	id_pkcs_pbeWithMD5AndDESCBC,
	id_pkcs_7,
	id_pkcs_data,
	id_pkcs_singnedData,
	id_pkcs_envelopedData,
	id_pkcs_signedAndEnvelopedData,
	id_pkcs_digestData,
	id_pkcs_encryptedData,
	id_pkcs_9,
	id_pkcs_emailAddress,
	id_pkcs_unstructuredName,
	id_pkcs_contentType,
	id_pkcs_messageDigest,
	id_pkcs_signingTime,
	id_pkcs_countersignature,
	id_pkcs_challengePassword,
	id_pkcs_unstructuredAddress,
	id_pkcs_extCertAttrs,
	id_algorithm_shaWithDSS		: con iota;

	# PKCS1

	RSAParams: adt {
		modulus			: ref Keyring->IPint;
		exponent		: ref Keyring->IPint;
	};

	RSAKey: adt {
		modulus			: ref Keyring->IPint;
		modlen			: int;
		exponent		: ref Keyring->IPint;

		bits: fn(k: self ref RSAKey): int;
		#tostring: fn(k: self ref RSAKey): string;
	};

	MD2_WithRSAEncryption		: con 0;
	MD5_WithRSAEncryption		: con 1;	

	rsa_encrypt: fn(data: array of byte, key: ref RSAKey, blocktype: int): (string, array of byte); 
	rsa_decrypt: fn(data: array of byte, key: ref RSAKey, public: int): (string, array of byte); 
	rsa_sign: fn(data: array of byte, sk: ref RSAKey, algid: int): (string, array of byte);
	rsa_verify: fn(data, signature: array of byte, pk: ref RSAKey, algid: int): int;
	decode_rsapubkey: fn(a: array of byte): (string, ref RSAKey);

	# Note:
	#	DSS included here is only for completeness.

	DSSParams: adt {
		p			: ref Keyring->IPint;
		q			: ref Keyring->IPint;
		alpha			: ref Keyring->IPint;
	};

	DSSPublicKey: adt {
		params			: ref DSSParams;
		y			: ref Keyring->IPint;
	};

	DSSPrivateKey: adt {
		params			: ref DSSParams;
		x			: ref Keyring->IPint;
	};

	generateDSSKeyPair: fn(strength: int): (ref DSSPublicKey, ref DSSPrivateKey);
	dss_sign: fn(a: array of byte, sk: ref DSSPrivateKey): (string, array of byte);
	dss_verify: fn(a, signa: array of byte, pk: ref DSSPublicKey): int;
	decode_dsspubkey: fn(a: array of byte): (string, ref DSSPublicKey);

	# PKCS3

	DHParams: adt {
		prime			: ref Keyring->IPint; # prime (p)
		base			: ref Keyring->IPint; # generator (alpha)
		privateValueLength	: int;
	};

	DHPublicKey: adt {
		param			: ref DHParams;
		pk			: ref Keyring->IPint;
	};

	DHPrivateKey: adt {
		param			: ref DHParams;
		pk			: ref Keyring->IPint;
		sk			: ref Keyring->IPint;
	};

	generateDHParams: fn(primelen: int): ref DHParams; 
	setupDHAgreement: fn(dh: ref DHParams): (ref DHPrivateKey, ref DHPublicKey);
	computeDHAgreedKey: fn(dh: ref DHParams, mysk, upk: ref Keyring->IPint): array of byte;
	decode_dhpubkey: fn(a: array of byte): (string, ref DHPublicKey);

	# PKCS5

	PBEParams: adt {
		salt			: array of byte; # [8]
		iterationCount		: int;
	};	

	PBE_MD2_DESCBC			: con 0;
	PBE_MD5_DESCBC			: con 1;

	generateDESKey: fn(pw: array of byte, param: ref PBEParams, alg: int)
		: (ref Keyring->DESstate, array of byte, array of byte);
	pbe_encrypt: fn(state: ref Keyring->DESstate, b: array of byte): array of byte;
	pbe_decrypt: fn(state: ref Keyring->DESstate, eb: array of byte): array of byte;

	# PKCS6

	ExtCertInfo: adt {
  		version 		: int;
  		cert 			: array of byte; # der encoded x509 Certificate
  		attrs 			: list of array of byte; # attribute as array of byte 
	};

	# PKCS7
	#	See module X509

	# PKCS8

	PrivateKeyInfo: adt {		# as SEQUENCE
		version			: int; # should be 0
		privateKeyAlgorithm	: ref AlgIdentifier;
		privateKey		: array of byte; # octet string
		attrs			: list of array of byte; # [0] IMPLICIT Attributes OPTIONAL 

		encode: fn(p: self ref PrivateKeyInfo): (string, array of byte);
		decode: fn(a: array of byte): (string, ref PrivateKeyInfo);		
	};

	EncryptedPrivateKeyInfo: adt {	# as SEQUENCE
  		encryptionAlgorithm 	: ref AlgIdentifier;
  		encryptedData 		: array of byte; # octet string

		encode: fn(ep: self ref EncryptedPrivateKeyInfo): (string, array of byte);
		decode: fn(a: array of byte): (string, ref EncryptedPrivateKeyInfo);
	};

	AlgIdentifier: adt {		# TODO: move this to ASN1
		oid			: ref ASN1->Oid;
		parameter		: array of byte;
	};

	# PKCS10
	#	See module X509
};


