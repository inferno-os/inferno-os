implement Newns;
#
# Build a new namespace from a file
#
#	new	create a new namespace from current directory (use cd)
#	fork	split the namespace before modification
#	nodev	disallow device attaches
#	bind	[-abrci] from to
#	mount	[-abrci9] [net!]machine[!svc] to [spec]
#	import [-abrci9] [net!]machine[!svc] [remotedir] dir
#	unmount	[-i] [from] to
#   	cd	directory
#
#	-i to bind/mount/unmount means continue in the face of errors
#
include "sys.m";
	sys: Sys;
	FD, FileIO: import Sys;
	stderr: ref FD;

include "draw.m";

include "bufio.m";
	bio: Bufio;
	Iobuf: import bio;

include "dial.m";
	dial: Dial;
	Connection: import dial;

include "newns.m";

#include "sh.m";

include "keyring.m";
	kr: Keyring;

include "security.m";
	au: Auth;

include "factotum.m";

include "arg.m";
	arg: Arg;

include "string.m";
	str: String;

newns(user: string, file: string): string
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	stderr = sys->fildes(2);

	# Could do some authentication here, and bail if no good FIXME
	if(user == nil)
		;
	bio = load Bufio Bufio->PATH;
	if(bio == nil)
		return sys->sprint("cannot load %s: %r", Bufio->PATH);

	arg = load Arg Arg->PATH;
	if (arg == nil)
		return sys->sprint("cannot load %s: %r", Arg->PATH);

	au = load Auth Auth->PATH;
	if(au == nil)
		return sys->sprint("cannot load %s: %r", Auth->PATH);
	err := au->init();
	if(err != nil)
		return "Auth->init: "+err;

	str = load String String->PATH;		# no check, because we'll live without it

	if(file == nil){
		file = "namespace";
		if(sys->stat(file).t0 < 0)
			file = "/lib/namespace";
	}

	mfp := bio->open(file, bio->OREAD);
	if(mfp==nil)
      		return sys->sprint("cannot open %q: %r", file);

	if(0 && user != nil){
		sys->pctl(Sys->FORKENV, nil);
		setenv("user", user);
		setenv("home", "/usr/"+user);
	}

	facfd := sys->open("/mnt/factotum/rpc", Sys->ORDWR);
	return nsfile(mfp, facfd);
}

nsfile(b: ref Iobuf, facfd: ref Sys->FD): string
{
	e := "";
	while((l := b.gets('\n')) != nil){
		if(str != nil)
			slist := str->unquoted(l);
		else
			(nil, slist) = sys->tokenize(l, " \t\n\r");	# old way, in absence of String
		if(slist == nil)
			continue;
		e = nsop(expand(slist), facfd);
		if(e != "")
			break;
   	}
	return e;
}

expand(l: list of string): list of string
{
	nl: list of string;
	for(; l != nil; l = tl l){
		s := hd l;
		for(i := 0; i < len s; i++)
			if(s[i] == '$'){
				for(j := i+1; j < len s; j++)
					if((c := s[j]) == '.' || c == '/' || c == '$')
						break;
				if(j > i+1){
					(ok, v) := getenv(s[i+1:j]);
					if(!ok)
						return nil;
					s = s[0:i] + v + s[j:];
					i = i + len v;
				}
			}
		nl = s :: nl;
	}
	l = nil;
	for(; nl != nil; nl = tl nl)
		l = hd nl :: l;
	return l;
}

nsop(argv: list of string, facfd: ref Sys->FD): string
{
	# ignore comments 
	if(argv == nil || (hd argv)[0] == '#')
		return nil;
 
	e := "";
	c := 0;
	cmdstr := hd argv;
	case cmdstr {
	"." =>
		if(tl argv == nil)
			return ".: needs a filename";
		nsf := hd tl argv;
		mfp := bio->open(nsf, bio->OREAD);
		if(mfp==nil)
      			return sys->sprint("can't open %q for read %r", nsf);
		e = nsfile(mfp, facfd);
	"new" =>
		c = Sys->NEWNS | Sys->FORKENV;
	"clear" =>
		if(sys->pctl(Sys->FORKNS, nil) < 0 ||
		   sys->bind("#/", "/", Sys->MREPL) < 0 ||
		   sys->chdir("/") < 0 ||
		   sys->pctl(Sys->NEWNS, nil) < 0)
			return sys->sprint("%r");
		return nil;
	"fork"  =>
		c = Sys->FORKNS;
	"nodev" =>
		c = Sys->NODEVS;
	"bind" =>
		e = bind(argv);
	"mount" =>
		e = mount(argv, facfd);
	"unmount" =>
		e = unmount(argv);
	"import" =>
		e = import9(argv, facfd);
   	"cd" =>
   		if(len argv != 2)
			return "cd: must have one argument";   
		if(sys->chdir(hd tl argv) < 0)
			return sys->sprint("%r");
	* =>
      		e = "invalid namespace command";
	}
	if(c != 0) {
		if(sys->pctl(c, nil) < 0)
			return sys->sprint("%r");
	}
	return e;
}

Moptres: adt {
	argv: list of string;
	flags: int;
	alg: string;
	keyfile: string;
	ignore: int;
	use9: int;
};

mopt(argv: list of string): (ref Moptres, string)
{
	r := ref Moptres(nil, 0, "none", nil, 0, 0);

	arg->init(argv);
	while ((opt := arg->opt()) != 0) {
		case opt {
		'i' => r.ignore = 1;
		'a' => r.flags |= sys->MAFTER;
		'b' => r.flags |= sys->MBEFORE;
		'c' => r.flags |= sys->MCREATE;
		'r' => r.flags |= sys->MREPL;
		'k' =>
			if((r.keyfile = arg->arg()) == nil)
				return (nil, "mount: missing arg to -k option");
		'C' =>
			if((r.alg = arg->arg()) == nil)
				return (nil, "mount: missing arg to -C option");
		'9' =>
			r.use9 = 1;
		 *  =>
			return (nil, sys->sprint("mount: bad option -%c", opt));
		}
	}
	if((r.flags & (Sys->MAFTER|Sys->MBEFORE)) == 0)
		r.flags |= Sys->MREPL;

	r.argv = arg->argv();
	return (r, nil);
}

bind(argv: list of string): string
{
	(r, err) := mopt(argv);
	if(err != nil)
		return err;

	if(len r.argv < 2)
		return "bind: too few args";

	from := hd r.argv;
	r.argv = tl r.argv;
	todir := hd r.argv;
	if(sys->bind(from, todir, r.flags) < 0)
		return ig(r, sys->sprint("bind %s %s: %r", from, todir));

	return nil;
}

mount(argv: list of string, facfd: ref Sys->FD): string
{
	fd: ref Sys->FD;

	(r, err) := mopt(argv);
	if(err != nil)
		return err;

	if(len r.argv < 2)
		return ig(r, "mount: too few args");

	if(dial == nil){
		dial = load Dial Dial->PATH;
		if(dial == nil)
			return ig(r, "mount: can't load Dial");
	}

	addr := hd r.argv;
	r.argv = tl r.argv;
	dest := dial->netmkaddr(addr, "net", "styx");
	dir := hd r.argv;
	r.argv = tl r.argv;
	if(r.argv != nil)
		spec := hd r.argv;

	c := dial->dial(dest, nil);
	if(c == nil)
		return ig(r, sys->sprint("dial: %s: %r", dest));
	
	if(r.use9){
		factotum := load Factotum Factotum->PATH;
		if(factotum == nil)
			return ig(r, sys->sprint("cannot load %s: %r", Factotum->PATH));
		factotum->init();
		afd := sys->fauth(fd, spec);
		if(afd != nil)
			factotum->proxy(afd, facfd, "proto=p9any role=client");	# ignore result; if it fails, mount will fail
		if(sys->mount(fd, afd, dir, r.flags, spec) < 0)
			return ig(r, sys->sprint("mount %q %q: %r", addr, dir));
		return nil;
	}

	user := user();
	kd := "/usr/" + user + "/keyring/";
	cert: string;
	if (r.keyfile != nil) {
		cert = r.keyfile;
		if (cert[0] != '/')
			cert = kd + cert;
		if(sys->stat(cert).t0 < 0)
			return ig(r, sys->sprint("cannot find certificate %q: %r", cert));
	} else {
		cert = kd + addr;
		if(sys->stat(cert).t0 < 0)
			cert = kd + "default";
	}
	ai := kr->readauthinfo(cert);
	if(ai == nil)
		return ig(r, sys->sprint("cannot read certificate from %q: %r", cert));

	err = au->init();
	if (err != nil)
		return ig(r, sys->sprint("auth->init: %r"));
	(fd, err) = au->client(r.alg, ai, c.dfd);
	if(fd == nil)
		return ig(r, sys->sprint("auth: %r"));

	if(sys->mount(fd, nil, dir, r.flags, spec) < 0)
		return ig(r, sys->sprint("mount %q %q: %r", addr, dir));

	return nil;
}

import9(argv: list of string, facfd: ref Sys->FD): string
{
	(r, err) := mopt(argv);
	if(err != nil)
		return err;

	if(len r.argv < 2)
		return "import: too few args";
	if(facfd == nil)
		return ig(r, "import: no factotum");
	factotum := load Factotum Factotum->PATH;
	if(factotum == nil)
		return ig(r, sys->sprint("cannot load %s: %r", Factotum->PATH));
	factotum->init();
	addr := hd r.argv;
	r.argv = tl r.argv;
	rdir := hd r.argv;
	r.argv = tl r.argv;
	dir := rdir;
	if(r.argv != nil)
		dir = hd r.argv;

	if(dial == nil){
		dial = load Dial Dial->PATH;
		if(dial == nil)
			return ig(r, "import: can't load Dial");
	}

	dest := dial->netmkaddr(addr, "net", "17007");	# exportfs; might not be in inferno's ndb yet
	c := dial->dial(dest, nil);
	if(c == nil)
		return ig(r, sys->sprint("import: %s: %r", dest));
	fd := c.dfd;
	if(factotum->proxy(fd, facfd, "proto=p9any role=client") == nil)
		return ig(r, sys->sprint("import: %s: %r", dest));
	if(sys->fprint(fd, "%s", rdir) < 0)
		return ig(r, sys->sprint("import: %s: %r", dest));
	buf := array[256] of byte;
	if((n := sys->read(fd, buf, len buf)) != 2 || buf[0] != byte 'O' || buf[1] != byte 'K'){
		if(n >= 4)
			sys->werrstr(string buf[0:n]);
		return ig(r, sys->sprint("import: %s: %r", dest));
	}
	# TO DO: new style: impo aan|nofilter clear|ssl|tls\n
	afd := sys->fauth(fd, "");
	if(afd != nil)
		factotum->proxy(afd, facfd, "proto=p9any role=client");
	if(sys->mount(fd, afd, dir, r.flags, "") < 0)
		return ig(r, sys->sprint("import %q %q: %r", addr, dir));
	return nil;
}

unmount(argv: list of string): string
{
	(r, err) := mopt(argv);
	if(err != nil)
		return err;

	from, tu: string;
	case len r.argv {
	* =>
		return "unmount: takes 1 or 2 args";
	1 =>
		from = nil;
		tu = hd r.argv;
	2 =>
		from = hd r.argv;
		tu = hd tl r.argv;
	}

	if(sys->unmount(from, tu) < 0)
		return ig(r, sys->sprint("unmount: %r"));

	return nil;
}

ig(r: ref Moptres, e: string): string
{
	if(r.ignore)
		return nil;
	return e;
}

user(): string
{
	sys = load Sys Sys->PATH;

	fd := sys->open("/dev/user", sys->OREAD);
	if(fd == nil)
		return "";

	buf := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return "";

	return string buf[0:n];	
}

getenv(name: string): (int, string)
{
	fd := sys->open("#e/"+name, Sys->OREAD);
	if(fd == nil)
		return (0, nil);
	b := array[256] of byte;
	n := sys->read(fd, b, len b);
	if(n <= 0)
		return (1, "");
	for(i := 0; i < n; i++)
		if(b[i] == byte 0 || b[i] == byte '\n')
			break;
	return (1, string b[0:i]);
}
	
setenv(name: string, val: string)
{
	fd := sys->create("#e/"+name, Sys->OWRITE, 8r664);
	if(fd != nil)
		sys->fprint(fd, "%s", val);
}

newuser(user: string, cap: string, nsfile: string): string
{
	if(cap == nil)
		return "no capability";

	sys = load Sys Sys->PATH;
	fd := sys->open("#¤/capuse", Sys->OWRITE);
	if(fd == nil)
		return sys->sprint("opening #¤/capuse: %r");

	b := array of byte cap;
	if(sys->write(fd, b, len b) < 0)
		return sys->sprint("writing %s to #¤/capuse: %r", cap);

	# mount factotum as new user (probably unhelpful if not factotum owner)
	sys->unmount(nil, "/mnt/factotum");
	sys->bind("#sfactotum", "/mnt/factotum", Sys->MREPL);

	return newns(user, nsfile);
}
