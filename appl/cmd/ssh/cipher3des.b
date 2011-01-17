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
	enc: array of ref DESstate;
	dec: array of ref DESstate;
};

cs: ref Cipherstate;

id(): int
{
	return SSH_CIPHER_3DES;
}

init(key: array of byte, nil: int)
{
	ipints = load IPints IPints->PATH;
	crypt = load Crypt Crypt->PATH;
	cs = ref Cipherstate(array[3] of ref DESstate, array[3] of ref DESstate);
	for(i := 0; i < 3; i++){
		cs.enc[i] = crypt->dessetup(key[i*8:], nil);
		cs.dec[i] = crypt->dessetup(key[i*8:], nil);
	}
}

encrypt(buf: array of byte, nbuf: int)
{
	crypt->descbc(cs.enc[0], buf, nbuf, Crypt->Encrypt);
	crypt->descbc(cs.enc[1], buf, nbuf, Crypt->Decrypt);
	crypt->descbc(cs.enc[2], buf, nbuf, Crypt->Encrypt);
}

decrypt(buf: array of byte, nbuf: int)
{
	crypt->descbc(cs.dec[2], buf, nbuf, Crypt->Decrypt);
	crypt->descbc(cs.dec[1], buf, nbuf, Crypt->Encrypt);
	crypt->descbc(cs.dec[0], buf, nbuf, Crypt->Decrypt);
}
