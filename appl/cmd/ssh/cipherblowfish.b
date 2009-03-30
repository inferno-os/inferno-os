implement Cipher;

include "sys.m";

include "keyring.m";
	kr: Keyring;
	BFstate: import kr;

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
	kr = load Keyring Keyring->PATH;
	cs = ref Cipherstate(kr->blowfishsetup(key, nil), kr->blowfishsetup(key, nil));
}

encrypt(buf: array of byte, nbuf: int)
{
	kr->blowfishcbc(cs.enc, buf, nbuf, Keyring->Encrypt);
}

decrypt(buf: array of byte, nbuf: int)
{
	kr->blowfishcbc(cs.dec, buf, nbuf, Keyring->Decrypt);
}
