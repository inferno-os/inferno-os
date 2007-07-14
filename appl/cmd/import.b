implement Import;

include "sys.m";
	sys: Sys;

include "draw.m";
include "keyring.m";
include "security.m";
include "factotum.m";
include "encoding.m";
include "arg.m";

Import: module
{
	init:	 fn(nil: ref Draw->Context, nil: list of string);
};

factotumfile := "/mnt/factotum/rpc";

fail(status, msg: string)
{
	sys->fprint(sys->fildes(2), "import: %s\n", msg);
	raise "fail:"+status;
}

nomod(mod: string)
{
	fail("load", sys->sprint("can't load %s: %r", mod));
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	factotum := load Factotum Factotum->PATH;
	if(factotum == nil)
		nomod(Factotum->PATH);
	factotum->init();

	arg := load Arg Arg->PATH;
	if(arg == nil)
		nomod(Arg->PATH);

	arg->init(args);
	arg->setusage("import [-a|-b] [-c] [-e enc digest] host file [localfile]");
	flags := 0;
	cryptalg := "";	# will be rc4_256 sha1
	keyspec := "";
	while((o := arg->opt()) != 0)
		case o {
		'a' =>
			flags |= Sys->MAFTER;
		'b' =>
			flags |= Sys->MBEFORE;
		'c' =>
			flags |= Sys->MCREATE;
		'e' =>
			cryptalg = arg->earg();
			if(cryptalg == "clear")
				cryptalg = nil;
		'k' =>
			keyspec = arg->earg();
		'9' =>
			;
		*   =>
			arg->usage();
		}
	args = arg->argv();
	if(len args != 2 && len args != 3)
		arg->usage();
	arg = nil;
	addr := hd args;
	file := hd tl args;
	mountpt := file;
	if(len args > 2)
		mountpt = hd tl tl args;

	sys->pctl(Sys->FORKFD, nil);

	facfd := sys->open(factotumfile, Sys->ORDWR);
	if(facfd == nil)
		fail("factotum", sys->sprint("can't open %s: %r", factotumfile));

	dest := netmkaddr(addr, "net", "exportfs");
	(ok, c) := sys->dial(dest, nil);
	if(ok < 0)
		fail("dial failed",  sys->sprint("can't dial %s: %r", dest));
	ai := factotum->proxy(c.dfd, facfd, "proto=p9any role=client "+keyspec);
	if(ai == nil)
		fail("auth", sys->sprint("can't authenticate import: %r"));
	if(sys->fprint(c.dfd, "%s", file) < 0)
		fail("import", sys->sprint("can't write to remote: %r"));
	buf := array[256] of byte;
	if((n := sys->read(c.dfd, buf, len buf)) != 2 || buf[0] != byte 'O' || buf[1] != byte 'K'){
		if(n >= 4)
			sys->werrstr("bad remote tree: "+string buf[0:n]);
		fail("import", sys->sprint("import %s %s: %r", addr, file));
	}
	if(cryptalg != nil){
		if(ai.secret == nil)
			fail("import", "factotum didn't establish shared secret");
		random := load Random Random->PATH;
		if(random == nil)
			nomod(Random->PATH);
		kr := load Keyring Keyring->PATH;
		if(kr == nil)
			nomod(Keyring->PATH);
		base64 := load Encoding Encoding->BASE64PATH;
		if(base64 == nil)
			nomod(Encoding->BASE64PATH);
		if(sys->fprint(c.dfd, "impo nofilter ssl\n") < 0)
			fail("import", sys->sprint("can't write to remote: %r"));
		key := array[16] of byte;	# myrand[4] secret[8] hisrand[4]
		key[0:] = random->randombuf(Random->ReallyRandom, 4);
		ns := len ai.secret;
		if(ns > 8)
			ns = 8;
		key[4:] = ai.secret[0:ns];
		if(sys->write(c.dfd, key, 4) != 4)
			fail("import", sys->sprint("can't write key to remote: %r"));
		if(sys->readn(c.dfd, key[12:], 4) != 4)
			fail("import", sys->sprint("can't read remote key: %r"));
		digest := array[Keyring->SHA1dlen] of byte;
		kr->sha1(key, len key, digest, nil);
		err: string;
		(c.dfd, err) = pushssl(c.dfd, base64->dec(S(digest[0:10])), base64->dec(S(digest[10:20])), cryptalg);
		if(err != nil)
			fail("import", sys->sprint("can't push security layer: %s", err));
	}else
		if(sys->fprint(c.dfd, "impo nofilter clear\n") < 0)
			fail("import", sys->sprint("can't write to remote: %r"));
	afd := sys->fauth(c.dfd, "");
	if(afd != nil)
		factotum->proxy(afd, facfd, "proto=p9any role=client");
	if(sys->mount(c.dfd, afd, mountpt, flags, "") < 0)
		fail("mount failed", sys->sprint("import %s %s: mount failed: %r", addr, file));
}

S(a: array of byte): string
{
	s := "";
	for(i:=0; i<len a; i++)
		s += sys->sprint("%.2ux", int a[i]);
	return s;
}

pushssl(fd: ref Sys->FD, secretin, secretout: array of byte, alg: string): (ref Sys->FD, string)
{
	ssl := load SSL SSL->PATH;
	if(ssl == nil)
		nomod(SSL->PATH);

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

netmkaddr(addr, net, svc: string): string
{
	if(net == nil)
		net = "net";
	(n, nil) := sys->tokenize(addr, "!");
	if(n <= 1){
		if(svc== nil)
			return sys->sprint("%s!%s", net, addr);
		return sys->sprint("%s!%s!%s", net, addr, svc);
	}
	if(svc == nil || n > 2)
		return addr;
	return sys->sprint("%s!%s", addr, svc);
}
