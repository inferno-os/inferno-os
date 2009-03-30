implement Cipher;

include "sys.m";

include "keyring.m";
	kr: Keyring;
	DESstate: import kr;

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
	kr = load Keyring Keyring->PATH;
	cs = ref Cipherstate(kr->dessetup(key, nil), kr->dessetup(key, nil));
}

encrypt(buf: array of byte, nbuf: int)
{
	kr->descbc(cs.enc, buf, nbuf, Keyring->Encrypt);
}

decrypt(buf: array of byte, nbuf: int)
{
	kr->descbc(cs.dec, buf, nbuf, Keyring->Decrypt);
}
