implement Auth;

include "sys.m";
	sys: Sys;

include "ipints.m";
	ipints: IPints;
	IPint: import ipints;

include "crypt.m";
	crypt: Crypt;
	PK, SK: import crypt;

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
	return SSH_AUTH_RSA;
}

init(mod: Sshio)
{
	sshio = mod;
	sys = load Sys Sys->PATH;
	ipints = load IPints IPints->PATH;
	crypt = load Crypt Crypt->PATH;
	factotum = load Factotum Factotum->PATH;
	factotum->init();
}

firstmsg(): int
{
	return SSH_CMSG_AUTH_RSA;
}

authsrv(c: ref Conn, m: ref Msg): ref AuthInfo
{
	# TO DO: use factotum
	hismod := m.getipint();
	if(hismod.bits() < 512){
		debug(DBG_AUTH, sys->sprint("rsa key for %s < 512 bits\n", c.user));
		return nil;
	}
	hispk := readpk("/keydb/ssh/"+c.user);
	if(hispk == nil){
		debug(DBG_AUTH, sys->sprint("no ssh/rsa key for %s: %r\n", c.user));
		return nil;
	}
	if(!hispk.n.eq(hismod)){
		debug(DBG_AUTH, sys->sprint("%s rsa key doesn't match modulus\n", c.user));
		return nil;
	}
	# encrypt a challenge with his pk
#	chal := IPint.random(256).expmod(IPint.inttoip(1), hismod);
	chal := IPint.random(256);
	echal := crypt->rsaencrypt(hispk, x := sshio->rsapad(chal, (hispk.n.bits()+7)/8));
debug(DBG_AUTH, sys->sprint("padded %s\nrsa chal %s\n", x.iptostr(16), echal.iptostr(16)));
	m = Msg.mk(SSH_SMSG_AUTH_RSA_CHALLENGE, 2048);
	m.putipint(echal);
	c.out <-= m;

	m = sshio->recvmsg(c, SSH_CMSG_AUTH_RSA_RESPONSE);
	response := m.getbytes(Crypt->MD5dlen);
	chalbuf := array[32+SESSIDLEN] of byte;
	sshio->iptorjustbe(chal, chalbuf, 32);
	debug(DBG_AUTH, sys->sprint("\trjusted %s\n", sshio->hex(chalbuf[0:32])));
	chalbuf[32:] = c.sessid[0: SESSIDLEN];
	debug(DBG_AUTH, sys->sprint("\tappend sessid %s\n", sshio->hex(chalbuf)));
	expected := array[Crypt->MD5dlen] of byte;
	crypt->md5(chalbuf, 32+SESSIDLEN, expected, nil);
	if(sshio->eqbytes(expected, response, len expected))
		return ref AuthInfo(c.user, nil);
	return nil;
}

readpk(file: string): ref PK.RSA
{
	fd := sys->open(file, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[8192] of byte;
	nr := sys->readn(fd, buf, len buf);
	if(nr < 0)
		return nil;
	attrs := factotum->parseattrs(string buf[0: nr]);
	if(findattrval(attrs, "proto") != "rsa" ||
	   (ns := findattrval(attrs, "n")) == nil ||
	   (eks := findattrval(attrs, "ek")) == nil){
		sys->werrstr("missing rsa key attributes");
		return nil;
	}
	n := IPint.strtoip(ns, 16);
	ek := IPint.strtoip(eks, 16);
	if(n == nil || ek == nil){
		sys->werrstr("invalid rsa key values");
		return nil;
	}
	return ref PK.RSA(n, ek);
}

auth(c: ref Conn): int
{
	chalbuf := array[32+SESSIDLEN] of byte;
	response := array[Crypt->MD5dlen] of byte;

	debug(DBG_AUTH, "authrsa\n");

	afd := sys->open("/mnt/factotum/rpc", Sys->ORDWR);
	if(afd == nil){
		debug(DBG_AUTH, sys->sprint("open /mnt/factotum/rpc: %r\n"));
		return -1;
	}
	s := "proto=rsa role=client";
	if(factotum->rpc(afd, "start", array of byte s).t0 != "ok"){
		debug(DBG_AUTH, sys->sprint("auth_rpc start %s failed: %r\n", s));
		return -1;
	}

	debug(DBG_AUTH, "trying factotum rsa keys\n");
	for(;;){
		(tag, value) := factotum->rpc(afd, "read", nil);
		if(tag != "ok")
			break;
		textkey := string value;
		sshio->debug(DBG_AUTH, sys->sprint("try %q\n", textkey));
		mod := IPint.strtoip(textkey, 16);
		m := Msg.mk(SSH_CMSG_AUTH_RSA, 16+(mod.bits()+7/8));
		m.putipint(mod);
		c.out <-= m;

		m = sshio->recvmsg(c, -1);
		case m.mtype {
		SSH_SMSG_FAILURE =>
			debug(DBG_AUTH, "\tnot accepted\n");
			continue;
		SSH_SMSG_AUTH_RSA_CHALLENGE =>
			;
		* =>
			sshio->badmsg(m, 0, nil);
		}
		chal := m.getipint();
		p := chal.iptostr(16);
		debug(DBG_AUTH, sys->sprint("\tgot challenge %s\n", p));
		unpad: ref IPint;
		if(factotum->rpc(afd, "write", array of byte p).t0 == "ok" &&
		   ((tag, value) = factotum->rpc(afd, "read", nil)).t0 == "ok"){
			debug(DBG_AUTH, sys->sprint("\tfactotum said %q\n", string value));
			decr := IPint.strtoip(string value, 16);
			if(decr != nil){
				debug(DBG_AUTH, sys->sprint("\tdecrypted %s\n", decr.iptostr(16)));
				unpad = sshio->rsaunpad(decr);
			}else
				unpad = IPint.inttoip(0);
		}else{
			debug(DBG_AUTH, sys->sprint("\tauth_rpc write or read failed: %r\n"));
			unpad = IPint.inttoip(0);	# it will fail, we'll go round again
		}
		debug(DBG_AUTH, sys->sprint("\tunpadded %s\n", unpad.iptostr(16)));
		sshio->iptorjustbe(unpad, chalbuf, 32);
#		debug(DBG_AUTH, sys->sprint("\trjusted %.*H\n", 32, chalbuf));
		chalbuf[32:] = c.sessid[0: SESSIDLEN];
#		debug(DBG_AUTH, sys->sprint("\tappend sesskey %.*H\n", 32, chalbuf));
		crypt->md5(chalbuf, 32+SESSIDLEN, response, nil);

		m = Msg.mk(SSH_CMSG_AUTH_RSA_RESPONSE, Crypt->MD5dlen);
		m.putbytes(response, Crypt->MD5dlen);
		c.out <-= m;

		m = sshio->recvmsg(c, -1);
		case m.mtype {
		SSH_SMSG_FAILURE =>
			;	# retry
		SSH_SMSG_SUCCESS =>
			return 0;
		* =>
			sshio->badmsg(m, 0, nil);
		}
	}
	return -1;
}
