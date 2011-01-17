implement Cipher;

include "sys.m";

include "ipints.m";
	ipints: IPints;
	IPint: import ipints;

include "crypt.m";
	crypt: Crypt;
	RC4state: import crypt;

include "sshio.m";

Cipherstate: adt
{
	enc: ref RC4state;
	dec: ref RC4state;
};

cs: ref Cipherstate;

id(): int
{
	return SSH_CIPHER_RC4;
}

init(key: array of byte, isserver: int)
{
	ipints = load IPints IPints->PATH;
	crypt = load Crypt Crypt->PATH;
	if(isserver)
		cs = ref Cipherstate(crypt->rc4setup(key[0:16]), crypt->rc4setup(key[16:32]));
	else
		cs = ref Cipherstate(crypt->rc4setup(key[16:32]), crypt->rc4setup(key[0:16]));
}

encrypt(buf: array of byte, nbuf: int)
{
	crypt->rc4(cs.enc, buf, nbuf);
}

decrypt(buf: array of byte, nbuf: int)
{
	crypt->rc4(cs.dec, buf, nbuf);
}
