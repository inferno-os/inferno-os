implement Cipher;

include "sys.m";

include "ipints.m";
	ipints: IPints;
	IPint: import ipints;

include "crypt.m";
	crypt: Crypt;
	DESstate: import crypt;

include "sshio.m";

Cipherstate: adt
{
	enc: ref DESstate;
	dec: ref DESstate;
};

cs: ref Cipherstate;

id(): int
{
	return SSH_CIPHER_DES;
}

init(key: array of byte, nil: int)
{
	ipints = load IPints IPints->PATH;
	crypt = load Crypt Crypt->PATH;
	cs = ref Cipherstate(crypt->dessetup(key, nil), crypt->dessetup(key, nil));
}

encrypt(buf: array of byte, nbuf: int)
{
	crypt->descbc(cs.enc, buf, nbuf, Crypt->Encrypt);
}

decrypt(buf: array of byte, nbuf: int)
{
	crypt->descbc(cs.dec, buf, nbuf, Crypt->Decrypt);
}
