implement Sshserve;

include "sys.m";
	sys: Sys;

include "draw.m";

include "ipints.m";
	ipints: IPints;
	IPint: import ipints;

include "crypt.m";
	crypt: Crypt;
	PK, SK: import crypt;

include "env.m";
	env: Env;

include "sh.m";
	sh: Sh;

include "wait.m";
	wait: Wait;

include "arg.m";

include "sshio.m";
	sshio: Sshio;
	Conn, Msg: import sshio;
	recvmsg: import sshio;
	error, debug: import sshio;

Sshserve: module
{
	init: fn(nil: ref Draw->Context, argl: list of string);
};

AuthRpc: adt {};
debuglevel := 0;

cipherlist := "blowfish rc4 3des";
ciphers: list of Cipher;

authlist := "rsa password tis";
authsrvs: list of Auth;

maxmsg := 256*1024;

serverpriv: ref SK.RSA;
serverkey: ref PK.RSA;
hostpriv: ref SK.RSA;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	ipints = load IPints IPints->PATH;
	crypt = load Crypt Crypt->PATH;
	env = load Env Env->PATH;
	sh = load Sh Sh->PATH;
	sshio = load Sshio Sshio->PATH;
	sshio->init();
	wait = load Wait Wait->PATH;
	wait->init();
#	fmtinstall('B', mpfmt);
#	fmtinstall('H', encodefmt);
	sys->pctl(Sys->NEWPGRP|Sys->FORKFD|Sys->FORKNS|Sys->FORKENV, nil);
	keyfile: string;
	arg := load Arg Arg->PATH;
	arg->setusage("sshserve [-A authlist] [-c cipherlist] [-k keyfile] client-ip-address");
	arg->init(args);
	while((o := arg->opt()) != 0){
		case o {
		'D' =>
			debuglevel = int arg->earg();
		'A' =>
			authlist = arg->earg();
		'c' =>
			cipherlist = arg->earg();
		'k' =>
			keyfile = arg->earg();
		* =>
			arg->usage();
		}
	}
	args = arg->argv();
	if(len args != 1)
		arg->usage();
	arg = nil;

	sys->dup(2, 1);
#	if(keyfile != nil)
#		;	# read hostpriv from file
#	sshlog("connect from %s", c.host);
	authsrvs = loadlist("auth", authlist, authload);
	ciphers = loadlist("cipher", cipherlist, cipherload);
	hostpriv = crypt->rsagen(1024, 6, 0);
	serverpriv = crypt->rsagen(768, 6, 0);
	serverkey = serverpriv.pk;
	{
		versioning(sys->fildes(0));
		c := Conn.mk(hd args, sys->fildes(0));
		c.setkey(hostpriv.pk);
		authenticate(c);
		comms(c);
	}exception e{
	"fail:*" =>
		raise e;
	"error*" =>
		notegrp(sys->pctl(0, nil), "error");
		raise "fail:"+e;
	}
}

authload(f: string): Auth
{
	return load Auth f;
}

cipherload(f: string): Cipher
{
	return load Cipher f;
}

loadlist[T](sort: string, set: string, loadf: ref fn(f: string): T): list of T
{
	l: list of T;
	(nil, fld) := sys->tokenize(set, " \t,");
	for(; fld != nil; fld = tl fld){
		f := "/dis/ssh/"+sort+hd fld+".dis";
		m := loadf(f);
		if(m == nil)
			error(sys->sprint("unknown %s scheme %s (%s)", sort, hd fld, f));
		l = m :: l;
	}
	return l;
}

comms(c: ref Conn)
{
	(kidpid, infd, waiting) := prelude(c);
Work:
	for(;;)alt{
	(m, nil) := <-c.in =>
		if(m == nil){
			notegrp(kidpid, "hungup");
			exit;
		}
		case m.mtype {
		* =>
			sshio->badmsg(m, 0, nil);
		SSH_MSG_DISCONNECT =>
			notegrp(kidpid, "hungup");
			sysfatal("client disconnected");
		SSH_CMSG_STDIN_DATA =>
			if(infd != nil){
				n := m.get4();
				sys->write(infd, m.getbytes(n), n);
			}
		SSH_CMSG_EOF =>
			infd = nil;
		SSH_CMSG_EXIT_CONFIRMATION =>
			#  sent by some clients as dying breath
			notegrp(kidpid, "hungup");
			break Work;
		SSH_CMSG_WINDOW_SIZE =>
			;	#  we don't care 
		}
	(pid, nil, status) := <-waiting =>
		if(pid == kidpid){
			if(status != "" && status != "0"){
				m := Msg.mk(SSH_MSG_DISCONNECT, 4+Sys->UTFmax*len status);
				m.putstring(status);
				sendmsg(c, m);
			}else{
				m := Msg.mk(SSH_SMSG_EXITSTATUS, 4);
				m.put4(0);
				sendmsg(c, m);
			}
			sendmsg(c, nil);
			break Work;
		}
	}
	notegrp(sys->pctl(0, nil), "done");
}

prelude(c: ref Conn): (int, ref Sys->FD, chan of (int, string, string))
{
	for(;;){
		m := recvmsg(c, -1);
		if(m == nil)
			return (-1, nil, nil);
		case m.mtype {
		* =>
			sendmsg(c, Msg.mk(SSH_SMSG_FAILURE, 0));
		SSH_MSG_DISCONNECT =>
			sysfatal("client disconnected");
		SSH_CMSG_REQUEST_PTY =>
			sendmsg(c, Msg.mk(SSH_SMSG_SUCCESS, 0));
		SSH_CMSG_MAX_PACKET_SIZE =>
			n := m.get4();
			if(n >= 32 && n <= SSH_MAX_MSG){
				maxmsg = n;
				sendmsg(c, Msg.mk(SSH_SMSG_SUCCESS, 0));
			}else
				sendmsg(c, Msg.mk(SSH_SMSG_FAILURE, 0));
		SSH_CMSG_EXEC_SHELL =>
			return startcmd(c, nil);
		SSH_CMSG_EXEC_CMD =>
			cmd := m.getstring();
			return startcmd(c, cmd);
		}
	}
}

copyout(c: ref Conn, fd: ref Sys->FD, mtype: int)
{
	buf := array[8192] of byte;
	max := len buf;
	if(max > maxmsg-32)	#  32 is an overestimate of packet overhead 
		max = maxmsg-32;
	if(max <= 0)
		sysfatal("maximum message size too small");
	while((n := sys->read(fd, buf, max)) > 0){
		m := Msg.mk(mtype, 4+n);
		m.put4(n);
		m.putbytes(buf, n);
		sendmsg(c, m);
	}
}

send_ssh_smsg_public_key(c: ref Conn, cookie: array of byte)
{
	m := Msg.mk(SSH_SMSG_PUBLIC_KEY, 2048);
	m.putbytes(cookie, COOKIELEN);
	m.putpk(serverkey);
	m.putpk(c.hostkey);
	m.put4(c.flags);
	ciphermask := 0;
	for(l1 := ciphers; l1 != nil; l1 = tl l1)
		ciphermask |= 1<<(hd l1)->id();
	m.put4(ciphermask);
	authmask := 0;
	for(l2 := authsrvs; l2 != nil; l2 = tl l2)
		authmask |= 1<<(hd l2)->id();
	m.put4(authmask);
	sendmsg(c, m);
}

rpcdecrypt(rpc: ref AuthRpc, b: ref IPint): ref IPint
{
	raise "rpcdecrypt";
#	p := array of byte b.iptostr(16);
#	if(auth_rpc(rpc, "write", p, len p) != ARok)
#		sysfatal("factotum rsa write: %r");
#	if(auth_rpc(rpc, "read", nil, 0) != ARok)
#		sysfatal("factotum rsa read: %r");
#	return strtomp(rpc.arg, nil, 16, nil);
}

recv_ssh_cmsg_session_key(c: ref Conn, rpc: ref AuthRpc, cookie: array of byte)
{
	m := recvmsg(c, SSH_CMSG_SESSION_KEY);
	id := m.get1();
	c.cipher = nil;
	for(l := ciphers; l != nil; l = tl l)
		if((hd l)->id() == id){
			c.cipher = hd l;
			break;
		}
	if(c.cipher == nil)
		sysfatal(sys->sprint("invalid cipher %d selected", id));
	if(!sshio->eqbytes(m.getbytes(COOKIELEN), cookie, len cookie))
		sysfatal("bad cookie");
	serverkeylen := serverkey.n.bits();
	hostkeylen := c.hostkey.n.bits();
	ksmall, kbig: ref SK.RSA;
	if(serverkeylen+128 <= hostkeylen){
		ksmall = serverpriv;
		kbig = nil;
	}else if(hostkeylen+128 <= serverkeylen){
		ksmall = nil;
		kbig = serverpriv;
	}else
		sysfatal("server session and host keys do not differ by at least 128 bits");
	b := m.getipint();
	debug(DBG_CRYPTO, sys->sprint("encrypted with kbig is %s\n", b.iptostr(16)));
	if(kbig != nil)
		b = sshio->rsadecrypt(kbig, b);
	else
#		b = rpcdecrypt(rpc, b);
		b = sshio->rsadecrypt(hostpriv, b);
	b = sshio->rsaunpad(b);
	sshio->debug(DBG_CRYPTO, sys->sprint("encrypted with ksmall is %s\n", b.iptostr(16)));
	if(ksmall != nil)
		b = sshio->rsadecrypt(ksmall, b);
	else
#		b = rpcdecrypt(rpc, b);
		b = sshio->rsadecrypt(hostpriv, b);
	b = sshio->rsaunpad(b);
	debug(DBG_CRYPTO, sys->sprint("munged is %s\n", b.iptostr(16)));
	n := (b.bits()+7)/8;
	if(n < SESSKEYLEN)
		sysfatal("client sent short session key");
	buf := array[SESSKEYLEN] of byte;
	sshio->iptorjustbe(b, buf, SESSKEYLEN);
	for(i := 0; i < SESSIDLEN; i++)
		buf[i] ^= c.sessid[i];
	c.sesskey[0: ] = buf[0: SESSKEYLEN];
	debug(DBG_CRYPTO, sys->sprint("unmunged is %.*s\n", SESSKEYLEN*2, sshio->hex(buf)));
	c.flags = m.get4();
}

authsrvuser(c: ref Conn)
{
	m := recvmsg(c, SSH_CMSG_USER);
	user := m.getstring();
	c.user = user;
	inited := 0;
	ai: ref Auth->AuthInfo;
	while(authsrvs != nil && ai == nil){
#		# 
#		# 		 * clumsy: if the client aborted the auth_tis early
#		# 		 * we don't send a new failure.  we check this by
#		# 		 * looking at c->unget, which is only used in that
#		# 		 * case.
#		# 		 
		if(c.unget == nil)
			sendmsg(c, Msg.mk(SSH_SMSG_FAILURE, 0));
		m = recvmsg(c, -1);
		for(l := authsrvs; l != nil; l = tl l)
			if((hd l)->firstmsg() == m.mtype){
				bit := 1 << (hd l)->id();
				if((inited & bit) == 0){
					(hd l)->init(sshio);
					inited |= bit;
				}
				ai = (hd l)->authsrv(c, m);
				break;
			}
		if(l == nil)
			sshio->badmsg(m, 0, nil);
	}
	sendmsg(c, Msg.mk(SSH_SMSG_SUCCESS, 0));
#	if(noworld(ai.cuid))
#		ns := "/lib/namespace.noworld";
#	else
#		ns = nil;
#	if(auth_chuid(ai, ns) < 0){
#		sshlog("auth_chuid to %s: %r", ai.cuid);
#		sysfatal("auth_chuid: %r");
#	}
#	sshlog("logged in as %q", ai.user);
	if(ai != nil)
		sys->print("logged in as %q\n", ai.user);
}

keyjunk()
{
	p: array of byte;
	m: ref IPint;
	rpc: ref AuthRpc;
	key: ref PK.RSA;

#	# 
#	# BUG: should use `attr' to get the key attributes
#	# after the read, but that's not implemented yet.
#	# 	 
#	if((b = Bopen("/mnt/factotum/ctl", OREAD)) == nil)
#		sysfatal("open /mnt/factotum/ctl: %r");
#	while((p = Brdline(b, '\n')) != nil){
#		if(strstr(p, " proto=rsa ") != nil && strstr(p, " service=sshserve ") != nil)
#			break;
#	}
#	if(p == nil)
#		sysfatal("no sshserve keys found in /mnt/factotum/ctl");
#	a = _parseattr(p);
#	Bterm(b);
#	key = rsaprivalloc();
#	if((p = _strfindattr(a, "n")) == nil)
#		sysfatal("no n in sshserve key");
#	if((key.n = IPint.strtoip(p, 16)) == nil)
#		sysfatal("bad n in sshserve key");
#	if((p = _strfindattr(a, "ek")) == nil)
#		sysfatal("no ek in sshserve key");
#	if((key.ek = IPint.strtoip(p, 16)) == nil)
#		sysfatal("bad ek in sshserve key");
#	_freeattr(a);
#	if((afd = sys->open("/mnt/factotum/rpc", ORDWR)) == nil)
#		sysfatal("open /mnt/factotum/rpc: %r");
#	if((rpc = auth_allocrpc(afd)) == nil)
#		sysfatal("auth_allocrpc: %r");
#	p = "proto=rsa role=client service=sshserve";
#	if(auth_rpc(rpc, "start", p, len p) != ARok)
#		sysfatal("auth_rpc start %s: %r", p);
#	if(auth_rpc(rpc, "read", nil, 0) != ARok)
#		sysfatal("auth_rpc read: %r");
#	m = strtomp(rpc.arg, nil, 16, nil);
#	if(mpcmp(m, key.n) != 0)
#		sysfatal("key in /mnt/factotum/ctl does not match rpc key");
#	mpfree(m);
#	c.hostkey = key;
}

versioning(fd: ref Sys->FD)
{
	sys->fprint(fd, "SSH-1.5-Inferno\n");
	(maj, min, err_or_id) := sshio->readversion(fd);
	if(maj < 0)
		sysfatal(err_or_id);
	if(maj != 1 || min < 5)
		sysfatal(sys->sprint("protocol mismatch; got %s, need SSH-1.x for x >= 5", err_or_id));
}

authenticate(c: ref Conn)
{
	rpc: ref AuthRpc;

	cookie := array[COOKIELEN] of {* => byte sshio->fastrand()};
	c.sessid = sshio->calcsessid(c.hostkey.n, serverkey.n, cookie);
	send_ssh_smsg_public_key(c, cookie);
	recv_ssh_cmsg_session_key(c, rpc, cookie);
#	afd = nil;
	c.cipher->init(c.sesskey, 1);	#  turns on encryption 
	sendmsg(c, Msg.mk(SSH_SMSG_SUCCESS, 0));
	authsrvuser(c);
}

startcmd(c: ref Conn, cmd: string): (int, ref Sys->FD, chan of (int, string, string))
{
	pfd := array[3] of {* => array[2] of ref Sys->FD};
	for(i := 0; i < 3; i++)
		if(sys->pipe(pfd[i]) < 0)
			sysfatal(sys->sprint("pipe: %r"));
	wfd := sys->open("#p/"+string sys->pctl(0, nil)+"/wait", Sys->OREAD);
	if(wfd == nil)
		sysfatal(sys->sprint("open wait: %r"));
	pidc := chan of int;
	spawn startcmd1(c, cmd, pfd, pidc);
	kidpid := <-pidc;
	(nil, waited) := wait->monitor(wfd);
	spawn copyout(c, pfd[1][0], SSH_SMSG_STDOUT_DATA);
	pfd[1][0] = nil;
	spawn copyout(c, pfd[2][0], SSH_SMSG_STDERR_DATA);
	pfd[2][0] = nil;
	return (kidpid, pfd[0][0], waited);
}

startcmd1(c: ref Conn, cmd: string, pfd: array of array of ref Sys->FD, pidc: chan of int)
{
	sysname := env->getenv("sysname");
	tz := env->getenv("timezone");
	sys->pctl(Sys->FORKFD, nil);
	for(i := 0; i < len pfd; i++)
		if(sys->dup(pfd[i][1].fd, i) < 0)
			sysfatal(sys->sprint("dup: %r"));
	pfd = nil;
	sys->pctl(Sys->NEWPGRP|Sys->FORKNS|Sys->FORKENV|Sys->NEWFD, 0::1::2::nil);
	pidc <-= sys->pctl(0, nil);
	env->setenv("user", c.user);
	if(sysname != nil)
		env->setenv("sysname", sysname);
	if(tz != nil)
		env->setenv("tz", tz);
	if(sys->chdir("/usr/"+c.user) < 0)
		sys->chdir("/");
	if(cmd != nil){
		env->setenv("service", "rx");
		status := sh->run(nil, list of {"/dis/sh.dis", "-lc", cmd});
		if(status != nil)
			raise "fail:"+status;
	}else{
		env->setenv("service", "con");
		#execl("/bin/ip/telnetd", "telnetd", "-tn", nil);	# TO DO: just for echo and line editing
		sys->fprint(sys->fildes(2), "sshserve: cannot run /dis/ip/telnetd: %r");
	}
}

sysfatal(s: string)
{
	sys->print("sysfatal: %s\n", s);
	notegrp(sys->pctl(0, nil), "zap");
	exit;
}

notegrp(pid: int, nil: string)
{
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "killgrp");
}

sendmsg(c: ref Conn, m: ref Msg)
{
	c.out <-= m;
}
