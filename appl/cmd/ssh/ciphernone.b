implement Cipher;

include "sys.m";

include "ipints.m";
	ipints: IPints;
	IPint: import ipints;

include "crypt.m";

include "sshio.m";

id(): int
{
	return SSH_CIPHER_NONE;
}

init(nil: array of byte, nil: int)
{
}

encrypt(nil: array of byte, nil: int)
{
}

decrypt(nil: array of byte, nil: int)
{
}
