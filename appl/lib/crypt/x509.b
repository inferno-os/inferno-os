implement X509;

include "sys.m";
	sys				: Sys;

include "asn1.m";
	asn1				: ASN1;
	Elem, Tag, Value, Oid,
	Universal, Context,
	BOOLEAN,
	INTEGER,
	BIT_STRING,
	OCTET_STRING,
	OBJECT_ID,
	SEQUENCE,
	UTCTime,
	IA5String,
	GeneralString,
	GeneralizedTime			: import asn1;

include "keyring.m";
	keyring				: Keyring;
	MD4, MD5, SHA1, IPint, DESstate	: import keyring;

include "security.m";
	random				: Random;

include "daytime.m";
	daytime				: Daytime;

include "pkcs.m";
	pkcs				: PKCS;

include "x509.m";

X509_DEBUG 				: con 0;
logfd 					: ref Sys->FD;

TAG_MASK 				: con 16r1F;
CONSTR_MASK 				: con 16r20;
CLASS_MASK 				: con 16rC0;

# object identifiers

objIdTab = array [] of {
	id_at =>			Oid(array [] of {2,5,4}),
	id_at_commonName => 		Oid(array [] of {2,5,4,3}),
	id_at_countryName => 		Oid(array [] of {2,5,4,6}),
	id_at_localityName => 		Oid(array [] of {2,5,4,7}), 
	id_at_stateOrProvinceName => 	Oid(array [] of {2,5,4,8}),
	id_at_organizationName =>	Oid(array [] of {2,5,4,10}),
	id_at_organizationalUnitName => Oid(array [] of {2,5,4,11}), 
	id_at_userPassword =>		Oid(array [] of {2,5,4,35}),
	id_at_userCertificate =>	Oid(array [] of {2,5,4,36}),
	id_at_cAcertificate =>		Oid(array [] of {2,5,4,37}),
	id_at_authorityRevocationList =>
					Oid(array [] of {2,5,4,38}),
	id_at_certificateRevocationList =>
					Oid(array [] of {2,5,4,39}),
	id_at_crossCertificatePair =>	Oid(array [] of {2,5,4,40}),
# 	id_at_crossCertificatePair => 	Oid(array [] of {2,5,4,58}),
	id_at_supportedAlgorithms =>	Oid(array [] of {2,5,4,52}),
	id_at_deltaRevocationList =>	Oid(array [] of {2,5,4,53}),

	id_ce =>			Oid(array [] of {2,5,29}),
	id_ce_subjectDirectoryAttributes =>
					Oid(array [] of {2,5,29,9}),
	id_ce_subjectKeyIdentifier =>	Oid(array [] of {2,5,29,14}),
	id_ce_keyUsage =>		Oid(array [] of {2,5,29,15}),
	id_ce_privateKeyUsage =>	Oid(array [] of {2,5,29,16}),
	id_ce_subjectAltName =>		Oid(array [] of {2,5,29,17}),
	id_ce_issuerAltName =>		Oid(array [] of {2,5,29,18}),
	id_ce_basicConstraints =>	Oid(array [] of {2,5,29,19}),
	id_ce_cRLNumber =>		Oid(array [] of {2,5,29,20}),
	id_ce_reasonCode =>		Oid(array [] of {2,5,29,21}),
	id_ce_instructionCode =>	Oid(array [] of {2,5,29,23}),
	id_ce_invalidityDate =>		Oid(array [] of {2,5,29,24}),
	id_ce_deltaCRLIndicator =>	Oid(array [] of {2,5,29,27}),
	id_ce_issuingDistributionPoint =>
					Oid(array [] of {2,5,29,28}),
	id_ce_certificateIssuer =>	Oid(array [] of {2,5,29,29}),
	id_ce_nameConstraints =>	Oid(array [] of {2,5,29,30}),
	id_ce_cRLDistributionPoint =>	Oid(array [] of {2,5,29,31}),
	id_ce_certificatePolicies =>	Oid(array [] of {2,5,29,32}),
	id_ce_policyMapping =>		Oid(array [] of {2,5,29,33}),
	id_ce_authorityKeyIdentifier =>
					Oid(array [] of {2,5,29,35}),
	id_ce_policyConstraints	=>	Oid(array [] of {2,5,29,36}),

#	id_mr =>			Oid(array [] of {2,5,?}),
# 	id_mr_certificateMatch =>	Oid(array [] of {2,5,?,35}),
# 	id_mr_certificatePairExactMatch	=>
#					Oid(array [] of {2,5,?,36}),
# 	id_mr_certificatePairMatch =>	Oid(array [] of {2,5,?,37}),
# 	id_mr_certificateListExactMatch	=>
#					Oid(array [] of {2,5,?,38}),
# 	id_mr_certificateListMatch =>	Oid(array [] of {2,5,?,39}),
# 	id_mr_algorithmidentifierMatch =>
#					Oid(array [] of {2,5,?,40})
};

# [public]

init(): string
{
	sys = load Sys Sys->PATH;

	if(X509_DEBUG)
		logfd = sys->fildes(1);

	keyring = load Keyring Keyring->PATH;
	if(keyring == nil)
		return sys->sprint("load %s: %r", Keyring->PATH);

	random = load Random Random->PATH;
	if(random == nil)
		return sys->sprint("load %s: %r", Random->PATH);

	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		return sys->sprint("load %s: %r", Daytime->PATH);

	asn1 = load ASN1 ASN1->PATH;
	if(asn1 == nil)
		return sys->sprint("load %s: %r", ASN1->PATH);
	asn1->init();

	pkcs = load PKCS PKCS->PATH;
	if(pkcs == nil)
		return sys->sprint("load %s: %r", PKCS->PATH);
	if((e := pkcs->init()) != nil)
		return sys->sprint("pkcs: %s", e);

	return nil;
}

# [private]

log(s: string)
{
	if(X509_DEBUG)
		sys->fprint(logfd, "x509: %s\n", s);
}

## SIGNED { ToBeSigned } ::= SEQUENCE {
##	toBeSigned	ToBeSigned,
##	COMPONENTS OF	SIGNATURE { ToBeSigned }}
##
## SIGNATURE {OfSignature} ::= SEQUENCE {
##	algorithmIdentifier	AlgorithmIdentifier,
##	encrypted	ENCRYPTED { HASHED { OfSignature }}}
##
## ENCRYPTED { ToBeEnciphered }	::= BIT STRING ( CONSTRAINED BY {
##	-- must be the result of applying an encipherment procedure --
##	-- to the BER-encoded octets of a value of -- ToBeEnciphered } )

# [public]

Signed.decode(a: array of byte): (string, ref Signed)
{
parse:
	for(;;) {
		# interpret the enclosing structure
		(ok, tag, i, n) := der_dec1(a, 0, len a);
		if(!ok || n != len a || !tag.constr || 
			tag.class != Universal || tag.num != SEQUENCE)
			break parse;
		s := ref Signed;
		# SIGNED sequence
		istart := i;
		(ok, tag, i, n) = der_dec1(a, i, len a);
		if(!ok || n == len a)
			break parse;
		s.tobe_signed = a[istart:n];
		# AlgIdentifier
		istart = n;
		(ok, tag, i, n) = der_dec1(a, n, len a);
		if(!ok || n == len a 
			|| !tag.constr || tag.class != Universal || tag.num != SEQUENCE) {
			if(X509_DEBUG)
				log("signed: der data: " + 
				sys->sprint("ok=%d, n=%d, constr=%d, class=%d, num=%d", 
				ok, n, tag.constr, tag.class, tag.num));
			break parse;
		}
		(ok, s.alg) = decode_algid(a[istart:n]);
		if(!ok) {
			if(X509_DEBUG)
				log("signed: alg identifier: syntax error");
			break;		
		}
		# signature
		(ok, tag, i, n) = der_dec1(a, n, len a);
		if(!ok || n != len a
			|| tag.constr || tag.class != Universal || tag.num != BIT_STRING) {
			if(X509_DEBUG)
				log("signed: signature: " + 
				sys->sprint("ok=%d, n=%d, constr=%d, class=%d, num=%d", 
				ok, n, tag.constr, tag.class, tag.num));
			break parse;
		}
		s.signature = a[i:n];
		# to the end of no error been found
		return ("", s);
	}
	return ("signed: syntax error", nil);
}

# [public]
# der encoding of signed data

Signed.encode(s: self ref Signed): (string, array of byte)
{
	(err, e_dat) := asn1->decode(s.tobe_signed); # why?
	if(err != "")
		return (err, nil);
	e_alg := pack_alg(s.alg);
	e_sig := ref Elem(
			Tag(Universal, BIT_STRING, 0), 
			ref Value.BitString(0,s.signature) # DER encode of BIT STRING
		);
	all := ref Elem(
			Tag(Universal, SEQUENCE, 1), 
			ref Value.Seq(e_dat::e_alg::e_sig::nil)
		);
	return asn1->encode(all);
}

# [public]

Signed.sign(s: self ref Signed, sk: ref PrivateKey, hash: int): (string, array of byte)
{
	# we require tobe_signed has 0 bits of padding	
	if(int s.tobe_signed[0] != 0)
		return ("syntax error", nil);
	pick key := sk {
	RSA =>
		(err, signature) := pkcs->rsa_sign(s.tobe_signed, key.sk, hash);
		s.signature = signature;
		# TODO: add AlgIdentifier based on public key and hash
		return (err, signature);
	DSS =>
		# TODO: hash s.tobe_signed for signing
		(err, signature) := pkcs->dss_sign(s.tobe_signed, key.sk);
		s.signature = signature;
		return (err, signature);
	DH =>
		return ("cannot sign using DH algorithm", nil);
	}
	return ("sign: failed", nil);
}

# [public]
# hash algorithm should be MD2, MD4, MD5 or SHA

Signed.verify(s: self ref Signed, pk: ref PublicKey, hash: int): int
{
	ok := 0;

	pick key := pk {
	RSA =>
		ok = pkcs->rsa_verify(s.tobe_signed, s.signature, key.pk, hash);
	DSS =>	
		# TODO: hash s.tobe_signed for verifying
		ok = pkcs->dss_verify(s.tobe_signed, s.signature, key.pk);
	DH =>
		# simply failure
	}

	return ok;
}

# [public]

Signed.tostring(s: self ref Signed): string
{
	str := "Signed";

	str += "\nToBeSigned: " + bastr(s.tobe_signed);
	str += "\nAlgorithm: " + s.alg.tostring();
	str += "\nSignature: " + bastr(s.signature);

	return str + "\n";
}

# DER
# a) the definite form of length encoding shall be used, encoded in the minimum number of 
#    octets;
# b) for string types, the constructed form of encoding shall not be used;
# c) if the value of a type is its default value, it shall be absent;
# d) the components of a Set type shall be encoded in ascending order of their tag value;
# e) the components of a Set-of type shall be encoded in ascending order of their octet value;
# f) if the value of a Boolean type is true, the encoding shall have its contents octet 
#    set to "FF"16;
# g) each unused bits in the final octet of the encoding of a Bit String value, if there are 
#    any, shall be set to zero;
# h) the encoding of a Real type shall be such that bases 8, 10, and 16 shall not be used, 
#    and the binary scaling factor shall be zero.

# [private]
# decode ASN1 one record at a time and return (err, tag, start of data, 
# end of data) for indefinite length, the end of data is same as 'n'

der_dec1(a: array of byte, i, n: int): (int, Tag, int, int)
{
	length: int;
	tag: Tag;
	ok := 1;
	(ok, i, tag) = der_dectag(a, i, n);
	if(ok) {
		(ok, i, length) = der_declen(a, i, n);
		if(ok) {
			if(length == -1) {
				if(!tag.constr)
					ok = 0;
				length = n - i;
			}
			else {
				if(i+length > n)
					ok = 0;
			}
		}
	}
	if(!ok && X509_DEBUG)
		log("der_dec1: syntax error");
	return (ok, tag, i, i+length);
}

# [private]
# der tag decode

der_dectag(a: array of byte, i, n: int): (int, int, Tag)
{
	ok := 1;
	class, num, constr: int;
	if(n-i >= 2) {
		v := int a[i++];
		class = v & CLASS_MASK;
		if(v & CONSTR_MASK)
			constr = 1;
		else
			constr = 0;
		num = v & TAG_MASK;
		if(num == TAG_MASK)
			# long tag number
			(ok, i, num) = uint7_decode(a, i, n);
	}
	else
		ok = 0;
	if(!ok && X509_DEBUG)
		log("der_declen: syntax error");
	return (ok, i, Tag(class, num, constr));
}

# [private]

int_decode(a: array of byte, i, n, count, unsigned: int): (int, int, int)
{
	ok := 1;
	num := 0;
	if(n-i >= count) {
		if((count > 4) || (unsigned && count == 4 && (int a[i] & 16r80)))
			ok = 1;
		else {
			if(!unsigned && count > 0 && count < 4 && (int a[i] & 16r80))
				num = -1;		# all bits set
			for(j := 0; j < count; j++) {
				v := int a[i++];
				num = (num << 8) | v;
			}
		}
	}
	else
		ok = 0;
	if(!ok && X509_DEBUG)
		log("int_decode: syntax error");
	return (ok, i, num);
}


# [private]

uint7_decode(a: array of byte, i, n: int) : (int, int, int)
{
	ok := 1;
	num := 0;
	more := 1;
	while(more && i < n) {
		v := int a[i++];
		if(num & 16r7F000000) {
			ok = 0;
			break;
		}
		num <<= 7;
		more = v & 16r80;
		num |= (v & 16r7F);
	}
	if(n == i)
		ok = 0;
	if(!ok && X509_DEBUG)
		log("uint7_decode: syntax error");
	return (ok, i, num);
}


# [private]
# der length decode - the definite form of length encoding shall be used, encoded 
# in the minimum number of octets

der_declen(a: array of byte, i, n: int): (int, int, int)
{
	ok := 1;
	num := 0;
	if(i < n) {
		v := int a[i++];
		if(v & 16r80)
			return int_decode(a, i, n, v&16r7F, 1);
		else if(v == 16r80) # indefinite length
			ok = 0;
		else
			num = v;
	}
	else
		ok = 0;
	if(!ok && X509_DEBUG)
		log("der_declen: syntax error");
	return (ok, i, num);
}

# [private]
# parse der encoded algorithm identifier

decode_algid(a: array of byte): (int, ref AlgIdentifier)
{
	(err, el) := asn1->decode(a);
	if(err != "") {
		if(X509_DEBUG)
			log("decode_algid: " + err);
		return (0, nil);
	}
	return parse_alg(el);
}


## TBS (Public Key) Certificate is signed by Certificate Authority and contains 
## information of public key usage (as a comparison of Certificate Revocation List 
## and Attribute Certificate).

# [public]
# constructs a certificate by parsing a der encoded certificate
# returns error if parsing is failed or nil if parsing is ok

certsyn(s: string): (string, ref Certificate)
{
	if(0)
		sys->fprint(sys->fildes(2), "cert: %s\n", s);
	return ("certificate syntax: "+s, nil);
}

#	Certificate ::= SEQUENCE {
#		certificateInfo CertificateInfo,
#		signatureAlgorithm AlgorithmIdentifier,
#		signature BIT STRING }
#
#	CertificateInfo ::= SEQUENCE {
#		version [0] INTEGER DEFAULT v1 (0),
#		serialNumber INTEGER,
#		signature AlgorithmIdentifier,
#		issuer Name,
#		validity Validity,
#		subject Name,
#		subjectPublicKeyInfo SubjectPublicKeyInfo }
#	(version v2 has two more fields, optional unique identifiers for
#  issuer and subject; since we ignore these anyway, we won't parse them)
#
#	Validity ::= SEQUENCE {
#		notBefore UTCTime,
#		notAfter UTCTime }
#
#	SubjectPublicKeyInfo ::= SEQUENCE {
#		algorithm AlgorithmIdentifier,
#		subjectPublicKey BIT STRING }
#
#	AlgorithmIdentifier ::= SEQUENCE {
#		algorithm OBJECT IDENTIFER,
#		parameters ANY DEFINED BY ALGORITHM OPTIONAL }
#
#	Name ::= SEQUENCE OF RelativeDistinguishedName
#
#	RelativeDistinguishedName ::= SETOF SIZE(1..MAX) OF AttributeTypeAndValue
#
#	AttributeTypeAndValue ::= SEQUENCE {
#		type OBJECT IDENTIFER,
#		value DirectoryString }
#	(selected attributes have these Object Ids:
#		commonName {2 5 4 3}
#		countryName {2 5 4 6}
#		localityName {2 5 4 7}
#		stateOrProvinceName {2 5 4 8}
#		organizationName {2 5 4 10}
#		organizationalUnitName {2 5 4 11}
#	)
#
#	DirectoryString ::= CHOICE {
#		teletexString TeletexString,
#		printableString PrintableString,
#		universalString UniversalString }
#
#  See rfc1423, rfc2437 for AlgorithmIdentifier, subjectPublicKeyInfo, signature.

Certificate.decode(a: array of byte): (string, ref Certificate)
{
parse:
	# break on error
	for(;;) {
		(err, all) := asn1->decode(a);
		if(err != "")
			return certsyn(err);
		c := ref Certificate;

		# certificate must be a ASN1 sequence
		(ok, el) := all.is_seq();
		if(!ok)
			return certsyn("invalid certificate sequence");

		if(len el == 3){	# ssl3.b uses CertificateInfo; others use Certificate  (TO DO: fix this botch)
			certinfo := hd el;
			sigalgid := hd tl el;
			sigbits := hd tl tl el;

			# certificate info is another ASN1 sequence
			(ok, el) = certinfo.is_seq();
			if(!ok || len el < 6)
				return certsyn("invalid certificate info sequence");
		}

		c.version = 0; # set to default (v1)
		(ok, c.version) = parse_version(hd el);
		if(!ok)
			return certsyn("can't parse version");
		if(c.version > 0) {
			el = tl el;
			if(len el < 6)
				break parse;
		}
		# serial number
		(ok, c.serial_number) = parse_sernum(hd el);
		if(!ok)
			return certsyn("can't parse serial number");
		el = tl el;
		# signature algorithm
		(ok, c.sig) = parse_alg(hd el);
		if(!ok)
			return certsyn("can't parse sigalg");
		el = tl el;
		# issuer 
		(ok, c.issuer) = parse_name(hd el);
		if(!ok)
			return certsyn("can't parse issuer");
		el = tl el;
		# validity	
		evalidity := hd el;
		(ok, c.validity) = parse_validity(evalidity);
		if(!ok)
			return certsyn("can't parse validity");
		el = tl el;
		# Subject
		(ok, c.subject) = parse_name(hd el);
		if(!ok)
			return certsyn("can't parse subject");
		el = tl el;
		# SubjectPublicKeyInfo
		(ok, c.subject_pkinfo) = parse_pkinfo(hd el);
		if(!ok)
			return certsyn("can't parse subject pk info");
		el = tl el;
		# OPTIONAL for v2 and v3, must be in order
		# issuer unique identifier
		if(c.version == 0 && el != nil)
			return certsyn("bad unique ID");
		if(el != nil) {
			if(c.version < 1) # at least v2
				return certsyn("invalid v1 cert");
			(ok, c.issuer_uid) = parse_uid(hd el, 1);
			if(ok)
				el = tl el;
		}
		# subject unique identifier
		if(el != nil) {
			if(c.version < 1) # v2 or v3
				return certsyn("invalid v1 cert");
			(ok, c.issuer_uid) = parse_uid(hd el, 2);
			if(ok)
				el = tl el;
		}
		# extensions
		if(el != nil) {
			if(c.version < 2) # must be v3
				return certsyn("invalid v1/v2 cert");
			e : ref Elem;
			(ok, e) = is_context(hd el, 3);
			if (!ok)
				break parse;
			(ok, c.exts) = parse_extlist(e);
			if(!ok)
				return certsyn("can't parse extension list");
			el = tl el;
		}
		# must be no more left
		if(el != nil)
			return certsyn("unexpected data at end");
		return ("", c);
	}

	return ("certificate: syntax error", nil);
}

# [public]
# a der encoding of certificate data; returns (error, nil) tuple in failure

Certificate.encode(c: self ref Certificate): (string, array of byte)
{
pack:
	for(;;) {
		el: list of ref Elem;
		# always has a version packed
		e_version := pack_version(c.version);
		if(e_version == nil)
			break pack;
		el = e_version :: el;
		# serial number
		e_sernum := pack_sernum(c.serial_number);
		if(e_sernum == nil)
			break pack;
		el = e_sernum :: el;
		# algorithm
		e_sig := pack_alg(c.sig);
		if(e_sig == nil)
			break pack;
		el = e_sig :: el;
		# issuer
		e_issuer := pack_name(c.issuer);
		if(e_issuer == nil)
			break pack;
		el = e_issuer :: el;
		# validity
		e_validity := pack_validity(c.validity);
		if(e_validity == nil)
			break pack;
		el = e_validity :: el;
		# subject
		e_subject := pack_name(c.subject);
		if(e_subject == nil)
			break pack;
		el = e_subject :: el;
		# public key info
		e_pkinfo := pack_pkinfo(c.subject_pkinfo);
		if(e_pkinfo == nil)
			break pack;
		el = e_pkinfo :: el;
		# issuer unique identifier
		if(c.issuer_uid != nil) {
			e_issuer_uid := pack_uid(c.issuer_uid);
			if(e_issuer_uid == nil)
				break pack;
			el = e_issuer_uid :: el;			
		}
		# subject unique identifier
		if(c.subject_uid != nil) {
			e_subject_uid := pack_uid(c.subject_uid);
			if(e_subject_uid == nil)
				break pack;
			el = e_subject_uid :: el;
		}
		# extensions
		if(c.exts != nil) {
			e_exts := pack_extlist(c.exts);
			if(e_exts == nil)
				break pack;
			el = e_exts :: el;
		}
		# SEQUENCE order is important
		lseq: list of ref Elem;
		while(el != nil) {
			lseq = (hd el) :: lseq;
			el = tl el;
		}		
		all := ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(lseq));
		return asn1->encode(all);
	}
	return ("incompleted certificate; unable to pack", nil);
}

# [public]
# converts content of a certificate as visible string

Certificate.tostring(c: self ref Certificate): string
{
	s := "\tTBS Certificate";
	s += "\n\tVersion:\n\t\t" + string c.version;
	s += "\n\tSerialNumber:\n\t\t" + c.serial_number.iptostr(10);
	s += "\n\tSignature: " + c.sig.tostring();
	s += "\n\tIssuer: " + c.issuer.tostring();
	s += "\n\tValidity: " + c.validity.tostring("local");
	s += "\n\tSubject: " + c.subject.tostring();
	s += "\n\tSubjectPKInfo: " + c.subject_pkinfo.tostring();
	s += "\n\tIssuerUID: " + bastr(c.issuer_uid);
	s += "\n\tSubjectUID: " + bastr(c.subject_uid);
	s += "\n\tExtensions: ";
	exts := c.exts;
	while(exts != nil) {
		s += "\t\t" + (hd exts).tostring();
		exts = tl exts;
	}
	return s;
}

# [public]

Certificate.is_expired(c: self ref Certificate, date: int): int
{
	if(date > c.validity.not_after || date < c.validity.not_before)
		return 1;

	return 0;
}


# [private]
# version is optional marked by explicit context tag 0; no version is 
# required if default version (v1) is used

parse_version(e: ref Elem): (int, int)
{
	ver := 0;
	(ans, ec) := is_context(e, 0);
	if(ans) {
		ok := 0;
		(ok, ver) = ec.is_int();
		if(!ok || ver < 0 || ver > 2)
			return (0, -1);
	}
	return (1, ver);
}

# [private]

pack_version(v: int): ref Elem
{
	return ref Elem(Tag(Universal, INTEGER, 0), ref Value.Int(v));
}

# [private]

parse_sernum(e: ref Elem): (int, ref IPint)
{
	(ok, a) := e.is_bigint();
	if(ok)
		return (1, IPint.bebytestoip(a));
	if(X509_DEBUG)
		log("parse_sernum: syntax error");
	return (0, nil);
}

# [private]

pack_sernum(sn: ref IPint): ref Elem
{
	return ref Elem(Tag(Universal, INTEGER, 0), ref Value.BigInt(sn.iptobebytes()));
}

# [private]

parse_alg(e: ref Elem): (int, ref AlgIdentifier)
{
parse:
	for(;;) {	
		(ok, el) := e.is_seq();
		if(!ok || el == nil)
			break parse;
		oid: ref Oid;
		(ok, oid) = (hd el).is_oid();
		if(!ok)
			break parse;
		el = tl el;
		params: array of byte;
		if(el != nil) {
			# TODO: determine the object type based on oid
			# 	then parse params
			#unused: int;
			#(ok, unused, params) = (hd el).is_bitstring();
			#if(!ok || unused || tl el != nil)
			#	break parse;
		}
		return (1, ref AlgIdentifier(oid, params));
	}
	if(X509_DEBUG)
		log("parse_alg: syntax error");
	return (0, nil);
}

# [private]

pack_alg(a: ref AlgIdentifier): ref Elem
{
	if(a.oid != nil) {
		el: list of ref Elem;
		el = ref Elem(Tag(Universal, ASN1->OBJECT_ID, 0), ref Value.ObjId(a.oid)) :: nil;
		if(a.parameter != nil)  {
			el = ref Elem(
				Tag(Universal, BIT_STRING, 0), 
				ref Value.BitString(0, a.parameter)
			) :: el;
		}
		return ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
	}
	return nil;
}

# [private]

parse_name(e: ref Elem): (int, ref Name)
{
parse:
	for(;;) {
		(ok, el) := e.is_seq();
		if(!ok)
			break parse;
		lrd: list of ref RDName;
		while(el != nil) {
			rd: ref RDName;
			(ok, rd) = parse_rdname(hd el);
			if(!ok)
				break parse;
			lrd = rd :: lrd;
			el = tl el;
		}
		# SEQUENCE
		l: list of ref RDName;
		while(lrd != nil) {
			l = (hd lrd) :: l;
			lrd = tl lrd;
		}
		return (1, ref Name(l));
	}
	if(X509_DEBUG)
		log("parse_name: syntax error");
	return (0, nil);
}

# [private]

pack_name(n: ref Name): ref Elem
{
	el: list of ref Elem;

	lrd := n.rd_names;
	while(lrd != nil) {
		rd := pack_rdname(hd lrd);
		if(rd == nil)
			return nil;
		el = rd :: el;
		lrd = tl lrd;
	}
	# reverse order
	l: list of ref Elem;
	while(el != nil) {
		l = (hd el) :: l;
		el = tl el;
	}

	return ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(l));
}

# [private]

parse_rdname(e: ref Elem): (int, ref RDName)
{
parse:
	for(;;) {
		(ok, el) := e.is_set(); # unordered
		if(!ok)
			break parse;
		lava: list of ref AVA;
		while(el != nil) {
			ava: ref AVA;
			(ok, ava) = parse_ava(hd el);
			if(!ok)
				break parse;
			lava = ava :: lava;
			el = tl el;
		}
		return (1, ref RDName(lava));
	}
	if(X509_DEBUG)
		log("parse_rdname: syntax error");
	return (0, nil);
}

# [private]

pack_rdname(r: ref RDName): ref Elem
{
	el: list of ref Elem;
	lava := r.avas;
	while(lava != nil) {
		ava := pack_ava(hd lava);
		if(ava == nil)
			return nil;
		el = ava :: el;
		lava = tl lava;
	}
	return ref Elem(Tag(Universal, ASN1->SET, 1), ref Value.Set(el));
}

# [private]

parse_ava(e: ref Elem): (int, ref AVA)
{
parse:
	for(;;) {
		(ok, el) := e.is_seq();
		if(!ok || len el != 2)
			break parse;
		a := ref AVA;
		(ok, a.oid) = (hd el).is_oid();
		if(!ok)
			break parse;
		el = tl el;
		(ok, a.value) = (hd el).is_string();
		if(!ok)
			break parse;
		return (1, a);
	}
	if(X509_DEBUG)
		log("parse_ava: syntax error");
	return (0, nil);
}

# [private]

pack_ava(a: ref AVA): ref Elem
{
	el: list of ref Elem;
	if(a.oid == nil || a.value == "")
		return nil;
	# Note: order is important
	el = ref Elem(Tag(Universal, ASN1->GeneralString, 0), ref Value.String(a.value)) :: el;
	el = ref Elem(Tag(Universal, ASN1->OBJECT_ID, 0), ref Value.ObjId(a.oid)) :: el;	
	return ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
}

# [private]

parse_validity(e: ref Elem): (int, ref Validity)
{
parse:
	for(;;) {
		(ok, el) := e.is_seq();
		if(!ok || len el != 2)
			break parse;
		v := ref Validity;
		(ok, v.not_before) = parse_time(hd el, UTCTime);
		if(!ok)
			break parse;
		el = tl el;
		(ok, v.not_after) = parse_time(hd el, UTCTime);
		if(!ok)
			break parse;
		return (1, v);
	}
	if(X509_DEBUG)
		log("parse_validity: syntax error");
	return (0, nil);
}

# [private]
# standard says only UTC Time allowed for TBS Certificate, but there is exception of
# GeneralizedTime for CRL and Attribute Certificate. Parsing is based on format of
# UTCTime, GeneralizedTime or undetermined (any int not UTCTime or GeneralizedTime).

parse_time(e: ref Elem, format: int): (int, int)
{
parse:
	for(;;) {
		(ok, date) := e.is_time();
		if(!ok)
			break parse;
		if(e.tag.num != UTCTime && e.tag.num != GeneralizedTime)
			break parse;
		if(format == UTCTime && e.tag.num != UTCTime)
			break parse;
		if(format == GeneralizedTime && e.tag.num != GeneralizedTime)
			break parse; 
		t := decode_time(date, e.tag.num);
		if(t < 0)
			break parse;
		return (1, t);
	}
	if(X509_DEBUG)
		log("parse_time: syntax error");
	return (0, -1);
}

# [private]
# decode a BER encoded UTC or Generalized time into epoch (seconds since 1/1/1970 GMT)
# UTC time format: YYMMDDhhmm[ss](Z|(+|-)hhmm)
# Generalized time format: YYYYMMDDhhmm[ss.s(...)](Z|(+|-)hhmm[ss.s(...))

decode_time(date: string, format: int): int
{
	time := ref Daytime->Tm;
parse:
	for(;;) {
    		i := 0;
		if(format == UTCTime) {
			if(len date < 11)
				break parse;
			time.year = get2(date, i);
	   		if(time.year < 0)
        			break parse;    
			if(time.year < 70)
        			time.year += 100;
			i += 2;
		}
		else {
			if(len date < 13)
				break parse;
			time.year = get2(date, i);
			if(time.year-19 < 0)
				break parse;
			time.year = (time.year - 19)*100;
			i += 2;
			time.year += get2(date, i);
			i += 2;
		}
		time.mon = get2(date, i) - 1;
		if(time.mon < 0 || time.mon > 11)
			break parse;
		i += 2;
		time.mday = get2(date, i);
		if(time.mday < 1 || time.mday > 31)
			break parse;
		i += 2;
		time.hour = get2(date, i);
		if(time.hour < 0 || time.hour > 23)
			break parse;
		i += 2;
		time.min = get2(date, i);
		if(time.min < 0 || time.min > 59)
			break parse;
		i += 2;
		if(int date[i] >= '0' && int date[i] <= '9') {
			if(len date < i+3)
            			break parse;
			time.sec = get2(date, i);
			if(time.sec < 0 || time.sec > 59)
				break parse;
			i += 2;
			if(format == GeneralizedTime) {
				if((len date < i+3) || int date[i++] != '.')
					break parse;
				# ignore rest
				ig := int date[i];
				while(ig >= '0' && ig <= '9' && i++ < len date) {
					ig = int date[i];
				}
			}
		}
		else {
			time.sec = 0;
		}    
		zf := int date[i];
		if(zf != 'Z' && zf != '+' && zf != '-')
			break parse;
		if(zf == 'Z') {
			if(len date != i+1)
				break parse;
			time.tzoff = 0;
		}
		else {   
			if(len date < i + 3)
				break parse;
			time.tzoff = get2(date, i+1);
			if(time.tzoff < 0 || time.tzoff > 23)
				break parse;
			i += 2;
			min := get2(date, i);
			if(min < 0 || min > 59)
				break parse;
			i += 2;
			sec := 0;
			if(i != len date) {
				if(format == UTCTime || len date < i+4)
					break parse;
				sec = get2(date, i);
				i += 2;
				# ignore the rest
			}
			time.tzoff = (time.tzoff*60 + min)*60 + sec;
			if(zf == '-')
				time.tzoff = -time.tzoff;
		}
		return daytime->tm2epoch(time);    
	}
	if(X509_DEBUG)
		log("decode_time: syntax error: " +
		sys->sprint("year=%d mon=%d mday=%d hour=%d min=%d, sec=%d", 
		time.year, time.mon, time.mday, time.hour, time.min, time.sec));
	return -1;
}

# [private]
# pack as UTC time

pack_validity(v: ref Validity): ref Elem
{
	el: list of ref Elem;
	el = ref Elem(
			Tag(Universal, UTCTime, 0), 
			ref Value.String(pack_time(v.not_before, UTCTime))
		) :: nil;
	el = ref Elem(
			Tag(Universal, UTCTime, 0), 
			ref Value.String(pack_time(v.not_after, UTCTime))
		) :: el;
	return ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
}

# [private]
# Format must be either UTCTime or GeneralizedTime
# TODO: convert to coordinate time

pack_time(t: int, format: int): string
{
	date := array [32] of byte;
	tm := daytime->gmt(t);

	i := 0;
	if(format == UTCTime) {
		i = put2(date, tm.year, i);
	}
	else { # GeneralizedTime
		i = put2(date, 19 + tm.year/100, i);
		i = put2(date, tm.year%100, i);
	}
	i = put2(date, tm.mon, i);
	i = put2(date, tm.mday, i);
	i = put2(date, tm.hour, i);
	i = put2(date, tm.min, i);
	if(tm.sec != 0) {
		if(format == UTCTime)
			i = put2(date, tm.sec, i);
		else {
			i = put2(date, tm.sec, i);
			date[i++] = byte '.';	
			date[i++] = byte 0;
		}
	}
	if(tm.tzoff == 0) {
		date[i++] = byte 'Z';
	}
	else {
		off := tm.tzoff;
		if(tm.tzoff < 0) {
			off = -off;
			date[i++] = byte '-';
		}
		else {
			date[i++] = byte '+';
		}
		hoff := int (off/3600);
		moff := int ((off%3600)/60);
		soff := int ((off%3600)%60);
		i = put2(date, hoff, i);
		i = put2(date, moff, i);
		if(soff) {
			if(format == UTCTime)
				i = put2(date, soff, i);
			else {
				i = put2(date, soff, i);
				date[i++] = byte '.';	
				date[i++] = byte 0;
			}
		}
	}
	return string date[0:i];
}

# [private]

parse_pkinfo(e: ref Elem): (int, ref SubjectPKInfo)
{
parse:
	for(;;) {
		p := ref SubjectPKInfo;
		(ok, el) := e.is_seq();
		if(!ok || len el != 2)
			break parse;
		(ok, p.alg_id) = parse_alg(hd el);
		if(!ok)
			break parse;
		unused: int;
		(ok, unused, p.subject_pk) = (hd tl el).is_bitstring();
		if(!ok || unused != 0)
			break parse;
		return (1, p);
	}
	if(X509_DEBUG)
		log("parse_pkinfo: syntax error");
	return (0, nil);
}

# [private]

pack_pkinfo(p: ref SubjectPKInfo): ref Elem
{
	el: list of ref Elem;
	# SEQUENCE order is important
	el = ref Elem(
			Tag(Universal, BIT_STRING, 0), 
			ref Value.BitString(0, p.subject_pk) # 0 bits unused ?
		) :: nil;
	el = pack_alg(p.alg_id) :: el;
	return ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
}

# [private]

parse_uid(e: ref Elem, num: int): (int, array of byte)
{
	ok, unused : int;
	uid : array of byte;
	e2 : ref Elem;
parse:
	for(;;) {
		(ok, e2) = is_context(e, num);
		if (!ok)
			break parse;
		e = e2;

		(ok, unused, uid) = e.is_bitstring();
#		if(!ok || unused != 0)
		if(!ok)
			break parse;
		return (1, uid);
	}
	if(X509_DEBUG)
		log("parse_uid: syntax error");
	return (0, nil);
}

# [private]

pack_uid(u: array of byte): ref Elem
{
	return ref Elem(Tag(Universal, ASN1->BIT_STRING, 0), ref Value.BitString(0,u));
}

# [private]

parse_extlist(e: ref Elem): (int, list of ref Extension)
{
parse:
	# dummy loop for breaking out of
	for(;;) {
		l: list of ref Extension;
		(ok, el) := e.is_seq();
		if(!ok)
			break parse;
		while(el != nil) {
			ext := ref Extension;
			(ok, ext) = parse_extension(hd el);
			if(!ok)
				break parse;
			l = ext :: l;
			el = tl el;
		}
		# sort to order
		nl: list of ref Extension;
		while(l != nil) {
			nl = (hd l) :: nl;
			l = tl l;
		}
		return (1, nl);
	}
	if(X509_DEBUG)
		log("parse_extlist: syntax error");
	return (0, nil);
}

# [private]

pack_extlist(e: list of ref Extension): ref Elem
{
	el: list of ref Elem;
	exts := e;
	while(exts != nil) {
		ext := pack_extension(hd exts);
		if(ext == nil)
			return nil;
		el = ext :: el;
		exts = tl exts;
	}
	# reverse order
	l: list of ref Elem;
	while(el != nil) {
		l = (hd el) :: l;
		el = tl el;
	}
	return ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(l));
}

# [private]
# Require further parse to check oid if critical is set to TRUE (see parse_exts)

parse_extension(e: ref Elem): (int, ref Extension)
{
parse:
	for(;;) {
		ext := ref Extension;
		(ok, el) := e.is_seq();
		if(!ok)
			break parse;
		oid: ref Oid;
		(ok, oid) = (hd el).is_oid(); 
		if(!ok)
			break parse;
		ext.oid = oid; 
		el = tl el;
		# BOOLEAN DEFAULT FALSE
		(ok, ext.critical) = (hd el).is_int();
		if(ok)
			el = tl el;
		else
			ext.critical = 0;
		if (len el != 1) {
			break parse;
		}
		(ok, ext.value) = (hd el).is_octetstring();
		if(!ok)
			break parse;
		return (1, ext);
	}
	if(X509_DEBUG)
		log("parse_extension: syntax error");
	return (0, nil);
}

# [private]

pack_extension(e: ref Extension): ref Elem
{
	el: list of ref Elem;

	if(e.oid == nil || (e.critical !=0 && e.critical != 1) || e.value == nil)
		return nil;
	# SEQUENCE order
	el = ref Elem(Tag(Universal, OCTET_STRING, 0), ref Value.Octets(e.value)) :: el;
	el = ref Elem(Tag(Universal, BOOLEAN, 0), ref Value.Bool(e.critical)) :: el;
	el = ref Elem(Tag(Universal, OBJECT_ID, 0), ref Value.ObjId(e.oid)) :: el;
	return ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
}

# [public]

AlgIdentifier.tostring(a: self ref AlgIdentifier): string
{
	return "\n\t\toid: " + a.oid.tostring() + "\n\t\twith parameter: "+ bastr(a.parameter);
}

# [public]

Name.equal(a: self ref Name, b: ref Name): int
{
	rda := a.rd_names;
	rdb := b.rd_names;
	if(len rda != len rdb)
		return 0;
	while(rda != nil && rdb != nil) {
		ok := (hd rda).equal(hd rdb);
		if(!ok)
			return 0;
		rda = tl rda;
		rdb = tl rdb;
	}

	return 1;
}

# [public]
# The sequence of RelativeDistinguishedName's gives a sort of pathname, from most general to 
# most specific.  Each element of the path can be one or more (but usually just one) 
# attribute-value pair, such as countryName="US". We'll just form a "postal-style" address 
# string by concatenating the elements from most specific to least specific, separated by commas.

Name.tostring(a: self ref Name): string
{
	path: string;
	rdn := a.rd_names;
	while(rdn != nil) {
		path += (hd rdn).tostring();
		rdn = tl rdn;
		if(rdn != nil)
			path += ",";
	}
	return path;
}

# [public]
# The allocation of distinguished names is the responsibility of the Naming Authorities. 
# Each user shall therefore trust the Naming Authorities not to issue duplicate distinguished
# names. The comparison shall be unique one to one match but may not in the same order.

RDName.equal(a: self ref RDName, b: ref RDName): int
{
	if(len a.avas != len b.avas)
		return 0;
	aa := a.avas;
	ba := b.avas;
	while(aa != nil) {
		found:= 0;
		rest: list of ref AVA;
		while(ba != nil) {
			ok := (hd ba).equal(hd ba);
			if(!ok)
				rest = (hd aa) :: rest;
			else {
				if(found)
					return 0;
				found = 1;
			}
			ba = tl ba;
		}
		if(found == 0)
			return 0;
		ba = rest;
		aa = tl aa;
	}
	return 1;
}

# [public]

RDName.tostring(a: self ref RDName): string
{
	s: string;
	avas := a.avas;
	while(avas != nil) {
		s += (hd avas).tostring();
		avas = tl avas;
		if(avas != nil)
			s += "-";
	}
	return s;
}

# [public]
# AVA are equal if they have the same type oid and value

AVA.equal(a: self ref AVA, b: ref AVA): int
{
	# TODO: need to match different encoding (T61String vs. IA5String)
	if(a.value != b.value)
		return 0;

	return oid_cmp(a.oid, b.oid);
}

# [public]

AVA.tostring(a: self ref AVA): string
{
	return a.value;
}

# [public]

Validity.tostring(v: self ref Validity, format: string): string
{
	s: string;
	if(format == "local") {
		s = "\n\t\tnot_before[local]: ";
	 	s += daytime->text(daytime->local(v.not_before));
		s += "\n\t\tnot_after[local]: ";
		s += daytime->text(daytime->local(v.not_after));
	}
	else if(format == "gmt") {
		s = "\n\t\tnot_before[gmt]: ";
	 	s += daytime->text(daytime->gmt(v.not_before));
		s += "\n\t\tnot_after[gmt]: ";
		s += daytime->text(daytime->gmt(v.not_after));
	}
	else
		s += "unknown format: " + format;
	return s;	
}

# [public]

SubjectPKInfo.getPublicKey(pkinfo: self ref SubjectPKInfo): (string, int, ref PublicKey)
{
parse:
	for(;;) {
		pk: ref PublicKey;
		id := asn1->oid_lookup(pkinfo.alg_id.oid, pkcs->objIdTab);
		case id {
		PKCS->id_pkcs_rsaEncryption or
		PKCS->id_pkcs_md2WithRSAEncryption or
		PKCS->id_pkcs_md4WithRSAEncryption or
		PKCS->id_pkcs_md5WithRSAEncryption =>
			(err, k) := pkcs->decode_rsapubkey(pkinfo.subject_pk);
			if(err != nil)
				break parse;
			pk = ref PublicKey.RSA(k);
		PKCS->id_algorithm_shaWithDSS =>
			(err, k) :=  pkcs->decode_dsspubkey(pkinfo.subject_pk);
			if(err != nil)
				break parse;
			pk = ref PublicKey.DSS(k);
		PKCS->id_pkcs_dhKeyAgreement =>
			(err, k) := pkcs->decode_dhpubkey(pkinfo.subject_pk);
			if(err != nil)
				break parse;
			pk = ref PublicKey.DH(k);
		* =>
			break parse;
		}
		return ("", id, pk);
	}
	return ("subject public key: syntax error", -1, nil);
}

# [public]

SubjectPKInfo.tostring(pkinfo: self ref SubjectPKInfo): string
{
	s := pkinfo.alg_id.tostring();
	s += "\n\t\tencoded key: " + bastr(pkinfo.subject_pk);
	return s;
}

# [public]

Extension.tostring(e: self ref Extension): string
{
	s := "oid: " + e.oid.tostring();
	s += "critical: ";
	if(e.critical)
		s += "true ";
	else
		s += "false ";
	s += bastr(e.value);
	return s;
}

## Certificate PATH
## A list of certificates needed to allow a particular user to obtain
## the public key of another, is known as a certificate path. A
## certificate path logically forms an unbroken chain of trusted
## points in the DIT between two users wishing to authenticate.
## To establish a certification path between user A and user B using
## the Directory without any prior information, each CA may store
## one certificate and one reverse certificate designated as
## corresponding to its superior CA.

# The ASN.1 data byte definitions for certificates and a certificate 
# path is
#
# Certificates	::= SEQUENCE {
#	userCertificate		Certificate,
#	certificationPath	ForwardCertificationPath OPTIONAL }
#
# ForwardCertificationPath ::= SEQUENCE OF CrossCertificates
# CrossCertificates ::=	SET OF Certificate
# 

# [public]
# Verify a decoded certificate chain in order of root to user. This is useful for 
# non_ASN.1 encoding of certificates, e.g. in SSL. Return (0, error string) if 
# verification failure or (1, "") if verification ok

verify_certchain(cs: list of array of byte): (int, string)
{
	lsc: list of (ref Signed, ref Certificate);

	l := cs;
	while(l != nil) {
		(err, s) := Signed.decode(hd l); 
		if(err != "") 
			return (0, err);
		c: ref Certificate;
		(err, c) = Certificate.decode(s.tobe_signed);
		if(err != "")
			return (0, err);		
		lsc = (s, c) :: lsc;
		l = tl l;
	}
	# reverse order
	a: list of (ref Signed, ref Certificate);
	while(lsc != nil) {
		a = (hd lsc) :: a;
		lsc = tl lsc;
	}
	return verify_certpath(a);
}

# [private]
# along certificate path; first certificate is root

verify_certpath(sc: list of (ref Signed, ref Certificate)): (int, string)
{
	# verify self-signed root certificate
	(s, c) := hd sc;
	# TODO: check root RDName with known CAs and using
	# external verification of root - Directory service
	(err, id, pk) := c.subject_pkinfo.getPublicKey();
	if(err != "")
		return (0, err);
	if(!is_validtime(c.validity)
		|| !c.issuer.equal(c.subject)
		|| !s.verify(pk, 0)) # TODO: prototype verify(key, ref AlgIdentifier)?
		return (0, "verification failure");

	sc = tl sc;
	while(sc != nil) {
		(ns, nc) := hd sc;
		# TODO: check critical flags of extension list
		# check alt names field
		(err, id, pk) = c.subject_pkinfo.getPublicKey();
		if(err != "")
			return (0, err);
		if(!is_validtime(nc.validity)
			|| !nc.issuer.equal(c.subject) 
			|| !ns.verify(pk, 0)) # TODO: move prototype as ?
			return (0, "verification failure");
		(s, c) = (ns, nc);
		sc = tl sc;
	}

	return (1, "");
}

# [public]
is_validtime(validity: ref Validity): int
{
	# a little more expensive but more accurate
	now := daytime->now();

	# need some conversion here
	if(now < validity.not_before || now > validity.not_after)
		return 0;

	return 1;	
} 

is_validpair(): int
{
	return 0;
}

## Certificate Revocation List (CRL)
##
## A CRL is a time-stampted list identifying revoked certificates. It is signed by a 
## Certificate Authority (CA) and made freely available in a public repository.
##
## Each revoked certificate is identified in a CRL by its certificate serial number. 
## When a certificate-using system uses a certificate (e.g., for verifying a remote 
## user's digital signature), that system not only checks the certificate signature 
## and validity but also acquires a suitably-recent CRL and checks that the certificate 
## serial number is not on that CRL. The meaning of "suitably-recent" may vary with
## local policy, but it usually means the most recently-issued CRL. A CA issues a new 
## CRL on a regular periodic basis (e.g., hourly, daily, or weekly). Entries are added 
## on CRLs as revocations occur, and an entry may be removed when the certificate 
## expiration date is reached.

# [public]

CRL.decode(a: array of byte): (string, ref CRL)
{
parse:
	# break on error
	for(;;) {
		(err, all) := asn1->decode(a);
		if(err != "")
			break parse;
		c := ref CRL;
		# CRL must be a ASN1 sequence
		(ok, el) := all.is_seq();
		if(!ok || len el < 3)
			break parse;
		c.version = 1; # set to default (v2)
		(ok, c.version) = parse_version(hd el);
		if(!ok)
			break parse;
		if(c.version < 0) {
			el = tl el;
			if(len el < 4)
				break parse;
		}
		# signature algorithm
		(ok, c.sig) = parse_alg(hd el);
		if(!ok)
			break parse;
		el = tl el;
		# issuer: who issues the CRL
		(ok, c.issuer) = parse_name(hd el);
		if(!ok)
			break parse;
		el = tl el;
		# this update
		(ok, c.this_update) = parse_time(hd el, UTCTime);
		if(!ok)
			break parse;
		el = tl el;
		# OPTIONAL, must be in order
		# next_update
		if(el != nil) {
			(ok, c.next_update) = parse_time(hd el, UTCTime);
			if(!ok)
				break parse;
			el = tl el;
		}
		# revoked certificates
		if(el != nil) {
			(ok, c.revoked_certs) = parse_revoked_certs(hd el);
			if(!ok)
				break parse;
			el = tl el;
		}
		# extensions
		if(el != nil) {
			(ok, c.exts) = parse_extlist(hd el);	
			if(!ok)
				break parse;
			el = tl el;
		}
		# must be no more left
		if(el != nil)
			break parse;
		return ("", c);
	}
	return ("CRL: syntax error", nil);
}

# [public]

CRL.encode(c: self ref CRL): (string, array of byte)
{
pack:
	for(;;) {
		el: list of ref Elem;
		# always has a version packed
		e_version := pack_version(c.version);
		if(e_version == nil)
			break pack;
		el = e_version :: el;
		# algorithm
		e_sig := pack_alg(c.sig);
		if(e_sig == nil)
			break pack;
		el = e_sig :: el;
		# crl issuer
		e_issuer := pack_name(c.issuer);
		if(e_issuer == nil)
			break pack;
		el = e_issuer :: el;
		# validity
		e_this_update := pack_time(c.this_update, UTCTime);
		if(e_this_update == nil)
			break pack;
		el = ref Elem(
			Tag(Universal, ASN1->UTCTime, 0), 
			ref Value.String(e_this_update)
			) :: el;
		# next crl update
		if(c.next_update != 0) {
			e_next_update := pack_time(c.next_update, UTCTime);
			if(e_next_update == nil)
				break pack;
			el = ref Elem(
				Tag(Universal, ASN1->UTCTime, 0),
				ref Value.String(e_next_update)
				) :: el;
		}
		# revoked certificates
		if(c.revoked_certs != nil) {
			e_revoked_certs := pack_revoked_certs(c.revoked_certs);
			if(e_revoked_certs == nil)
				break pack;
			el = e_revoked_certs :: el;
		}
		# crl extensions
		if(c.exts != nil) {
			e_exts := pack_extlist(c.exts);
			if(e_exts == nil)
				break pack;
			el = e_exts :: el;
		}
		# compose all elements
		lseq: list of ref Elem;
		while(el != nil) {
			lseq = (hd el) :: lseq;
			el = tl el;
		}
		all := ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(lseq));
		(err, ret) := asn1->encode(all);
		if(err != "")
			break;
		return ("", ret);
	}
	return ("incompleted CRL; unable to pack", nil);
}

# [public]

CRL.tostring(c: self ref CRL): string
{
	s := "Certificate Revocation List (CRL)";
	s += "\nVersion: " + string c.version;
	s += "\nSignature: " + c.sig.tostring();
	s += "\nIssuer: " + c.issuer.tostring();
	s += "\nThis Update: " + daytime->text(daytime->local(c.this_update));
	s += "\nNext Update: " + daytime->text(daytime->local(c.next_update));
	s += "\nRevoked Certificates: ";
	rcs := c.revoked_certs;
	while(rcs != nil) {
		s += "\t" + (hd rcs).tostring();
		rcs = tl rcs;
	}
	s += "\nExtensions: ";
	exts := c.exts;
	while(exts != nil) {
		s += "\t" + (hd exts).tostring();
		exts = tl exts;
	}
	return s;
}

# [public]

CRL.is_revoked(c: self ref CRL, sn: ref IPint): int
{
	es := c.revoked_certs;
	while(es != nil) {
		if(sn.eq((hd es).user_cert))
			return 1;
		es = tl es;
	}
	return 0;
}

# [public]

RevokedCert.tostring(rc: self ref RevokedCert): string
{
	s := "Revoked Certificate";
	if(rc.user_cert == nil)
		return s + " [Bad Format]\n";
	s += "\nSerial Number: " + rc.user_cert.iptostr(10);
	if(rc.revoc_date != 0)
		s += "\nRevocation Date: " + daytime->text(daytime->local(rc.revoc_date));
	if(rc.exts != nil) {
		exts := rc.exts;
		while(exts != nil) {
			s += "\t" + (hd exts).tostring();
			exts = tl exts;
		}
	}
	return s;		
}


# [private]

parse_revoked_certs(e: ref Elem): (int, list of ref RevokedCert)
{
	lc: list of ref RevokedCert;
parse:
	for(;;) {
		(ok, el) := e.is_seq();
		if(!ok)
			break parse;
		while(el != nil) {
			c: ref RevokedCert;
			(ok, c) = parse_revoked(hd el);
			if(!ok)
				break parse;
			lc = c :: lc;	
			el = tl el;
		}

		return (1, lc);
	}
	
	return (0, nil);
}

# [private]

pack_revoked_certs(r: list of ref RevokedCert): ref Elem
{
	el: list of ref Elem;

	rs := r;
	while(rs != nil) {
		rc := pack_revoked(hd rs);
		if(rc == nil)
			return nil;
		el = rc :: el;
		rs = tl rs;
	}
	# reverse order
	l: list of ref Elem;
	while(el != nil) {
		l = (hd el) :: l;
		el = tl el;
	}
	return ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(l));
	
}

# [private]

parse_revoked(e: ref Elem): (int, ref RevokedCert)
{
parse:
	for(;;) {
		c: ref RevokedCert;
		(ok, el) := e.is_seq();
		if(!ok || len el < 2)
			break parse;
		uc: array of byte;
		(ok, uc) = (hd el).is_bigint();
		if(!ok)
			break parse;
		c.user_cert = IPint.bebytestoip(uc);
		el = tl el;
		(ok, c.revoc_date) = parse_time(hd el, UTCTime);
		if(!ok)
			break parse;
		el = tl el;
		if(el != nil) {
			(ok, c.exts) = parse_extlist(hd el);
			if(!ok)
				break parse;
		}
		return (1, c);
	}
	return (0, nil);
}

# [private]

pack_revoked(r: ref RevokedCert): ref Elem
{
	el: list of ref Elem;
	if(r.exts != nil) {
		e_exts := pack_extlist(r.exts);
		if(e_exts == nil)
			return nil;		
		el = e_exts :: el;
	}
	if(r.revoc_date != 0) {
		e_date := pack_time(r.revoc_date, UTCTime);
		if(e_date == nil)
			return nil;
		el = ref Elem(
				Tag(Universal, ASN1->UTCTime, 0),
				ref Value.String(e_date)
			) :: el;
	}
	if(r.user_cert == nil)
		return nil;
	el = ref Elem(Tag(Universal, INTEGER, 0), 
			ref Value.BigInt(r.user_cert.iptobebytes())
		) :: el;
	return ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
}

## The extensions field allows addition of new fields to the structure 
## without modification to the ASN.1 definition. An extension field 
## consists of an extension identifier, a criticality flag, and a 
## canonical encoding of a data value of an ASN.1 type associated with 
## the identified extension. For those extensions where ordering of 
## individual extensions within the SEQUENCE is significant, the  
## specification of those individual extensions shall include the rules 
## for the significance of the ordering. When an implementation 
## processing a certificate does not recognize an extension, if the 
## criticality flag is FALSE, it may ignore that extension. If the 
## criticality flag is TRUE, unrecognized extensions shall cause the 
## structure to be considered invalid, i.e. in a certificate, an 
## unrecognized critical extension would cause validation of a signature 
## using that certificate to fail.

# [public]

cr_exts(es: list of ref Extension): list of ref Extension
{
	cr: list of ref Extension;
	l := es;
	while(l != nil) {
		e := hd l;
		if(e.critical == 1)
			cr = e :: cr;
		l = tl l;		
	}
	return cr;
}

# [public]

noncr_exts(es: list of ref Extension): list of ref Extension
{
	ncr: list of ref Extension;
	l := es;
	while(l != nil) {
		e := hd l;
		if(e.critical == 0)
			ncr = e :: ncr;
		l = tl l;		
	}
	return ncr;
}

# [public]

parse_exts(exts: list of ref Extension): (string, list of ref ExtClass)
{
	ets: list of ref ExtClass;
	l := exts;
	while(l != nil) {
		ext := hd l;
		(err, et) := ExtClass.decode(ext);
		if(err != "")
			return (err, nil);
		ets = et :: ets;
		l = tl l;
	}
	lseq: list of ref ExtClass;
	while(ets != nil) {
		lseq = (hd ets) :: lseq;
		ets = tl ets;
	}
	return ("", lseq);
}

# [public]

ExtClass.decode(ext: ref Extension): (string, ref ExtClass)
{
	err: string;
	eclass: ref ExtClass;

	oid := asn1->oid_lookup(ext.oid, objIdTab);
	case oid {
	id_ce_authorityKeyIdentifier =>
		(err, eclass) = decode_authorityKeyIdentifier(ext);
		if(err == "" && ext.critical == 1) {
			err = "authority key identifier: should be non-critical";
			break;
		}
	id_ce_subjectKeyIdentifier =>
		(err, eclass) = decode_subjectKeyIdentifier(ext);
		if(err != "" && ext.critical != 0) {
			err = "subject key identifier: should be non-critical";
			break;
		}
	id_ce_basicConstraints =>
		(err, eclass) = decode_basicConstraints(ext);
		if(err == "" && ext.critical != 1) {
			err = "basic constraints: should be critical";
			break;
		}
	id_ce_keyUsage =>
		(err, eclass) = decode_keyUsage(ext);
		if(err == "" && ext.critical != 1) {
			err = "key usage: should be critical";
			break;
		}
	id_ce_privateKeyUsage =>
		(err, eclass) = decode_privateKeyUsage(ext);
		if(err == "" && ext.critical != 0) {
			err = "private key usage: should be non-critical";
			break;
		}
	id_ce_policyMapping =>
		(err, eclass) = decode_policyMapping(ext);
		if(err == "" && ext.critical != 0) {
			err = "policy mapping: should be non-critical";
			break;
		}
	id_ce_certificatePolicies =>
		(err, eclass) = decode_certificatePolicies(ext);
		# either critical or non-critical
	id_ce_issuerAltName =>
		n: list of ref GeneralName;
		(err, n) = decode_alias(ext);
		if(err == "")
			eclass = ref ExtClass.IssuerAltName(n);
		# either critical or non-critical
	id_ce_subjectAltName =>
		n: list of ref GeneralName;
		(err, n) = decode_alias(ext);
		if(err == "")
			eclass = ref ExtClass.SubjectAltName(n);
		# either critical or non-critical
	id_ce_nameConstraints =>
		(err, eclass) = decode_nameConstraints(ext);
		# either critical or non-critical
	id_ce_policyConstraints =>
		(err, eclass) = decode_policyConstraints(ext);
		# either critical or non-critical
	id_ce_cRLNumber =>
		(err, eclass) = decode_cRLNumber(ext);
		if(err == "" && ext.critical != 0) {
			err = "crl number: should be non-critical";
			break;
		}
	id_ce_reasonCode =>
		(err, eclass) = decode_reasonCode(ext);
		if(err == "" && ext.critical != 0) {
			err = "crl reason: should be non-critical";
			break;
		}
	id_ce_instructionCode =>
		(err, eclass) = decode_instructionCode(ext);
		if(err == "" && ext.critical != 0) {
			err = "instruction code: should be non-critical";
			break;
		}
	id_ce_invalidityDate =>
		(err, eclass) = decode_invalidityDate(ext);
		if(err == "" && ext.critical != 0) {
			err = "invalidity date: should be non-critical";
			break;
		}
	id_ce_issuingDistributionPoint =>
		(err, eclass) = decode_issuingDistributionPoint(ext);
		if(err == "" && ext.critical != 1) {
			err = "issuing distribution point: should be critical";
			break;
		}
	id_ce_cRLDistributionPoint =>
		(err, eclass) = decode_cRLDistributionPoint(ext);
		# either critical or non-critical
	id_ce_certificateIssuer =>
		(err, eclass) = decode_certificateIssuer(ext);
		if(err == "" && ext.critical != 1) {
			err = "certificate issuer: should be critical";
			break;
		}
	id_ce_deltaCRLIndicator =>
		(err, eclass) = decode_deltaCRLIndicator(ext);
		if(err == "" && ext.critical != 1) {
			err = "delta crl indicator: should be critical";
			break;
		}
	id_ce_subjectDirectoryAttributes =>
		(err, eclass) = decode_subjectDirectoryAttributes(ext);
		if(ext.critical != 0) {
			err = "subject directory attributes should be non-critical";
			break;
		}
	* =>
		err = "unknown extension class";
	}

	return (err, eclass);
}

# [public]

ExtClass.encode(ec: self ref ExtClass, critical: int): ref Extension
{
	ext: ref Extension;

	if(critical)
		;	# unused
	pick c := ec {
	AuthorityKeyIdentifier =>
		(err, a) := encode_authorityKeyIdentifier(c);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_authorityKeyIdentifier], 0, a);
	SubjectKeyIdentifier =>
		(err, a) := encode_subjectKeyIdentifier(c);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_subjectKeyIdentifier], 0, a);
	BasicConstraints =>
		(err, a) := encode_basicConstraints(c);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_basicConstraints], 0, a);
	KeyUsage =>
		(err, a) := encode_keyUsage(c);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_keyUsage], 0, a);
	PrivateKeyUsage =>
		(err, a) := encode_privateKeyUsage(c);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_privateKeyUsage],	0, a);
	PolicyMapping =>
		(err, a) := encode_policyMapping(c);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_policyMapping], 0, a);
	CertificatePolicies =>
		(err, a) := encode_certificatePolicies(c);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_certificatePolicies], 0, a);
	IssuerAltName =>
		(err, a) := encode_alias(c.alias);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_issuerAltName], 0, a);
	SubjectAltName =>
		(err, a) := encode_alias(c.alias);
		if(err == "") 
			ext = ref Extension(ref objIdTab[id_ce_subjectAltName], 0, a);
	NameConstraints =>
		(err, a) := encode_nameConstraints(c);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_nameConstraints],	0, a);
	PolicyConstraints =>
		(err, a) := encode_policyConstraints(c);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_policyConstraints], 0, a);
	CRLNumber =>
		(err, a) := encode_cRLNumber(c);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_cRLNumber], 0, a);
	ReasonCode =>
		(err, a) := encode_reasonCode(c);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_reasonCode], 0, a);
	InstructionCode =>
		(err, a) := encode_instructionCode(c);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_instructionCode],	0, a);
	InvalidityDate =>
		(err, a) := encode_invalidityDate(c);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_invalidityDate], 0, a);
	CRLDistributionPoint =>
		(err, a) := encode_cRLDistributionPoint(c);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_cRLDistributionPoint], 0, a);
	IssuingDistributionPoint =>
		(err, a) := encode_issuingDistributionPoint(c);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_issuingDistributionPoint], 0, a);
	CertificateIssuer =>
		(err, a) := encode_certificateIssuer(c);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_certificateIssuer], 0, a);
	DeltaCRLIndicator =>
		(err, a) := encode_deltaCRLIndicator(c);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_deltaCRLIndicator], 0, a);
	SubjectDirectoryAttributes =>
		(err, a) := encode_subjectDirectoryAttributes(c);
		if(err == "")
			ext = ref Extension(ref objIdTab[id_ce_subjectDirectoryAttributes], 0, a);
	}
	return ext;
}

# [public]

ExtClass.tostring(et: self ref ExtClass): string
{
	s: string;

	pick t := et {
	AuthorityKeyIdentifier =>
		s = "Authority Key Identifier: ";
		s += "\n\tid = " + bastr(t.id);
		s += "\n\tissuer = " + t.issuer.tostring();
		s += "\n\tserial_number = " + bastr(t.serial_number.iptobebytes());
	SubjectKeyIdentifier =>
		s = "Subject Key Identifier ";
		s += "\n\tid = " + bastr(t.id);
	BasicConstraints =>	
		s = "Basic Constraints: ";
		s += "\n\tdepth = " + string t.depth;
	KeyUsage =>
		s = "Key Usage: ";
		s += "\n\tusage = ";
	PrivateKeyUsage =>
		s = "Private Key Usage: ";
		s += "\n\tusage = ";
	PolicyMapping =>
		s = "Policy Mapping: ";
		pl := t.pairs;
		while(pl != nil) {
			(issuer_oid, subject_oid) := hd pl;
			s += "\n\t(" + issuer_oid.tostring() + ", " + subject_oid.tostring() + ")";
			pl = tl pl;
		}
	CertificatePolicies =>
		s = "Certificate Policies: ";
		pl := t.policies;
		while(pl != nil) {
			s += (hd pl).tostring();
			pl = tl pl;
		}
	IssuerAltName =>
		s = "Issuer Alt Name: ";
		al := t.alias;
		while(al != nil) {
			s += (hd al).tostring() + ",";
			al = tl al;
		}
	SubjectAltName =>
		s = "Subject Alt Name: ";
		al := t.alias;
		while(al != nil) {
			s += (hd al).tostring() + ",";
			al = tl al;
		}		
	NameConstraints =>
		s = "Name Constraints: ";
		s += "\n\tpermitted = ";
		p := t.permitted;
		while(p != nil) {
			s += (hd p).tostring();
			p = tl p;
		}
		s += "\n\texcluded = ";
		e := t.excluded;
		while(e != nil) {
			s += (hd e).tostring();
			e = tl e;
		}
	PolicyConstraints =>
		s = "Policy Constraints: ";
		s += "\n\trequire = " + string t.require;
		s += "\n\tinhibit = " + string t.inhibit;
	CRLNumber =>
		s = "CRL Number: ";
		s += "\n\tcurrent crl number = " + string t.curr;
	ReasonCode =>
		s = "Reason Code: ";
		s += "\n\tcode = ";
	InstructionCode =>
		s = "Instruction Code: ";
		s += "\n\thold with oid = " + t.oid.tostring();
	InvalidityDate =>
		s = "Invalidity Date: ";
		s += "\n\tdate = " + daytime->text(daytime->local(t.date));
	CRLDistributionPoint =>
		s = "CRL Distribution Point: ";
		ps := t.ps;
		while(ps != nil) {
			s += (hd ps).tostring() + ",";
			ps = tl ps;
		}
	IssuingDistributionPoint =>
		s = "Issuing Distribution Point: ";
	CertificateIssuer =>
		s = "Certificate Issuer: ";
	DeltaCRLIndicator =>
		s = "Delta CRL Indicator: ";
	SubjectDirectoryAttributes =>
		s = "Subject Directory Attributes: ";
	* =>
		s = "Unknown Extension: ";
	}

	return s;
}

# [private]

decode_authorityKeyIdentifier(ext: ref Extension): (string, ref ExtClass)
{
parse:
	for(;;) {
		(err, all) := asn1->decode(ext.value);
		if(err != "")
			break parse;
		(ok, el) := all.is_seq();
		if(!ok)
			break parse;
		ak := ref ExtClass.AuthorityKeyIdentifier;
		e := hd el;
		(ok, e) = is_context(e, 0);
		if(ok) {
			(ok, ak.id) = e.is_octetstring();
			if(!ok)
				break parse;
			el = tl el;
		}
		if(el != nil && len el != 2)
			break parse;
		e = hd el;
		(ok, e) = is_context(e, 1);
		if(!ok)
			break parse;
		(ok, ak.issuer) = parse_gname(e);
		if(!ok)
			break parse;
		e = hd tl el;
		(ok, e) = is_context(e, 2);
		if(!ok)
			break parse;
		(ok, ak.serial_number) = parse_sernum(e);
		if(!ok)
			break;
		return ("", ak);
	}
	return ("syntax error", nil);	
}

# [private]

encode_authorityKeyIdentifier(c: ref ExtClass.AuthorityKeyIdentifier): (string, array of byte)
{
	el: list of ref Elem;
	if(c.serial_number != nil) {
		(ok, e) := pack_context(
				ref Elem(
					Tag(Universal, INTEGER, 0),
					ref Value.BigInt(c.serial_number.iptobebytes())
				),
				2
			);
		if(!ok)
			return ("syntax error", nil);
		el = e :: nil;
	}
	if(c.issuer != nil) {
		(ok, e) := pack_gname(c.issuer);
		if(!ok)
			return ("authority key identifier: encoding error", nil);
		(ok, e) = pack_context(e, 1);
		if(!ok)
			return ("authority key identifier: encoding error", nil);
		el = e :: el;
	}
	if(c.id != nil) {
		(ok, e) := pack_context(
				ref Elem(
					Tag(Universal, OCTET_STRING, 0),
					ref Value.Octets(c.id)
				),
				0
			);
		if(!ok)
			return ("authority key identifier: encoding error", nil);
		el = e :: el;
	}
	return asn1->encode(ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el)));
}

# [private]

decode_subjectKeyIdentifier(ext: ref Extension): (string, ref ExtClass)
{
parse:
	for(;;) {
		(err, all) := asn1->decode(ext.value);
		if(err != "")
			break parse;
		(ok, id) := all.is_octetstring();
		if(!ok)
			break parse;
		return ("", ref ExtClass.SubjectKeyIdentifier(id));

	}
	return ("subject key identifier: syntax error", nil);
}

# [private]

encode_subjectKeyIdentifier(c: ref ExtClass.SubjectKeyIdentifier): (string, array of byte)
{
	if(c.id == nil)
		return ("syntax error", nil);
	e := ref Elem(Tag(Universal, OCTET_STRING, 0), ref Value.Octets(c.id));
	return asn1->encode(e);
}

# [private]

decode_basicConstraints(ext: ref Extension): (string, ref ExtClass)
{
parse:
	for(;;) {
		(err, all) := asn1->decode(ext.value);
		if(err != "")
			break parse;
		(ok, el) := all.is_seq();
		if(!ok || len el != 2)
			break parse;
		ca: int;
		(ok, ca) = (hd el).is_int(); # boolean
		if(!ok || ca != 1)
			break parse;
		path: int;
		(ok, path) = (hd tl el).is_int(); # integer
		if(!ok || path < 0)
			break parse;		
		return ("", ref ExtClass.BasicConstraints(path));
	}
	return ("basic constraints: syntax error", nil);
}

# [private]

encode_basicConstraints(c: ref ExtClass.BasicConstraints): (string, array of byte)
{
	el: list of ref Elem;
	el = ref Elem(Tag(Universal, INTEGER, 0), ref Value.Int(c.depth)) :: nil;
	el = ref Elem(Tag(Universal, BOOLEAN, 0), ref Value.Bool(1)) :: el;
	e := ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
	return asn1->encode(e);
}

# [private]

decode_keyUsage(ext: ref Extension): (string, ref ExtClass)
{
parse:
	for(;;) {
		# assert bits can fit into a limbo int
		if(len ext.value > 4)
			break parse;
		return ("", ref ExtClass.KeyUsage(b4int(ext.value)));
	}
	return ("key usage: syntax error", nil);
}

# [private]

encode_keyUsage(c: ref ExtClass.KeyUsage): (string, array of byte)
{
	return ("", int4b(c.usage));
}

# [private]

decode_privateKeyUsage(ext: ref Extension): (string, ref ExtClass)
{
parse:
	for(;;) {
		(err, all) := asn1->decode(ext.value);
		if(err != "")
			break parse;
		(ok, el) := all.is_seq();
		if(!ok || len el < 1) # at least one exists
			break parse;
		v := ref Validity;
		e := hd el;
		(ok, e) = is_context(e, 0);
		if(ok) {
			(ok, v.not_before) = parse_time(e, GeneralizedTime);
			if(!ok)
				break parse;
			el = tl el;
		}
		if(el != nil) {
			e = hd el;
			(ok, e) = is_context(e, 1);
			if(!ok) 
				break parse;
			(ok, v.not_after) = parse_time(e, GeneralizedTime);
			if(!ok)
				break parse;
		}
		return ("", ref ExtClass.PrivateKeyUsage(v));
	}
	return ("private key usage: syntax error", nil);
}

# [private]

encode_privateKeyUsage(c: ref ExtClass.PrivateKeyUsage): (string, array of byte)
{
	el: list of ref Elem;
	e: ref Elem;
	ok := 1;
	p := c.period;
	if(p == nil)
		return ("encode private key usage: imcomplete data", nil);
	if(p.not_after > 0) {
		t := pack_time(p.not_after, GeneralizedTime);
		e = ref Elem(Tag(Universal, GeneralizedTime, 0), ref Value.String(t));
		(ok, e) = pack_context(e, 1);
		if(!ok)
			return ("encode private key usage: illegal context", nil);
		el = e :: nil;
	}
	if(p.not_before > 0) {
		t := pack_time(p.not_before, GeneralizedTime);
		e = ref Elem(Tag(Universal, GeneralizedTime, 0), ref Value.String(t));
		(ok, e) = pack_context(e, 0);
		if(!ok)
			return ("encode private key usage: illegal context", nil);
		el = e :: el;
	}
	e = ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
	return asn1->encode(e);
}

# [private]

decode_policyMapping(ext: ref Extension): (string, ref ExtClass)
{
parse:
	for(;;) {
		(err, all) := asn1->decode(ext.value);
		if(err != "")
			break parse;
		(ok, el) := all.is_seq();
		if(!ok)
			break parse;
		l_pm: list of (ref Oid, ref Oid);
		while(el != nil) {
			e_pm: list of ref Elem;
			(ok, e_pm) = (hd el).is_seq();
			if(!ok || len e_pm != 2)
				break parse;
			idp, sdp: ref Oid;
			(ok, idp) = (hd e_pm).is_oid();
			if(!ok)
				break parse;
			(ok, sdp) = (hd tl e_pm).is_oid();
			if(!ok)
				break parse;
			l_pm = (idp, sdp) :: l_pm;
		}
		# reverse the order
		l: list of (ref Oid, ref Oid);
		while(l_pm != nil) {
			l = (hd l_pm) :: l;
			l_pm = tl l_pm;
		}
		return ("", ref ExtClass.PolicyMapping(l));			
	}
	return ("policy mapping: syntax error", nil);
}

# [private]

encode_policyMapping(c: ref ExtClass.PolicyMapping): (string, array of byte)
{
	el, pel: list of ref Elem;
	if(c.pairs == nil)
		return ("policy mapping: incomplete data", nil);
	pl := c.pairs;
	while(pl != nil) {
		(a, b) := hd pl;
		if(a == nil || b == nil)
			return ("policy mapping: incomplete data", nil);
		be := ref Elem(Tag(Universal, OBJECT_ID, 0), ref Value.ObjId(b));
		ae := ref Elem(Tag(Universal, OBJECT_ID, 0), ref Value.ObjId(a));
		pel = ref Elem(
			Tag(Universal, SEQUENCE, 1), 
			ref Value.Seq(ae::be::nil)
		) :: pel;
		pl = tl pl;
	}
	while(pel != nil) {
		el = (hd pel) :: el;
		pel = tl pel;
	}
	e := ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
	return asn1->encode(e);
}

# [private]

decode_certificatePolicies(ext: ref Extension): (string, ref ExtClass)
{
parse:
	for(;;) {
		(err, all) := asn1->decode(ext.value);
		if(err != "")
			break parse;
		(ok, el) := all.is_seq();
		if(!ok)
			break parse;
		l_pi: list of ref PolicyInfo;
		while(el != nil) {
			e_pi: list of ref Elem;
			(ok, e_pi) = (hd el).is_seq();
			if(!ok || len e_pi > 2 || len e_pi < 1)
				break parse;
			pi: ref PolicyInfo;	
			(ok, pi.oid) = (hd e_pi).is_oid();
			if(!ok)
				break parse;
			# get optional policy qualifier info
			e_pi = tl e_pi;
			if(e_pi != nil) {
				e_pq: list of ref Elem;
				(ok, e_pq) = (hd e_pi).is_seq();
				if(!ok || len e_pq > 2 || len e_pq < 1)
					break parse;
				l_pq: list of ref PolicyQualifier;
				while(e_pq != nil) {
					pq: ref PolicyQualifier;
					(ok, pq.oid) = (hd e_pq).is_oid();
					if(!ok || pq.oid == nil)
						break parse;
					# get optional value
					if(tl e_pq != nil) {
						(ok, pq.value) = (hd tl e_pq).is_octetstring();
						if(!ok)
							break parse;
					}
					l_pq = pq :: l_pq;
					e_pq = tl e_pq;
				}
				# reverse the order
				while(l_pq != nil) {
					pi.qualifiers = (hd l_pq) :: pi.qualifiers;
					l_pq = tl l_pq;
				}
			}
			l_pi = pi :: l_pi;
		}
		# reverse the order
		l: list of ref PolicyInfo;
		while(l_pi != nil) {
			l = (hd l_pi) :: l;
			l_pi = tl l_pi;
		}
		return ("", ref ExtClass.CertificatePolicies(l));			
	}
	return ("certificate policies: syntax error", nil);
}

# [private]

encode_certificatePolicies(c: ref ExtClass.CertificatePolicies): (string, array of byte)
{
	el, pel: list of ref Elem;
	pl := c.policies;
	while(pl != nil) {
		p := hd pl;
		if(p.oid == nil)
			return ("certificate policies: incomplete data", nil);
		plseq: list of ref Elem;
		if(p.qualifiers != nil) {
			ql := p.qualifiers;
			qel, qlseq: list of ref Elem;
			while(ql != nil) {
				pq := hd ql;
				pqseq: list of ref Elem;
				if(pq.oid == nil)
					return ("certificate policies: incomplete data", nil);
				if(pq.value != nil) {
					pqseq = ref Elem(
							Tag(Universal, OCTET_STRING, 0),
							ref Value.Octets(pq.value)
					) :: nil;
				}
				pqseq = ref Elem(
						Tag(Universal, OBJECT_ID, 0),
						ref Value.ObjId(pq.oid)
				) :: pqseq;
				qlseq = ref Elem(
						Tag(Universal, SEQUENCE, 1),
						ref Value.Seq(pqseq)
				) :: qlseq;
				ql = tl ql;
			}
			while(qlseq != nil) {
				qel = (hd qlseq) :: qel;
				qlseq = tl qlseq;
			}
			plseq = ref Elem(
					Tag(Universal, SEQUENCE, 1),
					ref Value.Seq(qel)
			) :: nil;
		}
		plseq = ref Elem(
				Tag(Universal, OBJECT_ID, 0), 
				ref Value.ObjId(p.oid)
		) :: plseq;
		pel = ref Elem(
				Tag(Universal, SEQUENCE, 1), 
				ref Value.Seq(plseq)
		) :: pel;
		pl = tl pl;		
	}
	while(pel != nil) {
		el = (hd pel) :: el;
		pel = tl pel;
	}
	e := ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
	return asn1->encode(e);
}

# [private]

decode_alias(ext: ref Extension): (string, list of ref GeneralName)
{
parse:
	for(;;) {
		(err, all) := asn1->decode(ext.value);
		if(err != "")
			break parse;
		(ok, el) := all.is_seq();
		if(!ok)
			break parse;
		l_sa: list of ref GeneralName;
		while(el != nil) {
			gn: ref GeneralName;
			(ok, gn) = parse_gname(hd el);
			if(!ok)
				break parse;
			l_sa = gn :: l_sa;
			el = tl el;
		}
		# reverse order
		sa: list of ref GeneralName;
		while(l_sa != nil) {
			sa = (hd l_sa) :: sa;
			l_sa = tl l_sa;
		}
		return ("", sa);
	}
	return ("alias: syntax error", nil);
}

# [private]

encode_alias(gl: list of ref GeneralName): (string, array of byte)
{
	el, gel: list of ref Elem;
	while(gl != nil) {
		g := hd gl;
		(ok, e) := pack_gname(g);
		if(!ok)
			return ("alias: encoding error", nil);
		gel = e :: gel;
		gl = tl gl;
	}
	while(gel != nil) {
		el = (hd gel) :: el;
		gel = tl gel;
	}
	e := ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
	return asn1->encode(e);
}

# [private]

decode_subjectDirectoryAttributes(ext: ref Extension): (string, ref ExtClass)
{
parse:
	for(;;) {
		(err, all) := asn1->decode(ext.value);
		if(err != "")
			break parse;
		(ok, el) := all.is_seq();
		if(!ok)
			break parse;
		l_a: list of ref Attribute;
		while(el != nil) {
			a: ref Attribute;
			#(ok, a) = parse_attr(hd el);
			#if(!ok)
			#	break parse;
			l_a = a :: l_a;
			el = tl el;
		}
		# reverse order
		as: list of ref Attribute;
		while(l_a != nil) {
			as = (hd l_a) :: as;
			l_a = tl l_a;
		}
		return ("", ref ExtClass.SubjectDirectoryAttributes(as));
	}
	return ("subject directory attributes: syntax error", nil);
}

# [private]

encode_subjectDirectoryAttributes(c: ref ExtClass.SubjectDirectoryAttributes)
	: (string, array of byte)
{
	el, ael: list of ref Elem;
	al := c.attrs;
	while(al != nil) {
		(ok, e) := pack_attr(hd al);
		if(!ok)
			return ("subject directory attributes: encoding error", nil);
		ael = e :: ael;
		al = tl al;
	}
	while(ael != nil) {
		el = (hd ael) :: el;
		ael = tl ael;
	}
	e := ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
	return asn1->encode(e);
}

# [private]

decode_nameConstraints(ext: ref Extension): (string, ref ExtClass)
{
parse:
	for(;;) {
		(err, all) := asn1->decode(ext.value);
		if(err != "")
			break parse;
		(ok, el) := all.is_seq();
		if(!ok || len el < 1 || len el > 2)
			break parse;
		nc := ref ExtClass.NameConstraints;
		if(el != nil) {
			(ok, nc.permitted) = parse_gsubtrees(hd el);
			if(!ok || nc.permitted == nil)
				break parse;
			el = tl el; 
		}
		if(el!= nil) {
			(ok, nc.excluded) = parse_gsubtrees(hd el);
			if(!ok || nc.excluded == nil)
				break parse;
		}
		return ("", nc);
	}
	return ("name constraints: syntax error", nil); 
}

# [private]

encode_nameConstraints(c: ref ExtClass.NameConstraints): (string, array of byte)
{
	el: list of ref Elem;
	if(c.permitted == nil && c.excluded == nil)
		return ("name constraints: incomplete data", nil);
	if(c.excluded != nil) {
		(ok, e) := pack_gsubtrees(c.excluded);
		if(!ok)
			return ("name constraints: encoding error", nil);
		el = e :: el;
	}
	if(c.permitted != nil) {
		(ok, e) := pack_gsubtrees(c.permitted);
		if(!ok)
			return ("name constraints: encoding error", nil);
		el = e :: el;
	}
	e := ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
	return asn1->encode(e);	
}

# [private]

parse_gsubtrees(e: ref Elem): (int, list of ref GSubtree)
{
parse:
	for(;;) {
		(ok, el) := e.is_seq();
		if(!ok)
			break parse;
		l, lgs: list of ref GSubtree;
		while(el != nil) {
			gs: ref GSubtree;
			(ok, gs) = parse_gsubtree(hd el);
			if(!ok)
				break parse;
			lgs = gs :: lgs;
			el = tl el;
		}
		while(lgs != nil) {
			l = (hd lgs) :: l;
			lgs = tl lgs;
		}	 
		return (1, l);
	} 
	return (0, nil);
} 

# [private]

pack_gsubtrees(gs: list of ref GSubtree): (int, ref Elem)
{
	el, l: list of ref Elem;
	while(gs != nil) {
		(ok, e) := pack_gsubtree(hd gs);
		if(!ok)
			return (0, nil);
		l = e :: l;
	}
	while(l != nil) {
		el = (hd l) :: el;
		l = tl l;
	}
	e := ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
	return (1, e);
}

# [private]

parse_gsubtree(e: ref Elem): (int, ref GSubtree)
{
parse:
	for(;;) {
		(ok, el) := e.is_seq();
		if(!ok || len el > 3 || len el < 2)
			break parse;
		gs := ref GSubtree; 
		e = hd el;
		(ok, gs.base) = parse_gname(e);
		if(!ok)
			break parse;
		el = tl el;
		e = hd el;
		(ok, e) = is_context(e, 0);
		if(ok) {
			(ok, gs.min) = e.is_int();
			if(!ok)	
				break parse;
			el = tl el;
		}
		# get optional maximum base distance
		if(el != nil) {
			e = hd el;
			(ok, e) = is_context(e, 1);
			if(!ok)
				break parse;
			(ok, gs.max) = e.is_int();
			if(!ok)
				break parse;
		}
		return (1, gs);
	}
	return (0, nil);
}

# [private]

pack_gsubtree(g: ref GSubtree): (int, ref Elem)
{
	el: list of ref Elem;
	ok := 1;
	e: ref Elem;
	if(g.base == nil)
		return (0, nil);
	if(g.max != 0) {
		e = ref Elem(Tag(Universal, INTEGER, 0), ref Value.Int(g.max));
		(ok, e) = pack_context(e, 1);
		if(!ok)
			return (0, nil);
		el = e :: nil;
	}
	if(g.min != 0) {
		e = ref Elem(Tag(Universal, INTEGER, 0), ref Value.Int(g.min));
		(ok, e) = pack_context(e, 0);
		if(!ok)
			return (0, nil);
		el = e :: el;
	}
	(ok, e) = pack_gname(g.base);
	if(!ok)
		return (0, nil);
	el = e :: el;
	e = ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
	return (1, e);
}

# [private]

decode_policyConstraints(ext: ref Extension): (string, ref ExtClass)
{
parse:
	for(;;) {
		(err, all) := asn1->decode(ext.value);
		if(err != "")
			break parse;
		(ok, el) := all.is_seq();
		if(!ok || len el < 1 || len el > 2)
			break parse;
		pc := ref ExtClass.PolicyConstraints;
		e := hd el;
		(ok, e) = is_context(e, 0);
		if(ok) {
			(ok, pc.require) = e.is_int();
			if(!ok)
				break parse;
			el = tl el;
		}
		if(el != nil) {
			e = hd el;
			(ok, e) = is_context(e, 1);
			if(!ok)
				break parse;
			(ok, pc.inhibit) = e.is_int();
			if(!ok)
				break parse;
		} 
		return ("", pc);
	}
	return ("policy constraints: syntax error", nil);
}

# [private]

encode_policyConstraints(c: ref ExtClass.PolicyConstraints): (string, array of byte)
{
	el: list of ref Elem;
	ok := 1;
	if(c.inhibit > 0) {
		e := ref Elem(Tag(Universal, INTEGER, 0), ref Value.Int(c.inhibit));
		(ok, e) = pack_context(e, 1);
		if(!ok)
			return ("policy constraints: encoding error", nil);
		el = e :: nil;
	}
	if(c.require > 0) {
		e := ref Elem(Tag(Universal, INTEGER, 0), ref Value.Int(c.require));
		(ok, e) = pack_context(e, 0);
		if(!ok)
			return ("policy constraints: encoding error", nil);
		el = e :: el;
	}
	e := ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
	return asn1->encode(e);
}

# [private]

decode_cRLNumber(ext: ref Extension): (string, ref ExtClass)
{
parse:
	for(;;) {
		(err, all) := asn1->decode(ext.value);
		if(err != "")
			break parse;
		(ok, n) := all.is_int(); # TODO: should be IPint
		if(!ok)
			break parse;
		return ("", ref ExtClass.CRLNumber(n));
	}
	return ("crl number: syntax error", nil);
}

# [private]

encode_cRLNumber(c: ref ExtClass.CRLNumber): (string, array of byte)
{
	e := ref Elem(Tag(Universal, INTEGER, 0), ref Value.Int(c.curr));
	return asn1->encode(e);
}

# [private]

decode_reasonCode(ext: ref Extension): (string, ref ExtClass)
{
parse:
	for(;;) {
		(err, all) := asn1->decode(ext.value);
		if(err != "")
			break parse;
		(ok, un_used_bits, code) := all.is_bitstring();
		if(!ok)
			break parse;
		# no harm to ignore unused bits
		if(len code > 4)
			break parse;
		return ("", ref ExtClass.ReasonCode(b4int(code))); 
	}
	return ("crl reason: syntax error", nil);
}

# [private]

encode_reasonCode(c: ref ExtClass.ReasonCode): (string, array of byte)
{
	e := ref Elem(
			Tag(Universal, BIT_STRING, 0), 
			ref Value.BitString(0, int4b(c.code))
		);
	return asn1->encode(e);
}

# [private]

decode_instructionCode(ext: ref Extension): (string, ref ExtClass)
{
parse:
	for(;;) {
		(err, all) := asn1->decode(ext.value);
		if(err != "")
			break parse;
		(ok, code) := all.is_oid();
		if(!ok)
			break parse;
		return ("", ref ExtClass.InstructionCode(code));
	}
	return ("instruction code: syntax error", nil);
}

# [private]

encode_instructionCode(c: ref ExtClass.InstructionCode): (string, array of byte)
{
	e := ref Elem(Tag(Universal, OBJECT_ID, 0), ref Value.ObjId(c.oid));
	return asn1->encode(e);
}

# [private]

decode_invalidityDate(ext: ref Extension): (string, ref ExtClass)
{
parse:
	for(;;) {
		(err, all) := asn1->decode(ext.value);
		if(err != "")
			break parse;
		(ok, date) := all.is_time();
		if(!ok)
			break parse;
		t := decode_time(date, GeneralizedTime);
		if(t < 0)
			break parse;
		return ("", ref ExtClass.InvalidityDate(t));
	}
	return ("", nil);
}

# [private]

encode_invalidityDate(c: ref ExtClass.InvalidityDate): (string, array of byte)
{
	e := ref Elem(
			Tag(Universal, GeneralizedTime, 0), 
			ref Value.String(pack_time(c.date, GeneralizedTime))
		);
	return asn1->encode(e);
}

# [private]

decode_cRLDistributionPoint(ext: ref Extension): (string, ref ExtClass)
{
parse:
	for(;;) {
		(err, all) := asn1->decode(ext.value);
		if(err != "")
			break parse;
		(ok, el) := all.is_seq();
		if(!ok || len el < 1) # Note: at least one
			break parse;
		l, dpl: list of ref DistrPoint;
		while(el != nil) {
			dp: ref DistrPoint;
			(ok, dp) = parse_distrpoint(hd el);
			if(!ok)
				break parse;
			dpl = dp :: dpl;
		} 
		# reverse order
		while(dpl != nil) {
			l = (hd dpl) :: l;
			dpl = tl dpl;
		}
		return ("", ref ExtClass.CRLDistributionPoint(l));
	}
	return ("crl distribution point: syntax error", nil);
}

# [private]

encode_cRLDistributionPoint(c: ref ExtClass.CRLDistributionPoint): (string, array of byte)
{
	el, l: list of ref Elem;
	dpl := c.ps;
	if(dpl == nil) # at lease one
		return ("crl distribution point: incomplete data error", nil);		
	while(dpl != nil) {
		(ok, e) := pack_distrpoint(hd dpl);
		if(!ok)
			return ("crl distribution point: encoding error", nil);
		l = e :: l;
	}
	while(l != nil) {
		el = (hd l) :: el;
		l = tl l;
	}
	e := ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
	return asn1->encode(e);
}

# [private]

parse_distrpoint(e: ref Elem): (int, ref DistrPoint)
{
parse:
	for(;;) {
		(ok, el) := e.is_seq();
		if(!ok)
			break parse;
		if(!ok || len el > 3 || len el < 1)
			break parse;
		dp: ref DistrPoint;
		e = hd el;
		# get optional distribution point name
		(ok, e) = is_context(e, 0);
		if(ok) {
			(ok, dp.name) = parse_dpname(e);
			if(!ok)
				break parse;
			el = tl el;
		}
		# get optional reason flags
		if(el != nil) {
			e = hd el;
			(ok, e) = is_context(e, 1);
			if(ok) {
				unused_bits: int;
				reasons: array of byte;
				(ok, unused_bits, reasons) = e.is_bitstring();
				if(!ok)
					break parse;
				# no harm to ignore unused bits
				if(len reasons > 4)
					break parse;
				dp.reasons = b4int(reasons);
			}
			el = tl el;
		}
		# get optional crl issuer
		if(el != nil) {
			e = hd el;
			(ok, e) = is_context(e, 2);
			if(!ok)
				break parse;
			(ok, dp.issuer) = parse_lgname(e);
			if(!ok)
				break parse;
			el = tl el;
		}
		# must be no more left
		if(el != nil)
			break parse;
		return (1, dp);	
	}
	return (0, nil);
}

# [private]

pack_distrpoint(dp: ref DistrPoint): (int, ref Elem)
{
	el: list of ref Elem;
	if(dp.issuer != nil) {
		(ok, e) := pack_lgname(dp.issuer);
		if(!ok)
			return (0, nil);
		(ok, e) = pack_context(e, 2);
		if(!ok)
			return (0, nil);
		el = e :: nil;
	}
	if(dp.reasons != 0) {
		e := ref Elem(
				Tag(Universal, BIT_STRING, 0), 
				ref Value.BitString(0, int4b(dp.reasons))
			);
		ok := 1;
		(ok, e) = pack_context(e, 1);
		if(!ok)
			return (0, nil);
		el = e :: el;
	}
	if(dp.name != nil) {
		(ok, e) := pack_dpname(dp.name);
		if(!ok)
			return (0, nil);
		(ok, e) = pack_context(e, 0);
		if(!ok)
			return (0, nil);
		el = e :: el;
	}
	e := ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
	return (1, e);
}

# [private]

parse_dpname(e: ref Elem): (int, ref DistrPointName)
{
parse:
	for(;;) {
		# parse CHOICE
		ok := 0;
		(ok, e) = is_context(e, 0);
		if(ok) {
			lg: list of ref GeneralName;
			(ok, lg) = parse_lgname(e);
			if(!ok)
				break parse;
			return (1, ref DistrPointName(lg, nil));
		}
		(ok, e) = is_context(e, 1);
		if(!ok)
			break parse;
		n: ref Name;
		(ok, n) = parse_name(e);
		if(!ok)
			break parse;
		return (1, ref DistrPointName(nil, n.rd_names));
	}
	return (0, nil);
}

# [private]

pack_dpname(dpn: ref DistrPointName): (int, ref Elem)
{
	if(dpn.full_name != nil) {
		(ok, e) := pack_lgname(dpn.full_name);
		if(!ok)
			return (0, nil);
		return pack_context(e, 0);
	}
	if(dpn.rdname != nil) {
		rdn := dpn.rdname;
		el, l: list of ref Elem;
		while(rdn != nil) {
			l = pack_rdname(hd rdn) :: l;
			rdn = tl rdn;
		}
		while(l != nil) {
			el = (hd l) :: el;
			l = tl l;
		}
		e := ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
		return pack_context(e, 1);
	}
	return (0, nil);
}

# [private]

decode_issuingDistributionPoint(ext: ref Extension): (string, ref ExtClass)
{
parse:
	for(;;) {
		(err, all) := asn1->decode(ext.value);
		if(err != "")
			break parse;
		(ok, el) := all.is_seq();
		if(!ok || len el < 3 || len el > 5)
			break parse;
		ip := ref ExtClass.IssuingDistributionPoint;
		ae := hd el;
		# get optional distribution point name
		(ok, ae) = is_context(ae, 0);
		if(ok) {
			#(ok, ip.name) = parse_dpname(ae);
			if(!ok)
				break parse;
			el = tl el;
		}
		# get only contains user certs field
		if(el != nil) {
			ae = hd el;
			(ok, ae) = is_context(ae, 1);
			if(ok) {
				(ok, ip.only_usercerts) = ae.is_int(); # boolean
				if(!ok)
					break parse;
			}
			el = tl el;
		}
		# get only contains ca certs field
		if(el != nil) {
			ae = hd el;
			(ok, ae) = is_context(ae, 2);
			if(ok) {
				(ok, ip.only_cacerts) = ae.is_int(); # boolean
				if(!ok)
					break parse;
			}
			el = tl el;
		}
		# get optioinal only some reasons
		if(el != nil) {
			ae = hd el;
			(ok, ae) = is_context(ae, 3);
			if(ok) {
				reasons: array of byte;
				unused_bits: int;
				(ok, unused_bits, reasons) = ae.is_bitstring();
				if(!ok || len reasons > 4)
					break parse;
				ip.only_reasons = b4int(reasons);
			}
			el = tl el;
		}
		# get indirect crl field
		if(el != nil) {
			ae = hd el;
			(ok, ae) = is_context(ae, 4);
			if(!ok)
				break parse;
			(ok, ip.indirect_crl) = ae.is_int(); # boolean
			if(!ok)
				break parse;
			el = tl el;
		}
		# must be no more left
		if(el != nil)
			break parse;
		return ("", ip);
	}
	return ("issuing distribution point: syntax error", nil);
}

# [private]

encode_issuingDistributionPoint(c: ref ExtClass.IssuingDistributionPoint)
	: (string, array of byte)
{
	el: list of ref Elem;
	ok := 1;
	if(c.indirect_crl != 0) { # no encode for DEFAULT
		e := ref Elem(
				Tag(Universal, BOOLEAN, 0), 
				ref Value.Bool(c.indirect_crl)
			);
		(ok, e) = pack_context(e, 4);
		if(!ok)
			return ("issuing distribution point: encoding error", nil);
		el = e :: el;
	}
	if(c.only_reasons != 0) {
		e := ref Elem(
				Tag(Universal, BIT_STRING, 0),
				ref Value.BitString(0, int4b(c.only_reasons))
			);
		(ok, e) = pack_context(e, 3);
		if(!ok)
			return ("issuing distribution point: encoding error", nil);			
		el = e :: el;
	}
	if(c.only_cacerts != 0) {
		e := ref Elem(
				Tag(Universal, BOOLEAN, 0), 
				ref Value.Bool(c.only_cacerts)
			);
		(ok, e) = pack_context(e, 2);
		if(!ok)
			return ("issuing distribution point: encoding error", nil);
		el = e :: el;
	}
	if(c.only_usercerts != 0) {
		e := ref Elem(
				Tag(Universal, BOOLEAN, 0), 
				ref Value.Bool(c.only_usercerts)
			);
		(ok, e) = pack_context(e, 1);
		if(!ok)
			return ("issuing distribution point: encoding error", nil);
		el = e :: el;
	}
	if(c.name != nil) {
		e: ref Elem;
		(ok, e) = pack_dpname(c.name);
		if(!ok)
			return ("issuing distribution point: encoding error", nil);
		(ok, e) = pack_context(e, 0);
		if(!ok)
			return ("issuing distribution point: encoding error", nil);
		el = e :: el;
	}

	e := ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
	return asn1->encode(e);
}

# [private]

decode_certificateIssuer(ext: ref Extension): (string, ref ExtClass)
{
parse:
	for(;;) {
		(err, all) := asn1->decode(ext.value);
		if(err != "")
			break parse;
		(ok, el) := all.is_seq();
		if(!ok)
			break parse;
		gl, gnl: list of ref GeneralName;
		while(el != nil) {
			g: ref GeneralName;
			(ok, g) = parse_gname(hd el);
			if(!ok)
				break parse;
			gnl = g :: gnl;
			el = tl el;
		}
		while(gnl != nil) {
			gl = (hd gnl) :: gl;
			gnl = tl gnl;
		}
		return ("", ref ExtClass.CertificateIssuer(gl));
	}

	return ("certificate issuer: syntax error", nil);
}

# [private]

encode_certificateIssuer(c: ref ExtClass.CertificateIssuer): (string, array of byte)
{
	el, nel: list of ref Elem;
	ns := c.names;
	while(ns != nil) {
		(ok, e) := pack_gname(hd ns);
		if(!ok)
			return ("certificate issuer: encoding error", nil);
		nel = e :: nel;
		ns = tl ns;
	}
	while(nel != nil) {
		el = (hd nel) :: el;
		nel = tl nel;
	}
	e := ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
	return asn1->encode(e);
}

# [private]

decode_deltaCRLIndicator(ext: ref Extension): (string, ref ExtClass)
{
parse:
	for(;;) {
		(err, all) := asn1->decode(ext.value);
		if(err != "")
			break parse;
		(ok, b) := all.is_bigint();
		if(!ok)
			break parse;
		return ("", ref ExtClass.DeltaCRLIndicator(IPint.bebytestoip(b)));
	}
	return ("delta crl number: syntax error", nil);
}

# [private]

encode_deltaCRLIndicator(c: ref ExtClass.DeltaCRLIndicator): (string, array of byte)
{
	e := ref Elem(
			Tag(Universal, INTEGER, 0), 
			ref Value.BigInt(c.number.iptobebytes())
		);
	return asn1->encode(e);
}

# [public]

GeneralName.tostring(gn: self ref GeneralName): string
{
	s: string;

	pick g := gn {
	otherName => 
		s = "other name: " + g.str;
	rfc822Name =>
		s = "rfc822 name: " + g.str;
	dNSName =>
		s = "dns name: " + g.str;
	x400Address =>
		s = "x400 address: " + g.str;
	uniformResourceIdentifier =>
		s = "url: " + g.str;
	iPAddress =>
		s = "ip address: " + bastr(g.ip);
	registeredID =>
		s = "oid: " + g.oid.tostring();
	ediPartyName =>
		s = "edi party name: ";
		s += "\n\tname assigner is " + g.nameAssigner.tostring();
		s += "\n\tparty name is " + g.partyName.tostring();
	directoryName =>
		s = "directory name: " + g.dir.tostring();
	}
	return s;
}

# [public]

PolicyInfo.tostring(pi: self ref PolicyInfo): string
{
	s := "oid: " + pi.oid.tostring();
	s += "qualifiers: ";
	ql := pi.qualifiers;
	while(ql != nil) {
		s += (hd ql).tostring();
		ql = tl ql;
	}
	return s;
}

# [public]

PolicyQualifier.tostring(pq: self ref PolicyQualifier): string
{
	s := "oid: " + pq.oid.tostring();
	s += "value: " + bastr(pq.value);
	return s;
}

# [public]

GSubtree.tostring(gs: self ref GSubtree): string
{
	s := "base: " + gs.base.tostring();
	s += "range: " + string gs.min + "-" + string gs.max;
	return s;
}

# [public]

DistrPoint.tostring(dp: self ref DistrPoint): string
{
	s := "Distribution Point: ";
	s += "\n\tname = ";
	d := dp.name;
	if(d.full_name != nil) {
		f := d.full_name;
		while(f != nil) {
			s += (hd f).tostring() + ",";
			f = tl f;
		}
	}
	else {
		r := d.rdname;
		while(r != nil) {
			s += (hd r).tostring() + ",";
			r = tl r;
		}
	}
	s += "\n\treasons = " + string dp.reasons;
	s += "\n\tissuer = ";
	gl := dp.issuer;
	while(gl != nil) {
		s += (hd gl).tostring() + ",";
		gl = tl gl;
	}
	return s;
}

# [private]

is_context(e: ref Elem, num: int): (int, ref Elem)
{
	if(e.tag.class == ASN1->Context && e.tag.num == num) {
		pick v := e.val {
		Octets =>
			(err, all) := asn1->decode(v.bytes);
			if(err == "")
				return (1, all);
		}
	}
	return (0, nil);
}

# [private]

pack_context(e: ref Elem, num: int): (int, ref Elem)
{
	(err, b) := asn1->encode(e);
	if(err == "") 
		return (1, ref Elem(Tag(Context, num, 0), ref Value.Octets(b)));
	return (0, nil);
}

# [private]

parse_lgname(e: ref Elem): (int, list of ref GeneralName)
{
parse:
	for(;;) {
		(ok, el) := e.is_seq();
		if(!ok)
			break parse;
		l, lg: list of ref GeneralName;
		while(el != nil) {
			g: ref GeneralName;
			(ok, g) = parse_gname(hd el);
			if(!ok)
				break parse;
			lg = g :: lg;
			el = tl el;
		}
		while(lg != nil) {
			l = (hd lg) :: l;
			lg = tl lg;
		}
		return (1, l);
	}
	return (0, nil);
}

# [private]

pack_lgname(lg: list of ref GeneralName): (int, ref Elem)
{
	el, gel: list of ref Elem;
	while(lg != nil) {
		(ok, e) := pack_gname(hd lg);
		if(!ok)
			return (0, nil);
		gel = e :: gel;
		lg = tl lg;
	}
	while(gel != nil) {
		el = (hd gel) :: el;
		gel = tl gel;
	}
	e := ref Elem(Tag(Universal, SEQUENCE, 1), ref Value.Seq(el));
	return (1, e);
}

# [private]

parse_gname(e: ref Elem): (int, ref GeneralName)
{
parse:
	for(;;) {
		g: ref GeneralName;
		ok := 1;
		case e.tag.num {
		0 =>
			(ok, e) = is_context(e, 0);
			if(!ok)
				break parse;
			str: string;
			(ok, str) = e.is_string();
			if(!ok)
				break parse;
			g = ref GeneralName.otherName(str);
		1 =>
			(ok, e) = is_context(e, 1);
			if(!ok)
				break parse;
			str: string;
			(ok, str) = e.is_string();
			if(!ok)
				break parse;			
			g = ref GeneralName.rfc822Name(str);
		2 =>
			(ok, e) = is_context(e, 2);
			if(!ok)
				break parse;
			str: string;
			(ok, str) = e.is_string();
			if(!ok)
				break parse;
			g = ref GeneralName.dNSName(str);
		3 =>
			(ok, e) = is_context(e, 3);
			if(!ok)
				break parse;
			str: string;
			(ok, str) = e.is_string();
			if(!ok)
				break parse;
			g = ref GeneralName.x400Address(str);
		4 =>
			(ok, e) = is_context(e, 4);
			if(!ok)
				break parse;
			dir: ref Name;
			(ok, dir) = parse_name(e);
			if(!ok)
				break parse;
			g = ref GeneralName.directoryName(dir);
		5 =>
			(ok, e) = is_context(e, 5);
			if(!ok)
				break parse;
			el: list of ref Elem;
			(ok, el) = e.is_seq();
			if(!ok || len el < 1 || len el > 3)
				break parse;
			na, pn: ref Name;
			(ok, e) = is_context(hd el, 0);
			if(ok) {
				(ok, na) = parse_name(e);
				if(!ok)
					break parse;
				el = tl el;
			}
			if(el != nil) {
				(ok, e) = is_context(hd el, 1);
				if(!ok)
					break parse;
				(ok, pn) = parse_name(e);
				if(!ok)
					break parse;
			}
			g = ref GeneralName.ediPartyName(na, pn);
		6 =>
			(ok, e) = is_context(e, 6);
			if(!ok)
				break parse;
			str: string;
			(ok, str) = e.is_string();
			if(!ok)
				break parse;
			g = ref GeneralName.uniformResourceIdentifier(str);
		7 =>
			(ok, e) = is_context(e, 7);
			if(!ok)
				break parse;
			ip: array of byte;
			(ok, ip) = e.is_octetstring();
			if(!ok)
				break parse;
			g = ref GeneralName.iPAddress(ip);
		8 =>
			(ok, e) = is_context(e, 8);
			if(!ok)
				break parse;
			oid: ref Oid;
			(ok, oid) = e.is_oid();
			if(!ok)
				break parse;			
			g = ref GeneralName.registeredID(oid);
		* =>
			break parse;
		}
		return (1, g);
	}
	return (0, nil);
}

# [private]

pack_gname(gn: ref GeneralName): (int, ref Elem)
{
	e: ref Elem;
	ok := 1;

	pick g := gn {
	otherName => 
			e = ref Elem(
					Tag(Universal, GeneralString, 0),
					ref Value.String(g.str)
				); 
			(ok, e) = pack_context(e, 0);
			if(!ok)
				return (0, nil);
	rfc822Name =>
			e = ref Elem(
					Tag(Universal, IA5String, 0),
					ref Value.String(g.str)
				); 
			(ok, e) = pack_context(e, 1);
			if(!ok)
				return (0, nil);
	dNSName =>
			e = ref Elem(
					Tag(Universal, IA5String, 0),
					ref Value.String(g.str)
				); 
			(ok, e) = pack_context(e, 2);
			if(!ok)
				return (0, nil);
	x400Address =>
			e = ref Elem(
					Tag(Universal, GeneralString, 0),
					ref Value.String(g.str)
				); 
			(ok, e) = pack_context(e, 3);
			if(!ok)
				return (0, nil);
	uniformResourceIdentifier =>
			e = ref Elem(
					Tag(Universal, GeneralString, 0),
					ref Value.String(g.str)
				); 
			(ok, e) = pack_context(e, 6);
			if(!ok)
				return (0, nil);
	iPAddress =>
			e = ref Elem(
					Tag(Universal, OCTET_STRING, 0),
					ref Value.Octets(g.ip)
				); 
			(ok, e) = pack_context(e, 7);
			if(!ok)
				return (0, nil);

	registeredID =>
			e = ref Elem(
					Tag(Universal, OBJECT_ID, 0),
					ref Value.ObjId(g.oid)
				); 
			(ok, e) = pack_context(e, 8);
			if(!ok)
				return (0, nil);

	ediPartyName =>
			el: list of ref Elem;
			if(g.partyName != nil) {
				e = pack_name(g.partyName);
				(ok, e) = pack_context(e, 1);
				if(!ok)
					return (0, nil);
				el = e :: nil;
			}
			if(g.nameAssigner != nil) {
				e = pack_name(g.nameAssigner);
				(ok, e) = pack_context(e, 0);
				if(!ok)
					return (0, nil);
				el = e :: el;
			}
			e = ref Elem(
					Tag(Universal, SEQUENCE, 1),
					ref Value.Seq(el)
				); 
			(ok, e) = pack_context(e, 5);
			if(!ok)
				return (0, nil);
	directoryName =>
			e = pack_name(g.dir);
			(ok, e) = pack_context(e, 4);
			if(!ok)
				return (0, nil);			
	}
	return (1, e);
}

# [private]
# convert at most 4 bytes to int, len buf must be less than 4

b4int(buf: array of byte): int
{
	val := 0;
	for(i := 0; i < len buf; i++)
		val = (val << 8) | (int buf[i]);
	return val;	
}

# [private]

int4b(value: int): array of byte
{
	n := 4;
	buf := array [n] of byte;
	while(n--)	{   
		buf[n] = byte value;
		value >>= 8;
	}
	return buf;
}

# [private]

oid_cmp(a, b: ref Oid): int
{
	na := len a.nums;
	nb := len b.nums;
	if(na != nb)
		return 0;
	for(i := 0; i < na; i++) {
		if(a.nums[i] != b.nums[i])
			return 0;
	}
	return 1;
}

# [private]
# decode two bytes into an integer [0-99]
# return -1 for an invalid encoding

get2(a: string, i: int): int
{
	a0 := int a[i];
	a1 := int a[i+1];
	if(a0 < '0' || a0 > '9' || a1 < '0' || a1 > '9')
        	return -1;    
	return (a0 - '0')*10 + a1 - '0';
}

# [private]
# encode an integer [0-99] into two bytes

put2(a: array of byte, n, i: int): int
{
	a[i] = byte (n/10 + '0');
	a[i+1] = byte (n%10 + '0');
	return i+2;
}

# [private]

bastr(a: array of byte) : string
{
	ans := "";
	for(i := 0; i < len a; i++) {
		if(i < len a - 1 && i%10 == 0)
			ans += "\n\t\t";
		ans += sys->sprint("%2x ", int a[i]);
	}
	return ans;
}

# [private]

parse_attr(nil: ref Elem): (int, ref Attribute)
{
	return (0, nil);
}

# [private]

pack_attr(nil: ref Attribute): (int, ref Elem)
{
	return (0, nil);
}
