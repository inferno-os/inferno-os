implement Registries;

include "sys.m";
	sys: Sys;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "string.m";
	str: String;
include "keyring.m";
	keyring: Keyring;
include "dial.m";
	dial: Dial;
include "security.m";
	auth: Auth;
include "keyset.m";
	keyset: Keyset;
include "registries.m";

init()
{
	sys = load Sys Sys->PATH;
	bufio = checkload(load Bufio Bufio->PATH, Bufio->PATH);
	keyring = checkload(load Keyring Keyring->PATH, Keyring->PATH);
	str = checkload(load String String->PATH, String->PATH);
	keyset = checkload(load Keyset Keyset->PATH, Keyset->PATH);
	dial = checkload(load Dial Dial->PATH, Dial->PATH);
	auth = checkload(load Auth Auth->PATH, Auth->PATH);
	e := keyset->init();
	if(e != nil)
		raise sys->sprint("can't init Keyset: %s", e);
	e = auth->init();
	if(e != nil)
		raise sys->sprint("can't init Auth: %s", e);
}

checkload[T](x: T, s: string): T
{
	if(x == nil)
		raise sys->sprint("can't load %s: %r", s);
	return x;
}

Registry.new(dir: string): ref Registry
{
	if(dir == nil)
		dir = "/mnt/registry";
	r := ref Registry;
	r.dir = dir;
	r.indexfd = sys->open(dir + "/index", Sys->OREAD);
	if(r.indexfd == nil)
		return nil;
	return r;
}

Registry.connect(svc: ref Service, user, keydir: string): ref Registry
{
	# XXX broadcast for local registries here.
	if(svc == nil)
	#	svc = ref Service("net!$registry!registry", Attributes.new(("auth", "infpk1") :: nil));
		svc = ref Service("net!$registry!registry", Attributes.new(("auth", "none") :: nil));
	a := svc.attach(user, keydir);
	if(a == nil)
		return nil;
	if(sys->mount(a.fd, nil, "/mnt/registry", Sys->MREPL, nil) == -1){
		sys->werrstr(sys->sprint("mount failed: %r"));
		return nil;
	}
	return Registry.new("/mnt/registry");
}

Registry.services(r: self ref Registry): (list of ref Service, string)
{
	sys->seek(r.indexfd, big 0, Sys->SEEKSTART);
	iob := bufio->fopen(r.indexfd, Sys->OREAD);
	if(iob == nil)
		return (nil, sys->sprint("%r"));
	return (readservices(iob), nil);
}

Registry.find(r: self ref Registry, a: list of (string, string)): (list of ref Service, string)
{
	fd := sys->open(r.dir + "/find", Sys->ORDWR);	# could keep it open if it's a bottleneck
	if(fd == nil)
		return (nil, sys->sprint("%r"));
	s := "";
	if(a != nil){
		for(; a != nil; a = tl a){
			(n, v) := hd a;
			s += sys->sprint(" %q %q", n, v);
		}
		s = s[1:];
	}
	if(sys->fprint(fd, "%s", s) == -1)
		return (nil, sys->sprint("%r"));
	sys->seek(fd, big 0, Sys->SEEKSTART);
	iob := bufio->fopen(fd, Sys->OREAD);
	return (readservices(iob), nil);
}

readservices(iob: ref Iobuf): list of ref Service
{
	services: list of ref Service;
	while((s := qgets(iob, '\n')) != nil){
		toks := str->unquoted(s);
		if(toks == nil || len toks % 2 != 1)
			continue;
		svc := ref Service(hd toks, nil);
		attrs, rattrs: list of (string, string);
		for(toks = tl toks; toks != nil; toks = tl tl toks)
			rattrs = (hd toks, hd tl toks) :: rattrs;
		for(; rattrs != nil; rattrs = tl rattrs)
			attrs = hd rattrs :: attrs;
		svc.attrs = ref Attributes(attrs);
		services = svc :: services;
	}
	return rev(services);
}

rev[T](l: list of T): list of T
{
	rl: list of T;
	for(; l != nil; l = tl l)
		rl = hd l :: rl;
	return rl;
}

Registry.register(r: self ref Registry, addr: string, attrs: ref Attributes, persist: int): (ref Registered, string)
{
	fd := sys->open(r.dir + "/new", Sys->OWRITE);
	if(fd == nil)
		return (nil, sys->sprint("%r"));
	s := sys->sprint("%q", addr);
	for(a := attrs.attrs; a != nil; a = tl a)
		s += sys->sprint(" %q %q", (hd a).t0, (hd a).t1);
	if(persist)
		s += " persist 1";
	if(sys->fprint(fd, "%s", s) == -1)
		return (nil, sys->sprint("%r"));
	return (ref Registered(addr, r, fd), nil);
}

Registry.unregister(r: self ref Registry, addr: string): string
{
	if(sys->remove(r.dir + "/" + addr) == -1)
		return sys->sprint("%r");
	return nil;
}

Attributes.new(attrs: list of (string, string)): ref Attributes
{
	return ref Attributes(attrs);
}

Attributes.set(a: self ref Attributes, attr, val: string)
{
	for(al := a.attrs; al != nil; al = tl al)
		if((hd al).t0 == attr)
			break;
	if(al == nil){
		a.attrs = (attr, val) :: a.attrs;
		return;
	}
	attrs := (attr, val) :: tl al;
	for(al = a.attrs; al != nil; al = tl al){
		if((hd al).t0 == attr)
			break;
		attrs = hd al :: attrs;
	}
	a.attrs = attrs;
}

Attributes.get(a: self ref Attributes, attr: string): string
{
	for(al := a.attrs; al != nil; al = tl al)
		if((hd al).t0 == attr)
			return (hd al).t1;
	return nil;
}

qgets(iob: ref Iobuf, eoc: int): string
{
	inq := 0;
	s := "";
	while((c := iob.getc()) >= 0){
		s[len s] = c;
		if(inq){
			if(c == '\''){
				c = iob.getc();
				if(c == '\'')
					s[len s] = c;
				else{
					iob.ungetc();
					inq = 0;
				}
			}
		}else{
			if(c == eoc)
				return s;
			if(c == '\'')
				inq = 1;
		}
	}
	return s;
}

Service.attach(svc: self ref Service, localuser, keydir: string): ref Attached
{
	# attributes used:
	# 	auth			type of authentication to perform (auth, none)
	#	auth.crypt		type of encryption to push (as accepted by ssl(3)'s "alg" operation)
	#	auth.signer	hash of service's certificate's signer's public key

	c := dial->dial(svc.addr, nil);
	if(c == nil){
		sys->werrstr(sys->sprint("cannot dial: %r"));
		return nil;
	}
	attached := ref Attached;
	authkind := svc.attrs.get("auth");
	case authkind {
	"auth" or		# old
	"infpk1" =>
		cryptalg := svc.attrs.get("auth.crypt");
		if(cryptalg == nil)
			cryptalg = "none";
		ca := svc.attrs.get("auth.signer");
		kf: string;
		if(ca != nil){
			(kfl, err) := keyset->keysforsigner(nil, ca, nil, keydir);
			if(kfl == nil){
				s := "no matching keys found";
				if(err != nil)
					s += ": "+err;
				sys->werrstr(s);
				return nil;
			}
			if(localuser == nil)
				kf = (hd kfl).t0;
			else{
				for(; kfl != nil; kfl = tl kfl)
					if((hd kfl).t1 == localuser)
						break;
				if(kfl == nil){
					sys->werrstr("no matching user found");
					return nil;
				}
				kf = (hd kfl).t0;
			}
		} else {
			user := readname("/dev/user");
			if(user == nil)
				kf = "/lib/keyring/default";
			else
				kf = "/usr/" + user + "/keyring/default";
		}
		info := keyring->readauthinfo(kf);
		if(info == nil){
			sys->werrstr(sys->sprint("cannot read key: %r"));
			return nil;
		}
		(fd, ue) := auth->client(cryptalg, info, c.dfd);
		if(fd == nil){
			sys->werrstr(sys->sprint("cannot authenticate: %r"));
			return nil;
		}
		attached.signerpkhash = keyset->pkhash(keyring->pktostr(info.spk));
		attached.localuser = info.mypk.owner;
		attached.remoteuser = ue;
		attached.fd = fd;
	"" or
	"none" =>
		attached.fd = c.dfd;
	* =>
		sys->werrstr(sys->sprint("unknown authentication type %q", authkind));
		return nil;
	}
	return attached;
}

readname(s: string): string
{
	fd := sys->open(s, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	return string buf[0:n];
}
