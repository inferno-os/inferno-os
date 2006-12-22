#
# X.509 v3 by ITU-T Recommendation (11/93) & PKCS7 & PKCS10
#

X509: module {

	PATH: con "/dis/lib/crypt/x509.dis";

	init: fn(): string;

	## x509 (id_at) and x509 extention v3 (id_ce) Object Identifiers

	objIdTab			: array of ASN1->Oid;

	id_at,
	id_at_commonName,
	id_at_countryName,
	id_at_localityName,
	id_at_stateOrProvinceName,
	id_at_organizationName,
	id_at_organizationalUnitName,
	id_at_userPassword,
	id_at_userCertificate,
	id_at_cAcertificate,
	id_at_authorityRevocationList,
	id_at_certificateRevocationList,
	id_at_crossCertificatePair,
	id_at_supportedAlgorithms,
	id_at_deltaRevocationList,
	id_ce,
	id_ce_subjectDirectoryAttributes,
	id_ce_subjectKeyIdentifier,
	id_ce_keyUsage,
	id_ce_privateKeyUsage,
	id_ce_subjectAltName,
	id_ce_issuerAltName,
	id_ce_basicConstraints,
	id_ce_cRLNumber,
	id_ce_reasonCode,
	id_ce_instructionCode,
	id_ce_invalidityDate,
	id_ce_deltaCRLIndicator,
	id_ce_issuingDistributionPoint,
	id_ce_certificateIssuer,
	id_ce_nameConstraints,
	id_ce_cRLDistributionPoint,
	id_ce_certificatePolicies,
	id_ce_policyMapping,
	id_ce_authorityKeyIdentifier,
	id_ce_policyConstraints,
	id_mr,
	id_mr_certificateExactMatch,
 	id_mr_certificateMatch,
 	id_mr_certificatePairExactMatch,
 	id_mr_certificatePairMatch,
 	id_mr_certificateListExactMatch,
 	id_mr_certificateListMatch,
 	id_mr_algorithmidentifierMatch	: con iota;

	## Signed (as Public Key, CRL, Attribute Certificates and CertificationRequest)

	Signed: adt {
		tobe_signed		: array of byte;
  		alg			: ref AlgIdentifier;
  		signature		: array of byte; # BIT STRING, DER encoding
		
		decode: fn(a: array of byte): (string, ref Signed);
		encode: fn(s: self ref Signed): (string, array of byte);
		sign: fn(s: self ref Signed, sk: ref PrivateKey, hash: int): (string, array of byte);
		verify: fn(s: self ref Signed, pk: ref PublicKey, hash: int): int;
		tostring: fn(s: self ref Signed): string;
	};

	## Certificate Path

	verify_certchain: fn(cs: list of array of byte): (int, string);
	verify_certpath: fn(cp: list of (ref Signed, ref Certificate)): (int, string);

	## TBS (Public Key) Certificate

	Certificate: adt {
  		version			: int; # v1(0; default) or v2(1) or v3(2)
  		serial_number		: ref Keyring->IPint;
  		sig			: ref AlgIdentifier;
  		issuer			: ref Name;
  		validity		: ref Validity;
  		subject			: ref Name;
  		subject_pkinfo		: ref SubjectPKInfo;
					# OPTIONAL for v2 and v3; must be in order
  		issuer_uid		: array of byte; # v2
  		subject_uid		: array of byte; # v2 or v3
  		exts			: list of ref Extension; # v3

		decode: fn(a: array of byte): (string, ref Certificate);
		encode: fn(c: self ref Certificate): (string, array of byte);
		tostring: fn(c: self ref Certificate): string;
		is_expired: fn(c: self ref Certificate, date: int): int;
	};

	AlgIdentifier: adt {
		oid			: ref ASN1->Oid;
		parameter		: array of byte;

		tostring: fn(a: self ref AlgIdentifier): string;
	};

	Name: adt {
		rd_names		: list of ref RDName;

		equal: fn(a: self ref Name, b: ref Name): int;
		tostring: fn(n: self ref Name): string;
	};

	RDName: adt {
		avas			: list of ref AVA;

		equal: fn(a: self ref RDName, b: ref RDName): int;
		tostring: fn(r: self ref RDName): string;
	};

	AVA: adt {
		oid			: ref ASN1->Oid;
		value			: string;
		
		equal: fn(a: self ref AVA, b: ref AVA): int;
		tostring: fn(a: self ref AVA): string;
	};

	Validity: adt {
  		not_before		: int;
  		not_after		: int;

		tostring: fn(v: self ref Validity, format: string): string;
	};

	SubjectPKInfo: adt {
  		alg_id			: ref AlgIdentifier;
  		subject_pk		: array of byte; # BIT STRING

		getPublicKey: fn(c: self ref SubjectPKInfo): (string, int, ref PublicKey);
		tostring: fn(c: self ref SubjectPKInfo): string;
	};

	Extension: adt{
  		oid			: ref ASN1->Oid;
  		critical		: int; # default false 
  		value			: array of byte;

		tostring: fn(e: self ref Extension): string;
	};

	PublicKey: adt {
		pick {
		RSA =>
			pk		: ref PKCS->RSAKey;
		DSS =>
			pk		: ref PKCS->DSSPublicKey;
		DH =>
			pk		: ref PKCS->DHPublicKey;
		}
	};

	PrivateKey: adt {
		pick {
		RSA =>
			sk		: ref PKCS->RSAKey;
		DSS =>
			sk		: ref PKCS->DSSPrivateKey;
		DH =>
			sk		: ref PKCS->DHPrivateKey;
		}
	};

	## Certificate Revocation List

	CRL: adt {
		version			: int; # OPTIONAL; v2
		sig			: ref AlgIdentifier;
		issuer			: ref Name; 
		this_update		: int;
		next_update		: int; # OPTIONAL
		revoked_certs		: list of ref RevokedCert; # OPTIONAL
		exts			: list of ref Extension; # OPTIONAL

		decode: fn(a: array of byte): (string, ref CRL);
		encode: fn(c: self ref CRL): (string, array of byte);
		tostring: fn(c: self ref CRL): string;
		is_revoked: fn(c: self ref CRL, sn: ref Keyring->IPint): int;
	};

	RevokedCert: adt {
		user_cert		: ref Keyring->IPint; # serial_number
		revoc_date		: int; # OPTIONAL
		exts			: list of ref Extension; # OPTIONAL; CRL entry extensions

		tostring: fn(rc: self ref RevokedCert): string;	
	};

	## Certificate Extensions

	# get critical extensions	
	cr_exts: fn(es: list of ref Extension): list of ref Extension;

	# get non-critical extensions
	noncr_exts: fn(es: list of ref Extension): list of ref Extension;

	# decode a list of extensions
	parse_exts: fn(es: list of ref Extension): (string, list of ref ExtClass);

	# extension classes
	ExtClass: adt {
		pick {
		AuthorityKeyIdentifier =>
			id		: array of byte; # OCTET STRING
			issuer		: ref GeneralName;
			serial_number	: ref Keyring->IPint;
		SubjectKeyIdentifier =>
			id		: array of byte; # OCTET STRING
		BasicConstraints =>	
			depth		: int; # certificate path constraints
		KeyUsage =>
			usage		: int;
		PrivateKeyUsage =>
			period		: ref Validity;
		PolicyMapping =>	# (issuer, subject) domain policy pairs
			pairs		: list of (ref ASN1->Oid, ref ASN1->Oid);
		CertificatePolicies =>
			policies	: list of ref PolicyInfo;
		IssuerAltName =>
			alias		: list of ref GeneralName;
		SubjectAltName =>
			alias		: list of ref GeneralName;
		NameConstraints =>
			permitted	: list of ref GSubtree;
			excluded	: list of ref GSubtree;
		PolicyConstraints =>
			require		: int;
			inhibit		: int;
		CRLNumber =>
			curr		: int;
		ReasonCode =>
			code		: int;
		InstructionCode =>
			oid		: ref ASN1->Oid; # hold instruction code field
		InvalidityDate =>
			date		: int;
		CRLDistributionPoint =>
			ps		: list of ref DistrPoint;
		IssuingDistributionPoint =>
			name		: ref DistrPointName;
			only_usercerts	: int; # DEFAULT FALSE
			only_cacerts	: int; # DEFAULT FALSE
			only_reasons	: int;
			indirect_crl	: int; # DEFAULT FALSE	 	 
		CertificateIssuer =>
			names		: list of ref GeneralName;
		DeltaCRLIndicator =>
			number		: ref Keyring->IPint;
		SubjectDirectoryAttributes =>
			attrs		: list of ref Attribute;
		UnknownType =>
			ext		: ref Extension;
		}

		decode: fn(ext: ref Extension): (string, ref ExtClass);
		encode: fn(et: self ref ExtClass, critical: int): ref Extension;
		tostring: fn(et: self ref ExtClass): string;
	};

	# key usage
	KeyUsage_DigitalSignature, KeyUsage_NonRepudiation, KeyUsage_KeyEncipherment,
	KeyUsage_DataEncipherment, KeyUsage_KeyAgreement, KeyUsage_KeyCertSign, 
	KeyUsage_CRLSign, KeyUsage_EncipherOnly, KeyUsage_DecipherOnly : con iota << 1;

	# CRL reason
	Reason_Unspecified, Reason_KeyCompromise, Reason_CACompromise, 
	Reason_AffiliationChanged, Reason_Superseded, Reason_CessationOfOperation, 
	Reason_CertificateHold, Reason_RemoveFromCRL : con iota << 1;

	# General Name
	GeneralName: adt {
		pick {
		otherName or 		# [0]
		rfc822Name or 		# [1]
		dNSName or 		# [2]
		x400Address or 		# [3]
		uniformResourceIdentifier => # [6]
			str		: string;
		iPAddress =>		# [7]
			ip		: array of byte;
		registeredID =>		# [8]
			oid		: ref ASN1->Oid;
		ediPartyName =>		# [5]
			nameAssigner	: ref Name; # [0]
			partyName	: ref Name; # [1]
		directoryName =>	# [4]
			dir		: ref Name;
		}

		tostring: fn(g: self ref GeneralName): string;
	};

	# security policies
	PolicyInfo: adt {
		oid			: ref ASN1->Oid;
		qualifiers		: list of ref PolicyQualifier;

		tostring: fn(pi: self ref PolicyInfo): string;
	};

	PolicyQualifier: adt {
		oid			: ref ASN1->Oid;
		value			: array of byte; # OCTET STRING; OPTIONAL

		tostring: fn(pq: self ref PolicyQualifier): string;
	};

	GSubtree: adt {
		base			: ref GeneralName;
		min			: int;
		max			: int;
	
		tostring: fn(gs: self ref GSubtree): string;
	};
	
	# crl distribution point
	# with known reason code
	# Unused [0], KeyCompromise [1], CACompromise [2], AffilationChanged [3],
	# Superseded [4], CessationOfOperation [5], CertificateHold [6] 
	DistrPoint: adt{
		name			: ref DistrPointName;
 		reasons			: int;
		issuer			: list of ref GeneralName;

		tostring: fn(dp: self ref DistrPoint): string;
	};
	
	DistrPointName: adt {
		full_name		: list of ref GeneralName;
		rdname			: list of ref RDName;
	};

	Attribute: adt {
		id			: ASN1->Oid;
		value			: array of byte;
	};
};

#X509Attribute: module {
#
#	## Attribute Certificate
#
#	AttrCert: adt {
#		version			: int; # default v1
#		base_certid		: ref IssuerSerial; # [0]
#		subject_name		: list of ref GeneralName; # [1]
#		issuer			: list of ref GeneralName;
#		serial_number		: ref IPint;
#		validity		: ref Validity;
#		attrs			: list of ref Attribute;
#		issuer_uid		: array of byte; # OPTIONAL
#		exts			: list of ref Extension; # OPTIONAL			
#	};
#
#	IssuerSerial: adt {
#		issuer			: list of ref GeneralName;
#		serial			: ref IPint;
#		issuer_uid		: array of byte; # OPTIONAL
#	};
#};
