implement Auth;

include "sys.m";
	sys: Sys;

include "ipints.m";
	ipints: IPints;
	IPint: import ipints;

include "crypt.m";
	crypt: Crypt;	# TO DO: needed to avoid compiler error

include "factotum.m";
	factotum: Factotum;

include "sshio.m";
	sshio: Sshio;
	Conn, Msg: import sshio;

id(): int
{
	return SSH_AUTH_PASSWORD;
}

init(mod: Sshio)
{
	sys = load Sys Sys->PATH;
	sshio = mod;
}

firstmsg(): int
{
	return SSH_CMSG_AUTH_PASSWORD;
}

authsrv(c: ref Conn, m: ref Msg): ref AuthInfo
{
	pass := m.getstring();
#	return auth_userpasswd(c.user, pass);
	return ref AuthInfo(c.user, nil);	# TO DO:
}

auth(c: ref Conn): int
{
	if(factotum == nil)
		factotum = load Factotum Factotum->PATH;
	(user, pass) := factotum->getuserpasswd(sys->sprint("proto=pass service=ssh server=%q user=%q", c.host, c.user));
	if(user == nil){
		sshio->debug(DBG_AUTH, "getuserpasswd failed");
		return -1;
	}

	sshio->debug(DBG_AUTH, "try using password from factotum\n");
	m := Msg.mk(SSH_CMSG_AUTH_PASSWORD, 4+Sys->UTFmax*len pass);
	m.putstring(pass);
	c.out <-= m;

	m = sshio->recvmsg(c, -1);
	case m.mtype {
	SSH_SMSG_SUCCESS =>
		return 0;
	SSH_SMSG_FAILURE =>
		return -1;
	* =>
		sshio->badmsg(m, 0, nil);
		return -1;
	}
}
