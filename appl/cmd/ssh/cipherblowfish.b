implement Cipher;

include "sys.m";

include "ipints.m";
	ipints: IPints;
	IPint: import ipints;

include "crypt.m";
	crypt: Crypt;
	BFstate: import crypt;

include "sshio.m";

Cipherstate: adt
{
	enc: ref BFstate;
	dec: ref BFstate;
};

cs: ref Cipherstate;

id(): int
{
	return SSH_CIPHER_BLOWFISH;
}

init(key: array of byte, nil: int)
{
	ipints = load IPints IPints->PATH;
	crypt = load Crypt Crypt->PATH;
	cs = ref Cipherstate(crypt->blowfishsetup(key, nil), crypt->blowfishsetup(key, nil));
}

encrypt(buf: array of byte, nbuf: int)
{
	crypt->blowfishcbc(cs.enc, buf, nbuf, Crypt->Encrypt);
}

decrypt(buf: array of byte, nbuf: int)
{
	crypt->blowfishcbc(cs.dec, buf, nbuf, Crypt->Decrypt);
}
