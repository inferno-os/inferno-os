implement Auth;

# TO DO: add chal/resp to Factotum

include "sys.m";
	sys: Sys;

include "ipints.m";
	ipints: IPints;
	IPint: import ipints;

include "crypt.m";
	crypt: Crypt;	# avoid compiler error

include "factotum.m";
	factotum: Factotum;
	Attr: import factotum;
	findattrval: import factotum;

include "sshio.m";
	sshio: Sshio;
	Conn, Msg: import sshio;
	debug: import sshio;

id(): int
{
	return SSH_AUTH_TIS;
}

init(mod: Sshio)
{
	sshio = mod;
	sys = load Sys Sys->PATH;
	ipints = load IPints IPints->PATH;
	factotum = load Factotum Factotum->PATH;
	factotum->init();
}

firstmsg(): int
{
	return SSH_CMSG_AUTH_TIS;
}

authsrv(conn: ref Conn, nil: ref Msg): ref AuthInfo
{
	if((c := factotum->challenge(sys->sprint("proto=p9cr user=%q role=server", conn.user))) == nil){
#		sshlog("auth_challenge failed for %s", conn.user);
		return nil;
	}
	s := sys->sprint("Challenge: %s\nResponse: ", c.chal);
	m := Msg.mk(SSH_SMSG_AUTH_TIS_CHALLENGE, 4+len s);
	m.putstring(s);
	conn.out <-= m;

	m = sshio->recvmsg(conn, 0);
	if(m == nil)
		return nil;
	if(m.mtype != SSH_CMSG_AUTH_TIS_RESPONSE){
		#
		# apparently you can just give up on
		# this protocol and start a new one.
		#
		sshio->unrecvmsg(conn, m);
		return nil;
	}

	ai := factotum->response(c, m.getstring());
	if(ai == nil){
		debug(DBG_AUTH, sys->sprint("response rejected: %r\n"));
		return nil;
	}
	return ref AuthInfo(ai.cuid, ai.cap);
}

auth(c: ref Conn): int
{
	if(!c.interactive)
		return -1;

	debug(DBG_AUTH, "try TIS\n");
	c.out <-= Msg.mk(SSH_CMSG_AUTH_TIS, 0);

	m := sshio->recvmsg(c, -1);
	case m.mtype {
	SSH_SMSG_FAILURE =>
		return -1;
	SSH_SMSG_AUTH_TIS_CHALLENGE =>
		;
	* =>
		sshio->badmsg(m, SSH_SMSG_AUTH_TIS_CHALLENGE, nil);
	}

	chal := m.getstring();

	if((fd := sys->open("/dev/cons", Sys->ORDWR)) == nil)
		sshio->error(sys->sprint("can't open /dev/cons: %r"));

	sys->fprint(fd, "TIS Authentication\n%s", chal);
	resp := array[256] of byte;
	n := sys->read(fd, resp, len resp);
	if(n <= 0 || resp[0] == byte '\n')
		return -1;

	m = Msg.mk(SSH_CMSG_AUTH_TIS_RESPONSE, 4+n);
	m.put4(len resp);
	m.putbytes(resp, n);
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
