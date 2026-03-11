#include "os.h"
#include <mp.h>
#include <libsec.h>

/*
 * Raw RSA public-key operation: out = in^ek mod n.
 *
 * WARNING: This is textbook RSA with NO padding (no OAEP, no PKCS#1).
 * It MUST NOT be used for direct encryption of messages.
 *
 * Current usage: RSA signature verification only (rsa_verify in rsaalg.c),
 * where the caller applies PKCS#1 v1.5 digest encoding separately.
 * If you need RSA encryption, use OAEP padding (see pkcs.b).
 */
mpint*
rsaencrypt(RSApub *rsa, mpint *in, mpint *out)
{
	if(out == nil)
		out = mpnew(0);
	mpexp(in, rsa->ek, rsa->n, out);
	return out;
}
