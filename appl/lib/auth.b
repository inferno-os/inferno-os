# Inferno authentication protocol
implement Auth;

include "sys.m";
	sys: Sys;

include "keyring.m";

include "security.m";
	ssl: SSL;

init(): string
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	return nil;	
}

server(algs: list of string, ai: ref Keyring->Authinfo, fd: ref Sys->FD, setid: int): (ref Sys->FD, string)
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	kr := load Keyring Keyring->PATH;
	if(kr == nil)
		return (nil, sys->sprint("%r"));

	# mutual authentication
	(id_or_err, secret) := kr->auth(fd, ai, setid); 

	if(secret == nil){
		if(ai == nil && id_or_err == "no authentication information")
			id_or_err = "no server certificate";
		return (nil, id_or_err);
	}
	if(0)
		sys->fprint(sys->fildes(2), "secret is %s\n", dump(secret));

	# have got a secret, get algorithm from client
	# check if the client algorithm is in the server algorithm list
	# client algorithm ::= ident (' ' ident)*
	# where ident is defined by ssl(3)
	algbuf := string kr->getmsg(fd);
	if(algbuf == nil)
		return (nil, sys->sprint("can't read client ssl algorithm: %r"));
	alg := "";
	(nil, calgs) := sys->tokenize(algbuf, " /");
	for(; calgs != nil; calgs = tl calgs){
		calg := hd calgs;
		if(algs != nil){	# otherwise we suck it and see
			for(sl := algs; sl != nil; sl = tl sl)
				if(hd sl == calg)
					break;
			if(sl == nil)
				return (nil, "unsupported client algorithm: " + calg);
		}
		alg += calg + " ";
	}
	if(alg != nil)
		alg = alg[0:len alg - 1];

	# don't push ssl if server supports nossl
	if(alg == nil || alg == "none")
		return (fd, id_or_err);

	# push ssl and turn on algorithms
	ssl = load SSL SSL->PATH;
	if(ssl == nil)
		return (nil, sys->sprint("can't load ssl: %r"));
	(c, err) := pushssl(fd, secret, secret, alg);
	if(c == nil)
		return (nil, "push ssl: " + err);
	return (c, id_or_err);
}

client(alg: string, ai: ref Keyring->Authinfo, fd: ref Sys->FD): (ref Sys->FD, string)
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	kr := load Keyring Keyring->PATH;
	if(kr == nil)
		return (nil, sys->sprint("%r"));

	if(alg == nil)
		alg = "none";

	# mutual authentication
	(id_or_err, secret) := kr->auth(fd, ai, 0);
	if(secret == nil)
		return (nil, id_or_err);

	# send algorithm
	buf := array of byte alg;
	if(kr->sendmsg(fd, buf, len buf) < 0)
		return (nil, sys->sprint("can't send ssl algorithm: %r"));

	# don't push ssl if server supports no ssl connection
	if(alg == "none")
		return (fd, id_or_err);

	# push ssl and turn on algorithm
	ssl = load SSL SSL->PATH;
	if(ssl == nil)
		return (nil, sys->sprint("can't load ssl: %r"));
	(c, err) := pushssl(fd, secret, secret, alg);
	if(c == nil)
		return (nil, "push ssl: " + err);
	return (c, id_or_err);
}

auth(ai: ref Keyring->Authinfo, keyspec: string, alg: string, fd: ref Sys->FD): (ref Sys->FD, ref Keyring->Authinfo, string)
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	kr := load Keyring Keyring->PATH;
	if(kr == nil)
		return (nil, nil, sys->sprint("can't load %s: %r", Keyring->PATH));
	if(alg == nil)
		alg = "none";
	if(ai == nil && keyspec != nil){
		ai = key(keyspec);
		if(ai == nil)
			return (nil, nil, sys->sprint("can't obtain key: %r"));
	}

	# mutual authentication
	(id_or_err, secret) := kr->auth(fd, ai, 0);
	if(secret == nil)
		return (nil, nil, id_or_err);

	# send algorithm
	buf := array of byte alg;
	if(kr->sendmsg(fd, buf, len buf) < 0)
		return (nil, nil, sys->sprint("can't send ssl algorithm: %r"));

	if(0){		# TO DO
		hisalg := string kr->getmsg(fd);
		if(hisalg == nil)
			return (nil, nil, sys->sprint("can't get remote algorithm: %r"));
		# TO DO: compare the two, sort it out if they aren't equal
	}

	# don't push ssl if server supports no ssl connection
	if(alg == "none")
		return (fd, nil, id_or_err);

	# push ssl and turn on algorithm
	ssl = load SSL SSL->PATH;
	if(ssl == nil)
		return (nil, nil, sys->sprint("can't load ssl: %r"));
	(c, err) := pushssl(fd, secret, secret, alg);
	if(c == nil)
		return (nil, nil, "push ssl: " + err);
	return (c, nil, id_or_err);
}

dump(b: array of byte): string
{
	s := "";
	for(i := 0; i < len b; i++)
		s += sys->sprint("%.2ux", int b[i]);
	return s;
}

# push an SSLv2 Record Layer onto the fd
pushssl(fd: ref Sys->FD, secretin, secretout: array of byte, alg: string): (ref Sys->FD, string)
{
	(err, c) := ssl->connect(fd);
	if(err != nil)
		return (nil, "can't connect ssl: " + err);

	err = ssl->secret(c, secretin, secretout);
	if(err != nil)
		return (nil, "can't write secret: " + err);

	if(sys->fprint(c.cfd, "alg %s", alg) < 0)
		return (nil, sys->sprint("can't push algorithm %s: %r", alg));

	return (c.dfd, nil);
}

key(keyspec: string): ref Keyring->Authinfo
{
	f := keyfile(keyspec);
	if(f == nil)
		return nil;
	kr := load Keyring Keyring->PATH;
	if(kr == nil){
		sys->werrstr(sys->sprint("can't load %s: %r", Keyring->PATH));
		return nil;
	}
	return kr->readauthinfo(f);
}

#
# look for key in old style keyring directory;
# closest match to [net!]addr[!svc]
#

keyfile(keyspec: string): string
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	al := parseattr(keyspec);
	keyname := get(al, "key");
	if(keyname != nil){
		# explicit keyname overrides rest of spec
		if(keyname[0] == '/' ||
		   len keyname > 2 && keyname[0:2]=="./" ||
		   len keyname > 3 && keyname[0:3]=="../")
			return keyname;	# don't add directory
		return keydir()+keyname;
	}
	net := "net";
	svc := get(al, "service");
	addr := get(al, "server");
	(nf, flds) := sys->tokenize(addr, "!");	# compatibility
	if(nf > 1){
		net = hd flds;
		addr = hd tl flds;
	}
	if(addr != nil)
		keyname = addr;
	else
		keyname = "default";
	kd := keydir();
	dom := get(al, "dom");
	if(dom != nil){
		if((cert := exists(kd+dom)) != nil)
			return cert;
	}
	if(keyname == "default")
		return kd+"default";
	if(net == "net")
		l := "net!" :: "tcp!" :: nil;
	else
		l = net+"!" :: nil;
	if(svc != nil){
		for(nl := l; nl != nil; nl = tl nl){
			cert := exists(kd+(hd nl)+keyname+"!"+svc);	# most specific
			if(cert != nil)
				return cert;
		}
	}
	for(nl := l; nl != nil; nl = tl nl){
		cert := exists(kd+(hd nl)+keyname);
		if(cert != nil)
			return cert;
	}
	cert := exists(kd+keyname);	# unadorned
	if(cert != nil)
		return cert;
	if(keyname != "default"){
		cert = exists(kd+"default");
		if(cert != nil)
			return cert;
	}
	return kd+keyname;
}

keydir(): string
{
	fd := sys->open("/dev/user", Sys->OREAD);
	if(fd == nil)
		return nil;
	b := array[Sys->NAMEMAX] of byte;
	nr := sys->read(fd, b, len b);
	if(nr <= 0){
		sys->werrstr("can't read /dev/user");
		return nil;
	}
	user := string b[0:nr];
	return "/usr/" + user + "/keyring/";
}

exists(f: string): string
{
	(ok, nil) := sys->stat(f);
	if(0)sys->fprint(sys->fildes(2), "exists: %q %d\n", f, ok>=0);
	if(ok >= 0)
		return f;
	return nil;
}

Aattr, Aval, Aquery: con iota;

Attr: adt {
	tag:	int;
	name:	string;
	val:	string;
};

parseattr(s: string): list of ref Attr
{
	(nil, fld) := sys->tokenize(s, " \t\n");	# should do quoting; later
	rfld := fld;
	for(fld = nil; rfld != nil; rfld = tl rfld)
		fld = (hd rfld) :: fld;
	attrs: list of ref Attr;
	for(; fld != nil; fld = tl fld){
		n := hd fld;
		a := "";
		tag := Aattr;
		for(i:=0; i<len n; i++)
			if(n[i] == '='){
				a = n[i+1:];
				n = n[0:i];
				tag = Aval;
			}
		if(len n == 0)
			continue;
		if(tag == Aattr && len n > 1 && n[len n-1] == '?'){
			tag = Aquery;
			n = n[0:len n-1];
		}
		attrs = ref Attr(tag, n, a) :: attrs;
	}
	return attrs;
}

get(al: list of ref Attr, n: string): string
{
	for(; al != nil; al = tl al)
		if((a := hd al).name == n && a.tag == Aval)
			return a.val;
	return nil;
}
