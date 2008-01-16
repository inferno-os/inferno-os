implement Authproto;

# currently includes p9sk1

include "sys.m";
	sys: Sys;
	Rread, Rwrite: import Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "auth9.m";
	auth9: Auth9;
	ANAMELEN, AERRLEN, DOMLEN, DESKEYLEN, CHALLEN, SECRETLEN: import Auth9;
	TICKREQLEN, TICKETLEN, AUTHENTLEN: import Auth9;
	Ticketreq, Ticket, Authenticator: import auth9;

include "../authio.m";
	authio: Authio;
	Aattr, Aval, Aquery: import Authio;
	Attr, IO, Key, Authinfo: import authio;
	netmkaddr, eqbytes, memrandom: import authio;

include "encoding.m";
	base16: Encoding;

Debug: con 0;

# init, addkey, closekey, write, read, close, keyprompt

init(f: Authio): string
{
	authio = f;
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	auth9 = load Auth9 Auth9->PATH;
	auth9->init();
	base16 = load Encoding Encoding->BASE16PATH;
	return nil;
}

version := 1;

interaction(attrs: list of ref Attr, io: ref IO): string
{
	return p9any(io);
}

p9any(io: ref IO): string
{
	while((buf := io.read()) == nil || (n := len buf) == 0 || buf[n-1] != byte 0)
		io.toosmall(2048);
	s := string buf[0:n-1];
	if(Debug)
		sys->print("s: %q\n", s);
	(nil, flds) := sys->tokenize(s, " \t");
	if(flds != nil && len hd flds >= 2 && (hd flds)[0:2] == "v."){
		if(hd flds == "v.2"){
			version = 2;
			flds = tl flds;
			if(Debug)
				sys->print("version 2\n");
		}else
			return "p9any: unknown version";
	}
	doms: list of string;
	for(; flds != nil; flds = tl flds){
		(nf, subf) := sys->tokenize(hd flds, "@");
		if(nf == 2 && hd subf == "p9sk1")
			doms = hd tl subf :: doms;
	}
	if(doms == nil)
		return "p9any: unsupported protocol";
	if(Debug){
		for(l := doms; l != nil; l = tl l)
			sys->print("dom: %q\n", hd l);
	}
	r := array of byte ("p9sk1 "+hd doms);
	buf[0:] = r;
	buf[len r] = byte 0;
	io.write(buf, len r + 1);
	if(version == 2){
		b := io.readn(3);
		if(b == nil || b[0] != byte 'O' || b[1] != byte 'K' || b[2] != byte 0)
			return "p9any: AS protocol botch: not OK";
		if(Debug)
			sys->print("OK\n");
	}
	return p9sk1client(io, hd doms);
}

#p9sk1:
#	C->S:	nonce-C
#	S->C:	nonce-S, uid-S, domain-S
#	C->A:	nonce-S, uid-S, domain-S, uid-C, factotum-C
#	A->C:	Kc{nonce-S, uid-C, uid-S, Kn}, Ks{nonce-S, uid-C, uid-S, K-n}
#	C->S:	Ks{nonce-S, uid-C, uid-S, K-n}, Kn{nonce-S, counter}
#	S->C:	Kn{nonce-C, counter}

#asserts that uid-S and uid-C share new secret Kn
#increment the counter to reuse the ticket.

p9sk1client(io: ref IO, udom: string): string
{

	#	C->S:	nonce-C
	cchal := array[CHALLEN] of byte;
	memrandom(cchal, CHALLEN);
	if(io.write(cchal, len cchal) != len cchal)
		return sys->sprint("p9sk1: can't write cchal: %r");

	#	S->C:	nonce-S, uid-S, domain-S
	trbuf := io.readn(TICKREQLEN);
	if(trbuf == nil)
		return sys->sprint("p9sk1: can't read ticketreq: %r");

	(nil, tr) := Ticketreq.unpack(trbuf);
	if(tr == nil)
		return "p9sk1: can't unpack ticket request";
	if(Debug)
		sys->print("ticketreq: type=%d authid=%q authdom=%q chal= hostid=%q uid=%q\n",
			tr.rtype, tr.authid, tr.authdom, tr.hostid, tr.uid);

	(mykey, diag) := io.findkey(nil, sys->sprint("dom=%q proto=p9sk1 user? !password?", udom));
	if(mykey == nil)
		return "can't find key: "+diag;
	ukey: array of byte;
	if((a := authio->lookattrval(mykey.secrets, "!hex")) != nil){
		ukey = base16->dec(a);
		if(len ukey != DESKEYLEN)
			return "p9sk1: invalid !hex key";
	}else	if((a = authio->lookattrval(mykey.secrets, "!password")) != nil)
		ukey = auth9->passtokey(a);
	else
		return "no !password (or !hex) in key";

	#	A->C:	Kc{nonce-S, uid-C, uid-S, Kn}, Ks{nonce-S, uid-C, uid-S, K-n}
	user := authio->lookattrval(mykey.attrs, "user");
	if(user == nil)
		user = authio->user();	# shouldn't happen
	tr.rtype = Auth9->AuthTreq;
	tr.hostid = user;
	tr.uid = tr.hostid;	# not speaking for anyone else
	(tick, serverbits) := getastickets(tr, ukey);
	if(tick == nil)
		return sys->sprint("p9sk1: getasticket failed: %r");
	if(tick.num != Auth9->AuthTc)
		return "p9sk1: getasticket: failed: wrong key?";
	if(Debug)
		sys->print("ticket: num=%d chal= cuid=%q suid=%q key=\n", tick.num, tick.cuid, tick.suid);

	#	C->S:	Ks{nonce-S, uid-C, uid-S, K-n}, Kn{nonce-S, counter}
	ar := ref Authenticator;
	ar.num = Auth9->AuthAc;
	ar.chal = tick.chal;
	ar.id = 0;
	obuf := array[TICKETLEN+AUTHENTLEN] of byte;
	obuf[0:] = serverbits;
	obuf[TICKETLEN:] = ar.pack(tick.key);
	if(io.write(obuf, len obuf) != len obuf)
		return "p9sk1: error writing authenticator: %r";

	#	S->C:	Kn{nonce-C, counter}
	sbuf := io.readn(AUTHENTLEN);
	if(sbuf == nil)
		return sys->sprint("p9sk1: can't read server's authenticator: %r");
	(nil, ar) = Authenticator.unpack(sbuf, tick.key);
	if(ar.num != Auth9->AuthAs || !eqbytes(ar.chal, cchal) || ar.id != 0)
		return "invalid authenticator from server";

	ai := ref Authinfo(tick.cuid, tick.suid, nil, auth9->des56to64(tick.key));
	io.done(ai);

	return nil;
}

getastickets(tr: ref Ticketreq, key: array of byte): (ref Ticket, array of byte)
{
	afd := authdial(nil, tr.authdom);
	if(afd == nil)
		return (nil, nil);
	return auth9->_asgetticket(afd, tr, key);
}

#
# where to put the following functions?
#

csgetvalue(netroot: string, keytag: string, keyval: string, needtag: string): string
{
	cs := "/net/cs";
	if(netroot != nil)
		cs = netroot+"/cs";
	fd := sys->open(cs, Sys->ORDWR);	# TO DO: choice of root
	if(fd == nil)
		return nil;
	if(sys->fprint(fd, "!%s=%s %s=*", keytag, keyval, needtag) < 0)
		return nil;
	sys->seek(fd, big 0, 0);
	buf := array[1024] of byte;
	while((n := sys->read(fd, buf, len buf)) > 0){
		al := authio->parseline(string buf[0:n]);	# assume the conventions match factotum's
		for(; al != nil; al = tl al)
			if((hd al).name == needtag)
				return (hd al).val;
	}
	return nil;
}

authdial(netroot: string, dom: string): ref Sys->FD
{
	p: string;
	if(dom != nil){
		# look up an auth server in an authentication domain
		p = csgetvalue(netroot, "authdom", dom, "auth");

		# if that didn't work, just try the IP domain
		if(p == nil)
			p = csgetvalue(netroot, "dom", dom, "auth");
		if(p == nil)
			p = "$auth";	# temporary ...
		if(p == nil){
			sys->werrstr("no auth server found for "+dom);
			return nil;
		}
	}else
		p = "$auth";	# look for one relative to my machine
	(nil, conn) := sys->dial(netmkaddr(p, netroot, "ticket"), nil);
	return conn.dfd;
}

keycheck(nil: ref Authio->Key): string
{
	return nil;
}
