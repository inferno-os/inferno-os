implement Cipher;

include "sys.m";

include "keyring.m";
	kr: Keyring;
	DESstate: import kr;

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
	kr = load Keyring Keyring->PATH;
	cs = ref Cipherstate(array[3] of ref DESstate, array[3] of ref DESstate);
	for(i := 0; i < 3; i++){
		cs.enc[i] = kr->dessetup(key[i*8:], nil);
		cs.dec[i] = kr->dessetup(key[i*8:], nil);
	}
}

encrypt(buf: array of byte, nbuf: int)
{
	kr->descbc(cs.enc[0], buf, nbuf, Keyring->Encrypt);
	kr->descbc(cs.enc[1], buf, nbuf, Keyring->Decrypt);
	kr->descbc(cs.enc[2], buf, nbuf, Keyring->Encrypt);
}

decrypt(buf: array of byte, nbuf: int)
{
	kr->descbc(cs.dec[2], buf, nbuf, Keyring->Decrypt);
	kr->descbc(cs.dec[1], buf, nbuf, Keyring->Encrypt);
	kr->descbc(cs.dec[0], buf, nbuf, Keyring->Decrypt);
}
