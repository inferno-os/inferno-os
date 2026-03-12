#pragma	src	"/usr/inferno/libsec"

#ifndef _MPINT
typedef struct mpint mpint;
#endif

/* ===================================================== */
/* AES definitions */
/* ===================================================== */

enum
{
	AESbsize=	16,
	AESmaxkey=	32,
	AESmaxrounds=	14
};

typedef struct AESstate AESstate;
struct AESstate
{
	ulong	setup;
	int	rounds;
	int	keybytes;
	uchar	key[AESmaxkey];		/* unexpanded key */
	u32int	ekey[4*(AESmaxrounds + 1)];	/* encryption key */
	u32int	dkey[4*(AESmaxrounds + 1)];	/* decryption key */
	uchar	ivec[AESbsize];	/* initialization vector */
};

void	setupAESstate(AESstate *s, uchar key[], int keybytes, uchar *ivec);
void	aesCBCencrypt(uchar *p, int len, AESstate *s);
void	aesCBCdecrypt(uchar *p, int len, AESstate *s);
void	aesEncryptBlock(AESstate *s, uchar pt[16], uchar ct[16]);

/* ===================================================== */
/* AES-CTR */
/* ===================================================== */
void	aesCTRencrypt(uchar *p, int len, AESstate *s);
void	aesCTRdecrypt(uchar *p, int len, AESstate *s);

/* ===================================================== */
/* AES-GCM */
/* ===================================================== */
typedef struct AESGCMstate AESGCMstate;
struct AESGCMstate
{
	AESstate	a;
	uchar	hkey[AESbsize];		/* GHASH subkey */
	uchar	J0[AESbsize];		/* pre-counter block */
	u64int	htable[16*2];		/* precomputed GHASH table */
};

void	setupAESGCMstate(AESGCMstate *s, uchar *key, int keylen, uchar *iv, int ivlen);
int	aesgcm_encrypt(uchar *dat, ulong ndat, uchar *aad, ulong naad,
		uchar tag[16], AESGCMstate *s);
int	aesgcm_decrypt(uchar *dat, ulong ndat, uchar *aad, ulong naad,
		uchar tag[16], AESGCMstate *s);

/* ===================================================== */
/* ChaCha20 */
/* ===================================================== */
enum {
	ChachaBsize = 64,
	ChachaKeylen = 32
};

typedef struct ChaChastate ChaChastate;
struct ChaChastate
{
	u32int state[16];
	uchar buf[ChachaBsize];
	int blen;
	int rounds;
};

void	setupChaChastate(ChaChastate*, uchar *key, int keylen, uchar *nonce, int noncelen, int rounds);
void	chacha_encrypt(uchar *src, int n, ChaChastate *s);
void	chacha_setctr(ChaChastate *s, u32int ctr);

/* ===================================================== */
/* Poly1305 */
/* ===================================================== */
typedef struct Poly1305state Poly1305state;
struct Poly1305state
{
	u32int r[5];	/* clamped key */
	u32int h[5];	/* accumulator */
	u32int pad[4];	/* final key */
	int mlen;
	uchar mbuf[16];
};

void	setupPoly1305(Poly1305state*, uchar key[32]);
void	poly1305_update(Poly1305state*, uchar *msg, int len);
void	poly1305_finish(uchar tag[16], Poly1305state*);

/* ===================================================== */
/* ChaCha20-Poly1305 AEAD (RFC 8439) */
/* ===================================================== */
void	ccpoly_encrypt(uchar *dat, int ndat, uchar *aad, int naad,
		uchar tag[16], uchar key[32], uchar nonce[12]);
int	ccpoly_decrypt(uchar *dat, int ndat, uchar *aad, int naad,
		uchar tag[16], uchar key[32], uchar nonce[12]);

/* ===================================================== */
/* X25519 (Curve25519 ECDH, RFC 7748) */
/* ===================================================== */
void	x25519(uchar out[32], uchar scalar[32], uchar point[32]);
void	x25519_base(uchar out[32], uchar scalar[32]);

/* ===================================================== */
/* Ed25519 (RFC 8032) raw sign/verify */
/* ===================================================== */
void	ed25519_raw_sign(uchar sig[64], const uchar seed[32], const uchar *msg, ulong msglen);
int	ed25519_raw_verify(const uchar sig[64], const uchar pk[32], const uchar *msg, ulong msglen);
void	ed25519_raw_pubkey(uchar pk[32], const uchar seed[32]);

/* ===================================================== */
/* P-256 (secp256r1) ECDH + ECDSA */
/* ===================================================== */
typedef struct ECpoint ECpoint;
struct ECpoint {
	uchar x[32];
	uchar y[32];
};

int	p256_keygen(uchar priv[32], ECpoint *pub);
int	p256_ecdh(uchar shared[32], uchar priv[32], ECpoint *peerpub);
int	p256_ecdsa_sign(uchar sig[64], uchar priv[32], uchar *hash, int hashlen);
int	p256_ecdsa_verify(uchar sig[64], ECpoint *pub, uchar *hash, int hashlen);

/* ===================================================== */
/* P-384 (secp384r1) ECDSA verify only */
/* ===================================================== */
typedef struct ECpoint384 ECpoint384;
struct ECpoint384 {
	uchar x[48];
	uchar y[48];
};

int	p384_ecdsa_verify(uchar sig[96], ECpoint384 *pub, uchar *hash, int hashlen);

/* ===================================================== */
/* Blowfish Definitions */
/* ===================================================== */

enum
{
	BFbsize	= 8,
	BFrounds	= 16
};

/* 16-round Blowfish */
typedef struct BFstate BFstate;
struct BFstate
{
	ulong	setup;

	uchar	key[56];
	uchar	ivec[8];

	u32int 	pbox[BFrounds+2];
	u32int	sbox[1024];
};

void	setupBFstate(BFstate *s, uchar key[], int keybytes, uchar *ivec);
void	bfCBCencrypt(uchar*, int, BFstate*);
void	bfCBCdecrypt(uchar*, int, BFstate*);
void	bfECBencrypt(uchar*, int, BFstate*);
void	bfECBdecrypt(uchar*, int, BFstate*);

/* ===================================================== */
/* DES definitions */
/* ===================================================== */

enum
{
	DESbsize=	8
};

/* single des */
typedef struct DESstate DESstate;
struct DESstate
{
	ulong	setup;
	uchar	key[8];		/* unexpanded key */
	ulong	expanded[32];	/* expanded key */
	uchar	ivec[8];	/* initialization vector */
};

void	setupDESstate(DESstate *s, uchar key[8], uchar *ivec);
void	des_key_setup(uchar[8], ulong[32]);
void	block_cipher(ulong*, uchar*, int);
void	desCBCencrypt(uchar*, int, DESstate*);
void	desCBCdecrypt(uchar*, int, DESstate*);
void	desECBencrypt(uchar*, int, DESstate*);
void	desECBdecrypt(uchar*, int, DESstate*);

/* for backward compatibility with 7 byte DES key format */
void	des56to64(uchar *k56, uchar *k64);
void	des64to56(uchar *k64, uchar *k56);
void	key_setup(uchar[7], ulong[32]);

/* triple des encrypt/decrypt orderings */
enum {
	DES3E=		0,
	DES3D=		1,
	DES3EEE=	0,
	DES3EDE=	2,
	DES3DED=	5,
	DES3DDD=	7
};

typedef struct DES3state DES3state;
struct DES3state
{
	ulong	setup;
	uchar	key[3][8];		/* unexpanded key */
	ulong	expanded[3][32];	/* expanded key */
	uchar	ivec[8];		/* initialization vector */
};

void	setupDES3state(DES3state *s, uchar key[3][8], uchar *ivec);
void	triple_block_cipher(ulong keys[3][32], uchar*, int);
void	des3CBCencrypt(uchar*, int, DES3state*);
void	des3CBCdecrypt(uchar*, int, DES3state*);
void	des3ECBencrypt(uchar*, int, DES3state*);
void	des3ECBdecrypt(uchar*, int, DES3state*);

/* IDEA */
typedef struct IDEAstate IDEAstate;
struct IDEAstate
{
	uchar	key[16];
	ushort	edkey[104];
	uchar	ivec[8];
};

void	setupIDEAstate(IDEAstate*, uchar*, uchar*);
void	idea_key_setup(uchar*, ushort*);
void	idea_cipher(ushort*, uchar*, int);


/* ===================================================== */
/* digests */
/* ===================================================== */

enum
{
	/* digest lengths */
	SHA1dlen=	20,
	MD4dlen=	16,
	MD5dlen=	16,

	SHA224dlen=	28,
	SHA256dlen=	32,

	SHA384dlen=	48,
	SHA512dlen=	64,

	/* block sizes */
	SHA256bsize=	64,
	SHA512bsize=	128,
	Digestbsize=	128,		/* maximum */
};

typedef struct DigestState DigestState;
struct DigestState
{
	u64int len;
	u32int state[5];
	uchar buf[Digestbsize];
	int blen;
	u64int nb128[2];
	u64int h64[8];
	u32int h32[8];
	char malloced;
	char seeded;
};
typedef struct DigestState SHAstate;	/* obsolete name */
typedef struct DigestState SHA1state;
typedef struct DigestState MD5state;
typedef struct DigestState MD4state;
typedef struct DigestState SHA256state;
typedef struct DigestState SHA512state;

DigestState* md4(uchar*, ulong, uchar*, DigestState*);
DigestState* md5(uchar*, ulong, uchar*, DigestState*);
DigestState* sha1(uchar*, ulong, uchar*, DigestState*);
DigestState* sha224(uchar*, ulong, uchar*, DigestState*);
DigestState* sha256(uchar*, ulong, uchar*, DigestState*);
DigestState* sha384(uchar*, ulong, uchar*, DigestState*);
DigestState* sha512(uchar*, ulong, uchar*, DigestState*);
DigestState* hmac_md5(uchar*, ulong, uchar*, ulong, uchar*, DigestState*);
DigestState* hmac_sha1(uchar*, ulong, uchar*, ulong, uchar*, DigestState*);
DigestState* hmac_sha256(uchar*, ulong, uchar*, ulong, uchar*, DigestState*);
DigestState* hmac_sha384(uchar*, ulong, uchar*, ulong, uchar*, DigestState*);
DigestState* hmac_sha512(uchar*, ulong, uchar*, ulong, uchar*, DigestState*);
char* md5pickle(MD5state*);
MD5state* md5unpickle(char*);
char* sha1pickle(SHA1state*);
SHA1state* sha1unpickle(char*);

/* ===================================================== */
/* SHA-3 / SHAKE (FIPS 202) */
/* ===================================================== */

enum
{
	SHA3_256dlen=	32,
	SHA3_512dlen=	64,
};

typedef struct SHA3state SHA3state;
struct SHA3state
{
	u64int	a[25];		/* Keccak state (5x5 x 64-bit) */
	uchar	buf[200];	/* rate buffer */
	int	rate;		/* rate in bytes */
	int	pt;		/* buffer position */
	int	mdlen;		/* output length (0 for XOF) */
};

void	sha3_256(const uchar *in, ulong inlen, uchar out[32]);
void	sha3_512(const uchar *in, ulong inlen, uchar out[64]);
void	shake128_init(SHA3state *s);
void	shake128_absorb(SHA3state *s, const uchar *in, ulong inlen);
void	shake128_finalize(SHA3state *s);
void	shake128_squeeze(SHA3state *s, uchar *out, ulong outlen);
void	shake256_init(SHA3state *s);
void	shake256_absorb(SHA3state *s, const uchar *in, ulong inlen);
void	shake256_finalize(SHA3state *s);
void	shake256_squeeze(SHA3state *s, uchar *out, ulong outlen);
void	shake128(const uchar *in, ulong inlen, uchar *out, ulong outlen);
void	shake256(const uchar *in, ulong inlen, uchar *out, ulong outlen);

/* ===================================================== */
/* ML-KEM (FIPS 203) Key Encapsulation */
/* ===================================================== */

enum
{
	/* ML-KEM-768 (NIST Level 3) */
	MLKEM768_PKLEN=		1184,
	MLKEM768_SKLEN=		2400,
	MLKEM768_CTLEN=		1088,

	/* ML-KEM-1024 (NIST Level 5) */
	MLKEM1024_PKLEN=	1568,
	MLKEM1024_SKLEN=	3168,
	MLKEM1024_CTLEN=	1568,

	MLKEM_SSLEN=		32,
};

int	mlkem768_keygen(uchar *pk, uchar *sk);
int	mlkem768_encaps(uchar *ct, uchar *ss, const uchar *pk);
int	mlkem768_decaps(uchar *ss, const uchar *ct, const uchar *sk);
int	mlkem1024_keygen(uchar *pk, uchar *sk);
int	mlkem1024_encaps(uchar *ct, uchar *ss, const uchar *pk);
int	mlkem1024_decaps(uchar *ss, const uchar *ct, const uchar *sk);

/* internal NTT/poly functions used across mlkem_*.c files */
int16	mlkem_barrett_reduce(int16 a);
int16	mlkem_montgomery_reduce(int32 a);
int16	mlkem_cond_sub_q(int16 a);
void	mlkem_ntt(int16 r[256]);
void	mlkem_invntt(int16 r[256]);
void	mlkem_poly_basemul(int16 r[256], const int16 a[256], const int16 b[256]);
void	mlkem_poly_add(int16 r[256], const int16 a[256], const int16 b[256]);
void	mlkem_poly_sub(int16 r[256], const int16 a[256], const int16 b[256]);
void	mlkem_poly_reduce(int16 r[256]);
void	mlkem_poly_normalize(int16 r[256]);
void	mlkem_poly_sample_ntt(int16 r[256], const uchar seed[32], uchar x, uchar y);
void	mlkem_poly_sample_cbd(int16 r[256], const uchar seed[32], uchar nonce, int eta);
void	mlkem_poly_encode(uchar *out, const int16 r[256], int bits);
void	mlkem_poly_decode(int16 r[256], const uchar *in, int bits);
void	mlkem_poly_compress(int16 r[256], int d);
void	mlkem_poly_decompress(int16 r[256], int d);
void	mlkem_poly_tomont(int16 r[256]);

/* ===================================================== */
/* ML-DSA (FIPS 204) Digital Signatures */
/* ===================================================== */

enum
{
	/* ML-DSA-65 (NIST Level 3) */
	MLDSA65_PKLEN=		1952,
	MLDSA65_SKLEN=		4032,
	MLDSA65_SIGLEN=		3309,

	/* ML-DSA-87 (NIST Level 5) */
	MLDSA87_PKLEN=		2592,
	MLDSA87_SKLEN=		4896,
	MLDSA87_SIGLEN=		4627,
};

int	mldsa65_keygen(uchar *pk, uchar *sk);
int	mldsa65_sign(uchar *sig, const uchar *msg, ulong msglen, const uchar *sk);
int	mldsa65_verify(const uchar *sig, const uchar *msg, ulong msglen, const uchar *pk);
int	mldsa87_keygen(uchar *pk, uchar *sk);
int	mldsa87_sign(uchar *sig, const uchar *msg, ulong msglen, const uchar *sk);
int	mldsa87_verify(const uchar *sig, const uchar *msg, ulong msglen, const uchar *pk);

/* internal NTT/poly functions used across mldsa_*.c files */
int32	mldsa_barrett_reduce(int32 a);
int32	mldsa_montgomery_reduce(int64 a);
void	mldsa_ntt(int32 r[256]);
void	mldsa_invntt(int32 r[256]);
void	mldsa_poly_pointwise(int32 r[256], const int32 a[256], const int32 b[256]);
void	mldsa_poly_add(int32 r[256], const int32 a[256], const int32 b[256]);
void	mldsa_poly_sub(int32 r[256], const int32 a[256], const int32 b[256]);
void	mldsa_poly_reduce(int32 r[256]);

/* ===================================================== */
/* SLH-DSA (FIPS 205) Stateless Hash-Based Signatures */
/* ===================================================== */

enum
{
	/* SLH-DSA-SHAKE-192s (NIST Level 3) */
	SLHDSA192S_PKLEN=	48,
	SLHDSA192S_SKLEN=	96,
	SLHDSA192S_SIGLEN=	16224,

	/* SLH-DSA-SHAKE-256s (NIST Level 5) */
	SLHDSA256S_PKLEN=	64,
	SLHDSA256S_SKLEN=	128,
	SLHDSA256S_SIGLEN=	29792,
};

int	slhdsa192s_keygen(uchar *pk, uchar *sk);
int	slhdsa192s_sign(uchar *sig, const uchar *msg, ulong msglen, const uchar *sk);
int	slhdsa192s_verify(const uchar *sig, ulong siglen, const uchar *msg, ulong msglen, const uchar *pk);
int	slhdsa256s_keygen(uchar *pk, uchar *sk);
int	slhdsa256s_sign(uchar *sig, const uchar *msg, ulong msglen, const uchar *sk);
int	slhdsa256s_verify(const uchar *sig, ulong siglen, const uchar *msg, ulong msglen, const uchar *pk);

/* internal SLH-DSA functions used across slhdsa_*.c files */
void	slhdsa_adrs_init(uchar*);
void	slhdsa_adrs_set_layer(uchar*, u32int);
void	slhdsa_adrs_set_tree(uchar*, u64int);
void	slhdsa_adrs_set_type(uchar*, u32int);
void	slhdsa_adrs_set_keypair(uchar*, u32int);
void	slhdsa_adrs_set_chain(uchar*, u32int);
void	slhdsa_adrs_set_hash(uchar*, u32int);
void	slhdsa_adrs_set_height(uchar*, u32int);
void	slhdsa_adrs_set_index(uchar*, u32int);
void	slhdsa_adrs_copy(uchar*, const uchar*);
void	slhdsa_F(uchar*, int, const uchar*, int, const uchar*, const uchar*, int);
void	slhdsa_H(uchar*, int, const uchar*, int, const uchar*, const uchar*, int, const uchar*, int);
void	slhdsa_Tl(uchar*, int, const uchar*, int, const uchar*, const uchar*, int);
void	slhdsa_PRF(uchar*, int, const uchar*, int, const uchar*, int, const uchar*);
void	slhdsa_PRF_msg(uchar*, int, const uchar*, int, const uchar*, int, const uchar*, ulong);
void	slhdsa_H_msg(uchar*, int, const uchar*, int, const uchar*, int, const uchar*, int, const uchar*, ulong);
void	slhdsa_wots_pkgen(uchar*, int, const uchar*, int, const uchar*, int, uchar*);
void	slhdsa_wots_sign(uchar*, int, const uchar*, const uchar*, int, const uchar*, int, uchar*);
void	slhdsa_wots_pk_from_sig(uchar*, int, const uchar*, const uchar*, const uchar*, int, uchar*);
int	slhdsa_wots_len(int);
void	slhdsa_fors_sign(uchar*, int, const uchar*, const uchar*, int, const uchar*, int, uchar*, int, int);
void	slhdsa_fors_pk_from_sig(uchar*, int, const uchar*, const uchar*, const uchar*, int, uchar*, int, int);
int	slhdsa_treehash(uchar*, uchar*, int, const uchar*, int, const uchar*, int, u32int, u64int, int, int);
void	slhdsa_xmss_sign(uchar*, int, const uchar*, const uchar*, int, const uchar*, int, u32int, u64int, int, int);
void	slhdsa_xmss_root_from_sig(uchar*, int, const uchar*, int, const uchar*, const uchar*, int, u32int, u64int, int);
void	slhdsa_ht_sign(uchar*, int, const uchar*, const uchar*, int, const uchar*, int, u64int, u32int, int, int);
int	slhdsa_ht_verify(const uchar*, int, const uchar*, const uchar*, int, const uchar*, u64int, u32int, int, int);

/* ===================================================== */
/* random number generation */
/* ===================================================== */
void	genrandom(uchar *buf, int nbytes);
void	_genrandomqlock(void);
void	_genrandomqunlock(void);
void	prng(uchar *buf, int nbytes);
ulong	fastrand(void);
ulong	nfastrand(ulong);

/* ===================================================== */
/* secure memory clearing */
/* ===================================================== */
void	secureZero(void *buf, ulong nbytes);

/* ===================================================== */
/* primes */
/* ===================================================== */
void	genprime(mpint *p, int n, int accuracy); /* generate an n bit probable prime */
void	gensafeprime(mpint *p, mpint *alpha, int n, int accuracy);	/* prime and generator */
int	getdhparams(int bits, mpint *p, mpint *alpha);	/* get pre-computed RFC 3526 params */
void	genstrongprime(mpint *p, int n, int accuracy);	/* generate an n bit strong prime */
void	DSAprimes(mpint *q, mpint *p, uchar seed[SHA1dlen]);
int	probably_prime(mpint *n, int nrep);	/* miller-rabin test */
int	smallprimetest(mpint *p);		/* returns -1 if not prime, 0 otherwise */

/* ===================================================== */
/* rc4 */
/* ===================================================== */
typedef struct RC4state RC4state;
struct RC4state
{
	 uchar state[256];
	 uchar x;
	 uchar y;
};

void	setupRC4state(RC4state*, uchar*, int);
void	rc4(RC4state*, uchar*, int);
void	rc4skip(RC4state*, int);
void	rc4back(RC4state*, int);

/* ===================================================== */
/* rsa */
/* ===================================================== */
typedef struct RSApub RSApub;
typedef struct RSApriv RSApriv;
typedef struct PEMChain PEMChain;

/* public/encryption key */
struct RSApub
{
	mpint	*n;	/* modulus */
	mpint	*ek;	/* exp (encryption key) */
};

/* private/decryption key */
struct RSApriv
{
	RSApub	pub;

	mpint	*dk;	/* exp (decryption key) */

	/* precomputed values to help with chinese remainder theorem calc */
	mpint	*p;
	mpint	*q;
	mpint	*kp;	/* dk mod p-1 */
	mpint	*kq;	/* dk mod q-1 */
	mpint	*c2;	/* (inv p) mod q */
};

struct PEMChain{
	PEMChain *next;
	uchar *pem;
	int pemlen;
};

RSApriv*	rsagen(int nlen, int elen, int rounds);
RSApriv*	rsafill(mpint *n, mpint *e, mpint *d, mpint *p, mpint *q);
mpint*		rsaencrypt(RSApub *k, mpint *in, mpint *out);
mpint*		rsadecrypt(RSApriv *k, mpint *in, mpint *out);
RSApub*		rsapuballoc(void);
void		rsapubfree(RSApub*);
RSApriv*	rsaprivalloc(void);
void		rsaprivfree(RSApriv*);
RSApub*		rsaprivtopub(RSApriv*);
RSApub*		X509toRSApub(uchar*, int, char*, int);
RSApriv*	asn1toRSApriv(uchar*, int);
void		asn1dump(uchar *der, int len);
uchar*		decodePEM(char *s, char *type, int *len, char **new_s);
PEMChain*	decodepemchain(char *s, char *type);
uchar*		X509gen(RSApriv *priv, char *subj, ulong valid[2], int *certlen);
uchar*		X509req(RSApriv *priv, char *subj, int *certlen);
char*		X509verify(uchar *cert, int ncert, RSApub *pk);
void		X509dump(uchar *cert, int ncert);

/* ===================================================== */
/* elgamal */
/* ===================================================== */
typedef struct EGpub EGpub;
typedef struct EGpriv EGpriv;
typedef struct EGsig EGsig;

/* public/encryption key */
struct EGpub
{
	mpint	*p;	/* modulus */
	mpint	*alpha;	/* generator */
	mpint	*key;	/* (encryption key) alpha**secret mod p */
};

/* private/decryption key */
struct EGpriv
{
	EGpub	pub;
	mpint	*secret; /* (decryption key) */
};

/* signature */
struct EGsig
{
	mpint	*r, *s;
};

EGpriv*		eggen(int nlen, int rounds);
mpint*		egencrypt(EGpub *k, mpint *in, mpint *out);	/* deprecated */
mpint*		egdecrypt(EGpriv *k, mpint *in, mpint *out);
EGsig*		egsign(EGpriv *k, mpint *m);
int		egverify(EGpub *k, EGsig *sig, mpint *m);
EGpub*		egpuballoc(void);
void		egpubfree(EGpub*);
EGpriv*		egprivalloc(void);
void		egprivfree(EGpriv*);
EGsig*		egsigalloc(void);
void		egsigfree(EGsig*);
EGpub*		egprivtopub(EGpriv*);

/* ===================================================== */
/* dsa */
/* ===================================================== */
typedef struct DSApub DSApub;
typedef struct DSApriv DSApriv;
typedef struct DSAsig DSAsig;

/* public/encryption key */
struct DSApub
{
	mpint	*p;	/* modulus */
	mpint	*q;	/* group order, q divides p-1 */
	mpint	*alpha;	/* group generator */
	mpint	*key;	/* (encryption key) alpha**secret mod p */
};

/* private/decryption key */
struct DSApriv
{
	DSApub	pub;
	mpint	*secret; /* (decryption key) */
};

/* signature */
struct DSAsig
{
	mpint	*r, *s;
};

DSApriv*	dsagen(DSApub *opub);	/* opub not checked for consistency! */
DSAsig*		dsasign(DSApriv *k, mpint *m);
int		dsaverify(DSApub *k, DSAsig *sig, mpint *m);
DSApub*		dsapuballoc(void);
void		dsapubfree(DSApub*);
DSApriv*	dsaprivalloc(void);
void		dsaprivfree(DSApriv*);
DSAsig*		dsasigalloc(void);
void		dsasigfree(DSAsig*);
DSApub*		dsaprivtopub(DSApriv*);

/* ===================================================== */
/* TLS */
/* ===================================================== */
typedef struct Thumbprint{
	struct Thumbprint *next;
	uchar sha1[SHA1dlen];
} Thumbprint;

typedef struct TLSconn{
	char dir[40];  /* connection directory */
	uchar *cert;   /* certificate (local on input, remote on output) */
	uchar *sessionID;
	int certlen, sessionIDlen;
	int (*trace)(char*fmt, ...);
	PEMChain *chain; /* optional extra certificate evidence for servers to present */
} TLSconn;

/* tlshand.c */
int tlsClient(int fd, TLSconn *c);
int tlsServer(int fd, TLSconn *c);

/* thumb.c */
Thumbprint* initThumbprints(char *ok, char *crl);
void	freeThumbprints(Thumbprint *ok);
int		okThumbprint(uchar *sha1, Thumbprint *ok);

/* readcert.c */
uchar	*readcert(char *filename, int *pcertlen);
PEMChain *readcertchain(char *filename);
