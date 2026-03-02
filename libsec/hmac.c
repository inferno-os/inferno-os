#include "os.h"
#include <libsec.h>

/* rfc2104 */
static DigestState*
hmac_x(uchar *p, ulong len, uchar *key, ulong klen, uchar *digest, DigestState *s,
	DigestState*(*x)(uchar*, ulong, uchar*, DigestState*), int xlen, int bsize)
{
	int i;
	uchar pad[Digestbsize+1], innerdigest[SHA512dlen];
	uchar keydigest[SHA512dlen];

	if(xlen > sizeof(innerdigest))
		return nil;
	if(bsize > Digestbsize)
		return nil;

	/* per RFC 2104: if key longer than block size, hash it first */
	if(klen > bsize){
		(*x)(key, klen, keydigest, nil);
		key = keydigest;
		klen = xlen;
	}

	/* first time through */
	if(s == nil || s->seeded == 0){
		memset(pad, 0x36, bsize);
		pad[bsize] = 0;
		for(i=0; i<klen; i++)
			pad[i] ^= key[i];
		s = (*x)(pad, bsize, nil, s);
		if(s == nil)
			return nil;
	}

	s = (*x)(p, len, nil, s);
	if(digest == nil)
		return s;

	/* last time through */
	memset(pad, 0x5c, bsize);
	pad[bsize] = 0;
	for(i=0; i<klen; i++)
		pad[i] ^= key[i];
	(*x)(nil, 0, innerdigest, s);
	s = (*x)(pad, bsize, nil, nil);
	(*x)(innerdigest, xlen, digest, s);
	return nil;
}

DigestState*
hmac_sha1(uchar *p, ulong len, uchar *key, ulong klen, uchar *digest, DigestState *s)
{
	return hmac_x(p, len, key, klen, digest, s, sha1, SHA1dlen, SHA256bsize);
}

DigestState*
hmac_md5(uchar *p, ulong len, uchar *key, ulong klen, uchar *digest, DigestState *s)
{
	return hmac_x(p, len, key, klen, digest, s, md5, MD5dlen, SHA256bsize);
}

DigestState*
hmac_sha256(uchar *p, ulong len, uchar *key, ulong klen, uchar *digest, DigestState *s)
{
	return hmac_x(p, len, key, klen, digest, s, sha256, SHA256dlen, SHA256bsize);
}

DigestState*
hmac_sha384(uchar *p, ulong len, uchar *key, ulong klen, uchar *digest, DigestState *s)
{
	return hmac_x(p, len, key, klen, digest, s, sha384, SHA384dlen, SHA512bsize);
}

DigestState*
hmac_sha512(uchar *p, ulong len, uchar *key, ulong klen, uchar *digest, DigestState *s)
{
	return hmac_x(p, len, key, klen, digest, s, sha512, SHA512dlen, SHA512bsize);
}
